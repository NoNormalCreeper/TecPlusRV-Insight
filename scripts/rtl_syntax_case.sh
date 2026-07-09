#!/usr/bin/env bash
# RTL 语法单 case 执行器。
# 这里保留旧 iverilog 配方本体，但改成按 case_id 分发，方便 test_runner 逐条编排。
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR="$REPO_ROOT/sim/build"
CASE_ID=${1:-}

need_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "缺少必需工具：$1" >&2
        exit 1
    fi
}

run_iverilog() {
    local top="$1"
    shift
    echo "语法检查：$top"
    iverilog -g2001 -s "$top" -o "$BUILD_DIR/$top.syntax.out" "$@"
}

run_iverilog_soc_include() {
    local top="$1"
    shift
    echo "语法检查：$top"
    iverilog -g2001 -I "$REPO_ROOT/rtl/soc" -s "$top" \
        -o "$BUILD_DIR/$top.syntax.out" "$@"
}

require_files() {
    local label="$1"
    shift
    local path
    local missing=0
    for path in "$@"; do
        if [ -f "$path" ]; then
            continue
        fi
        if [ "$missing" -eq 0 ]; then
            echo "语法检查失败：$label 缺少依赖文件" >&2
            missing=1
        fi
        echo "  - $path" >&2
    done
    if [ "$missing" -ne 0 ]; then
        exit 1
    fi
}

if [ -z "$CASE_ID" ]; then
    echo "用法：scripts/rtl_syntax_case.sh <case_id>" >&2
    exit 2
fi

need_tool iverilog
mkdir -p "$BUILD_DIR"

