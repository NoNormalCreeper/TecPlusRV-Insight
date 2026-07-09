#!/usr/bin/env bash
# Verify buzzer MMIO programming and SPK toggles on both CPU implementations.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUZZER_MAIN="$REPO_ROOT/firmware/tests/buzzer_mmio.c"
DEFAULT_MAIN="$REPO_ROOT/firmware/main.c"

cleanup() {
    FIRMWARE_MAIN="$DEFAULT_MAIN" "$REPO_ROOT/scripts/build_firmware.sh" >/dev/null || true
}

trap cleanup EXIT

FIRMWARE_MAIN="$BUZZER_MAIN" "$REPO_ROOT/scripts/build_firmware.sh" >/dev/null
"$REPO_ROOT/sim/run_sim.sh" minisoc_buzzer_pico
"$REPO_ROOT/sim/run_sim.sh" minisoc_buzzer_dark

echo "PASS: buzzer MMIO passed on both CPU implementations"
