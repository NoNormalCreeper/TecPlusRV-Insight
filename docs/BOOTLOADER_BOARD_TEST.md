# Bootloader 双段装载上板测试指南与实现记录

> 本文同时记录实现约定、自动化验证入口和实验室上板验收步骤。

**目标：** 用确定性 SDRAM asset、CPU 全量读回和 READY→ACK 计时，建立可在实验室重复执行的 `LOAD_IMAGE` 正确性与吞吐验收路径。

**架构：** Python 生成带 magic/长度/seed 的 32-bit pattern asset；bootloader 把 verifier firmware 写入 BRAM、asset 写入 `0x81000000`；CPU 释放后逐 word 校验并通过 UART/LED/test_exit 报告。host 只增加传输统计，不改变 protocol v1 wire format。

**技术栈：** Python 3 标准库、RV32I freestanding C、Verilog-2001/Icarus Verilog、ISE 14.7、pyserial。

## 全局约束

- 保持 protocol v1 command 1/2 wire format 和整包重传语义不变。
- asset 与 SDRAM 地址必须 4-byte 对齐。
- 开发者文本使用中文，保留 UART、SDRAM、CRC、ACK 等常用术语。
- 不修改或清理 `perf_mix.c`、diary、issue draft 等现有无关工作区内容。
- 不自动加入 CRC 故障注入或串口自动复位控制；这些只留在手工异常测试步骤。

---

## 上板操作

### 1. 导出并烧录 bootloader bitstream

```bash
bash scripts/export_ise_project.sh bootloader
```

ISE 使用 `tecplus_minisoc_top` 和 `tecplus_minisoc.ucf`，Generics/Parameters 设置：

- `BOOTLOADER_ENABLE=1`
- `VGA_TEXT_ENABLE=0`
- `CPU_IMPL=1`，第一轮使用 DarkRISCV
- `UART_BAUD=9600`

生成并烧录 bitstream。之后只需按 RESET 重进 loader，不需要每次重新 JTAG program。

### 2. 构建 64 KiB pattern 和 verifier firmware

```bash
make boot-image-test-build DATA_BYTES=65536 SEED=0x12345678
```

输出：

- `build/bootloader-test/pattern.bin`
- `firmware/build/boot_image_verify.bin`
- `firmware/build/boot_image_verify.mem`

`DATA_BYTES` 只表示 pattern 数据长度；asset 还包含 16-byte BTV1 header。

### 3. WSL + Windows COM 上传

```bash
make boot-image-test-load \
  PORT=COM8 \
  BOOTLOAD_BAUD=9600 \
  DATA_BYTES=65536 \
  SEED=0x12345678
```

loader 打开串口后，按下并松开 TEC-PLUS RESET。预期先收到 READY/ACK 和 host
传输统计，然后由 verifier firmware 输出：

```text
boot_image_verify: checking SDRAM asset at 0x81000000
boot_image_verify: PASS bytes=65536 seed=0x12345678 verify_cycles=...
```

LED 最终为 `5`。若失败，LED 为 `f`，UART 会打印首个错误的 index、expected 和
actual。

### 4. Linux 原生串口上传

```bash
make boot-image-test-build DATA_BYTES=65536 SEED=0x12345678
python3 scripts/uart_loader.py \
  --port /dev/ttyUSB0 \
  --baud 9600 \
  --input firmware/build/boot_image_verify.bin \
  --sdram-input build/bootloader-test/pattern.bin \
  --sdram-address 0x81000000 \
  --monitor
```

### 5. 正确性矩阵

依次执行，每项至少两个 seed：

| `DATA_BYTES` | 目的 |
| ---: | --- |
| `16` | 最短有效 data |
| `4096` | 基础连续装载 |
| `65536` | 跨多个 SDRAM row 的主验收尺寸 |
| `262144` | 长传输压力 |

同一 bitstream 下连续执行：seed A -> RESET -> seed B。第二次必须报告 seed B 且
全量 PASS，证明目标 SDRAM 区域确实被覆盖。

传输 262144 bytes 时，在中途按 RESET。host 应检测新的 READY、整包重传，最终
统计中的“重传”至少为 1 且 firmware PASS。

### 6. 吞吐测试

host 统计窗口严格从 READY 后开始，到 ACK 返回结束，不包含人工按 RESET 的时间。
8N1 理论速度为 `baud / 10` bytes/s。

每档 baud 使用同一个 64 KiB asset 连续测试三次，记录中位数：

