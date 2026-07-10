    # DarkRISCV machine trap core-level 定向测试。
    # testbench 依次验证 MEI/MTI 优先级、ecall、ebreak 和 timer IRQ。
    .section .text.init
    .globl _start

_start:
    la   t0, trap_entry_test
    ori  t0, t0, 3
    csrw mtvec, t0
    csrw mie, zero
    csrw mstatus, zero
    li   s0, 0x12345678

disabled_window:
    .rept 8
    nop
    .endr

    li   t0, -1
    csrw mie, t0
    li   t0, -1
    csrw mstatus, t0

straight_line:
    .rept 32
    addi s1, s1, 1
    .endr

    ecall
after_ecall:
    ebreak
after_ebreak:
    li   t0, (1 << 7)
    csrw mie, t0
    csrsi mstatus, 8

timer_straight_line:
    .rept 16
    addi s2, s2, 1
    .endr

done:
    j done

    # 固定 trap 地址，testbench 无需解析 ELF symbol。
    .org 0x200
    .align 2
trap_entry_test:
    csrr t0, mcause
    csrr t2, mscratch
    slli t3, t2, 2
    la   t1, observed_cause
    add  t1, t1, t3
    sw   t0, 0(t1)
    csrr t4, mepc
    la   t1, observed_epc
    add  t1, t1, t3
    sw   t4, 0(t1)
    addi t2, t2, 1
    csrw mscratch, t2
    la   t1, trap_count
    sw   t2, 0(t1)

    # 同步 trap 跳过当前指令；interrupt 保持 mepc 不变。
    srli t5, t0, 31
    xori t5, t5, 1
    slli t5, t5, 2
    add  t4, t4, t5
    csrw mepc, t4
    mret

    .section .data
    .align 2
trap_count:
    .word 0
observed_cause:
    .word 0, 0, 0, 0
observed_epc:
    .word 0, 0, 0, 0
