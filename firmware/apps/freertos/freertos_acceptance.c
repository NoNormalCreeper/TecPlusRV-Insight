// FreeRTOS 常用模块与 SDRAM heap 的短时上板综合验收。
#include "FreeRTOS.h"
#include "event_groups.h"
#include "queue.h"
#include "semphr.h"
#include "task.h"
#include "timers.h"

#include "freertos/freertos_heap.h"
#include "tests/testlib.h"

#define WORKER_STACK_WORDS 128u
#define STATIC_WORKER_COUNT 13u
#define WAIT_TICKS 100u
#define QUEUE_LENGTH 4u

struct queue_message {
    unsigned int sequence;
    unsigned int value;
};

static StaticTask_t coordinator_tcb;
static StackType_t coordinator_stack[1024] __attribute__((aligned(16)));
static TaskHandle_t coordinator_handle;

static StaticTask_t watchdog_tcb;
static StackType_t watchdog_stack[256] __attribute__((aligned(16)));

static StaticTask_t worker_tcb[STATIC_WORKER_COUNT];
static StackType_t worker_stack[STATIC_WORKER_COUNT][WORKER_STACK_WORDS]
    __attribute__((aligned(16)));
static unsigned int worker_count;

static StaticQueue_t queue_control;
static unsigned char queue_storage[QUEUE_LENGTH * sizeof(struct queue_message)]
    __attribute__((aligned(4)));
static QueueHandle_t acceptance_queue;

static StaticSemaphore_t semaphore_control;
static SemaphoreHandle_t acceptance_semaphore;
static StaticSemaphore_t mutex_control;
static SemaphoreHandle_t acceptance_mutex;

static StaticEventGroup_t event_control;
static EventGroupHandle_t acceptance_events;

static StaticTimer_t one_shot_timer_control;
static StaticTimer_t periodic_timer_control;
static TimerHandle_t one_shot_timer;
static TimerHandle_t periodic_timer;

static volatile unsigned int preempt_ran;
static volatile unsigned int yield_index;
static volatile unsigned int yield_done;
static volatile unsigned int yield_order[8];
static volatile unsigned int timing_done;
static volatile unsigned int timing_ok;
static volatile unsigned int queue_producer_done;
static volatile unsigned int mutex_low_holds;
static volatile unsigned int mutex_release_low;
static volatile unsigned int mutex_low_done;
static volatile unsigned int mutex_low_priority_after;
static volatile unsigned int mutex_high_done;
static volatile unsigned int mutex_mid_done;
static volatile unsigned int mutex_mid_spins;
static volatile unsigned int one_shot_count;
static volatile unsigned int periodic_count;
static volatile unsigned int dynamic_task_done;

static void stage(const char *name)
{
    uart_puts("  ");
    uart_puts(name);
    uart_puts("\n");
}

static void wait_value(volatile unsigned int *value, unsigned int expected,
    TickType_t timeout, unsigned int code)
{
    TickType_t start = xTaskGetTickCount();

    while (*value != expected) {
        if ((xTaskGetTickCount() - start) >= timeout) {
            test_fail(code);
        }
        vTaskDelay(1u);
    }
}

static TaskHandle_t create_worker(TaskFunction_t entry, const char *name,
    void *argument, UBaseType_t priority)
{
    TaskHandle_t handle;

    if (worker_count >= STATIC_WORKER_COUNT) {
        return 0;
    }
    handle = xTaskCreateStatic(entry, name, WORKER_STACK_WORDS, argument,
        priority, worker_stack[worker_count], &worker_tcb[worker_count]);
    if (handle != 0) {
        worker_count++;
    }
    return handle;
}

static void heap_pattern_fill(unsigned char *block, unsigned int index)
{
    unsigned int *words = (unsigned int *)(void *)block;
    unsigned int sample;

    // 16 个样本从首 word 跨到末 word；subword lane 由独立 SDRAM 回归覆盖。
    for (sample = 0u; sample < 16u; sample++) {
        words[sample * 17u] = 0xa5000000u ^ (index << 8) ^ sample;
    }
}

