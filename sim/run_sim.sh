#!/usr/bin/env bash
# 本地仿真统一入口。
# 用法：sim/run_sim.sh <目标名>；不传参数时默认跑 uart_tx。
# 每个目标都会编译到 sim/build，再用 vvp 运行并检查 FAIL/TIMEOUT。
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

run_and_check() {
    local out_file="$1"
    shift

    "$@" >"$out_file" 2>&1
    cat "$out_file"

    # testbench 统一用 "FAIL:" / "TIMEOUT:" 标记失败，脚本只解析这两个关键词。
    if grep -Eq '(^|[[:space:]])(FAIL|TIMEOUT):' "$out_file"; then
        return 1
    fi
}

compile_minisoc_tb() {
    local arg_count=$#
    local out_file="$1"
    local cpu_impl="$2"
    local tb_module="$3"
    local tb_file="$4"
    local require_uart_write="${5:-}"
    local require_led_write="${6:-}"
    local require_exit_write="${7:-}"
    local expect_uart_fire_count="${8:-}"
    local expect_exit_code="${9:-}"
    local expect_led="${10:-}"
    local drive_uart_rx="${11:-}"
    local uart_rx_byte="${12:-}"
    local expect_uart_last_byte="${13:-}"
    local require_traffic_write="${14:-}"
    local expect_traffic="${15:-}"
    local extra_params=()

    if [ ! -f "$REPO_ROOT/rtl/core/picorv32.v" ]; then
        echo "缺少 rtl/core/picorv32.v，无法运行 MiniSoC 板级 top 仿真" >&2
        exit 1
    fi

    if [ ! -f "$REPO_ROOT/rtl/core/darkriscv.v" ]; then
        echo "缺少 rtl/core/darkriscv.v，无法运行 DarkRISCV MiniSoC 仿真" >&2
        exit 1
    fi

    if [ "$arg_count" -ge 7 ]; then
        extra_params=(
            -P "$tb_module.REQUIRE_UART_WRITE=$require_uart_write"
            -P "$tb_module.REQUIRE_LED_WRITE=$require_led_write"
            -P "$tb_module.REQUIRE_EXIT_WRITE=$require_exit_write"
        )
    fi

    if [ "$arg_count" -ge 8 ]; then
        extra_params+=(
            -P "$tb_module.EXPECT_UART_FIRE_COUNT=$expect_uart_fire_count"
        )
    fi

    if [ "$arg_count" -ge 9 ]; then
        extra_params+=(
            -P "$tb_module.EXPECT_EXIT_CODE=$expect_exit_code"
        )
    fi

    if [ "$arg_count" -ge 10 ]; then
        extra_params+=(
            -P "$tb_module.EXPECT_LED=$expect_led"
        )
    fi

    if [ "$arg_count" -ge 13 ]; then
        extra_params+=(
            -P "$tb_module.DRIVE_UART_RX=$drive_uart_rx"
            -P "$tb_module.UART_RX_BYTE=$uart_rx_byte"
            -P "$tb_module.EXPECT_UART_LAST_BYTE=$expect_uart_last_byte"
        )
    fi

    if [ "$arg_count" -ge 15 ]; then
        extra_params+=(
            -P "$tb_module.REQUIRE_TRAFFIC_WRITE=$require_traffic_write"
            -P "$tb_module.EXPECT_TRAFFIC=$expect_traffic"
        )
    fi

    iverilog -g2001 -I "$REPO_ROOT/rtl/soc" -I "$REPO_ROOT/rtl/core" \
        -P "$tb_module.CPU_IMPL=$cpu_impl" \
        "${extra_params[@]}" \
        -o "$out_file" \
        "$tb_file" \
        "$REPO_ROOT/rtl/core/picorv32.v" \
        "$REPO_ROOT/rtl/core/darkriscv.v" \
        "$REPO_ROOT/rtl/soc/tecplus_minisoc_top.v" \
        "$REPO_ROOT/rtl/soc/tecplus_cpu_wrapper.v" \
        "$REPO_ROOT/rtl/soc/picorv32_adapter.v" \
        "$REPO_ROOT/rtl/soc/darkriscv_adapter.v" \
        "$REPO_ROOT/rtl/soc/bram_dualport.v" \
        "$REPO_ROOT/rtl/soc/tinybus_decode.v" \
        "$REPO_ROOT/rtl/soc/mmio_test_exit.v" \
        "$REPO_ROOT/rtl/periph/uart_tx.v" \
        "$REPO_ROOT/rtl/periph/uart_rx.v" \
        "$REPO_ROOT/rtl/periph/traffic_light_gpio.v"
}

