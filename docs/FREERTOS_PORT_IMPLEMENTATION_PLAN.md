# DarkRISCV FreeRTOS Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 DarkRISCV MiniSoC 上建立可复用、可自动验证的 FreeRTOS firmware profile，并依次交付首任务、主动 yield、timer 抢占/延时和静态 queue demo。

**Architecture:** 固定 FreeRTOS-Kernel V11.3.0，只复用官方 `tasks.c`、`queue.c`、`list.c` 与公开 API。TecPlusRV 专用薄 port 把 FreeRTOS TCB 的 `pxTopOfStack` 映射到现有 canonical `trap_frame`，所有 tick、`ecall` 和 fault 继续经过唯一 `trap_entry`/`trap_dispatch()` 路径。

**Tech Stack:** FreeRTOS-Kernel V11.3.0、RV32I/Zicsr、DarkRISCV、C11 freestanding、RISC-V GCC、Verilog-2001、Icarus Verilog、TinyBus machine timer、现有 JSON test catalog。

## Global Constraints

- 只支持 `CPU_IMPL=1` 的 DarkRISCV；PicoRV32 和默认 `baremetal` profile 行为不得改变。
- 固定 `third_party/FreeRTOS-Kernel` git submodule 到 tag `V11.3.0` 对应 commit；不得跟踪上游 `main`。
- 不链接官方 RISC-V `portASM.S`，不得新增第二个 `mtvec` 入口或第二套 context layout。
- canonical `struct trap_frame` 的字段与 offset 保持不变；`reserved` 首轮保持 0。
- `portCRITICAL_NESTING_IN_TCB=1`；critical nesting 不放入公共 frame。
- 首轮只编译 `tasks.c`、`queue.c`、`list.c`；不开 dynamic allocation、software timer、event group、stream buffer、tickless idle、FPU/VPU。
- task、TCB、queue storage 全部静态分配；首轮 task stack 放 BRAM 并显式 16-byte 对齐。
- 仿真构建使用 `FREERTOS_CPU_CLOCK_HZ=1000000`，上板构建默认 `50000000`；tick rate 固定 1000 Hz。
- timer deadline 使用累计 `next_compare += counts_per_tick`，不得改为 `now + interval`。
- 所有新增开发者文本、注释、测试输出与 commit message 使用中文，保留 FreeRTOS、trap、frame、tick、queue 等常用术语。
- 每个任务严格执行 RED → GREEN；当前 gate 未通过，不进入下一任务。
- 不修改或提交当前无关的 `.gitignore`、`docs/diary.md`、`docs/issue_drafts/2026-07-07-sdram-runtime-bootloader-issues.md`。

---

## File Structure

### 新增文件

- `.gitmodules` / `third_party/FreeRTOS-Kernel`：固定的官方 kernel submodule。
- `firmware/freertos/FreeRTOSConfig.h`：全仓唯一 kernel 配置。
- `firmware/freertos/portmacro.h`：RV32I 类型、yield、critical 与 alignment 契约。
- `firmware/freertos/compat/stdlib.h`、`string.h`：无 libc headers 工具链所需的最小标准声明，不提供 malloc/newlib。
- `firmware/freertos/port.c`：初始 frame、scheduler、tick/yield trap 分发。
- `firmware/freertos/freertos_hooks.c`：assert、stack overflow 与 task return fatal hook。
- `firmware/tests/freertos_build_contract.c`：profile/header/build contract。
- `firmware/tests/freertos_frame_contract.c`：初始 canonical frame 定向检查。
- `firmware/tests/freertos_first_task.c`：公共 restore 入口与首任务启动。
- `firmware/tests/freertos_yield_smoke.c`：双任务 `ecall` yield。
- `firmware/tests/freertos_smoke.c`：timer 抢占、delay、critical section。
- `firmware/tests/freertos_queue.c`：静态 producer/consumer queue demo。
- `sim/tb_freertos_smoke.v`：FreeRTOS 通用 MiniSoC bench 与 trap 观测。
- `scripts/test_freertos_build_contract.sh`：kernel revision、profile、ELF/BRAM size 检查。

### 修改文件

- `firmware/runtime/trap_entry.S`、`firmware/runtime/trap.h`：暴露公共 `trap_restore_frame()`。
- `scripts/build_firmware.sh`：加入 `freertos` profile、kernel include/source、section GC 与独立输出。
- `sim/run_sim.sh`：加入 frame/first/yield/smoke/queue 仿真入口。
- `scripts/test_catalog.json`：加入 `freertos` suite，并在最终 gate 接入 `local/all`。
- `Makefile`：加入 `freertos-smoke`、`freertos-queue`、`freertos-load`。
- `scripts/export_ise_project.sh`：导出 kernel/port/profile 所需文件并生成 FreeRTOS firmware。
- `docs/DEV_FLOW.md`、`docs/darkriscv_wrapper_summary.md`、`docs/FREERTOS_PORT_DESIGN.md`：记录实际命令、资源与验证结论。

---

### Task 0: 重新确认公共 machine trap Gate 0

**Files:**
- Read: `docs/darkriscv_wrapper_summary.md:361-378`
- Test: `scripts/test_catalog.json`

**Interfaces:**
- Consumes: 当前 `dark_irq`、machine timer、canonical frame、2026-07-11 ISE/上板证据。
- Produces: 允许引入 FreeRTOS kernel 的已验证 baseline；不产生代码改动。