| UART_BAUD | 理论上限 |
| ---: | ---: |
| `9600` | 960 B/s |
| `38400` | 3840 B/s |
| `57600` | 5760 B/s |
| `115200` | 11520 B/s |

每换 baud 都必须重新综合 bitstream，并同时修改 host 的 `BOOTLOAD_BAUD`/`--baud`。
记录 packet bytes、elapsed、B/s、理论利用率、重传次数和 verifier PASS/FAIL。

### 7. 当前尚需手工补充的异常项

- `build_image_packet()` 会拒绝空 payload、未对齐地址/长度和越过 SDRAM 末尾；
  日常 CLI 会先把文件末尾补齐到 4-byte，因此生成器产物无需额外处理。
- 传输中按 RESET 已由正常 loader 自动整包恢复。
- wire CRC 故障和只发半包后的 timeout 目前没有日常 CLI 开关；需要临时 fault
  injection sender 时再单独增加，避免普通 loader 误触发破坏性测试。

### 8. 验收标准

- 四种尺寸、两个 seed 均为零 mismatch。
- 连续覆盖和中途 RESET 后最终仍 PASS。
- 9600 baud 连续三次无重传。
- 找到最高连续三次无错误的稳定 baud。
- 每次保留 host 统计行和 firmware PASS 行。

---

### Task 1: 确定性 board-test asset

**Files:**
- Create: `scripts/test_boot_image_asset.py`
- Create: `scripts/make_boot_image_test_asset.py`

**Interfaces:**
- `build_asset(data_bytes: int, seed: int) -> bytes`
- header words：magic `BTV1`、version 1、data word count、seed
- data word：`seed ^ ((index * 0x9e3779b9) & 0xffffffff)`
- CLI：`--data-bytes`、`--seed`、`--output`、可选 `--mem-output`

- [x] 写测试：header/pattern、非法尺寸、CLI binary 输出和精确 word `.mem` 输出。
- [x] 运行 `python3 scripts/test_boot_image_asset.py`，确认因模块不存在而失败。
- [x] 实现最小生成器和 CLI。
- [x] 重跑测试，确认 PASS。

### Task 2: CPU 全量读回 verifier

**Files:**
- Create: `firmware/apps/baremetal/boot_image_verify.c`
- Create: `sim/tb_boot_image_verify.v`
- Modify: `sim/run_sim.sh`
- Modify: `scripts/test_catalog.json`

**Interfaces:**
- asset base：`0x81000000`
- 最大 data：1 MiB
- PASS：LED `5`、`TINYBUS_TEST_EXIT=1`、UART 包含 `boot_image_verify: PASS`
- FAIL：LED `f`、非 1 test_exit、UART 打印 index/expected/actual

- [x] 先添加 testbench/runner，预装小 asset 并要求 CPU PASS。
- [x] 运行 `./sim/run_sim.sh boot_image_verify_pico`，确认 firmware 不存在而失败。
- [x] 实现 header、长度和逐 word 校验。
- [x] 运行 PicoRV32 与 DarkRISCV 端到端仿真，确认 PASS。

### Task 3: Loader 吞吐统计

**Files:**
- Modify: `scripts/test_uart_loader.py`
- Modify: `scripts/uart_loader.py`

**Interfaces:**
- `transfer_packet(...) -> int` 返回实际重传次数
- `format_transfer_stats(packet_bytes, elapsed_seconds, baud, retries) -> str`
- READY 后开始计时，ACK 后输出 elapsed、bytes/s、理论利用率和 retries

- [x] 先写统计格式和重传计数测试，运行后确认失败。
- [x] 实现最小返回值、格式函数和 `send_packet()` 计时。
- [x] 运行 `python3 scripts/test_uart_loader.py`，确认全部 PASS。

### Task 4: 构建与上板入口

**Files:**
- Modify: `Makefile`
- Modify: `scripts/export_ise_project.sh`
- Modify: `docs/BOOTLOADER_PROTOCOL.md`
- Modify: `docs/BOOTLOADER_BOARD_TEST.md`

**Interfaces:**
- `make boot-image-test-build DATA_BYTES=65536 SEED=0x12345678`
- 输出 `firmware/build/boot_image_verify.*` 与 `build/bootloader-test/pattern.bin`
- ISE target：`bootloader`，参数 `BOOTLOADER_ENABLE=1`、`VGA_TEXT_ENABLE=0`

- [x] 增加 build target 和 ISE/WSL/Linux 命令。
- [x] 运行 build target、asset/loader 测试和双核仿真。
- [x] 运行 smoke、platform、`git diff --check`。
