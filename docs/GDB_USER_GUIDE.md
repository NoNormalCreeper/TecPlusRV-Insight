# TecPlusRV GDB 使用与演示指南

## 你能得到什么

当前 GDB stub 让 Windows GDB 通过板载 UART 调试 DarkRISCV bare-metal firmware。推荐环境分工是：

```text
WSL：源码、RISC-V GCC、firmware 构建、Makefile
Windows：Python、CP2102 COM 口、riscv-none-elf-gdb.exe
FPGA：现有 MiniSoC bootloader bitstream
```

用户应用的目录、普通构建和上传统一见 [`FIRMWARE_GUIDE.md`](FIRMWARE_GUIDE.md)。调试 bare-metal 应用使用：

```bash
make firmware-debug APP=baremetal/hello.c PORT=COM8 BOOTLOAD_BAUD=115200
```

它会依次构建 GDB firmware、复用原有 Bootloader 上传、释放 COM8、启动 Windows GDB、加载 ELF、映射 WSL source path、设置 baud，并执行 `target remote COM8`。

## 当前能力

支持：

- cooperative `ebreak` 和同步 fault stop；
- 在同一 session 中经过多个显式 `DEBUG_BREAK()`；
- 读写 x0～x31 和 PC；
- 读写 64 KiB BRAM 与 32 MiB SDRAM；
- 函数、源码行和 global variable 的 DWARF 信息；
- 修改寄存器或 PC 后继续执行；
- Windows COM 口 9600/115200 等与 bitstream 一致的 baud。

暂不支持：

- 运行中按 Ctrl-C 异步暂停；
- `step`、`next`、single-step；
- `break function`、`Z0/z0` 动态断点；
- watchpoint；
- 用户程序直接向 GDB UART `printf`；
- FreeRTOS thread/task 视图。

## 1. 准备 Windows 工具

### Python 与 pyserial

在 Windows PowerShell 执行：

```powershell
py --version
py -m pip install pyserial
```

WSL 中应能找到 Windows Python：

```bash
command -v py.exe
```

### Windows RISC-V GDB

