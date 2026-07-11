# DarkRISCV FreeRTOS 接入设计

## 目标

在 `CPU_IMPL=1` 的 DarkRISCV MiniSoC 上接入一个可复用的单核 FreeRTOS
firmware profile。FreeRTOS 不是 Bad Apple 的专用 runtime；仓库应先用独立 smoke
和 queue demo 证明 port 正确，再把 Bad Apple 作为其中一个综合应用。

首轮交付至少支持：

- machine timer interrupt 产生 kernel tick；
- `taskYIELD()` 通过 machine `ecall` 主动切换；
- `vTaskDelay()` 阻塞并按 tick 唤醒；
- 两个静态任务长期抢占，寄存器和 stack 不损坏；
- 静态 queue 在 producer/consumer 之间传递消息；
- kernel 与应用静态链接成一个可由现有 bootloader 装载的 BRAM payload。

## 核心选择

采用“官方 kernel + TecPlusRV 专用薄 port”，不直接链接官方 RISC-V
`portASM.S`。

官方 kernel 的 `tasks.c`、`queue.c`、`list.c` 负责调度、延时和 queue；项目只实现
与 DarkRISCV 相关的 context 初始化、tick、yield 和任务恢复。这样可以继续复用已经
验证的：

```text
firmware/runtime/trap_frame.h
firmware/runtime/trap_entry.S
struct trap_frame *trap_dispatch(struct trap_frame *frame)
```

官方 RISC-V port 自带另一套 context layout、trap handler 和 ISR stack。如果直接复制，
会形成第二个 `mtvec` 入口，也会让 bare-metal fault、FreeRTOS 和未来 GDB 使用不同的
register frame。项目不重新发明调度算法，只把官方 port 的语义映射到现有 canonical
frame。

首轮固定 FreeRTOS-Kernel `V11.3.0`，以 git submodule 方式放在：

```text
third_party/FreeRTOS-Kernel/
```

不得跟踪上游 `main`。升级 kernel 必须单独跑 port、smoke、queue、RV32I/RV32MI 和
MiniSoC 回归。

## Context 模型

项目的 canonical frame 保持不变：

```c
struct trap_frame {
    unsigned int x[32];
    unsigned int mepc;
    unsigned int mstatus;
    unsigned int mcause;
    unsigned int reserved;
};
```

这里的 canonical 只表示“本项目统一格式”，不是 RISC-V 官方 ABI。物理排列继续由
`trap_frame.h` 与 `trap_entry.S` 共同固定。

FreeRTOS TCB 的第一个成员是 `pxTopOfStack`。在本 port 中，它始终指向该 task 最近
保存的 `struct trap_frame`：

```text
TCB_A.pxTopOfStack -> task A 的 canonical frame
TCB_B.pxTopOfStack -> task B 的 canonical frame
```

`trap_dispatch()` 收到当前 task 的 frame 后：

1. 把 frame pointer 写入当前 TCB；
2. 根据 `mcause` 更新 tick 或处理 yield；
3. 必要时调用 `vTaskSwitchContext()` 选择另一个 TCB；
4. 从新的当前 TCB 取出 frame pointer 并返回；
5. `trap_entry.S` 从返回的 frame 恢复 context 并执行 `mret`。

`reserved` 首轮继续保留为 0，不承担 FreeRTOS 私有状态。FreeRTOS-Kernel V11.3.0
使用 `portCRITICAL_NESTING_IN_TCB=1`，让每个 task 的 critical nesting 由 TCB 保存；
这样无需为了 kernel 私有字段改变公共 trap frame。

## 第一个任务

新 task 尚未运行过，没有可恢复的旧 frame。`pxPortInitialiseStack()` 必须在该 task
的静态 stack 顶部人工构造 canonical frame：

```text
x[1]     = task return error handler
x[2]     = task 恢复后的 stack pointer
x[10]    = task 参数 pvParameters
mepc     = task 入口函数
mstatus  = MPP=M、MPIE=1、MIE=0
mcause   = 0
reserved = 0
```

