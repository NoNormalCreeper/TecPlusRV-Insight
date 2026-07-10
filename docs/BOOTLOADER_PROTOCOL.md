# UART Bootloader v1 协议

本文档定义 TecPlusRV 当前唯一受支持的 UART bootloader wire protocol，以及 RESET、BRAM 和 CPU 所有权切换语义。

## 目标与边界

v1 只支持一件事：通过 UART 把一个 `firmware.bin` 写到 64 KiB BRAM 的 `0x0000_0000`，校验成功后释放 CPU 从 reset vector 执行。

当前不支持：

- 任意 load address 或 entry address
- SDRAM 取指
- 多段镜像
- Flash / EEPROM 持久化
- 加密、签名或通用调试命令

CRC32 只用于检测传输出错，不提供恶意 payload 的身份认证。

## 串口参数

- 8 data bits
- no parity
- 1 stop bit
- 默认 `9600 baud`
- `uart_rx` 与 `uart_tx` 共用顶层 `UART_BAUD` 参数

现有 UART probe 的 9600 baud 路径已经上板通过，因此 bootloader 首轮也沿用这个保守值；bootloader RX/READY/ACK 整条链路仍需单独上板确认。更高波特率可以通过参数尝试，但必须重新做 ISE timing 与真实串口测试。

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

## CRC32

CRC32 覆盖：

```text
version + command + payload_len + payload
```

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
- 成功释放 CPU 后 bootloader 不再监听 UART，也不会在 CPU 运行时改写 BRAM。要换程序必须按 RESET 重新进入 loader。

## Host 工具

构建测试 payload：

```bash
FIRMWARE_MAIN="$PWD/firmware/tests/boot_payload.c" ./scripts/build_firmware.sh
```

只检查封包结果：

```bash
python3 scripts/uart_loader.py --input firmware/build/firmware.bin --dry-run
```

真实发送需要 `pyserial`：

```bash
python3 -m pip install pyserial
python3 scripts/uart_loader.py \
  --port /dev/ttyUSB0 \
  --baud 9600 \
  --input firmware/build/firmware.bin
```

Windows 串口名可写成 `COM3`。脚本打开串口后会提示按 RESET，并等待 READY。
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

## 板级未确认点

RTL 仿真只能证明协议和所有权切换逻辑。首次上板仍必须记录：

- RESET 后是否稳定收到 `READY`
- 正确 payload 是否收到 `ACK` 并打印 `Bad Apple boot payload running.`
- 错 CRC 是否返回 `NACK 04`
- 再次 RESET 后是否能下载第二份 payload
- ISE 资源占用、timing 与 BRAM inference 是否正常
