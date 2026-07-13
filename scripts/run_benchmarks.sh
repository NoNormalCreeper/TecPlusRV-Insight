#!/usr/bin/env bash
# 可复跑的性能实验入口。
# 每次运行单独保存构建记录、双核原始 UART 日志、结构化 CSV/Markdown 表和环境快照。
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
RUN_SIM="$REPO_ROOT/sim/run_sim.sh"
BUILD_FIRMWARE="$REPO_ROOT/scripts/build_firmware.sh"
RUN_ID=${BENCHMARK_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}
RESULT_DIR=${BENCHMARK_RESULT_DIR:-"$REPO_ROOT/sim/build/benchmarks/$RUN_ID"}
FIRMWARE_DIR="$REPO_ROOT/firmware/build/benchmarks/$RUN_ID"
CSV_FILE="$RESULT_DIR/results.csv"
MARKDOWN_FILE="$RESULT_DIR/summary.md"
ENV_FILE="$RESULT_DIR/environment.txt"

mkdir -p "$RESULT_DIR" "$FIRMWARE_DIR"
printf 'cpu,benchmark,scope,cycles,instret,mem_wait,mem_wait_pct,cpi,throughput_kips\n' > "$CSV_FILE"

{
    echo "run_id=$RUN_ID"
    echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "git_commit=$(git -C "$REPO_ROOT" rev-parse HEAD)"
    echo "git_status=$(git -C "$REPO_ROOT" status --porcelain | wc -l | tr -d ' ') modified_paths"
    echo "host=$(uname -srmo)"
    echo "iverilog=$(iverilog -V 2>&1 | head -n 1)"
    echo "riscv_gcc=$(riscv64-unknown-elf-gcc --version | head -n 1)"
    echo "clock_hz=1000000 (tb_minisoc / tb_minisoc_sdram parameter)"
    echo "counter_scope=firmware perf_begin/perf_end delta; mem_wait counts data-port wait cycles"
} > "$ENV_FILE"

append_results() {
    local cpu="$1"
    local log_file="$2"

    awk -v cpu="$cpu" '
        /^RESULT:/ {
            # UART 以 CRLF 结束；若 testbench 紧随其后打印 PASS，CR 后半段
            # 会落在同一文本行，不能把它误当成 mem_wait 数值的一部分。
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
                mem_wait_pct = cycles == 0 ? 0 : mem_wait * 100 / cycles
                throughput_kips = cpi == 0 ? 0 : 1000 / cpi
                printf "%s,%s,%s,%s,%s,%s,%.1f,%.3f,%.1f\n", cpu, benchmark, scope, cycles, instret, mem_wait, mem_wait_pct, cpi, throughput_kips
            }
        }
    ' "$log_file" >> "$CSV_FILE"
}

run_cpu() {
    local name="$1"
    local cpu="$2"
    local target="$3"
    local firmware_mem="$4"
    local log_file="$RESULT_DIR/${name}_${cpu}.log"

    echo "=== $name / $cpu ==="
    if ! FIRMWARE_MEM="$firmware_mem" "$RUN_SIM" "$target" > "$log_file" 2>&1; then
        cat "$log_file"
        exit 1
    fi
    cat "$log_file"
    append_results "$cpu" "$log_file"
}

run_workload() {
    local name="$1"
    local main_file="$2"
    local pico_target="$3"
    local dark_target="$4"
    local firmware_out="$FIRMWARE_DIR/$name/firmware"
    local build_log="$RESULT_DIR/${name}_build.log"

    echo "=== 构建 $name ==="
    if ! FIRMWARE_MAIN="$REPO_ROOT/$main_file" FIRMWARE_OUT="$firmware_out" \
        "$BUILD_FIRMWARE" > "$build_log" 2>&1; then
        cat "$build_log"
        exit 1
    fi
    cat "$build_log"
    run_cpu "$name" "picorv32" "$pico_target" "$firmware_out.mem"
    run_cpu "$name" "darkriscv" "$dark_target" "$firmware_out.mem"
}

