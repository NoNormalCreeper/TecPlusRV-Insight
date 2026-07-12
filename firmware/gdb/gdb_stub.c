// DarkRISCV cooperative GDB Remote Serial Protocol stub。
#include "drivers/uart.h"
#include "gdb/gdb_packet.h"
#include "runtime/trap.h"

#define GDB_REGISTER_COUNT 33u
#define GDB_REGISTER_HEX_SIZE (GDB_REGISTER_COUNT * 8u)
#define GDB_BRAM_BASE 0x00000000u
#define GDB_BRAM_SIZE 0x00010000u
#define GDB_SDRAM_BASE 0x80000000u
#define GDB_SDRAM_SIZE 0x02000000u

static struct gdb_packet_parser packet_parser;
static char reply_buffer[GDB_PACKET_CAPACITY + 1u];
static char last_reply[GDB_PACKET_CAPACITY + 1u];
static unsigned int last_reply_length;
static unsigned int stopped_pc;
static unsigned int resume_pc_explicit;
static unsigned int debugger_attached;

static const char hex_digits[] = "0123456789abcdef";

static int text_equal(const char *left, const char *right)
{
    while (*left != '\0' && *right != '\0') {
        if (*left++ != *right++)
            return 0;
    }
    return *left == *right;
}

static int text_starts_with(const char *text, const char *prefix)
{
    while (*prefix != '\0') {
        if (*text++ != *prefix++)
            return 0;
    }
    return 1;
}

static unsigned int text_length(const char *text)
{
    unsigned int length = 0u;
    while (text[length] != '\0')
        length++;
    return length;
}

static void send_packet_bytes(const char *payload, unsigned int length)
{
    unsigned int checksum = 0u;
    unsigned int index;

    uart_putc('$');
    for (index = 0u; index < length; index++) {
        unsigned char byte = (unsigned char)payload[index];
        uart_putc((char)byte);
        checksum = (checksum + byte) & 0xffu;
    }
    uart_putc('#');
    uart_putc(hex_digits[checksum >> 4]);
    uart_putc(hex_digits[checksum & 0xfu]);
}

static void send_reply_length(const char *payload, unsigned int length)
{
    unsigned int index;

    for (index = 0u; index < length; index++)
        last_reply[index] = payload[index];
    last_reply[length] = '\0';
    last_reply_length = length;
    send_packet_bytes(last_reply, last_reply_length);
}

static void send_reply(const char *payload)
{
    send_reply_length(payload, text_length(payload));
}

static void resend_last_reply(void)
{
    send_packet_bytes(last_reply, last_reply_length);
}

static const char *stop_reply(unsigned int mcause)
{
    switch (mcause) {
    case 2u:
        return "S04";
    case 3u:
        return "S05";
    case 0u:
    case 1u:
    case 4u:
    case 5u:
    case 6u:
    case 7u:
        return "S0b";
    default:
        return "S05";
    }
}

static void encode_registers(const struct trap_frame *frame)
{
    char encoded[9];
    unsigned int register_index;
    unsigned int digit_index;
    unsigned int output_index = 0u;

    for (register_index = 0u; register_index < 32u; register_index++) {
        unsigned int value = register_index == 0u ? 0u : frame->x[register_index];
        gdb_encode_u32_le(encoded, value);
        for (digit_index = 0u; digit_index < 8u; digit_index++)
            reply_buffer[output_index++] = encoded[digit_index];
    }
    gdb_encode_u32_le(encoded, frame->mepc);
    for (digit_index = 0u; digit_index < 8u; digit_index++)
        reply_buffer[output_index++] = encoded[digit_index];
    reply_buffer[output_index] = '\0';
}

static int decode_registers(struct trap_frame *frame, const char *payload,
                            unsigned int length)
{
    unsigned int decoded[GDB_REGISTER_COUNT];
    unsigned int register_index;

    if (length != 1u + GDB_REGISTER_HEX_SIZE)
        return 0;

    for (register_index = 0u; register_index < GDB_REGISTER_COUNT;
         register_index++) {
        if (!gdb_decode_u32_le(&payload[1u + register_index * 8u],
                               &decoded[register_index]))
            return 0;
    }

    for (register_index = 1u; register_index < 32u; register_index++)
        frame->x[register_index] = decoded[register_index];
    frame->x[0] = 0u;
    frame->mepc = decoded[32];
    return 1;
}

static int range_inside(unsigned int addr, unsigned int length,
                        unsigned int base, unsigned int size)
{
    return addr >= base && length <= size && addr - base <= size - length;
}

static int memory_range_allowed(unsigned int addr, unsigned int length)
{
    if (length == 0u)
        return 0;
    return range_inside(addr, length, GDB_BRAM_BASE, GDB_BRAM_SIZE) ||
           range_inside(addr, length, GDB_SDRAM_BASE, GDB_SDRAM_SIZE);
}

static int parse_memory_header(const char *payload, unsigned int payload_length,
                               unsigned int *addr, unsigned int *length,
                               unsigned int *separator)
{
    unsigned int comma = 1u;
    unsigned int end;

    while (comma < payload_length && payload[comma] != ',')
        comma++;
    if (comma == payload_length)
        return 0;

    end = comma + 1u;
    while (end < payload_length && payload[end] != ':')
        end++;
    if (!gdb_parse_hex_u32(&payload[1], comma - 1u, addr) ||
        !gdb_parse_hex_u32(&payload[comma + 1u], end - comma - 1u, length))
        return 0;
    *separator = end;
    return 1;
}

