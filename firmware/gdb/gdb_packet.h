// GDB Remote Serial Protocol 的最小 packet parser 与 hex codec。
#ifndef GDB_PACKET_H
#define GDB_PACKET_H

#define GDB_PACKET_CAPACITY 512u

enum gdb_packet_event {
    GDB_PACKET_NONE,
    GDB_PACKET_READY,
    GDB_PACKET_CHECKSUM_ERROR,
    GDB_PACKET_OVERFLOW,
    GDB_PACKET_RETRY
};

struct gdb_packet_parser {
    // 多留一个 byte 写 NUL；协议允许的 payload 上限仍是 512 bytes。
    char payload[GDB_PACKET_CAPACITY + 1u];
    unsigned int length;
    unsigned int checksum;
    unsigned int received_checksum;
    unsigned int state;
    unsigned int overflow;
};

void gdb_packet_parser_init(struct gdb_packet_parser *parser);
enum gdb_packet_event gdb_packet_feed(struct gdb_packet_parser *parser,
                                      unsigned char byte);

int gdb_hex_nibble(unsigned char ch);
int gdb_parse_hex_u32(const char *text, unsigned int length,
                      unsigned int *value);
void gdb_encode_u32_le(char output[9], unsigned int value);
int gdb_decode_u32_le(const char input[8], unsigned int *value);

#endif
