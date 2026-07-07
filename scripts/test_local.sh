#!/usr/bin/env bash
# 本地一键 smoke flow。
# 给新组员判断“当前骨架有没有坏”：先查工具，再构建 firmware，再跑 RTL syntax 和仿真。
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

echo "[1/25] 检查本地工具链"
"$REPO_ROOT/scripts/check_env.sh"

echo
echo "[2/25] 构建 firmware"
"$REPO_ROOT/scripts/build_firmware.sh"

echo
echo "[3/25] 检查 RTL syntax"
"$REPO_ROOT/scripts/check_rtl_syntax.sh"

echo
echo "[4/25] 运行 probe_led_key_top 仿真"
"$REPO_ROOT/sim/run_sim.sh" probe_led_key

echo
echo "[5/25] 运行 probe_uart_top 仿真"
"$REPO_ROOT/sim/run_sim.sh" probe_uart_top

echo
echo "[6/25] 运行 bram 仿真"
"$REPO_ROOT/sim/run_sim.sh" bram

echo
echo "[7/25] 运行 bram_dualport 仿真"
"$REPO_ROOT/sim/run_sim.sh" bram_dualport

echo
echo "[8/25] 运行 tinybus_decode 仿真"
"$REPO_ROOT/sim/run_sim.sh" tinybus_decode

echo
echo "[9/25] 运行 mmio_test_exit 仿真"
"$REPO_ROOT/sim/run_sim.sh" mmio_test_exit

echo
echo "[10/25] 运行 UART TX 仿真"
"$REPO_ROOT/sim/run_sim.sh" uart_tx

echo
echo "[11/25] 运行 SDRAM smoke 控制器仿真"
"$REPO_ROOT/sim/run_sim.sh" sdram_smoke

echo
echo "[12/25] 运行 SDRAM tester 控制器仿真"
"$REPO_ROOT/sim/run_sim.sh" sdram_tester

echo
echo "[13/25] 运行 SDRAM tester 受控失败仿真"
"$REPO_ROOT/sim/run_sim.sh" sdram_tester_fail

echo
echo "[14/25] 运行 SDRAM tester reset 重复仿真"
"$REPO_ROOT/sim/run_sim.sh" sdram_tester_reset

echo
echo "[15/25] 运行 bigboard traffic-light 仿真"
"$REPO_ROOT/sim/run_sim.sh" bigboard_tl

echo
echo "[16/25] 运行 PicoRV32 MiniSoC board-top smoke 仿真"
"$REPO_ROOT/sim/run_sim.sh" minisoc_smoke_pico

echo
echo "[17/25] 运行 DarkRISCV MiniSoC board-top smoke 仿真"
"$REPO_ROOT/sim/run_sim.sh" minisoc_smoke_dark

echo
echo "[18/25] 运行 MiniSoC smoke / regression bench 模式检查"
"$REPO_ROOT/scripts/test_minisoc_tb_modes.sh"

echo
echo "[19/25] 运行单次 UART 写回归"
bash "$REPO_ROOT/scripts/test_uart_once_regression.sh"

echo
echo "[20/25] 运行 PicoRV32 counter source 仿真"
"$REPO_ROOT/sim/run_sim.sh" minisoc_counter_source_pico

echo
echo "[21/25] 运行 DarkRISCV counter source 仿真"
"$REPO_ROOT/sim/run_sim.sh" minisoc_counter_source_dark

echo
echo "[22/25] 检查 perf 仿真入口缺少地址时会失败"
"$REPO_ROOT/scripts/test_perf_targets_require_addrs.sh"

echo
echo "[23/25] 运行 PicoRV32 counter reset 仿真"
"$REPO_ROOT/sim/run_sim.sh" minisoc_counter_reset_pico

echo
echo "[24/25] 运行 DarkRISCV counter reset 仿真"
"$REPO_ROOT/sim/run_sim.sh" minisoc_counter_reset_dark

echo
echo "[25/25] 运行双核 firmware regression"
"$REPO_ROOT/scripts/test_dual_core_regression.sh"

echo
echo "本地 test flow 完成"
