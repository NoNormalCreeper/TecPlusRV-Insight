// DarkRISCV machine timer IRQ 上板验收程序，同时供端到端仿真复用。
#include "drivers/machine_timer.h"
#include "drivers/mmio.h"
#include "drivers/uart.h"
#include "runtime/trap.h"

#define TIMER_INTERVAL 1000ull
#define SIGNATURE_SEED 0x13572468u
#define SIGNATURE_STEP 0x31u

volatile unsigned int timer_irq_tick_count;
volatile unsigned int timer_loop_count;
static unsigned long long next_compare;

struct trap_frame *trap_dispatch(struct trap_frame *frame)
{
    if (frame->mcause != 0x80000007u) {
        uart_puts("timer irq fail: unexpected mcause=");
        uart_put_hex(frame->mcause);
        uart_putc('\n');
        uart_flush();
        mmio_write(TINYBUS_TEST_EXIT, 0xdead0001u);
        for (;;) {
        }
    }

    timer_irq_tick_count++;
    next_compare += TIMER_INTERVAL;
    machine_timer_set_compare(next_compare);
    return frame;
}

int main(void)
{
    register unsigned int signature asm("s1") = SIGNATURE_SEED;
    unsigned int expected;

    uart_puts("timer irq test start\n");
    uart_flush();
    trap_init();
    next_compare = machine_timer_now() + TIMER_INTERVAL;
    machine_timer_set_compare(next_compare);
    trap_enable_machine_timer();

    while (timer_irq_tick_count < 3u) {
        signature += SIGNATURE_STEP;
        timer_loop_count++;
    }

    expected = SIGNATURE_SEED + timer_loop_count * SIGNATURE_STEP;
    if (signature != expected) {
        uart_puts("timer irq fail: context corrupt\n");
        uart_flush();
        mmio_write(TINYBUS_TEST_EXIT, 0xdead0002u);
        for (;;) {
        }
    }

    // 验收完成后停止新 tick，避免 UART drain 期间继续进入 handler。
    __asm__ volatile ("csrc mie, %0" :: "r"(1u << 7));
    uart_puts("timer irq pass: ticks=");
    uart_put_dec(timer_irq_tick_count);
    uart_puts(" loops=");
    uart_put_dec(timer_loop_count);
    uart_putc('\n');
    uart_flush();
    mmio_write(TINYBUS_TEST_EXIT, 1u);

    for (;;) {
    }
}