- [x] **Step 1: 核对人工证据属于当前基础 revision**

Run:

```bash
git merge-base --is-ancestor f75e606 HEAD
rg -n "0.462 ns|timer irq pass: ticks=3 loops=46" \
  docs/MEMORY_MAP.md docs/darkriscv_wrapper_summary.md
```

Expected: 第一条 exit 0；第二条同时找到 timing 与真实 UART 记录。

- [x] **Step 2: 运行 Gate 0 自动回归**

Run:

```bash
python3 scripts/test_runner.py run-suite platform --keep-going
python3 scripts/test_runner.py run-suite rv32mi_dark --keep-going
python3 scripts/test_runner.py run-suite rv32i_safe --keep-going
python3 scripts/test_runner.py run-suite soc --keep-going
```

Expected: 当前 master 为 `platform PASS 14/14`、`rv32mi_dark PASS 10/10`、`rv32i_safe PASS 1/1`、`soc PASS 23/23`；suite 后续扩展时以 0 failure 为固定契约，不以旧计数阻止新增测试。

- [x] **Step 3: 检查工作树边界**

Run:

```bash
git status --short
```

Expected: 只保留用户已有的 `.gitignore`、diary、issue draft；若出现其他改动，先定位来源，不进入 Task 1。

---

### Task 1: 固定官方 kernel 并建立 freertos build profile

**Files:**
- Modify: `.gitmodules`
- Create: `third_party/FreeRTOS-Kernel` (git submodule, tag `V11.3.0`)
- Create: `firmware/freertos/FreeRTOSConfig.h`
- Create: `firmware/freertos/portmacro.h`
- Create: `firmware/freertos/compat/stdlib.h`
- Create: `firmware/freertos/compat/string.h`
- Create: `firmware/freertos/freertos_hooks.c`
- Create: `firmware/tests/freertos_build_contract.c`
- Create: `scripts/test_freertos_build_contract.sh`
- Modify: `scripts/build_firmware.sh`
- Modify: `Makefile`

**Interfaces:**
- Consumes: RISC-V GCC、现有 linker/startup、`FIRMWARE_PROFILE`/`FIRMWARE_MAIN`/`FIRMWARE_OUT`。
- Produces: `FIRMWARE_PROFILE=freertos`；`FreeRTOS.h`/`task.h`/`queue.h` 可用；profile-only `-march=rv32i_zicsr`、section GC 与 `FREERTOS_CPU_CLOCK_HZ`；`freertos_assert_fail()`、`freertos_task_returned()`、`freertos_fatal_trap()`。

- [x] **Step 1: 写 build contract 失败测试**

新增 `firmware/tests/freertos_build_contract.c`：

```c
#include "FreeRTOS.h"
#include "task.h"
#include "drivers/mmio.h"

_Static_assert(configSUPPORT_STATIC_ALLOCATION == 1,
    "FreeRTOS 首轮必须支持静态分配");
_Static_assert(configSUPPORT_DYNAMIC_ALLOCATION == 0,
    "FreeRTOS 首轮不得启用动态分配");
_Static_assert(configUSE_PREEMPTION == 1,
    "FreeRTOS 首轮必须启用抢占");

int main(void)
{
    mmio_write(TINYBUS_TEST_EXIT, 1u);
    for (;;) {
    }
}
```

新增 `scripts/test_freertos_build_contract.sh`：

```bash
#!/usr/bin/env bash
set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
KERNEL="$REPO_ROOT/third_party/FreeRTOS-Kernel"
OUT="$REPO_ROOT/firmware/build/freertos/build-contract/firmware"

test -f "$KERNEL/tasks.c"
test "$(git -C "$KERNEL" describe --tags --exact-match)" = "V11.3.0"

FIRMWARE_PROFILE=freertos \
FIRMWARE_MAIN="$REPO_ROOT/firmware/tests/freertos_build_contract.c" \
FIRMWARE_OUT="$OUT" \
FREERTOS_CPU_CLOCK_HZ=1000000 \
    "$REPO_ROOT/scripts/build_firmware.sh"

test -s "$OUT.elf"
test -s "$OUT.bin"
test -s "$OUT.mem"
test -s "$OUT.lst"

bin_bytes=$(wc -c < "$OUT.bin")
test "$bin_bytes" -lt 65536
echo "PASS: FreeRTOS profile 固定 V11.3.0 且 BRAM image=${bin_bytes} bytes"
```

- [x] **Step 2: 运行测试确认 RED**

Run:

```bash
bash scripts/test_freertos_build_contract.sh
```

Expected: FAIL at missing `third_party/FreeRTOS-Kernel/tasks.c` or unknown `FIRMWARE_PROFILE=freertos`。

- [x] **Step 3: 引入固定 submodule**

Run:

```bash
git submodule add https://github.com/FreeRTOS/FreeRTOS-Kernel.git third_party/FreeRTOS-Kernel
git -C third_party/FreeRTOS-Kernel checkout V11.3.0
git submodule status third_party/FreeRTOS-Kernel
```

Expected: submodule 状态指向 V11.3.0 commit，前缀不是 `-` 或 `+`。

- [x] **Step 4: 写最小 FreeRTOSConfig.h**

`firmware/freertos/FreeRTOSConfig.h` 固定以下配置：

