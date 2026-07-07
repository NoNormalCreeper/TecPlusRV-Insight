#include "testlib.h"

int main(void)
{
    int i;
    unsigned int acc = 0;

    test_banner("alu_branch");

    for (i = 1; i <= 16; i++) {
        if ((i & 1) == 0) {
            acc += (unsigned int)(i * 3);
        } else {
            acc ^= (unsigned int)(i << 4);
        }
    }

    test_expect(acc == 0x00000218u, 0x11u);
    test_pass();
    return 0;
}
