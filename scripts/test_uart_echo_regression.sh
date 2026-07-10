#!/usr/bin/env bash
# Build the UART echo firmware and verify RX -> CPU -> TX on both CPU cores.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
UART_ECHO_MAIN="$REPO_ROOT/firmware/tests/uart_echo.c"
FIRMWARE_OUT="$REPO_ROOT/firmware/build/regression/uart_echo/firmware"

FIRMWARE_MAIN="$UART_ECHO_MAIN" FIRMWARE_OUT="$FIRMWARE_OUT" \
    "$REPO_ROOT/scripts/build_firmware.sh" >/dev/null
FIRMWARE_MEM="$FIRMWARE_OUT.mem" "$REPO_ROOT/sim/run_sim.sh" minisoc_uart_echo_pico
FIRMWARE_MEM="$FIRMWARE_OUT.mem" "$REPO_ROOT/sim/run_sim.sh" minisoc_uart_echo_dark

echo "PASS: UART RX/TX echo passed on both CPU implementations"
