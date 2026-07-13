// CRC32 benchmark：比较 BRAM 与 SDRAM 上“读取 + 位运算”的混合负载。
//
// 相比纯 memcpy/memset，CRC32 更接近 bootloader 包校验、资源校验和协议处理。
#include "testlib.h"
#include "../drivers/perf.h"

#define BYTES 4096u

static volatile unsigned char bram_data[BYTES];
static volatile unsigned char sdram_data[BYTES] __attribute__((section(".sdram_bss")));
volatile unsigned int crc32_bench_sink;

static void fill_bytes(volatile unsigned char *buffer)
{
    unsigned int i;

    for (i = 0u; i < BYTES; i++) {
        buffer[i] = (unsigned char)((i * 37u) ^ (i >> 3) ^ 0xa5u);
    }
}

static unsigned int crc32_update(unsigned int crc, unsigned char byte)
{
    unsigned int bit;

    crc ^= byte;
    for (bit = 0u; bit < 8u; bit++) {
        if ((crc & 1u) != 0u) {
            crc = (crc >> 1) ^ 0xedb88320u;
        } else {
            crc >>= 1;
        }
    }
    return crc;
}

static unsigned int run_crc32(volatile unsigned char *buffer)
{
    unsigned int i;
    unsigned int crc = 0xffffffffu;

    for (i = 0u; i < BYTES; i++) {
        crc = crc32_update(crc, buffer[i]);
    }
    return crc ^ 0xffffffffu;
}

static unsigned int measure_crc32(const char *memory, volatile unsigned char *buffer)
{
    perf_snapshot_t snap;
    unsigned int crc;

    fill_bytes(buffer);
    perf_begin(&snap);
    crc = run_crc32(buffer);
    perf_end(&snap);
    crc32_bench_sink = (crc32_bench_sink << 5) ^ (crc32_bench_sink >> 2) ^ crc;

    uart_puts("RESULT: benchmark=crc32_bench memory=");
    uart_puts(memory);
    uart_puts(" bytes=");
    uart_put_dec(BYTES);
    uart_puts(" cycles=");
    uart_put_dec(snap.cycle);
    uart_puts(" instret=");
    uart_put_dec(snap.instret);
    uart_puts(" mem_wait=");
    uart_put_dec(snap.mem_wait);
    uart_puts(" crc=");
    uart_put_hex(crc);
    uart_puts("\n");

    return crc;
}

int main(void)
{
    unsigned int bram_crc;
    unsigned int sdram_crc;

    test_banner("crc32_bench");
    bram_crc = measure_crc32("bram", bram_data);
    sdram_crc = measure_crc32("sdram", sdram_data);
    test_expect(bram_crc == sdram_crc, 0xdead8201u);
    test_expect(crc32_bench_sink != 0u, 0xdead8202u);
    test_pass();
    return 0;
}
