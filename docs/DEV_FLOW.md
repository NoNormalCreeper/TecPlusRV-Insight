# 开发与验证流程

下面把下面几件事讲清楚：

- 现在仓库里每一部分是干什么的
- 开发时应该先写什么、后写什么
- 各模块最终怎么集合成可上板工程
- 本地应该怎么验证，哪些问题必须尽早在本地发现
- 到 ISE / 上板时，应该带哪些文件、按什么顺序验证

本文档的核心目标只有一个：**尽量把逻辑、接口、软件、集成错误提前在本地发现，让上板阶段主要只剩板级、约束和时序问题。**

## 先接受一个边界

本地仿真通过，不等于上板一定通过。

本地能够证明的是：

- RTL 逻辑行为
- 总线与寄存器语义
- `firmware` 构建与镜像生成
- 最小系统启动路径
- thin probe 的控制流

上板才能证明的是：

- `.ucf` 和真实板卡是否一致
- `reset` / `KEY` / `LED` / `UART` 极性与连线是否正确
- ISE 综合、布局布线、`timing` 是否成立
- SDRAM 这类真实器件的时序是否成立
- 核心板与大板连接是否正确

所以正确心态应该是：

- 本地开发证明“逻辑正确”
- 上板验证“平台成立”

如果把这两件事混在一起，你会在实验室里浪费大量时间做本来应该在本地就发现的问题。

## 仓库每一部分是干什么的

### `rtl/probe/`

用途：放板级早期探针顶层，目标是最小化板级验证复杂度。

当前典型文件：

- `probe_led_key_top.v`
- `probe_uart_top.v`
- `probe_sdram_smoke_top.v`
- `probe_bigboard_tl_top.v`
- `probe_buzzer_uart_top.v`
- `probe_vga_top.v`
- `probe_vga_text_top.v`
- `sdram_smoke_ctrl.v`

设计原则：

- 每个 probe 独立成 top
- 不依赖完整 SoC
- 现象尽量简单、可重复、肉眼可判断

### `rtl/periph/`

用途：放可复用外设模块。

当前典型文件：

- `uart_tx.v`
- `uart_rx.v`
- `traffic_light_gpio.v`
- `buzzer_pwm.v`
- `buzzer_tune_player.v`
- `buzzer_uart_reporter.v`
- `vga_timing_640x480.v`
- `font_rom_8x8.v`
- `vga_text_mode.v`

设计原则：

- 不和板卡强耦合
- 优先做成既能被 probe 用，也能被后续 SoC 用的模块

### `rtl/soc/`

用途：放后续 SoC 集成要用的公共模块和定义。

当前典型文件：

- `tinybus_defs.vh`
- `tinybus_decode.v`
- `bram.v`
- `mmio_test_exit.v`

设计原则：

- 尽量把地址、寄存器、存储器、退出语义这类“系统共识”放在这里
- 这些模块应优先可仿真、可复用，而不是先为板级写死

### `rtl/core/`

用途：放外部 CPU 核。

当前典型文件：

- `picorv32.v`

这里的重点不是“谁来写 CPU”，而是：

- CPU 文件位置固定
- 本地仿真和后续 ISE 工程都引用同一份 CPU 源码
- 不做自动下载，不做隐藏替换

### `constraints/`

用途：放每个板级 top 对应的 `.ucf`。

当前典型文件：

- `tecplus_led_key.ucf`
- `tecplus_uart.ucf`
- `tecplus_sdram_smoke.ucf`
- `tecplus_bigboard_tl.ucf`
- `tecplus_vga.ucf`

设计原则：

- 一个板级 top，尽量对应一份明确的 `.ucf`
- 不要把多个实验目标混在一份约束里搞得很难维护

### `firmware/`

用途：放裸机程序、启动代码、驱动、链接脚本。

当前典型文件：

- `startup.S`
- `linker.ld`
- `main.c`
- `drivers/*.h`
- `drivers/*.c`

