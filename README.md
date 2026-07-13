# TecPlusRV

TecPlusRV 是一个面向 TEC-PLUS Spartan-6 XC6SLX9-2FTG256 平台的 RISC-V SoC 课程设计第一版骨架仓库。

当前版本只聚焦于：

- 工程目录骨架
- 早期板级探针
- 可复用的 UART TX / RX RTL
- CPU 可读写的 12 位交通灯 MMIO 外设
- CPU 可编程频率与启停的蜂鸣器 MMIO 外设
- 蜂鸣器 UART debug probe
- 最小 VGA timing / 彩条 probe / 字符型 VGA 骨架 / 独立 8x8 字模
- 可切换 `PicoRV32 / DarkRISCV` 的 MiniSoC 板级 top 与 SoC 基础模块
- U2 32 MiB SDRAM data-only 控制器与 MiniSoC 集成
- UART RX -> BRAM -> CPU release 的 bootloader v1
- 复用 Bootloader/UART 的 DarkRISCV cooperative GDB stub
- 裸机 firmware 骨架
- 本地构建和仿真入口

当前版本还不提供：

- 从 SDRAM 取指或启动的执行路径
- ISE 工程文件或 bitstream

## DarkRISCV custom-0 DOT4

DarkRISCV profile 实现了一条非标准 `dot4.s8 rd, rs1, rs2` 指令：两个源寄存器
各打包四个 signed INT8，结果为四组乘积之和。它不是完整 SIMD/Vector 扩展，
PicoRV32 也不会执行这条指令。详细编码、验证边界和 ISE/上板步骤见
[`docs/DOT4_CUSTOM_ISA.md`](docs/DOT4_CUSTOM_ISA.md)。
`firmware/apps` 用户程序默认链接 `dot4_s8()` 软件接口；只有应用实际调用它时才要求
板上运行的是启用 DOT4 的 DarkRISCV bitstream。

```bash
make dot4-bench
make ise-export ISE_TARGET=minisoc_dot4_dark
make dot4-load PORT=COM8
```

## 仓库结构

- `rtl/probe/`：早期上板探针顶层
- `rtl/periph/`：可复用外设
- `rtl/soc/`：地址映射、BRAM、MMIO 和 MiniSoC 板级 top
- `rtl/core/`：vendored CPU 核，例如 `picorv32.v`、`darkriscv.v`
- `rtl/accel/`：后续扩展加速器
- `constraints/`：TEC-PLUS 约束文件
- `firmware/`：裸机启动代码、链接脚本、驱动和测试
- `sim/`：本地 testbench
- `scripts/`：本地构建和检查脚本
- `tests/riscv_tests/`：官方 `riscv-tests` submodule，以及本地 `tecplus_p` / `tecplus_m` 适配层

## 推荐先读

- 项目目标与边界：`docs/PROJECT_SPEC.md`
- 探针说明：`docs/PROBES.md`
- 开发与验证流程：`docs/DEV_FLOW.md`
- **Firmware 编译、上传与调试统一入口，有大改，先看这里：`docs/FIRMWARE_GUIDE.md`**
- UART bootloader 协议：`docs/BOOTLOADER_PROTOCOL.md`
- Windows + WSL2 串口下载：`docs/WINDOWS_WSL_UART.md`
- GDB 配置、体验与用户程序演示：`docs/GDB_USER_GUIDE.md`
- GDB stub 实现与扩展：`docs/GDB_STUB_DEVELOPMENT.md`
- 双核 wrapper 与 ISE/性能说明：`docs/darkriscv_wrapper_summary.md`

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
- `make`：本仓库统一的构建、仿真和 CI 入口
- `iverilog`：本地 Verilog 编译/仿真
- `gcc-riscv64-unknown-elf`：生成 RV32I 裸机程序
- `binutils-riscv64-unknown-elf`：提供 `objcopy`、`objdump`

### 2. 确认工具已就绪

```bash
make check-env
```

如果环境正常，应该能看到这些工具都显示为 `[ok]`。

如果准备跑官方 `rv32ui` 回归，还需要初始化 submodule：

```bash
git submodule update --init --recursive
```

### 3. 跑一遍本地 smoke

推荐直接用测试编排器：

```bash
python3 scripts/test_runner.py run-suite smoke
```

如果要看完整本地集合，可以跑：

```bash
python3 scripts/test_runner.py run-suite local
```

