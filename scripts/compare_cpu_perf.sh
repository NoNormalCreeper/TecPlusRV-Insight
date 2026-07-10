#!/usr/bin/env bash
# 最小双核性能对比：构建一个固定 benchmark，再分别跑 PicoRV32 / DarkRISCV。
# 输出 benchmark 测量区间内的 cycle / instret / CPI，适合双核粗对比，
# 但当前 DarkRISCV 的 instret 仍然来自其内部 CSR 计数，不是形式化 retire 证明。
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
PERF_MAIN=${1:-$REPO_ROOT/firmware/tests/perf_mix.c}
PERF_DIR="$REPO_ROOT/sim/build/perf"
FIRMWARE_OUT="$REPO_ROOT/firmware/build/perf/firmware"
OBJDUMP=${OBJDUMP:-riscv64-unknown-elf-objdump}

mkdir -p "$PERF_DIR"

if ! command -v "$OBJDUMP" >/dev/null 2>&1; then
    echo "缺少必需工具：$OBJDUMP" >&2
    exit 1
fi

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

extract_symbol_addr() {
    local symbol_name="$1"

    "$OBJDUMP" -t "$FIRMWARE_OUT.elf" | awk -v sym="$symbol_name" '
        $NF == sym {
            print "0x" $1;
            exit;
        }
    '
}

echo "=== 构建性能 benchmark ==="
FIRMWARE_MAIN="$PERF_MAIN" FIRMWARE_OUT="$FIRMWARE_OUT" \
    "$REPO_ROOT/scripts/build_firmware.sh"

PERF_RESULT_CYCLE_ADDR=$(extract_symbol_addr "perf_cycle_delta")
PERF_RESULT_INSTRET_ADDR=$(extract_symbol_addr "perf_instret_delta")

if [ -z "$PERF_RESULT_CYCLE_ADDR" ] || [ -z "$PERF_RESULT_INSTRET_ADDR" ]; then
    echo "未能从 firmware.elf 提取 perf delta 符号地址" >&2
    exit 1
fi

echo
echo "=== PicoRV32 ==="
PERF_RESULT_CYCLE_ADDR="$PERF_RESULT_CYCLE_ADDR" \
PERF_RESULT_INSTRET_ADDR="$PERF_RESULT_INSTRET_ADDR" \
FIRMWARE_MEM="$FIRMWARE_OUT.mem" \
    "$REPO_ROOT/sim/run_sim.sh" minisoc_perf_pico
cp "$REPO_ROOT/sim/build/tb_minisoc_perf_pico.log" "$PERF_DIR/pico.log"

echo
echo "=== DarkRISCV ==="
PERF_RESULT_CYCLE_ADDR="$PERF_RESULT_CYCLE_ADDR" \
PERF_RESULT_INSTRET_ADDR="$PERF_RESULT_INSTRET_ADDR" \
FIRMWARE_MEM="$FIRMWARE_OUT.mem" \
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
