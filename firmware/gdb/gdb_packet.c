#include "gdb_packet.h"

enum parser_state {
    PARSER_WAIT_START,
    PARSER_PAYLOAD,
    PARSER_CHECKSUM_HIGH,
    PARSER_CHECKSUM_LOW,
    PARSER_DISCARD
};

static const char hex_digits[] = "0123456789abcdef";

void gdb_packet_parser_init(struct gdb_packet_parser *parser)
{
    parser->payload[0] = '\0';
    parser->length = 0u;
    parser->checksum = 0u;
    parser->received_checksum = 0u;
    parser->state = PARSER_WAIT_START;
    parser->overflow = 0u;
}

static void start_packet(struct gdb_packet_parser *parser)
{
    parser->payload[0] = '\0';
    parser->length = 0u;
    parser->checksum = 0u;
    parser->received_checksum = 0u;
    parser->state = PARSER_PAYLOAD;
    parser->overflow = 0u;
}

enum gdb_packet_event gdb_packet_feed(struct gdb_packet_parser *parser,
                                      unsigned char byte)
{
    int nibble;

    // 任意阶段遇到新起始符都重新同步，包括截断和 overflow 后的恢复。
    if (byte == '$') {
        start_packet(parser);
        return GDB_PACKET_NONE;
    }

    switch (parser->state) {
    case PARSER_WAIT_START:
        if (byte == '-')
            return GDB_PACKET_RETRY;
        return GDB_PACKET_NONE;

    case PARSER_PAYLOAD:
        if (byte == '#') {
            parser->payload[parser->length] = '\0';
            parser->state = PARSER_CHECKSUM_HIGH;
            return GDB_PACKET_NONE;
        }
        if (parser->length >= GDB_PACKET_CAPACITY) {
            parser->overflow = 1u;
            parser->state = PARSER_DISCARD;
            return GDB_PACKET_OVERFLOW;
        }
        parser->payload[parser->length++] = (char)byte;
        parser->checksum = (parser->checksum + byte) & 0xffu;
        return GDB_PACKET_NONE;

    case PARSER_CHECKSUM_HIGH:
        nibble = gdb_hex_nibble(byte);
        if (nibble < 0) {
            parser->state = PARSER_WAIT_START;
            return GDB_PACKET_CHECKSUM_ERROR;
        }
        parser->received_checksum = (unsigned int)nibble << 4;
        parser->state = PARSER_CHECKSUM_LOW;
        return GDB_PACKET_NONE;

    case PARSER_CHECKSUM_LOW:
        nibble = gdb_hex_nibble(byte);
        parser->state = PARSER_WAIT_START;
        if (nibble < 0)
            return GDB_PACKET_CHECKSUM_ERROR;
        parser->received_checksum |= (unsigned int)nibble;
        if (parser->received_checksum != parser->checksum)
            return GDB_PACKET_CHECKSUM_ERROR;
        return GDB_PACKET_READY;

    case PARSER_DISCARD:
    default:
        return GDB_PACKET_NONE;
    }
}

int gdb_hex_nibble(unsigned char ch)
{
    if (ch >= '0' && ch <= '9')
        return (int)(ch - '0');
    if (ch >= 'a' && ch <= 'f')
        return (int)(ch - 'a') + 10;
    if (ch >= 'A' && ch <= 'F')
        return (int)(ch - 'A') + 10;
    return -1;
}

int gdb_parse_hex_u32(const char *text, unsigned int length,
                      unsigned int *value)
{
    unsigned int parsed = 0u;
    unsigned int index;

    if (length == 0u || length > 8u)
        return 0;

    for (index = 0u; index < length; index++) {
        int nibble = gdb_hex_nibble((unsigned char)text[index]);
        if (nibble < 0)
            return 0;
        parsed = (parsed << 4) | (unsigned int)nibble;
    }

    *value = parsed;
    return 1;
}

void gdb_encode_u32_le(char output[9], unsigned int value)
{
    unsigned int index;

    for (index = 0u; index < 4u; index++) {
        unsigned int byte = (value >> (index * 8u)) & 0xffu;
        output[index * 2u] = hex_digits[byte >> 4];
        output[index * 2u + 1u] = hex_digits[byte & 0xfu];
    }
    output[8] = '\0';
}

int gdb_decode_u32_le(const char input[8], unsigned int *value)
{
    unsigned int decoded = 0u;
    unsigned int index;

    for (index = 0u; index < 4u; index++) {
        int high = gdb_hex_nibble((unsigned char)input[index * 2u]);
        int low = gdb_hex_nibble((unsigned char)input[index * 2u + 1u]);
        unsigned int byte;

        if (high < 0 || low < 0)
            return 0;
        byte = ((unsigned int)high << 4) | (unsigned int)low;
        decoded |= byte << (index * 8u);
    }

    *value = decoded;
    return 1;
}
