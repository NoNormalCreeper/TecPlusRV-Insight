// 连续写入 benchmark：比较 BRAM 与 SDRAM 上 rt_memset 的成本。
//
// 这个 workload 对应常见的 buffer 清零、framebuffer 清屏和数组初始化场景。
// 测量区只包含 rt_memset 本身；正确性扫描放在测量区外，避免污染 cycles。
#include "testlib.h"
#include "../drivers/perf.h"
#include "../runtime/rt_string.h"

#define BYTES 4096u

static unsigned char bram_buf[BYTES];
static unsigned char sdram_buf[BYTES] __attribute__((section(".sdram_bss")));
volatile unsigned int memset_bench_sink;

static unsigned int checksum_buffer(const unsigned char *buffer)
{
    unsigned int i;
    unsigned int checksum = 0x12345678u;

    for (i = 0u; i < BYTES; i++) {
        checksum = (checksum << 5) ^ (checksum >> 2) ^ buffer[i] ^ i;
    }
    return checksum;
}

static unsigned int count_mismatch(const unsigned char *buffer, unsigned char expected)
{
    unsigned int i;
    unsigned int mismatch = 0u;

    for (i = 0u; i < BYTES; i++) {
        if (buffer[i] != expected) {
            mismatch++;
        }
    }
    return mismatch;
}

static unsigned int measure_memset(const char *memory, unsigned char *buffer, int value)
{
    perf_snapshot_t snap;
    unsigned int checksum;

    perf_begin(&snap);
    rt_memset(buffer, value, BYTES);
    perf_end(&snap);

    test_expect(count_mismatch(buffer, (unsigned char)value) == 0u, 0xdead8001u);
    checksum = checksum_buffer(buffer);
    memset_bench_sink = (memset_bench_sink << 5) ^ (memset_bench_sink >> 2) ^ checksum;

    uart_puts("RESULT: benchmark=memset_bench memory=");
    uart_puts(memory);
    uart_puts(" bytes=");
    uart_put_dec(BYTES);
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

int main(void)
{
    unsigned int bram_checksum;
    unsigned int sdram_checksum;

    test_banner("memset_bench");
    bram_checksum = measure_memset("bram", bram_buf, 0x5au);
    sdram_checksum = measure_memset("sdram", sdram_buf, 0x5au);
    test_expect(bram_checksum == sdram_checksum, 0xdead8002u);
    test_expect(memset_bench_sink != 0u, 0xdead8003u);
    test_pass();
    return 0;
}