```c
#ifndef FREERTOS_CONFIG_H
#define FREERTOS_CONFIG_H

#ifndef FREERTOS_CPU_CLOCK_HZ
#define FREERTOS_CPU_CLOCK_HZ 50000000UL
#endif

#define configCPU_CLOCK_HZ FREERTOS_CPU_CLOCK_HZ
#define configTICK_RATE_HZ 1000U
#define configUSE_PREEMPTION 1
#define configUSE_TIME_SLICING 1
#define configUSE_PORT_OPTIMISED_TASK_SELECTION 0
#define configUSE_TICKLESS_IDLE 0
#define configMAX_PRIORITIES 4U
#define configMINIMAL_STACK_SIZE 128U
#define configMAX_TASK_NAME_LEN 16U
#define configTICK_TYPE_WIDTH_IN_BITS TICK_TYPE_WIDTH_32_BITS
#define configIDLE_SHOULD_YIELD 1
#define configUSE_IDLE_HOOK 0
#define configUSE_TICK_HOOK 0
#define configUSE_CO_ROUTINES 0
#define configUSE_TASK_NOTIFICATIONS 1
#define configTASK_NOTIFICATION_ARRAY_ENTRIES 1
#define configQUEUE_REGISTRY_SIZE 0
#define configNUM_THREAD_LOCAL_STORAGE_POINTERS 0
#define configUSE_NEWLIB_REENTRANT 0
#define configUSE_TIMERS 0
#define configUSE_EVENT_GROUPS 0
#define configUSE_STREAM_BUFFERS 0
#define configSUPPORT_STATIC_ALLOCATION 1
#define configSUPPORT_DYNAMIC_ALLOCATION 0
#define configKERNEL_PROVIDED_STATIC_MEMORY 1
#define configCHECK_FOR_STACK_OVERFLOW 2
#define configUSE_MUTEXES 0
#define configUSE_RECURSIVE_MUTEXES 0
#define configUSE_COUNTING_SEMAPHORES 0
#define configUSE_QUEUE_SETS 0
#define configUSE_TRACE_FACILITY 0
#define configGENERATE_RUN_TIME_STATS 0
#define configENABLE_FPU 0
#define configENABLE_VPU 0

#define INCLUDE_vTaskDelay 1
#define INCLUDE_xTaskDelayUntil 1
#define INCLUDE_vTaskSuspend 0
#define INCLUDE_vTaskDelete 0
#define INCLUDE_uxTaskGetStackHighWaterMark 1

void freertos_assert_fail(const char *file, unsigned int line);
#define configASSERT(condition) \
    do { if (!(condition)) freertos_assert_fail(__FILE__, __LINE__); } while (0)

#endif
```

- [x] **Step 5: 写最小 portmacro.h、compat headers 和 fatal hooks**

`portmacro.h` 必须完整给出 RV32I 类型、16-byte alignment、`ecall` yield、MIE 开关、TCB nesting：

```c
#ifndef PORTMACRO_H
#define PORTMACRO_H

#include <stdint.h>
#include <stddef.h>

#define portSTACK_TYPE uint32_t
#define portBASE_TYPE int32_t
#define portUBASE_TYPE uint32_t
#define portMAX_DELAY ((TickType_t)0xffffffffUL)
#define portPOINTER_SIZE_TYPE uint32_t
typedef portSTACK_TYPE StackType_t;
typedef portBASE_TYPE BaseType_t;
typedef portUBASE_TYPE UBaseType_t;
typedef uint32_t TickType_t;

#define portSTACK_GROWTH (-1)
#define portTICK_PERIOD_MS ((TickType_t)1000 / configTICK_RATE_HZ)
#define portBYTE_ALIGNMENT 16
#define portTICK_TYPE_IS_ATOMIC 1
#define portCRITICAL_NESTING_IN_TCB 1

void vTaskEnterCritical(void);
void vTaskExitCritical(void);
int freertos_port_in_trap(void);

#define portYIELD() __asm__ volatile ("ecall" ::: "memory")
#define portDISABLE_INTERRUPTS() __asm__ volatile ("csrc mstatus, %0" :: "r"(8u) : "memory")
#define portENABLE_INTERRUPTS() __asm__ volatile ("csrs mstatus, %0" :: "r"(8u) : "memory")
#define portENTER_CRITICAL() vTaskEnterCritical()
#define portEXIT_CRITICAL() vTaskExitCritical()
#define portASSERT_IF_IN_ISR() configASSERT(freertos_port_in_trap() == 0)
#define portYIELD_FROM_ISR(need_switch) do { (void)(need_switch); } while (0)

#define portTASK_FUNCTION_PROTO(fn, arg) void fn(void *arg)
#define portTASK_FUNCTION(fn, arg) void fn(void *arg)
#define portNOP() __asm__ volatile ("nop")
#define portINLINE inline
#define portFORCE_INLINE inline __attribute__((always_inline))
#define portMEMORY_BARRIER() __asm__ volatile ("" ::: "memory")

#endif
```

`freertos_hooks.c` 固定提供：

```c
void freertos_assert_fail(const char *file, unsigned int line);
void freertos_task_returned(void) __attribute__((noreturn));
void freertos_fatal_trap(const struct trap_frame *frame) __attribute__((noreturn));
void vApplicationStackOverflowHook(TaskHandle_t task, char *name);
```

