// 用户程序接入 cooperative GDB stub 的最小接口。
#ifndef GDB_STUB_H
#define GDB_STUB_H

static inline void gdb_breakpoint(void)
{
    __asm__ volatile ("ebreak" ::: "memory");   // break at entry point
}

#endif
