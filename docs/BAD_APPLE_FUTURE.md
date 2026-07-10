# Bad Apple 1bpp 后续设计与实施计划

## 文档状态

本文档固定当前 BAM1/text-tile 原型之后的改造方向。当前清理回合不实施 bitmap
RTL、BAM2 或 FreeRTOS；后续实现应按本文的资源门和任务顺序推进。

当前原型状态、可运行命令和 overmap 证据见 `docs/BAD_APPLE_MINIMAL.md`。

## 复用边界

后续直接复用：

- `vga_timing_640x480` 与已上板 VGA probe
- BRAM-only instruction fetch
- SDRAM data-only 通路
- bootloader protocol v1 command 2 `LOAD_IMAGE`
- UART loader、buzzer、LED、UART MMIO
- MP4 抽帧、MIDI parser、track/transpose/offset/time-scale 校准
- BAM1 端到端 CPU/SDRAM/多外设仿真结构

当前 writable `40x30` text/tile VGA 只作为仿真和资源实验原型保留。普通
MiniSoC 默认 `VGA_TEXT_ENABLE=0`。

## 目标架构

```text
本地 MP4 + MIDI
  -> BAM2 1bpp frame diff + VGA-tick note events
  -> LOAD_IMAGE
       |-- BRAM firmware
       `-- SDRAM asset
  -> bare-metal player_step(vga_tick)
       |-- VGA framebuffer MMIO
       |-- buzzer MMIO
       |-- LED
       `-- low-rate UART
```

VGA scanout 和蜂鸣器 PWM 在硬件中自行运行。CPU 负责 asset 解码和事件调度；
后续 FreeRTOS 只替换调用 `player_step()` 的 scheduler，不改变显示、asset 或
bootloader 协议。

## VGA 显示契约

### 默认几何

| 项目 | 默认值 |
| --- | --- |
| VGA timing | `640x480` |
| 逻辑画面 | `64x48` |
| 色深 | 1bpp，`1=白`、`0=黑` |
| 放大 | `8x8` |
| 显示区域 | `512x384` |
| X/Y offset | 64 / 48 |
| framebuffer | 384 bytes，96 个 word |
| buffer | 单 buffer |

逻辑宽度 64 使每行正好是两个 32-bit word：

```text
linear_bit = y * 64 + x
word_index = linear_bit >> 5
bit_index  = linear_bit & 31
```

scanout 只使用移位、拼接和 bit select，不引入通用除法或乘法。

### 可配置边界

`LOGICAL_WIDTH`、`LOGICAL_HEIGHT`、`SCALE_SHIFT`、`X_OFFSET`、`Y_OFFSET` 是
RTL 综合期参数。首版不增加运行时几何 MMIO；需要调整黑边或缩放时重新综合。

若以后确认 firmware 必须动态切换窗口，再单独设计 control registers 和资源门。

### framebuffer 推断约束

- 只允许完整 32-bit word write
- 不支持 byte write 和 readback
- reset 后可通过同一 word 写口顺序清零
- 第一版使用 distributed RAM inference
- 必须检查 ISE Map，不能只看 RTL 仿真

如果仍展开成大量 FF/mux，先收紧 RAM inference。只有这一步失败后，才评估缩小
Bad Apple 专用启动 BRAM并改用同步 block RAM；不直接实现 SDRAM scanout/DMA。

## MMIO 契约

| 地址 | 名称 | 说明 |
| --- | --- | --- |
| `0x1000_0060` | `VGA_STATUS` | ready、vblank、16-bit frame counter |
| `0x1001_0000..0x1001_017f` | `VGA_FB` | 96 个 write-only word |

`VGA_STATUS`：

- bit 0：`VBLANK`
- bit 1：`READY`
- bit `[31:16]`：frame counter

driver 只提供状态查询和 framebuffer word write，不提供绘图、字符、readback 或
double-buffer abstraction。

## 视频与音频时间基准

VGA frame tick 为：

```text
25_000_000 / (800 * 525) = 1250 / 21 ~= 59.523810 Hz
```

BAM2 header 保存 `video_period_ticks`。默认值 6 对应：

```text
(1250 / 21) / 6 = 625 / 63 ~= 9.920635 FPS
```

常用值：

- 6 tick：约 9.92 FPS
- 4 tick：约 14.88 FPS
- 3 tick：约 19.84 FPS
- 2 tick：约 29.76 FPS

首版使用整数 tick period；需要任意小数 FPS 时，在 firmware 增加 phase
accumulator，不修改 VGA RTL。

