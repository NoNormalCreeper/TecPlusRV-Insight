// GDB stub 的 cooperative ebreak smoke firmware。
#include "drivers/mmio.h"
#include "gdb/gdb_stub.h"
#include "runtime/trap.h"

volatile unsigned int gdb_continue_seen;

__attribute__((naked, noinline, noreturn))
void gdb_pc_continue_target(void)
{
    // 第一条 li 是 G 写 PC 的精确落点；若 stub 错误地再加 4，t0 仍为 0，
    // test_exit 不会触发，从而让端到端仿真超时。
    __asm__ volatile (
        "li t0, 1\n"
        "j 1f\n"
        "1:\n"
        "li t1, 0x10000030\n"
        "sw t0, 0(t1)\n"
        "2: j 2b\n");
}

__attribute__((naked, noinline))
static void gdb_known_context_break(void)
{
    // 仿真里的未初始化 GPR 是 X；先构造确定 context，避免 X 传播到
    // register packet 的 hex table 地址。ra/sp/gp/tp 已由启动和 call 定义。
    __asm__ volatile (
        "li t0, 0\nli t1, 0\nli t2, 0\n"
        "li s0, 0\nli s1, 0\n"
        "li a0, 0\nli a1, 0\nli a2, 0\nli a3, 0\n"
        "li a4, 0\nli a5, 0\nli a6, 0\nli a7, 0\n"
        "li s2, 0\nli s3, 0\nli s4, 0\nli s5, 0\n"
        "li s6, 0\nli s7, 0\nli s8, 0\nli s9, 0\n"
        "li s10, 0\nli s11, 0\n"
        "li t3, 0\nli t4, 0\nli t5, 0\nli t6, 0\n"
        ".globl gdb_stop_site\n"
        "gdb_stop_site:\n"
        "ebreak\n"
        "ret\n");
}

int main(void)
{
    trap_init();
    gdb_known_context_break();

    // 已连接的 GDB 必须在第二次 cooperative stop 时主动收到 stop reply。
    gdb_breakpoint();

    // 正常 cooperative continue 的 fallback；端到端 G/PC 测试会跳到
    // gdb_pc_continue_target，不应落到这里。
    gdb_continue_seen = 1u;
    mmio_write(TINYBUS_TEST_EXIT, 2u);
    for (;;) {
    }
}
