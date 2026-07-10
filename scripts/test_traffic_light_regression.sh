#!/usr/bin/env bash
# Verify CPU MMIO write/readback reaches TL pins on both CPU implementations.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
TRAFFIC_MAIN="$REPO_ROOT/firmware/tests/traffic_light_mmio.c"
FIRMWARE_OUT="$REPO_ROOT/firmware/build/regression/traffic_light/firmware"

FIRMWARE_MAIN="$TRAFFIC_MAIN" FIRMWARE_OUT="$FIRMWARE_OUT" \
    "$REPO_ROOT/scripts/build_firmware.sh" >/dev/null
FIRMWARE_MEM="$FIRMWARE_OUT.mem" "$REPO_ROOT/sim/run_sim.sh" minisoc_traffic_pico
FIRMWARE_MEM="$FIRMWARE_OUT.mem" "$REPO_ROOT/sim/run_sim.sh" minisoc_traffic_dark

echo "PASS: traffic-light MMIO passed on both CPU implementations"
