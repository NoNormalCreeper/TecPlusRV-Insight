// TecPlusRV 的 FreeRTOS 薄 port：task 栈直接使用 runtime canonical trap frame。
#include "FreeRTOS.h"
#include "task.h"

#include "runtime/rt_string.h"
#include "runtime/trap_frame.h"

struct tcb_prefix {
    volatile StackType_t *pxTopOfStack;
};

extern struct tcb_prefix * volatile pxCurrentTCB;
void freertos_task_returned(void) __attribute__((noreturn));

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
    // Task 4 接入 trap dispatcher 时改为真实 nesting depth。
    return 0;
}