音符事件始终按 VGA tick 量化，约 16.8 ms 分辨率，不能因为视频采用 10 FPS 而
降到 100 ms 精度。

## BAM2 契约

BAM2 与当前 BAM1 明确不兼容，header 至少包含：

- magic/version
- total bytes
- frame count
- video stream offset
- `video_period_ticks`
- note count
- note stream offset
- framebuffer word count，首版必须为 96

视频继续使用已经验证的 replacement diff：

```text
change_count
  word_index, replacement_word
  ...
```

第一帧必须完整包含 96 words，后续只记录变化 word。第一版不实现 FULL/DELTA
opcode、压缩字典或 custom glyph。

离线脚本继续使用 Python 标准库和系统 ffmpeg：

1. 按 `video_period_ticks` 对应的精确有理数 FPS 抽帧。
2. area scale 到 `64x48` grayscale。
3. 二值化并打包为 96 words。
4. 生成 replacement diff、BAM2、JSON report 和带黑边 GIF。
5. 复用现有 MIDI parser 和同步参数。

## player 与 FreeRTOS 边界

播放器只建立两个软件边界：

- `player_init()`：验证 BAM2 header、offset 和 record 边界
- `player_step(current_vga_tick)`：处理已经到期的视频和音符事件

首版 `main()` 轮询 frame counter 调用 `player_step()`。driver 不包含 busy-wait
scheduler。

FreeRTOS 需要独立完成 DarkRISCV trap、timer interrupt、context switch 和 task
stack 约定。完成后，FreeRTOS task 可用 `vTaskDelayUntil()` 或 notification 调用同一
`player_step()`；FreeRTOS kernel、port 和 task-aware GDB 不属于本改造计划。

## 实施任务

### 任务 1：1bpp VGA module

文件：

- 新建 `rtl/periph/vga_bitmap_1bpp.v`
- 新建 `sim/tb_vga_bitmap_1bpp.v`
- 修改仿真、syntax 和 test catalog 入口

测试先验证清零、黑边、word 0/95、bit-to-pixel、HS/VS、vblank 和 frame counter，
再实现完整-word RAM 和移位寻址。

### 任务 2：MiniSoC MMIO

修改 TinyBus、MiniSoC、硬件/软件地址镜像和 VGA driver：

- `VGA_FB_BYTES=0x180`
- tile 命名改为 framebuffer
- bitmap 使用独立 enable，不复用 `VGA_TEXT_ENABLE`
- 原 text/tile 原型继续保留但默认关闭

完成后运行 bitmap module、TinyBus 和 MiniSoC 双核 smoke。

### 任务 3：BAM2 packer

先增加合成测试，覆盖：

- 96-word 首帧
- diff round-trip
- 损坏 header/index 拒绝
- `video_period_ticks=6` 的真实帧数
- MIDI timestamp 使用 VGA tick
- GIF 包含与硬件一致的黑边

随后复用当前脚本的 MP4/MIDI 基础实现 1bpp packer。

### 任务 4：非阻塞 firmware player

更新端到端仿真，使其验证：

- CPU 从 SDRAM 解析 BAM2
- 第一帧写入 96 words
- 视频每 6 tick 推进
- 音符可以在两个视频帧之间更新
- LED/UART/buzzer 证据仍存在

测试失败后再把 BAM1 loop 改为 `player_init/player_step`。

### 任务 5：ISE 资源门

分别记录：

1. `VGA_TEXT_ENABLE=0` 的普通 MiniSoC基线。
2. 新 1bpp VGA 开启后的增量。

必须包含 LUT、FF、LUT used as Memory、BRAM 和 50 MHz slack。Map/Place/Route 未
全部通过前，不进入真实媒体上板步骤。

### 任务 6：20 秒上板

生成 BAM2、GIF 和 JSON report，通过 `LOAD_IMAGE` 上传，记录：

- packet 大小和 9600 baud 时间
- 黑边、方向、画面稳定性
- MIDI 同步和音符清晰度
- LED、UART 与蜂鸣器行为

只有上板通过后，才决定是否提高 baud、实现真正 protocol v2 或增加 FreeRTOS
profile。

## 明确不做

- 在当前清理回合实施上述任务
- VGA DMA、SDRAM 直接 scanout、双 buffer、RGB 或 terminal
- PCM/AAC 解码、多声部或音量控制
- SDRAM 取指
- 在 Bad Apple 改造中顺带实现 FreeRTOS port
