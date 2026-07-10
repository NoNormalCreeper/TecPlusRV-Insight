# 地址映射

## 当前草案

| 地址 | 大小 | 用途 |
| --- | --- | --- |
| `0x0000_0000 - 0x0000_FFFF` | 64 KiB | BRAM 启动区 / loader 与小型用户程序 |
| `0x1000_0000` | 32 位 | GPIO LED |
| `0x1000_0004` | 32 位 | GPIO KEY |
| `0x1000_0010` | 32 位 | UART DATA：写入发送，读取并消费一个接收字节 |
| `0x1000_0014` | 32 位 | UART STATUS：收发状态与 RX 错误清除 |
| `0x1000_0020` | 32 位 | cycle counter |
| `0x1000_0024` | 32 位 | instret counter |
| `0x1000_0028` | 32 位 | mem_wait：CPU 数据请求等待 `mem_ready` 的累计周期数 |
| `0x1000_0030` | 32-bit | test_exit |
| `0x1000_0040` | 32 位 | 交通灯 TL11..TL0 原始输出与读回 |
| `0x1000_0050` | 32 位 | 蜂鸣器控制寄存器 |
| `0x1000_0054` | 32 位 | 蜂鸣器方波半周期 |
| `0x1000_0060` | 32 位 | 实验性 VGA status；`VGA_TEXT_ENABLE=0` 时返回未就绪 |
| `0x1001_0000 - 0x1001_04AF` | 1200 B | 实验性 write-only `40x30` packed tile window |
| `0x2000_0000` | 区域基址 | accelerator base |
| `0x8000_0000 - 0x81FF_FFFF` | 32 MiB | U2 SDRAM data-only 区域 |

## 说明

- 这是当前第一版骨架的软件可见地址图草案。
- 低地址 BRAM 是唯一可执行区。bootloader v1 在 CPU reset 期间接管 BRAM A 口，清空整个窗口后从 `0x0000_0000` 顺序写入 payload。
- bootloader wire protocol、RESET 后重复下载和 CRC32 定义见 `docs/BOOTLOADER_PROTOCOL.md`。
- 近期真正会用到的主要是 LED、KEY、UART、交通灯和 `test_exit`。
- 计数器和 accelerator 项先写入地址图，方便后续 firmware 与总线接口提前稳定。
- SDRAM 已通过 `sdram_data_ctrl` 接入 MiniSoC 数据总线；`ifetch_*` 仍只从 BRAM 取指。
- writable text/tile VGA 只作为 BAM1 仿真和资源实验原型保留。它在 LX9 MiniSoC
  中会 overmap，因此顶层参数 `VGA_TEXT_ENABLE` 默认是 0；后续轻量 1bpp 方案会
  复用地址但收紧 framebuffer 窗口。

## UART 寄存器

`UART DATA (0x1000_0010)`：

- 写入低 8 位：发送一个字节；TX 忙时总线请求会等待。
- 读取低 8 位：返回接收缓冲中的字节，并清除 `RX_VALID`。
- 软件应当先检查 `RX_VALID`，再读取 DATA。

`UART STATUS (0x1000_0014)`：

| 位 | 名称 | 含义 |
| --- | --- | --- |
| bit 0 | `TX_READY` | 为 1 时可以发送下一个字节 |
| bit 1 | `RX_VALID` | 为 1 时接收缓冲中存在未读字节 |
| bit 2 | `RX_OVERRUN` | 新字节到达时旧字节仍未读取，写 1 清除 |
| bit 3 | `FRAME_ERROR` | 收到错误停止位，写 1 清除 |

第一版 RX 只有一个字节的保持寄存器，没有 FIFO 和中断。固件必须及时轮询读取。

## 交通灯寄存器

`TRAFFIC DATA (0x1000_0040)`：

- bit `[11:0]` 分别直接驱动 `TL11..TL0`。
- bit `[31:12]` 写入时忽略，读取时返回 0。
- 复位后的逻辑输出为 `12'h000`。
- 本寄存器不反转有效电平，也不自动生成流水图样；灯的图样由 firmware 写入。
- `TL0..TL11` 仍需要按照教学板文档连接排线或 `#1` 线。

## 蜂鸣器寄存器

`BUZZER CTRL (0x1000_0050)`：

- bit 0 为 `ENABLE`，写 1 启动，写 0 停止。
- 复位或停止时 `Spk` 保持低电平。

`BUZZER PERIOD (0x1000_0054)`：

- 保存方波半周期对应的系统时钟数。
- 值为 0 时不输出方波。
- 输出频率为 `CLK_FREQ / (2 * HALF_PERIOD)`。
- 50 MHz 时钟下写入 `25000`，输出频率约为 1 kHz。

当前只提供单音方波。旋律和音符持续时间由 firmware 通过修改周期和延时实现。
