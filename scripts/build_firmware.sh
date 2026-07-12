#!/usr/bin/env bash
# firmware 构建脚本。
# 默认生成 firmware/build/firmware.{elf,bin,mem,lst}；其中 .mem 供 Verilog $readmemh 使用。
# FIRMWARE_OUT 是不带扩展名的输出前缀，可同时指定目录和文件名。
# 可通过环境变量覆盖 CC/OBJCOPY/OBJDUMP/PYTHON，方便不同机器调工具链。
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
CC=${CC:-riscv64-unknown-elf-gcc}
OBJCOPY=${OBJCOPY:-riscv64-unknown-elf-objcopy}
OBJDUMP=${OBJDUMP:-riscv64-unknown-elf-objdump}
SIZE=${SIZE:-riscv64-unknown-elf-size}
PYTHON=${PYTHON:-python3}
FIRMWARE_MAIN=${FIRMWARE_MAIN:-$REPO_ROOT/firmware/main.c}
FIRMWARE_OUT=${FIRMWARE_OUT:-$REPO_ROOT/firmware/build/firmware}
FIRMWARE_PROFILE=${FIRMWARE_PROFILE:-baremetal}

case "$FIRMWARE_OUT" in
    */) echo "FIRMWARE_OUT 必须是文件前缀，不能以 / 结尾：$FIRMWARE_OUT" >&2; exit 1 ;;
    /*) ;;
    *) FIRMWARE_OUT="$REPO_ROOT/$FIRMWARE_OUT" ;;
esac

OUTPUT_DIR=$(dirname "$FIRMWARE_OUT")

need_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "缺少必需工具：$1" >&2
        exit 1
    fi
}

need_tool "$CC"
need_tool "$OBJCOPY"
need_tool "$SIZE"
need_tool "$PYTHON"

if [ ! -f "$FIRMWARE_MAIN" ]; then
    echo "找不到 firmware 入口文件：$FIRMWARE_MAIN" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
rm -f "$FIRMWARE_OUT.elf" "$FIRMWARE_OUT.bin" "$FIRMWARE_OUT.mem" "$FIRMWARE_OUT.lst"
TMP_DIR=$(mktemp -d "$OUTPUT_DIR/.firmware-build.XXXXXX")
TMP_OUT="$TMP_DIR/firmware"

cleanup() {
    rm -rf "$TMP_DIR"
}

trap cleanup EXIT

# rv32i/ilp32 对齐 PicoRV32 最小配置；freestanding 表示不依赖标准 C runtime。
# -fno-tree-loop-distribute-patterns：禁止编译器把 rt_memcpy/rt_memset 里的
# 逐字节循环“优化”成对 memcpy/memset 的库调用——我们 -nostdlib，没有这些符号，
# 否则会在链接期报 undefined reference to `memcpy`/`memset`。
MARCH=rv32i
PROFILE_SOURCES=""
EXTRA_CFLAGS=""
EXTRA_INCLUDES=""
EXTRA_LDFLAGS=""

select_zicsr_march() {
    # 新工具链要求显式声明 Zicsr；旧 GCC 10 只接受 rv32i，
    # 但其 assembler 仍能正确接受 CSR 指令。
    if "$CC" -march=rv32i_zicsr -mabi=ilp32 \
        -E -x c /dev/null -o /dev/null >/dev/null 2>&1; then
        MARCH=rv32i_zicsr
    fi
}

case "$FIRMWARE_PROFILE" in
    baremetal)
        ;;
    dark_irq)
        select_zicsr_march
        PROFILE_SOURCES="
$REPO_ROOT/firmware/runtime/trap_entry.S
$REPO_ROOT/firmware/runtime/trap.c
$REPO_ROOT/firmware/drivers/machine_timer.c
"
        ;;
    gdb_stub)
        select_zicsr_march
        EXTRA_CFLAGS="-g3 -DGDB_STUB_ACTIVE=1"
        PROFILE_SOURCES="
$REPO_ROOT/firmware/runtime/trap_entry.S
$REPO_ROOT/firmware/runtime/trap.c
$REPO_ROOT/firmware/gdb/gdb_packet.c
$REPO_ROOT/firmware/gdb/gdb_stub.c
"
        ;;
    freertos)
        FREERTOS_KERNEL="$REPO_ROOT/third_party/FreeRTOS-Kernel"
        FREERTOS_CPU_CLOCK_HZ=${FREERTOS_CPU_CLOCK_HZ:-50000000}
        if [ ! -f "$FREERTOS_KERNEL/tasks.c" ]; then
            echo "缺少 FreeRTOS-Kernel；请运行 git submodule update --init --recursive" >&2
            exit 1
        fi
        select_zicsr_march
        EXTRA_CFLAGS="-ffunction-sections -fdata-sections -DFREERTOS_CPU_CLOCK_HZ=$FREERTOS_CPU_CLOCK_HZ"
        EXTRA_INCLUDES="-I$REPO_ROOT/firmware/freertos/compat -I$REPO_ROOT/firmware/freertos -I$FREERTOS_KERNEL/include"
        EXTRA_LDFLAGS="-Wl,--gc-sections"
        PROFILE_SOURCES="
$FREERTOS_KERNEL/tasks.c
$FREERTOS_KERNEL/queue.c
$FREERTOS_KERNEL/list.c
$FREERTOS_KERNEL/timers.c
$FREERTOS_KERNEL/event_groups.c
$FREERTOS_KERNEL/portable/MemMang/heap_5.c
$REPO_ROOT/firmware/runtime/trap_entry.S
$REPO_ROOT/firmware/runtime/trap.c
$REPO_ROOT/firmware/drivers/machine_timer.c
$REPO_ROOT/firmware/freertos/port.c
$REPO_ROOT/firmware/freertos/freertos_heap.c
$REPO_ROOT/firmware/freertos/freertos_hooks.c
"
        ;;
    *)
        echo "未知 FIRMWARE_PROFILE：$FIRMWARE_PROFILE" >&2
        exit 1
        ;;
esac

CFLAGS="-march=$MARCH -mabi=ilp32 -ffreestanding -nostdlib -nostartfiles -fno-tree-loop-distribute-patterns -Wall -Wextra -Werror -Os $EXTRA_CFLAGS"
INCLUDES="-I$REPO_ROOT/firmware $EXTRA_INCLUDES"
LDFLAGS="-T $REPO_ROOT/firmware/linker.ld $EXTRA_LDFLAGS"
SOURCES="
$REPO_ROOT/firmware/startup.S
$REPO_ROOT/firmware/drivers/uart.c
$REPO_ROOT/firmware/drivers/gpio.c
$REPO_ROOT/firmware/drivers/traffic_light.c
$REPO_ROOT/firmware/drivers/buzzer.c
$REPO_ROOT/firmware/drivers/vga.c
$REPO_ROOT/firmware/runtime/rt_string.c
$REPO_ROOT/firmware/runtime/rt_print.c
$REPO_ROOT/firmware/runtime/rt_alloc.c
$PROFILE_SOURCES
$FIRMWARE_MAIN
$REPO_ROOT/firmware/drivers/perf.c
$REPO_ROOT/firmware/tests/selftest.c
"

# 不单独生成 .o，保持脚本最薄；后续文件多了再引入 Makefile/CMake。
# -lgcc 提供 rv32i 缺失的软件运算例程（如 __udivsi3/__umodsi3 软件除法），
# firmware 里的十进制打印和 CPI 计算用到了除法/取模，必须链接它。
# 放在源文件之后，保证链接器能解析到这些符号。
"$CC" $CFLAGS $INCLUDES $LDFLAGS -o "$TMP_OUT.elf" $SOURCES -lgcc
"$SIZE" -A "$TMP_OUT.elf" > "$TMP_DIR/size.txt"
bram_used=$(awk '$1 ~ /^\.(text|data|bss|data_load)$/ {sum += $2} END {print sum + 0}' \
    "$TMP_DIR/size.txt")
echo "BRAM sections: ${bram_used} bytes"
awk '$1 ~ /^\.(text|data|bss|data_load|sdram_data|sdram_bss|heap)$/ {printf "  %-12s %8s bytes @ %s\n", $1, $2, $3}' \
    "$TMP_DIR/size.txt"
if [ "$bram_used" -ge 65536 ]; then
    echo "firmware BRAM section 超过 64 KiB hard limit：${bram_used} bytes" >&2
    exit 1
fi
if [ "$bram_used" -ge 49152 ]; then
    echo "WARNING: firmware BRAM section 超过 48 KiB soft budget：${bram_used} bytes" >&2
fi
"$OBJCOPY" -O binary "$TMP_OUT.elf" "$TMP_OUT.bin"
bin_bytes=$(wc -c < "$TMP_OUT.bin")
if [ "$bin_bytes" -ge 65536 ]; then
    echo "firmware BRAM image 超过 64 KiB hard limit：${bin_bytes} bytes" >&2
    exit 1
fi
"$PYTHON" "$REPO_ROOT/scripts/bin2mem.py" "$TMP_OUT.bin" "$TMP_OUT.mem" 16384

if command -v "$OBJDUMP" >/dev/null 2>&1; then
    # 反汇编不是仿真必需，但调启动代码和 memory map 时很有用。
    "$OBJDUMP" -d "$TMP_OUT.elf" > "$TMP_OUT.lst"
fi

mv "$TMP_OUT.elf" "$FIRMWARE_OUT.elf"
mv "$TMP_OUT.bin" "$FIRMWARE_OUT.bin"
mv "$TMP_OUT.mem" "$FIRMWARE_OUT.mem"
if [ -f "$TMP_OUT.lst" ]; then
    mv "$TMP_OUT.lst" "$FIRMWARE_OUT.lst"
fi

echo "firmware 构建完成："
echo "  entry: $FIRMWARE_MAIN"
echo "  output: $FIRMWARE_OUT"
echo "  $FIRMWARE_OUT.elf"
echo "  $FIRMWARE_OUT.bin"
echo "  $FIRMWARE_OUT.mem"
echo "  BRAM image: ${bin_bytes} bytes"