static int read_memory(const char *payload, unsigned int payload_length)
{
    unsigned int addr;
    unsigned int length;
    unsigned int separator;
    unsigned int index;

    if (!parse_memory_header(payload, payload_length, &addr, &length,
                             &separator) ||
        separator != payload_length || length > GDB_PACKET_CAPACITY / 2u ||
        !memory_range_allowed(addr, length))
        return 0;

    for (index = 0u; index < length; index++) {
        unsigned int byte = *(volatile unsigned char *)(addr + index);
        reply_buffer[index * 2u] = hex_digits[byte >> 4];
        reply_buffer[index * 2u + 1u] = hex_digits[byte & 0xfu];
    }
    reply_buffer[length * 2u] = '\0';
    send_reply_length(reply_buffer, length * 2u);
    return 1;
}

static int write_memory(const char *payload, unsigned int payload_length)
{
    unsigned int addr;
    unsigned int length;
    unsigned int separator;
    unsigned int index;

    if (!parse_memory_header(payload, payload_length, &addr, &length,
                             &separator) ||
        separator == payload_length || payload[separator] != ':' ||
        length > GDB_PACKET_CAPACITY / 2u ||
        payload_length - separator - 1u != length * 2u ||
        !memory_range_allowed(addr, length))
        return 0;

    // 先验证全部 hex，避免非法 packet 造成 partial write。
    for (index = 0u; index < length * 2u; index++) {
        if (gdb_hex_nibble((unsigned char)payload[separator + 1u + index]) < 0)
            return 0;
    }
    for (index = 0u; index < length; index++) {
        int high = gdb_hex_nibble(
            (unsigned char)payload[separator + 1u + index * 2u]);
        int low = gdb_hex_nibble(
            (unsigned char)payload[separator + 2u + index * 2u]);
        *(volatile unsigned char *)(addr + index) =
            (unsigned char)(((unsigned int)high << 4) | (unsigned int)low);
    }
    send_reply("OK");
    return 1;
}

static int continue_target(struct trap_frame *frame, const char *payload,
                           unsigned int payload_length)
{
    unsigned int addr;

    if (payload_length > 1u) {
        if (!gdb_parse_hex_u32(&payload[1], payload_length - 1u, &addr) ||
            (addr & 3u) != 0u || addr >= GDB_BRAM_SIZE) {
            send_reply("E01");
            return 0;
        }
        frame->mepc = addr;
    } else if (frame->mcause == 3u && resume_pc_explicit == 0u) {
        frame->mepc += 4u;
    }
    return 1;
}

static int dispatch_packet(struct trap_frame *frame)
{
    const char *payload = packet_parser.payload;

    if (text_starts_with(payload, "qSupported")) {
        send_reply("PacketSize=200");
    } else if (text_equal(payload, "vMustReplyEmpty")) {
        send_reply("");
    } else if (text_equal(payload, "Hc0") || text_equal(payload, "Hg0") ||
               text_equal(payload, "Hc-1") || text_equal(payload, "Hg-1")) {
        send_reply("OK");
    } else if (text_equal(payload, "qAttached")) {
        send_reply("1");
    } else if (text_equal(payload, "?")) {
        send_reply(stop_reply(frame->mcause));
    } else if (text_equal(payload, "g")) {
        encode_registers(frame);
        send_reply_length(reply_buffer, GDB_REGISTER_HEX_SIZE);
    } else if (payload[0] == 'G') {
        if (decode_registers(frame, payload, packet_parser.length)) {
            resume_pc_explicit = frame->mepc != stopped_pc;
            send_reply("OK");
        } else {
            send_reply("E01");
        }
    } else if (payload[0] == 'm') {
        if (!read_memory(payload, packet_parser.length))
            send_reply("E01");
    } else if (payload[0] == 'M') {
        if (!write_memory(payload, packet_parser.length))
            send_reply("E01");
    } else if (payload[0] == 'c') {
        return continue_target(frame, payload, packet_parser.length);
    } else {
        // RSP 规定未知 command 返回空 packet，而不是 NACK 或断开。
        send_reply("");
    }
    return 0;
}

struct trap_frame *trap_dispatch(struct trap_frame *frame)
{
    // GDB profile 不开启 timer；若已有 IRQ 到达，保留公共 runtime 的返回语义。
    if ((frame->mcause & 0x80000000u) != 0u)
        return frame;

    gdb_packet_parser_init(&packet_parser);
    last_reply[0] = '\0';
    last_reply_length = 0u;
    stopped_pc = frame->mepc;
    resume_pc_explicit = 0u;
    if (debugger_attached != 0u)
        send_reply(stop_reply(frame->mcause));

    for (;;) {
        enum gdb_packet_event event;

        if (uart_get_and_clear_rx_errors() != 0u) {
            gdb_packet_parser_init(&packet_parser);
            uart_putc('-');
        }

        event = gdb_packet_feed(&packet_parser, (unsigned char)uart_getc());
        if (event == GDB_PACKET_READY) {
            uart_putc('+');
            debugger_attached = 1u;
            if (dispatch_packet(frame))
                return frame;
        } else if (event == GDB_PACKET_CHECKSUM_ERROR ||
                   event == GDB_PACKET_OVERFLOW) {
            uart_putc('-');
        } else if (event == GDB_PACKET_RETRY) {
            resend_last_reply();
        }
    }
}
