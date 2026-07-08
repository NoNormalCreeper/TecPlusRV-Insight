#!/usr/bin/env bash
# 构建单个官方 riscv-tests case，并产出供 MiniSoC BRAM 使用的 .mem。
# 这里先只支持 rv32ui；trap/特权相关环境以后单独扩展。
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

CC=${CC:-riscv64-unknown-elf-gcc}
OBJCOPY=${OBJCOPY:-riscv64-unknown-elf-objcopy}
OBJDUMP=${OBJDUMP:-riscv64-unknown-elf-objdump}
PYTHON=${PYTHON:-python3}

RVTEST_ROOT="$REPO_ROOT/tests/riscv_tests"
CASE_ROOT="$RVTEST_ROOT/riscv-tests/isa/rv32ui"
ENV_ROOT="$RVTEST_ROOT/tecplus_p"

need_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "缺少必需工具：$1" >&2
        exit 1
    fi
}

usage() {
    cat <<'EOF'
用法：
  scripts/build_riscv_test.sh <case>

示例：
  scripts/build_riscv_test.sh add
  scripts/build_riscv_test.sh sw
EOF
}

if [ $# -ne 1 ]; then
    usage >&2
    exit 1
fi

need_tool "$CC"
need_tool "$OBJCOPY"
need_tool "$PYTHON"

case_name="$1"
case_path="$CASE_ROOT/$case_name.S"
if [ ! -f "$case_path" ]; then
    echo "找不到 rv32ui 测试：$case_path" >&2
    exit 1
fi

out_dir="$REPO_ROOT/build/riscv_tests/$case_name"
mkdir -p "$out_dir"

CFLAGS=(
    -march=rv32i
    -mabi=ilp32
    -ffreestanding
    -nostdlib
    -nostartfiles
    -Wall
    -Wextra
    -Werror
    -T "$ENV_ROOT/link.ld"
    -I "$ENV_ROOT"
    -I "$CASE_ROOT"
    -I "$REPO_ROOT/tests/riscv_tests/riscv-tests/isa/rv64ui"
    -I "$REPO_ROOT/tests/riscv_tests/riscv-tests/isa/macros/scalar"
)

"$CC" "${CFLAGS[@]}" -o "$out_dir/$case_name.elf" "$case_path"
"$OBJCOPY" -O binary "$out_dir/$case_name.elf" "$out_dir/$case_name.bin"
"$PYTHON" "$REPO_ROOT/scripts/bin2mem.py" "$out_dir/$case_name.bin" "$out_dir/$case_name.mem" 16384

if command -v "$OBJDUMP" >/dev/null 2>&1; then
    "$OBJDUMP" -d "$out_dir/$case_name.elf" > "$out_dir/$case_name.lst"
fi

echo "riscv-test 构建完成："
echo "  case: $case_name"
echo "  elf : $out_dir/$case_name.elf"
echo "  bin : $out_dir/$case_name.bin"
echo "  mem : $out_dir/$case_name.mem"
