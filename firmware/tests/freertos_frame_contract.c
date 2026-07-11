// 定向检查 FreeRTOS task 初始栈是否就是 runtime 的 canonical trap frame。
#include "FreeRTOS.h"
#include "task.h"

#include "drivers/gpio.h"
#include "drivers/mmio.h"
#include "runtime/trap_frame.h"

static StackType_t task_stack[512] __attribute__((aligned(16)));

static void dummy_task(void *argument)
{
    (void)argument;
    for (;;) {
    }
}

static void fail(unsigned int check)
{
    gpio_write_led(0xfu);
    mmio_write(TINYBUS_TEST_EXIT, 0xf2010000u | check);
    for (;;) {
    }
}

int main(void)
{
    void *const argument = (void *)0x12345678u;
    StackType_t *const initial_sp = pxPortInitialiseStack(
        &task_stack[511], dummy_task, argument);
    const struct trap_frame *const frame =
        (const struct trap_frame *)(const void *)initial_sp;
    unsigned int expected_gp;
    unsigned int expected_tp;

    __asm__ volatile ("mv %0, gp" : "=r"(expected_gp));
    __asm__ volatile ("mv %0, tp" : "=r"(expected_tp));

    if (((unsigned int)initial_sp & 15u) != 0u) {
        fail(1u);
    }
    if (frame->x[2] != (unsigned int)(initial_sp +
            (sizeof(*frame) / sizeof(*initial_sp)))) {
        fail(2u);
    }
    if (frame->x[10] != (unsigned int)argument) {
        fail(3u);
    }
    if (frame->mepc != (unsigned int)dummy_task) {
        fail(4u);
    }
    if ((frame->mstatus & 0x1880u) != 0x1880u) {
        fail(5u);
    }
    if (frame->mcause != 0u || frame->reserved != 0u) {
        fail(6u);
    }
    if (frame->x[1] == 0u || frame->x[3] != expected_gp ||
            frame->x[4] != expected_tp) {
        fail(7u);
    }

    gpio_write_led(5u);
    mmio_write(TINYBUS_TEST_EXIT, 1u);
    for (;;) {
    }
}
