// 交通灯 MMIO 上板验收程序，同时供端到端回归复用。
#include "drivers/gpio.h"
#include "drivers/mmio.h"
#include "drivers/traffic_light.h"

#define TRAFFIC_TEST_PATTERN 0x0a55u

int main(void)
{
    unsigned int result;

    traffic_light_write(TRAFFIC_TEST_PATTERN);
    if (traffic_light_read() == TRAFFIC_TEST_PATTERN) {
        gpio_write_led(0x5u);
        result = 1u;
    } else {
        gpio_write_led(0xfu);
        result = 0xdead0040u;
    }

    mmio_write(TINYBUS_TEST_EXIT, result);

    for (;;) {
    }

    return 0;
}
