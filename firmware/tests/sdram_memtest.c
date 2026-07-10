// SDRAM 功能自检。
// 目标：在 0x8000_0000 这块 SDRAM 窗口上，用软件证明它“可写、可读、可比较”。
// 覆盖三类证据：
//   1) 固定 pattern 写读回     —— 证明数据位没有粘连/翻转
//   2) 多个散列地址点写读回   —— 证明不是“只有第一个地址能用”的假象
//   3) 一小段连续遍历写读回   —— 覆盖越过单个访问点的顺序负载
//
// 覆盖范围说明：本自检只做 32 位字（word）访问。
// 当前不覆盖 / 不保证 byte、halfword 的独立读写语义——SDRAM 数据通路是否
// 支持子字节 strobe 由 M2 的控制器决定，接进总线后再单独补测。
//
// 失败约定：任何一步读回不匹配都写 0xdeadXXXX 错误码退出（沿用 test_fail 语义），
// testbench / 上板 LED 据此判断。全部通过则 test_pass()。
#include "testlib.h"

// SDRAM 基址上的 32 位字视图。volatile 防止编译器把这些硬件访问优化掉。
#define SDRAM_WORD(index) (*(volatile unsigned int *)(TINYBUS_SDRAM_BASE + ((index) * 4u)))

// 固定 pattern 表：覆盖全 0 / 全 1 / 交替 01 / 交替 10 / 递增标记。
static const unsigned int k_patterns[] = {
    0x00000000u,
    0xFFFFFFFFu,
    0xA5A5A5A5u,
    0x5A5A5A5Au,
    0x12345678u,
    0xDEADBEEFu,
};

#define PATTERN_COUNT (sizeof(k_patterns) / sizeof(k_patterns[0]))

// 散列地址点覆盖不同 bank/row，并成对检查 16/32 MiB 边界不发生 alias。
static const unsigned int k_scatter_index[] = {
    0u,
    1u,
    7u,
    255u,
    256u,
    512u,
    1023u,
    1024u,
    17408u,
    4194303u,
    8388607u,
};

#define SCATTER_COUNT (sizeof(k_scatter_index) / sizeof(k_scatter_index[0]))

// 顺序遍历长度（word 数）。固定值，保证结果可复现。
#define SEQ_WORDS 64u

int main(void)
{
    unsigned int i;
    unsigned int p;

    test_banner("sdram_memtest");

    // ---- 证据 1：固定 pattern 写读回 ----
    // 每个 pattern 都写进同一个基准单元再读回，逐位确认数据通路无粘连。
    for (p = 0u; p < PATTERN_COUNT; p++) {
        SDRAM_WORD(0u) = k_patterns[p];
        test_expect(SDRAM_WORD(0u) == k_patterns[p], 0xdead0000u + p);
    }

    // ---- 证据 2：多个散列地址点写读回 ----
    // 先全部写入（每个点写各自的唯一值），再统一读回，
    // 这样能发现“后写覆盖了前面地址”的地址译码错误。
    for (i = 0u; i < SCATTER_COUNT; i++) {
        SDRAM_WORD(k_scatter_index[i]) = 0xC0DE0000u + k_scatter_index[i];
    }
    for (i = 0u; i < SCATTER_COUNT; i++) {
        test_expect(SDRAM_WORD(k_scatter_index[i]) == (0xC0DE0000u + k_scatter_index[i]),
                    0xdead1000u + i);
    }

    // ---- 证据 3：连续遍历写读回 ----
    // 先顺序写一段，再顺序读回比较，覆盖跨相邻单元的顺序访问负载。
    for (i = 0u; i < SEQ_WORDS; i++) {
        SDRAM_WORD(i) = (i * 0x01010101u) ^ 0x0F0F0F0Fu;
    }
    for (i = 0u; i < SEQ_WORDS; i++) {
        test_expect(SDRAM_WORD(i) == ((i * 0x01010101u) ^ 0x0F0F0F0Fu),
                    0xdead2000u + i);
    }

    uart_puts("sdram_memtest: all patterns verified\n");
    uart_flush();

    test_pass();
    return 0;
}
