# UART Bootloader v1 与 `LOAD_IMAGE` 协议

本文档定义 TecPlusRV 当前支持的 UART bootloader wire protocol，以及 RESET、BRAM、SDRAM 和 CPU 所有权切换语义。

## 目标与边界

command 1 保持原有 v1 行为：通过 UART 把 `firmware.bin` 写到 64 KiB BRAM 的 `0x0000_0000`。command 2 `LOAD_IMAGE` 会在同一包中额外把 asset 写到 SDRAM，两个区域和整体 CRC 都成功后才释放 CPU。

这里的 `command=2` 仍属于 wire protocol version 1，不应称为“bootloader v2”。host
按 64 bytes 调用串口 write 只是发送实现细节，不是具有独立 CRC/ACK 的协议 chunk。

当前不支持：

- BRAM 的任意 load address 或 entry address
- SDRAM 取指
- 两段以上的通用 ELF 镜像
- Flash / EEPROM 持久化
- 加密、签名或通用调试命令

CRC32 只用于检测传输出错，不提供恶意 payload 的身份认证。

## 串口参数

- 8 data bits
- no parity
- 1 stop bit
- 默认 `9600 baud`
- `uart_rx` 与 `uart_tx` 共用顶层 `UART_BAUD` 参数

UART probe 与 bootloader 的 9600 baud 路径均已上板通过；bootloader 已确认稳定收到 READY/ACK、正确启动 payload，并覆盖错误 CRC 与 RESET 后重复下载。更高波特率可以通过参数尝试，但必须重新做 ISE timing 与真实串口测试。

## 请求帧

所有多字节整数都按 little-endian 发送。

| offset | 大小 | 字段 | v1 取值 |
| ---: | ---: | --- | --- |
| `0` | 4 B | `magic` | `0xbadabb1e`，wire bytes 为 `1e bb da ba` |
| `4` | 1 B | `version` | `0x01` |
| `5` | 1 B | `command` | `0x01`，表示 `LOAD_AND_RUN` |
| `6` | 4 B | `payload_len` | `1..65536` |
| `10` | N B | `payload` | `firmware.bin` 原始内容 |
| `10+N` | 4 B | `crc32` | 见下节 |

固定开销为 14 bytes。

### `LOAD_IMAGE` 请求帧

`command=0x02` 用于短 demo 的双段装载：

| offset | 大小 | 字段 | 约束 |
| ---: | ---: | --- | --- |
| `0` | 4 B | `magic` | 与 v1 相同 |
| `4` | 1 B | `version` | `0x01` |
| `5` | 1 B | `command` | `0x02` |
| `6` | 4 B | `bram_len` | `1..65536` |
| `10` | 4 B | `sdram_addr` | 4-byte 对齐，位于 `0x80000000..0x81ffffff` |
| `14` | 4 B | `sdram_len` | 非零、4-byte 对齐且不越过 SDRAM 末尾 |
| `18` | N B | `bram_payload` | firmware 原始内容 |
| `18+N` | M B | `sdram_payload` | asset 原始内容 |
| `18+N+M` | 4 B | `crc32` | 覆盖 version 至两个 payload |

初版只做整包 ACK 与整包重传，适合几十 KiB 的实验室 bring-up。CRC 失败时 SDRAM 可能保留部分失败数据，但 CPU 始终保持 reset；重传同一包会完整覆盖目标区域。长视频需要的逐 chunk ACK、断点续传和 session 状态不在这一版内。

## CRC32

CRC32 覆盖：

```text
version + command + payload_len + payload
```

上式是 command 1。command 2 则覆盖 `version + command + bram_len + sdram_addr + sdram_len + bram_payload + sdram_payload`。

不包含 magic，也不包含 CRC32 字段本身。

参数：

- reflected polynomial：`0xEDB88320`
- initial value：`0xFFFFFFFF`
- final XOR：`0xFFFFFFFF`

这个定义与 Python 的以下写法一致：

```python
crc32 = binascii.crc32(packet_without_magic_and_crc) & 0xffffffff
```

## 两字节响应

| byte 0 | byte 1 | 含义 |
| ---: | ---: | --- |
| `0x52` | `0x00` | `READY`：BRAM 已清空，可以发送请求帧 |
| `0x79` | `0x00` | `ACK`：CRC 正确，ACK 发完后释放 CPU |
| `0x1F` | error | `NACK`：请求失败，CPU 保持 reset |

错误码：

| error | 含义 |
| ---: | --- |
| `0x01` | version 或 command 不支持 |
| `0x02` | payload 长度为 0 或超过 64 KiB |
| `0x03` | UART framing error 或 overrun |
| `0x04` | CRC32 不匹配 |
| `0x05` | inter-byte timeout |
| `0x06` | SDRAM 控制器写请求失败 |

`ACK` 的停止位完整发送后才会把 UART TX 交给 CPU，因此不会和 payload 的第一条 UART 日志互相覆盖。

## RESET 与重复下载

TEC-PLUS 的程序 RESET 与 FPGA CONFIG 是两件事。bootloader bitstream 下载一次后，可以反复使用以下流程，不需要重新运行 ISE/JTAG：

```text
按下 RESET（低有效）
  -> CPU reset
  -> bootloader 接管 UART 与 BRAM A 口
松开 RESET
  -> 清空全部 64 KiB BRAM
  -> 发送 READY
  -> 接收并校验 payload
  -> 发送 ACK
  -> 释放 CPU
```

