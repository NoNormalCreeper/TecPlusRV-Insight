#!/usr/bin/env bash
# 构建一个 rv32ui case，并分别在 PicoRV32 / DarkRISCV MiniSoC 上运行。
# 复用现有 tb_minisoc，但通过 FIRMWARE_MEM 显式传入每个 case 的独立 .mem。
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
CASE_NAME=${1:-}
SAFE_CASES=(
    simple
    add addi
    and andi
    auipc
    beq bge bgeu blt bltu bne
    jal jalr
    lb lbu lh lhu lw ld_st
    lui
    or ori
    sb sh sw st_ld
    sll slli
    slt slti sltiu sltu
    sra srai
    srl srli
    sub
    xor xori
)
EXTRA_CASES=(
    fence_i
)
TRAPISH_CASES=(
    ma_data
)

usage() {
    cat <<'EOF'
用法：
  scripts/test_riscv_test_case.sh <rv32ui-case>
  scripts/test_riscv_test_case.sh safe
  scripts/test_riscv_test_case.sh extra
  scripts/test_riscv_test_case.sh all

示例：
  scripts/test_riscv_test_case.sh add
  scripts/test_riscv_test_case.sh sw
  scripts/test_riscv_test_case.sh safe
EOF
}

if [ -z "$CASE_NAME" ]; then
    usage >&2
    exit 1
fi

run_one_case() {
    local case_name="$1"
    "$REPO_ROOT/scripts/build_riscv_test.sh" "$case_name"

    local case_build_dir="$REPO_ROOT/build/riscv_tests/$case_name"
    local case_mem="$case_build_dir/$case_name.mem"
    if [ ! -f "$case_mem" ]; then
        echo "构建后找不到 .mem：$case_mem" >&2
        exit 1
    fi

    mkdir -p "$REPO_ROOT/sim/build/riscv_tests"

    echo "--- PicoRV32: $case_name ---"
    FIRMWARE_MEM="$case_mem" "$REPO_ROOT/sim/run_sim.sh" minisoc_rvtest_pico
    cp "$REPO_ROOT/sim/build/tb_minisoc_rvtest_pico.log" "$REPO_ROOT/sim/build/riscv_tests/${case_name}_pico.log"

    echo "--- DarkRISCV: $case_name ---"
    FIRMWARE_MEM="$case_mem" "$REPO_ROOT/sim/run_sim.sh" minisoc_rvtest_dark
    cp "$REPO_ROOT/sim/build/tb_minisoc_rvtest_dark.log" "$REPO_ROOT/sim/build/riscv_tests/${case_name}_dark.log"

    echo "riscv-test 仿真完成：$case_name"
}

run_group() {
    local group_name="$1"
    shift
    local case_name
    echo "=== 运行分组：$group_name ==="
    for case_name in "$@"; do
        run_one_case "$case_name"
    done
    echo "=== 分组完成：$group_name ==="
}

case "$CASE_NAME" in
    safe)
        run_group "safe" "${SAFE_CASES[@]}"
        ;;
    extra)
        run_group "extra" "${EXTRA_CASES[@]}"
        ;;
    all)
        run_group "safe" "${SAFE_CASES[@]}"
        run_group "extra" "${EXTRA_CASES[@]}"
        ;;
    trapish)
        echo "trapish case 当前单独保留，不纳入默认批量： ${TRAPISH_CASES[*]}"
        run_group "trapish" "${TRAPISH_CASES[@]}"
        ;;
    *)
        run_one_case "$CASE_NAME"
        ;;
esac

echo "日志目录：$REPO_ROOT/sim/build/riscv_tests"