static void heap_pattern_check(const unsigned char *block, unsigned int index)
{
    const unsigned int *words = (const unsigned int *)(const void *)block;
    unsigned int sample;

    for (sample = 0u; sample < 16u; sample++) {
        if (words[sample * 17u] !=
                (0xa5000000u ^ (index << 8) ^ sample)) {
            test_fail(0xfa060001u);
        }
    }
}

static void heap_acceptance(void)
{
    void *blocks[64];
    void *merged;
    size_t free_before;
    size_t free_after;
    unsigned int failures_before;
    unsigned int block_count;
    unsigned int index;

    stage("heap_5");
    free_before = xPortGetFreeHeapSize();
    failures_before = freertos_malloc_failed_count();
    block_count = 0u;

    while (block_count < 64u) {
        blocks[block_count] = pvPortMalloc(1024u);
        if (blocks[block_count] == 0) {
            break;
        }
        heap_pattern_fill((unsigned char *)blocks[block_count], block_count);
        block_count++;
    }

    test_expect(block_count >= 4u, 0xfa060002u);
    test_expect(block_count < 64u, 0xfa060003u);
    test_expect(freertos_malloc_failed_count() == failures_before + 1u,
        0xfa060004u);

    for (index = 0u; index < block_count; index++) {
        heap_pattern_check((const unsigned char *)blocks[index], index);
    }

    vPortFree(blocks[1]);
    vPortFree(blocks[2]);
    blocks[1] = 0;
    blocks[2] = 0;
    merged = pvPortMalloc(1500u);
    test_expect(merged != 0, 0xfa060005u);
    vPortFree(merged);

    for (index = 0u; index < block_count; index++) {
        if (blocks[index] != 0) {
            vPortFree(blocks[index]);
        }
    }

    free_after = xPortGetFreeHeapSize();
    test_expect(free_after == free_before, 0xfa060006u);
    test_expect(xPortGetMinimumEverFreeHeapSize() < free_before,
        0xfa060007u);
}

static void preempt_worker(void *argument)
{
    (void)argument;
    preempt_ran = 1u;
    vTaskDelete(0);
}

static void yield_worker(void *argument)
{
    unsigned int id = (unsigned int)argument;
    unsigned int iteration;

    for (iteration = 0u; iteration < 4u; iteration++) {
        unsigned int slot;

        taskENTER_CRITICAL();
        slot = yield_index;
        yield_order[slot] = id;
        yield_index = slot + 1u;
        taskEXIT_CRITICAL();
        taskYIELD();
    }
    yield_done++;
    vTaskDelete(0);
}

static void timing_worker(void *argument)
{
    TickType_t deadline = xTaskGetTickCount();
    unsigned int iteration;

    (void)argument;
    timing_ok = 1u;
    for (iteration = 0u; iteration < 3u; iteration++) {
        TickType_t now;

        vTaskDelayUntil(&deadline, 2u);
        now = xTaskGetTickCount();
        if (now < deadline || (now - deadline) > 2u) {
            timing_ok = 0u;
        }
    }
    timing_done = 1u;
    vTaskDelete(0);
}

static void queue_producer(void *argument)
{
    struct queue_message message;

    (void)argument;
    for (message.sequence = 0u; message.sequence < 8u; message.sequence++) {
        message.value = message.sequence ^ 0x5aa55aa5u;
        if (xQueueSend(acceptance_queue, &message, WAIT_TICKS) != pdPASS) {
            test_fail(0xfa020001u);
        }
    }
    queue_producer_done = 1u;
    vTaskDelete(0);
}

static void notification_bits_worker(void *argument)
{
    (void)argument;
    if (xTaskNotify(coordinator_handle, 0x5u, eSetBits) != pdPASS) {
        test_fail(0xfa020002u);
    }
    vTaskDelete(0);
}

static void notification_count_worker(void *argument)
{
    (void)argument;
    xTaskNotifyGive(coordinator_handle);
    xTaskNotifyGive(coordinator_handle);
    xTaskNotifyGive(coordinator_handle);
    vTaskDelete(0);
}