如果当前分支还带了双核 regression，可以再跑：

```bash
python3 scripts/test_runner.py run-suite all
```

`make` 的目标名保持不变，`make test-smoke`、`make test-all`、`make rtl-syntax` 这些入口仍然可用，只是内部已经转调到 runner。`scripts/check_rtl_syntax.sh` 和 `scripts/test_local.sh` 也仍然可用，但它们只是兼容壳。

如果你更习惯旧入口，也可以继续用：

```bash
make test-smoke
```

如果当前分支还带了双核 regression，可以再跑：

```bash
make test-all
```

`make test-smoke` 的公共前置顺序固定为 `check_env -> rtl_syntax`；需要 firmware 的 SoC case 会在执行时构建自己的隔离产物。当前 suite/case 覆盖关系以 `scripts/test_catalog.json` 和 `python3 scripts/test_runner.py list` 为准，不再在 README 里手抄一份 case 列表。

`make test-all` 会在此基础上再跑：

1. MiniSoC 通用 regression / counter-source 等 SoC 级仿真
2. 双核 firmware regression

GitHub Actions 的 push / pull request 默认执行 `make ci`，跑 `ci` suite 并跳过
Bad Apple player、FreeRTOS 长时间切换/抢占与双核 benchmark 等分钟级仿真。
需要完整回归时，在 GitHub Actions 手动触发 CI，或在本地运行：

```bash
make ci-full
```

`ci-full` 仍执行完整 `all` suite，不删减任何覆盖。

## 官方 `RV32I` 回归

当前仓库已经接入一条独立的官方 `riscv-tests` 验证支线，用来验证基础 `RV32I` 指令语义，而不影响默认 `firmware/apps/baremetal/soc_selftest.c` 主线。

目录约定：

- `tests/riscv_tests/riscv-tests/`：官方上游 `riscv-tests` submodule
- `tests/riscv_tests/riscv-tests/env/`：上游自带环境子模块
- `tests/riscv_tests/tecplus_p/`：基础 `rv32ui` 双核适配层
- `tests/riscv_tests/tecplus_m/`：DarkRISCV M-mode-only trap/CSR 适配层

推荐入口：

```bash
python3 scripts/test_runner.py run-suite rv32i_safe
python3 scripts/test_runner.py run-suite rv32mi_dark --keep-going
```

`rv32i_safe` 代表基础 `RV32I` 双核基线；`rv32mi_dark` 运行官方 machine CSR、`ecall`、illegal 与 misaligned trap case，只覆盖 DarkRISCV。

如果只想单独跑一个 case 或直接用批处理脚本，也可以用：

```bash
bash scripts/test_riscv_test_case.sh add
bash scripts/test_riscv_test_case.sh safe
bash scripts/test_riscv_test_case.sh rv32mi csr
```

边界说明：

- `rv32i_safe`：当前第一阶段主回归，默认纳入 `local` suite
- `rv32i_optional`：当前单独保留的边界 case，不纳入第一阶段必达
- `rv32mi_dark`：DarkRISCV machine-mode completion gate，不在 PicoRV32 上运行
- `fence_i`：当前 `PicoRV32` 这份 RTL 不支持 `fence.i`，因此不并入基线
- `ma_data`：会开始触碰 misaligned / trap 语义，因此单独保留到后续阶段

## 常用本地命令

检查工具环境：

```bash
make check-env
```

查看可用目标：

```bash
make help
```

检查 RTL 语法：

```bash
python3 scripts/test_runner.py run-suite rtl_syntax_internal
```

`make rtl-syntax` 和 `bash scripts/check_rtl_syntax.sh` 仍然保留，但只是兼容入口。

构建用户 firmware：

```bash
make firmware APP=baremetal/hello.c
```

用户程序按运行模型放进 `firmware/apps/baremetal/`、`irq/` 或 `freertos/`。上传和 GDB 调试分别使用：

```bash
make firmware-load APP=baremetal/hello.c PORT=COM8 BOOTLOAD_BAUD=115200
make firmware-debug APP=baremetal/hello.c PORT=COM8 BOOTLOAD_BAUD=115200
```

完整目录规则、产物说明、三类程序模板和兼容入口见 [`docs/FIRMWARE_GUIDE.md`](docs/FIRMWARE_GUIDE.md)。无参数 `make firmware`、`FIRMWARE_MAIN` 和 `bootload` 继续作为内部/历史兼容入口。

