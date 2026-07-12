# Firmware 工作流与构建模型整理设计

## 背景

当前 firmware 构建已经包含四个互斥 profile：

- `baremetal`；
- `dark_irq`；
- `gdb_stub`；
- `freertos`。

每增加一种运行方式，仓库都会同时增加 `build_firmware.sh` 分支、根 Makefile target、入口变量和文档命令。用户现在需要理解 `FIRMWARE_PROFILE`、`FIRMWARE_MAIN`、`GDB_STUB_MAIN`、`FIRMWARE_OUT` 的组合，且同类操作分散在 README、`DEV_FLOW.md`、GDB、FreeRTOS、Bootloader 和 Windows/WSL 文档中。

问题不在于 trap、GDB 或 FreeRTOS 本身没有真实实现，而在于“程序采用什么运行模型”和“用什么方式调试程序”被压进了同一个 profile 维度。GDB 被表现成第四类应用，导致用户入口和内部构建模型一起变复杂。

## 目标

本轮整理必须达到以下结果：

1. 用户把单文件应用放入正确目录后，构建系统能推断其运行模型；
2. GDB 是针对应用的调试动作，不再作为用户需要选择的第四种运行模型；
3. 普通用户只需要指定 `APP`，上传或调试时再指定 `PORT`；当板上 bitstream 的 UART 参数不同于仓库默认值时，允许额外覆盖 `BOOTLOAD_BAUD`；
4. 现有 `FIRMWARE_PROFILE`、`FIRMWARE_MAIN`、`FIRMWARE_OUT` 和专用 Make target 继续可用；
5. 现有仿真、benchmark、ISE export 和 Bootloader 不因用户入口整理而被迫迁移；
6. 新增一份统一的 firmware 编译、上传、调试文档，其他文档不再重复维护完整命令；
7. 构建组合不受支持时必须明确失败，不能静默生成语义错误的 payload。

## 非目标

本轮不做以下工作：

- 不引入 CMake、Meson 或其他新构建依赖；
- 不新增独立的 `firmware/Makefile`；
- 不重写 `scripts/build_firmware.sh` 为另一种语言；
- 不大规模移动 `firmware/tests/` 中的历史验收程序；
- 不修改 RTL、CPU、Bootloader protocol、UART loader 或 linker memory map；
- 不实现 GDB 与 IRQ/FreeRTOS 的 trap dispatcher 合流；
- 不在本轮顺带实现 `Z0/z0`、single-step 或 RSP `O` console packet；
- 不删除任何现有稳定 Make target 或环境变量入口。

## 用户可见目录

新增用户应用目录：

```text
firmware/apps/
├── baremetal/
├── irq/
└── freertos/
```

目录名表达应用运行模型：

| 目录 | 内部 runtime | 语义 |
| --- | --- | --- |
| `baremetal/` | `baremetal` | 不安装通用 IRQ runtime |
| `irq/` | `dark_irq` | DarkRISCV machine trap 与 IRQ 应用 |
| `freertos/` | `freertos` | DarkRISCV FreeRTOS 应用 |

自动推断仅适用于 `firmware/apps/`。`firmware/tests/`、仿真脚本、benchmark 和 ISE export 继续使用显式 `FIRMWARE_PROFILE` 与 `FIRMWARE_MAIN`，避免为目录整理制造无关迁移。

本轮不要求把现有 `firmware/main.c` 移走；它继续作为无参数 `make firmware` 的兼容默认入口。新用户应用和后续示例进入 `firmware/apps/`。

## 用户命令

### 编译

```bash
make firmware APP=baremetal/hello.c
make firmware APP=irq/timer_demo.c
make firmware APP=freertos/queue_demo.c
```

`APP` 接受以下两种等价形式：

```text
baremetal/hello.c
firmware/apps/baremetal/hello.c
```

不提供 `APP` 时，`make firmware` 保持现有行为，构建 `firmware/main.c`。

### 上传并监视

```bash
make firmware-load \
  APP=baremetal/hello.c \
  PORT=COM8 \
  BOOTLOAD_BAUD=115200
```

`firmware-load` 复用现有 `bootload` 和 `scripts/uart_loader.py`，不会产生第二套 loader。
`BOOTLOAD_BAUD` 是硬件相关校准参数而不是应用运行模型；它继续保留，并且必须与当前 bitstream 的 `UART_BAUD` 一致。

### GDB 调试

