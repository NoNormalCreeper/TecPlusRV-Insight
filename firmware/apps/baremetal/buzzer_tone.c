// 板级蜂鸣器 demo：在 50 MHz 时钟下持续播放 1 kHz 音调。
#include "drivers/buzzer.h"
#include "drivers/gpio.h"

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
