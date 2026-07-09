#!/usr/bin/env bash
# Verify CPU MMIO write/readback reaches TL pins on both CPU implementations.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
TRAFFIC_MAIN="$REPO_ROOT/firmware/tests/traffic_light_mmio.c"
DEFAULT_MAIN="$REPO_ROOT/firmware/main.c"

cleanup() {
    FIRMWARE_MAIN="$DEFAULT_MAIN" "$REPO_ROOT/scripts/build_firmware.sh" >/dev/null || true
}

trap cleanup EXIT

FIRMWARE_MAIN="$TRAFFIC_MAIN" "$REPO_ROOT/scripts/build_firmware.sh" >/dev/null
"$REPO_ROOT/sim/run_sim.sh" minisoc_traffic_pico
"$REPO_ROOT/sim/run_sim.sh" minisoc_traffic_dark

echo "PASS: traffic-light MMIO passed on both CPU implementations"
