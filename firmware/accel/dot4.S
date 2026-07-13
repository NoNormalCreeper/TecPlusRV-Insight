    # int dot4_s8(unsigned int packed_a, unsigned int packed_b)
    # a0/a1 直接作为 rs1/rs2，结果按 ABI 返回到 a0。
    .section .text
    .align 2
    .globl dot4_s8
    .type dot4_s8, @function
dot4_s8:
    .insn r CUSTOM_0, 0, 0, a0, a0, a1
    ret
    .size dot4_s8, .-dot4_s8
