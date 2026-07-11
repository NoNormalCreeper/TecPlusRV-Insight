// SDRAM subword 回归：覆盖四个 byte lane 与两个 halfword lane。
#include "testlib.h"

int main(void)
{
    volatile unsigned int *word =
        (volatile unsigned int *)(TINYBUS_SDRAM_BASE + 0x400u);
    volatile unsigned char *bytes =
        (volatile unsigned char *)(TINYBUS_SDRAM_BASE + 0x400u);
    volatile unsigned short *halves =
        (volatile unsigned short *)(TINYBUS_SDRAM_BASE + 0x400u);

    test_banner("sdram_subword");

    *word = 0x44332211u;
    bytes[0] = 0xa0u;
    test_expect(*word == 0x443322a0u, 0xfa0b0001u);
    bytes[1] = 0xb1u;
    test_expect(*word == 0x4433b1a0u, 0xfa0b0002u);
    bytes[2] = 0xc2u;
    test_expect(*word == 0x44c2b1a0u, 0xfa0b0003u);
    bytes[3] = 0xd3u;
    test_expect(*word == 0xd3c2b1a0u, 0xfa0b0004u);

    test_expect(bytes[0] == 0xa0u, 0xfa0b0010u);
    test_expect(bytes[1] == 0xb1u, 0xfa0b0011u);
    test_expect(bytes[2] == 0xc2u, 0xfa0b0012u);
    test_expect(bytes[3] == 0xd3u, 0xfa0b0013u);

    *word = 0x44332211u;
    halves[0] = 0xa1b2u;
    test_expect(*word == 0x4433a1b2u, 0xfa0b0020u);
    halves[1] = 0xc3d4u;
    test_expect(*word == 0xc3d4a1b2u, 0xfa0b0021u);
    test_expect(halves[0] == 0xa1b2u, 0xfa0b0030u);
    test_expect(halves[1] == 0xc3d4u, 0xfa0b0031u);

    uart_puts("sdram_subword: all lanes verified\n");
    uart_flush();
    test_pass();
    return 0;
}
