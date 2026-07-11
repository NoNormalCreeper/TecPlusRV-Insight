# FreeRTOS heap 与短时综合验收 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 DarkRISCV MiniSoC 上用官方 `heap_5` 接管现有 SDRAM heap region，并增加可自动结束的短时 FreeRTOS 综合验收 payload。

**Architecture:** 保留 BRAM smoke 与 bare-metal bump allocator；仅 FreeRTOS profile 链接 `heap_5.c`，通过一个初始化函数把 linker 的 `_heap_start.._heap_end` 定义为唯一 heap region。新的 acceptance 复用现有 MiniSoC SDRAM controller/model，按确定性阶段验证 scheduler、IPC、timer、event group 和 static/dynamic allocation。

**Tech Stack:** RV32I C/assembly、FreeRTOS-Kernel V11.3.0、DarkRISCV、Icarus Verilog、Bash、JSON test catalog、Xilinx ISE 导出脚本。

## Global Constraints

- 所有开发者文本、注释、文档和 commit message 使用中文，保留常见 English 术语。
- 直接在当前 `master` 工作，不创建 worktree，不修改 `.gitignore`、`docs/diary.md`、`docs/issue_drafts/2026-07-07-sdram-runtime-bootloader-issues.md`。
- FreeRTOS-Kernel 固定 `V11.3.0` / `9b777ae5c5b8e9e456065a00294d1e5f5f9facf5`。
- BRAM 设计预算 48 KiB，hard limit 64 KiB；每个新增 payload 报告 section 与 `.bin` 尺寸。
- 复用现有 `sdram_data_ctrl`、`sdram_x16_model`、canonical trap frame 和 `test_exit`，不增加第二套 allocator 专用内存模型或 trap entry。
- 自动 Gate 未通过不得进入上板 Gate；无法自动执行的 ISE 和物理板验证明确交给用户。

---

## 文件结构

- Create `firmware/freertos/freertos_heap.h`：声明 FreeRTOS heap 初始化与边界查询接口。
- Create `firmware/freertos/freertos_heap.c`：把 linker heap region 一次性交给 `heap_5`。
- Modify `firmware/freertos/FreeRTOSConfig.h`：启用 dynamic allocation、mutex、semaphore、event group、software timer 和删除/优先级查询 API。
- Modify `firmware/freertos/freertos_hooks.c`：记录 malloc failure，并保留 fatal assert/stack/trap 行为。
- Modify `scripts/build_firmware.sh`：FreeRTOS profile 链接官方新增模块和 heap wrapper，并报告/限制 BRAM 用量。
- Modify `scripts/test_freertos_build_contract.sh`：验证 kernel revision、链接符号、heap region 和容量 contract。
- Create `firmware/tests/freertos_acceptance.c`：短时综合验收的唯一 firmware 入口。
- Reuse `sim/tb_minisoc_sdram.v`：直接使用现有 `test_exit`、LED、SDRAM traffic 与 timeout 检查，不复制 testbench。
- Modify `sim/run_sim.sh`：增加 `freertos_acceptance` 仿真目标。
- Modify `scripts/test_catalog.json`：把 acceptance 放到 `freertos` suite 的细粒度测试之后。
- Modify `Makefile`：增加 build/load/test 的稳定入口。
- Modify `scripts/export_ise_project.sh`：导出 acceptance firmware 所需 FreeRTOS sources 与独立目标。
- Modify `docs/FREERTOS_PORT_DESIGN.md`：记录 dynamic modules、heap 边界、验证入口和实测尺寸。

---

### Task 1: 用 build contract 锁定 dynamic FreeRTOS profile

**Files:**
- Modify: `scripts/test_freertos_build_contract.sh`
- Modify: `scripts/build_firmware.sh`
- Modify: `firmware/freertos/FreeRTOSConfig.h`
- Modify: `firmware/tests/freertos_build_contract.c`

**Interfaces:**
- Consumes: `FIRMWARE_PROFILE=freertos`、linker symbols `_heap_start` / `_heap_end`。
- Produces: profile 中可链接的 `timers.c`、`event_groups.c`、`heap_5.c`，以及启用相应 API 的统一配置。

- [ ] **Step 1: 先扩展 build contract，使当前实现失败**

在 `scripts/test_freertos_build_contract.sh` 构建完成后加入 ELF 符号检查：

```sh
NM=${NM:-riscv64-unknown-elf-nm}
need_symbol() {
    if ! "$NM" "$OUT.elf" | awk '{print $3}' | grep -qx "$1"; then
        echo "FAIL: FreeRTOS profile 缺少符号 $1" >&2
        exit 1
    fi
}

need_symbol vPortDefineHeapRegions
need_symbol xTimerCreate
need_symbol xEventGroupCreate
```

