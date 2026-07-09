// Board-facing buzzer example: play a continuous 1 kHz tone at 50 MHz.
#include "../drivers/buzzer.h"
#include "../drivers/gpio.h"

#define BOARD_CLOCK_HZ 50000000u
#define TONE_HZ        1000u

int main(void)
{
    buzzer_start_hz(BOARD_CLOCK_HZ, TONE_HZ);
    gpio_write_led(0x5u);

    for (;;) {
    }

    return 0;
}
