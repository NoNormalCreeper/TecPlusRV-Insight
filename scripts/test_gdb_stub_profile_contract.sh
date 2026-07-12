#!/usr/bin/env bash
# 验证 GDB runtime/debug 组合、自动 main wrapper、公共 breakpoint API 与 DWARF。
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
readelf_tool=${READELF:-riscv64-unknown-elf-readelf}
nm_tool=${NM:-riscv64-unknown-elf-nm}
objdump_tool=${OBJDUMP:-riscv64-unknown-elf-objdump}
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

cat >"$tmp_dir/gdb_user_contract.c" <<'EOF'
#include "runtime/debug.h"

#ifndef GDB_STUB_ACTIVE
#error "GDB build 必须定义 GDB_STUB_ACTIVE"
#endif

volatile unsigned int gdb_user_value;

int main(void)
{
    gdb_user_value = 0x12345678u;
    DEBUG_BREAK();
    for (;;) {
    }
}
EOF

FIRMWARE_RUNTIME=baremetal \
FIRMWARE_DEBUG=gdb \
FIRMWARE_MAIN="$tmp_dir/gdb_user_contract.c" \
FIRMWARE_OUT="$tmp_dir/runtime-debug" \
    "$repo_root/scripts/build_firmware.sh" >/dev/null

"$readelf_tool" --debug-dump=info "$tmp_dir/runtime-debug.elf" |
    grep -F 'gdb_user_contract.c' >/dev/null
"$nm_tool" "$tmp_dir/runtime-debug.elf" | grep -F ' __wrap_main' >/dev/null
"$nm_tool" "$tmp_dir/runtime-debug.elf" | grep -F ' main' >/dev/null
"$objdump_tool" -d "$tmp_dir/runtime-debug.elf" |
    grep -E 'jal[[:space:]].*<__wrap_main>' >/dev/null

# 旧 profile 入口继续映射到 baremetal + gdb。
FIRMWARE_PROFILE=gdb_stub \
FIRMWARE_MAIN="$tmp_dir/gdb_user_contract.c" \
FIRMWARE_OUT="$tmp_dir/legacy-profile" \
    "$repo_root/scripts/build_firmware.sh" >/dev/null

"$nm_tool" "$tmp_dir/legacy-profile.elf" | grep -F ' __wrap_main' >/dev/null

for runtime in irq freertos; do
    error_file="$tmp_dir/$runtime.err"
    if FIRMWARE_RUNTIME="$runtime" FIRMWARE_DEBUG=gdb \
        FIRMWARE_MAIN="$tmp_dir/gdb_user_contract.c" \
        FIRMWARE_OUT="$tmp_dir/$runtime-gdb" \
        "$repo_root/scripts/build_firmware.sh" >"$tmp_dir/$runtime.out" 2>"$error_file"; then
        echo "FAIL: $runtime + gdb 组合意外构建成功" >&2
        exit 1
    fi
    grep -F "当前 GDB 调试尚不支持 $runtime 应用" "$error_file" >/dev/null
done

echo "PASS: GDB runtime/debug 组合、自动接入与 DWARF 契约"