答辩用的短时综合巡检与 Runtime Insight 演示分别使用：

```bash
make firmware-load APP=baremetal/board_demo.c PORT=COM8 BOOTLOAD_BAUD=115200
make firmware-debug APP=baremetal/gdb_demo.c PORT=COM8 BOOTLOAD_BAUD=115200
```

`board_demo` 不依赖外部媒体 asset，会依次给出 SDRAM、VGA、LED、交通灯、蜂鸣器、
按键、UART 和性能计数器证据；GDB 的逐步演示命令见
[`docs/GDB_USER_GUIDE.md`](docs/GDB_USER_GUIDE.md)。

在 Windows + WSL2 中，推荐让 CP2102 保持为 Windows `COMx`，由 WSL 一条命令完成构建、上传并进入 serial monitor：

Windows 端只需预先安装一次 `pyserial`：`py -m pip install pyserial`。完整配置和备用 USB/IP 流程见 `docs/WINDOWS_WSL_UART.md`。

上传期间如果再次按 RESET，host 会检测 READY、废弃当前 attempt，并从 magic 自动整包重传。

跑探针类仿真：

```bash
make test-probe
```

跑平台层仿真：

```bash
make test-platform
```

跑 SoC 级仿真：

```bash
make test-soc
```

单独跑 MiniSoC 通用 regression bench：

```bash
sim/run_sim.sh minisoc_pico
sim/run_sim.sh minisoc_dark
```

单独跑 MiniSoC board-top smoke：

```bash
sim/run_sim.sh minisoc_smoke_pico
sim/run_sim.sh minisoc_smoke_dark
```

验证 bootloader 协议、双核启动与 RESET 后重复下载：

```bash
sim/run_sim.sh bootloader_ctrl
sim/run_sim.sh bootloader_pico
sim/run_sim.sh bootloader_dark
python3 scripts/test_uart_loader.py
```

构建并检查可下载 payload：

```bash
FIRMWARE_MAIN="$PWD/firmware/apps/baremetal/boot_payload.c" \
FIRMWARE_OUT=firmware/build/manual/boot_payload \
  ./scripts/build_firmware.sh
python3 scripts/uart_loader.py \
  --input firmware/build/manual/boot_payload.bin \
  --dry-run
```

真实串口命令和 `0xBADABB1E` wire protocol 见 `docs/BOOTLOADER_PROTOCOL.md`。
Windows `COMx` 一键下载是推荐路径；usbipd、`/dev/ttyUSB0` 与 RESET 的备用配置流程见 `docs/WINDOWS_WSL_UART.md`。

运行完整双核性能实验（原始日志、CSV、Markdown 表和环境快照会写入 `sim/build/benchmarks/`）：

```bash
make perf
```

workload、指标口径和瓶颈分析方法见 `docs/BENCHMARKS.md`；真实板级采集流程见
`docs/BOARD_PERFORMANCE_TEST.md`。

单独跑 core-backed counter source 检查：

```bash
sim/run_sim.sh minisoc_counter_source_pico
sim/run_sim.sh minisoc_counter_source_dark
```

检查 MiniSoC 通用 regression / smoke bench 分层：

```bash
bash scripts/test_minisoc_tb_modes.sh
```

单独跑一个仿真目标：

```bash
make sim TARGET=uart_tx
make sim TARGET=uart_rx
make sim TARGET=bootloader_ctrl
make sim TARGET=bootloader_pico
make sim TARGET=traffic_light_gpio
make sim TARGET=buzzer_pwm
make sim TARGET=font_rom_8x8
make sim TARGET=minisoc_pico
make sim TARGET=minisoc_smoke_pico
```

验证 UART echo 与交通灯 MMIO（PicoRV32 / DarkRISCV）：

```bash
scripts/test_uart_echo_regression.sh
scripts/test_traffic_light_regression.sh
scripts/test_buzzer_regression.sh
```

如果当前分支提供双核脚本，还可以用：

```bash
make test-dual-core
make perf
```

导出一个可直接复制到 ISE 工程旁边的最小文件包：

```bash
make ise-export ISE_TARGET=minisoc
make ise-export ISE_TARGET=minisoc_bootloader
make ise-export ISE_TARGET=probe_uart
make ise-export ISE_TARGET=probe_minisoc_sdram
make ise-export ISE_TARGET=probe_uart ISE_EXPORT_MODE=full
```

