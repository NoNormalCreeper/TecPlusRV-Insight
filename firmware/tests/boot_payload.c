// UART bootloader 的最小可下载 payload。
// 启动后通过 UART 和 LED 给出可见证据，并写 test_exit 供 SoC 仿真收敛。
#include "../drivers/gpio.h"
#include "../drivers/mmio.h"
#include "../drivers/uart.h"

int main(void)
{
    gpio_write_led(0x5u);
    uart_puts("Bad Apple boot payload running.\n");
    uart_puts("Hello Bootloader v1!!!\n");
    uart_flush();
    mmio_write(TINYBUS_TEST_EXIT, 1u);

    for (;;) {
    }

    return 0;
}
