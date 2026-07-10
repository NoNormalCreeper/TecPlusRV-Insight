#!/usr/bin/env bash
# Verify buzzer MMIO programming and SPK toggles on both CPU implementations.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUZZER_MAIN="$REPO_ROOT/firmware/tests/buzzer_mmio.c"
FIRMWARE_OUT="$REPO_ROOT/firmware/build/regression/buzzer/firmware"

FIRMWARE_MAIN="$BUZZER_MAIN" FIRMWARE_OUT="$FIRMWARE_OUT" \
    "$REPO_ROOT/scripts/build_firmware.sh" >/dev/null
FIRMWARE_MEM="$FIRMWARE_OUT.mem" "$REPO_ROOT/sim/run_sim.sh" minisoc_buzzer_pico
FIRMWARE_MEM="$FIRMWARE_OUT.mem" "$REPO_ROOT/sim/run_sim.sh" minisoc_buzzer_dark

echo "PASS: buzzer MMIO passed on both CPU implementations"
