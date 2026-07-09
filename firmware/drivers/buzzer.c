#include "buzzer.h"
#include "mmio.h"

void buzzer_set_half_period(unsigned int clock_ticks)
{
    mmio_write(TINYBUS_BUZZER_PERIOD, clock_ticks);
}

unsigned int buzzer_get_half_period(void)
{
    return mmio_read(TINYBUS_BUZZER_PERIOD);
}

void buzzer_start(unsigned int half_period_ticks)
{
    buzzer_set_half_period(half_period_ticks);
    mmio_write(TINYBUS_BUZZER_CTRL, 1u);
}

void buzzer_start_hz(unsigned int clock_hz, unsigned int tone_hz)
{
    unsigned int half_period;

    if (tone_hz == 0u) {
        buzzer_stop();
        return;
    }

    half_period = (clock_hz / tone_hz) / 2u;
    if (half_period == 0u) {
        buzzer_stop();
        return;
    }

    buzzer_start(half_period);
}

void buzzer_stop(void)
{
    mmio_write(TINYBUS_BUZZER_CTRL, 0u);
}

unsigned int buzzer_is_enabled(void)
{
    return mmio_read(TINYBUS_BUZZER_CTRL) & 1u;
}
