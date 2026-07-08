# VGA Probe 与字符显示骨架 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 TEC-PLUS 增加一个可上板的 VGA thin probe，以及一个暂不接 SoC 的字符型 VGA 显示骨架。

**Architecture:** 抽出共享 VGA timing 模块，在此基础上实现 `probe_vga_top` 的彩条探针和 `vga_text_mode` 的字符渲染器。前者专注板级链路验证，后者提供未来 MMIO 集成所需的最小显示骨架与写口。

**Tech Stack:** Verilog-2001、Icarus Verilog、ISE 14.7、TEC-PLUS UCF

---

## 文件结构

- Create: `rtl/periph/vga_timing_640x480.v`
- Create: `rtl/periph/vga_text_mode.v`
- Create: `rtl/probe/probe_vga_top.v`
- Create: `rtl/probe/probe_vga_text_top.v`
- Create: `constraints/tecplus_vga.ucf`
- Create: `sim/tb_probe_vga_top.v`
- Create: `sim/tb_vga_text_mode.v`
- Modify: `sim/run_sim.sh`
- Modify: `scripts/check_rtl_syntax.sh`
- Modify: `scripts/test_local.sh`
- Modify: `scripts/export_ise_project.sh`
- Modify: `rtl/files.f`
- Modify: `README.md`
- Modify: `docs/PROBES.md`
- Modify: `docs/DEV_FLOW.md`

## 任务

### Task 1: 先写 failing test

- [ ] 为 `probe_vga_top` 新增 bench，并在 RTL 尚不存在时跑出编译失败。
- [ ] 为 `vga_text_mode` 新增 bench，并在 RTL 尚不存在时跑出编译失败。

### Task 2: 实现共享 timing 与 thin probe

- [ ] 新增 `vga_timing_640x480.v`
- [ ] 新增 `probe_vga_top.v`
- [ ] 让 bench 从“缺模块失败”变成“行为通过”

### Task 3: 实现字符型 VGA 外设骨架

- [ ] 新增 `vga_text_mode.v`
- [ ] 新增 `probe_vga_text_top.v`
- [ ] 让字符写口与 banner bench 通过

### Task 4: 接入脚本与文档

- [ ] 增加 `run_sim` / syntax / local test / ISE export 入口
- [ ] 更新 `README`、`PROBES`、`DEV_FLOW`

### Task 5: 最终验证

- [ ] 运行 `bash scripts/check_rtl_syntax.sh`
- [ ] 运行 `./sim/run_sim.sh probe_vga`
- [ ] 运行 `./sim/run_sim.sh vga_text_mode`
