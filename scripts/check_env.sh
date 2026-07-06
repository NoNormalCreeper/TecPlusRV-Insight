#!/usr/bin/env bash
set -eu

check_tool() {
    local name="$1"
    local kind="$2"

    if command -v "$name" >/dev/null 2>&1; then
        printf '[ok]      %-24s %s\n' "$name" "$kind"
    else
        printf '[missing] %-24s %s\n' "$name" "$kind"
    fi
}

echo "TecPlusRV 本地环境检查"
echo
check_tool riscv64-unknown-elf-gcc "firmware 构建必需"
check_tool riscv64-unknown-elf-objcopy "firmware 构建必需"
check_tool riscv64-unknown-elf-objdump "可选的反汇编辅助工具"
check_tool python3 "构建辅助脚本必需"
check_tool iverilog "本地 RTL simulation 需要"
check_tool vvp "本地 RTL simulation 需要"