设计原则：

- 本地仿真和上板尽量跑同一份 `firmware`
- `memory map`、驱动地址和 RTL 定义必须一致

### `sim/`

用途：放本地 testbench 和仿真入口。

当前典型文件：

- `tb_uart_tx.v`
- `tb_sdram_smoke_ctrl.v`
- `tb_bigboard_tl.v`
- `tb_minisoc.v`
- `run_sim.sh`

设计原则：

- 单模块和系统级 testbench 分开
- 尽量统一结束语义：`PASS / FAIL / TIMEOUT`

### `scripts/`

用途：放构建、检查、本地 smoke 入口。

当前典型文件：

- `check_env.sh`
- `build_firmware.sh`
- `check_rtl_syntax.sh`
- `test_local.sh`
- `bin2mem.py`

设计原则：

- 让日常本地回归变成固定命令
- 不依赖手工重复操作

补充约定：

- `scripts/test_catalog.json` 是测试编排的单一真相源。
- 新增或挂载测试时，优先改 catalog，再由 `scripts/test_runner.py` 统一编排执行。
- `sim/run_sim.sh` 和 `scripts/rtl_syntax_case.sh` 仍然保留，但只负责最底层的单 case 配方。
- `scripts/check_rtl_syntax.sh` 和 `scripts/test_local.sh` 仍然可用，但只是兼容壳，不再承担测试编排职责。

### `tests/riscv_tests/`

用途：放官方 `riscv-tests` 资产和本仓库自己的适配层。

当前典型内容：

- `riscv-tests/`：官方上游 submodule
- `riscv-tests/env/`：上游环境子模块
- `tecplus_p/`：基础 `rv32ui` 的双核 `MiniSoC` 适配环境
- `tecplus_m/`：DarkRISCV M-mode-only trap/CSR 适配环境

设计原则：

- 官方 case 尽量保持原样，不直接改测试本体
- 本地差异优先收敛在 `tecplus_p` / `tecplus_m` 这种 target environment 里
- `rv32ui` 保持 PicoRV32 / DarkRISCV 双核基线；`rv32mi` 只在 DarkRISCV 上运行，官方 case 的 `mcause/mepc` 断言不得在环境层跳过

## 整个项目怎么从“零散文件”集合起来

需要分成两条线理解：

### 线 1：本地开发与仿真线

这条线的核心输入是：

- `rtl/**/*.v`
- `rtl/**/*.vh`
- `firmware/*`
- `sim/*.v`
- `scripts/*`

这条线的目标是：

- 先得到可验证的 RTL 行为
- 再得到可运行的 `firmware.mem`
- 最后用 testbench 证明模块或最小系统逻辑成立

### 线 2：ISE / 上板线

这条线真正要带进 ISE 的不是整个仓库，而是一组**目标相关的最小输入文件集**。

ISE 真正关心的通常是：

- `*.v`
- `*.vh`
- `*.ucf`
- 导出包内的 `firmware/build/firmware.mem`（如果 BRAM 要初始化）

ISE 不关心的通常是：

- `sim/*.v` testbench
- `sim/build/*`
- `*.vcd`
- 本地 smoke 脚本
- 文档本身

这意味着：  
**从本地工程到 ISE 工程，是从仓库里挑出正确的源文件集合交给 ISE。**（后期可能会写一个脚本）

## 开发顺序应该是什么样

推荐按风险和依赖关系推进，而不是按“最终功能清单”推进。

### 阶段 0：基础链路

目标：先确认板子最底层还能用。

顺序：

1. `Probe 0`：`LED / KEY / RESET / CLK`
2. `Probe 1`：`UART TX`

如果这两步都没稳定，就不要进入完整 SoC。

### 阶段 1：本地 SoC 骨架

目标：先让本地最小系统路径成型。

顺序：

