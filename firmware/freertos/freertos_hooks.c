// FreeRTOS profile 的 fatal hooks；错误必须通过 test_exit 可自动判定。
#include "FreeRTOS.h"
#include "task.h"

#include "drivers/mmio.h"
#include "drivers/uart.h"
#include "freertos_heap.h"
#include "runtime/trap_frame.h"

static void freertos_stop(unsigned int code) __attribute__((noreturn));
static volatile unsigned int malloc_failed_count;

static void freertos_stop(unsigned int code)
{
    mmio_write(TINYBUS_TEST_EXIT, code);

    for (;;) {
    }
}

void freertos_assert_fail(const char *file, unsigned int line)
{
    (void)file;
    uart_puts("freertos assert: task=");
    uart_puts(pcTaskGetName(0));
    uart_puts(" line=");
    uart_put_dec(line);
    uart_puts("\n");
    uart_flush();
    freertos_stop(0xf1010000u | (line & 0xffffu));
}

void freertos_task_returned(void)
{
    freertos_stop(0xf1020001u);
}

void freertos_fatal_trap(const struct trap_frame *frame)
{
    uart_puts("freertos fatal: task=");
    uart_puts(pcTaskGetName(0));
    uart_puts(" mepc=");
    uart_put_hex(frame->mepc);
    uart_puts(" mcause=");
    uart_put_hex(frame->mcause);
    uart_puts("\n");
    uart_flush();
    freertos_stop(0xf1030000u | (frame->mcause & 0xffffu));
}

void vApplicationStackOverflowHook(TaskHandle_t task, char *name)
{
    (void)task;
    (void)name;
    freertos_stop(0xf1040001u);
}

void vApplicationMallocFailedHook(void)
{
    // malloc failure 由调用方检查返回值；hook 允许 acceptance 覆盖恢复路径。
    malloc_failed_count++;
}

unsigned int freertos_malloc_failed_count(void)
{
    return malloc_failed_count;
}