同时检查 `_heap_end - _heap_start == 65536`，并检查 build output 包含 BRAM section
summary。使用 `riscv64-unknown-elf-nm -n` 读取两个 linker symbol 的十六进制地址后做
shell arithmetic。

在 `freertos_build_contract.c` 把 dynamic static assert 改为 1，并通过 volatile 条件保留
新增模块的链接引用：

```c
#include "event_groups.h"
#include "timers.h"

_Static_assert(configSUPPORT_DYNAMIC_ALLOCATION == 1,
    "FreeRTOS profile 必须支持动态分配");

static volatile unsigned int keep_dynamic_modules;

static void contract_timer_callback(TimerHandle_t timer)
{
    (void)timer;
}

/* main 中的 volatile 条件不会在编译期消失，只用于链接 contract，不实际运行。 */
if (keep_dynamic_modules != 0u) {
    (void)xTimerCreate("contract", 1u, pdFALSE, 0, contract_timer_callback);
    (void)xEventGroupCreate();
}
```

- [ ] **Step 2: 运行 contract，确认红灯原因正确**

Run: `scripts/test_freertos_build_contract.sh`

Expected: FAIL，首先报告缺少 `vPortDefineHeapRegions`，而不是工具链、kernel revision
或原有 firmware 构建失败。

- [ ] **Step 3: 最小启用 kernel modules 与配置**

在 `scripts/build_firmware.sh` 的 FreeRTOS sources 加入：

```text
$FREERTOS_KERNEL/timers.c
$FREERTOS_KERNEL/event_groups.c
$FREERTOS_KERNEL/portable/MemMang/heap_5.c
```

在 `FreeRTOSConfig.h` 设置：

```c
#define configUSE_TIMERS 1
#define configTIMER_TASK_PRIORITY (configMAX_PRIORITIES - 1U)
#define configTIMER_QUEUE_LENGTH 8U
#define configTIMER_TASK_STACK_DEPTH 256U
#define configUSE_EVENT_GROUPS 1
#define configSUPPORT_STATIC_ALLOCATION 1
#define configSUPPORT_DYNAMIC_ALLOCATION 1
#define configUSE_MALLOC_FAILED_HOOK 1
#define configUSE_MUTEXES 1
#define configUSE_COUNTING_SEMAPHORES 1
#define INCLUDE_vTaskDelete 1
#define INCLUDE_uxTaskPriorityGet 1
```

不要启用 stream buffer、queue set、recursive mutex、trace 或 runtime stats。

- [ ] **Step 4: 给构建脚本增加真实 BRAM size report 与 hard limit**

使用 `${SIZE:-riscv64-unknown-elf-size} -A "$TMP_OUT.elf"` 输出 section；从
`.text/.data/.bss/.data_load` 与 SDRAM section 的 VMA 分类计算 BRAM，而不是把
`.heap` 的 64 KiB NOLOAD 算入 BRAM。若 BRAM used `>= 65536` 则构建失败；若
`>= 49152` 则打印 soft-budget warning。继续保留最终 `.bin < 65536` 检查。

- [ ] **Step 5: 运行新增 kernel module contract**

Run: `scripts/test_freertos_build_contract.sh`

Expected: PASS；profile 能编译新增官方 sources，并保留 `vPortDefineHeapRegions`、
`xTimerCreate` 与 `xEventGroupCreate`。linker region wrapper 在下一 task 单独红绿验证。

- [ ] **Step 6: 提交 profile 基础**

```bash
git add firmware/freertos/FreeRTOSConfig.h firmware/tests/freertos_build_contract.c scripts/build_firmware.sh scripts/test_freertos_build_contract.sh
git commit -m "build: 启用常用 FreeRTOS kernel 模块"
```

---

### Task 2: 将官方 heap_5 映射到 linker SDRAM heap

**Files:**
- Create: `firmware/freertos/freertos_heap.h`
- Create: `firmware/freertos/freertos_heap.c`
- Modify: `firmware/freertos/freertos_hooks.c`
- Modify: `scripts/build_firmware.sh`
- Modify: `scripts/test_freertos_build_contract.sh`
- Test: `firmware/tests/freertos_build_contract.c`

**Interfaces:**
- Consumes: linker symbols `extern unsigned char _heap_start[]`、`_heap_end[]`，FreeRTOS `HeapRegion_t` 与 `vPortDefineHeapRegions()`。
- Produces: `void freertos_heap_init(void)`、`unsigned int freertos_malloc_failed_count(void)`。

