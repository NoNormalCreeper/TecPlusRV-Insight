# 开发与验证流程

本文档定义 TecPlusRV 的推荐开发节奏。目标不是追求“本地过了就一定上板过”，而是尽可能把逻辑、接口、软件、集成层的问题提前在本地发现，让上板主要只剩板级与时序风险。

## 核心原则

1. 本地优先验证逻辑正确性，上板只验证平台落地正确性。
2. 模块逻辑尽量放在可仿真的 RTL 中，board top 只做端口包装、极性适配和 `inout` 连接。
3. `firmware`、`memory map`、寄存器语义在本地仿真和上板之间尽量保持一致。
4. 先过 thin probe，再碰完整 SoC。
5. 任何新功能都先补本地 testbench 或回归入口，再考虑上板。

## 本地和上板各自证明什么

本地主要证明：

- 模块行为是否符合预期
- 总线和 `MMIO` 语义是否一致
- `firmware` 构建和镜像生成是否正常
- CPU 启动、取指、访问 `test_exit` 的最小控制流是否正常
- SDRAM / 大板外设 thin probe 的控制流是否正常

上板主要证明：

- `UCF` 和真实板卡是否一致
- `reset` / `KEY` / `LED` / `UART` 极性与链路是否正确
- ISE 综合、布局布线和 `timing` 是否成立
- SDRAM 真实器件时序是否成立
- 核心板与大板的真实连接是否正确

## 推荐验证金字塔

### 第 1 层：模块级

目标：先确认单个模块本身没写错。

典型对象：

- `uart_tx`
- `mmio_test_exit`
- `sdram_smoke_ctrl`

推荐动作：

1. 为模块写独立 testbench。
2. 用 `PASS / FAIL / TIMEOUT` 或明确波形断言结束仿真。
3. 生成 `VCD`，必要时人工看波形。

### 第 2 层：子系统级

目标：确认模块拼接后协议与接口语义正确。

典型对象：

- `tinybus_decode` + `MMIO`
- `BRAM` + `firmware.mem`
- `CPU + BRAM + test_exit`

推荐动作：

1. 把真实 `memory map` 接进 testbench。
2. 优先让 testbench 直接观察寄存器行为，不先依赖板级现象。
3. 统一通过 `test_exit` 判断 `PASS / FAIL / TIMEOUT`。

### 第 3 层：板级 thin probe

目标：不引入完整 SoC 复杂度，只验证最小板级链路。

当前建议顺序：

1. `Probe 0`：`LED / KEY / RESET / CLK`
2. `Probe 1`：`UART TX`
3. `Probe 4a`：`SDRAM smoke probe`
4. `Probe 5a`：`bigboard traffic-light thin probe`

这里的关键思想是：先确认链路活着，再让完整系统上板。

### 第 4 层：最终 SoC 仿真

目标：在本地用真实 `firmware.mem` 证明最小系统集成路径成立。

要求：

- 使用真实 `rtl/core/picorv32.v`
- 使用真实 `firmware/build/firmware.mem`
- 使用统一的 `test_exit`
- 结果必须能收敛到 `PASS / FAIL / TIMEOUT`

### 第 5 层：板级 SoC bring-up

目标：在已知逻辑大致正确的前提下，只验证平台化问题。

此时如果上板失败，优先检查：

- `.ucf`
- top 端口名
- `reset` 极性
- 时钟路径
- `timing`
- SDRAM / 大板连线

不要第一反应就回头怀疑整个 SoC 逻辑。

## 每次改动建议怎么做

### 改模块 RTL

1. 先补或修改对应 testbench。
2. 先跑该模块的单独仿真。
3. 再跑：

```bash
scripts/check_rtl_syntax.sh
```

4. 如果模块会影响 SoC 级行为，再跑：

```bash
sim/run_sim.sh minisoc
```

### 改 `firmware`

1. 先构建：

```bash
scripts/build_firmware.sh
```

2. 再跑：

```bash
sim/run_sim.sh minisoc
```

3. 如果改动涉及 `MMIO` 或启动流程，优先看 `PASS / FAIL / TIMEOUT` 是否变化。

### 改 board probe

1. 先跑对应模块级或 thin-probe 本地仿真。
2. 再跑：

```bash
scripts/check_rtl_syntax.sh
```

3. 最后在实验室验证对应 `.ucf` 和真实现象。

### 改动较大时

直接跑整套本地 smoke：

```bash
scripts/test_local.sh
```

当前它会覆盖：

1. 工具链检查
2. `firmware` 构建
3. RTL 语法烟测
4. `UART TX` 仿真
5. `SDRAM smoke` 仿真
6. `bigboard traffic-light` 仿真
7. `MiniSoC` 仿真

## 上板前清单

### 代码侧

- `scripts/test_local.sh` 通过
- 新增 RTL 已通过 `iverilog -g2001`
- `firmware.mem` 已重新生成
- 文档中的地址图、寄存器语义和代码一致

### 工程侧

- ISE 工程器件型号正确：`XC6SLX9-2FTG256`
- top module 设对
- 对应 `.ucf` 已加入工程
- 没有因为改端口名导致 `.ucf` 失配

### 现象侧

- 这次上板要验证的现象只有一个或一类
- 不要一次同时验证“新 CPU + 新总线 + 新 SDRAM + 新外设”
- 如果要调完整 SoC，先确认相应 thin probe 已经成立

## 为了保持本地和上板行为一致，代码上应该怎么设计

### 1. 单一真相源

下列内容必须尽量只有一份定义：

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

不要把真正的业务逻辑塞进 board top，不然本地仿真和上板跑的就不是同一份核心逻辑。

### 3. firmware 尽量不分叉

本地仿真和上板尽量跑同一份 `firmware`。  
如果必须分叉，差异要非常小，而且要明确写清楚为什么分叉。

### 4. 统一结束语义

所有 SoC 级本地验证都尽量统一成：

- `PASS`
- `FAIL`
- `TIMEOUT`

这样后面做回归时，不需要重新发明一套判断标准。

## 当前仓库建议使用顺序

1. `Probe 0`
2. `Probe 1`
3. `PicoRV32 Minimal synthesis probe`
4. `MiniSoC simulation probe`
5. `Probe 4a`
6. `Probe 5a`
7. 板级 `MiniSoC bring-up`

如果 `Probe 0` 和 `Probe 1` 还没稳定，就不要急着上完整 SoC。

## 不能误判的几点

1. 本地仿真通过，不等于 `timing` 一定能过。
2. 本地仿真通过，不等于 `.ucf` 一定正确。
3. `Probe 4a` 通过，不等于通用 `SDRAM controller` 已经可用。
4. `Probe 5a` 通过，不等于完整显示/大板外设系统已经可用。
5. `MiniSoC simulation probe` 通过，不等于板级串口、reset、下载链路一定没问题。

## 最后一句话

本地开发要证明“逻辑正确”，上板要验证“平台成立”。  
如果把这两件事混在一起，你会在实验室里浪费大量时间做本来应该在本地发现的问题。
