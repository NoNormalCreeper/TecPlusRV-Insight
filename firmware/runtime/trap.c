// 默认 machine trap 初始化与 dispatcher。
#include "trap.h"

__attribute__((weak))
struct trap_frame *trap_dispatch(struct trap_frame *frame)
{
    return frame;
}

void trap_init(void)
{
    __asm__ volatile ("csrw mtvec, %0" :: "r"(trap_entry));
}

void trap_enable_machine_timer(void)
{
    __asm__ volatile ("csrs mie, %0" :: "r"(1u << 7));
    __asm__ volatile ("csrsi mstatus, 8");
}