static void semaphore_worker(void *argument)
{
    (void)argument;
    if (xSemaphoreGive(acceptance_semaphore) != pdPASS ||
            xSemaphoreGive(acceptance_semaphore) != pdPASS) {
        test_fail(0xfa030001u);
    }
    vTaskDelete(0);
}

static void mutex_low_worker(void *argument)
{
    (void)argument;
    if (xSemaphoreTake(acceptance_mutex, WAIT_TICKS) != pdPASS) {
        test_fail(0xfa030002u);
    }
    mutex_low_holds = 1u;
    while (mutex_release_low == 0u) {
        vTaskDelay(1u);
    }
    if (xSemaphoreGive(acceptance_mutex) != pdPASS) {
        test_fail(0xfa030003u);
    }
    mutex_low_priority_after = uxTaskPriorityGet(0);
    mutex_low_done = 1u;
    vTaskDelete(0);
}

static void mutex_mid_worker(void *argument)
{
    (void)argument;
    while (mutex_high_done == 0u) {
        mutex_mid_spins++;
        taskYIELD();
    }
    mutex_mid_done = 1u;
    vTaskDelete(0);
}

static void mutex_high_worker(void *argument)
{
    (void)argument;
    if (xSemaphoreTake(acceptance_mutex, WAIT_TICKS) != pdPASS) {
        test_fail(0xfa030004u);
    }
    mutex_high_done = 1u;
    if (xSemaphoreGive(acceptance_mutex) != pdPASS) {
        test_fail(0xfa030005u);
    }
    vTaskDelete(0);
}

static void event_worker(void *argument)
{
    EventBits_t bit = (EventBits_t)(unsigned int)argument;

    (void)xEventGroupSetBits(acceptance_events, bit);
    vTaskDelete(0);
}

static void one_shot_callback(TimerHandle_t timer)
{
    (void)timer;
    one_shot_count++;
}

static void periodic_callback(TimerHandle_t timer)
{
    periodic_count++;
    if (periodic_count == 3u) {
        if (xTimerStop(timer, 0u) != pdPASS) {
            test_fail(0xfa050001u);
        }
    }
}

static void dynamic_lifecycle_worker(void *argument)
{
    (void)argument;
    dynamic_task_done = 1u;
    vTaskDelete(0);
}

