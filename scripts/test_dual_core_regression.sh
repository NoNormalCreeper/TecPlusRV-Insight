#!/usr/bin/env bash
# 双核 regression：对同一批裸机自检程序分别跑 PicoRV32 和 DarkRISCV。
# 目标是验证 wrapper 切核后，软件可见 SoC 语义保持一致。
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
REGRESSION_DIR="$REPO_ROOT/sim/build/regression"
DEFAULT_MAIN="$REPO_ROOT/firmware/main.c"
TESTS=${TESTS:-"smoke alu_branch load_store counters perf_mix sdram_memtest runtime_heap_smoke"}

mkdir -p "$REGRESSION_DIR"

restore_default() {
    FIRMWARE_MAIN="$DEFAULT_MAIN" "$REPO_ROOT/scripts/build_firmware.sh" >/dev/null
}

trap restore_default EXIT

for test_name in $TESTS; do
    test_main="$REPO_ROOT/firmware/tests/$test_name.c"
    pico_target="minisoc_pico"
    dark_target="minisoc_dark"
    pico_log="tb_minisoc_pico.log"
    dark_log="tb_minisoc_dark.log"

    case "$test_name" in
        sdram_memtest|sdram_sum_bench|runtime_heap_smoke)
            pico_target="minisoc_sdram_pico"
            dark_target="minisoc_sdram_dark"
            pico_log="tb_minisoc_sdram_pico.log"
            dark_log="tb_minisoc_sdram_dark.log"
            ;;
    esac

    echo "=== 构建 firmware 测试：$test_name ==="
    FIRMWARE_MAIN="$test_main" "$REPO_ROOT/scripts/build_firmware.sh"

    if [ -f "$REPO_ROOT/firmware/build/firmware.lst" ]; then
        cp "$REPO_ROOT/firmware/build/firmware.lst" "$REGRESSION_DIR/$test_name.lst"
    fi

    echo "--- PicoRV32: $test_name ---"
    FIRMWARE_MAIN="$test_main" "$REPO_ROOT/sim/run_sim.sh" "$pico_target"
    cp "$REPO_ROOT/sim/build/$pico_log" "$REGRESSION_DIR/${test_name}_pico.log"

    echo "--- DarkRISCV: $test_name ---"
    FIRMWARE_MAIN="$test_main" "$REPO_ROOT/sim/run_sim.sh" "$dark_target"
    cp "$REPO_ROOT/sim/build/$dark_log" "$REGRESSION_DIR/${test_name}_dark.log"
done

echo "双核 regression 完成：$REGRESSION_DIR"
