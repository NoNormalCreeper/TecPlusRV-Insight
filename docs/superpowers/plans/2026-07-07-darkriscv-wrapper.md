# DarkRISCV Wrapper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a switchable CPU wrapper so TecPlusRV can run on either PicoRV32 or DarkRISCV while preserving the existing SoC shell, MMIO contract, and firmware-facing behavior.

**Architecture:** Keep `tecplus_minisoc_top` as the board-level shell and move CPU selection behind a wrapper. Use one adapter for PicoRV32 and one for DarkRISCV so the rest of the SoC sees a unified master-style request interface and stable performance-counter/MMIO outputs.

**Tech Stack:** Verilog-2001, shell scripts, Icarus Verilog, RISC-V bare-metal GCC

---

### Task 1: Add wrapper-facing documentation and plan anchors

**Files:**
- Modify: `docs/PROJECT_SPEC.md`
- Modify: `docs/DEV_FLOW.md`
- Modify: `README.md`
- Create: `docs/superpowers/plans/2026-07-07-darkriscv-wrapper.md`

- [ ] Describe the CPU-switchable architecture and the invariant that MMIO addresses and firmware access patterns stay stable.
- [ ] Document the new regression targets for dual-core smoke and adapter-focused tests.

### Task 2: Introduce a unified CPU request interface

**Files:**
- Create: `rtl/soc/cpu_bus_if.vh`
- Create: `rtl/soc/tecplus_cpu_wrapper.v`
- Create: `rtl/soc/picorv32_adapter.v`
- Create: `rtl/soc/darkriscv_adapter.v`
- Modify: `rtl/soc/tecplus_minisoc_top.v`

- [ ] Define one internal CPU-side interface that expresses fetch/data access in a SoC-friendly way.
- [ ] Re-home the PicoRV32 instance behind `picorv32_adapter`.
- [ ] Add `darkriscv_adapter` that translates DarkRISCV Harvard buses into the unified request interface.
- [ ] Make `tecplus_minisoc_top` select the adapter with a parameter, without changing external board pins or MMIO addresses.

### Task 3: Vendor and trim the DarkRISCV core for local use

**Files:**
- Create: `rtl/core/darkriscv.v`
- Create: `rtl/core/darkriscv_config.vh`
- Modify: `sim/run_sim.sh`
- Modify: `scripts/check_rtl_syntax.sh`

- [ ] Vendor the minimum DarkRISCV source needed for simulation and local synthesis-oriented syntax checking.
- [ ] Freeze a local configuration that keeps reset PC, endian, and ISA assumptions aligned with current firmware.
- [ ] Teach local simulation/syntax scripts how to compile both CPU variants.

### Task 4: Preserve firmware-visible counters and system behavior

**Files:**
- Modify: `rtl/soc/tecplus_minisoc_top.v`
- Modify: `rtl/soc/tinybus_decode.v`
- Modify: `firmware/main.c`
- Create: `firmware/tests/cpu_smoke.c`
- Create: `firmware/tests/mmio_smoke.c`
- Create: `firmware/tests/counter_smoke.c`
- Modify: `scripts/build_firmware.sh`

- [ ] Keep `TINYBUS_CYCLE` and `TINYBUS_INSTRET` at the same MMIO addresses.
- [ ] Replace the current rough `instret` counting with adapter-driven or core-backed accounting that can be compared across both CPUs.
- [ ] Expand firmware smoke coverage so both CPU variants execute the same self-checking binaries.

### Task 5: Add strict regression coverage

**Files:**
- Create: `sim/tb_picorv32_adapter.v`
- Create: `sim/tb_darkriscv_adapter.v`
- Modify: `sim/tb_minisoc.v`
- Modify: `sim/run_sim.sh`
- Modify: `scripts/test_local.sh`

- [ ] Add adapter-focused testbenches that force expected wait/ack/read/write behavior.
- [ ] Run `tb_minisoc` against both CPU implementations.
- [ ] Add firmware-selected regression modes so ALU/branch/load-store/MMIO/counter paths are covered under both cores.
- [ ] Make the one-shot local test script fail if either CPU implementation regresses.

### Task 6: Write the implementation summary

**Files:**
- Create: `docs/darkriscv-wrapper-summary.md`

- [ ] Summarize architecture changes, dependent-module impacts, validation scope, residual risks, and confidence level.
