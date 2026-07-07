#include "testlib.h"

static volatile unsigned int perf_buf[64];

int main(void)
{
    unsigned int checksum = 0u;
    unsigned int round;
    unsigned int i;

    for (i = 0; i < 64u; i++) {
        perf_buf[i] = (i * 0x10203u) + 0x55AA00FFu;
    }

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

    test_expect(checksum == 0x907BE4BEu, 0x41u);
    test_pass();
    return 0;
}
