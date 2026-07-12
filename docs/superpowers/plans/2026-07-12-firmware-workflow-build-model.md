# Firmware 工作流与构建模型整理 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让用户通过 `firmware/apps/<runtime>/` 目录和统一 `APP` 命令编译、上传、调试 firmware，同时把 GDB 从运行 profile 中拆成可选调试维度并保持旧入口兼容。

**Architecture:** 根 Makefile 负责把 `APP` 路径解析成用户可见 runtime，现有 `build_firmware.sh` 继续作为唯一 builder，并把 runtime 与 debug 分开选择。GDB debug 通过 ld `--wrap=main` 自动安装 trap 和首次 stop，应用只通过 `runtime/debug.h` 使用可选 cooperative breakpoint。

**Tech Stack:** GNU Make、POSIX shell、RISC-V GNU toolchain、C/assembly、Icarus Verilog、现有 Python test runner。

## Global Constraints

- 所有开发者文本、注释、错误信息和文档使用中文，保留常用英文术语。
- 不引入新依赖，不新增 `firmware/Makefile`，不修改 RTL、Bootloader protocol、UART loader 或 linker memory map。
- `FIRMWARE_PROFILE`、`FIRMWARE_MAIN`、`FIRMWARE_OUT`、现有 Make target 和输出隔离语义必须兼容。
- `firmware/tests/` 和现有内部脚本继续允许显式选择 profile，不强制迁移到 apps 目录。
- `irq + gdb`、`freertos + gdb` 必须明确失败。
- 不实现 GDB/IRQ/FreeRTOS dispatcher 合流、`Z0/z0`、single-step 或 RSP `O` packet。
- 遵照用户要求，本轮修改只记录，不在任务间 commit。

---

### Task 1: runtime/debug 构建轴与 GDB auto-attach

**Files:**
- Modify: `scripts/test_gdb_stub_profile_contract.sh`
- Modify: `scripts/build_firmware.sh`
- Create: `firmware/gdb/gdb_bootstrap.c`
- Create: `firmware/runtime/debug.h`

**Interfaces:**
- Consumes: `FIRMWARE_PROFILE`、`FIRMWARE_MAIN`、`FIRMWARE_OUT`。
- Produces: `FIRMWARE_RUNTIME=baremetal|irq|freertos`、`FIRMWARE_DEBUG=none|gdb`；兼容映射 `gdb_stub -> baremetal+gdb`；`DEBUG_BREAK()`。

- [x] **Step 1: 扩展 profile contract，要求无 GDB 特殊初始化的 app 自动接入**

测试 fixture 只包含公共 debug API：

```c
#include "runtime/debug.h"

#ifndef GDB_STUB_ACTIVE
#error "GDB build 必须定义 GDB_STUB_ACTIVE"
#endif

volatile unsigned int gdb_user_value;

int main(void)
{
    gdb_user_value = 0x12345678u;
    DEBUG_BREAK();
    for (;;) {
    }
}
```

contract 还需用 `nm` 检查 `__wrap_main`、`__real_main`，并分别验证：

```bash
FIRMWARE_RUNTIME=baremetal FIRMWARE_DEBUG=gdb ... build_firmware.sh
FIRMWARE_PROFILE=gdb_stub ... build_firmware.sh
FIRMWARE_RUNTIME=irq FIRMWARE_DEBUG=gdb ... build_firmware.sh
FIRMWARE_RUNTIME=freertos FIRMWARE_DEBUG=gdb ... build_firmware.sh
```

前两项成功，后两项失败且包含“当前 GDB 调试尚不支持”。

- [x] **Step 2: 运行 contract，确认 RED**

Run:

```bash
bash scripts/test_gdb_stub_profile_contract.sh
```

Expected: FAIL，原因是 builder 尚不认识 `FIRMWARE_RUNTIME/FIRMWARE_DEBUG`，且 ELF 不含 `__wrap_main`。

- [x] **Step 3: 在 builder 中拆分 runtime 与 debug**

选择规则：

