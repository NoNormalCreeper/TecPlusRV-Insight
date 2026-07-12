// 最小 machine timer IRQ 应用。
#include "drivers/machine_timer.h"
#include "drivers/gpio.h"
#include "runtime/trap.h"

#define TIMER_INTERVAL 50000000ull

static unsigned long long next_compare;
volatile unsigned int timer_ticks;

struct trap_frame *trap_dispatch(struct trap_frame *frame)
{
    if (frame->mcause == 0x80000007u) {
        timer_ticks++;
        gpio_write_led(timer_ticks & 0xfu);
        next_compare += TIMER_INTERVAL;
        machine_timer_set_compare(next_compare);
    }
    return frame;
}

int main(void)
{
    trap_init();
    next_compare = machine_timer_now() + TIMER_INTERVAL;
    machine_timer_set_compare(next_compare);
    trap_enable_machine_timer();

    for (;;) {
    }
}
