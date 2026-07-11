// machine trap 的 canonical register frame；汇编与 C 共用这些 offset。
#ifndef TRAP_FRAME_H
#define TRAP_FRAME_H

#define TRAP_X_OFFSET(n) ((n) * 4)
#define TRAP_MEPC_OFFSET 128
#define TRAP_MSTATUS_OFFSET 132
#define TRAP_MCAUSE_OFFSET 136
#define TRAP_FRAME_SIZE 144

#ifndef __ASSEMBLER__
struct trap_frame {
    unsigned int x[32];
    unsigned int mepc;
    unsigned int mstatus;
    unsigned int mcause;
    // 基础 profile 固定为 0；FreeRTOS 后续可专用于 critical nesting。
    unsigned int reserved;
};

_Static_assert(sizeof(struct trap_frame) == TRAP_FRAME_SIZE,
    "trap_frame size 必须与汇编入口一致");
_Static_assert(__builtin_offsetof(struct trap_frame, mepc) == TRAP_MEPC_OFFSET,
    "trap_frame mepc offset 必须与汇编入口一致");
_Static_assert(__builtin_offsetof(struct trap_frame, mstatus) == TRAP_MSTATUS_OFFSET,
    "trap_frame mstatus offset 必须与汇编入口一致");
_Static_assert(__builtin_offsetof(struct trap_frame, mcause) == TRAP_MCAUSE_OFFSET,
    "trap_frame mcause offset 必须与汇编入口一致");

struct trap_frame *trap_dispatch(struct trap_frame *frame);
#endif

#endif
