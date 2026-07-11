// FreeRTOS timer smoke：覆盖抢占、delay 与每 task critical nesting。
#include "FreeRTOS.h"
#include "task.h"

#include "drivers/gpio.h"
#include "drivers/machine_timer.h"
#include "drivers/mmio.h"

#define COUNTS_PER_TICK (configCPU_CLOCK_HZ / configTICK_RATE_HZ)

static StaticTask_t task_tcb[2];
static StackType_t task_stack[2][512] __attribute__((aligned(16)));
static volatile unsigned int task_a_counter;
static volatile unsigned int task_b_counter;
static volatile unsigned int smoke_phase;

static void fail(unsigned int code) __attribute__((noreturn));

static void fail(unsigned int code)
{
    gpio_write_led(0xfu);
    mmio_write(TINYBUS_TEST_EXIT, code);
    for (;;) {
    }
}

void smoke_task_b(void *argument)
{
    register unsigned int signature __asm__("s1") = 0x24681357u;

    (void)argument;
    for (;;) {
        if (smoke_phase == 0u) {
            task_b_counter++;
            signature += 5u;
            __asm__ volatile ("" : "+r"(signature));
            if (signature != 0x24681357u + task_b_counter * 5u) {
                fail(0xf5010002u);
            }
        }
    }
}

void smoke_task_a(void *argument)
{
    register unsigned int signature __asm__("s1") = 0x13572468u;
    TickType_t delay_start;
    TickType_t delay_end;
    TickType_t critical_tick;
    TickType_t final_start;
    unsigned long long critical_deadline;
    unsigned long long recovery_deadline;

    (void)argument;
    while (task_b_counter == 0u || task_a_counter < 16u) {
        task_a_counter++;
        signature += 3u;
        __asm__ volatile ("" : "+r"(signature));
        if (signature != 0x13572468u + task_a_counter * 3u) {
            fail(0xf5010001u);
        }
    }
    smoke_phase = 1u;

    delay_start = xTaskGetTickCount();
    vTaskDelay(5u);
    delay_end = xTaskGetTickCount();
    if ((delay_end - delay_start) < 5u || (delay_end - delay_start) >= 8u) {
        fail(0xf5010003u);
    }

    taskENTER_CRITICAL();
    critical_tick = xTaskGetTickCount();
    critical_deadline = machine_timer_now() + 2ull * COUNTS_PER_TICK;
    while (machine_timer_now() < critical_deadline) {
    }
    if (xTaskGetTickCount() != critical_tick) {
        fail(0xf5010004u);
    }
    taskEXIT_CRITICAL();

    recovery_deadline = machine_timer_now() + 8ull * COUNTS_PER_TICK;
    while (xTaskGetTickCount() == critical_tick &&
            machine_timer_now() < recovery_deadline) {
    }
    if (xTaskGetTickCount() == critical_tick) {
        fail(0xf5010005u);
    }

    final_start = xTaskGetTickCount();
    while ((xTaskGetTickCount() - final_start) < 1000u) {
    }

    if (task_a_counter == 0u || task_b_counter == 0u) {
        fail(0xf5010006u);
    }
    gpio_write_led(5u);
    mmio_write(TINYBUS_TEST_EXIT, 1u);
    for (;;) {
    }
}

int main(void)
{
    if (COUNTS_PER_TICK == 0u) {
        fail(0xf5010007u);
    }
    if (xTaskCreateStatic(smoke_task_a, "tick-a", 512u, 0,
            tskIDLE_PRIORITY + 1u, task_stack[0], &task_tcb[0]) == 0) {
        fail(0xf5010008u);
    }
    if (xTaskCreateStatic(smoke_task_b, "tick-b", 512u, 0,
            tskIDLE_PRIORITY + 1u, task_stack[1], &task_tcb[1]) == 0) {
        fail(0xf5010009u);
    }

    vTaskStartScheduler();
    fail(0xf501000au);
}
