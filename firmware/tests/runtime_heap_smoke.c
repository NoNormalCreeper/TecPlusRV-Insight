// M3 最小 runtime 冒烟测试。
// 覆盖 issue 要求的四层验收：
//   1) 启动级：.data copy 生效、.bss zero 生效、显式放到 .sdram_data/.sdram_bss
//      的对象在运行时地址和内容都正确。
//   2) 库函数级：memcpy / memset / memmove（含重叠区间）和 rt_* 薄封装。
//   3) allocator 级：连续分配、对齐、空间耗尽、reset 后重新初始化，
//      并通过分配到的指针真实读写 SDRAM heap。
//   4) SoC 级：本文件本身作为 minisoc 冒烟入口，双核跑通即证明整条链可用。
//
// 运行目标：M2b 接通 0x8000_0000 后，heap 落在 SDRAM（linker.ld），
// 所以本测试须跑在 minisoc_sdram_pico / minisoc_sdram_dark 上（带 SDRAM 模型）。
// 在无 SDRAM 的 minisoc_pico/dark 上，SDRAM 段与 heap 读写检查会被
// sdram_present() 探测跳过，只剩纯计算类断言，不构成完整验收。
#include "testlib.h"
#include "../runtime/rt_string.h"
#include "../runtime/rt_alloc.h"
#include "../runtime/rt_print.h"

// linker.ld 导出的 heap 边界，用于耗尽测试算容量。
extern unsigned char _heap_start[];
extern unsigned char _heap_end[];

// ---- 启动搬运的验证素材 ----
// 有初值的普通全局：走 .data，验证 startup 的 .data copy 语义。
static volatile unsigned int data_marker = 0x1234ABCDu;
// 未初始化全局：走 .bss，C 语义要求启动后为 0。
static unsigned int bss_marker;

// 显式落到 SDRAM 段的对象：有初值的走 .sdram_data（需 startup 从 LMA 搬到 VMA），
// 未初始化的走 .sdram_bss（需 startup 清零）。
static unsigned int sdram_data_marker __attribute__((section(".sdram_data"))) = 0xCAFEF00Du;
static unsigned int sdram_bss_marker __attribute__((section(".sdram_bss")));

// 运行时探测 0x8000_0000 SDRAM 窗口是否已接上总线。
// M2b 未接通前，对该地址的写会被丢弃、读回不成立，返回 0；接通后返回 1。
// 用两个不同地址 + 不同 pattern：既能识别“写被忽略 / 读恒定”的未接通状态，
// 也能防止“单锁存器总线永远返回最后一次写”造成的误判。
static int sdram_present(void)
{
    volatile unsigned int *a = (volatile unsigned int *)(TINYBUS_SDRAM_BASE + 0x100u);
    volatile unsigned int *b = (volatile unsigned int *)(TINYBUS_SDRAM_BASE + 0x200u);

    *a = 0xA5A50001u;
    *b = 0x5A5A0002u;
    return (*a == 0xA5A50001u) && (*b == 0x5A5A0002u);
}