static void scheduler_acceptance(void)
{
    unsigned int yield_counts[3] = {0u, 0u, 0u};
    unsigned int index;
    TaskHandle_t low_handle;

    stage("scheduler");
    test_expect(create_worker(preempt_worker, "preempt", 0, 3u) != 0,
        0xfa010001u);
    test_expect(preempt_ran == 1u, 0xfa010002u);

    test_expect(create_worker(yield_worker, "yield-a", (void *)1u, 1u) != 0,
        0xfa010003u);
    test_expect(create_worker(yield_worker, "yield-b", (void *)2u, 1u) != 0,
        0xfa010004u);
    {
        TickType_t start = xTaskGetTickCount();

        while (yield_done != 2u) {
            if ((xTaskGetTickCount() - start) >= WAIT_TICKS) {
                test_fail(0xfa015000u | ((yield_done & 0xfu) << 8) |
                    (yield_index & 0xffu));
            }
            vTaskDelay(1u);
        }
    }
    test_expect(yield_index == 8u, 0xfa010006u);
    for (index = 0u; index < 8u; index++) {
        test_expect(yield_order[index] == 1u || yield_order[index] == 2u,
            0xfa010007u);
        yield_counts[yield_order[index]]++;
    }
    test_expect(yield_counts[1] == 4u && yield_counts[2] == 4u,
        0xfa01000bu);

    test_expect(create_worker(timing_worker, "timing", 0, 1u) != 0,
        0xfa010008u);
    wait_value(&timing_done, 1u, WAIT_TICKS, 0xfa010009u);
    test_expect(timing_ok == 1u, 0xfa01000au);

    stage("queue + notify");
    test_expect(uxQueueMessagesWaiting(acceptance_queue) == 0u,
        0xfa020003u);
    test_expect(create_worker(queue_producer, "producer", 0, 3u) != 0,
        0xfa020004u);
    test_expect(uxQueueSpacesAvailable(acceptance_queue) == 0u,
        0xfa020005u);
    for (index = 0u; index < 8u; index++) {
        struct queue_message message;

        test_expect(xQueueReceive(acceptance_queue, &message, WAIT_TICKS) ==
            pdPASS, 0xfa020006u);
        test_expect(message.sequence == index &&
            message.value == (index ^ 0x5aa55aa5u), 0xfa020007u);
    }
    wait_value(&queue_producer_done, 1u, WAIT_TICKS, 0xfa020008u);

    test_expect(create_worker(notification_bits_worker, "notify-bit", 0,
        1u) != 0, 0xfa020009u);
    {
        uint32_t notified = 0u;
        test_expect(xTaskNotifyWait(0u, 0xffffffffu, &notified, WAIT_TICKS) ==
            pdTRUE && notified == 0x5u, 0xfa02000au);
    }
    test_expect(create_worker(notification_count_worker, "notify-count", 0,
        3u) != 0, 0xfa02000bu);
    test_expect(ulTaskNotifyTake(pdTRUE, WAIT_TICKS) == 3u, 0xfa02000cu);

    stage("semaphore + mutex");
    test_expect(create_worker(semaphore_worker, "semaphore", 0, 1u) != 0,
        0xfa030006u);
    test_expect(xSemaphoreTake(acceptance_semaphore, WAIT_TICKS) == pdPASS,
        0xfa030007u);
    test_expect(xSemaphoreTake(acceptance_semaphore, WAIT_TICKS) == pdPASS,
        0xfa030008u);
    test_expect(xSemaphoreTake(acceptance_semaphore, 0u) == pdFAIL,
        0xfa030009u);

    low_handle = create_worker(mutex_low_worker, "mutex-low", 0, 1u);
    test_expect(low_handle != 0, 0xfa03000au);
    wait_value(&mutex_low_holds, 1u, WAIT_TICKS, 0xfa03000bu);
    test_expect(create_worker(mutex_mid_worker, "mutex-mid", 0, 2u) != 0,
        0xfa03000cu);
    test_expect(create_worker(mutex_high_worker, "mutex-high", 0, 3u) != 0,
        0xfa03000du);
    test_expect(uxTaskPriorityGet(low_handle) == 3u, 0xfa03000eu);
    mutex_release_low = 1u;
    wait_value(&mutex_high_done, 1u, WAIT_TICKS, 0xfa03000fu);
    wait_value(&mutex_low_done, 1u, WAIT_TICKS, 0xfa030010u);
    wait_value(&mutex_mid_done, 1u, WAIT_TICKS, 0xfa030011u);
    test_expect(mutex_low_priority_after == 1u, 0xfa030012u);
    test_expect(mutex_mid_spins != 0u, 0xfa030013u);
}

static void event_timer_acceptance(void)
{
    EventBits_t bits;

    stage("event group");
    test_expect(create_worker(event_worker, "event-a", (void *)0x1u,
        1u) != 0, 0xfa040001u);
    test_expect(create_worker(event_worker, "event-b", (void *)0x2u,
        1u) != 0, 0xfa040002u);
    bits = xEventGroupWaitBits(acceptance_events, 0x3u, pdTRUE, pdTRUE,
        WAIT_TICKS);
    test_expect((bits & 0x3u) == 0x3u, 0xfa040003u);

    stage("software timer");
    test_expect(xTimerStart(one_shot_timer, 0u) == pdPASS, 0xfa050002u);
    test_expect(xTimerStart(periodic_timer, 0u) == pdPASS, 0xfa050003u);
    wait_value(&one_shot_count, 1u, WAIT_TICKS, 0xfa050004u);
    wait_value(&periodic_count, 3u, WAIT_TICKS, 0xfa050005u);
    vTaskDelay(5u);
    test_expect(one_shot_count == 1u && periodic_count == 3u,
        0xfa050006u);
}

