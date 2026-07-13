// 系统级用户程序 benchmark：同一滑动窗口滤波分别跑在 BRAM 与 SDRAM。
//
// 这不是 microbenchmark：每个输出同时依赖相邻三个输入，覆盖真实的数据读、
// 计算与写回路径；相邻迭代还会重叠读取同一元素，可作为 Dark SDRAM 读请求
// 重放修复的上层回归。
#include "tests/testlib.h"
#include "drivers/perf.h"

#define WORDS 256u
#define ROUNDS 4u

static volatile unsigned int bram_src[WORDS];
static volatile unsigned int bram_dst[WORDS];
static volatile unsigned int sdram_src[WORDS] __attribute__((section(".sdram_bss")));
static volatile unsigned int sdram_dst[WORDS] __attribute__((section(".sdram_bss")));

static void fill_buffer(volatile unsigned int *buffer)
{
    unsigned int i;

    for (i = 0u; i < WORDS; i++) {
        buffer[i] = (i * 0x10203u) ^ 0x5a5aa5a5u;
    }
}

static unsigned int run_stencil(volatile unsigned int *src, volatile unsigned int *dst)
{
    unsigned int checksum = 0u;
    unsigned int round;
    unsigned int i;

    for (round = 0u; round < ROUNDS; round++) {
        for (i = 1u; i + 1u < WORDS; i++) {
            unsigned int value = src[i - 1u] + (src[i] << 1) + src[i + 1u];
            value ^= round * 0x9e37u + i;
            dst[i] = value;
            checksum ^= value >> (i & 7u);
        }
    }
    return checksum;
}

static unsigned int measure_stencil(
    const char *memory,
    volatile unsigned int *src,
    volatile unsigned int *dst
)
{
    perf_snapshot_t snap;
    unsigned int checksum;

    perf_begin(&snap);
    checksum = run_stencil(src, dst);
    perf_end(&snap);

    uart_puts("RESULT: benchmark=system_bench case=stencil memory=");
    uart_puts(memory);
    uart_puts(" words=256 rounds=4 cycles=");
    uart_put_dec(snap.cycle);
    uart_puts(" instret=");
    uart_put_dec(snap.instret);
    uart_puts(" mem_wait=");
    uart_put_dec(snap.mem_wait);
    uart_puts("\n");
    return checksum;
}

int main(void)
{
    unsigned int bram_checksum;
    unsigned int sdram_checksum;

    test_banner("system_bench");
    fill_buffer(bram_src);
    fill_buffer(sdram_src);

    bram_checksum = measure_stencil("bram", bram_src, bram_dst);
    sdram_checksum = measure_stencil("sdram", sdram_src, sdram_dst);
    test_expect(bram_checksum == sdram_checksum, 0xdead7001u);
    test_expect(bram_dst[127] == sdram_dst[127], 0xdead7002u);
    test_pass();
    return 0;
}
