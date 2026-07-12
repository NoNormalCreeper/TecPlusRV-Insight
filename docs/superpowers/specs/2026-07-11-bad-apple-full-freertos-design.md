# 全时长 Bad Apple FreeRTOS 播放设计

## 目标

在当前 TecPlusRV MiniSoC 上实现明天可上板的完整 Bad Apple：

- 播放 `firmware/assets/bad-apple.mp4` 的完整 `219.099 s` 视频；
- 显示为 `64×48` 黑白像素方块，每个逻辑像素由现有 VGA bitmap 放大为 `8×8`；
- 音频使用 `touhou-bad-apple-featnomico-26035-nonstop2k.com.mid` 两轨钢琴版的
  `compact-piano` 单音归约；
- 使用 FreeRTOS video/playback task 与 audio queue task；
- 复用现有 BRAM instruction fetch、SDRAM data path、`LOAD_IMAGE`、VGA bitmap MMIO、
  buzzer、UART、LED 和已验证 FreeRTOS port；
- 完整自动仿真后复用默认 UART baud 的 ISE/loader 上板入口；baud 只通过
  `BOOTLOAD_BAUD` 显式覆盖，不在 Bad Apple target 中写死。

## 复用与不改动边界

直接复用：

- `vga_bitmap_1bpp`：`64×48`、96 words、1bpp、`8×8` 放大；
- MiniSoC `VGA_BITMAP_ENABLE=1` 路径与 `vga_bitmap_write_word()`；
- SDRAM `0x8100_0000..0x81ff_ffff` asset 区；
- bootloader protocol v1 `LOAD_IMAGE` 和 `uart_loader.py`；
- FreeRTOS static task、static queue、timer/trap port；
- buzzer PWM、LED、UART 和 `test_exit`；
- BAM1 已验证的 replacement-diff 与 SDRAM model preload 思路。

本轮不修改 VGA RTL、SDRAM controller、bootloader wire protocol 或 CPU core。若这些
既有基础设施的回归失败，先定位兼容问题，不以新协议/新总线绕过。

## 音频能力边界

板上 buzzer 只能输出一个可编程频率的方波，不能同时播放 MIDI 的和弦、音色和力度。
正式 reducer 固定为用户试听确认的两轨钢琴版规则：

1. MIDI 完整尾点对齐 MP4 有效音频尾点 `217.080 s`，time scale 为 `1.0`，得到
   offset 约 `+1.400954 s`；
2. 第 2 轨低音双音/四音在主旋律两侧转换成三段降频 kick/accent 包络；
3. 第 2 轨从视频约 `29.23 s` 起作为受保护主旋律；八度叠音选择较低音；
4. 短句间空隙保持静音，不允许第 3 轨插入怪单音；
5. 唯一长间奏约 `111.836..126.618 s` 使用第 3 轨最高音填充，并把音高按八度折叠到
   MIDI 52..76；
6. 主旋律结束后，第 3 轨恢复为三段降频尾奏节奏，最后包络约 `216.905 s` 结束。

物理输出仍是 monophonic MIDI reduction，不宣称还原原始多声部或采样鼓声。

## 时间基准与完整时长

现有 VGA frame tick：

```text
25 MHz / (800 * 525) = 1250/21 Hz
```

视频每 6 个 VGA ticks 更新：

```text
video FPS = 625/63 ~= 9.920635
```

MP4 video stream `219.099 s` 预计生成约 2174 帧，播放约 219.14 秒。MIDI events 使用
每个 VGA tick 约 16.8 ms 的时间轴；video 和 audio task 都以同一个 hardware VGA
frame counter 为基准，不以 UART、FreeRTOS tick 或主循环速度累计时间。

播放器按 hardware VGA frame counter 每秒输出紧凑进度 `t=Ns`，完整一轮为
`t=1s..t=219s`；默认 9600 baud 下短行阻塞小于一个 VGA tick。完成一轮后输出 PASS
并等待 10 秒，再从第一帧循环。

## BAM2 格式

BAM2 little-endian header 固定 12 words：

| word | 字段 |
| ---: | --- |
| 0 | magic `BAM2` (`0x324d4142`) |
| 1 | version `2` |
| 2 | total bytes |
| 3 | duration in VGA ticks |
| 4 | frame count |
| 5 | video stream byte offset |
| 6 | video period ticks，首版为 `6` |
| 7 | audio event count |
| 8 | audio stream byte offset |
| 9 | framebuffer words，必须为 `96` |
| 10 | flags，首版为 `0` |
| 11 | reserved，必须为 `0` |

视频记录继续使用 replacement diff：

```text
change_count
  word_index, replacement_word
  ...
```

第一帧必须完整写 96 words；后续只写变化 words。audio stream 是排序的
`(vga_tick, hz)` pairs。packer 和 firmware 都必须完整遍历 variable-length video
records，不能用固定 frame count/offset 猜边界。