导出交通灯 MMIO 上板验收程序：

```bash
FIRMWARE_MAIN="$PWD/firmware/apps/baremetal/traffic_light_mmio.c" \
make ise-export ISE_TARGET=minisoc
```

导出蜂鸣器 1 kHz 持续音示例：

```bash
FIRMWARE_MAIN="$PWD/firmware/apps/baremetal/buzzer_tone.c" \
make ise-export ISE_TARGET=minisoc
```

默认会生成到 `build/ise-export/<target>/`。其中 `.v` / `.vh` / `.ucf` 会摊平到导出目录根部，便于在 ISE 里直接 Import Sources；只有 `firmware/build/firmware.mem` 这类路径敏感文件继续保留目录结构。导出目录里还会附带 `files.list` 和 `README.txt`。

`minisoc_bootloader` 导出包需要在 ISE 的 `Generics, Parameters` 中设置 `BOOTLOADER_ENABLE=1`；普通 `minisoc` 默认仍为 0，保持原有 `firmware.mem` 直接启动行为。

- 默认 `ISE_EXPORT_MODE=minimal`：只导出当前 `ISE_TARGET` 直接需要的 `.v` / `.vh` / `.ucf`
- `ISE_EXPORT_MODE=full`：额外把仓库内全部 `.v` / `.vh` / `.ucf` 也摊平导出，适合一次性导入后在 ISE 里自己选择 top 和 `.ucf`

`sim/run_sim.sh` 和 `scripts/rtl_syntax_case.sh` 是底层 recipe；`scripts/check_rtl_syntax.sh` 和 `scripts/test_local.sh` 是兼容壳。推荐优先从 `python3 scripts/test_runner.py ...` 入口进入；`make` 和旧脚本名只是兼容层。

## 第一次上手怎么做

如果你现在只是想确认这套骨架是不是“活的”，不要一上来就做完整 SoC，按下面顺序走。

### 第 1 步：本地确认仓库骨架没坏

```bash
make test-smoke
```

你应该看到几类结果：

- firmware 构建成功
- `uart_tx` / `uart_rx` 仿真输出 `PASS`
- `minisoc_smoke_pico` / `minisoc_smoke_dark` 仿真输出 `PASS` / `FAIL` / `TIMEOUT`

如果当前分支还有双核 wrapper / regression，再补跑：

```bash
make test-all
```

其中：

- `minisoc_smoke_*` 是 board-top smoke，默认要求 UART / LED / `test_exit` 路径都真实发生
- `minisoc_*` 是通用 firmware regression bench，默认只检查最小软件可见结果，不强制所有程序都走 UART

### 第 2 步：实验室先做 Probe 0

目标不是“展示功能”，而是先确认最基本的板级链路：

- `CLK` 真的进了 FPGA
- `RESET` 低有效极性理解正确
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

### 第 4 步：再碰 CPU / MiniSoC

只有在 Probe 0 和 Probe 1 都通过后，才建议做：

1. CPU minimal 综合探针（PicoRV32 / DarkRISCV）
2. 双核 MiniSoC 本地仿真
3. MiniSoC 板级 bring-up

原因很直接：如果 LED 和 UART 这两个最小探针都没过，后面即使 SoC 不工作，你也分不清是 CPU、wrapper、总线、memory map、UCF、还是板级 I/O 出的问题。

### 第 5 步：用 Probe 4a / Probe 4 / 5a 提前排雷

当前仓库已经补了几个独立探针，用来在不上完整系统的前提下更早暴露风险：

- `Probe 4a`：`rtl/probe/probe_sdram_smoke_top.v`
- `Probe 4`：`rtl/probe/probe_sdram_tester_top.v`
- `Probe 4 UART debug`：`rtl/probe/probe_sdram_tester_uart_top.v`
- `Probe 5a`：`rtl/probe/probe_bigboard_tl_top.v`
- `Probe 5c`：`rtl/probe/probe_buzzer_uart_top.v`
- `Probe 5b`：`rtl/probe/probe_vga_top.v`
- `Probe 5`：`rtl/probe/probe_vga_text_top.v`

其中：

