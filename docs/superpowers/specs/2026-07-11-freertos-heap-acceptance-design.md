# FreeRTOS heap 与短时综合验收设计

## 目标与范围

本轮在已经通过仿真和上板的 FreeRTOS BRAM smoke 之后，增加第二道验收门：

1. 使用官方 `heap_5.c`，让 FreeRTOS dynamic allocation 复用 linker 已经划出的
   SDRAM `_heap_start.._heap_end` 区域；
2. 增加一个短时、确定性、可自动结束的 `freertos-acceptance` payload，综合验证
   scheduler、常用同步原语、software timer、static/dynamic allocation 和 SDRAM 数据
   完整性；
3. 保留现有 smoke、queue demo 和 bare-metal bump allocator，不在本轮实现长时间
   stress、traffic/audio demo 或 Bad Apple media pipeline。

本轮是后续独立教学 demo 和压力测试的基础。只有本轮自动化及必要的上板验证通过，
才进入下一阶段。

## 验收层级

测试按以下顺序执行：

```text
现有 BRAM FreeRTOS smoke
    -> SDRAM + heap_5 freertos-acceptance
    -> 独立教学 demo
    -> 长时间 stress
    -> media pipeline / Bad Apple
```

BRAM smoke 继续只回答“trap、context switch、tick 和基本 queue 是否工作”。新的
acceptance 才回答“常用 FreeRTOS 模块和 SDRAM heap 能否共同工作”。两者分开，避免
SDRAM 或 allocator 故障掩盖最基础的 port 故障。

## heap 策略

### FreeRTOS payload

FreeRTOS profile 同时启用 static 与 dynamic allocation，并链接官方 `heap_5.c`。
初始化函数只做一次：

```text
_heap_start -------------------- _heap_end
       一个 HeapRegion_t 区域
```

在创建任何 dynamic FreeRTOS object 之前，调用 `vPortDefineHeapRegions()`，将这段
linker 区域交给 `heap_5`。FreeRTOS object 通过 `pvPortMalloc()` / `vPortFree()` 管理，
不经过项目的 bump allocator。

选择 `heap_5` 而不是 `heap_4`，是为了直接使用 linker 给出的非默认地址区域。首轮只
配置一个 SDRAM region，不预先设计多 region 策略。

### bare-metal payload

`firmware/runtime/rt_alloc.c` 及其 `bump_alloc()` 行为保持不变。它仍服务既有
bare-metal firmware；FreeRTOS profile 不同时使用 bump allocator 和 `heap_5` 管理
同一段地址。

### static 与 dynamic 的使用边界

acceptance 同时覆盖两种创建方式。后续 Bad Apple 等长期运行 payload 的核心 task、
queue 仍优先 static allocation；dynamic allocation 用于教学、短生命周期对象或确实
需要可变大小的工作区。这样可以演示 heap，同时降低长期碎片化风险。

## Kernel 配置与模块

FreeRTOS profile 在现有 `tasks.c`、`queue.c`、`list.c` 基础上增加：

- `timers.c`：software timer；
- `event_groups.c`：event group；
- `portable/MemMang/heap_5.c`：SDRAM dynamic allocation。

同时启用：

- task notification；
- mutex、counting semaphore；
- software timer；
- event group；
- task/object 删除所需 API；
- malloc failed hook。

首轮不加入 stream buffer、queue set、recursive mutex、trace facility 或 runtime stats。
这些能力没有当前验收需求，避免扩大代码体积和故障面。

## `freertos-acceptance` 结构

一个静态 coordinator task 按固定阶段驱动若干 worker。阶段之间使用明确的计数器、
通知或 event bit 校验，不依赖 UART 文本时序。UART 只负责人可读进度和错误码。

### 阶段 1：调度与时间

- 不同优先级 task 均得到执行；
- `taskYIELD()` 能主动切换；
- `vTaskDelay()` / `vTaskDelayUntil()` 能按 tick 唤醒；
- ready 的高优先级 task 能抢占低优先级 task。

### 阶段 2：queue 与 task notification

- queue 覆盖 empty、正常传递和 full；
- producer/consumer 校验消息顺序与内容；
- notification 覆盖二值唤醒和计数累加。

### 阶段 3：semaphore 与 mutex

- semaphore 完成两个 task 间的事件同步；
- mutex 保护共享计数器；
- 构造可重复的低、中、高优先级顺序，检查基本 priority inheritance，避免只验证
  “能加锁”而漏掉 mutex 与 binary semaphore 的关键差异。

