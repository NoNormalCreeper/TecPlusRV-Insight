# TecPlusRV Insight

TecPlusRV Insight 是我们在 TEC-PLUS 开发板上完成的《项目式课程阶段2——从部件到整机：计算机系统控制器与处理器设计实践》RISC-V SoC 课程设计，主题为*面向 TEC-PLUS 资源约束平台的可验证、可拓展 RISC-V SoC 设计与实现：系统软件运行、交互调试与指令扩展*，这也是项目名称 *Insight* 的名称来历。系统运行于 Xilinx Spartan-6 XC6SLX9，使用统一的 MiniSoC 外壳接入 PicoRV32 和 DarkRISCV，并提供 BRAM、SDRAM、UART、VGA、蜂鸣器、交通灯和按键等存储与外设路径。

项目从 Probe 逐级上板开始，随后加入 UART Bootloader、最小 C runtime、machine trap、FreeRTOS port、cooperative GDB stub 和 `dot4.s8` 自定义指令。*Bad Apple!!*、GDB 调试和 DOT4 benchmark 是三组系统级 demo，分别检查多任务与多外设运行、处理器状态观测和指令扩展性能。课程设计已经完成验收，仓库保留了本地回归、板级测试和性能数据。

## 主要实现

- PicoRV32 多周期核与 DarkRISCV 三阶段流水线核，共用 memory map、firmware 和 MMIO 接口。
- 64 KiB 双口 BRAM，用于取指、普通数据和栈。
- 32 MiB data-only SDRAM，用于显式数据段、heap 和媒体资源。
- UART Bootloader，支持分别装载 BRAM firmware 和 SDRAM asset，并在校验成功后释放 CPU。
- 裸机、machine IRQ 和 FreeRTOS 三类 firmware profile，以及项目自己的 startup、linker script、驱动和最小运行库。
- DarkRISCV machine-mode trap、machine timer IRQ、canonical trap frame 和 FreeRTOS port。
- 通过 UART 连接 GNU GDB 的 cooperative GDB stub，可读写寄存器、BRAM 和 SDRAM。
- DarkRISCV custom-0 `dot4.s8` 指令，以及 scalar/custom 正确性和性能对照。
- Probe、官方 `riscv-tests`、自动化 test catalog、CI、性能计数器和板级验证流程。

## 快速开始

本地开发需要 Python 3、GNU Make、Icarus Verilog、RISC-V GCC 和 Binutils。Ubuntu 或 WSL2 的安装与环境说明见 [开发与验证流程](docs/DEV_FLOW.md)。

```bash
git submodule update --init --recursive
make check-env
make test-smoke
make help
```

`make test-smoke` 运行环境检查、RTL 语法检查和快速回归。完整测试会运行更长时间：

```bash
make test-all
```

测试 case 和 suite 以 `scripts/test_catalog.json` 为准，可通过下面的命令查看：

```bash
python3 scripts/test_runner.py list
```

## 常用命令

| 目的 | 命令 |
| --- | --- |
| 检查开发环境 | `make check-env` |
| 查看 Make 入口 | `make help` |
| 运行快速回归 | `make test-smoke` |
| 运行完整回归 | `make test-all` |
| 构建用户程序 | `make firmware APP=baremetal/hello.c` |
| 构建、上传并监视程序 | `make firmware-load APP=baremetal/hello.c PORT=COM8 BOOTLOAD_BAUD=115200` |
| 用 GDB 调试用户程序 | `make firmware-debug APP=baremetal/gdb_demo.c PORT=COM8 BOOTLOAD_BAUD=115200` |
| 构建 FreeRTOS 综合验收程序 | `make freertos-acceptance` |
| 构建 Bad Apple 完整演示 | `make bad-apple-full-build` |
| 上传 Bad Apple 完整演示 | `make bad-apple-full-load PORT=COM8 BOOTLOAD_BAUD=115200` |
| 运行双核与存储性能实验 | `make perf` |
| 运行板级性能实验 | `make board-benchmark PORT=COM9 BOOTLOAD_BAUD=115200` |
| 导出 ISE 文件包 | `make ise-export ISE_TARGET=minisoc_dot4_dark` |

firmware 的目录规则、构建产物和三类 profile 见 [Firmware 编译、上传与调试指南](docs/FIRMWARE_GUIDE.md)。底层仿真目标和全部上板参数不在 README 中重复列出，可通过 `make help`、测试 catalog 和对应文档查询。

## 文档索引

### 理解系统

| 内容 | 文档 |
| --- | --- |
| 项目目标、能力和开源代码边界 | [项目说明](docs/PROJECT_SPEC.md) |
| BRAM、SDRAM 与 MMIO 地址 | [地址映射](docs/MEMORY_MAP.md) |