1. `tinybus_defs.vh`
2. `tinybus_decode.v`
3. `bram.v`
4. `mmio_test_exit.v`
5. `firmware` 构建链路
6. `tb_minisoc.v`

此时要能回答的问题是：

- CPU 是否能取指
- BRAM 是否能提供初始化镜像
- `MMIO` 地址语义是否对
- `test_exit` 是否能作为统一判定口

### 阶段 2：资源与平台风险

目标：在真正做更大系统前，先排资源和器件链路风险。

顺序：

1. `CPU Minimal synthesis probe`（`Probe 2a / 2b`）
2. `Probe 4a`：`SDRAM smoke probe`
3. `Probe 5a`：`bigboard traffic-light thin probe`
4. `Probe 5c`：`buzzer UART debug probe`
5. `Probe 5b`：`VGA thin probe`

此时要能回答的问题是：

- 两颗 CPU 最小配置能不能放下
- SDRAM 最小命令链路是不是活的
- 核心板到大板某一组最小输出链路是不是活的
- 蜂鸣器与串口联合调试链路是不是活的
- VGA 最小显示链路是不是活的

### 阶段 3：完整 MiniSoC bring-up

目标：在已知底层链路基本成立的前提下，把 CPU、BRAM、MMIO、probe 经验收敛成一个可上板的小系统。

这时上板应该主要验证：

- `.ucf`
- top 包装
- `timing`
- 板级现象

而不是第一次发现软件、地址图、寄存器语义或逻辑状态机写错。

## 推荐验证金字塔

### 第 1 层：模块级

目标：单个模块先证明自己没写错。

当前典型对象：

- `uart_tx`
- `uart_rx`
- `traffic_light_gpio`
- `buzzer_pwm`
- `font_rom_8x8`
- `mmio_test_exit`
- `sdram_smoke_ctrl`

要求：

1. 为模块写独立 testbench。
2. 明确结束条件。
3. 必要时生成 `VCD`。

### 第 2 层：子系统级

目标：多个模块拼起来后，协议和地址语义仍然对。

当前典型对象：

- `tinybus_decode + MMIO`
- `BRAM + firmware.mem`
- `CPU + BRAM + test_exit`

要求：

1. 尽量直接检查寄存器和内存行为。
2. 不要先依赖 LED/UART 之类板级现象。
3. 尽量统一到 `PASS / FAIL / TIMEOUT`。

### 第 3 层：板级 thin probe

目标：不引入完整 SoC 复杂度，只验证最小链路。

当前 probe：

1. `Probe 0`
2. `Probe 1`
3. `Probe 4a`
4. `Probe 5a`

这里的关键思想是：先确认链路活着，再让复杂系统上板。

### 第 4 层：最终 SoC 仿真

目标：在本地用真实 `firmware.mem` 证明最小系统启动路径成立。

要求：

- 使用真实 CPU wrapper 和 vendored CPU 核
- 使用当前目标专属的真实 `firmware/build/sim/<target>/firmware.mem`
- 使用统一的 `test_exit`
- 结果收敛到 `PASS / FAIL / TIMEOUT`

### 第 5 层：板级 SoC bring-up

目标：只验证平台化问题。

一旦这个阶段失败，优先检查：

- `.ucf`
- top 端口名
- `reset` 极性（当前核心板按低有效处理）
- 时钟路径
- `timing`
- SDRAM / 大板连线

不要第一反应就回头怀疑整个 SoC。

## 日常开发时，具体应该怎么做

### 场景 1：改模块 RTL

适用例子：

- 改 `uart_tx`
- 改 `sdram_smoke_ctrl`
- 改 `tinybus_decode`

建议顺序：

1. 先补或修改对应 testbench。
2. 先跑该模块的单独仿真。
3. 再跑：

```bash
python3 scripts/test_runner.py run-suite rtl_syntax_internal
```

4. 如果该模块影响系统行为，再跑：

```bash
make test-soc
```

### 场景 2：改 `firmware`

