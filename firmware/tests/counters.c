#include "testlib.h"

int main(void)
{
    unsigned int cycle0;
    unsigned int cycle1;
    unsigned int inst0;
    unsigned int inst1;
    volatile unsigned int sink = 0u;
    unsigned int i;

    test_banner("counters");

    cycle0 = test_read_cycle();
    inst0 = test_read_instret();

    for (i = 0; i < 64u; i++) {
        sink += (i ^ 0x5Au);
    }

    cycle1 = test_read_cycle();
    inst1 = test_read_instret();

    test_expect(sink != 0u, 0x31u);
    test_expect(cycle1 > cycle0, 0x32u);
    test_expect(inst1 > inst0, 0x33u);
    test_expect((cycle1 - cycle0) >= (inst1 - inst0), 0x34u);

    test_pass();
    return 0;
}
