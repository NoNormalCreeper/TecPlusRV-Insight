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
- SDRAM 控制器
- 已 vendored 的 PicoRV32
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
5. MiniSoC 骨架仿真

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

如果 `rtl/core/picorv32.v` 不存在，MiniSoC testbench 会输出 `SKIP`，而不是假装通过。

## PicoRV32 放置方式

如果后续要尝试 MiniSoC 真正执行，请把 vendored 的 PicoRV32 文件放到：

```text
rtl/core/picorv32.v
```

当前仓库默认它是外部引入并经过人工审阅的源码，不会自动生成或自动下载。

## 实验室上板顺序

不要在 LED/UART 都没确认之前就去调完整 SoC。

推荐第一轮实验室顺序：

1. `probe_led_key_top` + `constraints/tecplus_led_key.ucf`
2. `probe_uart_top` + `constraints/tecplus_uart.ucf`
3. PicoRV32 minimal 综合/资源探针
4. MiniSoC 板级启动

## 本地验证与实验室验证边界

当前仓库本地可以验证：

- firmware 镜像生成
- RTL 语法烟测
- UART TX 模块仿真
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
- SDRAM 在当前版本里只有文档和地址预留，没有伪造“已完成”的控制器。
