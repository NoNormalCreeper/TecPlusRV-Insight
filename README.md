# TecPlusRV

TecPlusRV 是一个面向 TEC-PLUS Spartan-6 XC6SLX9-2FTG256 平台的 RISC-V SoC 课程设计第一版骨架仓库。

当前版本只聚焦于：

- 工程目录骨架
- 早期板级探针
- 可复用的 UART TX RTL
- 最小 SoC 占位模块
- 裸机 firmware 骨架
- 本地构建和仿真入口

当前版本还不提供：

- 完整 SoC 顶层
- 通用 SDRAM 控制器
- ISE 工程文件或 bitstream

## 仓库结构

- `rtl/probe/`：早期上板探针顶层
- `rtl/periph/`：可复用外设
- `rtl/soc/`：地址映射、BRAM、MMIO 占位模块
- `rtl/core/`：外部 CPU 核，例如后续放入的 `picorv32.v`
- `rtl/accel/`：后续扩展加速器
- `constraints/`：TEC-PLUS 约束文件
- `firmware/`：裸机启动代码、链接脚本、驱动和测试
- `sim/`：本地 testbench
- `scripts/`：本地构建和检查脚本

## 推荐先读

- 项目目标与边界：`docs/PROJECT_SPEC.md`
- 探针说明：`docs/PROBES.md`
- 开发与验证流程：`docs/DEV_FLOW.md`

## 最简单环境配置教程

下面这套命令以 Ubuntu 22.04 / WSL2 Ubuntu 为例，目标是把本仓库当前需要的本地工具一次装齐。

### 1. 安装基础工具

```bash
sudo apt update
sudo apt install -y \
  python3 \
  make \
  iverilog \
  gcc-riscv64-unknown-elf \
  binutils-riscv64-unknown-elf
```

这几个包分别用于：

- `python3`：运行 `bin2mem.py`
- `make`：通用构建辅助工具，虽然当前脚本不强依赖，但建议一起装
- `iverilog`：本地 Verilog 编译/仿真
- `gcc-riscv64-unknown-elf`：生成 RV32I 裸机程序
- `binutils-riscv64-unknown-elf`：提供 `objcopy`、`objdump`

### 2. 确认工具已就绪

```bash
scripts/check_env.sh
```

如果环境正常，应该能看到这些工具都显示为 `[ok]`。

### 3. 跑一遍本地 smoke

```bash
scripts/test_local.sh
```

这条命令会顺序执行：

1. 本地工具检查
2. firmware 构建
3. RTL 语法烟测
4. UART TX 仿真
5. SDRAM smoke 控制器仿真
6. bigboard traffic-light 仿真
7. MiniSoC 骨架仿真

## 常用本地命令

检查工具环境：

```bash
scripts/check_env.sh
```

检查 RTL 语法：

```bash
scripts/check_rtl_syntax.sh
```

运行当前本地 smoke：

```bash
scripts/test_local.sh
```

单独构建 firmware：

```bash
scripts/build_firmware.sh
```

单独跑 UART TX 仿真：

```bash
sim/run_sim.sh uart_tx
```

单独跑 MiniSoC 骨架：

```bash
sim/run_sim.sh minisoc
```

单独跑 SDRAM smoke 控制器仿真：

```bash
sim/run_sim.sh sdram_smoke
```

单独跑 bigboard traffic-light 仿真：

```bash
sim/run_sim.sh bigboard_tl
```

如果 `rtl/core/picorv32.v` 不存在，MiniSoC testbench 会输出 `SKIP`，而不是假装通过。

## 第一次上手怎么做

如果你现在只是想确认这套骨架是不是“活的”，不要一上来就做完整 SoC，按下面顺序走。

### 第 1 步：本地确认仓库骨架没坏

```bash
scripts/test_local.sh
```

你应该看到几类结果：

- firmware 构建成功
- `uart_tx` 仿真输出 `PASS`
- `minisoc` 仿真在没有 `rtl/core/picorv32.v` 时输出 `SKIP`
- 如果已经放入 `rtl/core/picorv32.v`，则应输出 `PASS` / `FAIL` / `TIMEOUT` 之一

### 第 2 步：实验室先做 Probe 0

目标不是“展示功能”，而是先确认最基本的板级链路：

- `CLK` 真的进了 FPGA
- `RESET` 极性理解正确
- `LED` 和 `KEY` 的 UCF 管脚没有配反

要用的文件：

- 顶层：`rtl/probe/probe_led_key_top.v`
- 约束：`constraints/tecplus_led_key.ucf`

实验室里最简单的判断标准：

- 下载 bitstream 后，释放 `reset`，LED 会跑马灯
- 按 `KEY1`，跑马灯速度变化
- 按 `KEY2`，切到固定显示模式

