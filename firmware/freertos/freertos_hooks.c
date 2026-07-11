// FreeRTOS profile 的 fatal hooks；错误必须通过 test_exit 可自动判定。
#include "FreeRTOS.h"
#include "task.h"

#include "drivers/mmio.h"
#include "runtime/trap_frame.h"

static void freertos_stop(unsigned int code) __attribute__((noreturn));

static void freertos_stop(unsigned int code)
{
    mmio_write(TINYBUS_TEST_EXIT, code);

    for (;;) {
    }
}

void freertos_assert_fail(const char *file, unsigned int line)
{
    (void)file;
    freertos_stop(0xf1010000u | (line & 0xffffu));
}

void freertos_task_returned(void)
{
    freertos_stop(0xf1020001u);
}

void freertos_fatal_trap(const struct trap_frame *frame)
{
    freertos_stop(0xf1030000u | (frame->mcause & 0xffffu));
}

void vApplicationStackOverflowHook(TaskHandle_t task, char *name)
{
    (void)task;
    (void)name;
    freertos_stop(0xf1040001u);
}
