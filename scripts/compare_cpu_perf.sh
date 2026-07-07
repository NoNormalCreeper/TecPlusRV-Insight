#!/usr/bin/env bash
# 最小双核性能对比：构建一个固定 benchmark，再分别跑 PicoRV32 / DarkRISCV。
# 输出 SoC 侧的 cycle / instret / CPI，适合早期粗对比，不是最终严格性能报告。
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
PERF_MAIN=${1:-$REPO_ROOT/firmware/tests/perf_mix.c}
DEFAULT_MAIN="$REPO_ROOT/firmware/main.c"
PERF_DIR="$REPO_ROOT/sim/build/perf"

mkdir -p "$PERF_DIR"

restore_default() {
    FIRMWARE_MAIN="$DEFAULT_MAIN" "$REPO_ROOT/scripts/build_firmware.sh" >/dev/null
}

extract_field() {
    local log_file="$1"
    local field_name="$2"
    awk -v key="$field_name" '
        /^RESULT:/ {
            for (i = 1; i <= NF; i++) {
                split($i, kv, "=");
                if (kv[1] == key) {
                    print kv[2];
                    exit;
                }
            }
        }
    ' "$log_file"
}

trap restore_default EXIT

echo "=== 构建性能 benchmark ==="
FIRMWARE_MAIN="$PERF_MAIN" "$REPO_ROOT/scripts/build_firmware.sh"

echo
echo "=== PicoRV32 ==="
"$REPO_ROOT/sim/run_sim.sh" minisoc_perf_pico
cp "$REPO_ROOT/sim/build/tb_minisoc_perf_pico.log" "$PERF_DIR/pico.log"

echo
echo "=== DarkRISCV ==="
"$REPO_ROOT/sim/run_sim.sh" minisoc_perf_dark
cp "$REPO_ROOT/sim/build/tb_minisoc_perf_dark.log" "$PERF_DIR/dark.log"

PICO_CYCLES=$(extract_field "$PERF_DIR/pico.log" "cycles")
PICO_INSTRET=$(extract_field "$PERF_DIR/pico.log" "instret")
PICO_CPI_X1000=$(extract_field "$PERF_DIR/pico.log" "cpi_x1000")

DARK_CYCLES=$(extract_field "$PERF_DIR/dark.log" "cycles")
DARK_INSTRET=$(extract_field "$PERF_DIR/dark.log" "instret")
DARK_CPI_X1000=$(extract_field "$PERF_DIR/dark.log" "cpi_x1000")

echo
printf "%-12s %-12s %-12s %-12s\n" "cpu" "cycles" "instret" "cpi_x1000"
printf "%-12s %-12s %-12s %-12s\n" "picorv32" "$PICO_CYCLES" "$PICO_INSTRET" "$PICO_CPI_X1000"
printf "%-12s %-12s %-12s %-12s\n" "darkriscv" "$DARK_CYCLES" "$DARK_INSTRET" "$DARK_CPI_X1000"

echo
echo "性能对比日志保存在：$PERF_DIR"
