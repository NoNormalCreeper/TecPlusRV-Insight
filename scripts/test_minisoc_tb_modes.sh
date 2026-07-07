#!/usr/bin/env bash
# 区分 MiniSoC 通用 regression bench 与 board-top smoke bench 的语义：
# quiet_pass 不触发 UART，因此应该通过通用目标、但被严格 smoke 目标拒绝。
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
QUIET_MAIN="$REPO_ROOT/firmware/tests/quiet_pass.c"
DEFAULT_MAIN="$REPO_ROOT/firmware/main.c"
TMP_LOG=$(mktemp)

cleanup() {
    FIRMWARE_MAIN="$DEFAULT_MAIN" "$REPO_ROOT/scripts/build_firmware.sh" >/dev/null || true
    rm -f "$TMP_LOG"
}

trap cleanup EXIT

FIRMWARE_MAIN="$QUIET_MAIN" "$REPO_ROOT/scripts/build_firmware.sh" >/dev/null

for sim_kind in minisoc_pico minisoc_dark; do
    if ! "$REPO_ROOT/sim/run_sim.sh" "$sim_kind" >"$TMP_LOG" 2>&1; then
        cat "$TMP_LOG"
        echo "FAIL: $sim_kind 应该接受 quiet_pass 这类无 UART firmware" >&2
        exit 1
    fi
done

for sim_kind in minisoc_smoke_pico minisoc_smoke_dark; do
    if "$REPO_ROOT/sim/run_sim.sh" "$sim_kind" >"$TMP_LOG" 2>&1; then
        cat "$TMP_LOG"
        echo "FAIL: $sim_kind 不应该接受 quiet_pass 这类无 UART firmware" >&2
        exit 1
    fi

    if ! grep -q "No UART write occurred" "$TMP_LOG"; then
        cat "$TMP_LOG"
        echo "FAIL: $sim_kind 失败原因不是缺少 UART 写" >&2
        exit 1
    fi
done

echo "PASS: MiniSoC regression / smoke bench 语义区分正确"
