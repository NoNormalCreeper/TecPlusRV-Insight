# DarkRISCV Wrapper Summary

分支：`darkriscv-wrapper`

## 迁移说明

这一轮最重要的不是“多了一颗核”，而是**组内理解模型和内部边界变了**。

### 不变的契约

以下内容继续视为稳定契约：

- 软件可见 memory map
- MMIO 地址与语义
- `firmware/drivers/mmio.h` 的访问方式
- `test_exit` / `LED` / `UART` 的板级观测语义

这意味着：

- firmware 开发者基本不需要改原有驱动心智模型
- MMIO 外设开发者仍然按 `tinybus_decode + 顶层寄存器行为` 的方式扩展

### 改变的契约

变的是 **CPU 和 SoC 内部互连的契约**。

旧模型：

```text
CPU
-> 单一 mem_* 访问口
-> BRAM / TinyBus / MMIO
```

新模型：

```text
CPU core
-> wrapper
-> ifetch_*   (指令口)
-> mem_*      (数据口)
-> SoC fabric
-> BRAM / MMIO / future memory
```

对应当前实现：

- `I-bus -> ifetch_*`
- `D-bus -> mem_*`

所以现在必须明确区分：

- **可执行存储**：必须被 `ifetch_*` 看见
- **普通外设 / 数据设备**：主要挂在 `mem_*`

### SoC 内部到底变了什么

这里最容易被忽略的是：**这次不是只在顶层多包了一层 wrapper，而是把 SoC 里“CPU 请求如何进入存储/外设”的内部流向改了。**

#### 旧 SoC 的实际工作方式

旧版 MiniSoC 可以近似理解成：

```text
PicoRV32
  -> mem_valid / mem_addr / mem_wdata / mem_wstrb
  -> top 内部单一 pending/respond 状态机
  -> BRAM 或 TinyBus/MMIO
```

它的关键特点是：

- CPU 只有一个统一访问口
- 取指、load/store、MMIO 都走同一套 `mem_*`
- SoC 顶层只维护一套请求状态：`pending + req_* + respond`
- BRAM 也是单口模型，CPU 的所有存储流量都复用这一口

所以旧模型下，大家很容易自然形成一个认知：

> “CPU 发一个请求，SoC 决定它是去 BRAM 还是去 MMIO，仅此而已。”

这个认知对 PicoRV32 是成立的。

#### 新 SoC 的实际工作方式

新实现不再是“一套统一存储流量”，而是**两条并行但语义不同的内部通路**：

```text
DarkRISCV
  -> I-bus  -> ifetch_* -> BRAM port B
  -> D-bus  -> mem_*    -> old data/MMIO path
```

PicoRV32 则仍然保持兼容模式：

```text
PicoRV32
  -> mem_*    -> old data/MMIO path
  -> ifetch_* -> 未使用
```

也就是说，现在 SoC 顶层内部其实同时存在两套小互连逻辑：

1. **取指通路**
   - 输入：`ifetch_valid / ifetch_addr`
   - 当前只允许访问 BRAM 窗口
   - 通过双口 BRAM 的第二口返回 `ifetch_rdata`
   - 顶层用 `ifetch_pending` 实现一个固定的一拍同步读返回

2. **数据通路**
   - 输入：`mem_valid / mem_addr / mem_wdata / mem_wstrb`
   - 继续沿用旧版 `pending / req_* / respond / mem_ready`
   - 可以去 BRAM 数据口，也可以去 TinyBus/MMIO

所以现在的 SoC 不是“一个 CPU 请求口 + 一个互连状态机”，而更接近：

> “一个取指微通路 + 一个数据/MMIO 微通路，共同组成当前最小 SoC fabric。”

#### BRAM 的角色怎么变了

旧版 BRAM 是单口，只是“CPU 统一内存窗口”的实现。

新版 BRAM 变成了**双口，并且两个端口角色已经固定**：

- **port A**：数据访问口
  - 承接 `mem_*` 里的 BRAM load/store
- **port B**：指令取指口
  - 承接 `ifetch_*`

这件事的后果很直接：

- 指令取值不再和 MMIO / 数据写回抢同一个端口
- DarkRISCV 的 Harvard 语义在 SoC 里第一次真正落地
- “BRAM 是可执行存储”这件事从隐含前提变成了明确结构

#### TinyBus 的角色怎么变了

TinyBus 本身没改成另一套协议，但它的**地位**变了。

旧版可以把 TinyBus 理解成“统一存储访问中的 MMIO 分支”。