case "$CASE_ID" in
    probe_led_key_top)
        run_iverilog probe_led_key_top \
            "$REPO_ROOT/rtl/probe/probe_led_key_top.v"
        ;;
    probe_uart_top)
        run_iverilog probe_uart_top \
            "$REPO_ROOT/rtl/probe/probe_uart_top.v" \
            "$REPO_ROOT/rtl/periph/uart_tx.v"
        ;;
    uart_rx)
        run_iverilog uart_rx \
            "$REPO_ROOT/rtl/periph/uart_rx.v"
        ;;
    traffic_light_gpio)
        run_iverilog traffic_light_gpio \
            "$REPO_ROOT/rtl/periph/traffic_light_gpio.v"
        ;;
    sdram_smoke_ctrl)
        run_iverilog sdram_smoke_ctrl \
            "$REPO_ROOT/rtl/probe/sdram_smoke_ctrl.v"
        ;;
    sdram_data_ctrl)
        run_iverilog sdram_data_ctrl \
            "$REPO_ROOT/rtl/soc/sdram_data_ctrl.v"
        ;;
    probe_sdram_smoke_top)
        run_iverilog probe_sdram_smoke_top \
            "$REPO_ROOT/rtl/probe/probe_sdram_smoke_top.v" \
            "$REPO_ROOT/rtl/probe/sdram_smoke_ctrl.v"
        ;;
    sdram_tester_ctrl)
        run_iverilog sdram_tester_ctrl \
            "$REPO_ROOT/rtl/probe/sdram_tester_ctrl.v"
        ;;
    probe_sdram_tester_top)
        run_iverilog probe_sdram_tester_top \
            "$REPO_ROOT/rtl/probe/probe_sdram_tester_top.v" \
            "$REPO_ROOT/rtl/probe/sdram_tester_ctrl.v"
        ;;
    sdram_tester_uart_reporter)
        run_iverilog sdram_tester_uart_reporter \
            "$REPO_ROOT/rtl/probe/sdram_tester_uart_reporter.v"
        ;;
    probe_sdram_tester_uart_top)
        run_iverilog probe_sdram_tester_uart_top \
            "$REPO_ROOT/rtl/probe/probe_sdram_tester_uart_top.v" \
            "$REPO_ROOT/rtl/probe/sdram_tester_ctrl.v" \
            "$REPO_ROOT/rtl/probe/sdram_tester_uart_reporter.v" \
            "$REPO_ROOT/rtl/periph/uart_tx.v"
        ;;
    probe_bigboard_tl_top)
        run_iverilog probe_bigboard_tl_top \
            "$REPO_ROOT/rtl/probe/probe_bigboard_tl_top.v"
        ;;
    buzzer_tune_player)
        run_iverilog buzzer_tune_player \
            "$REPO_ROOT/rtl/probe/buzzer_tune_player.v"
        ;;
    buzzer_uart_reporter)
        run_iverilog buzzer_uart_reporter \
            "$REPO_ROOT/rtl/probe/buzzer_uart_reporter.v"
        ;;
    probe_buzzer_uart_top)
        run_iverilog probe_buzzer_uart_top \
            "$REPO_ROOT/rtl/probe/probe_buzzer_uart_top.v" \
            "$REPO_ROOT/rtl/probe/buzzer_tune_player.v" \
            "$REPO_ROOT/rtl/probe/buzzer_uart_reporter.v" \
            "$REPO_ROOT/rtl/periph/uart_tx.v"
        ;;
    vga_timing_640x480)
        run_iverilog vga_timing_640x480 \
            "$REPO_ROOT/rtl/periph/vga_timing_640x480.v"
        ;;
    vga_text_mode)
        run_iverilog vga_text_mode \
            "$REPO_ROOT/rtl/periph/vga_text_mode.v" \
            "$REPO_ROOT/rtl/periph/vga_timing_640x480.v"
        ;;
    probe_vga_top)
        run_iverilog probe_vga_top \
            "$REPO_ROOT/rtl/probe/probe_vga_top.v" \
            "$REPO_ROOT/rtl/periph/vga_timing_640x480.v"
        ;;
    probe_vga_text_top)
        run_iverilog probe_vga_text_top \
            "$REPO_ROOT/rtl/probe/probe_vga_text_top.v" \
            "$REPO_ROOT/rtl/periph/vga_text_mode.v" \
            "$REPO_ROOT/rtl/periph/vga_timing_640x480.v"
        ;;
    tinybus_decode)
        run_iverilog_soc_include tinybus_decode \
            "$REPO_ROOT/rtl/soc/tinybus_decode.v"
        ;;
    bram)
        run_iverilog bram \
            "$REPO_ROOT/rtl/soc/bram.v"
        ;;
    bram_dualport)
        run_iverilog bram_dualport \
            "$REPO_ROOT/rtl/soc/bram_dualport.v"
        ;;
    mmio_test_exit)
        run_iverilog mmio_test_exit \
            "$REPO_ROOT/rtl/soc/mmio_test_exit.v"
        ;;
    picorv32_adapter)
        require_files picorv32_adapter \
            "$REPO_ROOT/rtl/core/picorv32.v"
        echo "语法检查：picorv32_adapter"
        iverilog -g2001 -I "$REPO_ROOT/rtl/core" -s picorv32_adapter \
            -o "$BUILD_DIR/picorv32_adapter.syntax.out" \
            "$REPO_ROOT/rtl/soc/picorv32_adapter.v" \
            "$REPO_ROOT/rtl/core/picorv32.v"
        ;;
    darkriscv_adapter)
        require_files darkriscv_adapter \
            "$REPO_ROOT/rtl/core/darkriscv.v"
        echo "语法检查：darkriscv_adapter"
        iverilog -g2001 -I "$REPO_ROOT/rtl/core" -s darkriscv_adapter \
            -o "$BUILD_DIR/darkriscv_adapter.syntax.out" \
            "$REPO_ROOT/rtl/soc/darkriscv_adapter.v" \
            "$REPO_ROOT/rtl/core/darkriscv.v"
        ;;
    tecplus_cpu_wrapper)
        require_files tecplus_cpu_wrapper \
            "$REPO_ROOT/rtl/core/picorv32.v" \
            "$REPO_ROOT/rtl/core/darkriscv.v"
        echo "语法检查：tecplus_cpu_wrapper"
        iverilog -g2001 -I "$REPO_ROOT/rtl/core" -s tecplus_cpu_wrapper \
            -o "$BUILD_DIR/tecplus_cpu_wrapper.syntax.out" \
            "$REPO_ROOT/rtl/soc/tecplus_cpu_wrapper.v" \
            "$REPO_ROOT/rtl/soc/picorv32_adapter.v" \
            "$REPO_ROOT/rtl/soc/darkriscv_adapter.v" \
            "$REPO_ROOT/rtl/core/picorv32.v" \
            "$REPO_ROOT/rtl/core/darkriscv.v"
        ;;
    tecplus_minisoc_top)
        require_files tecplus_minisoc_top \
            "$REPO_ROOT/rtl/core/picorv32.v" \
            "$REPO_ROOT/rtl/core/darkriscv.v"
        echo "语法检查：tecplus_minisoc_top"
        iverilog -g2001 -I "$REPO_ROOT/rtl/soc" -I "$REPO_ROOT/rtl/core" \
            -s tecplus_minisoc_top \
            -o "$BUILD_DIR/tecplus_minisoc_top.syntax.out" \
            "$REPO_ROOT/rtl/soc/tecplus_minisoc_top.v" \
            "$REPO_ROOT/rtl/soc/tecplus_cpu_wrapper.v" \
            "$REPO_ROOT/rtl/soc/picorv32_adapter.v" \
            "$REPO_ROOT/rtl/soc/darkriscv_adapter.v" \
            "$REPO_ROOT/rtl/core/picorv32.v" \
            "$REPO_ROOT/rtl/core/darkriscv.v" \
            "$REPO_ROOT/rtl/soc/bram_dualport.v" \
            "$REPO_ROOT/rtl/soc/tinybus_decode.v" \
            "$REPO_ROOT/rtl/soc/mmio_test_exit.v" \
            "$REPO_ROOT/rtl/periph/uart_tx.v" \
            "$REPO_ROOT/rtl/periph/uart_rx.v" \
            "$REPO_ROOT/rtl/periph/traffic_light_gpio.v"
        ;;
    *)
        echo "未知 RTL syntax case: $CASE_ID" >&2
        exit 2
        ;;
esac