适用例子：

- 改 `main.c`
- 改驱动头文件
- 改 `startup.S`
- 改 `linker.ld`

建议顺序：

1. 先构建：

```bash
make firmware
```

`make firmware` 是手动默认构建，生成 `firmware/build/firmware.*`。自动仿真、regression、perf、bootload 和 ISE export 都必须通过 `FIRMWARE_OUT` 使用专属目录，不能覆盖这组默认产物。

2. 再跑：

```bash
make test-soc
```

3. 如果改动只影响软件可见结果，重点看通用 `minisoc_*` regression 是否仍然收敛。
4. 如果改动涉及 board-level UART / LED / `test_exit` 路径，再补跑 `python3 scripts/test_runner.py run-suite smoke`，或者直接跑对应的 `minisoc_smoke_*`。
5. 如果改动会影响指令执行结果、加载存储、分支跳转或启动布局，再补跑：

```bash
python3 scripts/test_runner.py run-suite rv32i_safe
```

如果改动涉及 DarkRISCV machine CSR、trap 入口或 misaligned 行为，再补跑：

```bash
python3 scripts/test_runner.py run-suite rv32mi_dark --keep-going
```

### Firmware profile 边界

- `baremetal`：默认 profile，沿用现有 startup/runtime，不链接 trap runtime，也不会主动开启 IRQ。
- `dark_irq`：当前已实现的 DarkRISCV-only 基础 profile，链接统一 trap frame 与 machine timer driver；应用仍须显式调用 `trap_init()` 和 enable helper。
- `freertos`：后续 DarkRISCV-only profile，复用同一个 trap frame；kernel 与应用静态链接成单一 payload。
- `gdb-stub`：后续 DarkRISCV-only profile，复用同一个 trap frame；`ebreak/fault` 进入 remote loop。

后两类目前只是稳定的接入契约，不是可选的现成构建值。bootloader 与 bitstream 继续共用，每次只装载一个 BRAM firmware image；FreeRTOS 是 bootloader 可装载的 payload，不是另一套 bootloader。

常用构建入口：

```bash
make firmware          # 强制 baremetal
make timer-irq-smoke   # 构建 dark_irq timer 验收镜像
```

### 场景 3：改 board probe

适用例子：

- 改 `probe_led_key_top`
- 改 `probe_uart_top`
- 改 `probe_sdram_smoke_top`
- 改 `probe_bigboard_tl_top`

建议顺序：

1. 先跑对应模块级或 thin-probe 本地仿真。
2. 再跑：

```bash
python3 scripts/test_runner.py run-suite rtl_syntax_internal
```

3. 最后再在实验室验证对应 `.ucf` 和真实现象。

### 场景 4：改动较大

直接跑整套本地 smoke：

```bash
python3 scripts/test_runner.py run-suite smoke
```

这些 suite 的覆盖关系由 `scripts/test_catalog.json` 决定。

当前它覆盖：

1. 工具链检查
2. `firmware` 构建
3. RTL 语法烟测
4. probe 类仿真
5. 平台层仿真
6. `MiniSoC` board-top smoke
7. MiniSoC smoke / regression bench 模式检查
8. 官方 `rv32i_safe` 基线

如果当前改动范围更大，可以再跑完整本地集合：

```bash
python3 scripts/test_runner.py run-suite local
```

如果当前分支还带了通用 SoC regression / 双核 regression，再跑：

```bash
python3 scripts/test_runner.py run-suite all
```

补充说明：

- `rv32i_safe` 是当前第一阶段必须稳定通过的官方 `RV32I` 子集。
- `rv32i_optional` 暂时只放边界 case，例如 `fence_i` 和 `ma_data`。
- `rv32mi_dark` 是 DarkRISCV-only machine-mode completion gate，不在 PicoRV32 上运行。
- `fence_i` 当前不纳入基线，因为这份 `PicoRV32` RTL 不支持 `fence.i`。
- `ma_data` 当前不纳入基线，因为它会开始要求明确的 misaligned / trap 语义。