assert、stack overflow、task return 和 fatal trap 都写各自独立的 `test_exit` 错误码并停机；不得在 timer ISR 中打印 UART。`file`、`line`、`task`、`name` 在首轮仅用于避免丢失接口信息，不依赖 UART 才能判定失败。

由于本机 `riscv64-unknown-elf-gcc` 不提供 libc headers，`compat/stdlib.h` 只定义
`NULL`/`SIZE_MAX`，`compat/string.h` 只声明现有 runtime 或 kernel 会引用的 string
接口。不得在这里加入 allocator 或伪造完整 libc。

- [x] **Step 6: 扩展 build profile**

`scripts/build_firmware.sh` 的 `freertos)` 分支必须：

```bash
FREERTOS_KERNEL="$REPO_ROOT/third_party/FreeRTOS-Kernel"
FREERTOS_CPU_CLOCK_HZ=${FREERTOS_CPU_CLOCK_HZ:-50000000}
MARCH=rv32i_zicsr  # 老 GCC 继续沿用现有探测回退
CFLAGS="$CFLAGS -ffunction-sections -fdata-sections -DFREERTOS_CPU_CLOCK_HZ=$FREERTOS_CPU_CLOCK_HZ"
INCLUDES="$INCLUDES -I$REPO_ROOT/firmware/freertos/compat -I$REPO_ROOT/firmware/freertos -I$FREERTOS_KERNEL/include"
LDFLAGS="$LDFLAGS -Wl,--gc-sections"
PROFILE_SOURCES="$FREERTOS_KERNEL/tasks.c $FREERTOS_KERNEL/queue.c $FREERTOS_KERNEL/list.c $REPO_ROOT/firmware/freertos/freertos_hooks.c"
```

在进入编译前显式检查 kernel 文件，缺 submodule 时输出：

```text
缺少 FreeRTOS-Kernel；请运行 git submodule update --init --recursive
```

- [x] **Step 7: 运行测试确认 GREEN**

Run:

```bash
bash scripts/test_freertos_build_contract.sh
make firmware
```

Expected: contract 输出 `PASS`；默认 baremetal 仍构建成功。

- [x] **Step 8: Commit**

```bash
git add .gitmodules third_party/FreeRTOS-Kernel \
  firmware/freertos/FreeRTOSConfig.h firmware/freertos/portmacro.h \
  firmware/freertos/compat/stdlib.h firmware/freertos/compat/string.h \
  firmware/freertos/freertos_hooks.c firmware/tests/freertos_build_contract.c \
  scripts/test_freertos_build_contract.sh scripts/build_firmware.sh Makefile
git commit -m "build: 接入固定版本 FreeRTOS kernel"
```

---

### Task 2: 构造 canonical task frame 并暴露公共 restore

**Files:**
- Create: `firmware/freertos/port.c`
- Create: `firmware/tests/freertos_frame_contract.c`
- Modify: `firmware/runtime/trap_entry.S`
- Modify: `firmware/runtime/trap.h`
- Modify: `scripts/build_firmware.sh`
- Modify: `sim/run_sim.sh`

**Interfaces:**
- Consumes: `StackType_t *pxPortInitialiseStack(StackType_t *, TaskFunction_t, void *)`、canonical frame offsets。
- Produces: `void trap_restore_frame(struct trap_frame *frame) __attribute__((noreturn))`；TCB `pxTopOfStack` 可直接保存返回的 frame pointer。

- [x] **Step 1: 写 frame contract 失败 firmware**

`freertos_frame_contract.c` 使用 512-word、16-byte aligned 静态 stack，调用
`pxPortInitialiseStack()` 后逐项检查：frame 16-byte aligned、x1/x2/x3/x4/x10、
`mepc`、`mstatus`、`mcause`、`reserved`。成功写 `test_exit=1`，任一失败写
`0xf2010000 | case_id`。

关键断言：

```c
frame = (struct trap_frame *)pxPortInitialiseStack(
    &stack[511], dummy_task, (void *)0x12345678u);
CHECK(((unsigned int)frame & 15u) == 0u, 1u);
CHECK(frame->x[2] == (unsigned int)frame + sizeof(*frame), 2u);
CHECK(frame->x[10] == 0x12345678u, 3u);
CHECK(frame->mepc == (unsigned int)dummy_task, 4u);
CHECK((frame->mstatus & 0x1880u) == 0x1880u, 5u);
CHECK(frame->mcause == 0u && frame->reserved == 0u, 6u);
```

- [x] **Step 2: 加入仿真入口并确认 RED**

`freertos_frame_contract` 使用 `tb_minisoc`、DarkRISCV、`EXPECT_EXIT_CODE=1`：

```bash
FIRMWARE_PROFILE=freertos
FIRMWARE_MAIN="$REPO_ROOT/firmware/tests/freertos_frame_contract.c"
FREERTOS_CPU_CLOCK_HZ=1000000
compile_minisoc_tb ... 1 tb_minisoc ... 0 1 1 -1 1 5
```

Run:

```bash
./sim/run_sim.sh freertos_frame_contract
```

Expected: link FAIL，缺少 `pxPortInitialiseStack`。

- [x] **Step 3: 实现 frame constructor**

`port.c` 定义 TCB prefix：

```c
struct tcb_prefix {
    volatile StackType_t *pxTopOfStack;
};
extern struct tcb_prefix * volatile pxCurrentTCB;
```

`pxPortInitialiseStack()`：