`xPortStartScheduler()` 初始化 `mtvec`、timer compare 和当前 TCB 后，跳到
`trap_entry.S` 中独立暴露的公共 restore label。restore label 仍属于唯一 trap 入口的
保存/恢复实现，不复制第二套 context assembly。

## Tick、yield 与异常

trap 分发固定为：

| `mcause` | 行为 |
| --- | --- |
| `0x80000007` machine timer interrupt | 累加下一次绝对 deadline，更新 `mtimecmp`，调用 `xTaskIncrementTick()`，必要时切换 task |
| `0x0000000b` machine `ecall` | `mepc += 4`，调用 `vTaskSwitchContext()` |
| `0x00000003` `ebreak` | 进入 fatal hook，首轮不静默继续 |
| 其他同步 trap | 输出最小诊断并停止，首轮不尝试恢复 |
| machine external interrupt | 交给应用 IRQ hook；首轮没有来源时视为 fatal |

timer 使用累计 deadline：

```text
next_compare += timer_counts_per_tick
```

不得在 handler 中使用 `now + interval`，否则 ISR latency 会逐 tick 积累为时钟漂移。
仿真与上板允许使用不同的 `configCPU_CLOCK_HZ`，但必须由构建参数显式给出，不能在
应用源码中写死。

## Critical section

首轮是单核 M-mode-only 系统：

- `portDISABLE_INTERRUPTS()` 清 `mstatus.MIE`；
- `portENABLE_INTERRUPTS()` 置 `mstatus.MIE`；
- `portENTER_CRITICAL()` / `portEXIT_CRITICAL()` 使用 kernel 的
  `vTaskEnterCritical()` / `vTaskExitCritical()`；
- `portCRITICAL_NESTING_IN_TCB=1`，nesting 属于各自 task；
- critical section 中 timer 可以 pending，但不能进入 handler；退出最外层后应立即响应。

首轮不支持 nested IRQ priority，也不从 ISR 调用普通 UART/VGA/buzzer driver。

## 构建与目录边界

新增 profile：

```text
FIRMWARE_PROFILE=freertos
```

建议文件：

```text
third_party/FreeRTOS-Kernel/           固定的官方 kernel
firmware/freertos/FreeRTOSConfig.h     全仓唯一 FreeRTOS 配置
firmware/freertos/portmacro.h          RV32I 类型、yield、critical 宏
firmware/freertos/port.c               初始 frame、scheduler、trap dispatch
firmware/freertos/freertos_hooks.c     assert、stack overflow、静态 idle memory
firmware/tests/freertos_smoke.c         tick/yield/delay/抢占 smoke
firmware/tests/freertos_queue.c         静态 producer/consumer queue demo
sim/tb_freertos_smoke.v                 通用 FreeRTOS MiniSoC 验收 bench
```

首轮不新增 `port_context.S`；只有实际证明 C 无法可靠构造初始 frame 时才允许增加最小
汇编 helper。`trap_entry.S` 只暴露公共 restore label。

首轮 kernel source 只包含：

```text
tasks.c
queue.c
list.c
```

不包含 `timers.c`、`event_groups.c`、`stream_buffer.c` 或 `heap_4.c`。构建使用
function/data sections 与 linker GC，避免未使用的 kernel 和通用 driver 占用 64 KiB
BRAM image。

不同 demo 通过 `FIRMWARE_MAIN` 选择应用，共用同一个 profile、kernel、port、bitstream
和 bootloader：

```text
make freertos-smoke
make freertos-queue
make freertos-bad-apple
```

输出隔离到：

```text
firmware/build/freertos/<demo>/firmware.{elf,bin,mem,lst}
```

## 内存策略

第一阶段全部使用静态分配：