## 从本地文件到 ISE 工程，应该怎么转换

这里最容易误解，所以单独说。

### 结论先说

ISE 自己做：

1. `Synthesize`
2. `Implement Design`
3. `Generate Programming File`

你需要做的是：

- 从仓库中挑出这次目标所需的最小源文件集合
- 把它们加入 ISE 工程
- 设对 top module
- 加入对应 `.ucf`

如果只是想先拿到一个便于复制的最小文件包，现在可以直接用：

```bash
make ise-export ISE_TARGET=minisoc
make ise-export ISE_TARGET=probe_uart
make ise-export ISE_TARGET=probe_minisoc_sdram
```

导出目录默认是 `build/ise-export/<target>/`。仓库中的构建产物放在 `firmware/build/ise/<target>/firmware.*`；导出脚本只把对应 `.mem` 复制到导出包内的 `firmware/build/firmware.mem`，保持 RTL 默认 `$readmemh` 相对路径，同时不改写仓库的手动默认产物。

### ISE 一般真正需要的输入

- `rtl/**/*.v`
- `rtl/**/*.vh`
- `constraints/*.ucf`
- 导出包内的 `firmware/build/firmware.mem`（如果设计依赖 BRAM 初始化）

### ISE 一般不需要的输入

- `sim/*.v` testbench
- `sim/build/*`
- `*.vcd`
- `scripts/test_local.sh`
- `sim/run_sim.sh`
- 文档文件

### Probe 工程最小文件集示例

#### Probe 0

- `rtl/probe/probe_led_key_top.v`
- `constraints/tecplus_led_key.ucf`

#### Probe 1

- `rtl/probe/probe_uart_top.v`
- `rtl/periph/uart_tx.v`
- `constraints/tecplus_uart.ucf`

#### Probe 4a

- `rtl/probe/probe_sdram_smoke_top.v`
- `rtl/probe/sdram_smoke_ctrl.v`
- `constraints/tecplus_sdram_smoke.ucf`

#### Probe 5a

- `rtl/probe/probe_bigboard_tl_top.v`
- `constraints/tecplus_bigboard_tl.ucf`

### MiniSoC 工程最小文件集思路

需要的通常包括：

- `rtl/core/picorv32.v`
- `rtl/core/darkriscv.v`
- `rtl/soc/tecplus_cpu_wrapper.v`
- `rtl/soc/picorv32_adapter.v`
- `rtl/soc/darkriscv_adapter.v`
- `rtl/soc/bram_dualport.v`
- `rtl/soc/*.v`
- `rtl/soc/tecplus_minisoc_top.v`
- `rtl/periph/uart_tx.v`
- `constraints/tecplus_minisoc.ucf`
- 当前 ISE target 专属的 `firmware/build/ise/<target>/firmware.mem`

注意这里的 `firmware.mem` 不是 ISE 输出，而是 ISE 的输入之一。

所以如果是 SoC 路线，推荐直接让导出目标构建并打包自己的 firmware：

```bash
make ise-export ISE_TARGET=minisoc
```

## ISE 里实际应该怎么操作

### 新建工程时

1. 新建 ISE 工程
2. 器件型号选 `XC6SLX9-2FTG256`
3. 加入本次目标所需的 `*.v` / `*.vh`
4. 加入对应 `.ucf`
5. 设对 top module

### 编译时

1. `Synthesize`
2. `Implement Design`
3. `Generate Programming File`

如果当前目标是切换 CPU 核，还需要在 `Synthesize - XST` 的 `Generics, Parameters` 中确认：

- `CPU_IMPL=0`：PicoRV32
- `CPU_IMPL=1`：DarkRISCV

### 如果需要 BRAM 初始化

在综合前确认：

