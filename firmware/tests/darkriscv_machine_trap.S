    # DarkRISCV machine trap core-level 定向测试。
    # Task 1 只驱动外部 IRQ：旧 RTL 错误地等到 JREQ 才会进入 mtvec，
    # 因而必须在下面连续 addi 区间内失败。
    .section .text.init
    .globl _start

_start:
    la   t0, trap_entry_test
    csrw mtvec, t0
    li   t0, (1 << 11)
    csrw mie, t0
    li   t0, (1 << 3)
    csrw mstatus, t0
    li   s0, 0x12345678

straight_line:
    .rept 64
    addi s1, s1, 1
    .endr

wait_forever:
    j wait_forever

    # 固定 trap 地址，testbench 无需解析 ELF symbol。
    .org 0x200
    .align 2
trap_entry_test:
    csrr t0, mcause
    la   t1, observed_cause
    sw   t0, 0(t1)
    csrr t0, mepc
    la   t1, observed_epc
    sw   t0, 0(t1)
    li   t0, 1
    la   t1, trap_count
    sw   t0, 0(t1)
    csrw mie, zero
    mret

    .section .data
    .align 2
trap_count:
    .word 0
observed_cause:
    .word 0
observed_epc:
    .word 0