```c
uintptr_t top = ((uintptr_t)pxTopOfStack + sizeof(StackType_t)) & ~(uintptr_t)15u;
struct trap_frame *frame = (struct trap_frame *)(top - sizeof(*frame));
rt_memset(frame, 0, sizeof(*frame));
frame->x[1] = (uintptr_t)freertos_task_returned;
frame->x[2] = top;
__asm__ volatile ("mv %0, gp" : "=r"(frame->x[3]));
__asm__ volatile ("mv %0, tp" : "=r"(frame->x[4]));
frame->x[10] = (uintptr_t)pvParameters;
frame->mepc = (uintptr_t)pxCode;
frame->mstatus = 0x1880u;
return (StackType_t *)frame;
```

- [x] **Step 4: 暴露唯一 restore 入口**

`trap_entry.S` 保留现有 handler，在 `call trap_dispatch` 后跳入 `.Lrestore_frame`；新增：

```asm
    .globl trap_restore_frame
    .type trap_restore_frame, @function
trap_restore_frame:
    mv sp, a0
    j .Lrestore_frame

.Lrestore_frame:
    # 后续仍是现有 mepc/mstatus/x1..x31 恢复和 mret
```

`trap.h` 声明：

```c
void trap_restore_frame(struct trap_frame *frame) __attribute__((noreturn));
```

- [x] **Step 5: 运行 GREEN 与 trap 回归**

Run:

```bash
./sim/run_sim.sh freertos_frame_contract
./sim/run_sim.sh darkriscv_machine_trap
./sim/run_sim.sh minisoc_timer_irq_dark
```

Expected: 三项 PASS，证明公共 restore 没破坏 bare-metal trap。

- [x] **Step 6: Commit**

```bash
git add firmware/freertos/port.c firmware/tests/freertos_frame_contract.c \
  firmware/runtime/trap_entry.S firmware/runtime/trap.h \
  scripts/build_firmware.sh sim/run_sim.sh
git commit -m "feat: 构造 FreeRTOS canonical task frame"
```

---

### Task 3: 启动第一个静态 task

**Files:**
- Create: `firmware/tests/freertos_first_task.c`
- Modify: `firmware/freertos/port.c`
- Modify: `sim/run_sim.sh`
- Modify: `sim/tb_freertos_smoke.v`

**Interfaces:**
- Consumes: `pxCurrentTCB->pxTopOfStack`、`trap_init()`、`trap_restore_frame()`。
- Produces: `BaseType_t xPortStartScheduler(void)`；首个 task 从 canonical frame 开始执行。

- [x] **Step 1: 写首任务失败测试**

firmware 静态创建一个 task，参数固定 `0x2468ace0`。task 检查参数、SP 16-byte
alignment，并写：

```c
mmio_write(TINYBUS_TEST_EXIT,
    argument == (void *)0x2468ace0u && (read_sp() & 15u) == 0u
        ? 1u : 0xf3010001u);
```

`tb_freertos_smoke.v` 还必须统计 `dut.test_exited` 前至少一次 PC 进入 task symbol 所在
BRAM 区间；firmware 的 `test_exit` 是主判据。

- [x] **Step 2: 运行确认 RED**

Run:

```bash
./sim/run_sim.sh freertos_first_task
```

Expected: link FAIL，缺少 `xPortStartScheduler`，或 TIMEOUT 未进入 task。

- [x] **Step 3: 实现 scheduler start**

`xPortStartScheduler()`：

```c
BaseType_t xPortStartScheduler(void)
{
    trap_init();
    if (pxCurrentTCB == 0 || pxCurrentTCB->pxTopOfStack == 0) {
        freertos_assert_fail(__FILE__, __LINE__);
    }
    trap_restore_frame((struct trap_frame *)pxCurrentTCB->pxTopOfStack);
}
```

`vPortEndScheduler()` 与 `freertos_task_returned()` 都调用 fatal hook 后永久停机。
Gate 3 前不在 scheduler start 内启用 timer；Task 4 的 yield 不依赖 tick。

- [x] **Step 4: 运行 GREEN 与 frame contract**

Run:

```bash
./sim/run_sim.sh freertos_first_task
./sim/run_sim.sh freertos_frame_contract
```

Expected: 两项 PASS。

- [x] **Step 5: Commit**

```bash
git add firmware/tests/freertos_first_task.c firmware/freertos/port.c \
  sim/tb_freertos_smoke.v sim/run_sim.sh
git commit -m "feat: 启动首个 FreeRTOS 静态任务"
```

---

### Task 4: 通过 ecall 主动切换两个 task

**Files:**
- Create: `firmware/tests/freertos_yield_smoke.c`
- Modify: `firmware/freertos/port.c`
- Modify: `sim/tb_freertos_smoke.v`
- Modify: `sim/run_sim.sh`

**Interfaces:**
- Consumes: `portYIELD() -> ecall`、`mcause=0x0000000b`、TCB prefix。
- Produces: 当前 frame 写回旧 TCB、`vTaskSwitchContext()` 后返回新 TCB frame。

- [x] **Step 1: 写双任务 yield 失败测试**

两个相同优先级 task 各自把固定 seed 保存在 `s1`，执行 1000 次：

```c
signature += step;
counter++;
taskYIELD();
```

每次返回后检查 `signature == seed + counter * step`。两边都达到 1000 后写
`test_exit=1`；损坏写 `0xf4010001/2`。

