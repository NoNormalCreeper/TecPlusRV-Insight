#!/usr/bin/env bash
# 答辩 demo 的最小行为契约：GDB 可观察对象与双核普通运行路径。
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR=$(mktemp -d)
NM=${NM:-riscv64-unknown-elf-nm}

cleanup() {
    rm -rf "$BUILD_DIR"
}
trap cleanup EXIT

FIRMWARE_MAIN="$REPO_ROOT/firmware/apps/baremetal/gdb_demo.c" \
FIRMWARE_OUT="$BUILD_DIR/gdb_demo" \
    "$REPO_ROOT/scripts/build_firmware.sh" >/dev/null

state_addr=$($NM -n "$BUILD_DIR/gdb_demo.elf" | awk '$3 == "gdb_demo_state" { print $1 }')
sdram_addr=$($NM -n "$BUILD_DIR/gdb_demo.elf" | awk '$3 == "gdb_demo_sdram" { print $1 }')

if [ -z "$state_addr" ] || [ -z "$sdram_addr" ]; then
    echo "FAIL: gdb_demo 缺少可由 GDB 访问的状态 symbol" >&2
    exit 1
fi

case "$state_addr" in
    0000*) ;;
    *)
        echo "FAIL: gdb_demo_state 不在 BRAM：0x$state_addr" >&2
        exit 1
        ;;
esac

case "$sdram_addr" in
    80*|81*) ;;
    *)
        echo "FAIL: gdb_demo_sdram 不在 SDRAM：0x$sdram_addr" >&2
        exit 1
        ;;
esac

FIRMWARE_MAIN="$REPO_ROOT/firmware/apps/baremetal/gdb_demo.c" \
    "$REPO_ROOT/sim/run_sim.sh" minisoc_sdram_pico
FIRMWARE_MAIN="$REPO_ROOT/firmware/apps/baremetal/gdb_demo.c" \
    "$REPO_ROOT/sim/run_sim.sh" minisoc_sdram_dark
"$REPO_ROOT/sim/run_sim.sh" board_demo_pico
"$REPO_ROOT/sim/run_sim.sh" board_demo_dark

echo "PASS: gdb_demo 与 board_demo 答辩路径"