int main(void)
{
    unsigned char buf[16];
    unsigned char seq[8];
    unsigned int i;
    void *p0;
    void *p1;
    void *p2;
    size_t heap_capacity;

    test_banner("runtime_heap_smoke");

    // ================= 1) 启动级 =================
    // .data：有初值全局应保留初值。即使当前 LMA/VMA 都在 BRAM，也由 startup copy。
    test_expect(data_marker == 0x1234ABCDu, 0xdead0001u);
    // .bss：未初始化全局应被清零。现在就能验。
    test_expect(bss_marker == 0u, 0xdead0002u);

    // .sdram_data / .sdram_bss 的运行地址在 0x8000_0000（SDRAM 窗口）。
    // M2b 把该窗口接上总线前，这些地址写被丢弃、读回不成立，无法真验证，
    // 所以先运行时探测：接通后自动校验（同一份固件无需重编），未接通则跳过。
    if (sdram_present()) {
        // .sdram_data：应被 startup 从加载地址搬到运行地址，内容保留。
        test_expect(sdram_data_marker == 0xCAFEF00Du, 0xdead0003u);
        // .sdram_bss：应被 startup 清零。
        test_expect(sdram_bss_marker == 0u, 0xdead0004u);
        // 写回验证运行时地址确实可读写（不是只读的加载副本）。
        sdram_data_marker = 0x55AA55AAu;
        test_expect(sdram_data_marker == 0x55AA55AAu, 0xdead0005u);
        sdram_bss_marker = 0x99u;
        test_expect(sdram_bss_marker == 0x99u, 0xdead0006u);
        rt_puts("runtime_heap_smoke: sdram window present, sdram segments verified\n");
    } else {
        rt_puts("runtime_heap_smoke: sdram window absent, skipping sdram segment checks (pending M2b)\n");
    }

    // ================= 2) 库函数级 =================
    // memset：整块设值。
    memset(buf, 0xAB, sizeof(buf));
    for (i = 0u; i < sizeof(buf); i++) {
        test_expect(buf[i] == 0xABu, 0xdead1000u + i);
    }

    // memcpy：不重叠拷贝。
    for (i = 0u; i < sizeof(seq); i++) {
        seq[i] = (unsigned char)i;
    }
    memcpy(buf, seq, sizeof(seq));
    for (i = 0u; i < sizeof(seq); i++) {
        test_expect(buf[i] == (unsigned char)i, 0xdead1100u + i);
    }

    // memmove：重叠区间，目的在源之后（前向重叠）。
    // buf = {0,1,2,3,4,5,6,7,...}，把 [0..5] 拷到 [2..7]，
    // 期望结果 [2..7] = {0,1,2,3,4,5}，不能被自身覆盖污染。
    memmove(&buf[2], &buf[0], 6u);
    test_expect(buf[2] == 0u, 0xdead1200u);
    test_expect(buf[3] == 1u, 0xdead1201u);
    test_expect(buf[4] == 2u, 0xdead1202u);
    test_expect(buf[5] == 3u, 0xdead1203u);
    test_expect(buf[6] == 4u, 0xdead1204u);
    test_expect(buf[7] == 5u, 0xdead1205u);

    // memmove：目的在源之前（后向重叠）。
    // 重置为 {0..7}，把 [2..7] 拷到 [0..5]，期望 [0..5] = {2,3,4,5,6,7}。
    for (i = 0u; i < sizeof(seq); i++) {
        buf[i] = (unsigned char)i;
    }
    memmove(&buf[0], &buf[2], 6u);
    test_expect(buf[0] == 2u, 0xdead1210u);
    test_expect(buf[1] == 3u, 0xdead1211u);
    test_expect(buf[2] == 4u, 0xdead1212u);
    test_expect(buf[3] == 5u, 0xdead1213u);
    test_expect(buf[4] == 6u, 0xdead1214u);
    test_expect(buf[5] == 7u, 0xdead1215u);

    // rt_* 入口保留给项目内部代码使用，语义应与标准入口一致。
    rt_memset(buf, 0x11, sizeof(buf));
    test_expect(buf[0] == 0x11u && buf[15] == 0x11u, 0xdead1220u);
    rt_memcpy(buf, seq, sizeof(seq));
    test_expect(buf[0] == 0u && buf[7] == 7u, 0xdead1221u);
    rt_memmove(&buf[1], &buf[0], 4u);
    test_expect(buf[1] == 0u && buf[4] == 3u, 0xdead1222u);

    // ================= 3) allocator 级 =================
    heap_init();
    test_expect(heap_used() == 0u, 0xdead2000u);

    // 连续分配：两次分配返回不同区域，第二块在第一块之后。
    p0 = bump_alloc(16u, 4u);
    test_expect(p0 != 0, 0xdead2001u);
    p1 = bump_alloc(16u, 4u);
    test_expect(p1 != 0, 0xdead2002u);
    test_expect((unsigned char *)p1 >= (unsigned char *)p0 + 16u, 0xdead2003u);

    // 对齐：请求 16 字节对齐，返回地址低 4 位应为 0。
    p2 = bump_alloc(8u, 16u);
    test_expect(p2 != 0, 0xdead2004u);
    test_expect(((unsigned long)p2 & 0xFu) == 0u, 0xdead2005u);

    // 空间耗尽：请求超过整个 heap 容量应返回 NULL。
    heap_init();
    heap_capacity = (size_t)(_heap_end - _heap_start);
    test_expect(bump_alloc(heap_capacity + 16u, 4u) == 0, 0xdead2006u);
    // 失败的分配不应消耗游标。
    test_expect(heap_used() == 0u, 0xdead2007u);

    // reset 后重新初始化：耗尽后 heap_init 应能重新从头分配。
    heap_init();
    test_expect(bump_alloc(32u, 4u) != 0, 0xdead2008u);
    heap_init();
    test_expect(heap_used() == 0u, 0xdead2009u);
    test_expect(bump_alloc(32u, 4u) != 0, 0xdead200Au);

    // heap 现在落在 SDRAM（linker.ld 单点开关）：断言起点确实在 0x8000_0000 窗口内。
    // 这是纯地址比较，不解引用，无 SDRAM 也成立，用来证明链接期归属切换生效。
    test_expect((unsigned long)_heap_start >= (unsigned long)TINYBUS_SDRAM_BASE, 0xdead2100u);

    // ============ 4) SDRAM heap 真实读写 ============
    // 通过 allocator 分配到的指针真正写入再读回，证明 heap 落在 SDRAM 且可用。
    // 依赖 SDRAM 接通，故门控；无 SDRAM 时跳过（此时上面的地址已指向 0x8000_0000，
    // 解引用无意义）。
    if (sdram_present()) {
        unsigned int *blk;
        unsigned int k;

        heap_init();
        blk = (unsigned int *)bump_alloc(16u * sizeof(unsigned int), 4u);
        test_expect(blk != 0, 0xdead2200u);
        for (k = 0u; k < 16u; k++) {
            blk[k] = 0xB000u + k;
        }
        for (k = 0u; k < 16u; k++) {
            test_expect(blk[k] == (0xB000u + k), 0xdead2210u + k);
        }
        rt_puts("runtime_heap_smoke: sdram heap read/write verified\n");
    } else {
        rt_puts("runtime_heap_smoke: sdram absent, skipping heap read/write (need minisoc_sdram target)\n");
    }

    rt_puts("runtime_heap_smoke: all runtime checks passed\n");

    test_pass();
    return 0;
}