- 导出包内的 `firmware/build/firmware.mem` 已由当前 ISE target 重新生成
- ISE 工程工作目录下能正确找到该文件
- Map report 里 64 KiB 启动内存应主要消耗 `RAMB16BWER` / `RAMB8BWER`；如果看到大量 `Slice LUTs used as Memory`，说明 BRAM 没有被正确推断。

### 什么时候需要手工改引脚

如果：

- 顶层端口名和仓库一致
- 你使用了仓库里的对应 `.ucf`

那通常不需要在 ISE GUI 里手工一根根重新分配引脚。

真正需要手工改引脚，通常是这些情况：

- 实验室实际板卡版本与当前 `.ucf` 不一致
- 你改了顶层端口名
- 你换了 probe 或改了连线方案

## 上板前清单

### 代码侧

- `scripts/test_local.sh` 当前会卡在既有的 `sdram_data_ctrl`，报 `FAIL: init PRECHARGE not ALL banks`
- 新增 RTL 已通过 `iverilog -g2001`
- `firmware.mem` 已重新生成（如果本次目标需要）
- 文档中的地址图、寄存器语义和代码一致

### 工程侧

- ISE 工程器件型号正确：`XC6SLX9-2FTG256`
- top module 设对
- 对应 `.ucf` 已加入工程
- 没有因为改端口名导致 `.ucf` 失配

### 目标侧

- 这次上板只验证一个明确目标
- 不要一次同时验证“新 CPU + 新总线 + 新 SDRAM + 新外设”
- 如果要调完整 SoC，先确认相应 thin probe 已经成立

## 实验室上板建议顺序

### 顺序 1：基础链路

1. `Probe 0`
2. `Probe 1`

目的：

- 确认时钟进了 FPGA
- 确认 `RESET` 低有效极性理解正确
- 确认最基本的输入输出链路活着

### 顺序 2：资源和系统前置风险

1. `Probe 2a / 2b`
2. `MiniSoC dual-core simulation probe`

目的：

- 先看两颗核的资源和时序是否都能接受
- 先看本地双核最小系统启动路径，以及 board-top smoke 路径是否都打通

### 顺序 3：板级扩展风险

1. `Probe 4a`
2. `Probe 5a`

目的：

- 先确认 SDRAM 最小命令链路
- 先确认大板某一组最小外设链路

### 顺序 4：完整 MiniSoC bring-up

只有前面都大致成立后，才建议进入完整 SoC 板级启动。

## 如果上板失败，应该怎么定位

### 情况 1：Probe 0 都不对

优先查：

- `.ucf`
- `reset` 极性
- `KEY` / `LED` 管脚
- 时钟是否真的进来

不要先怀疑 SoC。

### 情况 2：Probe 0 正常，Probe 1 串口不对

优先查：

- `TXD` 管脚
- 串口参数 `9600 8N1`
- 终端端口号
- `reset` 是否因为低有效理解错误而一直有效

### 情况 3：本地 `MiniSoC` 过了，但板上不工作

优先查：

- `.ucf`
- BRAM 初始化是否真的生效
- top 是否接对
- ISE `timing`
- 板级 `reset` / `UART`

### 情况 4：Probe 4a 失败

优先查：

- SDRAM 那一组 `.ucf`
- 控制线和数据线是否绑错
- `50MHz` 假设是否过于激进
- 真实板上是否就是文档对应那组 SDRAM

### 情况 5：Probe 5a 失败

优先查：

- 核心板与大板连接
- 交通灯那组输出管脚
- 是否需要额外排线
- 观察的是否真的是对应外设区

## 为了让本地和上板尽量一致，代码上应该怎么设计

### 1. 单一真相源

下列内容尽量只有一份定义：

- `memory map`
- 寄存器地址
- bit 含义
- reset 默认值

建议同步维护：

- `docs/MEMORY_MAP.md`
- `rtl/soc/tinybus_defs.vh`
- `firmware/drivers/*.h`

