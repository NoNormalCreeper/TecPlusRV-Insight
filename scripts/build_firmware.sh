#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR="$REPO_ROOT/firmware/build"
CC=${CC:-riscv64-unknown-elf-gcc}
OBJCOPY=${OBJCOPY:-riscv64-unknown-elf-objcopy}
OBJDUMP=${OBJDUMP:-riscv64-unknown-elf-objdump}
PYTHON=${PYTHON:-python3}

need_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "缺少必需工具：$1" >&2
        exit 1
    fi
}

need_tool "$CC"
need_tool "$OBJCOPY"
need_tool "$PYTHON"

mkdir -p "$BUILD_DIR"

CFLAGS="-march=rv32i -mabi=ilp32 -ffreestanding -nostdlib -nostartfiles -Wall -Wextra -Werror -Os"
INCLUDES="-I$REPO_ROOT/firmware"
LDFLAGS="-T $REPO_ROOT/firmware/linker.ld"
SOURCES="
$REPO_ROOT/firmware/startup.S
$REPO_ROOT/firmware/drivers/uart.c
$REPO_ROOT/firmware/drivers/gpio.c
$REPO_ROOT/firmware/main.c
"

"$CC" $CFLAGS $INCLUDES $LDFLAGS -o "$BUILD_DIR/firmware.elf" $SOURCES
"$OBJCOPY" -O binary "$BUILD_DIR/firmware.elf" "$BUILD_DIR/firmware.bin"
"$PYTHON" "$REPO_ROOT/scripts/bin2mem.py" "$BUILD_DIR/firmware.bin" "$BUILD_DIR/firmware.mem"

if command -v "$OBJDUMP" >/dev/null 2>&1; then
    "$OBJDUMP" -d "$BUILD_DIR/firmware.elf" > "$BUILD_DIR/firmware.lst"
fi

echo "firmware 构建完成："
echo "  $BUILD_DIR/firmware.elf"
echo "  $BUILD_DIR/firmware.bin"
echo "  $BUILD_DIR/firmware.mem"