再次按 RESET 会重新进入相同流程，可以下载另一份 firmware。`CONFIG`、重新上电或重新下载 bitstream 才属于 FPGA 重新配置。

## 失败与重传

- magic 使用滑动匹配，等待状态中的普通串口噪声不会释放 CPU。
- payload 接收过程中使用 inter-byte timeout，不限制整个包的总下载时间。
- version、command、长度、UART 或 CRC 错误都会保持 CPU reset。
- 失败后硬件清空部分写入的 BRAM，再返回 NACK；host 收到 NACK 后可以直接重传，无需按 RESET。
- host 按 64-byte chunk 发送并在块间检查响应。传输中收到 READY 表示发生 RESET，当前 attempt 立即废弃并从 magic 开始整包重传；不能从 payload 中间续传，因为 RESET 已清空 BRAM，CRC32 也覆盖完整 payload。
- READY/NACK 默认最多触发 5 次自动重传；超过上限后 host 明确失败，避免无限循环。
- 成功释放 CPU 后 bootloader 不再监听 UART，也不会在 CPU 运行时改写 BRAM。要换程序必须按 RESET 重新进入 loader。

## Host 工具

Windows + WSL2 推荐直接在 WSL 仓库根目录执行：

```bash
make bootload PORT=COM8
```

该目标会构建到专属的 `firmware/build/bootload/firmware.*`，不会改写手动构建的默认 `firmware/build/firmware.*`；随后通过 Windows Python 打开 `COM8` 完成下载，并在收到 ACK 后使用同一个串口连接进入 serial monitor。完整环境配置见 `docs/WINDOWS_WSL_UART.md`。

DarkRISCV timer IRQ 上板验收可复用同一条 bootloader 路径：

```bash
make timer-irq-load PORT=COM8
```

`make bootload` 默认仍构建普通 baremetal payload；也可用 `FIRMWARE_PROFILE` 和 `FIRMWARE_MAIN` 显式选择其他 profile 与入口文件。

构建测试 payload：

```bash
FIRMWARE_MAIN="$PWD/firmware/tests/boot_payload.c" \
FIRMWARE_OUT=firmware/build/manual/boot_payload \
  ./scripts/build_firmware.sh
```

只检查封包结果：

```bash
python3 scripts/uart_loader.py \
  --input firmware/build/manual/boot_payload.bin \
  --dry-run
```

真实发送需要 `pyserial`：

```bash
python3 -m pip install pyserial
python3 scripts/uart_loader.py \
  --port /dev/ttyUSB0 \
  --baud 9600 \
  --input firmware/build/manual/boot_payload.bin \
  --monitor
```

Windows 串口名可写成 `COM3`。脚本打开串口后会提示按 RESET，并等待 READY；`--monitor` 会在下载成功后持续显示 payload 输出，按 `Enter` 或 `Ctrl+C` 退出。
传输期间再次按 RESET 时，host 会检测新的 READY 并自动从 magic 整包重传。可用 `--max-retries N` 覆盖默认的 5 次重传上限。
上传期间，交互终端会按 64-byte chunk 在同一行实时刷新完整 wire packet 的进度，例如 `300/65550 Byte, chunk 5/1025, 0.5%`；这里的总字节数包含 header、payload 和 CRC。RESET/NACK 触发整包重传后，byte 与 chunk 计数会从新 attempt 重新开始；重定向到文件等非交互输出只记录每次 attempt 的最终进度，避免逐 chunk 刷屏。
提供 `--sdram-input` 后，host 自动改用 `LOAD_IMAGE`；不足 4-byte 的文件会在末尾补零：

```bash
python3 scripts/uart_loader.py \
  --port /dev/ttyUSB0 \
  --input firmware/build/bad_apple_minimal.bin \
  --sdram-input firmware/assets/bad_apple_minimal.bin \
  --sdram-address 0x81000000 \
  --monitor
```
Windows + WSL2 的 usbipd、`/dev/ttyUSB0`、权限与故障排查见 `docs/WINDOWS_WSL_UART.md`。

## RTL 与验证入口

- 协议状态机：`rtl/soc/bootloader_ctrl.v`
- MiniSoC 仲裁：`rtl/soc/tecplus_minisoc_top.v`
- 模块测试：`sim/tb_bootloader_ctrl.v`
- SoC 串行波形测试：`sim/tb_minisoc_bootloader.v`

```bash
./sim/run_sim.sh bootloader_ctrl
./sim/run_sim.sh bootloader_pico
./sim/run_sim.sh bootloader_dark
python3 scripts/test_uart_loader.py
```

SoC 测试会覆盖坏 CRC 后不释放 CPU、无需 RESET 直接重传、合法 payload 启动，以及按 RESET 后下载第二份程序。

## 板级验证状态

2026-07-11 已完成 bootloader 板级验证：

- RESET 后稳定收到 `READY`；
- 正确 payload 收到 `ACK`，并打印测试 firmware 启动日志；
- 错 CRC 返回 `NACK 04`；
- 再次 RESET 后可下载并运行第二份 payload；
- ISE Map 无 overmap，BRAM inference 正常，50 MHz PAR post-route timing slack 为 `0.462 ns`。

以上结论只对应当前 revision、约束和 ISE 工程；RTL、约束或时钟设置变化后必须重新验证。

`LOAD_IMAGE` 的确定性 pattern、CPU 全量读回、RESET 恢复和吞吐测试步骤见
`docs/BOOTLOADER_BOARD_TEST.md`。
