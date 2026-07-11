# Bad Apple 1bpp / BAM2 实现说明

## 文档状态

原计划中的 bitmap RTL、BAM2、FreeRTOS 双 task player 和完整媒体 packer 已经实现。
当前自动 Gate 已通过，ISE Map/PAR 与真实上板仍待完成；B3 通过前不把本功能写成
“已上板完成”。

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
  -> FreeRTOS playback/audio tasks
       |-- VGA framebuffer MMIO
       |-- buzzer MMIO
       |-- LED
       `-- low-rate UART
```

VGA scanout 和蜂鸣器 PWM 在硬件中自行运行。CPU 负责 asset 解码和事件调度；
FreeRTOS 不改变显示、asset 或 bootloader 协议。

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
5. 使用正式两轨钢琴 MIDI 的 `compact-piano` reducer：低音和弦生成降频鼓包络，
   第 2 轨保护主旋律，唯一长间奏由第 3 轨填充。

## player 与 FreeRTOS 边界

`firmware/tests/bad_apple_full.c` 在启动时完整验证 BAM2 header、offset、所有 video
records 和 audio tick；播放时以 hardware VGA frame counter 为唯一时间基准。UART
每秒输出紧凑进度 `t=Ns`，从 `t=1s` 到 `t=219s`；默认 9600 baud 下单行阻塞约
5..9 ms，小于一个约 16.8 ms VGA tick。旧的每 100 帧点号输出已移除。

FreeRTOS 是独立的通用 firmware profile，不是 Bad Apple 私有依赖，也不能用 Bad
Apple 代替 port bring-up。必须先由 `freertos-smoke` 验证 tick/yield/delay/抢占，再由
`freertos-queue` 验证静态 queue；两道 gate 通过后，Bad Apple 才作为综合 demo 接入。

FreeRTOS 版本拆成两个 owner task：video/playback task 调用播放器边界并唯一写 VGA，
发现音符后把 `audio_event` 写入静态 queue；audio task 阻塞等待 queue 并唯一写
buzzer。首轮不增加 mutex，status/log task 也不作为播放成立的前提。FreeRTOS port
设计见 [`FREERTOS_PORT_DESIGN.md`](FREERTOS_PORT_DESIGN.md)。

## 当前验证与上板命令

完整资源当前实测：

- MP4 输入 `219.099 s`；BAM2 播放时间 `219.1392 s`；
- 2174 个 `64x48` 1bpp frames；
- 1376 个单音 MIDI events，解析正式两轨钢琴 MIDI；
- asset `902048 bytes`；
- FreeRTOS firmware BRAM image `20940 bytes`。

自动验证：

```bash
python3 scripts/test_runner.py run-case bad_apple_full_asset
python3 scripts/test_runner.py run-case bad_apple_full
make bad-apple-full-build
make bad-apple-full-preview
make bad-apple-source-audio-preview
```

预览直接反向解码最终 BAM2，输出
`build/badapple_full/bad_apple_full_preview.mp4` 和同目录 WAV。MP4 使用与板上一致的
`64x48` 1bpp、`8x8` nearest-neighbor 放大和 640x480 黑边；WAV 模拟单路方波 buzzer，
用于检查画面、MIDI reducer、同步和完整时长，不代表实体蜂鸣器的实际响度与音色。

`bad-apple-source-audio-preview` 是独立实验：从 MP4 AAC 解码 mono PCM，以 16 ms hop
做 harmonic-summation pitch detection，再输出 12-TET 方波 WAV。它依赖 host 的
NumPy/SciPy，只用于先试听“原视频提取”路线；用户确认听感前不会替换 BAM2 的 MIDI
事件或增加 firmware 依赖。

正式路径使用 `touhou-bad-apple-featnomico-26035-nonstop2k.com.mid`，把 MIDI 完整尾点
对齐到 MP4 有效音频尾点 `217.080 s`，offset 为约 `+1.400954 s`。低音双音/四音不会
作为持续音高，而会变成三段降频 kick/accent；第 2 轨从约 `29.23 s` 起作为受保护
主旋律，句间空隙不允许第 3 轨插入单音。唯一长间奏 `111.836..126.618 s` 使用第 3
轨最高音连续填充，并折叠到 MIDI 52..76；主旋律结束后，第 3 轨提供尾奏降频节奏。
`make bad-apple-compact-midi-preview` 仅作为 `bad-apple-full-preview` 的兼容别名保留。

上板：

```bash
make ise-export ISE_TARGET=bad_apple_full_dark
# ISE 设置 CPU_IMPL=1、BOOTLOADER_ENABLE=1、VGA_BITMAP_ENABLE=1、
# VGA_TEXT_ENABLE=0；UART_BAUD 与 BOOTLOAD_BAUD 一致（默认 9600）
# 然后生成并烧录 bitstream
make bad-apple-full-load PORT=COM8
```

约 219 秒后 UART 应输出 `bad apple full pass`、LED=`5`，随后循环。真实板仍需检查
画面黑白方向、完整时长、音频连续性与 reset 后重新上传。

## 历史实施任务

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
- 在 Bad Apple 改造中顺带实现或首次调试 FreeRTOS port