```bash
make firmware-debug \
  APP=baremetal/hello.c \
  PORT=COM8 \
  BOOTLOAD_BAUD=115200
```

`firmware-debug` 复用现有 Windows GDB 启动、WSL path conversion 和 source substitute-path 行为。

首轮只接受 `baremetal/`：

```text
make firmware-debug APP=irq/timer_demo.c
ERROR: 当前 GDB 调试尚不支持 irq 应用

make firmware-debug APP=freertos/queue_demo.c
ERROR: 当前 GDB 调试尚不支持 freertos 应用
```

## 内部构建模型

将用户概念拆成两个维度：

```text
runtime = baremetal | irq | freertos
debug   = none | gdb
```

本轮合法组合：

| runtime | debug | 支持 |
| --- | --- | --- |
| `baremetal` | `none` | 是 |
| `baremetal` | `gdb` | 是 |
| `irq` | `none` | 是 |
| `irq` | `gdb` | 否，明确失败 |
| `freertos` | `none` | 是 |
| `freertos` | `gdb` | 否，明确失败 |

底层仍使用现有 profile source list：

```text
baremetal + none -> FIRMWARE_PROFILE=baremetal
irq       + none -> FIRMWARE_PROFILE=dark_irq
freertos  + none -> FIRMWARE_PROFILE=freertos
baremetal + gdb  -> GDB runtime source + debug flags
```

现有 `FIRMWARE_PROFILE=gdb_stub` 作为兼容入口保留，并映射到 `baremetal + gdb`。内部脚本仍接受绝对路径的 `FIRMWARE_MAIN` 和显式 `FIRMWARE_OUT`。

## GDB 自动接入

### 首次 stop

用户程序不应再负责安装 GDB trap。GDB build 通过仅在 debug 组合启用的 main wrapper 完成：

```c
extern int __real_main(void);

int __wrap_main(void)
{
    trap_init();
    gdb_breakpoint();
    return __real_main();
}
```

链接时使用 GNU ld `--wrap=main`，使 `startup.S` 对 `main` 的调用进入 wrapper。这样：

- 公共 `startup.S` 不需要新增 profile hook；
- 普通、IRQ、FreeRTOS 启动路径不变；
- firmware 上传后会在用户 `main` 执行前等待 GDB；
- Windows GDB 在 Bootloader 释放 COM 口后能够稳定连接。

如果实际工具链验证表明 `--wrap=main` 无法可靠重写 `startup.S` 的引用，唯一允许的 fallback 是在公共 startup 中调用一个 weak、默认 no-op 的 profile init hook。不得同时保留两套 auto-attach 机制。

### 用户断点接口

新增公共头文件：

```c
#include "runtime/debug.h"

DEBUG_BREAK();
```

其语义为：

- GDB build：执行 `gdb_breakpoint()`；
- 其他 build：编译为空操作。

用户代码不直接包含 `gdb/gdb_stub.h`，也不检查 `GDB_STUB_ACTIVE`。在尚未实现动态 breakpoint 和 single-step 前，`DEBUG_BREAK()` 是用户放置后续 cooperative stop 的稳定接口。

现有直接调用 `trap_init()`、`gdb_breakpoint()` 的程序继续允许构建。它们可能在自动首次 stop 后产生额外 stop，但不会链接失败。

### 日志边界

本轮不提供伪 `DEBUG_LOG()`。当前 GDB session 仍然禁止应用直接向同一 UART 输出普通文本。等 RSP `O` console packet 实现后，再增加跨普通/GDB build 的统一日志接口。

## Makefile 兼容层

根 Makefile 新增：

```text
APP
firmware-load
firmware-debug
```

保留并继续验证：

```text
firmware
bootload
gdb-stub-load
gdb-stub-debug
timer-irq-smoke
timer-irq-load
freertos-smoke
freertos-queue
freertos-acceptance
freertos-load
freertos-acceptance-load
```

旧 target 可以委托给新的公共 recipe，但其参数和行为不得变化。尤其是：

- `bootload` 默认仍进入 serial monitor；
- GDB 上传后必须释放 COM 口；
- Windows GDB 必须加载与上传 payload 同一次构建生成的 ELF；
- `FIRMWARE_OUT` 的隔离与失败清理语义保持不变。

## 输入验证与错误处理

用户入口必须检查：

