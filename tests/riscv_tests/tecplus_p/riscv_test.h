// 基于 TecPlusRV MiniSoC 的最薄 riscv-tests 物理环境。
// 目标只有一个：先把 rv32ui 这类基础 RV32I 自检 case 跑起来。
//
// 这里故意不复用官方 p env 的 trap/tohost/特权初始化逻辑，
// 因为当前仓库的稳定契约是：
// 1. 程序从 0x0000_0000 的 BRAM 启动
// 2. PASS/FAIL 通过 TINYBUS_TEST_EXIT 写回 testbench / 板级可观测层
// 3. 第一阶段不把 trap 语义纳入必须验收范围
#ifndef _ENV_TECPUS_P_H
#define _ENV_TECPUS_P_H

#include "../riscv-tests/env/encoding.h"

#define TINYBUS_ADDR_TEST_EXIT 0x10000030

#define RVTEST_RV32U \
  .macro init; \
  .endm

#define RVTEST_RV64U \
  .macro init; \
  .endm

#define TESTNUM gp

#define INIT_XREG \
  li x1, 0;  \
  li x2, 0;  \
  li x3, 0;  \
  li x4, 0;  \
  li x5, 0;  \
  li x6, 0;  \
  li x7, 0;  \
  li x8, 0;  \
  li x9, 0;  \
  li x10, 0; \
  li x11, 0; \
  li x12, 0; \
  li x13, 0; \
  li x14, 0; \
  li x15, 0; \
  li x16, 0; \
  li x17, 0; \
  li x18, 0; \
  li x19, 0; \
  li x20, 0; \
  li x21, 0; \
  li x22, 0; \
  li x23, 0; \
  li x24, 0; \
  li x25, 0; \
  li x26, 0; \
  li x27, 0; \
  li x28, 0; \
  li x29, 0; \
  li x30, 0; \
  li x31, 0;

#define RVTEST_CODE_BEGIN \
  .section .text.init; \
  .align 4; \
  .globl _start; \
  _start:; \
    INIT_XREG; \
    la sp, _stack_top; \
    li TESTNUM, 0; \
    init;

#define RVTEST_CODE_END \
  unimp

#define RVTEST_PASS \
  fence; \
  li TESTNUM, 1; \
  li t0, TINYBUS_ADDR_TEST_EXIT; \
rvtest_pass_loop: \
  sw TESTNUM, 0(t0); \
  j rvtest_pass_loop

#define RVTEST_FAIL \
  fence; \
rvtest_fail_wait: \
  beqz TESTNUM, rvtest_fail_wait; \
  sll TESTNUM, TESTNUM, 1; \
  ori TESTNUM, TESTNUM, 1; \
  li t0, TINYBUS_ADDR_TEST_EXIT; \
rvtest_fail_loop: \
  sw TESTNUM, 0(t0); \
  j rvtest_fail_loop

#define EXTRA_DATA

#define RVTEST_DATA_BEGIN \
  EXTRA_DATA; \
  .align 4; \
  .global begin_signature; \
  begin_signature:

#define RVTEST_DATA_END \
  .align 4; \
  .global end_signature; \
  end_signature:

#endif