```sh
FIRMWARE_PROFILE=${FIRMWARE_PROFILE:-}
FIRMWARE_RUNTIME=${FIRMWARE_RUNTIME:-}
FIRMWARE_DEBUG=${FIRMWARE_DEBUG:-none}

if [ -n "$FIRMWARE_PROFILE" ]; then
    case "$FIRMWARE_PROFILE" in
        baremetal) FIRMWARE_RUNTIME=${FIRMWARE_RUNTIME:-baremetal} ;;
        dark_irq)  FIRMWARE_RUNTIME=${FIRMWARE_RUNTIME:-irq} ;;
        freertos)  FIRMWARE_RUNTIME=${FIRMWARE_RUNTIME:-freertos} ;;
        gdb_stub)
            FIRMWARE_RUNTIME=${FIRMWARE_RUNTIME:-baremetal}
            FIRMWARE_DEBUG=gdb
            ;;
        *) echo "未知 FIRMWARE_PROFILE：$FIRMWARE_PROFILE" >&2; exit 1 ;;
    esac
fi
FIRMWARE_RUNTIME=${FIRMWARE_RUNTIME:-baremetal}
```

runtime case 只负责 trap/timer/FreeRTOS source；debug case 只负责：

```sh
EXTRA_CFLAGS="$EXTRA_CFLAGS -g3 -DGDB_STUB_ACTIVE=1"
EXTRA_LDFLAGS="$EXTRA_LDFLAGS -Wl,--wrap=main"
PROFILE_SOURCES="$PROFILE_SOURCES
$REPO_ROOT/firmware/gdb/gdb_packet.c
$REPO_ROOT/firmware/gdb/gdb_stub.c
$REPO_ROOT/firmware/gdb/gdb_bootstrap.c"
```

只有 `baremetal:gdb` 合法。

- [x] **Step 4: 实现 GDB main wrapper 与公共 breakpoint API**

`firmware/gdb/gdb_bootstrap.c`：

```c
#include "gdb/gdb_stub.h"
#include "runtime/trap.h"

int __real_main(void);

int __wrap_main(void)
{
    trap_init();
    gdb_breakpoint();
    return __real_main();
}
```

`firmware/runtime/debug.h`：

```c
#ifndef RUNTIME_DEBUG_H
#define RUNTIME_DEBUG_H

#ifdef GDB_STUB_ACTIVE
#include "gdb/gdb_stub.h"
#define DEBUG_BREAK() gdb_breakpoint()
#else
#define DEBUG_BREAK() ((void)0)
#endif

#endif
```

- [x] **Step 5: 运行 contract，确认 GREEN**

Run:

```bash
bash scripts/test_gdb_stub_profile_contract.sh
```

Expected: `PASS: GDB runtime/debug 组合、自动接入与 DWARF 契约`。

---

### Task 2: APP 目录推断与统一 Make 入口

**Files:**
- Create: `scripts/test_firmware_app_workflow.sh`
- Modify: `Makefile`
- Create: `firmware/apps/baremetal/hello.c`
- Create: `firmware/apps/irq/timer_demo.c`
- Create: `firmware/apps/freertos/queue_demo.c`
- Modify: `scripts/test_catalog.json`

**Interfaces:**
- Consumes: `APP=baremetal/foo.c` 或 `APP=firmware/apps/baremetal/foo.c`。
- Produces: `firmware-load`、`firmware-debug`；内部 `FIRMWARE_RUNTIME` 与绝对 `FIRMWARE_MAIN`。

- [x] **Step 1: 编写 APP workflow contract**

contract 使用 `make --no-print-directory -n` 检查：

```bash
make -n firmware APP=baremetal/hello.c
make -n firmware APP=firmware/apps/irq/timer_demo.c
make -n firmware-load APP=freertos/queue_demo.c PORT=COM8
make -n firmware-debug APP=baremetal/hello.c PORT=COM8
```

分别包含正确绝对 `FIRMWARE_MAIN`、`FIRMWARE_RUNTIME` 和 `FIRMWARE_DEBUG`。以下命令必须失败：

```bash
make -n firmware APP=unknown/demo.c
make -n firmware APP=../tests/smoke.c
make -n firmware APP=baremetal/missing.c
make -n firmware-debug APP=irq/timer_demo.c PORT=COM8
make -n firmware-debug APP=freertos/queue_demo.c PORT=COM8
make -n firmware-load APP=baremetal/hello.c
```

