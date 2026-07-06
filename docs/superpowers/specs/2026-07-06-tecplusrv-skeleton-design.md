# TecPlusRV 第一版骨架设计说明

## 目标

在当前仓库中创建一个面向 TEC-PLUS Spartan-6 板卡的 TecPlusRV 课程设计第一版骨架。当前版本刻意限制在以下范围内：

- 工程目录结构
- 早期探针 RTL
- 最小 SoC 占位模块
- 裸机 firmware 骨架
- 本地仿真和 firmware 构建脚本
- 明确区分“本地可验证”和“必须实验室验证”的文档

当前版本不尝试完成完整 SoC、SDRAM 控制器或完整板级 bring-up 流程。

## 范围

### 包含

- 探针 0 的 LED / KEY 顶层和 UCF
- 探针 1 的 UART TX 顶层和 UCF
- UART TX RTL 和 UART 模块 testbench
- TinyBus 地址映射头文件和占位译码器
- BRAM 模型和 MMIO `test_exit` 模块
- 含 startup、linker、MMIO 辅助和 `main.c` 的最小 firmware 目录
- firmware 构建脚本和 binary-to-mem 转换工具
- 在 `rtl/core/picorv32.v` 不存在时可明确 skip 的 MiniSoC testbench 骨架
- 项目文档和顶层 README

### 明确不包含

- SDRAM 控制器实现
- UART RX / echo 实现
- 完整可综合 SoC 顶层
- ISE 工程文件和实验室烧录流程
- 完整性能计数器硬件实现
- 任何“PicoRV32 已经集成完成”的暗示

## 架构划分

当前骨架按职责拆分：

- `rtl/probe/`：实验室优先的独立探针顶层
- `rtl/periph/`：可复用外设，例如 UART TX
- `rtl/soc/`：后续集成所需的总线、BRAM、MMIO 占位模块
- `firmware/`：最小裸机运行时和与地址图对应的驱动
- `sim/`：模块级以及未来 SoC 级 testbench
- `scripts/`：仅用于本地的构建和检查脚本

这样可以让第一版保持清晰，也避免把早期板级验证和未完成的 SoC 工作强耦合在一起。

## 关键设计决策

### 1. 先 probe，后 SoC

探针模块使用独立 top 和独立 UCF，因为任务说明和课程说明都明确把它们定义为早期风险排查手段。

### 2. 只用 Verilog-2001

RTL 保持在纯 Verilog-2001 范围内，不使用 SystemVerilog、设计模块中的不可综合语句，也不依赖 Vivado 专属内容，以保证和 ISE 14.7 对齐。

### 3. 本地仿真先于实验室上板

只有能在本地有意义验证的部分才在本地验证：

- UART TX 模块级时序
- firmware 镜像生成
- PicoRV32 缺失时的 MiniSoC testbench 控制流

板级相关验证仍然明确标记为实验室任务，因为当前环境不能运行 ISE，也无法访问板卡。

### 4. 占位模块必须诚实

未完成的 SoC 组件必须用清晰的占位模块和文档标出来，而不是伪装成“已经可用”。这一点对 SDRAM 和 CPU 集成尤其重要。

## 风险与缓解

### 板卡引脚和极性风险

Markdown 化的板卡文档已经足够支持起草 UCF，但生成的 UCF 仍会明确提醒：实验室现象必须和实际板卡及教学环境再次核对。

### 工具可用性风险

当前环境具备 RISC-V GCC 工具链和 Python，本地 Verilog 仿真器是否可用则需要实际检查。因此脚本必须在缺工具时给出明确报错，而不是静默失败。

### PicoRV32 可用性风险

当前仓库不包含 `rtl/core/picorv32.v`。因此文档和 testbench 都把它当作一个需要人工 vendored 的外部文件；在它存在之前，MiniSoC 仿真只走 skip 路径。

## 验证策略

### 本地

- 运行 UART TX 仿真并查看 VCD
- 生成 firmware 的 ELF、BIN、MEM
- 在 PicoRV32 缺失时运行 MiniSoC testbench 的 skip 路径

### 实验室

- LED / KEY 探针综合和板级现象
- UART 探针综合和串口现象
- ISE 下的 PicoRV32 资源适配探针
- 后续任何 MiniSoC 板级启动尝试
