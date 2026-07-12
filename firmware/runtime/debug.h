// 应用可安全跨普通/GDB build 使用的最小调试接口。
#ifndef RUNTIME_DEBUG_H
#define RUNTIME_DEBUG_H

#ifdef GDB_STUB_ACTIVE
#include "gdb/gdb_stub.h"
#define DEBUG_BREAK() gdb_breakpoint()
#else
#define DEBUG_BREAK() ((void)0)
#endif

#endif