1. `APP` 是否位于 `firmware/apps/`；
2. 路径是否为现有普通文件；
3. 第一层目录是否为 `baremetal`、`irq` 或 `freertos`；
4. `firmware-load` 与 `firmware-debug` 是否提供 `PORT`；
5. debug/runtime 组合是否受支持；
6. FreeRTOS kernel submodule 是否存在；
7. Windows Python/GDB、`wslpath` 和串口参数是否满足现有约束。

错误信息使用用户目录名和推荐命令，不暴露内部 shell `case` 或 source list。

内部兼容入口不强制要求 `FIRMWARE_MAIN` 位于 `firmware/apps/`，因为仿真、临时 contract 和 benchmark 会使用 `firmware/tests/` 或 `/tmp` 源文件。

## 文档设计

新增：

```text
docs/FIRMWARE_GUIDE.md
```

它是面向用户的唯一完整操作入口，包含：

1. 应用目录选择；
2. 编译、上传和 GDB 命令；
3. 四类产物的用途；
4. bare-metal、IRQ、FreeRTOS 的最小程序结构；
5. `DEBUG_BREAK()` 的使用与当前 GDB 边界；
6. UART baud、Windows/WSL 和 Bootloader 的关系；
7. 常见错误排查。

以下文档保留各自的机制说明，但将重复操作流程缩减为链接：

- `README.md`；
- `docs/DEV_FLOW.md`；
- `docs/WINDOWS_WSL_UART.md`；
- `docs/GDB_USER_GUIDE.md`；
- `docs/GDB_STUB_DEVELOPMENT.md`；
- `docs/FREERTOS_PORT_DESIGN.md`；
- `docs/BOOTLOADER_PROTOCOL.md`。

历史 implementation plan 和 issue draft 不做机械改写，它们记录的是当时真实使用的内部接口。

## 验证

### 构建 contract

至少覆盖：

- 三个 apps 目录正确推断 runtime；
- 短 APP 路径和仓库相对路径等价；
- 非法目录、缺失文件、目录冒充文件明确失败；
- `firmware-debug` 对 IRQ/FreeRTOS 明确失败；
- 旧 `FIRMWARE_PROFILE/FIRMWARE_MAIN/FIRMWARE_OUT` 继续工作；
- `FIRMWARE_PROFILE=gdb_stub` 兼容入口继续产生 DWARF；
- 默认 `make firmware` 行为不变；
- 不同 APP 的输出隔离，失败构建不留下旧产物。

### GDB 端到端

真实 DarkRISCV + UART 仿真至少覆盖：

- 没有显式 `trap_init()` 或 `gdb_breakpoint()` 的普通 bare-metal app 能自动进入首次 stop；
- continue 后进入用户 `main`；
- `DEBUG_BREAK()` 在 GDB build 产生后续 stop；
- `DEBUG_BREAK()` 在普通 build 为 no-op；
- register、memory、continue 和多次 stop 原有行为不回归。

### 回归范围

实施完成后至少运行：

```bash
python3 scripts/test_runner.py run-suite platform --keep-going
python3 scripts/test_runner.py run-suite soc --keep-going
python3 scripts/test_runner.py run-suite freertos --keep-going
python3 scripts/test_runner.py run-suite rv32mi_dark --keep-going
python3 scripts/test_runner.py run-suite rv32i_safe --keep-going
```

涉及 Makefile dry-run contract、GDB profile contract 和 firmware output isolation 的测试必须纳入现有 catalog suite，不能只靠人工执行。

### 物理验收

自动验证通过后，至少给出以下手工流程：

```bash
make firmware-load APP=baremetal/<demo>.c PORT=COM8 BOOTLOAD_BAUD=115200
make firmware-debug APP=baremetal/<demo>.c PORT=COM8 BOOTLOAD_BAUD=115200
```

物理板级验收复用现有 Bootloader 和 Windows GDB。自动仿真不能替代 COM 口所有权、真实 baud 和 Windows source path 的验证。

## 实施顺序

1. 为 APP 路径解析和 runtime/debug 合法组合编写失败 contract；
2. 在现有 builder 中拆分 runtime 与 debug 选择，同时保留旧 profile；
3. 增加统一 Make target 和兼容 alias；
4. 为 GDB 增加 auto-attach wrapper 与 `DEBUG_BREAK()`；
5. 更新 GDB CPU+UART 端到端仿真；
6. 新增 `firmware/apps/` 最小示例；
7. 编写 `FIRMWARE_GUIDE.md` 并收敛相邻文档；
8. 运行完整自动回归并整理上板指引。