### 开发与上板

| 内容 | 文档 |
| --- | --- |
| 仓库结构、验证顺序和 ISE 流程 | [开发与验证流程](docs/DEV_FLOW.md) |
| 用户程序编译、上传和调试 | [Firmware 指南](docs/FIRMWARE_GUIDE.md) |
| Probe 0 至 Probe 5 的目标与上板步骤 | [探针测试说明](docs/PROBES.md) |
| Bootloader wire protocol 和 `LOAD_IMAGE` | [Bootloader 协议](docs/BOOTLOADER_PROTOCOL.md) |
| Windows、WSL2 和串口配置 | [Windows 与 WSL2 串口下载](docs/WINDOWS_WSL_UART.md) |

### 模块与扩展

| 内容 | 文档 |
| --- | --- |
| SDRAM controller 接口与 data-only 路径 | [SDRAM 数据控制器](docs/SDRAM_DATA_CTRL.md) |
| DarkRISCV trap 与 FreeRTOS port | [FreeRTOS 接入设计](docs/FREERTOS_PORT_DESIGN.md) |
| GDB stub 内部实现 | [GDB stub 开发说明](docs/GDB_STUB_DEVELOPMENT.md) |
| GDB 安装、连接与演示 | [GDB 使用指南](docs/GDB_USER_GUIDE.md) |
| `dot4.s8` 编码、硬件路径和验证 | [DOT4 自定义指令](docs/DOT4_CUSTOM_ISA.md) |

### 性能与验证结果

| 内容 | 文档 |
| --- | --- |
| workload、计数器口径和结果解读 | [性能实验说明](docs/BENCHMARKS.md) |
| 真实开发板性能采集方法 | [板级性能测试流程](docs/BOARD_PERFORMANCE_TEST.md) |
| benchmark 覆盖和证据关系 | [Benchmark 验证总览](reports/benchmark-validation-summary.md) |
| BRAM 与 SDRAM 板级结果 | [板级性能总结](reports/board-performance-summary.md) |
| DOT4 正确性、资源和时序结果 | [DOT4 上板验证](reports/dot4-board-validation.md) |

### 课程材料

| 内容 | 文档 |
| --- | --- |
| 课程设计报告 | [实验报告正文](docs/实验报告正文.md) |
| 项目逐日开发记录 | [开发日志](docs/diary.md) |

## 仓库结构

| 路径 | 内容 |
| --- | --- |
| `rtl/core/` | PicoRV32、DarkRISCV 与本地接口修改 |
| `rtl/soc/` | CPU adapter、wrapper、BRAM、SDRAM、Bootloader 和 MiniSoC top |
| `rtl/periph/` | UART、GPIO、VGA、蜂鸣器、交通灯和 machine timer |
| `rtl/probe/` | 板级独立验证顶层 |
| `rtl/accel/` | DOT4 自定义指令单元 |
| `firmware/` | startup、linker、runtime、驱动、应用和测试程序 |
| `sim/` | Verilog testbench 与仿真入口 |
| `scripts/` | 构建、测试、串口下载、ISE 导出和素材处理脚本 |
| `tests/riscv_tests/` | 官方 `riscv-tests` submodule 与本地 target environment |
| `reports/`、`results/` | 性能、资源、时序和板级实验记录 |

## ISE 与上板

仓库不提交预生成的 ISE 工程和 bitstream。`make ise-export` 会按目标导出 Verilog、UCF、firmware 镜像和文件清单，再由 ISE 14.7 完成综合、Map、Place and Route、时序分析和 bitstream 生成。

Probe 0 至 Probe 5 及其依赖模块已经完成上板测试，适合用于确认时钟、复位、UART 和 SDRAM 等基础链路。完整 MiniSoC 或外设出现问题时，应先运行对应 Probe 和本地回归，再检查 ISE 报告与板级现象。

## 当前边界

- CPU 只从 BRAM 取指，SDRAM 当前用于数据、heap 和外部 asset。
- SDRAM controller 使用 closed-page、单 outstanding 请求，没有 Cache、burst 或 DMA。
- machine trap、FreeRTOS、GDB 和 DOT4 使用 DarkRISCV profile，PicoRV32 保留为 RV32I 与性能基线。
- GDB stub 使用预埋 `ebreak` 的 cooperative breakpoint，不支持动态断点、single-step 和运行中异步暂停。
- `dot4.s8` 是一条 custom-0 packed INT8 点积指令，不代表完整 SIMD 或 RISC-V Vector 扩展。
- ISE 资源与时序结论以对应导出目标和板级记录为准，修改 RTL 或顶层配置后需要重新验证。