- [ ] **Step 1: 让 firmware contract 调用尚不存在的初始化接口**

在 `firmware/tests/freertos_build_contract.c` 的 `main()` 写 `test_exit` 之前加入：

```c
#include "freertos/freertos_heap.h"

freertos_heap_init();
if (xPortGetFreeHeapSize() == 0u) {
    return 1;
}
```

build contract 另外要求 ELF 包含 `freertos_heap_init`。

- [ ] **Step 2: 运行 contract 确认 link 失败**

Run: `scripts/test_freertos_build_contract.sh`

Expected: FAIL with undefined reference to `freertos_heap_init`。

- [ ] **Step 3: 实现一次性 region 初始化**

`freertos_heap.h`：

```c
#ifndef FREERTOS_HEAP_H
#define FREERTOS_HEAP_H

void freertos_heap_init(void);
unsigned int freertos_malloc_failed_count(void);

#endif
```

`freertos_heap.c` 使用 local `HeapRegion_t regions[2]`；`vPortDefineHeapRegions()` 在调用
期间完成 region list 构造，不保存数组地址：

```c
void freertos_heap_init(void)
{
    HeapRegion_t regions[2];

    configASSERT(heap_initialized == 0u);
    regions[0].pucStartAddress = _heap_start;
    regions[0].xSizeInBytes = (size_t)(_heap_end - _heap_start);
    regions[1].pucStartAddress = 0;
    regions[1].xSizeInBytes = 0u;
    vPortDefineHeapRegions(regions);
    heap_initialized = 1u;
}
```

wrapper 只用于 FreeRTOS profile，不调用 `heap_init()` / `bump_alloc()`。

- [ ] **Step 4: 实现可观察但可恢复的 malloc failed hook**

在 `freertos_hooks.c` 保存 `static volatile unsigned int malloc_failed_count`；
`vApplicationMallocFailedHook()` 只递增计数并返回。unexpected object-creation failure 仍由
每个 API caller 检查返回值并调用 fatal `test_fail`。

- [ ] **Step 5: 运行 heap contract 与 bare-metal heap smoke**

Run:

```bash
scripts/test_freertos_build_contract.sh
FIRMWARE_MAIN=firmware/tests/runtime_heap_smoke.c scripts/build_firmware.sh
```

Expected: FreeRTOS contract PASS；bare-metal firmware 仍能构建，证明没有把 bump
allocator 从通用 runtime 删除。

- [ ] **Step 6: 提交 heap 映射**

```bash
git add firmware/freertos/freertos_heap.h firmware/freertos/freertos_heap.c firmware/freertos/freertos_hooks.c firmware/tests/freertos_build_contract.c scripts/build_firmware.sh scripts/test_freertos_build_contract.sh
git commit -m "feat: 将 FreeRTOS heap 映射到 SDRAM"
```

---

### Task 3: 实现确定性的短时 acceptance payload

**Files:**
- Create: `firmware/tests/freertos_acceptance.c`
- Test: `firmware/tests/freertos_acceptance.c`（firmware 自检）

**Interfaces:**
- Consumes: `freertos_heap_init()`、FreeRTOS task/queue/semaphore/event/timer API、`testlib.h`。
- Produces: success UART `freertos acceptance pass`、LED `0x5`、`test_exit=1`；failure code family `0xfaSS00NN`，其中 `SS` 是阶段号。

- [ ] **Step 1: 先建立只会失败的 acceptance 骨架**

入口先执行：

```c
int main(void)
{
    test_banner("freertos acceptance");
    freertos_heap_init();
    test_fail(0xfa000001u);
}
```

Run:

```bash
FIRMWARE_PROFILE=freertos FREERTOS_CPU_CLOCK_HZ=1000000 \
FIRMWARE_MAIN=firmware/tests/freertos_acceptance.c \
FIRMWARE_OUT=firmware/build/freertos/acceptance/firmware \
scripts/build_firmware.sh
```

Expected: build PASS；运行阶段尚未接线，因此还不能进入 test suite。

- [ ] **Step 2: 加入 pre-scheduler heap 自检**

用最多 64 个 pointer、每块 1024 bytes 持续分配直到第一次 NULL；确认 malloc-failed
计数增加。释放两个相邻块后申请 1500 bytes，覆盖 coalescing；最后释放全部块，要求
`xPortGetFreeHeapSize()` 恢复到初始值，并记录 minimum-ever-free heap。每个块先写入
与 index 相关的 byte pattern，再读回校验。

- [ ] **Step 3: 创建 static coordinator 与基础 scheduler worker**

