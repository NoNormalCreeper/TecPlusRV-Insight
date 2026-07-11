// 首任务 smoke：只验证静态 task 创建、参数传递和 canonical frame 首次恢复。
#include "FreeRTOS.h"
#include "task.h"

#include "drivers/gpio.h"
#include "drivers/mmio.h"

static StaticTask_t first_task_tcb;
static StackType_t first_task_stack[512] __attribute__((aligned(16)));

void first_task(void *argument)
{
    unsigned int sp;

    __asm__ volatile ("mv %0, sp" : "=r"(sp));
    if (argument != (void *)0x2468ace0u || (sp & 15u) != 0u) {
        gpio_write_led(0xfu);
        mmio_write(TINYBUS_TEST_EXIT, 0xf3010001u);
    } else {
        gpio_write_led(5u);
        mmio_write(TINYBUS_TEST_EXIT, 1u);
    }

    for (;;) {
    }
}

int main(void)
{
    TaskHandle_t task = xTaskCreateStatic(first_task, "first", 512u,
        (void *)0x2468ace0u, tskIDLE_PRIORITY + 1u,
        first_task_stack, &first_task_tcb);

    if (task == 0) {
        gpio_write_led(0xfu);
        mmio_write(TINYBUS_TEST_EXIT, 0xf3010002u);
        for (;;) {
        }
    }

    vTaskStartScheduler();
    gpio_write_led(0xfu);
    mmio_write(TINYBUS_TEST_EXIT, 0xf3010003u);
    for (;;) {
    }
}