extract_symbol_addr() {
    local firmware_elf="$1"
    local symbol_name="$2"

    riscv64-unknown-elf-objdump -t "$firmware_elf" | awk -v sym="$symbol_name" '
        $NF == sym {
            print "0x" $1
            exit
        }
    '
}

run_perf_cpu() {
    local cpu="$1"
    local target="$2"
    local firmware_mem="$3"
    local cycle_addr="$4"
    local instret_addr="$5"
    local log_file="$RESULT_DIR/perf_mix_${cpu}.log"

    echo "=== perf_mix / $cpu ==="
    if ! PERF_RESULT_CYCLE_ADDR="$cycle_addr" PERF_RESULT_INSTRET_ADDR="$instret_addr" \
        FIRMWARE_MEM="$firmware_mem" "$RUN_SIM" "$target" > "$log_file" 2>&1; then
        cat "$log_file"
        exit 1
    fi
    cat "$log_file"
    append_results "$cpu" "$log_file"
}

run_perf_mix() {
    local firmware_out="$FIRMWARE_DIR/perf_mix/firmware"
    local build_log="$RESULT_DIR/perf_mix_build.log"
    local cycle_addr
    local instret_addr

    echo "=== 构建 perf_mix ==="
    if ! FIRMWARE_MAIN="$REPO_ROOT/firmware/apps/baremetal/benchmarks/perf_mix.c" FIRMWARE_OUT="$firmware_out" \
        "$BUILD_FIRMWARE" > "$build_log" 2>&1; then
        cat "$build_log"
        exit 1
    fi
    cat "$build_log"
    cycle_addr=$(extract_symbol_addr "$firmware_out.elf" "perf_cycle_delta")
    instret_addr=$(extract_symbol_addr "$firmware_out.elf" "perf_instret_delta")
    if [ -z "$cycle_addr" ] || [ -z "$instret_addr" ]; then
        echo "FAIL: 未能从 perf_mix.elf 提取结果符号地址" >&2
        exit 1
    fi
    run_perf_cpu "picorv32" "minisoc_perf_pico" "$firmware_out.mem" "$cycle_addr" "$instret_addr"
    run_perf_cpu "darkriscv" "minisoc_perf_dark" "$firmware_out.mem" "$cycle_addr" "$instret_addr"
}

run_perf_mix
run_workload "system_bench" "firmware/apps/baremetal/benchmarks/system_bench.c" "minisoc_sdram_pico" "minisoc_sdram_dark"
run_workload "riscv_tests_median" "firmware/apps/baremetal/benchmarks/riscv_bench_median.c" "minisoc_sdram_pico" "minisoc_sdram_dark"
run_workload "riscv_tests_memcpy" "firmware/apps/baremetal/benchmarks/riscv_bench_memcpy.c" "minisoc_sdram_pico" "minisoc_sdram_dark"

{
    echo "# 性能实验汇总"
    echo
    echo "- 运行编号：\`$RUN_ID\`"
    echo "- 环境：\`environment.txt\`"
    echo "- 口径：cycle / instret / mem_wait 都是 firmware \`perf_begin/perf_end\` 区间差值；CPI = cycles / instret；吞吐量按 testbench 的 1 MHz 时钟换算。"
    echo
    echo "| CPU | benchmark | scope | cycles | instret | mem_wait | wait % | CPI | KIPS @ 1 MHz |"
    echo "| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |"
    awk -F, 'NR > 1 {printf "| %s | %s | %s | %s | %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5, $6, $7, $8, $9}' "$CSV_FILE"
    echo
    echo "原始 UART 日志与每个 workload 的构建日志均在当前目录。"
} > "$MARKDOWN_FILE"

cat "$MARKDOWN_FILE"
echo "性能实验结果目录：$RESULT_DIR"