compile_minisoc_perf_tb() {
    local out_file="$1"
    local cpu_impl="$2"
    local tb_module="$3"
    local tb_file="$4"
    local result_cycle_addr="${PERF_RESULT_CYCLE_ADDR:-}"
    local result_instret_addr="${PERF_RESULT_INSTRET_ADDR:-}"

    if [ -z "$result_cycle_addr" ] || [ -z "$result_instret_addr" ]; then
        echo "缺少 PERF_RESULT_CYCLE_ADDR / PERF_RESULT_INSTRET_ADDR；请先提供 firmware 中 perf 结果符号地址，或直接运行 scripts/compare_cpu_perf.sh" >&2
        exit 1
    fi

    if [ ! -f "$REPO_ROOT/rtl/core/picorv32.v" ]; then
        echo "缺少 rtl/core/picorv32.v，无法运行 MiniSoC 板级 top 仿真" >&2
        exit 1
    fi

    if [ ! -f "$REPO_ROOT/rtl/core/darkriscv.v" ]; then
        echo "缺少 rtl/core/darkriscv.v，无法运行 DarkRISCV MiniSoC 仿真" >&2
        exit 1
    fi

    iverilog -g2001 -I "$REPO_ROOT/rtl/soc" -I "$REPO_ROOT/rtl/core" \
        -P "$tb_module.CPU_IMPL=$cpu_impl" \
        -P "$tb_module.RESULT_CYCLE_ADDR=$result_cycle_addr" \
        -P "$tb_module.RESULT_INSTRET_ADDR=$result_instret_addr" \
        -o "$out_file" \
        "$tb_file" \
        "$REPO_ROOT/rtl/core/picorv32.v" \
        "$REPO_ROOT/rtl/core/darkriscv.v" \
        "$REPO_ROOT/rtl/soc/tecplus_minisoc_top.v" \
        "$REPO_ROOT/rtl/soc/tecplus_cpu_wrapper.v" \
        "$REPO_ROOT/rtl/soc/picorv32_adapter.v" \
        "$REPO_ROOT/rtl/soc/darkriscv_adapter.v" \
        "$REPO_ROOT/rtl/soc/bram_dualport.v" \
        "$REPO_ROOT/rtl/soc/tinybus_decode.v" \
        "$REPO_ROOT/rtl/soc/mmio_test_exit.v" \
        "$REPO_ROOT/rtl/periph/uart_tx.v" \
        "$REPO_ROOT/rtl/periph/uart_rx.v" \
        "$REPO_ROOT/rtl/periph/traffic_light_gpio.v"
}

