# Board Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增一个独立的板上 demo firmware，并生成可导入 ISE 的 `.mem` 文件。

**Architecture:** 在现有 MiniSoC/MMIO/驱动接口上新增 `board_demo.c`，让它周期性切换 LED 并打印 UART 文本。仿真侧增加一个最小专用 testbench，只验证“确实发生了多次 LED/UART 活动且能到 `test_exit=1`”，避免把测试耦合到完整串口解码。

**Tech Stack:** C 裸机 firmware、Verilog testbench、现有 `build_firmware.sh` 与 `iverilog/vvp`

---

### Task 1: 建立 board demo 的 failing test

**Files:**
- Create: `sim/tb_board_demo.v`
- Modify: `sim/run_sim.sh`

- [ ] **Step 1: 写专用 failing test**

  新增 `sim/tb_board_demo.v`，实例化 `tecplus_minisoc_top`，要求在超时前观察到：
  - `test_exit_code == 1`
  - `led_write_count >= 4`
  - `uart_write_count >= 4`
  - `led == 4'h8`

- [ ] **Step 2: 运行测试确认失败**

  Run: `FIRMWARE_MAIN=/home/rikka/NexysRV-Insight/firmware/tests/board_demo.c ./sim/run_sim.sh board_demo_pico`

  Expected: FAIL，原因是 `board_demo.c` 尚不存在，firmware 构建失败。

### Task 2: 实现最小 board demo firmware

**Files:**
- Create: `firmware/tests/board_demo.c`

- [ ] **Step 1: 写最小实现**

  `board_demo.c` 的行为：
  - 启动后输出一行 banner
  - 依次把 LED 写成 `1/2/4/8`
  - 每一步输出一行 `"step N led=0xX"`
  - 完成首轮后写 `test_exit=1`
  - 之后继续无限循环执行上述图样

- [ ] **Step 2: 运行测试确认通过**

  Run: `FIRMWARE_MAIN=/home/rikka/NexysRV-Insight/firmware/tests/board_demo.c ./sim/run_sim.sh board_demo_pico`

  Expected: PASS，显示 board demo 已完成预期 LED/UART/test_exit 活动。

### Task 3: 生成独立 mem 产物

**Files:**
- Output: `firmware/build/board_demo.mem`
- Output: `firmware/build/board_demo.elf`
- Output: `firmware/build/board_demo.bin`

- [ ] **Step 1: 生成产物**

  Run: `FIRMWARE_MAIN=/home/rikka/NexysRV-Insight/firmware/tests/board_demo.c ./scripts/build_firmware.sh`

- [ ] **Step 2: 复制为独立文件名**

  Run:
  - `cp firmware/build/firmware.elf firmware/build/board_demo.elf`
  - `cp firmware/build/firmware.bin firmware/build/board_demo.bin`
  - `cp firmware/build/firmware.mem firmware/build/board_demo.mem`

- [ ] **Step 3: 再次做最终验证**

  Run: `FIRMWARE_MAIN=/home/rikka/NexysRV-Insight/firmware/tests/board_demo.c ./sim/run_sim.sh board_demo_pico`

  Expected: PASS
