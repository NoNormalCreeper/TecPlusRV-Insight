#include "testlib.h"

static volatile unsigned int word_slot;

int main(void)
{
    volatile unsigned char *bytes = (volatile unsigned char *)&word_slot;
    volatile unsigned short *halves = (volatile unsigned short *)&word_slot;

    test_banner("load_store");

    word_slot = 0u;
    bytes[0] = 0x11u;
    bytes[1] = 0x22u;
    bytes[2] = 0x33u;
    bytes[3] = 0x44u;
    test_expect(word_slot == 0x44332211u, 0x21u);

    halves[0] = 0xABCDu;
    halves[1] = 0x1234u;
    test_expect(word_slot == 0x1234ABCDu, 0x22u);
    test_expect(bytes[0] == 0xCDu, 0x23u);
    test_expect(bytes[1] == 0xABu, 0x24u);
    test_expect(bytes[2] == 0x34u, 0x25u);
    test_expect(bytes[3] == 0x12u, 0x26u);

    test_pass();
    return 0;
}