同时验证无 `APP` 的 `make -n firmware` 仍使用 `firmware/main.c`，旧 `gdb-stub-debug GDB_STUB_MAIN=/tmp/app.c` 仍工作。

- [x] **Step 2: 运行 contract，确认 RED**

Run:

```bash
bash scripts/test_firmware_app_workflow.sh
```

Expected: FAIL，原因是 apps 示例和统一 target 尚不存在。

- [x] **Step 3: 增加三个最小应用示例**

- `baremetal/hello.c` 使用 `uart_puts()` 输出并进入循环；
- `irq/timer_demo.c` 复用 `timer_irq_smoke.c` 的最小 timer compare、`trap_dispatch()` 和 `trap_enable_machine_timer()` 模式；
- `freertos/queue_demo.c` 使用两个静态 task 与一个静态 queue，不依赖动态 heap。

示例只证明目录对应的运行模型，不复制完整验收程序。

- [x] **Step 4: 在根 Makefile 解析 APP 并增加统一 target**

Makefile 仅在 `APP` 非空时：

1. 去掉可选的 `firmware/apps/` 前缀；
2. 提取第一段目录；
3. 映射 `baremetal -> baremetal`、`irq -> irq`、`freertos -> freertos`；
4. 将 source 固定解析到 `$(REPO_ROOT)/firmware/apps/...`；
5. 在 recipe 前以 `test -f` 验证普通文件。

公共变量：

```make
APP_INPUT := $(patsubst firmware/apps/%,%,$(strip $(APP)))
APP_KIND := $(firstword $(subst /, ,$(APP_INPUT)))
APP_SOURCE := $(REPO_ROOT)/firmware/apps/$(APP_INPUT)
```

新增入口：

```make
firmware-load:
	# 校验 APP/PORT 后委托 bootload，传递 runtime 与 main

firmware-debug:
	# 仅 baremetal，委托 GDB 上传和 Windows GDB 启动
```

旧 target 不删除，并继续使用同一 bootload/GDB recipe。

- [x] **Step 5: 把 contract 加入 test catalog 并确认 GREEN**

Run:

```bash
bash scripts/test_firmware_app_workflow.sh
python3 scripts/test_runner.py run-case firmware_app_workflow
```

Expected: 两次均 PASS。

---

### Task 3: GDB CPU+UART auto-attach 端到端

**Files:**
- Modify: `firmware/tests/gdb_stub_smoke.c`
- Modify: `sim/tb_gdb_stub.v`

**Interfaces:**
- Consumes: GDB wrapper 的首次 stop、`DEBUG_BREAK()` 后续 stop。
- Produces: auto-attach、continue 进入用户 main、原 register/memory/continue 行为的板级等价仿真证据。

- [x] **Step 1: 先修改 testbench 期望 auto-attach stop**

首个 stop 应位于 `__wrap_main` 的 cooperative breakpoint。testbench 在完成基础 handshake 后发送 `c`，随后等待用户 firmware 中的 known-context stop，再执行现有 register/memory/PC 测试。

firmware 去掉显式 `trap_init()`，后续 cooperative stop 改用：

```c
#include "runtime/debug.h"

DEBUG_BREAK();
```

- [x] **Step 2: 运行 GDB 仿真，确认 RED**

Run:

```bash
python3 scripts/test_runner.py run-case gdb_stub
```

Expected: FAIL，若 Task 1 wrapper 已工作，则原因应是旧 testbench 尚未按两阶段 stop 驱动；若 test 已先改完，则失败点应明确指向 stop 顺序。

- [x] **Step 3: 完成 firmware/testbench 两阶段 stop 驱动**

保持原有覆盖：长 `qSupported`、ACK/NACK、register `g/G`、BRAM/SDRAM `m/M`、非法 write、`c/cADDR` 和第二次主动 stop。只增加首次 wrapper stop，不删除原断言。

- [x] **Step 4: 运行聚焦 GDB 测试**

Run:

```bash
python3 scripts/test_runner.py run-case gdb_packet
python3 scripts/test_runner.py run-case gdb_stub_probe
python3 scripts/test_runner.py run-case gdb_stub_profile_contract
python3 scripts/test_runner.py run-case gdb_stub_load_contract
python3 scripts/test_runner.py run-case gdb_stub
```

Expected: 全部 PASS。

---

### Task 4: 统一 firmware 用户文档与相邻文档收敛

**Files:**
- Create: `docs/FIRMWARE_GUIDE.md`
- Modify: `README.md`
- Modify: `docs/DEV_FLOW.md`
- Modify: `docs/WINDOWS_WSL_UART.md`
- Modify: `docs/GDB_USER_GUIDE.md`
- Modify: `docs/GDB_STUB_DEVELOPMENT.md`
- Modify: `docs/FREERTOS_PORT_DESIGN.md`
- Modify: `docs/BOOTLOADER_PROTOCOL.md`

**Interfaces:**
- Consumes: Task 2 的真实命令和目录。
- Produces: 唯一完整用户入口；其他文档只保留机制和交叉链接。

- [x] **Step 1: 编写文档 contract 的 RED 检查**

在 `scripts/test_firmware_app_workflow.sh` 增加：

```bash
grep -F 'make firmware APP=baremetal/hello.c' docs/FIRMWARE_GUIDE.md
grep -F 'make firmware-load' docs/FIRMWARE_GUIDE.md
grep -F 'make firmware-debug' docs/FIRMWARE_GUIDE.md
grep -F 'DEBUG_BREAK()' docs/FIRMWARE_GUIDE.md
grep -F 'docs/FIRMWARE_GUIDE.md' README.md
```

Run 后应因文档不存在而失败。

- [x] **Step 2: 编写 `FIRMWARE_GUIDE.md`**

内容必须包含：目录选择、compile/load/debug 命令、`.elf/.bin/.mem/.lst`、三类最小应用、`DEBUG_BREAK()`、GDB UART 限制、baud/bitstream 对齐、Windows/WSL 前提和常见错误。

- [x] **Step 3: 收敛相邻文档**

README 提供最短入口；机制文档保留内部变量和历史命令，但在用户操作段优先链接 `FIRMWARE_GUIDE.md`。不机械修改历史 implementation plan 和 issue draft。

- [x] **Step 4: 运行文档与 workflow contract**

Run:

```bash
python3 scripts/test_runner.py run-case firmware_app_workflow
git diff --check
```

Expected: PASS；无 whitespace error。

---

### Task 5: 完整回归与完成审计

**Files:**
- Verify only; only fix files with a reproduced failing test.

**Interfaces:**
- Consumes: Tasks 1-4 全部行为。
- Produces: 对 spec 每项要求的当前证据。

- [x] **Step 1: 运行 build/workflow/GDB 聚焦回归**

```bash
python3 scripts/test_runner.py run-case firmware_app_workflow
python3 scripts/test_runner.py run-case firmware_output_isolation
python3 scripts/test_runner.py run-case gdb_stub_profile_contract
python3 scripts/test_runner.py run-case gdb_stub_load_contract
python3 scripts/test_runner.py run-case gdb_stub
```

- [x] **Step 2: 运行要求的 suite**

```bash
python3 scripts/test_runner.py run-suite platform --keep-going
python3 scripts/test_runner.py run-suite soc --keep-going
python3 scripts/test_runner.py run-suite freertos --keep-going
python3 scripts/test_runner.py run-suite rv32mi_dark --keep-going
python3 scripts/test_runner.py run-suite rv32i_safe --keep-going
```

Expected: 每个 suite 最终 PASS，任何失败必须先以聚焦 failing test 重现再修复。

- [x] **Step 3: 审计兼容性和工作区边界**

检查：

```bash
make --no-print-directory -n firmware
make --no-print-directory -n gdb-stub-debug PORT=COM8
make --no-print-directory -n timer-irq-load PORT=COM8
make --no-print-directory -n freertos-load PORT=COM8
git status --short
git diff --check
```

确认用户原有 `.gitignore`、`docs/diary.md`、issue draft 没有被改写或纳入本轮内容，并记录尚需真实 COM 口执行的两条上板命令，不用自动验证冒充物理验收。