case "$SIM_KIND" in
    uart_tx)
        iverilog -g2001 -o "$BUILD_DIR/tb_uart_tx.out" \
            "$REPO_ROOT/sim/tb_uart_tx.v" \
            "$REPO_ROOT/rtl/periph/uart_tx.v"
        run_and_check "$BUILD_DIR/tb_uart_tx.log" vvp "$BUILD_DIR/tb_uart_tx.out"
        ;;
    uart_rx)
        iverilog -g2001 -o "$BUILD_DIR/tb_uart_rx.out" \
            "$REPO_ROOT/sim/tb_uart_rx.v" \
            "$REPO_ROOT/rtl/periph/uart_rx.v"
        run_and_check "$BUILD_DIR/tb_uart_rx.log" vvp "$BUILD_DIR/tb_uart_rx.out"
        ;;
    traffic_light_gpio)
        iverilog -g2001 -o "$BUILD_DIR/tb_traffic_light_gpio.out" \
            "$REPO_ROOT/sim/tb_traffic_light_gpio.v" \
            "$REPO_ROOT/rtl/periph/traffic_light_gpio.v"
        run_and_check "$BUILD_DIR/tb_traffic_light_gpio.log" vvp "$BUILD_DIR/tb_traffic_light_gpio.out"
        ;;
    probe_led_key)
        iverilog -g2001 -o "$BUILD_DIR/tb_probe_led_key_top.out" \
            "$REPO_ROOT/sim/tb_probe_led_key_top.v" \
            "$REPO_ROOT/rtl/probe/probe_led_key_top.v"
        run_and_check "$BUILD_DIR/tb_probe_led_key_top.log" vvp "$BUILD_DIR/tb_probe_led_key_top.out"
        ;;
    probe_uart_top)
        iverilog -g2001 -o "$BUILD_DIR/tb_probe_uart_top.out" \
            "$REPO_ROOT/sim/tb_probe_uart_top.v" \
            "$REPO_ROOT/rtl/probe/probe_uart_top.v" \
            "$REPO_ROOT/rtl/periph/uart_tx.v"
        run_and_check "$BUILD_DIR/tb_probe_uart_top.log" vvp "$BUILD_DIR/tb_probe_uart_top.out"
        ;;
    bram)
        iverilog -g2001 -o "$BUILD_DIR/tb_bram.out" \
            "$REPO_ROOT/sim/tb_bram.v" \
            "$REPO_ROOT/rtl/soc/bram.v"
        run_and_check "$BUILD_DIR/tb_bram.log" vvp "$BUILD_DIR/tb_bram.out"
        ;;
    bram_dualport)
        iverilog -g2001 -o "$BUILD_DIR/tb_bram_dualport.out" \
            "$REPO_ROOT/sim/tb_bram_dualport.v" \
            "$REPO_ROOT/rtl/soc/bram_dualport.v"
        run_and_check "$BUILD_DIR/tb_bram_dualport.log" vvp "$BUILD_DIR/tb_bram_dualport.out"
        ;;
    tinybus_decode)
        iverilog -g2001 -I "$REPO_ROOT/rtl/soc" -o "$BUILD_DIR/tb_tinybus_decode.out" \
            "$REPO_ROOT/sim/tb_tinybus_decode.v" \
            "$REPO_ROOT/rtl/soc/tinybus_decode.v"
        run_and_check "$BUILD_DIR/tb_tinybus_decode.log" vvp "$BUILD_DIR/tb_tinybus_decode.out"
        ;;
    mmio_test_exit)
        iverilog -g2001 -o "$BUILD_DIR/tb_mmio_test_exit.out" \
            "$REPO_ROOT/sim/tb_mmio_test_exit.v" \
            "$REPO_ROOT/rtl/soc/mmio_test_exit.v"
        run_and_check "$BUILD_DIR/tb_mmio_test_exit.log" vvp "$BUILD_DIR/tb_mmio_test_exit.out"
        ;;
    minisoc)
        compile_minisoc_tb "$BUILD_DIR/tb_minisoc.out" 0 tb_minisoc "$REPO_ROOT/sim/tb_minisoc.v" 1 1 1
        run_and_check "$BUILD_DIR/tb_minisoc.log" vvp "$BUILD_DIR/tb_minisoc.out"
        ;;
    minisoc_pico)
        compile_minisoc_tb "$BUILD_DIR/tb_minisoc_pico.out" 0 tb_minisoc "$REPO_ROOT/sim/tb_minisoc.v"
        run_and_check "$BUILD_DIR/tb_minisoc_pico.log" vvp "$BUILD_DIR/tb_minisoc_pico.out"
        ;;
    minisoc_dark)
        compile_minisoc_tb "$BUILD_DIR/tb_minisoc_dark.out" 1 tb_minisoc "$REPO_ROOT/sim/tb_minisoc.v"
        run_and_check "$BUILD_DIR/tb_minisoc_dark.log" vvp "$BUILD_DIR/tb_minisoc_dark.out"
        ;;
    minisoc_smoke_pico)
        compile_minisoc_tb "$BUILD_DIR/tb_minisoc_smoke_pico.out" 0 tb_minisoc "$REPO_ROOT/sim/tb_minisoc.v" 1 1 1
        run_and_check "$BUILD_DIR/tb_minisoc_smoke_pico.log" vvp "$BUILD_DIR/tb_minisoc_smoke_pico.out"
        ;;
    minisoc_smoke_dark)
        compile_minisoc_tb "$BUILD_DIR/tb_minisoc_smoke_dark.out" 1 tb_minisoc "$REPO_ROOT/sim/tb_minisoc.v" 1 1 1
        run_and_check "$BUILD_DIR/tb_minisoc_smoke_dark.log" vvp "$BUILD_DIR/tb_minisoc_smoke_dark.out"
        ;;
    minisoc_uart_once_pico)
        compile_minisoc_tb "$BUILD_DIR/tb_minisoc_uart_once_pico.out" 0 tb_minisoc "$REPO_ROOT/sim/tb_minisoc.v" 1 0 1 1
        run_and_check "$BUILD_DIR/tb_minisoc_uart_once_pico.log" vvp "$BUILD_DIR/tb_minisoc_uart_once_pico.out"
        ;;
    minisoc_uart_once_dark)
        compile_minisoc_tb "$BUILD_DIR/tb_minisoc_uart_once_dark.out" 1 tb_minisoc "$REPO_ROOT/sim/tb_minisoc.v" 1 0 1 1
        run_and_check "$BUILD_DIR/tb_minisoc_uart_once_dark.log" vvp "$BUILD_DIR/tb_minisoc_uart_once_dark.out"
        ;;
    minisoc_uart_echo_pico)
        compile_minisoc_tb "$BUILD_DIR/tb_minisoc_uart_echo_pico.out" 0 tb_minisoc "$REPO_ROOT/sim/tb_minisoc.v" 1 1 1 1 1 5 1 90 90
        run_and_check "$BUILD_DIR/tb_minisoc_uart_echo_pico.log" vvp "$BUILD_DIR/tb_minisoc_uart_echo_pico.out"
        ;;
    minisoc_uart_echo_dark)
        compile_minisoc_tb "$BUILD_DIR/tb_minisoc_uart_echo_dark.out" 1 tb_minisoc "$REPO_ROOT/sim/tb_minisoc.v" 1 1 1 1 1 5 1 90 90
        run_and_check "$BUILD_DIR/tb_minisoc_uart_echo_dark.log" vvp "$BUILD_DIR/tb_minisoc_uart_echo_dark.out"
        ;;
    minisoc_traffic_pico)
        compile_minisoc_tb "$BUILD_DIR/tb_minisoc_traffic_pico.out" 0 tb_minisoc "$REPO_ROOT/sim/tb_minisoc.v" 0 1 1 -1 1 5 0 0 -1 1 2645
        run_and_check "$BUILD_DIR/tb_minisoc_traffic_pico.log" vvp "$BUILD_DIR/tb_minisoc_traffic_pico.out"
        ;;
    minisoc_traffic_dark)
        compile_minisoc_tb "$BUILD_DIR/tb_minisoc_traffic_dark.out" 1 tb_minisoc "$REPO_ROOT/sim/tb_minisoc.v" 0 1 1 -1 1 5 0 0 -1 1 2645
        run_and_check "$BUILD_DIR/tb_minisoc_traffic_dark.log" vvp "$BUILD_DIR/tb_minisoc_traffic_dark.out"
        ;;
    minisoc_perf_pico)
        compile_minisoc_perf_tb "$BUILD_DIR/tb_minisoc_perf_pico.out" 0 tb_minisoc_perf "$REPO_ROOT/sim/tb_minisoc_perf.v"
        run_and_check "$BUILD_DIR/tb_minisoc_perf_pico.log" vvp "$BUILD_DIR/tb_minisoc_perf_pico.out"
        ;;
    minisoc_perf_dark)
        compile_minisoc_perf_tb "$BUILD_DIR/tb_minisoc_perf_dark.out" 1 tb_minisoc_perf "$REPO_ROOT/sim/tb_minisoc_perf.v"
        run_and_check "$BUILD_DIR/tb_minisoc_perf_dark.log" vvp "$BUILD_DIR/tb_minisoc_perf_dark.out"
        ;;
    minisoc_counter_source_pico)
        compile_minisoc_tb "$BUILD_DIR/tb_minisoc_counter_source_pico.out" 0 tb_minisoc_counter_source "$REPO_ROOT/sim/tb_minisoc_counter_source.v"
        run_and_check "$BUILD_DIR/tb_minisoc_counter_source_pico.log" vvp "$BUILD_DIR/tb_minisoc_counter_source_pico.out"
        ;;
    minisoc_counter_source_dark)
        compile_minisoc_tb "$BUILD_DIR/tb_minisoc_counter_source_dark.out" 1 tb_minisoc_counter_source "$REPO_ROOT/sim/tb_minisoc_counter_source.v"
        run_and_check "$BUILD_DIR/tb_minisoc_counter_source_dark.log" vvp "$BUILD_DIR/tb_minisoc_counter_source_dark.out"
        ;;
    minisoc_counter_reset_pico)
        compile_minisoc_tb "$BUILD_DIR/tb_minisoc_counter_reset_pico.out" 0 tb_minisoc_counter_reset "$REPO_ROOT/sim/tb_minisoc_counter_reset.v"
        run_and_check "$BUILD_DIR/tb_minisoc_counter_reset_pico.log" vvp "$BUILD_DIR/tb_minisoc_counter_reset_pico.out"
        ;;
    minisoc_counter_reset_dark)
        compile_minisoc_tb "$BUILD_DIR/tb_minisoc_counter_reset_dark.out" 1 tb_minisoc_counter_reset "$REPO_ROOT/sim/tb_minisoc_counter_reset.v"
        run_and_check "$BUILD_DIR/tb_minisoc_counter_reset_dark.log" vvp "$BUILD_DIR/tb_minisoc_counter_reset_dark.out"
        ;;
    minisoc_rvtest_pico)
        compile_minisoc_tb "$BUILD_DIR/tb_minisoc_rvtest_pico.out" 0 tb_minisoc "$REPO_ROOT/sim/tb_minisoc.v" 0 0 0 -1 1 0
        run_and_check "$BUILD_DIR/tb_minisoc_rvtest_pico.log" vvp "$BUILD_DIR/tb_minisoc_rvtest_pico.out"
        ;;
    minisoc_rvtest_dark)
        compile_minisoc_tb "$BUILD_DIR/tb_minisoc_rvtest_dark.out" 1 tb_minisoc "$REPO_ROOT/sim/tb_minisoc.v" 0 0 0 -1 1 0
        run_and_check "$BUILD_DIR/tb_minisoc_rvtest_dark.log" vvp "$BUILD_DIR/tb_minisoc_rvtest_dark.out"
        ;;
    board_demo_pico)
        compile_minisoc_tb "$BUILD_DIR/tb_board_demo_pico.out" 0 tb_board_demo "$REPO_ROOT/sim/tb_board_demo.v"
        run_and_check "$BUILD_DIR/tb_board_demo_pico.log" vvp "$BUILD_DIR/tb_board_demo_pico.out"
        ;;
    board_demo_dark)
        compile_minisoc_tb "$BUILD_DIR/tb_board_demo_dark.out" 1 tb_board_demo "$REPO_ROOT/sim/tb_board_demo.v"
        run_and_check "$BUILD_DIR/tb_board_demo_dark.log" vvp "$BUILD_DIR/tb_board_demo_dark.out"
        ;;
    sdram_smoke)
        iverilog -g2001 -o "$BUILD_DIR/tb_sdram_smoke_ctrl.out" \
            "$REPO_ROOT/sim/tb_sdram_smoke_ctrl.v" \
            "$REPO_ROOT/rtl/probe/sdram_smoke_ctrl.v"
        run_and_check "$BUILD_DIR/tb_sdram_smoke_ctrl.log" vvp "$BUILD_DIR/tb_sdram_smoke_ctrl.out"
        ;;
    sdram_data_ctrl)
        iverilog -g2001 -o "$BUILD_DIR/tb_sdram_data_ctrl.out" \
            "$REPO_ROOT/sim/tb_sdram_data_ctrl.v" \
            "$REPO_ROOT/rtl/soc/sdram_data_ctrl.v"
        run_and_check "$BUILD_DIR/tb_sdram_data_ctrl.log" vvp "$BUILD_DIR/tb_sdram_data_ctrl.out"
        ;;
    sdram_tester)
        iverilog -g2001 -o "$BUILD_DIR/tb_sdram_tester_ctrl.out" \
            "$REPO_ROOT/sim/tb_sdram_tester_ctrl.v" \
            "$REPO_ROOT/rtl/probe/sdram_tester_ctrl.v"
        run_and_check "$BUILD_DIR/tb_sdram_tester_ctrl.log" vvp "$BUILD_DIR/tb_sdram_tester_ctrl.out"
        ;;
    sdram_tester_fail)
        iverilog -g2001 -o "$BUILD_DIR/tb_sdram_tester_fail.out" \
            "$REPO_ROOT/sim/tb_sdram_tester_fail.v" \
            "$REPO_ROOT/rtl/probe/sdram_tester_ctrl.v"
        run_and_check "$BUILD_DIR/tb_sdram_tester_fail.log" vvp "$BUILD_DIR/tb_sdram_tester_fail.out"
        ;;
    sdram_tester_reset)
        iverilog -g2001 -o "$BUILD_DIR/tb_sdram_tester_reset.out" \
            "$REPO_ROOT/sim/tb_sdram_tester_reset.v" \
            "$REPO_ROOT/rtl/probe/sdram_tester_ctrl.v"
        run_and_check "$BUILD_DIR/tb_sdram_tester_reset.log" vvp "$BUILD_DIR/tb_sdram_tester_reset.out"
        ;;
    sdram_tester_uart_reporter)
        iverilog -g2001 -o "$BUILD_DIR/tb_sdram_tester_uart_reporter.out" \
            "$REPO_ROOT/sim/tb_sdram_tester_uart_reporter.v" \
            "$REPO_ROOT/rtl/probe/sdram_tester_uart_reporter.v"
        run_and_check "$BUILD_DIR/tb_sdram_tester_uart_reporter.log" vvp "$BUILD_DIR/tb_sdram_tester_uart_reporter.out"
        ;;
    bigboard_tl)
        iverilog -g2001 -o "$BUILD_DIR/tb_bigboard_tl.out" \
            "$REPO_ROOT/sim/tb_bigboard_tl.v" \
            "$REPO_ROOT/rtl/probe/probe_bigboard_tl_top.v"
        run_and_check "$BUILD_DIR/tb_bigboard_tl.log" vvp "$BUILD_DIR/tb_bigboard_tl.out"
        ;;
    probe_buzzer_uart)
        iverilog -g2001 -o "$BUILD_DIR/tb_probe_buzzer_uart_top.out" \
            "$REPO_ROOT/sim/tb_probe_buzzer_uart_top.v" \
            "$REPO_ROOT/rtl/probe/probe_buzzer_uart_top.v" \
            "$REPO_ROOT/rtl/probe/buzzer_tune_player.v" \
            "$REPO_ROOT/rtl/probe/buzzer_uart_reporter.v" \
            "$REPO_ROOT/rtl/periph/uart_tx.v"
        run_and_check "$BUILD_DIR/tb_probe_buzzer_uart_top.log" vvp "$BUILD_DIR/tb_probe_buzzer_uart_top.out"
        ;;
    probe_vga)
        iverilog -g2001 -o "$BUILD_DIR/tb_probe_vga_top.out" \
            "$REPO_ROOT/sim/tb_probe_vga_top.v" \
            "$REPO_ROOT/rtl/probe/probe_vga_top.v" \
            "$REPO_ROOT/rtl/periph/vga_timing_640x480.v"
        run_and_check "$BUILD_DIR/tb_probe_vga_top.log" vvp "$BUILD_DIR/tb_probe_vga_top.out"
        ;;
    vga_text_mode)
        iverilog -g2001 -o "$BUILD_DIR/tb_vga_text_mode.out" \
            "$REPO_ROOT/sim/tb_vga_text_mode.v" \
            "$REPO_ROOT/rtl/periph/vga_text_mode.v" \
            "$REPO_ROOT/rtl/periph/vga_timing_640x480.v"
        run_and_check "$BUILD_DIR/tb_vga_text_mode.log" vvp "$BUILD_DIR/tb_vga_text_mode.out"
        ;;
    *)
        echo "未知仿真目标：$SIM_KIND" >&2
        echo "支持的目标：uart_tx、uart_rx、traffic_light_gpio、probe_led_key、probe_uart_top、bram、bram_dualport、tinybus_decode、mmio_test_exit、minisoc、minisoc_pico、minisoc_dark、minisoc_smoke_pico、minisoc_smoke_dark、minisoc_uart_once_pico、minisoc_uart_once_dark、minisoc_uart_echo_pico、minisoc_uart_echo_dark、minisoc_traffic_pico、minisoc_traffic_dark、minisoc_perf_pico、minisoc_perf_dark、minisoc_counter_source_pico、minisoc_counter_source_dark、minisoc_counter_reset_pico、minisoc_counter_reset_dark、board_demo_pico、board_demo_dark、sdram_smoke、sdram_data_ctrl、sdram_tester、sdram_tester_fail、sdram_tester_reset、sdram_tester_uart_reporter、bigboard_tl、probe_buzzer_uart、probe_vga、vga_text_mode" >&2
        exit 1
        ;;
esac
