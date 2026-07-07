// SoC 自检测试实现。
// 每个子测试独立返回：成功返回 0，失败返回 0xdeadXXXX 错误码。
// selftest_run_all() 依次跑三类测试，任何一项失败就立刻把错误码带回，
// 这样 testbench / 上板 LED 能直接看到"失败在哪一类、哪一项"。
#include "selftest.h"
#include "drivers/mmio.h"
#include "drivers/uart.h"

// 用 volatile 阻止编译器把下面的算式在编译期直接算好折叠掉；
// 我们要测的是 CPU 运行期真的执行了这些指令，而不是常量传播的结果。
static volatile unsigned int g_zero = 0u;
static volatile unsigned int g_seed = 0x12345678u;

// ---- ISA 指令测试：算术 / 逻辑 / 移位 / 分支 ----
// 目的：确认 PicoRV32 的 rv32i 基本指令在这套 SoC 上执行结果正确。
static unsigned int test_isa(void)
{
    unsigned int a = g_seed;      // 0x12345678，来自 volatile，运行期才知道
    unsigned int b = g_zero + 3u; // 3

    // 加减法
    if ((a + b) != 0x1234567Bu) return 0xdead0101u;
    if ((a - b) != 0x12345675u) return 0xdead0102u;

    // 逻辑运算
    if ((a & 0x0000FFFFu) != 0x00005678u) return 0xdead0103u;
    if ((a | 0xFFFF0000u) != 0xFFFF5678u) return 0xdead0104u;
    if ((a ^ 0xFFFFFFFFu) != 0xEDCBA987u) return 0xdead0105u;

    // 移位（左移 / 逻辑右移）
    if ((a << 4) != 0x23456780u) return 0xdead0106u;
    if ((a >> 8) != 0x00123456u) return 0xdead0107u;

    // 比较分支：确认条件跳转真的按大小走对了分支
    if (!(b < a)) return 0xdead0108u;
    if (b >= a)   return 0xdead0109u;

    // 简单循环累加，顺便压一下分支回跳
    {
        unsigned int i;
        unsigned int sum = 0u;
        for (i = 0u; i < 10u; i++) {
            sum += i;
        }
        if (sum != 45u) return 0xdead010Au; // 0+1+...+9
    }

    return 0u;
}

// ---- BRAM 存储测试：字写 / 读回 / 字节写 ----
// 目的：确认顶层的 BRAM + wstrb 通路正确，firmware 的数据段真的可读写。
static unsigned int test_bram(void)
{
    // 放在栈/静态区的普通变量，读写它们就是在读写 BRAM。
    static volatile unsigned int buf[4];
    unsigned int i;

    // 整字写入一组 pattern，再读回比对
    buf[0] = 0xA5A5A5A5u;
    buf[1] = 0x5A5A5A5Au;
    buf[2] = 0x00000000u;
    buf[3] = 0xFFFFFFFFu;
    for (i = 0u; i < 4u; i++) {
        // 每个元素单独给错误码，方便定位是哪个地址坏了
        unsigned int expect =
            (i == 0u) ? 0xA5A5A5A5u :
            (i == 1u) ? 0x5A5A5A5Au :
            (i == 2u) ? 0x00000000u : 0xFFFFFFFFu;
        if (buf[i] != expect) return 0xdead0201u + i;
    }

    // 字节写测试：只改最低字节，确认 wstrb 只影响目标 byte lane。
    buf[0] = 0xFFFFFFFFu;
    {
        volatile unsigned char *p = (volatile unsigned char *)&buf[0];
        p[0] = 0x12u; // 只写 lane0
        if (buf[0] != 0xFFFFFF12u) return 0xdead0210u;
    }

    return 0u;
}

// ---- MMIO 外设测试：GPIO / UART 状态 / cycle 计数器 ----
// 目的：确认 TinyBus 译码 + 外设寄存器可访问，这是顶层架构的对外接口。
static unsigned int test_mmio(void)
{
    unsigned int c0;
    unsigned int c1;

    // GPIO LED：可写不可回读（当前硬件只锁存到引脚），这里只保证写不挂死。
    mmio_write(TINYBUS_GPIO_LED, 0x0u);
    mmio_write(TINYBUS_GPIO_LED, 0xFu);

    // UART 状态寄存器：bit0 是 TX ready。空闲时应当为就绪(1)，否则说明
    // 状态回读通路或 UART 有问题。
    if ((mmio_read(TINYBUS_UART_STATUS) & 0x1u) == 0u) return 0xdead0301u;

    // cycle 计数器：连续读两次应当递增（顶层每周期 +1）。
    c0 = mmio_read(TINYBUS_CYCLE);
    c1 = mmio_read(TINYBUS_CYCLE);
    if (c1 == c0) return 0xdead0302u; // 没在走 = 计数器没接对

    return 0u;
}

unsigned int selftest_run_all(void)
{
    unsigned int rc;

    uart_puts("[selftest] ISA  ... ");
    rc = test_isa();
    if (rc != 0u) { uart_puts("FAIL "); uart_put_hex(rc); uart_putc('\n'); return rc; }
    uart_puts("ok\n");

    uart_puts("[selftest] BRAM ... ");
    rc = test_bram();
    if (rc != 0u) { uart_puts("FAIL "); uart_put_hex(rc); uart_putc('\n'); return rc; }
    uart_puts("ok\n");

    uart_puts("[selftest] MMIO ... ");
    rc = test_mmio();
    if (rc != 0u) { uart_puts("FAIL "); uart_put_hex(rc); uart_putc('\n'); return rc; }
    uart_puts("ok\n");

    return SELFTEST_PASS;
}