coordinator、idle memory 使用 static allocation。scheduler worker 覆盖：

```text
同优先级 taskYIELD 顺序
vTaskDelay / vTaskDelayUntil tick 边界
高优先级 task 被通知后抢占低优先级 task
```

每个等待使用有限 tick timeout；coordinator 失败时直接 `test_fail(0xfa0100NN)`。

- [ ] **Step 4: 加入 queue、notification、semaphore 与 mutex 阶段**

- 4-slot static queue 先检查 empty，再填满检查 full，最后校验 FIFO payload；
- notification 先覆盖 `eSetBits` 二值事件，再用 `ulTaskNotifyTake()` 覆盖计数；
- counting semaphore 从 0 give 两次并 take 两次；
- mutex 用低优先级 owner、中优先级 spinner、高优先级 waiter 的固定握手，检查 owner
  持锁期间 `uxTaskPriorityGet(owner)` 临时达到 waiter priority，释放后恢复。

- [ ] **Step 5: 加入 event group 与 software timer 阶段**

两个 worker 分别设置 `BIT0` / `BIT1`，coordinator 用有限 timeout 等待全部 bit。
one-shot callback 递增一次计数；periodic callback 达到 3 次后 `xTimerStop(..., 0)` 并
通知 coordinator。callback 不打印 UART、不阻塞。

- [ ] **Step 6: 加入 dynamic object 生命周期与最终判定**

- `xQueueCreate()` / `vQueueDelete()` 创建删除 dynamic queue；
- `xTaskCreate()` 创建一个完成通知后 `vTaskDelete(NULL)` 的 dynamic task；
- coordinator 等待 idle task 回收后检查 free heap 回升，不要求地址相同；
- 所有阶段通过后打印 free/minimum heap、`freertos acceptance pass`，再调用
  `test_pass()`。

在单独的最高优先级 watchdog task 中 `vTaskDelay(1500)` 后调用
`test_fail(0xfaff0001)`；正常结束早于该 deadline。

- [ ] **Step 7: 构建并检查容量**

Run: 使用 Step 1 build 命令。

Expected: build PASS，输出 BRAM used < 49152 bytes、`.bin < 65536`，且 ELF 中
`.heap` 为 SDRAM NOLOAD reservation。

- [ ] **Step 8: 提交 acceptance firmware**

```bash
git add firmware/tests/freertos_acceptance.c
git commit -m "test: 增加 FreeRTOS 短时综合验收固件"
```

---

### Task 4: 接入真实 SDRAM 自动仿真

**Files:**
- Reuse: `sim/tb_minisoc_sdram.v`
- Modify: `sim/run_sim.sh`
- Modify: `scripts/test_catalog.json`

**Interfaces:**
- Consumes: acceptance `.mem`、`tecplus_minisoc_top`、`sdram_x16_model`、`test_exit`。
- Produces: `./sim/run_sim.sh freertos_acceptance` 和 catalog case `freertos_acceptance`。

- [ ] **Step 1: 先把不存在的 case 加入 catalog**

在 `freertos` suite 的末尾加入：

```json
{
  "id": "freertos_acceptance",
  "kind": "sim",
  "sim_target": "freertos_acceptance"
}
```

Run: `python3 scripts/test_runner.py run-case freertos_acceptance`

Expected: FAIL，`sim/run_sim.sh` 报告未知目标。

- [ ] **Step 2: 确认现有 SDRAM-aware testbench contract 足够**

不新建 testbench。复用 `tb_minisoc_sdram.v`，由 runner 固定 `CPU_IMPL=1`、仿真
`CLK_FREQ=1 MHz`。现有成功条件已经包括：

```verilog
test_exit_code == 1
led == 4'h5
accepted_read_count > 0
accepted_write_count > 0
model command count 与 32-bit/x16 请求数一致
```

现有 bench 还覆盖 BRAM/MMIO/SDRAM one-hot、ifetch 仍来自 BRAM、request/response 与
每笔 32-bit 访问对应两个 x16 command。cycle timeout 独立于 firmware watchdog。

- [ ] **Step 3: 在 runner 中构建 acceptance 并编译 bench**

`freertos_acceptance)` case 先设置：

```sh
FIRMWARE_PROFILE=freertos
FREERTOS_CPU_CLOCK_HZ=1000000
FIRMWARE_MAIN="$REPO_ROOT/firmware/tests/freertos_acceptance.c"
FIRMWARE_OUT="$REPO_ROOT/firmware/build/freertos/acceptance/firmware"
```

然后调用现有 `compile_minisoc_tb`，module/file 使用
`tb_minisoc_sdram sim/tb_minisoc_sdram.v`，确保 source list 包含
`sdram_data_ctrl.v` 与 `sdram_x16_model.v`。