### 阶段 4：event group

两个 worker 分别设置不同 bit，coordinator 等待全部 bit 后继续。超时或出现意外 bit
都视为失败。

### 阶段 5：software timer

- one-shot timer 精确触发一次；
- periodic timer 精确触发若干次后停止；
- callback 只更新状态或发送非阻塞信号，不在 timer service task 中执行阻塞操作。

### 阶段 6：static 与 dynamic allocation

- 创建并删除 dynamic task 和 dynamic queue；
- 保留 static task/queue 作为对照；
- 用 `pvPortMalloc()` 分配多个不同大小的块，写入 pattern 并读回；
- 释放相邻块后申请更大的块，覆盖空闲块合并；
- 覆盖 allocation failure，确认释放后可以恢复分配；
- 输出当前 free heap 和 minimum-ever-free heap。

测试不假定释放后返回完全相同的地址，只验证 FreeRTOS allocator 对外保证的行为。

## 结束、错误与可观察性

每个阶段输出一条简短 UART 进度。失败输出稳定的阶段错误码，设置失败 LED，并通过
`test_exit` 非 1 值结束仿真；成功输出：

```text
freertos acceptance pass
```

成功时 LED 为 `0x5`、`test_exit=1`。设置约 1500 tick 的逻辑 watchdog，避免 task
死锁后固件无限等待；testbench 另有 cycle timeout，防止 tick 本身失效时 watchdog
也无法运行。

UART 不是 pass 的唯一依据。testbench 还必须观察到实际 SDRAM read/write，并保留
现有 MiniSoC SDRAM bench 对 BRAM/MMIO/SDRAM 路由、request/response 数量和 x16
command 数量的检查。

## 构建、仿真与上板入口

新增稳定入口：

```bash
make freertos-acceptance
make test-freertos
make freertos-acceptance-load PORT=COM8
```

`freertos-acceptance` 使用 DarkRISCV、FreeRTOS profile 和 SDRAM MiniSoC 配置。仿真
复用现有 `sdram_data_ctrl`、`sdram_x16_model` 与 MiniSoC SDRAM 路径，不新增第二套
SDRAM 模型或简化 allocator 专用内存。

`make test-freertos` 继续先跑已有细粒度 contract/smoke，再运行 acceptance。任一前置
测试失败时 fail-fast，不用综合测试结果覆盖更精确的错误定位。

## 容量约束

板上 BRAM 为 64 KiB，不是 32 KiB。每个 FreeRTOS payload 构建后报告：

- `.text`、`.data`、BRAM `.bss`；
- SDRAM `.sdram_data`、`.sdram_bss`、`.heap` reservation；
- 最终 `.bin` 大小。

BRAM 设计预算为 48 KiB，64 KiB 是 hard limit。超过 48 KiB 时必须先检查是否误链接
未使用模块或是否能减少 task stack；超过 64 KiB 则构建直接失败。SDRAM 的 64 KiB
heap 是当前 linker policy，不是物理硬件上限。

## 验证 Gate

### Gate A：构建 contract

- kernel 固定版本与 submodule 状态正确；
- `heap_5.c`、`timers.c`、`event_groups.c` 被 FreeRTOS profile 正确链接；
- FreeRTOS heap region 等于 `_heap_start.._heap_end`；
- bare-metal bump allocator 构建和既有 runtime heap smoke 不回退；
- 所有 payload 输出 section/bin size，BRAM hard limit 生效。

### Gate B：自动仿真

- 已有 FreeRTOS 细粒度测试全部通过；
- `freertos-acceptance` 通过并真实产生 SDRAM read/write；
- `make test-platform`、`make test-soc`、RV32I/RV32MI 回归通过；
- `make test-all` 最终通过。

### Gate C：FPGA 工具链与上板

- 导出独立 ISE project，完成 Map/PAR/timing；
- 50 MHz timing slack 不得由本轮 RTL 不变的软件改动恶化；
- 上板运行 `freertos-acceptance`，记录 UART pass、LED 和至少一次重复运行结果。

当前本地环境不能自动完成的 ISE GUI、串口或物理板验证必须明确交给用户执行。未得到
上板证据前，只能声明自动仿真通过，不能声明完整 Gate C 通过。

## 后续阶段

本轮通过后，再为独立 demo 与 stress 分别确认实现细节。已确定的方向包括 heap、
notification、mutex、event group、software timer、traffic/audio，以及约 10000 tick
仿真、10 分钟上板和可选无限 soak；它们不与本轮 acceptance 一次实现。
