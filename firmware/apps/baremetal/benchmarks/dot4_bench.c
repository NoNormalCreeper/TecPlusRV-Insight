// 纯 RV32I 与 DarkRISCV custom-0 DOT4 的正确性/性能对照。
#include "tests/testlib.h"
#include "drivers/perf.h"
#include "accel/dot4.h"

#define VECTOR_COUNT 32u
#define ROUNDS 16u

static volatile unsigned int input_a[VECTOR_COUNT];
static volatile unsigned int input_b[VECTOR_COUNT];
static volatile int scalar_result[VECTOR_COUNT];
static volatile int custom_result[VECTOR_COUNT];

static int __attribute__((noinline)) dot4_scalar_s8(
    unsigned int packed_a,
    unsigned int packed_b
)
{
    signed char a0 = (signed char)(packed_a & 0xffu);
    signed char a1 = (signed char)((packed_a >> 8) & 0xffu);
    signed char a2 = (signed char)((packed_a >> 16) & 0xffu);
    signed char a3 = (signed char)((packed_a >> 24) & 0xffu);
    signed char b0 = (signed char)(packed_b & 0xffu);
    signed char b1 = (signed char)((packed_b >> 8) & 0xffu);
    signed char b2 = (signed char)((packed_b >> 16) & 0xffu);
    signed char b3 = (signed char)((packed_b >> 24) & 0xffu);

    return a0 * b0 + a1 * b1 + a2 * b2 + a3 * b3;
}

static void init_vectors(void)
{
    unsigned int i;

    for (i = 0u; i < VECTOR_COUNT; i++) {
        input_a[i] = 0x80ff017fu ^ (i * 0x01030507u);
        input_b[i] = 0x7f02ff80u + (i * 0x07050301u);
    }
}

static unsigned int run_scalar(void)
{
    unsigned int round;
    unsigned int i;
    unsigned int checksum = 0u;

    for (round = 0u; round < ROUNDS; round++) {
        for (i = 0u; i < VECTOR_COUNT; i++) {
            int value = dot4_scalar_s8(input_a[i], input_b[i]);
            scalar_result[i] = value;
            checksum ^= (unsigned int)value + round + i;
        }
    }
    return checksum;
}

static unsigned int run_custom(void)
{
    unsigned int round;
    unsigned int i;
    unsigned int checksum = 0u;

    for (round = 0u; round < ROUNDS; round++) {
        for (i = 0u; i < VECTOR_COUNT; i++) {
            int value = dot4_s8(input_a[i], input_b[i]);
            custom_result[i] = value;
            checksum ^= (unsigned int)value + round + i;
        }
    }
    return checksum;
}

static void report_result(
    const char *mode,
    unsigned int checksum,
    const perf_snapshot_t *snap
)
{
    uart_puts("RESULT: benchmark=dot4 mode=");
    uart_puts(mode);
    uart_puts(" vectors=32 rounds=16 checksum=");
    uart_put_hex(checksum);
    uart_puts(" cycles=");
    uart_put_dec(snap->cycle);
    uart_puts(" instret=");
    uart_put_dec(snap->instret);
    uart_puts(" mem_wait=");
    uart_put_dec(snap->mem_wait);
    uart_puts("\n");
}

int main(void)
{
    perf_snapshot_t scalar_perf;
    perf_snapshot_t custom_perf;
    unsigned int scalar_checksum;
    unsigned int custom_checksum;
    unsigned int i;

    test_banner("dot4_bench");
    init_vectors();

    perf_begin(&scalar_perf);
    scalar_checksum = run_scalar();
    perf_end(&scalar_perf);

    perf_begin(&custom_perf);
    custom_checksum = run_custom();
    perf_end(&custom_perf);

    for (i = 0u; i < VECTOR_COUNT; i++) {
        test_expect(custom_result[i] == scalar_result[i], 0xdead8000u + i);
    }
    test_expect(custom_checksum == scalar_checksum, 0xdead8100u);
    test_expect(custom_perf.cycle < scalar_perf.cycle, 0xdead8101u);
    test_expect(custom_perf.instret < scalar_perf.instret, 0xdead8102u);

    report_result("scalar", scalar_checksum, &scalar_perf);
    report_result("custom", custom_checksum, &custom_perf);
    uart_flush();
    test_pass();
    return 0;
}
