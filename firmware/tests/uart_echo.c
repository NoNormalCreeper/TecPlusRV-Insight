// UART RX/TX end-to-end regression firmware.
// Wait for one received byte, echo it once, then report success.
#include "../drivers/gpio.h"
#include "../drivers/mmio.h"
#include "../drivers/uart.h"

int main(void)
{
    char ch = uart_getc();

    uart_putc(ch);
    uart_flush();
    gpio_write_led(0x5u);
    mmio_write(TINYBUS_TEST_EXIT, 1u);

    for (;;) {
    }

    return 0;
}