static void dynamic_object_acceptance(void)
{
    QueueHandle_t dynamic_queue;
    size_t free_before;
    unsigned int value = 0x12345678u;
    TickType_t start;

    stage("dynamic objects");
    vTaskDelay(20u);
    free_before = xPortGetFreeHeapSize();
    dynamic_queue = xQueueCreate(4u, sizeof(value));
    test_expect(dynamic_queue != 0, 0xfa060008u);
    test_expect(xQueueSend(dynamic_queue, &value, 0u) == pdPASS,
        0xfa060009u);
    value = 0u;
    test_expect(xQueueReceive(dynamic_queue, &value, 0u) == pdPASS &&
        value == 0x12345678u, 0xfa06000au);
    vQueueDelete(dynamic_queue);
    test_expect(xPortGetFreeHeapSize() == free_before, 0xfa06000bu);

    free_before = xPortGetFreeHeapSize();
    test_expect(xTaskCreate(dynamic_lifecycle_worker, "dynamic",
        WORKER_STACK_WORDS, 0, 1u, 0) == pdPASS, 0xfa06000cu);
    wait_value(&dynamic_task_done, 1u, WAIT_TICKS, 0xfa06000du);
    start = xTaskGetTickCount();
    while (xPortGetFreeHeapSize() != free_before) {
        if ((xTaskGetTickCount() - start) >= WAIT_TICKS) {
            test_fail(0xfa06000eu);
        }
        vTaskDelay(1u);
    }
}

static void coordinator_task(void *argument)
{
    (void)argument;
    scheduler_acceptance();
    event_timer_acceptance();
    dynamic_object_acceptance();

    uart_puts("  free heap: ");
    uart_put_dec((unsigned int)xPortGetFreeHeapSize());
    uart_puts(", minimum: ");
    uart_put_dec((unsigned int)xPortGetMinimumEverFreeHeapSize());
    uart_puts("\nfreertos acceptance pass\n");
    uart_flush();
    test_pass();
}

static void watchdog_task(void *argument)
{
    (void)argument;
    vTaskDelay(1500u);
    test_fail(0xfaff0001u);
}

int main(void)
{
    test_banner("freertos acceptance");
    freertos_heap_init();
    heap_acceptance();

    acceptance_queue = xQueueCreateStatic(QUEUE_LENGTH,
        sizeof(struct queue_message), queue_storage, &queue_control);
    test_expect(acceptance_queue != 0, 0xfa000002u);
    acceptance_semaphore = xSemaphoreCreateCountingStatic(2u, 0u,
        &semaphore_control);
    test_expect(acceptance_semaphore != 0, 0xfa000003u);
    acceptance_mutex = xSemaphoreCreateMutexStatic(&mutex_control);
    test_expect(acceptance_mutex != 0, 0xfa000004u);
    acceptance_events = xEventGroupCreateStatic(&event_control);
    test_expect(acceptance_events != 0, 0xfa000005u);
    one_shot_timer = xTimerCreateStatic("one-shot", 3u, pdFALSE, 0,
        one_shot_callback, &one_shot_timer_control);
    test_expect(one_shot_timer != 0, 0xfa000006u);
    periodic_timer = xTimerCreateStatic("periodic", 2u, pdTRUE, 0,
        periodic_callback, &periodic_timer_control);
    test_expect(periodic_timer != 0, 0xfa000007u);

    coordinator_handle = xTaskCreateStatic(coordinator_task, "coordinator",
        1024u, 0, 2u, coordinator_stack, &coordinator_tcb);
    test_expect(coordinator_handle != 0, 0xfa000008u);
    test_expect(xTaskCreateStatic(watchdog_task, "watchdog", 256u, 0, 1u,
        watchdog_stack, &watchdog_tcb) != 0, 0xfa000009u);

    vTaskStartScheduler();
    test_fail(0xfa00000au);
    return 0;
}