如果这一步都不稳定，不要继续调 UART，更不要继续调 SoC。

### 第 3 步：实验室再做 Probe 1

目标是确认串口发通：

- 顶层：`rtl/probe/probe_uart_top.v`
- 约束：`constraints/tecplus_uart.ucf`
- 主机串口设置：`9600 8N1`

成功现象很简单：串口终端里周期性出现 `Hello TecPlusRV`。

如果这一步失败，优先怀疑：

- `TXD` 管脚
- 波特率设置
- `reset` 是否一直有效
- 实验室板卡实际 UCF 是否与仓库文档一致

### 第 4 步：再碰 PicoRV32 / MiniSoC

只有在 Probe 0 和 Probe 1 都通过后，才建议做：

1. PicoRV32 minimal 综合探针
2. MiniSoC 本地仿真
3. MiniSoC 板级 bring-up

原因很直接：如果 LED 和 UART 这两个最小探针都没过，后面即使 SoC 不工作，你也分不清是 CPU、总线、memory map、UCF、还是板级 I/O 出的问题。

### 第 5 步：用更薄的 Probe 4a / 5a 提前排雷

当前仓库已经补了两个薄探针，用来在不上完整系统的前提下更早暴露风险：

- `Probe 4a`：`rtl/probe/probe_sdram_smoke_top.v`
- `Probe 5a`：`rtl/probe/probe_bigboard_tl_top.v`

其中：

- `Probe 4a` 不是通用 `SDRAM controller`，只是一个脚本式 `write -> read back -> compare` smoke probe
- `Probe 5a` 不是完整显示/大板外设系统，只是交通灯输出存在性探针

这两个 probe 的意义是让你在投入完整 `Probe 4 / 5` 之前，先回答“最小链路是不是活的”。

## PicoRV32 放置方式

如果后续要尝试 MiniSoC 真正执行，仓库约定 PicoRV32 文件位于：

```text
rtl/core/picorv32.v
```

这里的 `vendored` 只是术语，意思是“手工引入、自己审阅、随仓库一起管理的第三方源码”。

如果这个文件已经在你的工作树里，就不需要再做额外动作；不是“还要再放一次”。

## 实验室上板顺序

不要在 LED/UART 都没确认之前就去调完整 SoC。

推荐第一轮实验室顺序：

1. `probe_led_key_top` + `constraints/tecplus_led_key.ucf`
2. `probe_uart_top` + `constraints/tecplus_uart.ucf`
3. PicoRV32 minimal 综合/资源探针
4. `probe_sdram_smoke_top` + `constraints/tecplus_sdram_smoke.ucf`
5. `probe_bigboard_tl_top` + `constraints/tecplus_bigboard_tl.ucf`
6. MiniSoC 板级启动

这里要区分两层：

- `Probe 4a / 5a`：当前仓库已经实现的 thin probe
- `Probe 4 / 5`：后续更完整的 `SDRAM standalone tester` / 显示与大板外设 probe

也就是说，当前不是“Probe 4/5 完整实现了”，而是先落了更薄、更适合早期排雷的版本。

## ISE 里还需要做什么

要，ISE 里仍然需要把正确的 `.ucf` 加进工程。

但如果：

- 顶层端口名和仓库一致
- 你使用了仓库给出的对应 `.ucf`

那通常不需要在 ISE GUI 里手工一根根重新分配引脚。更常见的动作是：

1. 把 `.v` 文件加入工程
2. 把对应 `.ucf` 加入工程
3. 设对 top module
4. 跑综合、布局布线、生成 bitstream

真正需要手工改引脚，一般发生在：

- 实验室实际板卡版本和文档/UCF 不一致
- 你改了顶层端口名
- 你换了 probe 或改了连线方案

## 本地验证与实验室验证边界

当前仓库本地可以验证：

- firmware 镜像生成
- RTL 语法烟测
- UART TX 模块仿真
- SDRAM smoke 控制器命令序列仿真
- bigboard traffic-light 图样仿真
- MiniSoC 骨架控制流

这些仍然必须在实验室验证：

- UCF 引脚是否和实际板卡完全一致
- reset / key 极性是否和实际接线一致
- CP2102 串口现象
- ISE 综合、布局布线、时序和下载
- CPU 集成后的资源是否放得下

## 备注

- 新增工程路径保持 ASCII，避免 ISE/脚本在中文路径、空格路径下出问题。
- `rtl/soc/bram.v` 支持 `$readmemh`，用于早期仿真和 bring-up；但在 ISE 下的初始化行为仍要以实验室验证为准。
- `Probe 4a` 只代表 SDRAM smoke probe 已存在，不代表通用 SDRAM 控制器已完成。