- kernel text/rodata 放 BRAM；
- TCB 与两个小 task stack 放 BRAM `.bss`；
- ISR stack 继续使用公共 trap runtime 的独立 BRAM stack；
- task stack 显式 16-byte 对齐；
- 不链接 FreeRTOS heap；
- kernel 加入后检查 BRAM section 与最终 `.bin`，不能用包含 SDRAM NOLOAD 的总
  `bss` 数字误判 BRAM 占用。

BRAM smoke 通过后，再增加独立 `freertos_sdram_stack_smoke`，把相同 task stack
迁到 `.sdram_bss`，测量 context switch cycle。这个实验不是 FreeRTOS 首次接入门槛，
也不得与第一个 context switch 同时调试。

## Demo 边界

FreeRTOS 是通用运行 profile，不绑定 Bad Apple。至少保留：

1. `freertos-smoke`：两个 task 使用不同 register signature，覆盖主动 yield、timer
   抢占和 `vTaskDelay()`；
2. `freertos-queue`：静态 producer/consumer queue，证明阻塞与唤醒；
3. `freertos-bad-apple`：综合应用。

Bad Apple 使用：

```text
video/playback task
  -> 解析时间线与 frame diff
  -> 唯一写 VGA
  -> 把 audio_event 写入静态 queue

audio task
  -> 阻塞等待 queue
  -> 唯一写 buzzer
```

首轮不为每个外设引入 mutex。status/log task 可在基础播放通过后增加，不能让 9600
baud UART 阻塞影响视频或 audio task 的验收。

## 自动化验证与阶段门

实施必须逐阶段推进；当前阶段未通过，不进入下一阶段。

### Gate 0：公共基础

自动化：

```bash
python3 scripts/test_runner.py run-suite platform --keep-going
python3 scripts/test_runner.py run-suite rv32mi_dark --keep-going
python3 scripts/test_runner.py run-suite rv32i_safe --keep-going
python3 scripts/test_runner.py run-suite soc --keep-going
```

人工：ISE Map 无 overmap、PAR 后 50 MHz slack 为正、timer IRQ smoke 上板通过。

### Gate 1：首个 task

- 构建后检查 ELF/section/BRAM image size；
- task 参数、入口 PC、SP 对齐和 task return hook 有定向仿真；
- 尚不启用周期 tick，只证明首个 task 可恢复执行。

### Gate 2：主动 yield

- 两个 task 通过 `ecall` 交替执行至少 1000 次；
- 每个 task 的 callee-saved register signature 保持正确；
- `mepc` 精确跳过 `ecall`。

### Gate 3：timer 抢占与 delay

- 两个不主动 yield 的 task 被 timer 稳定抢占；
- `vTaskDelay()` 在预期 tick 唤醒；
- timer 落在 memory stall 中时延后到完整指令边界；
- critical section 内只产生 pending，退出后立即处理。

### Gate 4：queue demo

- 静态 queue 顺序、满/空和阻塞唤醒正确；
- producer/consumer 运行固定数量消息后用 `test_exit` 报告 PASS；
- 不依赖 UART 文本作为唯一判据。

### Gate 5：回归与上板

- `baremetal` 默认构建行为不变；
- FreeRTOS smoke/queue 加入 test catalog；
- `platform`、`soc`、`rv32i_safe`、`rv32mi_dark` 全部通过；
- ISE Map/PAR/timing 通过；
- 上板 smoke 的 LED/UART 现象与同一 firmware 仿真一致。

任何自动化无法覆盖的 ISE、串口或真实板级步骤，都必须记录明确操作、预期输出和失败
诊断；由开发者完成并回传结果后，才允许进入依赖该 gate 的下一阶段。

## 非目标

- PicoRV32 FreeRTOS port；
- SMP、用户态或权限隔离；
- dynamic task creation 与 `heap_4.c`；
- tickless idle、software timer、event group、stream buffer；
- nested interrupt priority；
- FreeRTOS-aware GDB；
- 首轮就把 task stack 放进 SDRAM；
- 在 FreeRTOS bring-up 阶段同时重写 Bad Apple player。
