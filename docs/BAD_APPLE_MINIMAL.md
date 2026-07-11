# Bad Apple 原型状态

## 当前结论

仓库已经保留一条可仿真的 Bad Apple 原型链路：

```text
本地 MP4 + MIDI
  -> BAM1 tile/note asset
  -> bootloader LOAD_IMAGE
  -> BRAM firmware + SDRAM asset
  -> CPU diff replay
  -> VGA tile / buzzer / LED / UART
```

这条链路证明了协议、数据流和多外设调度可以协同工作，但当前 writable
`40x30` text/tile VGA 不适合目标 Spartan-6 LX9。ISE Map 的失败结果为：

- Slice Registers：`11119 / 11440`，约 97%
- Slice LUTs：`22348 / 5720`，约 390%，overmapped
- RAMB16BWER：`32 / 32`

主要原因不是视频 FPS，而是 `300x32 bit`、byte-write、async-read 的动态 tile
RAM 没有完整推断为 distributed RAM。接入 CPU 写口后，大量存储位和读取 mux
被展开成 FF/LUT。独立 text probe 的写口被常量绑死，ISE 可以做常量折叠，因而
probe 能通过不能证明 writable SoC 版本也能 fit。

因此：当前 BAM1 路径只作为仿真、协议和资源实验原型保留，不再宣称是可上板
Bad Apple 完成态。

## 已固定、可继续复用的进度

- `rtl/soc/bootloader_ctrl.v`
  - protocol v1 command 1 `LOAD_AND_RUN`
  - protocol v1 command 2 `LOAD_IMAGE`
  - CPU reset 期间顺序写 BRAM firmware 和 SDRAM asset
- `scripts/uart_loader.py`
  - 构造双段 image packet
  - CRC32、READY/ACK/NACK、RESET 后整包重传
- `rtl/soc/sdram_data_ctrl.v` 与 MiniSoC data-only SDRAM 通路
- `scripts/make_bad_apple_minimal_asset.py`
  - 真实 MP4 抽帧
  - format-1 MIDI、tempo、running status、note on/off 解析
  - MIDI track、transpose、offset、time-scale 校准
- `firmware/tests/bad_apple_minimal.c`
  - SDRAM asset 边界检查
  - diff replay、蜂鸣器、LED、低频 UART 输出
- `sim/tb_bad_apple_minimal.v`
  - 真实 CPU 从 SDRAM 解析 BAM1 并驱动四类外设的端到端证据
- `rtl/periph/vga_timing_640x480.v` 与 VGA probe
  - 继续作为后续轻量 framebuffer 的已验证 timing/板级基础

MiniSoC 新增 `VGA_TEXT_ENABLE` 综合参数，默认值为 `0`。普通 MiniSoC 不会
实例化重 text/tile RAM；保留的 Bad Apple 仿真显式设为 `1`。

## 当前可运行验证

运行合成 BAM1 端到端仿真：

```bash
./sim/run_sim.sh bad_apple_minimal_pico
```

运行真实 MP4/MIDI 转换回归：

```bash
python3 scripts/test_bad_apple_real_asset.py
```

生成 20 秒原片、MIDI、asset、预览和报告：

```bash
make bad-apple-build
```

生成物位于：

- `build/badapple/bad_apple_20s.bin`
- `build/badapple/bad_apple_20s.gif`
- `build/badapple/bad_apple_20s.json`
- `firmware/build/bad_apple_minimal.*`

这些生成物和本地 MP4/MIDI 都保持在 `.gitignore` 范围内。

`make bad-apple-load` 仅保留用于复现实验；在当前 LX9 上启用
`VGA_TEXT_ENABLE=1` 会 overmap，不能作为正常上板步骤。

## 当前正式方向

上述改造已经由 BAM2 / FreeRTOS 路径实现：

- `64x48` 1bpp framebuffer，默认每个逻辑像素放大为 `8x8`
- 默认显示区域 `512x384`，左右黑边 64、上下黑边 48
- 黑边、缩放和逻辑尺寸使用 RTL 综合期参数，不在首版增加运行时几何 MMIO
- 帧率由 asset 的 `video_period_ticks` 配置；默认 6 个 VGA tick，约 9.92 FPS
- MIDI 音符按 VGA tick 调度，不降到 10 FPS 视频精度
- player 使用 FreeRTOS playback task + static audio queue/task
- 继续使用 BRAM 取指、SDRAM data-only asset、`LOAD_IMAGE` 和现有 buzzer/LED/UART

运行 `make bad-apple-full-build` 构建完整 219 秒 asset 与 firmware；详细契约、自动
验证和上板步骤见 `docs/BAD_APPLE_FUTURE.md`。完整版正式使用新增的两轨钢琴 MIDI
及 `compact-piano` reducer；原 13-track MIDI 与 BAM1 仍只用于历史原型回归。