asset 必须 4-byte 对齐，`total_bytes <= 16 MiB`，且装入
`0x8100_0000..0x81ff_ffff`。取消 BAM1 的 `frame_count<=1000`、`note_count<=256` 和
`asset<=1 MiB` 原型限制。

## 离线 packer

新增 `scripts/make_bad_apple_full_asset.py`，只依赖 Python 标准库与系统 ffmpeg/ffprobe：

1. ffprobe 读取 video/audio stream duration；
2. ffmpeg 按 `625/63 FPS` 提取 `64×48` grayscale；
3. threshold 为 128，打包 96 个 little-endian 1bpp words；
4. 生成首帧 full + 后续 replacement diffs；
5. 解析两轨 MIDI 的 tempo、running status 和 Note On/Off；
6. 按 `compact-piano` 主旋律、长间奏与降频鼓包络规则生成 `(vga_tick, hz)` events；
7. 输出 BAM2 binary、可选 testbench `.mem` 和 JSON report；
8. validator 完整 round-trip 所有 frames/events，并核对总时长和边界。

短 synthetic asset 用于 RTL regression；真实媒体测试使用 1 秒 clip，并额外构造跨轨
接力与重叠音符测试；正式 build 执行完整 219.099 秒转换并在 report 中记录 frame
count、各 track 音符数、event count、asset bytes、估算 115200 上传时间和最后一个 tick。

## FreeRTOS player

新增 `firmware/tests/bad_apple_full.c`，全部长期对象 static allocation：

```text
playback task, priority 2
  -> validate BAM2
  -> wait VGA ready
  -> follow VGA frame counter
  -> apply due framebuffer diffs
  -> enqueue due audio hz events
  -> progress UART / LED

audio task, priority 3
  -> block on static queue
  -> hz==0: buzzer_stop
  -> hz>0: buzzer_start_hz(configCPU_CLOCK_HZ, hz)
```

queue length 16；playback 每个 VGA tick 最多发送当前到期 events。若 queue 满、record
越界、word index>=96、tick 非递增或 stream 未精确结束，输出稳定错误码并停止。

一轮完成后停止 buzzer，UART 输出 `bad apple full pass`、LED=`5`、`test_exit=1`，然后
等待短暂间隔并循环。仿真看到 `test_exit` 后结束；真实板继续运行。

## 自动仿真

新增 synthetic BAM2 和 `tb_bad_apple_full.v`：

- DarkRISCV + FreeRTOS 逻辑 4 MHz；
- `VGA_BITMAP_ENABLE=1`；
- 缩短 VGA timing，但保持 frame counter、VGA MMIO 和 buzzer toggle；
- 把 synthetic BAM2 预装到 SDRAM `0x8100_0000`；
- 检查第一帧 96 writes、delta writes、audio register writes、SPK toggle、UART、LED、
  `test_exit=1` 和实际 SDRAM traffic。

真实 asset 回归不在 RTL 仿真中播放 219 秒；它由 packer full build + validator 证明
格式与时长，短 synthetic end-to-end 证明 firmware/RTL 数据流。

## 明天上板路径

新增：

```bash
make bad-apple-full-build
make ise-export ISE_TARGET=bad_apple_full_dark
make bad-apple-full-load PORT=COM8
```

完整 asset 可能达到 MiB 级。ISE target 明确要求：

```text
CPU_IMPL=1
BOOTLOADER_ENABLE=1
VGA_BITMAP_ENABLE=1
VGA_TEXT_ENABLE=0
UART_BAUD 与 BOOTLOAD_BAUD 一致，默认 9600
```

loader target 使用 `BOOTLOAD_BAUD`，默认 9600；需要提速时由用户同时修改 bitstream
generic 与 Make 参数。wire protocol 与 CRC 不变。

## Gate

### B1：packer

- synthetic round-trip；
- 真实 1 秒 video/MIDI clip；
- synthetic 多轨接力、重叠音符与释放后回退测试；
- 完整 219.099 秒 build/validate；
- asset 小于 16 MiB，report 时间轴覆盖完整视频。

### B2：firmware/RTL

- BAM2 synthetic DarkRISCV end-to-end PASS；
- FreeRTOS、VGA bitmap、SDRAM subword、bootloader tests 不回退；
- `make test-all` 全绿；
- 50 MHz firmware BRAM 低于 48 KiB soft budget。

### B3：ISE/上板

- export 成功；
- ISE Map/PAR 通过，50 MHz slack 为正；
- loader 完成 firmware + full asset CRC；
- VGA 画面方向、黑白、边界、完整时长和循环正确；
- UART 在约 219 秒后输出 `bad apple full pass`、LED=`5`；
- buzzer 与视频节奏相关且持续完整时长；
- reset 后可以重新上传并再次播放。

B3 完成前，不恢复 demos 实施或进入 stress。
