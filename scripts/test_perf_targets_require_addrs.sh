#!/usr/bin/env bash
# 检查公开 perf 仿真目标在缺少结果地址时会 fail fast，
# 避免静默回退到默认地址并产出伪造结果。
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
TMP_LOG=$(mktemp)

cleanup() {
    rm -f "$TMP_LOG"
}

trap cleanup EXIT

"$REPO_ROOT/scripts/build_firmware.sh" >/dev/null

for sim_kind in minisoc_perf_pico minisoc_perf_dark; do
    if PERF_RESULT_CYCLE_ADDR= PERF_RESULT_INSTRET_ADDR= \
        "$REPO_ROOT/sim/run_sim.sh" "$sim_kind" >"$TMP_LOG" 2>&1; then
        cat "$TMP_LOG"
        echo "FAIL: $sim_kind 在缺少 PERF_RESULT_* 地址时仍然成功" >&2
        exit 1
    fi

    if ! grep -q "PERF_RESULT_CYCLE_ADDR" "$TMP_LOG"; then
        cat "$TMP_LOG"
        echo "FAIL: $sim_kind 失败时没有明确指出缺少 perf 结果地址" >&2
        exit 1
    fi
done

echo "PASS: perf 仿真目标会在缺少结果地址时立即失败"