新版更准确的理解是：

- TinyBus 只挂在 `mem_*` / `D-bus` 一侧
- TinyBus **不是** 取指通路的一部分
- 所以一个地址块如果只接到 TinyBus，就只是数据/MMIO 可见，不自动意味着“能从这里执行代码”

这也是为什么以后如果要支持：

- SDRAM 执行
- Flash/XIP 执行
- instruction cache

你不能只在数据路径上把它接进来，还必须决定 `ifetch_*` 怎么到它那里。

#### 状态机和握手语义怎么变了

旧版 SoC 顶层只有一套握手语义：

- CPU 发 `mem_valid`
- 顶层锁存成 `req_*`
- 下一拍或若干拍后给 `mem_ready`

现在有两套不同节奏的握手：

- **取指口**
  - 不是 `mem_ready` 语义
  - 是 `ifetch_valid -> ifetch_pending -> ifetch_ready`
  - 当前假定为 BRAM 一拍同步读

- **数据口**
  - 继续是 `mem_valid / mem_ready`
  - MMIO stall、UART ready、test_exit 等都仍然在这一侧发生

所以对 SoC 开发者来说，最重要的新事实是：

> 现在不是“一种访问语义”，而是“取指握手”和“数据握手”两种访问语义并存。

#### 现阶段这个结构的边界

当前实现是**的中间态**，不是最终总线。

它已经做到：

- wrapper 层把 PicoRV32 / DarkRISCV 的差异收住
- SoC 外壳和软件契约保持稳定
- DarkRISCV 可以在现有系统里真实使用 I/D 分离

但它也明确还没做到：

- `ifetch_*` 进入真正通用的 master-slave fabric
- 非 BRAM 可执行存储支持
- cache / SDRAM / 多主设备仲裁

因此，这一版最准确的理解不是“总线已经定稿”，而是：

> CPU 边界已经稳定，SoC 内部互连正在从单口模型过渡到显式区分取指与数据访问的模型。

### 各类开发者需要适配什么

**firmware 开发者**

- 基本不需要改 MMIO 用法
- 新增了 `FIRMWARE_MAIN=/abs/path/to/test.c scripts/build_firmware.sh` 这种入口切换方式，便于写裸机自检和 benchmark
- 默认 `baremetal` profile 不链接 trap runtime；DarkRISCV timer IRQ 使用显式 `dark_irq` profile
- 后续 FreeRTOS 与 GDB stub 必须复用现有 canonical trap frame 和唯一 `mtvec` 汇编入口

**MMIO / 外设开发者**

- 原来的寄存器开发方式不变
- 但不要再隐含假设“CPU 所有访问都走同一口”
- 你们做的是 `D-bus` 可见设备，不是默认可执行存储

**SoC / fabric 开发者**

- 现在要把 `ifetch_*` 和 `mem_*` 当成两条语义不同的通路
- 当前实现里，DarkRISCV 的 `ifetch_*` 直接接双口 BRAM 第二口
- 所以目前默认只有 BRAM 窗口是可执行存储
- 如果以后要让 SDRAM / Flash 执行代码，必须把 `ifetch_*` 一起纳入新的 fabric / bus 设计
- 另外要知道：顶层现在不是一个统一状态机，而是“取指一套小状态 + 数据/MMIO 一套旧状态机”并存

**验证 / 回归开发者**

- “通过”不再等于“Pico 能启动”
- 现在默认回归要求：同一批程序在 PicoRV32 和 DarkRISCV 上都跑出一致的 SoC 结果

### 现在组内最该统一的一句话

> 稳定的是“软件契约 + wrapper 边界”，不是当前 SoC fabric 的具体内部实现。

以后就算继续改 master-slave / cache / SDRAM，也应该主要替换 fabric，而不是推翻 firmware、双核对比基线和整体理解模型。

## 自动化性能对比

最终性能实验入口是：

```bash
make perf
```

它会构建并分别运行 PicoRV32 / DarkRISCV 的 `perf_mix`、系统级滑动窗口程序，以及来自 `riscv-tests` 的 `median`、`memcpy`。每次运行会保存原始 UART 日志、CSV、Markdown 汇总表和环境快照；完整 workload、指标口径与瓶颈分析方式见 `docs/BENCHMARKS.md`。

`scripts/compare_cpu_perf.sh` 保留为只看 `perf_mix` 最终 mixed case 的快速兼容入口，不再作为课程报告的主数据来源。

