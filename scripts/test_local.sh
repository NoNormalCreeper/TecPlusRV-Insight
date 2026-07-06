#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

echo "[1/5] 检查本地工具链"
"$REPO_ROOT/scripts/check_env.sh"

echo
echo "[2/5] 构建 firmware"
"$REPO_ROOT/scripts/build_firmware.sh"

echo
echo "[3/5] 检查 RTL syntax"
"$REPO_ROOT/scripts/check_rtl_syntax.sh"

echo
echo "[4/5] 运行 UART TX 仿真"
"$REPO_ROOT/sim/run_sim.sh" uart_tx

echo
echo "[5/5] 运行 MiniSoC testbench 骨架"
"$REPO_ROOT/sim/run_sim.sh" minisoc

echo
echo "本地 test flow 完成"
