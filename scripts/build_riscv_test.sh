#!/usr/bin/env bash
# 构建单个官方 riscv-tests case，并产出供 MiniSoC BRAM 使用的 .mem。
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

CC=${CC:-riscv64-unknown-elf-gcc}
OBJCOPY=${OBJCOPY:-riscv64-unknown-elf-objcopy}
OBJDUMP=${OBJDUMP:-riscv64-unknown-elf-objdump}
PYTHON=${PYTHON:-python3}

RVTEST_ROOT="$REPO_ROOT/tests/riscv_tests"

need_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "缺少必需工具：$1" >&2
        exit 1
    fi
}

usage() {
    cat <<'EOF'
用法：
  scripts/build_riscv_test.sh <profile> <case>
  scripts/build_riscv_test.sh <rv32ui-case>  # 兼容旧接口

示例：
  scripts/build_riscv_test.sh rv32ui add
  scripts/build_riscv_test.sh rv32mi csr
  scripts/build_riscv_test.sh add
EOF
}

if [ $# -eq 1 ]; then
    profile=rv32ui
    case_name="$1"
elif [ $# -eq 2 ]; then
    profile="$1"
    case_name="$2"
else
    usage >&2
    exit 1
fi

case "$profile" in
    rv32ui)
        CASE_ROOT="$RVTEST_ROOT/riscv-tests/isa/rv32ui"
        ENV_ROOT="$RVTEST_ROOT/tecplus_p"
        ;;
    rv32mi)
        CASE_ROOT="$RVTEST_ROOT/riscv-tests/isa/rv32mi"
        ENV_ROOT="$RVTEST_ROOT/tecplus_m"
        ;;
    *)
        echo "未知 riscv-test profile：$profile" >&2
        exit 1
        ;;
esac

need_tool "$CC"
need_tool "$OBJCOPY"
need_tool "$PYTHON"

case_path="$CASE_ROOT/$case_name.S"
if [ ! -f "$case_path" ]; then
    echo "找不到 $profile 测试：$case_path" >&2
    exit 1
fi

out_dir="$REPO_ROOT/build/riscv_tests/$profile/$case_name"
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
echo "  profile: $profile"
echo "  case: $case_name"
echo "  elf : $out_dir/$case_name.elf"
echo "  bin : $out_dir/$case_name.bin"
echo "  mem : $out_dir/$case_name.mem"