- `Probe 4a` 不是通用 `SDRAM controller`，只是一个脚本式 `write -> read back -> compare` smoke probe
- `Probe 4` 是独立 SDRAM tester，会对一段地址窗口和多组 pattern 重复写入、读回、校验，但仍不接 MiniSoC
- MiniSoC 另行接入 `sdram_data_ctrl` 作为 data-only 区，`minisoc_sdram_pico/dark` 使用真实 CPU 写读回验证
- `probe_minisoc_sdram` 打包同一生产 top 和 `sdram_memtest`，用于 M2b 上板验收，不复制另一套 probe RTL
- `Probe 4 UART debug` 是可选验证顶层，用板载 KEY1，也就是 RTL 的 `key[0]`，做受控注错，并通过 UART 输出 `error_count` 和首错信息
- `Probe 5a` 不是完整显示/大板外设系统，只是交通灯输出存在性探针
- `Probe 5c` 是蜂鸣器 thin probe 的 UART debug 变体，主要拿来做“听到什么”和“RTL 认为自己在播什么”的对照
- `Probe 5b` 不是字符系统，只是 VGA 链路存在性探针
- `Probe 5` 当前只是独立字符型 VGA 骨架，还不接 `TinyBus` / `MiniSoC`

这些 probe 的意义是先回答“最小链路是不是活的”，再把风险逐步推到 SoC 集成层。

M2.5 的 SDRAM firmware 验收使用以下入口：

```bash
TESTS="smoke alu_branch load_store counters perf_mix sdram_memtest" \
  bash scripts/test_dual_core_regression.sh
FIRMWARE_MAIN="$PWD/firmware/apps/baremetal/benchmarks/sdram_sum_bench.c" \
  ./sim/run_sim.sh minisoc_sdram_pico
FIRMWARE_MAIN="$PWD/firmware/apps/baremetal/benchmarks/sdram_sum_bench.c" \
  ./sim/run_sim.sh minisoc_sdram_dark
```

功能覆盖和当前 benchmark baseline 记录在 `docs/SDRAM_DATA_CTRL.md`。

## PicoRV32 放置方式

MiniSoC 使用的 PicoRV32 文件位于：

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
3. CPU minimal 综合/资源探针（PicoRV32 / DarkRISCV）
4. `probe_sdram_smoke_top` + `constraints/tecplus_sdram_smoke.ucf`
5. `probe_sdram_tester_top` + `constraints/tecplus_sdram_tester.ucf`
6. 可选：`probe_sdram_tester_uart_top` + `constraints/tecplus_sdram_tester_uart.ucf`
7. `probe_bigboard_tl_top` + `constraints/tecplus_bigboard_tl.ucf`
8. `probe_buzzer_uart_top` + `constraints/tecplus_buzzer_uart.ucf`
9. `probe_vga_top` + `constraints/tecplus_vga.ucf`
10. `probe_vga_text_top` + `constraints/tecplus_vga.ucf`
11. `tecplus_minisoc_top` + `constraints/tecplus_minisoc.ucf`

这里要区分两层：

- `Probe 4a / 5a`：thin probe
- `Probe 4`：独立 SDRAM tester
- `Probe 5`：后续更完整的显示与大板外设 probe

也就是说，当前 `Probe 4` 可以用于独立 SDRAM 多地址、多 pattern 写读校验，但还不能当作 SoC 的通用 SDRAM 子系统使用。

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
- SDRAM tester 多地址写读控制流仿真
- SDRAM tester 受控失败与 reset 重复仿真
- SDRAM tester UART reporter 格式化仿真
- bigboard traffic-light 图样仿真
- 蜂鸣器 probe 的音符 token / 方波切换仿真
- VGA 彩条 probe 同步与颜色输出仿真
- 字符型 VGA 骨架 banner / 写口仿真
- MiniSoC 板级 top 控制流

这些仍然必须在实验室验证：

- UCF 引脚是否和实际板卡完全一致
- 板上 `RESET` 是否确认为低有效、`KEY` 极性是否和实际接线一致
- CP2102 串口现象
- ISE 综合、布局布线、时序和下载
- CPU 集成后的资源是否放得下

## 备注

- 新增工程路径保持 ASCII，避免 ISE/脚本在中文路径、空格路径下出问题。
- `rtl/soc/bram.v` 支持 `$readmemh`，用于早期仿真和 bring-up；但在 ISE 下的初始化行为仍要以实验室验证为准。
- `Probe 4a` 是最小 smoke；`Probe 4` 是独立 tester 初版。二者都不代表 SoC 级通用 SDRAM 控制器已完成。
