    # machine trap 的唯一汇编入口：先在被中断栈保存 canonical frame，
    # 再切到独立 ISR stack 调用 C dispatcher。
#include "trap_frame.h"

    .section .text.trap
    .balign 16
    .globl trap_entry
    .type trap_entry, @function
trap_entry:
    addi sp, sp, -TRAP_FRAME_SIZE

    # t0 在被用作 scratch 之前必须先保存；x2 保存 trap 前的原始 sp。
    sw   t0, TRAP_X_OFFSET(5)(sp)
    addi t0, sp, TRAP_FRAME_SIZE
    sw   t0, TRAP_X_OFFSET(2)(sp)
    sw   zero, TRAP_X_OFFSET(0)(sp)
    sw   ra, TRAP_X_OFFSET(1)(sp)
    sw   gp, TRAP_X_OFFSET(3)(sp)
    sw   tp, TRAP_X_OFFSET(4)(sp)
    sw   t1, TRAP_X_OFFSET(6)(sp)
    sw   t2, TRAP_X_OFFSET(7)(sp)
    sw   s0, TRAP_X_OFFSET(8)(sp)
    sw   s1, TRAP_X_OFFSET(9)(sp)
    sw   a0, TRAP_X_OFFSET(10)(sp)
    sw   a1, TRAP_X_OFFSET(11)(sp)
    sw   a2, TRAP_X_OFFSET(12)(sp)
    sw   a3, TRAP_X_OFFSET(13)(sp)
    sw   a4, TRAP_X_OFFSET(14)(sp)
    sw   a5, TRAP_X_OFFSET(15)(sp)
    sw   a6, TRAP_X_OFFSET(16)(sp)
    sw   a7, TRAP_X_OFFSET(17)(sp)
    sw   s2, TRAP_X_OFFSET(18)(sp)
    sw   s3, TRAP_X_OFFSET(19)(sp)
    sw   s4, TRAP_X_OFFSET(20)(sp)
    sw   s5, TRAP_X_OFFSET(21)(sp)
    sw   s6, TRAP_X_OFFSET(22)(sp)
    sw   s7, TRAP_X_OFFSET(23)(sp)
    sw   s8, TRAP_X_OFFSET(24)(sp)
    sw   s9, TRAP_X_OFFSET(25)(sp)
    sw   s10, TRAP_X_OFFSET(26)(sp)
    sw   s11, TRAP_X_OFFSET(27)(sp)
    sw   t3, TRAP_X_OFFSET(28)(sp)
    sw   t4, TRAP_X_OFFSET(29)(sp)
    sw   t5, TRAP_X_OFFSET(30)(sp)
    sw   t6, TRAP_X_OFFSET(31)(sp)

    csrr t0, mepc
    sw   t0, TRAP_MEPC_OFFSET(sp)
    csrr t0, mstatus
    sw   t0, TRAP_MSTATUS_OFFSET(sp)
    csrr t0, mcause
    sw   t0, TRAP_MCAUSE_OFFSET(sp)
    sw   zero, 140(sp)

    mv   a0, sp
    la   sp, __trap_isr_stack_top
    call trap_dispatch
    mv   sp, a0

    lw   t0, TRAP_MEPC_OFFSET(sp)
    csrw mepc, t0
    lw   t0, TRAP_MSTATUS_OFFSET(sp)
    csrw mstatus, t0

    lw   ra, TRAP_X_OFFSET(1)(sp)
    lw   gp, TRAP_X_OFFSET(3)(sp)
    lw   tp, TRAP_X_OFFSET(4)(sp)
    lw   t1, TRAP_X_OFFSET(6)(sp)
    lw   t2, TRAP_X_OFFSET(7)(sp)
    lw   s0, TRAP_X_OFFSET(8)(sp)
    lw   s1, TRAP_X_OFFSET(9)(sp)
    lw   a0, TRAP_X_OFFSET(10)(sp)
    lw   a1, TRAP_X_OFFSET(11)(sp)
    lw   a2, TRAP_X_OFFSET(12)(sp)
    lw   a3, TRAP_X_OFFSET(13)(sp)
    lw   a4, TRAP_X_OFFSET(14)(sp)
    lw   a5, TRAP_X_OFFSET(15)(sp)
    lw   a6, TRAP_X_OFFSET(16)(sp)
    lw   a7, TRAP_X_OFFSET(17)(sp)
    lw   s2, TRAP_X_OFFSET(18)(sp)
    lw   s3, TRAP_X_OFFSET(19)(sp)
    lw   s4, TRAP_X_OFFSET(20)(sp)
    lw   s5, TRAP_X_OFFSET(21)(sp)
    lw   s6, TRAP_X_OFFSET(22)(sp)
    lw   s7, TRAP_X_OFFSET(23)(sp)
    lw   s8, TRAP_X_OFFSET(24)(sp)
    lw   s9, TRAP_X_OFFSET(25)(sp)
    lw   s10, TRAP_X_OFFSET(26)(sp)
    lw   s11, TRAP_X_OFFSET(27)(sp)
    lw   t3, TRAP_X_OFFSET(28)(sp)
    lw   t4, TRAP_X_OFFSET(29)(sp)
    lw   t5, TRAP_X_OFFSET(30)(sp)
    lw   t6, TRAP_X_OFFSET(31)(sp)
    lw   t0, TRAP_X_OFFSET(5)(sp)
    lw   sp, TRAP_X_OFFSET(2)(sp)
    mret
    .size trap_entry, .-trap_entry

    .section .bss.trap_stack,"aw",@nobits
    .balign 16
    .globl __trap_isr_stack
__trap_isr_stack:
    .space 1024
    .globl __trap_isr_stack_top
__trap_isr_stack_top:
