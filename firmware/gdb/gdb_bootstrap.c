// GDB build 的 main 薄包装：在用户代码运行前安装 trap 并等待 debugger。
#include "gdb/gdb_stub.h"
#include "runtime/trap.h"

int __real_main(void);

int __wrap_main(void)
{
    trap_init();
    gdb_breakpoint();
    return __real_main();
}
