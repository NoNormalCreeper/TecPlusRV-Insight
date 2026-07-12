#!/usr/bin/env bash
# 验证 GDB stub 上传入口复用 bootload，且 ACK 后不进入串口 monitor。
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
output=$(make --no-print-directory -n -C "$repo_root" gdb-stub-load PORT=COM8)
default_output=$(make --no-print-directory -n -C "$repo_root" bootload PORT=COM8)
debug_output=$(make --no-print-directory -n -C "$repo_root" gdb-stub-debug PORT=COM8)
user_output=$(make --no-print-directory -n -C "$repo_root" gdb-stub-debug \
    PORT=COM8 GDB_STUB_MAIN=/tmp/gdb_user_program.c)

grep -F 'bootload PORT="COM8"' <<<"$output" >/dev/null
grep -F 'FIRMWARE_PROFILE="gdb_stub"' <<<"$output" >/dev/null
grep -F 'firmware/tests/gdb_stub_smoke.c' <<<"$output" >/dev/null
grep -F 'scripts/uart_loader.py' <<<"$output" >/dev/null

if grep -F -- '--monitor' <<<"$output" >/dev/null; then
    echo "FAIL: gdb-stub-load 上传后仍会进入串口 monitor" >&2
    exit 1
fi
grep -F -- '--monitor' <<<"$default_output" >/dev/null

grep -F 'riscv-none-elf-gdb.exe' <<<"$debug_output" >/dev/null
grep -F 'firmware/build/bootload/firmware.elf' <<<"$debug_output" >/dev/null
grep -F -- '-ex "set serial baud 9600"' <<<"$debug_output" >/dev/null
grep -F -- '-ex "set substitute-path ' <<<"$debug_output" >/dev/null
grep -F 'wslpath -m' <<<"$debug_output" >/dev/null
grep -F -- '-ex "target remote COM8"' <<<"$debug_output" >/dev/null
grep -F 'FIRMWARE_MAIN="/tmp/gdb_user_program.c"' <<<"$user_output" >/dev/null

echo "PASS: GDB stub 复用 bootload 并启动 Windows GDB"
