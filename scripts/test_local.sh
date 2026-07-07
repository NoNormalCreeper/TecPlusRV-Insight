#!/usr/bin/env bash
# 本地一键 smoke flow。
# 给新组员判断“当前骨架有没有坏”：先查工具，再构建 firmware，再跑 RTL syntax 和仿真。
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

echo "[1/21] 检查本地工具链"
"$REPO_ROOT/scripts/check_env.sh"

echo
echo "[2/21] 构建 firmware"
"$REPO_ROOT/scripts/build_firmware.sh"

echo
echo "[3/21] 检查 RTL syntax"
"$REPO_ROOT/scripts/check_rtl_syntax.sh"

echo
echo "[4/21] 运行 probe_led_key_top 仿真"
"$REPO_ROOT/sim/run_sim.sh" probe_led_key

echo
echo "[5/21] 运行 probe_uart_top 仿真"
"$REPO_ROOT/sim/run_sim.sh" probe_uart_top

echo
echo "[6/21] 运行 bram 仿真"
"$REPO_ROOT/sim/run_sim.sh" bram

echo
echo "[7/21] 运行 bram_dualport 仿真"
"$REPO_ROOT/sim/run_sim.sh" bram_dualport

echo
echo "[8/21] 运行 tinybus_decode 仿真"
"$REPO_ROOT/sim/run_sim.sh" tinybus_decode

echo
echo "[9/21] 运行 mmio_test_exit 仿真"
"$REPO_ROOT/sim/run_sim.sh" mmio_test_exit

echo
echo "[10/21] 运行 UART TX 仿真"
"$REPO_ROOT/sim/run_sim.sh" uart_tx

echo
echo "[11/21] 运行 SDRAM smoke 控制器仿真"
"$REPO_ROOT/sim/run_sim.sh" sdram_smoke

echo
echo "[12/21] 运行 bigboard traffic-light 仿真"
"$REPO_ROOT/sim/run_sim.sh" bigboard_tl

echo
echo "[13/21] 运行 PicoRV32 MiniSoC board-top smoke 仿真"
"$REPO_ROOT/sim/run_sim.sh" minisoc_smoke_pico

echo
echo "[14/21] 运行 DarkRISCV MiniSoC board-top smoke 仿真"
"$REPO_ROOT/sim/run_sim.sh" minisoc_smoke_dark

echo
echo "[15/21] 运行 MiniSoC smoke / regression bench 模式检查"
"$REPO_ROOT/scripts/test_minisoc_tb_modes.sh"

echo
echo "[16/21] 运行 PicoRV32 counter source 仿真"
"$REPO_ROOT/sim/run_sim.sh" minisoc_counter_source_pico

echo
echo "[17/21] 运行 DarkRISCV counter source 仿真"
"$REPO_ROOT/sim/run_sim.sh" minisoc_counter_source_dark

echo
echo "[18/21] 检查 perf 仿真入口缺少地址时会失败"
"$REPO_ROOT/scripts/test_perf_targets_require_addrs.sh"

echo
echo "[19/21] 运行 PicoRV32 counter reset 仿真"
"$REPO_ROOT/sim/run_sim.sh" minisoc_counter_reset_pico

echo
echo "[20/21] 运行 DarkRISCV counter reset 仿真"
"$REPO_ROOT/sim/run_sim.sh" minisoc_counter_reset_dark

echo
echo "[21/21] 运行双核 firmware regression"
"$REPO_ROOT/scripts/test_dual_core_regression.sh"

echo
echo "本地 test flow 完成"
