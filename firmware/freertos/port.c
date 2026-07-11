// TecPlusRV 的 FreeRTOS 薄 port：task 栈直接使用 runtime canonical trap frame。
#include "FreeRTOS.h"
#include "task.h"

#include "drivers/machine_timer.h"
#include "runtime/rt_string.h"
#include "runtime/trap.h"
#include "runtime/trap_frame.h"

struct tcb_prefix {
    volatile StackType_t *pxTopOfStack;
};

extern struct tcb_prefix * volatile pxCurrentTCB;
void freertos_task_returned(void) __attribute__((noreturn));
void freertos_fatal_trap(const struct trap_frame *frame)
    __attribute__((noreturn));

static volatile unsigned int freertos_trap_depth;
static unsigned int counts_per_tick;
static unsigned long long next_compare;

#if portCRITICAL_NESTING_IN_TCB != 1
#error "FreeRTOS critical nesting 必须保存在每个 task 的 TCB 中"
#endif

StackType_t *pxPortInitialiseStack(StackType_t *pxTopOfStack,
    TaskFunction_t pxCode, void *pvParameters)
{
    const unsigned int top =
        ((unsigned int)(pxTopOfStack + 1) & ~15u);
    struct trap_frame *const frame =
        (struct trap_frame *)(top - sizeof(*frame));
    unsigned int gp;
    unsigned int tp;

    rt_memset(frame, 0, sizeof(*frame));
    __asm__ volatile ("mv %0, gp" : "=r"(gp));
    __asm__ volatile ("mv %0, tp" : "=r"(tp));

    frame->x[1] = (unsigned int)freertos_task_returned;
    frame->x[2] = top;
    frame->x[3] = gp;
    frame->x[4] = tp;
    frame->x[10] = (unsigned int)pvParameters;
    frame->mepc = (unsigned int)pxCode;
    // machine mode，MPIE=1；首次 mret 后保持 machine interrupt 开启。
    frame->mstatus = 0x1880u;

    return (StackType_t *)(void *)frame;
}

int freertos_port_in_trap(void)
{
    return freertos_trap_depth != 0u;
}

struct trap_frame *trap_dispatch(struct trap_frame *frame)
{
    pxCurrentTCB->pxTopOfStack = (StackType_t *)(void *)frame;
    freertos_trap_depth++;

    if (frame->mcause == 0x0000000bu) {
        // DarkRISCV 当前仅实现 32-bit 指令；这里只跳过 machine ecall。
        frame->mepc += 4u;
        vTaskSwitchContext();
    } else if (frame->mcause == MACHINE_TIMER_INTERRUPT_CAUSE) {
        next_compare += counts_per_tick;
        machine_timer_set_compare(next_compare);
        if (xTaskIncrementTick() != pdFALSE) {
            vTaskSwitchContext();
        }
    } else {
        freertos_fatal_trap(frame);
    }

    freertos_trap_depth--;
    return (struct trap_frame *)(void *)pxCurrentTCB->pxTopOfStack;
}

BaseType_t xPortStartScheduler(void)
{
    trap_init();
    if (pxCurrentTCB == 0 || pxCurrentTCB->pxTopOfStack == 0) {
        freertos_assert_fail(__FILE__, __LINE__);
        return pdFAIL;
    }

    counts_per_tick = configCPU_CLOCK_HZ / configTICK_RATE_HZ;
    configASSERT(counts_per_tick != 0u);
    next_compare = machine_timer_now() + counts_per_tick;
    machine_timer_set_compare(next_compare);
    // 此处只开 MTIE；首次 mret 根据 task frame 的 MPIE 再打开全局 MIE，
    // 避免 scheduler 启动栈被 timer trap 误存进当前 TCB。
    trap_enable_machine_timer_source();

    trap_restore_frame((struct trap_frame *)(void *)
        pxCurrentTCB->pxTopOfStack);
}

void vPortEndScheduler(void)
{
    // 裸机 target 没有可返回的 host scheduler；走 fatal hook 后永久停机。
    freertos_assert_fail(__FILE__, __LINE__);
    for (;;) {
    }
}
