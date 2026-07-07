#include "testlib.h"

static volatile unsigned int perf_buf[64];
volatile unsigned int perf_cycle_delta;
volatile unsigned int perf_instret_delta;

int main(void)
{
    unsigned int checksum = 0u;
    unsigned int cycle0;
    unsigned int cycle1;
    unsigned int inst0;
    unsigned int inst1;
    unsigned int round;
    unsigned int i;

    for (i = 0; i < 64u; i++) {
        perf_buf[i] = (i * 0x10203u) + 0x55AA00FFu;
    }

    cycle0 = test_read_cycle();
    inst0 = test_read_instret();

    for (round = 0; round < 128u; round++) {
        for (i = 0; i < 64u; i++) {
            unsigned int v = perf_buf[i];
            v = (v << 1) ^ (v + 0x9E3779B9u + round + i);
            if ((v & 1u) != 0u) {
                v ^= 0xA5A5A5A5u;
            } else {
                v += 0x3C6EF372u;
            }
            perf_buf[i] = v;
            checksum ^= (v >> (i & 7u));
        }
    }

    cycle1 = test_read_cycle();
    inst1 = test_read_instret();
    perf_cycle_delta = cycle1 - cycle0;
    perf_instret_delta = inst1 - inst0;

    test_expect(checksum == 0x907BE4BEu, 0x41u);
    test_expect(perf_cycle_delta != 0u, 0x42u);
    test_expect(perf_instret_delta != 0u, 0x43u);
    test_pass();
    return 0;
}
