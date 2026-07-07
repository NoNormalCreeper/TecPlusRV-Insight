// 裸机 firmware 入口。
// 启动后先打 boot log，再让 CPU 主动自检硬件（ISA / BRAM / MMIO），
// 最后把自检结果写进 test_exit：PASS 写 1，FAIL 写 0xdeadXXXX 错误码。
// 仿真 testbench 和上板 LED 都靠这个结果判断系统是否真的跑通。
#include "drivers/gpio.h"
#include "drivers/mmio.h"
#include "drivers/perf.h"
#include "drivers/uart.h"
#include "tests/selftest.h"

// 演示性能测量用的负载。
// 关键点：循环边界和被加数都来自 volatile，编译器无法在编译期预知它们的值，
// 所以只能老老实实运行期一圈圈跑，测出来的才是循环真实的 cycles / instret。
// （之前用常量求和，被 -Os 直接套等差数列公式算掉了，循环根本没执行。）
static volatile unsigned int g_perf_count = 1000u; // 迭代次数，运行期才读
static volatile unsigned int g_perf_step = 3u;     // 每次累加的步长，运行期才读
static volatile unsigned int g_perf_sink;          // 结果写回，防止整段被当死代码删

static void perf_demo(void)
{
    perf_snapshot_t snap;
    unsigned int i;
    unsigned int n = g_perf_count;
    unsigned int sum = 0u;

    // 用 begin/end 夹住这段循环，测它消耗了多少周期和指令。
    perf_begin(&snap);
    for (i = 0u; i < n; i++) {
        // 每轮都读一次 volatile，逼编译器真正执行加载 + 累加，无法折叠。
        sum += g_perf_step;
    }
    perf_end(&snap);

    g_perf_sink = sum;            // 写回 volatile，确保循环不被当死代码删掉
    perf_report("loop_1000x", &snap);
}

int main(void)
{
    unsigned int result;

    uart_puts("TecPlusRV boot\n");

    // 让 CPU 依次考自己的硬件：任何一项不过都会带回错误码。
    result = selftest_run_all();

    if (result == SELFTEST_PASS) {
        // 全通过：LED 显示 0x5 作为 PASS 的板级可视信号（testbench 也会核对）。
        gpio_write_led(0x5u);
        uart_puts("SELFTEST PASS\n");
        // 自检通过后，演示性能计数器：测一段循环的 cycles / instret / CPI。
        perf_demo();
    } else {
        // 失败：LED 显示 0xF，UART 已经打过具体错误码。
        gpio_write_led(0xFu);
        uart_puts("SELFTEST FAIL\n");
    }

    // 退出前把串口发送队列排空，确保最后一行输出（换行等）完整发出，
    // 不会因为紧接着的 test_exit 让 testbench 提前 $finish 而被截断。
    uart_flush();

    // testbench 监听这个 MMIO 地址：1=PASS，0xdeadXXXX=FAIL+错误码。
    mmio_write(TINYBUS_TEST_EXIT, result);

    // 裸机没有操作系统可返回，main 完成后留在死循环。
    for (;;) {
    }

    return 0;
}