需要注意：`cycle` / `instret` 来自 core-backed counter source；DarkRISCV 的 `instret` 来自内部 `CSRINS`。因此应首先确认同一 workload 的两核 `instret` 一致，再比较 CPI；板上频率则必须以 ISE post-route timing report 为准，不能直接使用 1 MHz testbench 的换算值。

### Counter source 一致性回归

现在额外有两条专门的回归用来验证 MMIO 读到的 `cycle` / `instret` 是否真的来自对应 CPU 的 backing counter：

```bash
sim/run_sim.sh minisoc_counter_source_pico
sim/run_sim.sh minisoc_counter_source_dark
```

这两条测试会在 `test_exit` 后直接对比：

- MiniSoC MMIO 侧看到的 counter
- PicoRV32 的 `count_cycle` / `count_instr`
- DarkRISCV 的 `CSRCLK` / `CSRINS`

这样后续如果有人又把顶层改回 SoC 代理计数，这里会先红。

## Machine trap 与 firmware profile

DarkRISCV wrapper 现在额外接受 `irq_external` / `irq_timer`，MiniSoC 第一版把 external IRQ 固定为 0，把 CLINT-like machine timer 的 level IRQ 接到 MTIP。软件侧固定三类长期 profile：

- `baremetal`：默认不开 IRQ，保持现有程序与 PicoRV32 路径不变。
- `freertos`：已实现的 DarkRISCV-only 静态镜像；复用官方 kernel，但使用 TecPlusRV 专用薄 port，scheduler 通过 `trap_dispatch()` 返回新的 canonical frame。
- `gdb-stub`：后续 DarkRISCV-only 静态镜像，复用同一 frame 进入 remote loop。

当前已实现的 `dark_irq` 是后两者共用的基础验收 profile，不是第四种长期产品形态。FreeRTOS 和 GDB stub 都不得重新定义 frame，也不得另建第二个 `mtvec` 入口。

FreeRTOS TCB 的 `pxTopOfStack` 固定指向该 task 最近保存的 canonical frame。首个 task
由 `pxPortInitialiseStack()` 在静态 stack 顶部构造同样的 frame；critical nesting 使用
FreeRTOS-Kernel V11.3.0 的 TCB 字段，不占用公共 frame 的 `reserved`。详细设计见
[`FREERTOS_PORT_DESIGN.md`](FREERTOS_PORT_DESIGN.md)。

当前 FreeRTOS-Kernel 固定为 `V11.3.0` / commit
`9b777ae5c5b8e9e456065a00294d1e5f5f9facf5`。自动 gate 包含 build contract、初始
frame、首任务、ecall yield、timer 抢占/delay/critical 与静态 queue，运行：

```bash
make test-freertos
```

`freertos` suite 已接入 `local/all`。50 MHz smoke payload 当前 `.text=5355 B`、
`.data=4 B`、BRAM `.bss=6096 B`、`.bin=11460 B`；queue payload 为
`.text=8189 B`、`.data=4 B`、BRAM `.bss=6208 B`、`.bin=14420 B`。SDRAM
NOLOAD heap 不计入 BRAM image。

## ISE 使用方式

除了本地仿真，当前也已经可以在 ISE 里把同一个 `tecplus_minisoc_top` 切到不同 CPU 实现，用来做资源和时序对比。

### 在 ISE 里如何切换 CPU

当前 `tecplus_minisoc_top` 的 `CPU_IMPL` 参数约定是：

- `0`：PicoRV32
- `1`：DarkRISCV

最直接的做法是在 ISE 里给综合顶层覆写 parameter：

1. 选择顶层 `tecplus_minisoc_top`
2. 右键 `Synthesize - XST`
3. 打开 `Process Properties`
4. 在 `Generics, Parameters` 中填写：

```text
CPU_IMPL=1
```

这样本次综合/实现就会切到 DarkRISCV；改回 `CPU_IMPL=0` 就是 PicoRV32。


### 怎么确认 ISE 里真的切到了 DarkRISCV

`Design Summary` 里只会显示顶层名字 `tecplus_minisoc_top`，不会直接告诉你 `CPU_IMPL` 当前是多少。

因此不要只看：

- `Design 'tecplus_minisoc_top'`
- `Number of errors: 0`

这些只能说明设计成功综合 / map，不足以证明当前核已经切换。

真正应该确认的是层次结构。当前 wrapper 里的 generate 名称已经固定：

- `g_darkriscv`：表示 `CPU_IMPL == 1`
- `g_picorv32`：表示 `CPU_IMPL == 0`

