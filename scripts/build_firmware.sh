#!/usr/bin/env bash
# firmware 构建脚本。
# 生成 firmware.elf / firmware.bin / firmware.mem；其中 .mem 供 Verilog $readmemh 使用。
# 可通过环境变量覆盖 CC/OBJCOPY/OBJDUMP/PYTHON，方便不同机器调工具链。
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR="$REPO_ROOT/firmware/build"
CC=${CC:-riscv64-unknown-elf-gcc}
OBJCOPY=${OBJCOPY:-riscv64-unknown-elf-objcopy}
OBJDUMP=${OBJDUMP:-riscv64-unknown-elf-objdump}
PYTHON=${PYTHON:-python3}
FIRMWARE_MAIN=${FIRMWARE_MAIN:-$REPO_ROOT/firmware/main.c}

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

if [ ! -f "$FIRMWARE_MAIN" ]; then
    echo "找不到 firmware 入口文件：$FIRMWARE_MAIN" >&2
    exit 1
fi

# rv32i/ilp32 对齐 PicoRV32 最小配置；freestanding 表示不依赖标准 C runtime。
CFLAGS="-march=rv32i -mabi=ilp32 -ffreestanding -nostdlib -nostartfiles -Wall -Wextra -Werror -Os"
INCLUDES="-I$REPO_ROOT/firmware"
LDFLAGS="-T $REPO_ROOT/firmware/linker.ld"
SOURCES="
$REPO_ROOT/firmware/startup.S
$REPO_ROOT/firmware/drivers/uart.c
$REPO_ROOT/firmware/drivers/gpio.c
$FIRMWARE_MAIN
$REPO_ROOT/firmware/drivers/perf.c
$REPO_ROOT/firmware/tests/selftest.c
$REPO_ROOT/firmware/main.c
"

# 不单独生成 .o，保持脚本最薄；后续文件多了再引入 Makefile/CMake。
# -lgcc 提供 rv32i 缺失的软件运算例程（如 __udivsi3/__umodsi3 软件除法），
# firmware 里的十进制打印和 CPI 计算用到了除法/取模，必须链接它。
# 放在源文件之后，保证链接器能解析到这些符号。
"$CC" $CFLAGS $INCLUDES $LDFLAGS -o "$BUILD_DIR/firmware.elf" $SOURCES -lgcc
"$OBJCOPY" -O binary "$BUILD_DIR/firmware.elf" "$BUILD_DIR/firmware.bin"
"$PYTHON" "$REPO_ROOT/scripts/bin2mem.py" "$BUILD_DIR/firmware.bin" "$BUILD_DIR/firmware.mem" 16384

if command -v "$OBJDUMP" >/dev/null 2>&1; then
    # 反汇编不是仿真必需，但调启动代码和 memory map 时很有用。
    "$OBJDUMP" -d "$BUILD_DIR/firmware.elf" > "$BUILD_DIR/firmware.lst"
fi

echo "firmware 构建完成："
echo "  entry: $FIRMWARE_MAIN"
echo "  $BUILD_DIR/firmware.elf"
echo "  $BUILD_DIR/firmware.bin"
echo "  $BUILD_DIR/firmware.mem"