- [ ] **Step 4: 跑单 case 并调到 green**

Run: `python3 scripts/test_runner.py run-case freertos_acceptance`

Expected: UART 包含 `freertos acceptance pass`，testbench 报告 PASS，实际 SDRAM
read/write 均非 0。

- [ ] **Step 5: 跑完整 FreeRTOS suite**

Run: `make test-freertos`

Expected: 既有 build/frame/first-task/yield/smoke/queue 全部 PASS，最后 acceptance PASS。

- [ ] **Step 6: 提交仿真入口**

```bash
git add sim/run_sim.sh scripts/test_catalog.json
git commit -m "test: 接入 FreeRTOS SDRAM 综合验收仿真"
```

---

### Task 5: 补齐 Make、ISE、文档与全回归 Gate

**Files:**
- Modify: `Makefile`
- Modify: `scripts/export_ise_project.sh`
- Modify: `docs/FREERTOS_PORT_DESIGN.md`
- Test: `scripts/test_freertos_build_contract.sh`

**Interfaces:**
- Consumes: `freertos_acceptance` build/sim target。
- Produces: `make freertos-acceptance`、`make freertos-acceptance-load PORT=...`、ISE target `minisoc_freertos_acceptance_dark`。

- [ ] **Step 1: 先写入口 contract 并确认失败**

在 build contract 检查：

```sh
grep -q '^freertos-acceptance:' "$REPO_ROOT/Makefile"
grep -q '^freertos-acceptance-load:' "$REPO_ROOT/Makefile"
grep -q 'minisoc_freertos_acceptance_dark' "$REPO_ROOT/scripts/export_ise_project.sh"
```

Run: `scripts/test_freertos_build_contract.sh`

Expected: FAIL，报告缺少 Make/ISE 入口。

- [ ] **Step 2: 增加稳定 build/load target**

`make freertos-acceptance` 使用 50 MHz、DarkRISCV acceptance source 与隔离输出目录。
`make freertos-acceptance-load PORT=COM8` 复用现有 bootloader upload/monitor 流程；不复制
新的 Python uploader。

- [ ] **Step 3: 扩展 ISE export**

让 FreeRTOS export copy/check `timers.c`、`event_groups.c`、`heap_5.c`、
`freertos_heap.[ch]` 与 acceptance source；新增目标
`minisoc_freertos_acceptance_dark`，继续使用既有 50 MHz MiniSoC SDRAM top/constraints。

- [ ] **Step 4: 更新 FreeRTOS 设计文档**

将首轮“static only”改为历史状态；新增当前 dynamic heap region、已启用模块、acceptance
入口、真实构建尺寸和自动验证结果。保留“上板未验证”的明确边界，直到用户回传 UART、
LED 与 timing 结果。

- [ ] **Step 5: 运行 focused Gate**

Run:

```bash
scripts/test_freertos_build_contract.sh
make freertos-acceptance
make test-freertos
```

Expected: 全部 PASS；输出 acceptance section/bin size。

- [ ] **Step 6: 运行相邻与全量回归**

Run:

```bash
make test-platform
make test-soc
python3 scripts/test_runner.py run-suite rv32i_safe
python3 scripts/test_runner.py run-suite rv32mi_dark
make test-all
```

Expected: 所有 case PASS。若失败，使用 systematic-debugging 先定位 root cause，不跳过
或降低既有检查。

- [ ] **Step 7: 验证 ISE export 可生成**

Run: `scripts/export_ise_project.sh minisoc_freertos_acceptance_dark`

Expected: export 完成，工程包含新增 kernel/profile/acceptance sources。若本机无法运行
ISE Map/PAR，则停止在导出证据，并把 50 MHz timing 与物理板 acceptance 命令交给用户。

- [ ] **Step 8: 提交入口与文档**

```bash
git add Makefile scripts/export_ise_project.sh scripts/test_freertos_build_contract.sh docs/FREERTOS_PORT_DESIGN.md
git commit -m "docs: 补齐 FreeRTOS 综合验收入口"
```

---

## 最终人工 Gate

自动 Gate 全绿后，请用户执行：

```bash
make freertos-acceptance-load PORT=COM8
```

需要回传：

1. UART 中完整的阶段进度与 `freertos acceptance pass`；
2. LED 最终为 `0x5`；
3. 至少重复运行一次仍通过；
4. ISE Map/PAR 成功及 50 MHz timing slack。

收到上述证据后，才把本轮标记为完整验证，并开始独立 demo 设计/实施。
