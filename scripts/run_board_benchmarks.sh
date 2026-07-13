#!/usr/bin/env bash
# 板级性能实验入口。
# 复用仿真 benchmark 的 firmware，通过 UART bootloader 逐个上传到真实 FPGA。
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_FIRMWARE="$REPO_ROOT/scripts/build_firmware.sh"
UART_LOADER="$REPO_ROOT/scripts/uart_loader.py"

WINDOWS_PYTHON=${WINDOWS_PYTHON:-py.exe}
PORT=${PORT:-}
BOOTLOAD_BAUD=${BOOTLOAD_BAUD:-115200}
RUN_ID=${BOARD_BENCHMARK_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}
RESULT_DIR=${BOARD_BENCHMARK_RESULT_DIR:-"$REPO_ROOT/build/board-benchmarks/$RUN_ID"}
FIRMWARE_DIR="$RESULT_DIR/firmware"
CSV_FILE="$RESULT_DIR/results.csv"
SUMMARY_FILE="$RESULT_DIR/summary.md"
ENV_FILE="$RESULT_DIR/environment.txt"

if [ -z "$PORT" ]; then
    echo "用法：make board-benchmark PORT=COM9 BOOTLOAD_BAUD=115200" >&2
    exit 1
fi

if ! command -v wslpath >/dev/null 2>&1; then
    echo "board-benchmark 需要在 WSL 中运行，以便调用 Windows COM 口。" >&2
    exit 1
fi

if ! command -v "$WINDOWS_PYTHON" >/dev/null 2>&1; then
    echo "找不到 Windows Python：$WINDOWS_PYTHON" >&2
    exit 1
fi

mkdir -p "$RESULT_DIR" "$FIRMWARE_DIR"
printf 'benchmark,scope,cycles,instret,mem_wait,cpi\n' > "$CSV_FILE"

{
    echo "run_id=$RUN_ID"
    echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "git_commit=$(git -C "$REPO_ROOT" rev-parse HEAD)"
    echo "git_status=$(git -C "$REPO_ROOT" status --porcelain | wc -l | tr -d ' ') modified_paths"
    echo "port=$PORT"
    echo "bootload_baud=$BOOTLOAD_BAUD"
    echo "host=$(uname -srmo)"
    echo "riscv_gcc=$(riscv64-unknown-elf-gcc --version | head -n 1)"
    echo "counter_scope=firmware perf_begin/perf_end delta; values come from real board UART logs"
} > "$ENV_FILE"

extract_results() {
    local log_file="$1"

    awk '
        /^RESULT:/ {
            sub(/\r.*/, "")
            benchmark = scope = ""
            cycles = instret = mem_wait = ""
            for (i = 1; i <= NF; i++) {
                split($i, pair, "=")
                key = pair[1]
                value = pair[2]
                if (key == "benchmark") benchmark = value
                else if (key == "case" || key == "memory" || key == "path") {
                    scope = scope == "" ? value : scope "_" value
                } else if (key == "cycles") cycles = value
                else if (key == "instret") instret = value
                else if (key == "mem_wait") mem_wait = value
            }
            if (benchmark != "" && cycles != "" && instret != "" && mem_wait != "") {
                cpi = instret == 0 ? 0 : cycles / instret
                printf "%s,%s,%s,%s,%s,%.3f\n", benchmark, scope, cycles, instret, mem_wait, cpi
            }
        }
    ' "$log_file" >> "$CSV_FILE"
}

run_case() {
    local name="$1"
    local main_file="$2"
    local case_dir="$FIRMWARE_DIR/$name"
    local firmware_out="$case_dir/firmware"
    local build_log="$RESULT_DIR/${name}_build.log"
    local board_log="$RESULT_DIR/${name}_board.log"

    mkdir -p "$case_dir"
    echo
    echo "=== 构建 $name ==="
    FIRMWARE_MAIN="$REPO_ROOT/$main_file" FIRMWARE_OUT="$firmware_out" \
        "$BUILD_FIRMWARE" 2>&1 | tee "$build_log"

    echo
    echo "=== 上板运行 $name ==="
    echo "请在 loader 提示后按下并松开 TEC-PLUS RESET。"
    echo "看到 PASS 或最终 RESULT 后，按 Enter 结束当前 monitor 并进入下一个 case。"
    PYTHONUTF8=1 PYTHONIOENCODING=utf-8 \
        "$WINDOWS_PYTHON" "$(wslpath -w "$UART_LOADER")" \
        --port "$PORT" \
        --baud "$BOOTLOAD_BAUD" \
        --input "$(wslpath -w "$firmware_out.bin")" \
        --monitor 2>&1 | tee "$board_log"
    local loader_status=${PIPESTATUS[0]}
    if [ "$loader_status" -ne 0 ]; then
        echo "FAIL: $name 上板运行失败，日志：$board_log" >&2
        exit "$loader_status"
    fi
    extract_results "$board_log"
}

run_case "perf_mix" "firmware/tests/perf_mix.c"
run_case "system_bench" "firmware/tests/system_bench.c"
run_case "riscv_tests_median" "firmware/tests/riscv_bench_median.c"
run_case "riscv_tests_memcpy" "firmware/tests/riscv_bench_memcpy.c"
run_case "sdram_sum_bench" "firmware/tests/sdram_sum_bench.c"

{
    echo "# 板级性能实验汇总"
    echo
    echo "- 运行编号：\`$RUN_ID\`"
    echo "- 环境：\`environment.txt\`"
    echo "- 原始串口日志：\`*_board.log\`"
    echo "- 口径：cycle / instret / mem_wait 来自真实板子的 firmware 计数器输出。"
    echo
    echo "| benchmark | scope | cycles | instret | mem_wait | CPI |"
    echo "| --- | --- | ---: | ---: | ---: | ---: |"
    awk -F, 'NR > 1 {printf "| %s | %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5, $6}' "$CSV_FILE"
} > "$SUMMARY_FILE"

cat "$SUMMARY_FILE"
echo "板级性能实验结果目录：$RESULT_DIR"
