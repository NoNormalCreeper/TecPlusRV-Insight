# DarkRISCV custom-0 DOT4 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 DarkRISCV 增加 signed INT8 `dot4.s8` custom-0 指令，并以 RTL、core、MiniSoC benchmark、官方 ISA 回归和 ISE/上板 Gate 验证。

**Architecture:** 独立 DOT4 模块通过 DarkRISCV `CPR_*` 接口接入，`CPR_PC` 绑定 transaction；软件用独立汇编 ABI 调用，默认 RV32I firmware 不包含自定义指令。

**Tech Stack:** Verilog-2001、Icarus Verilog、RV32I assembly、riscv64-unknown-elf GCC/binutils、TecPlusRV test runner、ISE 14.7。

## Global Constraints

- 所有开发者文本使用中文，保留常用英文术语。
- 第一版仅支持 DarkRISCV，MMIO、PicoRV32 PCPI、完整 SIMD/Vector 和浮点不在范围内。
- 指令为 signed INT8 纯点积，lane 0=`[7:0]`。
- 每项行为先观察失败测试，再写最小实现。
- ISE/PAR 和上板属于人工 Gate，不能用 Icarus 替代。

---

### Task 1: DOT4 计算与 transaction 握手

**Files:**
- Create: `rtl/accel/dot4_int8.v`
- Create: `sim/tb_dot4_int8.v`
- Modify: `sim/run_sim.sh`
- Modify: `scripts/rtl_syntax_case.sh`
- Modify: `scripts/test_catalog.json`
- Modify: `rtl/files.f`

**Interfaces:** `req/tag/rs1/rs2 -> ack/result`。

- [x] 写缺少 module 时失败的 testbench。
- [x] 实现 signed 四路乘法、18-bit 求和与 32-bit 符号扩展。
- [x] 用 PC tag 覆盖同一请求保持和相邻请求连续为高。
- [x] 运行 `./sim/run_sim.sh dot4_int8` 与 syntax case。

### Task 2: DarkRISCV custom-0 接入

**Files:**
- Create: `firmware/tests/darkriscv_dot4.S`
- Create: `sim/tb_darkriscv_dot4.v`
- Modify: `rtl/core/darkriscv.v`
- Modify: `rtl/core/darkriscv_config.vh`
- Modify: `rtl/soc/darkriscv_adapter.v`

**Interfaces:** 仅 `custom-0/funct3=0/funct7=0` 合法。

- [x] 先观察协处理器端口缺失的失败测试。
- [x] 接入 CPR request/result/ack 与 `CPR_PC`。
- [x] 覆盖结果、相邻 DOT4、x0、非法编码和 stall 中 timer IRQ。
- [x] 运行 machine trap、`rv32i_safe` 和 `rv32mi_dark`。

### Task 3: firmware ABI 与性能对照

**Files:**
- Create: `firmware/accel/dot4.h`
- Create: `firmware/accel/dot4.S`
- Create: `firmware/tests/dot4_bench.c`
- Create: `scripts/test_dot4_benchmark.sh`
- Modify: `scripts/build_firmware.sh`
- Modify: `Makefile`

**Interfaces:** `int dot4_s8(unsigned int a, unsigned int b)`；显式
`FIRMWARE_ACCEL=dot4`。

- [x] 先观察 `dot4_s8` undefined reference。
- [x] 增加 `.insn r CUSTOM_0, 0, 0, a0, a0, a1` ABI。
- [x] 比较相同输入的 checksum、cycles 和 instret。
- [x] 自动要求 custom cycles/instret 均低于 scalar。

### Task 4: 文档、回归与人工 Gate

**Files:**
- Create: `docs/DOT4_CUSTOM_ISA.md`
- Modify: `README.md`
- Modify: `docs/PROJECT_SPEC.md`
- Modify: `docs/BENCHMARKS.md`
- Modify: `scripts/export_ise_project.sh`

- [x] 增加 `dot4` suite 和 `make dot4-bench`。
- [x] 增加 `minisoc_dot4_dark` ISE 导出目标。
- [x] 从共同基线 `3f41961` 生成无 DOT4 的 `minisoc_dark` PPA 对照包，并验证两份导出包可脱离源码树独立 elaboration。
- [x] fresh 运行 `dot4`、smoke、RV32I、RV32MI completion gate。
- [ ] 用户执行 ISE Map/PAR/Timing 与真实上板验证。
