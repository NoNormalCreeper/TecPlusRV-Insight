# TecPlusRV Thin Probes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add thin Probe 4a/5a implementations plus local verification and aligned documentation.

**Architecture:** Keep Probe 4a as a dedicated SDRAM command sequencer with fixed-address readback, and keep Probe 5a as a dedicated bigboard traffic-light pattern generator. Neither probe should pretend to be a reusable full subsystem.

**Tech Stack:** Verilog-2001, UCF, shell scripts, Icarus Verilog, Markdown

---

### Task 1: Add failing local testbenches

**Files:**
- Create: `sim/tb_sdram_smoke_ctrl.v`
- Create: `sim/tb_bigboard_tl.v`

- [ ] Add a testbench for SDRAM smoke sequencing and readback comparison.
- [ ] Add a testbench for bigboard traffic-light pattern rotation.

### Task 2: Implement thin probe RTL and UCF

**Files:**
- Create: `rtl/probe/sdram_smoke_ctrl.v`
- Create: `rtl/probe/probe_sdram_smoke_top.v`
- Create: `rtl/probe/probe_bigboard_tl_top.v`
- Create: `constraints/tecplus_sdram_smoke.ucf`
- Create: `constraints/tecplus_bigboard_tl.ucf`

- [ ] Implement a fixed-flow SDRAM smoke controller.
- [ ] Wrap the controller in a board top with U2 SDRAM pins and LED status.
- [ ] Implement a bigboard traffic-light one-hot pattern probe.
- [ ] Add matching UCF files.

### Task 3: Wire verification and docs

**Files:**
- Modify: `scripts/check_rtl_syntax.sh`
- Modify: `sim/run_sim.sh`
- Modify: `scripts/test_local.sh`
- Modify: `README.md`
- Modify: `docs/PROJECT_SPEC.md`
- Modify: `docs/PROBES.md`

- [ ] Add syntax/simulation entry points for the new probes.
- [ ] Update repo-facing docs so they clearly separate thin Probe 4a/5a from full Probe 4/5.
