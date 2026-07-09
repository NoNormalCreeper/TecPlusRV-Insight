// SDRAM 求和 benchmark 基线（第一版）。
// 目标：在 SDRAM 窗口上放一个固定大小的大数组，做一次顺序遍历求和，
// 测出这段负载消耗的 cycle 与 instret，作为后续 BRAM / SDRAM 对比的可复现基线。
//
// 设计取舍：
//   - 规模固定为 N=1024 个 32 位字（4 KiB），换机器 / 换核结果都可比。
//   - 只做“顺序遍历求和”这一种最朴素的访问模式，第一版不追求性能漂亮，
//     只要能跑通、能对比。更复杂的访问模式（随机 / 跨步）留待后续。
//   - a[i] = i，求和期望值 = N*(N-1)/2，用它做正确性断言，防止“测了个假循环”。
//
// 覆盖范围说明：与 sdram_memtest 一致，只做 32 位字访问。
#include "testlib.h"

// SDRAM 基址上的 32 位字视图。volatile 保证填充和读取都真正落到内存上，
// 不被编译器优化成常量或消掉循环。
#define SDRAM_WORD(index) (*(volatile unsigned int *)(TINYBUS_SDRAM_BASE + ((index) * 4u)))

// 固定数组规模（word 数）。改这个值会改变基线，对比时必须两边一致。
#define BENCH_WORDS 1024u

// 基线结果写回 volatile 全局，既方便 testbench/波形观察，也防止整段被当死代码删。
volatile unsigned int bench_sum;
volatile unsigned int bench_cycle_delta;
volatile unsigned int bench_instret_delta;

int main(void)
{
    unsigned int i;
    unsigned int sum = 0u;
    unsigned int cycle0;
    unsigned int cycle1;
    unsigned int inst0;
    unsigned int inst1;
    // N*(N-1)/2，用无符号 32 位算，1024 规模不会溢出。
    unsigned int expected = (BENCH_WORDS * (BENCH_WORDS - 1u)) / 2u;

    test_banner("sdram_sum_bench");

    // 填充固定内容：a[i] = i。
    for (i = 0u; i < BENCH_WORDS; i++) {
        SDRAM_WORD(i) = i;
    }

    // ---- 被测负载：顺序遍历求和 ----
    cycle0 = test_read_cycle();
    inst0 = test_read_instret();

    for (i = 0u; i < BENCH_WORDS; i++) {
        sum += SDRAM_WORD(i);
    }

    cycle1 = test_read_cycle();
    inst1 = test_read_instret();

    bench_sum = sum;
    bench_cycle_delta = cycle1 - cycle0;
    bench_instret_delta = inst1 - inst0;

    // 打印基线，方便人看和记录。
    uart_puts("sdram_sum_bench: words=");
    uart_put_dec(BENCH_WORDS);
    uart_puts(" sum=");
    uart_put_hex(bench_sum);
    uart_puts(" cycles=");
    uart_put_dec(bench_cycle_delta);
    uart_puts(" instret=");
    uart_put_dec(bench_instret_delta);
    uart_puts("\n");
    uart_flush();

    // 正确性 + 计数器非零，任一不满足写错误码退出。
    test_expect(bench_sum == expected, 0xdead3001u);
    test_expect(bench_cycle_delta != 0u, 0xdead3002u);
    test_expect(bench_instret_delta != 0u, 0xdead3003u);

    test_pass();
    return 0;
}