bench 统计 `mcause==0x0000000b` 的 trap 次数至少 2000，且每次 `mepc` 返回后不再是
产生该次 trap 的 ecall PC。

- [x] **Step 2: 运行确认 RED**

Run:

```bash
./sim/run_sim.sh freertos_yield_smoke
```

Expected: TIMEOUT 或 fatal hook，因为默认 weak dispatcher 只返回原 frame。

- [x] **Step 3: 实现 FreeRTOS trap dispatch**

`port.c` 提供强定义：

```c
struct trap_frame *trap_dispatch(struct trap_frame *frame)
{
    pxCurrentTCB->pxTopOfStack = (StackType_t *)frame;
    freertos_trap_depth++;

    if (frame->mcause == 0x0000000bu) {
        frame->mepc += 4u;
        vTaskSwitchContext();
    } else {
        freertos_fatal_trap(frame);
    }

    freertos_trap_depth--;
    return (struct trap_frame *)pxCurrentTCB->pxTopOfStack;
}
```

`freertos_port_in_trap()` 返回 `freertos_trap_depth != 0`。`mepc += 4` 只适用于
machine `ecall`，不得对 fault 或 `ebreak` 无条件推进。

- [x] **Step 4: 运行 GREEN 与 RV32MI 回归**

Run:

```bash
./sim/run_sim.sh freertos_yield_smoke
python3 scripts/test_runner.py run-suite rv32mi_dark --keep-going
```

Expected: yield smoke PASS；RV32MI 10/10 PASS。

实际仿真中 2000 次完整 context switch 约需 205 万 cycles，因此该 case 独立使用
250 万 cycles timeout；2,000,000-cycle 默认值会稳定停在约 1949 次，不代表死锁。

- [x] **Step 5: Commit**

```bash
git add firmware/tests/freertos_yield_smoke.c firmware/freertos/port.c \
  sim/tb_freertos_smoke.v sim/run_sim.sh
git commit -m "feat: 支持 FreeRTOS ecall 主动切换"
```

---

### Task 5: 接入 timer tick、抢占、delay 与 critical section

**Files:**
- Create: `firmware/tests/freertos_smoke.c`
- Modify: `firmware/freertos/port.c`
- Modify: `firmware/drivers/machine_timer.h`
- Modify: `firmware/runtime/trap.c`
- Modify: `firmware/runtime/trap.h`
- Modify: `scripts/build_firmware.sh`
- Modify: `sim/tb_freertos_smoke.v`
- Modify: `sim/run_sim.sh`

**Interfaces:**
- Consumes: `machine_timer_now()`、`machine_timer_set_compare()`、`xTaskIncrementTick()`。
- Produces: 1000 Hz tick；同优先级 time slicing；`vTaskDelay()`；每 task TCB critical nesting。

- [x] **Step 1: 写 timer/delay/critical 失败测试**

smoke 分三 phase：

1. 两个相同优先级 task 不调用 yield，各自累加 register signature；两边都必须被抢占；
2. task A 记录 tick 后 `vTaskDelay(5)`，恢复时检查差值至少 5 且小于 8；
3. task A 进入 critical section，保持超过一个 tick interval，确认共享 tick counter 不变；退出后 tick 在有限循环内增长。

成功条件：至少 1000 次 timer trap、两个 task counter 都增长、delay/critical 断言通过，
写 `test_exit=1`。错误码使用 `0xf5010001` 起的独立值。

bench 在一次 BRAM/SDRAM data transaction 中 force `respond=0`，直到 MTIP pending，确认
stall 期间未进入 trap，release 后才进入；沿用 `tb_minisoc_timer_irq.v` 的注入方式。

- [x] **Step 2: 运行确认 RED**

Run:

```bash
./sim/run_sim.sh freertos_smoke
```

Expected: TIMEOUT，因为 scheduler 尚未设置 timer compare/MTIE/MIE。

- [x] **Step 3: 实现累计 tick deadline**

`xPortStartScheduler()` 在恢复首任务前：

```c
counts_per_tick = configCPU_CLOCK_HZ / configTICK_RATE_HZ;
configASSERT(counts_per_tick != 0u);
next_compare = machine_timer_now() + counts_per_tick;
machine_timer_set_compare(next_compare);
trap_enable_machine_timer_source();
```

timer trap：

```c
if (frame->mcause == 0x80000007u) {
    next_compare += counts_per_tick;
    machine_timer_set_compare(next_compare);
    if (xTaskIncrementTick() != pdFALSE) {
        vTaskSwitchContext();
    }
}
```

timer 写 compare 继续复用现有 RV32 安全 high/low 顺序。

`trap_enable_machine_timer_source()` 只打开 MTIE，不提前打开全局 MIE；首次
`trap_restore_frame()` 的 `mret` 根据 task frame 的 MPIE 打开 MIE。若在 scheduler
启动栈上提前打开 MIE，首个 timer trap 会把启动栈 frame 误写进当前 TCB，覆盖 task
初始 frame。原 `trap_enable_machine_timer()` 仍保持 MTIE+MIE 的 bare-metal 语义。

- [x] **Step 4: 完成 critical macro contract**

确认 `portCRITICAL_NESTING_IN_TCB=1`，`portENTER_CRITICAL()`/`EXIT` 调 kernel 的
`vTaskEnterCritical()`/`vTaskExitCritical()`；增加编译期断言与 runtime smoke，不在
frame `reserved` 中镜像 nesting。

