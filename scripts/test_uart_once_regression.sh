#!/usr/bin/env bash
# 验证“单次 UART 写”不会被 SoC 顶层重复受理。
# 这个用例专门盯 DarkRISCV 在 UART MMIO 写路径上的重复发送回归。
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
UART_ONCE_MAIN="$REPO_ROOT/firmware/tests/uart_once.c"
DEFAULT_MAIN="$REPO_ROOT/firmware/main.c"

cleanup() {
    FIRMWARE_MAIN="$DEFAULT_MAIN" "$REPO_ROOT/scripts/build_firmware.sh" >/dev/null || true
}

trap cleanup EXIT

FIRMWARE_MAIN="$UART_ONCE_MAIN" "$REPO_ROOT/scripts/build_firmware.sh" >/dev/null
"$REPO_ROOT/sim/run_sim.sh" minisoc_uart_once_pico
"$REPO_ROOT/sim/run_sim.sh" minisoc_uart_once_dark

echo "PASS: 单次 UART 写在两种 CPU 下都只发送 1 次"