[安装 Windows xPack GNU RISC-V Embedded GCC](https://xpack-dev-tools.github.io/riscv-none-elf-gcc-xpack/docs/install/)，确认包含：

```text
riscv-none-elf-gdb.exe
```

如果它已经加入 Windows PATH，重新打开 WSL 后检查：

```bash
command -v riscv-none-elf-gdb.exe
```

如果不想修改 PATH，记住它的 WSL 路径，例如：

```text
/mnt/c/Tools/xpack-riscv/bin/riscv-none-elf-gdb.exe
```

## 2. 准备 FPGA 与串口

FPGA 中应已经下载 MiniSoC bootloader bitstream，并满足：

- `CPU_IMPL=1`，即 DarkRISCV；
- `BOOTLOADER_ENABLE=1`；
- `UART_BAUD` 与命令中的 `BOOTLOAD_BAUD` 一致；
- CP2102 由 Windows 持有，设备管理器中能看到 `COMx`；
- PuTTY、串口 monitor、IDE 等没有占用该 COM 口。

更换用户程序只需通过 Bootloader 重新上传，不需要重新综合或下载 bitstream。

## 3. 运行内置 smoke

下面的旧 target 专门运行仓库内部 GDB smoke；调试自己的应用优先使用 `firmware-debug APP=...`。

在 WSL 仓库根目录执行：

```bash
make gdb-stub-debug PORT=COM8 BOOTLOAD_BAUD=115200
```

loader 提示后按下并松开 TEC-PLUS RESET。正常流程是：

```text
bootloader READY
-> 上传 firmware.bin
-> ACK
-> loader 关闭 COM8
-> Windows GDB 打开 firmware.elf
-> GDB 连接 COM8
-> target 停在 __wrap_main 的首次 auto-attach breakpoint
```

执行一次 `continue` 后，内置 smoke 才会进入 `gdb_stop_site`。

如果 GDB 不在 PATH：

```bash
make gdb-stub-debug \
  PORT=COM8 \
  BOOTLOAD_BAUD=115200 \
  WINDOWS_GDB=/mnt/c/Tools/xpack-riscv/bin/riscv-none-elf-gdb.exe
```

连接成功后会出现类似：

```text
Remote debugging using COM8
... in gdb_known_context_break ()
(gdb)
```

## 4. 第一次体验

### 查看当前位置和源码

```gdb
info registers pc sp ra a0
frame
list
x/12i $pc-16
disassemble /r main
```

一站式 target 已自动执行 WSL→Windows 的 `set substitute-path`。如果源码仍找不到，可检查：

```gdb
show substitute-path
info source
```

### 修改寄存器

```gdb
set $a0 = 0x12345678
set $a1 = 0x87654321
info registers a0 a1
```

x0 是硬连线零寄存器，即使通过 `G` packet 尝试写入也会保持为 0。

### 查看栈和 BRAM

```gdb
x/16wx $sp
x/16wx 0x00000000
x/32bx 0x00003000
```

### 读取 SDRAM

```gdb
x/8wx 0x80000000
x/64bx 0x80000000
```

搜索一个 word：

```gdb
find /w 0x80000000, 0x80001000, 0x00010000
```

导出 256 bytes 到 Windows：

```gdb
dump binary memory C:/Temp/tecplus-sdram.bin 0x80000000 0x80000100
```

### 写 BRAM

当前 stub 支持文本 `M` packet，尚不支持 binary `X` packet。最确定的演示方式是：

```gdb
maintenance packet M00003000,4:78563412
x/wx 0x00003000
```

预期：

```text
received: "OK"
0x3000: 0x12345678
```

跨 word 写入：

```gdb
maintenance packet M00003001,5:1122334455
x/8bx 0x00003000
```

TinyBus MMIO 被故意禁止：

```gdb
maintenance packet m10000010,1
```

应返回 `E01`。

### 查看 RSP 日志

下一次连接前可在 GDB 中设置：

```gdb
set remotelogfile C:/Temp/tecplus-rsp.log
set remotelogbase hex
target remote COM8
```

一站式 target 已自动连接；若需要记录完整握手，可先执行 `disconnect`，设置日志后 RESET 并重新运行一站式命令，或把这些命令写进 Windows GDB init 文件。

## 5. 调试自己的用户程序

仓库提供 `firmware/apps/baremetal/gdb_demo.c`。它在第一次 `DEBUG_BREAK()` 前把
`input` 初始化为 7，继续后计算 `output = input * 3`，再在第二次 breakpoint 暴露结果。

一条命令构建、上传并连接：

```bash
make firmware-debug \
  APP=baremetal/gdb_demo.c \
  PORT=COM8 \
  BOOTLOAD_BAUD=115200
```

第一次停住后：

```gdb
p/x gdb_demo_state
set var gdb_demo_state.input = 10
list
continue
```

后续 `DEBUG_BREAK()` 会主动上报新的 `SIGTRAP`，GDB 再次回到 prompt：

```gdb
p/x gdb_demo_state
p/x gdb_demo_state.output
continue
```

如果第一次停住时把 `input` 改为 10，第二次停住时 `output` 应为 30。这同时证明
symbol/DWARF、memory write、cooperative stop 和 continue 路径。

最后一次 `continue` 后程序进入无限循环。因为当前不支持异步 Ctrl-C，要开始新 session，请退出 GDB、重新执行一站式命令并按 RESET。

## 6. UART 与日志策略

GDB 连接期间，同一个 UART 完全属于 RSP。下面这些函数最终都会直接写 UART，不能在 GDB session 中当普通日志使用：

```text
uart_putc
uart_puts
uart_put_hex
uart_put_dec
rt_puts
```

项目当前也没有完整 libc `printf`。即使自行加入 tinyprintf，只要 backend 是同一个 UART，仍会破坏 RSP。

推荐让同一份用户代码支持两种 build：

```c
#include "drivers/uart.h"

#ifdef GDB_STUB_ACTIVE
#define APP_LOG(text) ((void)0)
#else
#define APP_LOG(text) uart_puts(text)
#endif
```

GDB build 使用 `volatile` memory state：

```c
volatile unsigned int debug_phase;
volatile unsigned int debug_error;
```

GDB 中查看：

```gdb
p/x debug_phase
p/x debug_error
```

普通 bare-metal build 则继续使用 UART 日志。未来若要在 GDB session 显示文本，应由 stub 实现 RSP `O` console packet，而不是让应用绕过协议直接写 UART。

## 7. 常见问题

### loader 一直等待 READY

- 确认按的是 RESET，不是 CONFIG；
- 确认 bitstream 启用了 Bootloader；
- 确认 COM 口和 baud；
- 关闭其他串口程序。

### 上传 ACK 后 GDB 无法打开 COM8

- 确认上传命令没有 `--monitor`；
- 用户应用使用 `firmware-debug`；内部 smoke 仍可使用 `gdb-stub-debug`；不要用会进入 serial monitor 的普通 `bootload`；
- 检查 Windows Python 进程是否已经退出；
- 确认 CP2102 没有 attach 给 WSL。

### 找不到 Windows GDB

```bash
command -v riscv-none-elf-gdb.exe
```

找不到时显式设置 `WINDOWS_GDB=/mnt/c/.../riscv-none-elf-gdb.exe`。

### GDB 找不到源码

```gdb
show substitute-path
info source
```

确认用户源文件位于 `firmware/apps/baremetal/`，并使用最新 `firmware-debug`；target 会自动把仓库根路径映射为 `wslpath -m` 生成的 Windows 路径。

### `warning: could not convert ... CP1252 ...`

xPack GDB 可能在 Windows host encoding 下打印转换 warning。本轮真实测试中它不影响 symbol、register、SDRAM 和 continue。若源码路径或变量名包含非 ASCII 字符，优先改用 ASCII 路径和 symbol 名，避免把 encoding warning 与 RSP 故障混为一谈。

### `break main`、`step` 或 Ctrl-C 不工作

这是当前协议子集的已知边界。请在源码中显式放置 `DEBUG_BREAK()`；多个 cooperative breakpoint 已支持，但动态 breakpoint、single-step 和运行中异步暂停尚未实现。

### `continue` 后一直显示 `Continuing`

如果后续代码没有再次执行 `DEBUG_BREAK()` 或发生 fault，这是正常现象。当前不能通过 Ctrl-C 把正在运行的程序异步拉回 stub；退出 GDB、RESET 并重新上传即可开始新 session。

## 8. 本地回归

修改用户程序通常先跑 profile 与核心仿真：

```bash
python3 scripts/test_runner.py run-case gdb_stub_profile_contract
python3 scripts/test_runner.py run-case gdb_stub
```

修改 stub、trap、UART 或 build flow 时使用开发文档中的完整合并前回归。实现细节见 [`GDB_STUB_DEVELOPMENT.md`](GDB_STUB_DEVELOPMENT.md)。