- [x] **Step 5: 运行 GREEN 与基础回归**

Run:

```bash
./sim/run_sim.sh freertos_smoke
./sim/run_sim.sh minisoc_timer_irq_dark
python3 scripts/test_runner.py run-suite platform --keep-going
```

Expected: FreeRTOS smoke PASS，stall/pending 证据齐全；原 timer IRQ 与 platform 仍 PASS。

仿真统一使用 4 MHz 逻辑 CPU clock（每 tick 4000 cycles），避免 1 MHz 下通用 C kernel
的完整 tick/time-slice handler 超过 1000-cycle tick interval，形成不代表 50 MHz 板级
目标的持续 MTIP backlog。实际结果为 timer smoke 1013 traps、yield 回归 2115 ecall
traps、platform 14/14 PASS。

- [x] **Step 6: Commit**

```bash
git add firmware/tests/freertos_smoke.c firmware/freertos/port.c \
  firmware/drivers/machine_timer.h firmware/runtime/trap.c firmware/runtime/trap.h \
  scripts/build_firmware.sh sim/tb_freertos_smoke.v sim/run_sim.sh
git commit -m "feat: 接入 FreeRTOS timer tick 与抢占"
```

---

### Task 6: 增加静态 producer/consumer queue demo

**Files:**
- Create: `firmware/tests/freertos_queue.c`
- Modify: `sim/run_sim.sh`
- Test: `sim/tb_freertos_smoke.v`

**Interfaces:**
- Consumes: `xQueueCreateStatic()`、`xQueueSend()`、`xQueueReceive()`、tick/delay。
- Produces: 后续 Bad Apple audio queue 可复用的静态 queue 使用范式。

- [x] **Step 1: 写 queue 失败测试**

定义：

```c
struct demo_message {
    unsigned int sequence;
    unsigned int value;
};
```

queue 长度固定 4。producer 发送 sequence 0..63，`value=sequence ^ 0xa5a55a5a`；
consumer 阻塞接收并验证顺序和值。producer 开头连续发送 5 条，使第 5 条确定因 queue
满而阻塞；后续每 3 条 `vTaskDelay(1)`。demo 显式记录 empty、non-empty、full 三种状态，
consumer 收完 64 条且三种状态齐全后写 `test_exit=1`。

- [x] **Step 2: 运行确认 RED**

Run:

```bash
./sim/run_sim.sh freertos_queue
```

Expected: 未知仿真目标或 build 失败。

- [x] **Step 3: 接入 queue 仿真入口**

使用相同 `tb_freertos_smoke.v`，firmware main 改为 `freertos_queue.c`，保持
`FIRMWARE_PROFILE=freertos`、Task 5 已验证的 4 MHz 逻辑时钟与
`EXPECT_EXIT_CODE=1`。

- [x] **Step 4: 运行 GREEN 并重复三次**

Run:

```bash
./sim/run_sim.sh freertos_queue
./sim/run_sim.sh freertos_queue
./sim/run_sim.sh freertos_queue
```

Expected: 三次都 PASS，避免一次性时序巧合。

- [x] **Step 5: Commit**

```bash
git add firmware/tests/freertos_queue.c sim/run_sim.sh
git commit -m "feat: 增加 FreeRTOS 静态 queue 演示"
```

---

### Task 7: 接入 test catalog、构建入口与完整自动回归

**Files:**
- Modify: `scripts/test_catalog.json`
- Modify: `Makefile`
- Modify: `scripts/export_ise_project.sh`
- Modify: `firmware/startup.S`
- Modify: `firmware/linker.ld`
- Modify: `firmware/tests/freertos_smoke.c`
- Modify: `sim/tb_freertos_smoke.v`
- Modify: `sim/run_sim.sh`
- Modify: `docs/DEV_FLOW.md`
- Modify: `docs/darkriscv_wrapper_summary.md`
- Modify: `docs/FREERTOS_PORT_DESIGN.md`

**Interfaces:**
- Consumes: Task 1-6 全部通过的 sim targets。
- Produces: `freertos` suite、稳定 Make targets、ISE export 与人工 Gate 5 操作说明。

- [x] **Step 1: 先写 catalog 失败引用**

加入 cases：

```json
{"id":"freertos_build_contract","kind":"script","script":"scripts/test_freertos_build_contract.sh"},
{"id":"freertos_frame_contract","kind":"sim","sim_target":"freertos_frame_contract"},
{"id":"freertos_first_task","kind":"sim","sim_target":"freertos_first_task"},
{"id":"freertos_yield_smoke","kind":"sim","sim_target":"freertos_yield_smoke"},
{"id":"freertos_smoke","kind":"sim","sim_target":"freertos_smoke"},
{"id":"freertos_queue","kind":"sim","sim_target":"freertos_queue"}
```

先把 suite `freertos` 指向这些 case，并故意在尚未加入 `local` 前运行单 suite。

- [x] **Step 2: 运行 suite 确认能发现任何未接通项**

Run:

```bash
python3 scripts/test_runner.py run-suite freertos --keep-going
```

Expected: 若 Task 1-6 有遗漏则 FAIL 并给出具体 case；不得通过删除失败 case 变绿。

首次 suite 准确发现 `freertos_frame_contract` TIMEOUT。VCD 定位为 startup 未初始化
`gp/tp`，导致 frame contract 的 x3/x4 比较传播 X；补齐 psABI `__global_pointer$` 与
确定的 `gp/tp` 初始化后，单 case 与完整 suite 均通过。

