# DarkRISCV GDB stub 开发说明

## 目标与边界

本实现是在 TecPlusRV DarkRISCV MiniSoC 上运行的 cooperative GDB Remote Serial Protocol（RSP）stub。它复用现有 UART、machine trap runtime、canonical `trap_frame` 和 UART bootloader，不修改 CPU core，也不新增 RTL debug transport。

首版目标是形成下面的最小闭环：

```text
用户程序执行 ebreak 或发生同步 fault
-> trap_entry 保存完整 integer context
-> gdb_stub 通过 UART 处理 RSP
-> host 读写寄存器或 BRAM/SDRAM
-> continue 恢复原 context
```

当前不提供：

- 运行中异步 Ctrl-C 暂停；
- single-step；
- `Z0/z0` 软件断点；
- hardware breakpoint/watchpoint；
- FreeRTOS task/thread 枚举；
- target XML；
- no-ack mode；
- RSP `O` console output。

## 文件职责

| 文件 | 职责 |
| --- | --- |
| `firmware/gdb/gdb_packet.h/.c` | 无副作用的 RSP framing、checksum 和 hex codec |
| `firmware/gdb/gdb_stub.h` | 用户程序可调用的 `gdb_breakpoint()` |
| `firmware/gdb/gdb_stub.c` | trap dispatcher、command dispatch、寄存器和 memory 语义 |
| `firmware/runtime/trap_entry.S` | 保存和恢复 canonical machine context |
| `firmware/runtime/trap_frame.h` | 汇编与 C 共用的 frame layout |
| `firmware/runtime/trap.c` | `mtvec` 初始化与默认 trap runtime |
| `firmware/tests/gdb_stub_smoke.c` | register/memory/多次 stop/resume 验收 firmware |
| `sim/tb_gdb_stub.v` | DarkRISCV CPU + UART + RSP 端到端仿真 |
| `scripts/gdb_stub_probe.py` | 物理串口 raw RSP probe |
| `scripts/test_gdb_stub_*_contract.sh` | profile、DWARF、Bootloader 与 Windows GDB 命令契约 |

## 构建 profile

`FIRMWARE_PROFILE=gdb_stub` 在普通裸机源文件之外链接：

```text
firmware/runtime/trap_entry.S
firmware/runtime/trap.c
firmware/gdb/gdb_packet.c
firmware/gdb/gdb_stub.c
```

该 profile 还定义：

```text
GDB_STUB_ACTIVE=1
```

并使用 `-g3` 生成 DWARF。debug sections 只保留在 ELF 中，不进入 `.bin`，因此不占用板上 64 KiB BRAM image。profile 继续保留 `-Os`，需要稳定观察的局部状态应优先放在 `volatile` 全局对象中。

独立构建示例：

```bash
FIRMWARE_PROFILE=gdb_stub \
FIRMWARE_MAIN="$PWD/firmware/apps/example.c" \
FIRMWARE_OUT=firmware/build/gdb-example/firmware \
  ./scripts/build_firmware.sh
```

## 用户程序接入契约

用户程序必须先安装 machine trap vector，再执行 cooperative breakpoint：

```c
#include "gdb/gdb_stub.h"
#include "runtime/trap.h"

volatile unsigned int debug_value;

int main(void)
{
    trap_init();
    debug_value = 0x12345678u;
    gdb_breakpoint();
    for (;;) {
    }
}
```

`gdb_breakpoint()` 是带 `memory` clobber 的 inline `ebreak`。它保证编译器不会把 breakpoint 两侧的普通 memory access 跨过停点重排，但不阻止 `-Os` 优化未使用的局部变量。

如果源文件需要同时支持普通运行和 GDB build，可使用：

```c
#if GDB_STUB_ACTIVE
    gdb_breakpoint();
#endif
```

普通 profile 不定义 `GDB_STUB_ACTIVE`，跨 profile 共享代码时建议写成：

```c
#ifdef GDB_STUB_ACTIVE
    gdb_breakpoint();
#endif
```

## trap frame 与 register packet

`trap_entry.S` 在被中断程序的栈上分配 144-byte canonical frame：

| Offset | 内容 |
| ---: | --- |
| `0..124` | `x0..x31`，每项 32-bit |
| `128` | `mepc` |
| `132` | `mstatus` |
| `136` | `mcause` |
| `140` | reserved |

RSP `g/G` 暴露 33 个 32-bit register：

```text
x0, x1, ... x31, pc
```

每个 register 使用 4-byte little-endian hex，因此完整 `g` reply 是 `33 * 8 = 264` 个字符。`G` 写入时忽略 x0，并把 x0 强制恢复为 0。

PC 写入与 continue 的关系：

- breakpoint stop 后直接 `c`：`mepc += 4`，跳过当前 `ebreak`；
- GDB 已显式修改 PC 后 `c`：精确使用新 PC，不再额外加 4；
- `cADDR`：使用对齐且位于 BRAM 的显式地址。

## 首次 stop 与后续 stop

首次启动时，firmware 通常在 GDB 尚未打开 COM 口前已经进入 `gdb_breakpoint()`。stub 此时只等待 host request；GDB 连接后发送 `qSupported`、`?` 等 packet，建立 session。

一旦处理过合法 request，`debugger_attached` 会保持为 1。之后 `continue` 返回用户程序，再次进入 `ebreak` 或同步 fault 时，stub 必须主动发送 stop reply：

