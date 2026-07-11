# 全时长 Bad Apple FreeRTOS Implementation Plan

> **执行约束：** 直接在 `master` 工作，不使用 worktree 或 sub-agent；每个任务先补可失败的自动检查，再写实现。

**Goal:** 用完整 MP4 生成 64x48 1bpp 像素动画，用完整多轨 MIDI 生成单路 buzzer 音频，在 FreeRTOS 下同步播放约 219 秒并可于明天上板。

**Architecture:** BAM2 asset 放在 `0x81000000` SDRAM；playback task 以 VGA frame counter 为唯一时间基准，更新 96-word bitmap 并把到期 MIDI 频率放入 static queue；audio task 独占 buzzer。保留现有 `LOAD_IMAGE` protocol，仅把目标 baud 提升到 115200。

**Tech Stack:** Python 标准库、ffmpeg/ffprobe、RV32I C、FreeRTOS V11.3.0、DarkRISCV、Icarus Verilog、Xilinx ISE 14.7。

---

### Task 1: BAM2 packer 与全轨 MIDI reducer

**Files:**
- Create: `scripts/make_bad_apple_full_asset.py`
- Create: `scripts/test_bad_apple_full_asset.py`

- [ ] 先写 header/diff round-trip、跨轨接力、重叠音符释放回退、同 tick Off/On 和 16 MiB 边界测试。
- [ ] 从 BAM1 复用 SMF parser、tempo map、running status、MP4 抽帧和 replacement diff，改为 64x48 1bpp、625/63 FPS、BAM2 12-word header。
- [ ] 正式 reducer 使用试听确认的两轨钢琴 MIDI：第 2 轨主旋律、两侧降频鼓包络、
  唯一长间奏第 3 轨填充，并将 MIDI 尾点对齐到视频有效音频尾点。
- [ ] 输出 `.bin`、可选 `.mem` 与 JSON report；validator 必须遍历到两个 stream 精确末尾。
- [ ] 先运行 synthetic 与 1 秒真实媒体测试，再生成完整 219 秒 asset 并核对尺寸和最后时间戳。

### Task 2: FreeRTOS 播放器

**Files:**
- Create: `firmware/tests/bad_apple_full.c`
- Modify: `firmware/drivers/vga.h`
- Modify: `firmware/drivers/vga.c`（仅在缺少 frame counter API 时）

- [ ] 先构造错误 header/越界记录测试入口，确认播放器拒绝坏 asset。
- [ ] playback/audio 两个 static tasks，static queue 长度 16；不引入新的 heap 使用。
- [ ] 用 16-bit VGA frame counter 的 wrap-safe delta 建立相对 tick；完整播放只约 13042 ticks，不跨硬件 counter wrap。
- [ ] 首帧写满 96 words，后续只应用 replacement diff；音频 task 是 buzzer 唯一 owner。
- [ ] 完整一轮后停止 buzzer，输出 `bad apple full pass`、LED=5、`test_exit=1`，真实板继续循环。

### Task 3: synthetic 端到端 RTL 仿真

**Files:**
- Create: `sim/tb_bad_apple_full.v`
- Modify: `sim/run_sim.sh`
- Modify: `scripts/test_catalog.json`

- [ ] 先增加 `bad_apple_full` catalog case，确认目标未接入时失败。
- [ ] packer 生成短 BAM2 `.mem`，testbench 预装到 SDRAM `0x81000000`。
- [ ] 检查实际 SDRAM traffic、96 次首帧写、delta write、buzzer register/SPK、UART PASS、LED=5 和 `test_exit=1`。
- [ ] 使用 DarkRISCV + FreeRTOS 4 MHz 逻辑时钟；缩短 VGA timing 但保留 frame-counter 驱动关系。

### Task 4: 构建、115200 loader 与 ISE target

**Files:**
- Modify: `Makefile`
- Modify: `scripts/export_ise_project.sh`
- Modify: `scripts/uart_loader.py`（仅补 throughput 显示，不改 protocol）
- Modify: `docs/BAD_APPLE_FUTURE.md`
- Modify: `docs/BAD_APPLE_MINIMAL.md`

- [ ] 增加 `bad-apple-full-build`，隔离输出 firmware、BAM2 binary/report/mem。
- [ ] 增加 `bad-apple-full-load PORT=...`，firmware 和 asset 均固定 `--baud 115200`、asset 地址 `0x81000000`。
- [ ] 增加 `bad_apple_full_dark` ISE export：DarkRISCV、bootloader、bitmap VGA、关闭 text VGA、UART 115200。
- [ ] 更新旧文档：BAM1 继续作为原型，新 BAM2 是当前上板目标；不得再写“未来才有 bitmap”。

### Task 5: 自动 Gate 与明日上板 Gate

- [ ] 运行 packer unit/real/full tests，保存完整 asset 的 frame/event/track/bytes/duration 报告。
- [ ] 运行 `bad_apple_full` 端到端仿真及 FreeRTOS、VGA bitmap、SDRAM、bootloader 相邻回归。
- [ ] 运行 `make test-all` 和固件尺寸检查；失败时不进入 ISE。
- [ ] 导出并运行 ISE Map/PAR，要求 50 MHz slack 为正且资源不 overmap。
- [ ] 交付三条上板命令与约 219 秒观察清单；用户确认画面、音频、PASS/LED 与循环后才恢复 demos/stress。
