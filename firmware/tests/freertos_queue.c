// 静态 producer/consumer queue demo；后续 audio queue 可复用同一创建与阻塞范式。
#include "FreeRTOS.h"
#include "queue.h"
#include "task.h"

#include "drivers/gpio.h"
#include "drivers/mmio.h"

#define QUEUE_LENGTH 4u
#define MESSAGE_COUNT 64u

struct demo_message {
    unsigned int sequence;
    unsigned int value;
};

static StaticQueue_t demo_queue_control;
static StackType_t demo_queue_storage[
    (QUEUE_LENGTH * sizeof(struct demo_message) + sizeof(StackType_t) - 1u) /
    sizeof(StackType_t)];
static QueueHandle_t demo_queue;
static volatile unsigned int queue_states;

#define QUEUE_SAW_EMPTY 1u
#define QUEUE_SAW_NONEMPTY 2u
#define QUEUE_SAW_FULL 4u

static StaticTask_t task_tcb[2];
static StackType_t task_stack[2][512] __attribute__((aligned(16)));

static void fail(unsigned int code) __attribute__((noreturn));

static void fail(unsigned int code)
{
    gpio_write_led(0xfu);
    mmio_write(TINYBUS_TEST_EXIT, code);
    for (;;) {
    }
}

void queue_producer_task(void *argument)
{
    struct demo_message message;

    (void)argument;
    for (message.sequence = 0u; message.sequence < MESSAGE_COUNT;
            message.sequence++) {
        message.value = message.sequence ^ 0xa5a55a5au;
        if (xQueueSend(demo_queue, &message, portMAX_DELAY) != pdPASS) {
            fail(0xf6010001u);
        }
        queue_states |= QUEUE_SAW_NONEMPTY;
        if (uxQueueSpacesAvailable(demo_queue) == 0u) {
            queue_states |= QUEUE_SAW_FULL;
        }
        // 开头连续发送 5 条，确保第 5 条在 4-slot queue 满时阻塞；
        // 后续每 3 条 delay，让 consumer 再次把 queue 排空。
        if (message.sequence >= 6u &&
                ((message.sequence - 4u) % 3u) == 2u) {
            vTaskDelay(1u);
        }
    }

    vTaskDelete(0);
}

void queue_consumer_task(void *argument)
{
    struct demo_message message;
    unsigned int expected;

    (void)argument;
    for (expected = 0u; expected < MESSAGE_COUNT; expected++) {
        if (uxQueueMessagesWaiting(demo_queue) == 0u) {
            queue_states |= QUEUE_SAW_EMPTY;
        }
        if (xQueueReceive(demo_queue, &message, portMAX_DELAY) != pdPASS) {
            fail(0xf6010002u);
        }
        if (message.sequence != expected ||
                message.value != (expected ^ 0xa5a55a5au)) {
            fail(0xf6010003u);
        }
    }

    if (queue_states !=
            (QUEUE_SAW_EMPTY | QUEUE_SAW_NONEMPTY | QUEUE_SAW_FULL)) {
        fail(0xf6010008u);
    }

    gpio_write_led(5u);
    mmio_write(TINYBUS_TEST_EXIT, 1u);
    for (;;) {
    }
}

int main(void)
{
    demo_queue = xQueueCreateStatic(QUEUE_LENGTH,
        sizeof(struct demo_message), (uint8_t *)(void *)demo_queue_storage,
        &demo_queue_control);
    if (demo_queue == 0) {
        fail(0xf6010004u);
    }
    if (uxQueueMessagesWaiting(demo_queue) == 0u) {
        queue_states |= QUEUE_SAW_EMPTY;
    }

    if (xTaskCreateStatic(queue_consumer_task, "consumer", 512u, 0,
            tskIDLE_PRIORITY + 1u, task_stack[0], &task_tcb[0]) == 0) {
        fail(0xf6010005u);
    }
    if (xTaskCreateStatic(queue_producer_task, "producer", 512u, 0,
            tskIDLE_PRIORITY + 2u, task_stack[1], &task_tcb[1]) == 0) {
        fail(0xf6010006u);
    }

    vTaskStartScheduler();
    fail(0xf6010007u);
}
