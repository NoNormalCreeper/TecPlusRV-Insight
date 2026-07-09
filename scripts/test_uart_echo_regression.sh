#!/usr/bin/env bash
# Build the UART echo firmware and verify RX -> CPU -> TX on both CPU cores.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
UART_ECHO_MAIN="$REPO_ROOT/firmware/tests/uart_echo.c"
DEFAULT_MAIN="$REPO_ROOT/firmware/main.c"

cleanup() {
    FIRMWARE_MAIN="$DEFAULT_MAIN" "$REPO_ROOT/scripts/build_firmware.sh" >/dev/null || true
}

trap cleanup EXIT

FIRMWARE_MAIN="$UART_ECHO_MAIN" "$REPO_ROOT/scripts/build_firmware.sh" >/dev/null
"$REPO_ROOT/sim/run_sim.sh" minisoc_uart_echo_pico
"$REPO_ROOT/sim/run_sim.sh" minisoc_uart_echo_dark

echo "PASS: UART RX/TX echo passed on both CPU implementations"