### 2. board top 尽量变薄

board top 最好只做：

- 端口展开
- `inout` 包装
- 极性适配
- 与 `.ucf` 的绑定

不要把真正业务逻辑塞进 board top，不然本地仿真和上板跑的就不是同一份核心逻辑。

### 3. firmware 尽量不分叉

本地仿真和上板尽量跑同一份 `firmware`。  
如果必须分叉，差异要非常小，而且要明确写清楚原因。

### 4. 统一结束语义

所有 SoC 级本地验证尽量统一成：

- `PASS`
- `FAIL`
- `TIMEOUT`

这样后面做回归时，不需要重新发明一套判断标准。

### 5. thin probe 和 full 系统明确分层

- `Probe 4a` 通过，不等于通用 `SDRAM controller` 已可用
- `Probe 5a` 通过，不等于完整显示/大板外设系统已可用

thin probe 的价值是早发现底层风险，不是替代后续完整系统。

## 当前仓库推荐使用顺序

1. `Probe 0`
2. `Probe 1`
3. `Probe 2a`
4. `Probe 2b`
5. `MiniSoC dual-core simulation probe`
6. `Probe 4a`
7. `Probe 5a`
8. 板级 `MiniSoC bring-up`
9. UART bootloader：模块仿真 -> 双核 SoC 仿真 -> ISE -> RESET 重复下载

如果 `Probe 0` 和 `Probe 1` 还没稳定，就不要急着上完整 SoC。

## UART bootloader 开发与上板顺序

bootloader v1 固定走 `UART -> BRAM 0x0000_0000 -> CPU release`。默认 MiniSoC 参数 `BOOTLOADER_ENABLE=0`，因此旧 firmware 回归仍直接使用 `firmware.mem`；只有 bootloader ISE 目标需要把参数设为 1。

本地先跑：

```bash
./sim/run_sim.sh bootloader_ctrl
./sim/run_sim.sh bootloader_pico
./sim/run_sim.sh bootloader_dark
python3 scripts/test_uart_loader.py
```

再构建真实 payload 并检查封包：

```bash
FIRMWARE_MAIN="$PWD/firmware/tests/boot_payload.c" \
FIRMWARE_OUT=firmware/build/manual/boot_payload \
  ./scripts/build_firmware.sh
python3 scripts/uart_loader.py \
  --input firmware/build/manual/boot_payload.bin \
  --dry-run
```

ISE 导出：

```bash
make ise-export ISE_TARGET=minisoc_bootloader
```

导入后在 ISE 的 `Generics, Parameters` 中设置 `BOOTLOADER_ENABLE=1`。Windows + WSL2 上板，可参考文档 WINDOWS_WSL_UART.md，推荐让串口留在 Windows，并在 WSL 执行：

```bash
make bootload PORT=COM8
```

该目标会依次构建、上传并进入 serial monitor。看到提示后按下并松开 RESET；收到 READY 后发送，收到 ACK 后 CPU 才运行。换程序只需退出 monitor、再次执行该目标并按 RESET，不需要重新下载 bitstream。

协议字段、错误码和真实串口命令统一以 `docs/BOOTLOADER_PROTOCOL.md` 为准，不要在其他文档复制另一套常量。

## 不能误判的几点

1. 本地仿真通过，不等于 `timing` 一定能过。
2. 本地仿真通过，不等于 `.ucf` 一定正确。
3. `Probe 4a` 通过，不等于通用 `SDRAM controller` 已经可用。
4. `Probe 5a` 通过，不等于完整显示/大板外设系统已经可用。
5. `MiniSoC dual-core simulation probe` 通过，不等于板级串口、reset、下载链路一定没问题。

## 最后一句话

本地开发要证明“逻辑正确”，上板要验证“平台成立”。  
能在本地先发现的问题，就不要留到实验室。  
能用 thin probe 先排掉的板级风险，就不要带着完整 SoC 一起去赌。 
