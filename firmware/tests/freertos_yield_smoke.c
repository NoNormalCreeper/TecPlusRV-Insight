// 双任务主动 yield smoke：检查 task context 与 callee-saved register 不串扰。
#include "FreeRTOS.h"
#include "task.h"

#include "drivers/gpio.h"
#include "drivers/mmio.h"

struct task_config {
    unsigned int seed;
    unsigned int step;
    unsigned int done_bit;
    unsigned int failure_code;
};

static StaticTask_t task_tcb[2];
static StackType_t task_stack[2][512] __attribute__((aligned(16)));
static volatile unsigned int done_mask;

static const struct task_config task_config[2] = {
    { 0x13572468u, 3u, 1u, 0xf4010001u },
    { 0x24681357u, 5u, 2u, 0xf4010002u },
};

void yield_task(void *argument)
{
    const struct task_config *const config = argument;
    register unsigned int signature __asm__("s1") = config->seed;
    unsigned int counter;

    for (counter = 1u; counter <= 1000u; counter++) {
        signature += config->step;
        __asm__ volatile ("" : "+r"(signature));
        taskYIELD();
        __asm__ volatile ("" : "+r"(signature));

        if (signature != config->seed + counter * config->step) {
            gpio_write_led(0xfu);
            mmio_write(TINYBUS_TEST_EXIT, config->failure_code);
            for (;;) {
            }
        }
    }

    done_mask |= config->done_bit;
    while (done_mask != 3u) {
        taskYIELD();
    }

    gpio_write_led(5u);
    mmio_write(TINYBUS_TEST_EXIT, 1u);
    for (;;) {
    }
}

int main(void)
{
    unsigned int i;

    for (i = 0u; i < 2u; i++) {
        if (xTaskCreateStatic(yield_task, "yield", 512u,
                (void *)&task_config[i], tskIDLE_PRIORITY + 1u,
                task_stack[i], &task_tcb[i]) == 0) {
            gpio_write_led(0xfu);
            mmio_write(TINYBUS_TEST_EXIT, 0xf4010003u + i);
            for (;;) {
            }
        }
    }

    vTaskStartScheduler();
    gpio_write_led(0xfu);
    mmio_write(TINYBUS_TEST_EXIT, 0xf4010005u);
    for (;;) {
    }
}
