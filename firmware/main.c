// 裸机 firmware 的最小入口。
// 当前只做三件事：写 LED、从 UART 打一行字符串、写 test_exit 告诉仿真结束。
// 后续真正跑 SoC 时，可以从这里逐步替换成更完整的板级初始化和应用逻辑。
#include "drivers/gpio.h"
#include "drivers/mmio.h"
#include "drivers/uart.h"

int main(void)
{
    gpio_write_led(0x5u);
    uart_puts("TecPlusRV firmware skeleton\n");
    // testbench 监听这个 MMIO 地址；写 1 表示当前 smoke 程序按预期跑完。
    mmio_write(TINYBUS_TEST_EXIT, 1u);

    // 裸机没有操作系统可返回，main 完成后留在死循环。
    for (;;) {
    }

    return 0;
}
