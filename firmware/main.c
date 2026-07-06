#include "drivers/gpio.h"
#include "drivers/mmio.h"
#include "drivers/uart.h"

int main(void)
{
    gpio_write_led(0x5u);
    uart_puts("TecPlusRV firmware skeleton\n");
    mmio_write(TINYBUS_TEST_EXIT, 1u);

    for (;;) {
    }

    return 0;
}

