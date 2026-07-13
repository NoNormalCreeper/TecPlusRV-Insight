// 步长访问 benchmark：同样次数的读改写，在 BRAM 与 SDRAM 上比较 stride 影响。
//
// stride=1 接近顺序访问；stride 变大后访问更稀疏，更容易暴露外部存储延迟。
#include "testlib.h"
#include "../drivers/perf.h"

#define WORDS 1024u
#define ACCESSES 2048u

static volatile unsigned int bram_words[WORDS];
static volatile unsigned int sdram_words[WORDS] __attribute__((section(".sdram_bss")));
volatile unsigned int stride_bench_sink;

static void fill_words(volatile unsigned int *buffer)
{
    unsigned int i;

    for (i = 0u; i < WORDS; i++) {
        buffer[i] = (i * 0x10203u) ^ 0x5a5aa5a5u;
    }
}

static unsigned int run_stride(volatile unsigned int *buffer, unsigned int stride)
{
    unsigned int i;
    unsigned int checksum = 0x2468ace0u;

    for (i = 0u; i < ACCESSES; i++) {
        unsigned int index = (i * stride) & (WORDS - 1u);
        unsigned int value = buffer[index];
        checksum = (checksum << 3) ^ (checksum >> 7) ^ value ^ i;
        buffer[index] = value + checksum + stride;
    }
    return checksum;
}

static unsigned int measure_stride(
    const char *memory,
    const char *case_name,
    volatile unsigned int *buffer,
    unsigned int stride
)
{
    perf_snapshot_t snap;
    unsigned int checksum;

    fill_words(buffer);
    perf_begin(&snap);
    checksum = run_stride(buffer, stride);
    perf_end(&snap);
    stride_bench_sink = (stride_bench_sink << 5) ^ (stride_bench_sink >> 2) ^ checksum;

    uart_puts("RESULT: benchmark=stride_bench case=");
    uart_puts(case_name);
    uart_puts(" memory=");
    uart_puts(memory);
    uart_puts(" words=");
    uart_put_dec(WORDS);
    uart_puts(" accesses=");
    uart_put_dec(ACCESSES);
    uart_puts(" cycles=");
    uart_put_dec(snap.cycle);
    uart_puts(" instret=");
    uart_put_dec(snap.instret);
    uart_puts(" mem_wait=");
    uart_put_dec(snap.mem_wait);
    uart_puts(" checksum=");
    uart_put_hex(checksum);
    uart_puts("\n");

    return checksum;
}

static void measure_pair(const char *case_name, unsigned int stride, unsigned int error_code)
{
    unsigned int bram_checksum;
    unsigned int sdram_checksum;

    bram_checksum = measure_stride("bram", case_name, bram_words, stride);
    sdram_checksum = measure_stride("sdram", case_name, sdram_words, stride);
    test_expect(bram_checksum == sdram_checksum, error_code);
}

int main(void)
{
    test_banner("stride_bench");
    measure_pair("stride1", 1u, 0xdead8101u);
    measure_pair("stride2", 2u, 0xdead8102u);
    measure_pair("stride4", 4u, 0xdead8103u);
    measure_pair("stride8", 8u, 0xdead8104u);
    measure_pair("stride16", 16u, 0xdead8105u);
    test_expect(stride_bench_sink != 0u, 0xdead8106u);
    test_pass();
    return 0;
}