```text
breakpoint                 -> S05
illegal instruction        -> S04
misaligned/access fault    -> S0b
```

主动 reply 同样保存在 `last_reply`；host 返回 NACK 时可以重发。这个区别很重要：如果后续 trap 仍等待 host 先发 `?`，GDB 与 target 会互相等待。

## RSP packet 层

parser 支持：

- `$payload#checksum`；
- 合法 packet 的 ACK `+`；
- checksum/overflow 的 NACK `-`；
- host NACK 后重发上一 reply；
- 任意 parser 状态遇到新 `$` 时重新同步；
- 512-byte payload 上限。

当前 command 子集：

| Command | 行为 |
| --- | --- |
| `qSupported...` | `PacketSize=200` |
| `vMustReplyEmpty` | empty reply |
| `Hc0/Hg0/Hc-1/Hg-1` | `OK` |
| `qAttached` | `1` |
| `?` | 当前 stop reason |
| `g/G` | 读写 x0～x31 与 PC |
| `m/M` | 读写允许的 memory window |
| `c/cADDR` | 恢复执行 |
| 未知 command | empty reply |

不要用 NACK 表示“不支持 command”；RSP 要求未知 command 返回空 packet。

## memory 访问边界

stub 只允许：

| Window | 范围 |
| --- | --- |
| BRAM | `0x0000_0000..0x0000_FFFF` |
| SDRAM | `0x8000_0000..0x81FF_FFFF` |

TinyBus MMIO、加速器窗口和其他地址全部返回 `E01`。这样可以避免：

- 读取 UART DATA 意外消费 RX byte；
- 写 GPIO、蜂鸣器等外设产生副作用；
- GDB 扫描不存在的地址导致总线行为不确定。

范围检查使用减法形式，避免 `addr + length` 的 32-bit overflow。`M` 在执行任何 byte write 前先校验完整 payload，非法 hex 不会留下 partial write。

## UART 所有权

GDB session 期间，UART 是 RSP 独占 transport。用户程序不能直接调用 `uart_puts()`、`rt_puts()` 或其他最终写 `uart_putc()` 的输出函数。裸文本会被 GDB 当成 protocol noise；其中的 `$`、`#`、`+`、`-` 还可能破坏 framing。

当前推荐策略：

- GDB build 把诊断状态写进 `volatile` global/struct，由 GDB 读取；
- 普通 build 使用 UART 日志；
- 如果未来必须在 GDB session 输出文本，实现带 ACK/retry 的 RSP `O` packet，不要绕过 stub 直接写 UART；
- 另一条硬件路径是增加独立 UART，但不属于 issue #23 MVP。

## Bootloader 与 Windows GDB

`gdb-stub-load` 不实现新 loader，而是递归调用现有 `bootload`：

```text
WSL build
-> Windows py.exe
-> scripts/uart_loader.py
-> COMx
-> READY/ACK
```

差异只有 `BOOTLOAD_MONITOR_ARG=`：收到 ACK 后 Windows Python 关闭 COM 口。`gdb-stub-debug` 随后通过 WSL Interop 启动 Windows `riscv-none-elf-gdb.exe`，加载同一次构建生成的 ELF，并连接同一个 COM 口。

## 验证入口

聚焦测试：

```bash
python3 scripts/test_runner.py run-case gdb_packet
python3 scripts/test_runner.py run-case gdb_stub_probe
python3 scripts/test_runner.py run-case gdb_stub_load_contract
python3 scripts/test_runner.py run-case gdb_stub_profile_contract
python3 scripts/test_runner.py run-case gdb_stub
```

其中 `gdb_stub` 使用真实 DarkRISCV CPU、BRAM、UART RX/TX 和 firmware，覆盖：

- 长 `qSupported` request；
- ACK/NACK/checksum/resync；
- stop reason；
- register read/write 与 x0；
- PC write；
- BRAM/SDRAM memory；
- 非法 `M` 无 partial write；
- 普通 `c`、显式 PC 后 `c`、`cADDR`；
- 同一 session 的第二次 `ebreak` 主动 stop/resume。

合并前还应运行：

```bash
python3 scripts/test_runner.py run-suite platform --keep-going
python3 scripts/test_runner.py run-suite soc --keep-going
python3 scripts/test_runner.py run-suite rv32mi_dark --keep-going
python3 scripts/test_runner.py run-suite rv32i_safe --keep-going
```

## 已完成的物理验收

2026-07-12 已验证：

- Bootloader 以 115200 baud 上传 GDB firmware 并收到 ACK；
- WSL 启动 Windows xPack GDB 16.3；
- Windows GDB 直接连接 COM8；
- `info registers` 正确读取 33-register context；
- GDB 从 `0x8000_0000` 读取 SDRAM；
- `continue` 恢复执行。

这份证据证明当前 UART/Bootloader/RSP/SDRAM read 的物理闭环。后续 RTL、bitstream、UART baud 或 trap layout 变化后必须重新验收。

## 扩展原则

建议按以下顺序扩展：

1. RSP `O` console packet；
2. `D` detach 和更完整的 session 生命周期；
3. `X` binary memory write；
4. `Z0/z0` software breakpoint；
5. async Ctrl-C；
6. single-step。

不要先实现完整 gdbserver。每增加一个 command，都应同时增加 parser/unit test、CPU+UART 端到端测试和用户文档，并确保 UART MMIO 不被 memory command 暴露。
