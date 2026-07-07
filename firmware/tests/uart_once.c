// 最小 UART 次数回归：
// 只发送 1 个字符，然后立刻写 test_exit，方便检查同一个 store 是否被重复受理。
#include "../drivers/gpio.h"
#include "../drivers/mmio.h"
#include "../drivers/uart.h"

int main(void)
{
    gpio_write_led(0x5u);
    uart_putc('A');
    mmio_write(TINYBUS_TEST_EXIT, 1u);

    for (;;) {
    }

    return 0;
}
