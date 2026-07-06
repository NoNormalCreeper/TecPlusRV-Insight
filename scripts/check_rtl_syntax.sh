#!/usr/bin/env bash
# RTL 语法 smoke 检查。
# 这里用 iverilog 编译每个关键模块，目标是尽早发现拼写、端口和 Verilog-2001 语法错误。
# 它不是综合检查，也不能替代 ISE timing/implementation。
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR="$REPO_ROOT/sim/build"

need_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "缺少必需工具：$1" >&2
        exit 1
    fi
}

need_tool iverilog
mkdir -p "$BUILD_DIR"

# 每个 -s 都指定一个顶层，避免因为同名/未实例化模块导致检查范围不清楚。
echo "语法检查：probe_led_key_top"
iverilog -g2001 -s probe_led_key_top -o "$BUILD_DIR/probe_led_key_top.syntax.out" \
    "$REPO_ROOT/rtl/probe/probe_led_key_top.v"

echo "语法检查：probe_uart_top"
iverilog -g2001 -s probe_uart_top -o "$BUILD_DIR/probe_uart_top.syntax.out" \
    "$REPO_ROOT/rtl/probe/probe_uart_top.v" \
    "$REPO_ROOT/rtl/periph/uart_tx.v"

echo "语法检查：sdram_smoke_ctrl"
iverilog -g2001 -s sdram_smoke_ctrl -o "$BUILD_DIR/sdram_smoke_ctrl.syntax.out" \
    "$REPO_ROOT/rtl/probe/sdram_smoke_ctrl.v"

echo "语法检查：probe_sdram_smoke_top"
iverilog -g2001 -s probe_sdram_smoke_top -o "$BUILD_DIR/probe_sdram_smoke_top.syntax.out" \
    "$REPO_ROOT/rtl/probe/probe_sdram_smoke_top.v" \
    "$REPO_ROOT/rtl/probe/sdram_smoke_ctrl.v"

echo "语法检查：probe_bigboard_tl_top"
iverilog -g2001 -s probe_bigboard_tl_top -o "$BUILD_DIR/probe_bigboard_tl_top.syntax.out" \
    "$REPO_ROOT/rtl/probe/probe_bigboard_tl_top.v"

echo "语法检查：tinybus_decode"
iverilog -g2001 -I "$REPO_ROOT/rtl/soc" -s tinybus_decode \
    -o "$BUILD_DIR/tinybus_decode.syntax.out" \
    "$REPO_ROOT/rtl/soc/tinybus_decode.v"

echo "语法检查：bram"
iverilog -g2001 -s bram -o "$BUILD_DIR/bram.syntax.out" \
    "$REPO_ROOT/rtl/soc/bram.v"

echo "语法检查：mmio_test_exit"
iverilog -g2001 -s mmio_test_exit -o "$BUILD_DIR/mmio_test_exit.syntax.out" \
    "$REPO_ROOT/rtl/soc/mmio_test_exit.v"

echo "RTL syntax smoke checks passed"
