#include "../drivers/gpio.h"
#include "../drivers/mmio.h"

int main(void)
{
    // 故意不走 UART，用来区分“通用 regression bench”与“board-top smoke bench”。
    gpio_write_led(0x5u);
    mmio_write(TINYBUS_TEST_EXIT, 1u);
    for (;;) {
    }
}
