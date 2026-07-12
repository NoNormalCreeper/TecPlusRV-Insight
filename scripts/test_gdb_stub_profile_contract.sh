#!/usr/bin/env bash
# 验证 GDB profile 对用户程序暴露 breakpoint helper、模式宏与 DWARF。
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
readelf_tool=${READELF:-riscv64-unknown-elf-readelf}
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

cat >"$tmp_dir/gdb_user_contract.c" <<'EOF'
#include "gdb/gdb_stub.h"
#include "runtime/trap.h"

#ifndef GDB_STUB_ACTIVE
#error "gdb_stub profile 必须定义 GDB_STUB_ACTIVE"
#endif

volatile unsigned int gdb_user_value;

int main(void)
{
    trap_init();
    gdb_user_value = 0x12345678u;
    gdb_breakpoint();
    for (;;) {
    }
}
EOF

FIRMWARE_PROFILE=gdb_stub \
FIRMWARE_MAIN="$tmp_dir/gdb_user_contract.c" \
FIRMWARE_OUT="$tmp_dir/firmware" \
    "$repo_root/scripts/build_firmware.sh" >/dev/null

"$readelf_tool" --debug-dump=info "$tmp_dir/firmware.elf" |
    grep -F 'gdb_user_contract.c' >/dev/null

echo "PASS: GDB profile 用户入口与 DWARF 契约"
