#!/usr/bin/env bash
# 双核 regression：对同一批裸机自检程序分别跑 PicoRV32 和 DarkRISCV。
# 目标是验证 wrapper 切核后，软件可见 SoC 语义保持一致。
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
REGRESSION_DIR="$REPO_ROOT/sim/build/regression"
DEFAULT_MAIN="$REPO_ROOT/firmware/main.c"
TESTS=${TESTS:-"smoke alu_branch load_store counters perf_mix"}

mkdir -p "$REGRESSION_DIR"

restore_default() {
    FIRMWARE_MAIN="$DEFAULT_MAIN" "$REPO_ROOT/scripts/build_firmware.sh" >/dev/null
}

trap restore_default EXIT

for test_name in $TESTS; do
    test_main="$REPO_ROOT/firmware/tests/$test_name.c"

    echo "=== 构建 firmware 测试：$test_name ==="
    FIRMWARE_MAIN="$test_main" "$REPO_ROOT/scripts/build_firmware.sh"

    if [ -f "$REPO_ROOT/firmware/build/firmware.lst" ]; then
        cp "$REPO_ROOT/firmware/build/firmware.lst" "$REGRESSION_DIR/$test_name.lst"
    fi

    echo "--- PicoRV32: $test_name ---"
    "$REPO_ROOT/sim/run_sim.sh" minisoc_pico
    cp "$REPO_ROOT/sim/build/tb_minisoc_pico.log" "$REGRESSION_DIR/${test_name}_pico.log"

    echo "--- DarkRISCV: $test_name ---"
    "$REPO_ROOT/sim/run_sim.sh" minisoc_dark
    cp "$REPO_ROOT/sim/build/tb_minisoc_dark.log" "$REGRESSION_DIR/${test_name}_dark.log"
done

echo "双核 regression 完成：$REGRESSION_DIR"
