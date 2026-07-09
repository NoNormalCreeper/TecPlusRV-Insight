// Buzzer MMIO end-to-end regression firmware.
#include "../drivers/buzzer.h"
#include "../drivers/gpio.h"
#include "../drivers/mmio.h"

#define BUZZER_TEST_HALF_PERIOD 4u

int main(void)
{
    volatile unsigned int delay;
    unsigned int result = 1u;

    buzzer_start(BUZZER_TEST_HALF_PERIOD);
    if ((buzzer_get_half_period() != BUZZER_TEST_HALF_PERIOD) ||
        (buzzer_is_enabled() == 0u)) {
        result = 0xdead0050u;
    }

    // Keep the generator enabled long enough for simulation to observe edges.
    for (delay = 0u; delay < 64u; delay++) {
    }

    buzzer_stop();
    if (buzzer_is_enabled() != 0u) {
        result = 0xdead0051u;
    }

    gpio_write_led((result == 1u) ? 0x5u : 0xfu);
    mmio_write(TINYBUS_TEST_EXIT, result);

    for (;;) {
    }

    return 0;
}