- [x] **Step 3: 补 Make 与 export 入口**

Make targets：

```make
freertos-smoke:
	FIRMWARE_PROFILE=freertos \
	FIRMWARE_MAIN="$(REPO_ROOT)/firmware/tests/freertos_smoke.c" \
	FIRMWARE_OUT="$(REPO_ROOT)/firmware/build/freertos/smoke/firmware" \
	"$(BUILD_FIRMWARE)"

freertos-queue:
	FIRMWARE_PROFILE=freertos \
	FIRMWARE_MAIN="$(REPO_ROOT)/firmware/tests/freertos_queue.c" \
	FIRMWARE_OUT="$(REPO_ROOT)/firmware/build/freertos/queue/firmware" \
	"$(BUILD_FIRMWARE)"

freertos-load:
	$(MAKE) bootload PORT="$(PORT)" \
	FIRMWARE_PROFILE=freertos \
	FIRMWARE_MAIN="$(REPO_ROOT)/firmware/tests/freertos_smoke.c"
```

ISE export 必须检查 submodule、复制 kernel source/include 与 `firmware/freertos`，并用
50 MHz 构建 `freertos_smoke` payload；不把 kernel C 文件加入 RTL source list。

- [x] **Step 4: 把 freertos suite 接入 local/all**

只有独立 suite 全绿后，才在 `local` 中加入 `@freertos`。保持 `.NOTPARALLEL`，避免多个
firmware case 争用产物。

- [x] **Step 5: 运行完整自动 Gate 5**

Run:

```bash
python3 scripts/test_runner.py run-suite freertos --keep-going
python3 scripts/test_runner.py run-suite platform --keep-going
python3 scripts/test_runner.py run-suite soc --keep-going
python3 scripts/test_runner.py run-suite rv32i_safe --keep-going
python3 scripts/test_runner.py run-suite rv32mi_dark --keep-going
python3 scripts/test_runner.py run-suite all --keep-going
git diff --check
```

Expected: 所有 suite 0 failure；`git diff --check` 无输出。

实际结果：`freertos 6/6`、`platform 14/14`、`soc 23/23`、`rv32i_safe 1/1`、
`rv32mi_dark 10/10`、聚合 `all 59/59`，且最终 ISE export 与 50 MHz Make targets
均成功。

- [x] **Step 6: 更新文档为实际实现状态**

记录：

- pinned kernel commit 与 tag；
- 实际 ELF `.text/.data/.bss`、BRAM `.bin` 大小；
- 每个自动 case 命令与 PASS 结果；
- `freertos-load PORT=COM8` 操作、预期 UART/LED/test_exit；
- FreeRTOS profile 仍只支持 DarkRISCV；
- Bad Apple 尚未在本计划中迁移。

- [x] **Step 7: Commit**

```bash
git add scripts/test_catalog.json Makefile scripts/export_ise_project.sh \
  firmware/startup.S firmware/linker.ld firmware/tests/freertos_smoke.c \
  sim/tb_freertos_smoke.v sim/run_sim.sh \
  docs/DEV_FLOW.md docs/darkriscv_wrapper_summary.md docs/FREERTOS_PORT_DESIGN.md
git commit -m "test: 接入 FreeRTOS 自动回归与上板入口"
```

---

### Task 8: FreeRTOS ISE 与真实上板 Gate

**Files:**
- Read: `docs/DEV_FLOW.md`
- Generated outside git: ISE Map/PAR/timing reports、UART log。

**Interfaces:**
- Consumes: 自动 Gate 5 全绿、`make freertos-smoke`、`make freertos-load`。
- Produces: 允许开始 `freertos-bad-apple` 独立设计/计划的硬件证据。

- [x] **Step 1: 导出并生成 FreeRTOS 工程**

Run:

```bash
bash scripts/export_ise_project.sh minisoc_freertos_dark
make freertos-smoke
```

Expected: export/build 成功，firmware `.bin` 小于 64 KiB。当前自动结果为
`11460 bytes`。

- [ ] **Step 2: 由开发者运行 ISE Map/PAR**

人工验收：

```text
[ ] Map 无 OVERMAPPED
[ ] Slice LUT / Register / RAMB16 未超容量
[ ] machine_timer、DarkRISCV IRQ CSR、FreeRTOS payload 未被错误 trim
[ ] PAR 后 50 MHz post-route timing slack > 0
```

任一失败都回到对应实现任务修复并重跑完整自动 Gate 5，不能进入上板。

- [ ] **Step 3: 由开发者运行同一 smoke 上板**

Run:

```bash
make freertos-load PORT=COM8
```

人工验收：

```text
[ ] UART 输出 freertos smoke pass
[ ] LED 最终显示 5
[ ] 无 fatal/assert/stack overflow 错误码
```

- [ ] **Step 4: 保存证据并提交**

把 Map/PAR/timing 摘要、bitstream/firmware commit、UART 原始输出与日期写回
`docs/darkriscv_wrapper_summary.md` 或独立 results 目录，然后：

```bash
git add docs/darkriscv_wrapper_summary.md
git commit -m "docs: 记录 FreeRTOS 上板验收结果"
```

只有 Task 8 全部通过，才开始 Bad Apple FreeRTOS 版本的独立 design/spec/plan。
