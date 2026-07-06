#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR="$REPO_ROOT/sim/build"
SIM_KIND=${1:-uart_tx}

need_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "缺少必需工具：$1" >&2
        exit 1
    fi
}

need_tool iverilog
need_tool vvp

mkdir -p "$BUILD_DIR"

case "$SIM_KIND" in
    uart_tx)
        iverilog -g2001 -o "$BUILD_DIR/tb_uart_tx.out" \
            "$REPO_ROOT/sim/tb_uart_tx.v" \
            "$REPO_ROOT/rtl/periph/uart_tx.v"
        vvp "$BUILD_DIR/tb_uart_tx.out"
        ;;
    minisoc)
        if [ -f "$REPO_ROOT/rtl/core/picorv32.v" ]; then
            iverilog -g2001 -DPICORV32_PRESENT -o "$BUILD_DIR/tb_minisoc.out" \
                "$REPO_ROOT/sim/tb_minisoc.v" \
                "$REPO_ROOT/rtl/core/picorv32.v"
        else
            iverilog -g2001 -o "$BUILD_DIR/tb_minisoc.out" \
                "$REPO_ROOT/sim/tb_minisoc.v"
        fi
        vvp "$BUILD_DIR/tb_minisoc.out"
        ;;
    *)
        echo "未知仿真目标：$SIM_KIND" >&2
        echo "支持的目标：uart_tx、minisoc" >&2
        exit 1
        ;;
esac
