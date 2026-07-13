    # DarkRISCV custom-0 DOT4 core-level 定向测试。
    .section .text.init
    .globl _start

_start:
    la   t0, trap_entry_dot4
    csrw mtvec, t0
    li   t0, (1 << 7)
    csrw mie, t0
    csrsi mstatus, 8

    li   a0, 0x04030201
    li   a1, 0x08070605
    .insn r CUSTOM_0, 0, 0, s0, a0, a1
after_irq_dot4:
    addi s1, s1, 1

    li   a0, 0x80ff017f
    li   a1, 0x7f02ff80
    .insn r CUSTOM_0, 0, 0, s2, a0, a1

    # rd=x0 仍应完成 transaction，但不能改变 x0。
    .insn r CUSTOM_0, 0, 0, zero, a0, a1

    li   a0, 0x01010101
    li   a1, 0x01010101
    .insn r CUSTOM_0, 0, 0, s3, a0, a1
    li   a0, 0x02020202
    li   a1, 0x03030303
    .insn r CUSTOM_0, 0, 0, s4, a0, a1

    # funct7=1 未定义，必须进入 illegal-instruction trap。
    .insn r CUSTOM_0, 0, 1, s5, a0, a1
after_illegal:
    sw   s0, 0x100(zero)
    sw   s1, 0x104(zero)
    sw   s2, 0x108(zero)
    sw   s3, 0x10c(zero)
    sw   s4, 0x110(zero)
    sw   zero, 0x114(zero)
    li   t0, 1
    sw   t0, 0x13c(zero)

done:
    j done

    .org 0x200
    .align 2
trap_entry_dot4:
    csrr t0, mcause
    bltz t0, interrupt_trap

    sw   t0, 0x120(zero)
    csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1
    mret

interrupt_trap:
    sw   t0, 0x124(zero)
    csrw mie, zero
    mret
