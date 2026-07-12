// 最小 FreeRTOS 静态 queue 应用：producer 发送计数，consumer 显示到 LED。
#include "FreeRTOS.h"
#include "queue.h"
#include "task.h"

#include "drivers/gpio.h"

static StaticQueue_t queue_control;
static unsigned char queue_storage[sizeof(unsigned int)];
static QueueHandle_t demo_queue;
static StaticTask_t task_control[2];
static StackType_t task_stack[2][256] __attribute__((aligned(16)));

static void producer(void *argument)
{
    unsigned int value = 0u;

    (void)argument;
    for (;;) {
        value++;
        xQueueSend(demo_queue, &value, portMAX_DELAY);
        vTaskDelay(pdMS_TO_TICKS(500u));
    }
}

static void consumer(void *argument)
{
    unsigned int value;

    (void)argument;
    for (;;) {
        if (xQueueReceive(demo_queue, &value, portMAX_DELAY) == pdPASS) {
            gpio_write_led(value & 0xfu);
        }
    }
}

int main(void)
{
    demo_queue = xQueueCreateStatic(1u, sizeof(unsigned int), queue_storage,
        &queue_control);
    xTaskCreateStatic(consumer, "consumer", 256u, 0,
        tskIDLE_PRIORITY + 1u, task_stack[0], &task_control[0]);
    xTaskCreateStatic(producer, "producer", 256u, 0,
        tskIDLE_PRIORITY + 1u, task_stack[1], &task_control[1]);
    vTaskStartScheduler();

    for (;;) {
    }
}