因此在 ISE 报告里应重点搜索：

- `g_darkriscv`
- `darkriscv_adapter`
- `darkriscv`

或反过来搜索：

- `g_picorv32`
- `picorv32_adapter`
- `picorv32`

最适合看的位置：

1. `Map Report` 的 `Utilization by Hierarchy`
2. `Synthesize - XST` 的 hierarchy / macro statistics
3. `Technology Schematic`

如果看到保留下来的是 `g_darkriscv` 这一支，才能说明这次 ISE 流程确实是在跑 DarkRISCV。

### ISE 报告结果应该怎么解读

当前看 ISE 报告时，至少应分开看三类结论：

1. **流程是否成功**
   - 例如 `Number of errors: 0`
   - 例如 `Map created a placed design`
   - 这说明设计已经成功 map 到目标器件

2. **当前到底是哪颗核**
   - 不能只靠顶层名判断
   - 必须看层次结构里的 `g_darkriscv` / `g_picorv32`

3. **资源和时序代价**
   - LUT / FF / Slice
   - `RAMB16BWER`
   - 后续 Place & Route / Timing Report 里的频率或 slack

### DarkRISCV timer IRQ 的硬件验收门

```bash
bash scripts/export_ise_project.sh minisoc_dark
```

导出包使用 `dark_irq` timer smoke，并包含可由 bootloader 装载的 `firmware/build/firmware.bin`。ISE 14.7 中设置 `CPU_IMPL=1`、`BOOTLOADER_ENABLE=1`、`VGA_TEXT_ENABLE=0` 后，必须同时满足：

1. Map 无 `OVERMAPPED`，Slice LUT / Register / RAMB16 均不超过容量；
2. PAR 后 50 MHz post-route timing slack 为正；
3. hierarchy/report 能确认 `machine_timer` 与 DarkRISCV interrupt CSR 未被 trim；
4. 上板 UART 输出 `timer irq pass: ticks=<次数> loops=<前台循环次数>`。

2026-07-11 已完成上述验收：Map 无 `OVERMAPPED` 且资源未超容量，PAR 后 50 MHz post-route timing slack 为 `0.462 ns`，`machine_timer` 与 DarkRISCV interrupt CSR 未被 trim；真实上板 UART 输出为：

```text
timer irq test start
timer irq pass: ticks=3 loops=46
```

该结果证明当前 revision 通过，后续 RTL 或约束变化仍必须重新检查 Map/PAR 和上板行为，不能沿用本次硬件证据。

### FreeRTOS 的独立硬件验收门

```bash
make ise-export ISE_TARGET=minisoc_freertos_dark
make freertos-load PORT=COM8
```

导出目标以 50 MHz 构建 `freertos_smoke`，并校验固定 kernel revision。ISE 中仍设置
`CPU_IMPL=1`、`BOOTLOADER_ENABLE=1`、`VGA_TEXT_ENABLE=0`。自动仿真已经通过；
FreeRTOS 自身的 Map/PAR/timing 与真实上板仍待本轮人工 Gate，不能复用 bare-metal
timer smoke 的硬件结果。成功现象是 UART `freertos smoke pass` 且 LED=5。

当前阶段真正值得做的是把 PicoRV32 和 DarkRISCV 的 ISE 结果并排记成一张表，而不是只看一份报告是否“能过”。

### 为什么 BRAM 会 100% 用满

这通常不是因为当前 firmware 程序“临时用了很多内存”，而是因为 SoC 结构本身已经**固定实例化了整块 64 KiB BRAM**。

当前 RTL 里：

- `BRAM_ADDR_WIDTH = 14`
- `BRAM_BYTES = (1 << 14) * 4 = 64 KiB`

也就是说综合器看到的是一个固定大小的 `16384 x 32-bit` 片上 RAM，而不是“按当前程序实际大小动态缩小”的存储器。

因此即使 firmware 很小，只要顶层仍然保留这块完整 64 KiB 启动 BRAM，ISE 也会把它完整映射成 FPGA block RAM。

这件事更多反映的是：

- 当前 SoC 的片上内存容量配置

而不是：

- 当前 benchmark 恰好占了多少字节

所以如果以后想腾出 BRAM 资源，必须同步缩小：

- RTL 里的 `BRAM_ADDR_WIDTH`
- linker 脚本里的 BRAM 长度
- `firmware.mem` 生成深度

只让程序变小，并不会自动让 `RAMB16BWER` 数下降。

