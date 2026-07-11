#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "gdb/gdb_packet.h"

static enum gdb_packet_event feed_text(struct gdb_packet_parser *parser,
                                       const char *text)
{
    enum gdb_packet_event event = GDB_PACKET_NONE;

    while (*text != '\0') {
        enum gdb_packet_event next =
            gdb_packet_feed(parser, (unsigned char)*text++);
        if (next != GDB_PACKET_NONE)
            event = next;
    }

    return event;
}

static enum gdb_packet_event feed_packet(struct gdb_packet_parser *parser,
                                         const char *payload)
{
    static const char digits[] = "0123456789abcdef";
    enum gdb_packet_event event;
    unsigned int checksum = 0u;
    const char *cursor;

    event = gdb_packet_feed(parser, '$');
    assert(event == GDB_PACKET_NONE);
    for (cursor = payload; *cursor != '\0'; cursor++) {
        checksum = (checksum + (unsigned char)*cursor) & 0xffu;
        event = gdb_packet_feed(parser, (unsigned char)*cursor);
    }
    event = gdb_packet_feed(parser, '#');
    assert(event == GDB_PACKET_NONE);
    event = gdb_packet_feed(parser, (unsigned char)digits[checksum >> 4]);
    assert(event == GDB_PACKET_NONE);
    return gdb_packet_feed(parser, (unsigned char)digits[checksum & 0xfu]);
}

static void test_valid_packet(void)
{
    struct gdb_packet_parser parser;

    gdb_packet_parser_init(&parser);
    assert(feed_text(&parser, "$?#3f") == GDB_PACKET_READY);
    assert(parser.length == 1u);
    assert(strcmp(parser.payload, "?") == 0);
}

static void test_checksum_and_retry(void)
{
    struct gdb_packet_parser parser;

    gdb_packet_parser_init(&parser);
    assert(feed_text(&parser, "$g#00") == GDB_PACKET_CHECKSUM_ERROR);
    assert(gdb_packet_feed(&parser, '-') == GDB_PACKET_RETRY);
    assert(gdb_packet_feed(&parser, '+') == GDB_PACKET_NONE);
}

static void test_long_payload(void)
{
    static const char request[] =
        "qSupported:multiprocess+;swbreak+;hwbreak+;qRelocInsn+;"
        "fork-events+;vfork-events+;exec-events+;vContSupported+;"
        "QThreadEvents+;no-resumed+;memory-tagging+;xmlRegisters=i386";
    struct gdb_packet_parser parser;

    assert(strlen(request) == 171u);
    gdb_packet_parser_init(&parser);
    assert(feed_packet(&parser, request) == GDB_PACKET_READY);
    assert(strcmp(parser.payload, request) == 0);
}

static void test_overflow_resynchronizes(void)
{
    struct gdb_packet_parser parser;
    enum gdb_packet_event event = GDB_PACKET_NONE;
    unsigned int index;

    gdb_packet_parser_init(&parser);
    assert(gdb_packet_feed(&parser, '$') == GDB_PACKET_NONE);
    for (index = 0; index < GDB_PACKET_CAPACITY + 1u; index++)
        event = gdb_packet_feed(&parser, 'a');
    assert(event == GDB_PACKET_OVERFLOW);
    assert(feed_text(&parser, "#00") == GDB_PACKET_NONE);
    assert(feed_text(&parser, "$?#3f") == GDB_PACKET_READY);
    assert(strcmp(parser.payload, "?") == 0);
}

static void test_new_start_discards_truncated_packet(void)
{
    struct gdb_packet_parser parser;

    gdb_packet_parser_init(&parser);
    assert(feed_text(&parser, "$truncated$?#3f") == GDB_PACKET_READY);
    assert(strcmp(parser.payload, "?") == 0);
}

static void test_hex_codec(void)
{
    char encoded[9];
    unsigned int value = 0u;

    assert(gdb_hex_nibble('0') == 0);
    assert(gdb_hex_nibble('a') == 10);
    assert(gdb_hex_nibble('F') == 15);
    assert(gdb_hex_nibble('x') == -1);

    assert(gdb_parse_hex_u32("81ffffff", 8u, &value));
    assert(value == 0x81ffffffu);
    assert(!gdb_parse_hex_u32("", 0u, &value));
    assert(!gdb_parse_hex_u32("100000000", 9u, &value));
    assert(!gdb_parse_hex_u32("12xz", 4u, &value));

    gdb_encode_u32_le(encoded, 0x12345678u);
    assert(strcmp(encoded, "78563412") == 0);
    assert(gdb_decode_u32_le(encoded, &value));
    assert(value == 0x12345678u);
    assert(!gdb_decode_u32_le("7856341x", &value));
}

int main(void)
{
    test_valid_packet();
    test_checksum_and_retry();
    test_long_payload();
    test_overflow_resynchronizes();
    test_new_start_discards_truncated_packet();
    test_hex_codec();
    puts("PASS: GDB packet parser 与 codec");
    return 0;
}
