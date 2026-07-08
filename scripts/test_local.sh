#!/usr/bin/env bash
# 本地一键 smoke flow。
# 给新组员判断“当前骨架有没有坏”：先查工具，再构建 firmware，再跑 RTL syntax 和仿真。
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

echo "[1/30] 检查本地工具链"
"$REPO_ROOT/scripts/check_env.sh"

echo
echo "[2/30] 构建 firmware"
"$REPO_ROOT/scripts/build_firmware.sh"

echo
echo "[3/30] 检查 RTL syntax"
"$REPO_ROOT/scripts/check_rtl_syntax.sh"

echo
echo "[4/30] 运行 probe_led_key_top 仿真"
"$REPO_ROOT/sim/run_sim.sh" probe_led_key

echo
echo "[5/30] 运行 probe_uart_top 仿真"
"$REPO_ROOT/sim/run_sim.sh" probe_uart_top

echo
echo "[6/30] 运行 bram 仿真"
"$REPO_ROOT/sim/run_sim.sh" bram

echo
echo "[7/30] 运行 bram_dualport 仿真"
"$REPO_ROOT/sim/run_sim.sh" bram_dualport

echo
echo "[8/30] 运行 tinybus_decode 仿真"
"$REPO_ROOT/sim/run_sim.sh" tinybus_decode

echo
echo "[9/30] 运行 mmio_test_exit 仿真"
"$REPO_ROOT/sim/run_sim.sh" mmio_test_exit

echo
echo "[10/30] 运行 UART TX 仿真"
"$REPO_ROOT/sim/run_sim.sh" uart_tx

echo
echo "[11/30] 运行 SDRAM smoke 控制器仿真"
"$REPO_ROOT/sim/run_sim.sh" sdram_smoke

echo
echo "[12/30] 运行 SDRAM data controller 仿真"
"$REPO_ROOT/sim/run_sim.sh" sdram_data_ctrl

echo
echo "[13/30] 运行 SDRAM tester 控制器仿真"
"$REPO_ROOT/sim/run_sim.sh" sdram_tester

echo
echo "[14/30] 运行 SDRAM tester 受控失败仿真"
"$REPO_ROOT/sim/run_sim.sh" sdram_tester_fail

echo
echo "[15/30] 运行 SDRAM tester reset 重复仿真"
"$REPO_ROOT/sim/run_sim.sh" sdram_tester_reset

echo
echo "[16/30] 运行 SDRAM tester UART reporter 仿真"
"$REPO_ROOT/sim/run_sim.sh" sdram_tester_uart_reporter

echo
echo "[17/30] 运行 bigboard traffic-light 仿真"
"$REPO_ROOT/sim/run_sim.sh" bigboard_tl

echo
echo "[18/30] 运行 buzzer UART debug probe 仿真"
"$REPO_ROOT/sim/run_sim.sh" probe_buzzer_uart

echo
echo "[19/30] 运行 VGA thin probe 仿真"
"$REPO_ROOT/sim/run_sim.sh" probe_vga

echo
echo "[20/30] 运行 VGA text-mode 仿真"
"$REPO_ROOT/sim/run_sim.sh" vga_text_mode

echo
echo "[21/30] 运行 PicoRV32 MiniSoC board-top smoke 仿真"
"$REPO_ROOT/sim/run_sim.sh" minisoc_smoke_pico

echo
echo "[22/30] 运行 DarkRISCV MiniSoC board-top smoke 仿真"
"$REPO_ROOT/sim/run_sim.sh" minisoc_smoke_dark

echo
echo "[23/30] 运行 MiniSoC smoke / regression bench 模式检查"
"$REPO_ROOT/scripts/test_minisoc_tb_modes.sh"

echo
echo "[24/30] 运行单次 UART 写回归"
bash "$REPO_ROOT/scripts/test_uart_once_regression.sh"

echo
echo "[25/30] 运行 PicoRV32 counter source 仿真"
"$REPO_ROOT/sim/run_sim.sh" minisoc_counter_source_pico

echo
echo "[26/30] 运行 DarkRISCV counter source 仿真"
"$REPO_ROOT/sim/run_sim.sh" minisoc_counter_source_dark

echo
echo "[27/30] 检查 perf 仿真入口缺少地址时会失败"
"$REPO_ROOT/scripts/test_perf_targets_require_addrs.sh"

echo
echo "[28/30] 运行 PicoRV32 counter reset 仿真"
"$REPO_ROOT/sim/run_sim.sh" minisoc_counter_reset_pico

echo
echo "[29/30] 运行 DarkRISCV counter reset 仿真"
"$REPO_ROOT/sim/run_sim.sh" minisoc_counter_reset_dark

echo
echo "[30/30] 运行双核 firmware regression"
"$REPO_ROOT/scripts/test_dual_core_regression.sh"

echo
echo "本地 test flow 完成"