## 新增的 regression

### 1. RTL / module 级

- `bram`
- `bram_dualport`
- `tinybus_decode`
- `mmio_test_exit`
- `uart_tx`
- 以及原有 probe / SDRAM smoke / bigboard traffic-light

### 2. 板级双核 smoke

- `sim/run_sim.sh minisoc_smoke_pico`
- `sim/run_sim.sh minisoc_smoke_dark`

两颗核都跑同一个 `tb_minisoc`，验证：

- BRAM 启动
- LED 写入
- `test_exit`
- UART 路径连通

这里的 `tb_minisoc` 现在是一个可配置 bench：

- `minisoc_smoke_*`：打开 UART / LED / `test_exit` write requirement，作为 board-top smoke
- `minisoc_*`：关闭这些额外 requirement，作为通用 firmware regression bench

### 3. firmware 双核矩阵 regression

脚本：

- `scripts/test_dual_core_regression.sh`

当前自检程序：

- `firmware/tests/smoke.c`
  - 基本启动 / LED / UART / `test_exit`
- `firmware/tests/alu_branch.c`
  - 算术与分支
- `firmware/tests/load_store.c`
  - byte / halfword / word 读写与字节使能
- `firmware/tests/counters.c`
  - `cycle` / `instret` 的基本可读性与单调性

每个程序都会分别在：

- PicoRV32
- DarkRISCV

上运行一遍；这里默认用的是通用 `minisoc_*` 目标，不再要求所有 firmware 都必须顺带触发 UART。

上运行一遍，并在 `sim/build/regression/` 留下对应日志和反汇编产物。

## 依赖变化

新增的核心依赖是本地 vendored 的 DarkRISCV：

- `rtl/core/darkriscv.v`
- `rtl/core/darkriscv_config.vh`

当前配置假设：

- RV32I
- 3-stage
- reset PC = `0x0000_0000`
- firmware 仍驻留在 BRAM 起始地址

额外的结构性依赖变化：

- DarkRISCV 现在依赖双口 BRAM 提供独立取指口
- 因此，当前实现下“可执行存储区”默认就是 BRAM 窗口
- 如果以后要支持 SDRAM/Flash 执行，必须把 `ifetch_*` 一起纳入新的 SoC fabric / bus 设计

## 计数器说明

`cycle` / `instret` 的 MMIO 地址保持不变，但当前读到的值已经改成**core-backed counter source**：

- PicoRV32: `count_cycle` / `count_instr`
- DarkRISCV: `CSRCLK` / `CSRINS`

目前它更适合作为：

- 双核可读的统一软件接口
- 基本趋势对照
- 课程阶段的第一版 per-core 性能对比口径

但它依然不是最终严谨的微架构退休统计，主要是 DarkRISCV 这里目前仍然是 `CSRINS`，比旧的 SoC 代理计数可靠得多，但还不是形式化意义上的 retire proof。

如果后面要做正式性能报告，建议把这部分再升级成更精确的 per-core 统计来源。

## 实际验证结果

本地完整验证已通过：

- `scripts/check_rtl_syntax.sh`
- `scripts/test_dual_core_regression.sh`
- `scripts/test_local.sh`

`scripts/test_local.sh` 当前会覆盖：

- 环境检查
- firmware 默认构建
- RTL 语法检查
- 关键模块 testbench
- PicoRV32 MiniSoC board-top smoke
- DarkRISCV MiniSoC board-top smoke
- MiniSoC smoke / regression bench 模式检查
- 双核 firmware regression 矩阵

## 可信度判断

### 高

- BRAM 启动路径
- DarkRISCV / PicoRV32 切核后的基础 SoC 契约一致性
- MMIO 基本访问语义
- 基本 RV32I 裸机程序在两颗核上的一致运行

### 中

- `instret` 作为性能指标的绝对精度
- 将来扩展到更复杂存储层次时，这套 `ifetch_* / mem_*` glue 的可复用程度

### 低 / 尚未验证

- ISE 综合后的资源与时序影响
- 板上真实运行
- BRAM 以外的可执行存储区支持

## 后续建议

如果下一步继续做“双核对比基线”，最合理的顺序是：

1. 保持 wrapper 边界不变
2. 用这套 regression 继续扩展更有针对性的 firmware 自检
3. 单独补性能统计口径
4. 再把 SoC fabric 往 master-slave / cache / SDRAM 方向重构

这样后续即使内部总线实现继续变化，CPU 切换与双核对比基线也不会被推倒重来。
