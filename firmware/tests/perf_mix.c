#include "testlib.h"
#include "../drivers/perf.h"

static volatile unsigned int perf_buf[64];
#define MIXED_ROUNDS 32u
volatile unsigned int perf_cycle_delta;
volatile unsigned int perf_instret_delta;
volatile unsigned int perf_mem_wait_delta;

static void init_buffer(void)
{
    unsigned int i;

    for (i = 0u; i < 64u; i++) {
        perf_buf[i] = (i * 0x10203u) + 0x55AA00FFu;
    }
}

static void report_case(const char *name, const perf_snapshot_t *snap)
{
    uart_puts("RESULT: benchmark=perf_mix case=");
    uart_puts(name);
    uart_puts(" cycles=");
    uart_put_dec(snap->cycle);
    uart_puts(" instret=");
    uart_put_dec(snap->instret);
    uart_puts(" mem_wait=");
    uart_put_dec(snap->mem_wait);
    uart_puts("\n");
}

static unsigned int run_alu_dep(void)
{
    unsigned int i;
    unsigned int value = 0x13579BDFu;

    for (i = 0u; i < 4096u; i++) {
        value = (value << 3) ^ (value >> 5) ^ (i * 0x9E37u);
    }
    return value;
}

static unsigned int run_branch_alternating(void)
{
    unsigned int i;
    unsigned int sum = 0u;

    for (i = 0u; i < 4096u; i++) {
        if ((i & 1u) == 0u) {
            sum += i ^ 0x55AAu;
        } else {
            sum ^= i + 0x33CCu;
        }
    }
    return sum;
}

static unsigned int run_bram_load_store(void)
{
    unsigned int i;
    unsigned int sum = 0u;

    for (i = 0u; i < 1024u; i++) {
        unsigned int index = i & 63u;
        unsigned int value = perf_buf[index];
        perf_buf[index] = value + i + 1u;
        sum ^= value;
    }
    return sum;
}

static unsigned int run_mixed(void)
{
    unsigned int checksum = 0u;
    unsigned int round;
    unsigned int i;

    for (round = 0u; round < MIXED_ROUNDS; round++) {
        for (i = 0u; i < 64u; i++) {
            unsigned int value = perf_buf[i];
            value = (value << 1) ^ (value + 0x9E3779B9u + round + i);
            if ((value & 1u) != 0u) {
                value ^= 0xA5A5A5A5u;
            } else {
                value += 0x3C6EF372u;
            }
            perf_buf[i] = value;
            checksum ^= value >> (i & 7u);
        }
    }
    return checksum;
}

int main(void)
{
    perf_snapshot_t snap;
    unsigned int checksum;
    init_buffer();

    perf_begin(&snap);
    checksum = run_alu_dep();
    perf_end(&snap);
    report_case("alu_dep", &snap);
    test_expect(checksum != 0u, 0x41u);

    perf_begin(&snap);
    checksum = run_branch_alternating();
    perf_end(&snap);
    report_case("branch_alternating", &snap);
    test_expect(checksum != 0u, 0x42u);

    perf_begin(&snap);
    checksum = run_bram_load_store();
    perf_end(&snap);
    report_case("bram_load_store", &snap);
    test_expect(checksum != 0u, 0x43u);

    // mixed case 保持原有输入，确保历史 CPI 基线仍然可比。
    init_buffer();
    perf_begin(&snap);
    checksum = run_mixed();
    perf_end(&snap);
    perf_cycle_delta = snap.cycle;
    perf_instret_delta = snap.instret;
    perf_mem_wait_delta = snap.mem_wait;
    report_case("mixed", &snap);

    test_expect(checksum == 0x387C3121u, 0x44u);
    test_expect(perf_cycle_delta != 0u, 0x45u);
    test_expect(perf_instret_delta != 0u, 0x46u);
    test_expect(perf_mem_wait_delta != 0u, 0x47u);
    uart_flush();
    test_pass();
    return 0;
}
