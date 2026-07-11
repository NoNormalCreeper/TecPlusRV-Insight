// TecPlusRV DarkRISCV 的 M-mode-only riscv-tests 环境。
// case 本体及其 mtvec_handler 保持官方语义；这里只替换启动与 PASS/FAIL 出口。
#ifndef _ENV_TECPLUS_M_H
#define _ENV_TECPLUS_M_H

#include "../riscv-tests/env/encoding.h"

#define TINYBUS_ADDR_TEST_EXIT 0x10000030
#define TESTNUM gp

#define RVTEST_RV32M \
  .macro init;       \
  .endm

#define RVTEST_RV64M RVTEST_RV32M

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

#define RVTEST_CODE_BEGIN                 \
  .section .text.init;                    \
  .align 6;                               \
  .weak mtvec_handler;                    \
  .globl _start;                          \
_start:                                   \
  j reset_vector;                         \
  .align 2;                               \
trap_vector:                              \
  la t5, mtvec_handler;                   \
  beqz t5, unhandled_trap;                \
  jr t5;                                  \
unhandled_trap:                           \
  ori TESTNUM, TESTNUM, 1337;             \
  li t5, TINYBUS_ADDR_TEST_EXIT;          \
  sw TESTNUM, 0(t5);                      \
  j unhandled_trap;                       \
reset_vector:                             \
  INIT_XREG;                              \
  la sp, _stack_top;                      \
  li TESTNUM, 0;                          \
  la t0, trap_vector;                     \
  csrw mtvec, t0;                         \
  init;

#define RVTEST_CODE_END \
  unimp

#define RVTEST_PASS                     \
  fence;                                \
  li TESTNUM, 1;                        \
  li t0, TINYBUS_ADDR_TEST_EXIT;        \
1:                                      \
  sw TESTNUM, 0(t0);                    \
  j 1b

#define RVTEST_FAIL                     \
  fence;                                \
1:                                      \
  beqz TESTNUM, 1b;                     \
  sll TESTNUM, TESTNUM, 1;              \
  ori TESTNUM, TESTNUM, 1;              \
  li t0, TINYBUS_ADDR_TEST_EXIT;        \
2:                                      \
  sw TESTNUM, 0(t0);                    \
  j 2b

#define EXTRA_DATA

#define RVTEST_DATA_BEGIN \
  EXTRA_DATA;             \
  .align 4;               \
  .global begin_signature; \
  begin_signature:

#define RVTEST_DATA_END \
  .align 4;             \
  .global end_signature; \
  end_signature:

#endif
