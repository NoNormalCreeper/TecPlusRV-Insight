#!/usr/bin/env bash
# 本地仿真统一入口。
# 用法：sim/run_sim.sh <目标名>；不传参数时默认跑 uart_tx。
# 每个目标都会编译到 sim/build，再用 vvp 运行并检查 FAIL/TIMEOUT。
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR="$REPO_ROOT/sim/build"
SIM_KIND=${1:-uart_tx}
DEFAULT_FIRMWARE_MAIN="$REPO_ROOT/firmware/apps/baremetal/soc_selftest.c"
# SDRAM 目标默认跑 memtest；显式传入 FIRMWARE_MAIN 时用于 benchmark/runtime 验收。
SDRAM_FIRMWARE_MAIN=${FIRMWARE_MAIN:-$REPO_ROOT/firmware/apps/baremetal/sdram_memtest.c}
FIRMWARE_MEM=${FIRMWARE_MEM:-}

need_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "缺少必需工具：$1" >&2
        exit 1
    fi
}

need_tool iverilog
need_tool vvp

mkdir -p "$BUILD_DIR"

prepare_firmware() {
    local firmware_out

    if [ -n "$FIRMWARE_MEM" ]; then
        case "$FIRMWARE_MEM" in
            /*) ;;
            *) FIRMWARE_MEM="$REPO_ROOT/$FIRMWARE_MEM" ;;
        esac
        if [ ! -f "$FIRMWARE_MEM" ]; then
            echo "找不到指定的 firmware mem：$FIRMWARE_MEM" >&2
            exit 1
        fi
        return
    fi

    firmware_out=${FIRMWARE_OUT:-$REPO_ROOT/firmware/build/sim/$SIM_KIND/firmware}
    case "$firmware_out" in
        /*) ;;
        *) firmware_out="$REPO_ROOT/$firmware_out" ;;
    esac

    FIRMWARE_MAIN=${FIRMWARE_MAIN:-$DEFAULT_FIRMWARE_MAIN} \
    FIRMWARE_OUT="$firmware_out" \
        "$REPO_ROOT/scripts/build_firmware.sh" >/dev/null
    FIRMWARE_MEM="$firmware_out.mem"
}

run_and_check() {
    local out_file="$1"
    shift

    "$@" >"$out_file" 2>&1
    cat "$out_file"

    # testbench 统一用 "FAIL:" / "TIMEOUT:" 标记失败，脚本只解析这两个关键词。
    if grep -Eq '(FAIL|TIMEOUT):' "$out_file"; then
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
    local require_buzzer_write="${16:-}"
    local require_buzzer_toggle="${17:-}"
    local extra_params=()
    local firmware_param

    prepare_firmware
    firmware_param="$tb_module.FIRMWARE_MEM_FILE=\"$FIRMWARE_MEM\""

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

    if [ -n "${TB_GDB_CONTINUE_PC:-}" ]; then
        extra_params+=(
            -P "$tb_module.CONTINUE_PC=32'h$TB_GDB_CONTINUE_PC"
        )
    fi

    if [ -n "${TB_GDB_EXPLICIT_PC:-}" ]; then
        extra_params+=(
            -P "$tb_module.EXPLICIT_PC=$TB_GDB_EXPLICIT_PC"
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

    if [ "$arg_count" -ge 17 ]; then
        extra_params+=(
            -P "$tb_module.REQUIRE_BUZZER_WRITE=$require_buzzer_write"
            -P "$tb_module.REQUIRE_BUZZER_TOGGLE=$require_buzzer_toggle"
        )
    fi

    if [ "$tb_module" = "tb_bad_apple_minimal" ] ||
       [ "$tb_module" = "tb_bad_apple_full" ] ||
       [ "$tb_module" = "tb_boot_image_verify" ]; then
        extra_params+=(
            -P "$tb_module.ASSET_MEM_FILE=\"$ASSET_MEM\""
        )
    fi

    if [ "$tb_module" = "tb_freertos_smoke" ]; then
        if [ -z "${TASK_PC_START:-}" ] || [ -z "${TASK_PC_END:-}" ] ||
           [ -z "${TRAP_PC_START:-}" ]; then
            echo "缺少 TASK_PC_START / TASK_PC_END / TRAP_PC_START，无法验证 FreeRTOS 控制流" >&2
            exit 1
        fi
        extra_params+=(
            -P "$tb_module.TASK_PC_START=32'h$TASK_PC_START"
            -P "$tb_module.TASK_PC_END=32'h$TASK_PC_END"
            -P "$tb_module.TRAP_PC_START=32'h$TRAP_PC_START"
            -P "$tb_module.MIN_ECALL_TRAPS=${MIN_ECALL_TRAPS:-0}"
            -P "$tb_module.MIN_TIMER_TRAPS=${MIN_TIMER_TRAPS:-0}"
            -P "$tb_module.REQUIRE_TIMER_STALL=${REQUIRE_TIMER_STALL:-0}"
            -P "$tb_module.EXPECT_QUEUE_DEMO=${EXPECT_QUEUE_DEMO:-0}"
            -P "$tb_module.REQUIRE_UART_WRITE=${REQUIRE_FREERTOS_UART:-0}"
            -P "$tb_module.SOC_CLK_FREQ=${FREERTOS_SOC_CLK_FREQ:-1000000}"
            -P "$tb_module.TIMEOUT_CYCLES=${FREERTOS_TIMEOUT_CYCLES:-2000000}"
        )
    fi

    iverilog -g2001 -I "$REPO_ROOT/rtl/soc" -I "$REPO_ROOT/rtl/core" \
        -s "$tb_module" \
        -P "$tb_module.CPU_IMPL=$cpu_impl" \
        -P "$firmware_param" \
        "${extra_params[@]}" \
        -o "$out_file" \
        "$tb_file" \
        "$REPO_ROOT/rtl/core/picorv32.v" \
        "$REPO_ROOT/rtl/core/darkriscv.v" \
        "$REPO_ROOT/rtl/soc/tecplus_minisoc_top.v" \
        "$REPO_ROOT/rtl/soc/bootloader_ctrl.v" \
        "$REPO_ROOT/rtl/soc/tecplus_cpu_wrapper.v" \
        "$REPO_ROOT/rtl/soc/picorv32_adapter.v" \
        "$REPO_ROOT/rtl/soc/darkriscv_adapter.v" \
        "$REPO_ROOT/rtl/soc/bram_dualport.v" \
        "$REPO_ROOT/rtl/soc/tinybus_decode.v" \
        "$REPO_ROOT/rtl/soc/mmio_test_exit.v" \
        "$REPO_ROOT/rtl/periph/uart_tx.v" \
        "$REPO_ROOT/rtl/periph/uart_rx.v" \
        "$REPO_ROOT/rtl/periph/traffic_light_gpio.v" \
        "$REPO_ROOT/rtl/periph/machine_timer.v" \
        "$REPO_ROOT/rtl/soc/sdram_data_ctrl.v" \
        "$REPO_ROOT/sim/sdram_x16_model.v" \
        "$REPO_ROOT/rtl/periph/buzzer_pwm.v" \
        "$REPO_ROOT/rtl/periph/vga_text_mode.v" \
        "$REPO_ROOT/rtl/periph/vga_bitmap_1bpp.v" \
        "$REPO_ROOT/rtl/periph/vga_timing_640x480.v" \
        "$REPO_ROOT/rtl/periph/font_rom_8x8.v"
}

compile_minisoc_perf_tb() {
    local out_file="$1"
    local cpu_impl="$2"
    local tb_module="$3"
    local tb_file="$4"
    local result_cycle_addr="${PERF_RESULT_CYCLE_ADDR:-}"
    local result_instret_addr="${PERF_RESULT_INSTRET_ADDR:-}"
    local firmware_param

    prepare_firmware
    firmware_param="$tb_module.FIRMWARE_MEM_FILE=\"$FIRMWARE_MEM\""

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
        -s "$tb_module" \
        -P "$tb_module.CPU_IMPL=$cpu_impl" \
        -P "$firmware_param" \
        -P "$tb_module.RESULT_CYCLE_ADDR=$result_cycle_addr" \
        -P "$tb_module.RESULT_INSTRET_ADDR=$result_instret_addr" \
        -o "$out_file" \
        "$tb_file" \
        "$REPO_ROOT/rtl/core/picorv32.v" \
        "$REPO_ROOT/rtl/core/darkriscv.v" \
        "$REPO_ROOT/rtl/soc/tecplus_minisoc_top.v" \
        "$REPO_ROOT/rtl/soc/bootloader_ctrl.v" \
        "$REPO_ROOT/rtl/soc/tecplus_cpu_wrapper.v" \
        "$REPO_ROOT/rtl/soc/picorv32_adapter.v" \
        "$REPO_ROOT/rtl/soc/darkriscv_adapter.v" \
        "$REPO_ROOT/rtl/soc/bram_dualport.v" \
        "$REPO_ROOT/rtl/soc/tinybus_decode.v" \
        "$REPO_ROOT/rtl/soc/mmio_test_exit.v" \
        "$REPO_ROOT/rtl/periph/uart_tx.v" \
        "$REPO_ROOT/rtl/periph/uart_rx.v" \
        "$REPO_ROOT/rtl/periph/traffic_light_gpio.v" \
        "$REPO_ROOT/rtl/periph/machine_timer.v" \
        "$REPO_ROOT/rtl/soc/sdram_data_ctrl.v" \
        "$REPO_ROOT/rtl/periph/buzzer_pwm.v" \
        "$REPO_ROOT/rtl/periph/vga_text_mode.v" \
        "$REPO_ROOT/rtl/periph/vga_bitmap_1bpp.v" \
        "$REPO_ROOT/rtl/periph/vga_timing_640x480.v" \
        "$REPO_ROOT/rtl/periph/font_rom_8x8.v"
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
    gdb_packet)
        "${HOST_CC:-cc}" -std=c11 -Wall -Wextra -Werror \
            -I"$REPO_ROOT/firmware" \
            -o "$BUILD_DIR/test_gdb_packet" \
            "$REPO_ROOT/tests/test_gdb_packet.c" \
            "$REPO_ROOT/firmware/gdb/gdb_packet.c"
        run_and_check "$BUILD_DIR/test_gdb_packet.log" "$BUILD_DIR/test_gdb_packet"
        ;;
    bootloader_ctrl)
        iverilog -g2001 -s tb_bootloader_ctrl \
            -o "$BUILD_DIR/tb_bootloader_ctrl.out" \
            "$REPO_ROOT/sim/tb_bootloader_ctrl.v" \
            "$REPO_ROOT/rtl/soc/bootloader_ctrl.v"
        run_and_check "$BUILD_DIR/tb_bootloader_ctrl.log" vvp "$BUILD_DIR/tb_bootloader_ctrl.out"
        ;;
    traffic_light_gpio)
        iverilog -g2001 -o "$BUILD_DIR/tb_traffic_light_gpio.out" \
            "$REPO_ROOT/sim/tb_traffic_light_gpio.v" \
            "$REPO_ROOT/rtl/periph/traffic_light_gpio.v"
        run_and_check "$BUILD_DIR/tb_traffic_light_gpio.log" vvp "$BUILD_DIR/tb_traffic_light_gpio.out"
        ;;
    buzzer_pwm)
        iverilog -g2001 -o "$BUILD_DIR/tb_buzzer_pwm.out" \
            "$REPO_ROOT/sim/tb_buzzer_pwm.v" \
            "$REPO_ROOT/rtl/periph/buzzer_pwm.v"
        run_and_check "$BUILD_DIR/tb_buzzer_pwm.log" vvp "$BUILD_DIR/tb_buzzer_pwm.out"
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
    bootloader_pico)
        compile_minisoc_tb "$BUILD_DIR/tb_bootloader_pico.out" 0 tb_minisoc_bootloader "$REPO_ROOT/sim/tb_minisoc_bootloader.v"
        run_and_check "$BUILD_DIR/tb_bootloader_pico.log" vvp "$BUILD_DIR/tb_bootloader_pico.out"
        ;;
    bootloader_dark)
        compile_minisoc_tb "$BUILD_DIR/tb_bootloader_dark.out" 1 tb_minisoc_bootloader "$REPO_ROOT/sim/tb_minisoc_bootloader.v"
        run_and_check "$BUILD_DIR/tb_bootloader_dark.log" vvp "$BUILD_DIR/tb_bootloader_dark.out"
        ;;
    bad_apple_minimal_pico)
        ASSET_MEM=${ASSET_MEM:-$BUILD_DIR/bad_apple_minimal.mem}
        python3 "$REPO_ROOT/scripts/make_bad_apple_minimal_asset.py" \
            --output "$BUILD_DIR/bad_apple_minimal.bin" \
            --mem-output "$ASSET_MEM" >/dev/null
        FIRMWARE_MAIN="$REPO_ROOT/firmware/apps/baremetal/bad_apple_minimal.c"
        compile_minisoc_tb "$BUILD_DIR/tb_bad_apple_minimal_pico.out" 0 tb_bad_apple_minimal "$REPO_ROOT/sim/tb_bad_apple_minimal.v"
        run_and_check "$BUILD_DIR/tb_bad_apple_minimal_pico.log" vvp "$BUILD_DIR/tb_bad_apple_minimal_pico.out"
        ;;
    bad_apple_full)
        ASSET_MEM=${ASSET_MEM:-$BUILD_DIR/bad_apple_full.mem}
        python3 "$REPO_ROOT/scripts/make_bad_apple_full_asset.py" \
            --synthetic --output "$BUILD_DIR/bad_apple_full.bin" \
            --mem "$ASSET_MEM" >/dev/null
        FIRMWARE_MAIN="$REPO_ROOT/firmware/apps/freertos/bad_apple_full.c" \
        FIRMWARE_PROFILE=freertos \
        FREERTOS_CPU_CLOCK_HZ=4000000 \
            compile_minisoc_tb "$BUILD_DIR/tb_bad_apple_full.out" 1 \
                tb_bad_apple_full "$REPO_ROOT/sim/tb_bad_apple_full.v"
        run_and_check "$BUILD_DIR/tb_bad_apple_full.log" \
            vvp "$BUILD_DIR/tb_bad_apple_full.out"
        ;;
    boot_image_verify_pico|boot_image_verify_dark)
        ASSET_MEM=${ASSET_MEM:-$BUILD_DIR/boot_image_test.mem}
        python3 "$REPO_ROOT/scripts/make_boot_image_test_asset.py" \
            --data-bytes 256 --seed 0x12345678 \
            --output "$BUILD_DIR/boot_image_test.bin" \
            --mem-output "$ASSET_MEM" >/dev/null
        FIRMWARE_MAIN="$REPO_ROOT/firmware/apps/baremetal/boot_image_verify.c"
        if [ "$SIM_KIND" = "boot_image_verify_pico" ]; then
            compile_minisoc_tb "$BUILD_DIR/tb_boot_image_verify_pico.out" 0 tb_boot_image_verify "$REPO_ROOT/sim/tb_boot_image_verify.v"
            run_and_check "$BUILD_DIR/tb_boot_image_verify_pico.log" vvp "$BUILD_DIR/tb_boot_image_verify_pico.out"
        else
            compile_minisoc_tb "$BUILD_DIR/tb_boot_image_verify_dark.out" 1 tb_boot_image_verify "$REPO_ROOT/sim/tb_boot_image_verify.v"
            run_and_check "$BUILD_DIR/tb_boot_image_verify_dark.log" vvp "$BUILD_DIR/tb_boot_image_verify_dark.out"
        fi
        ;;
    minisoc_smoke_pico)
        compile_minisoc_tb "$BUILD_DIR/tb_minisoc_smoke_pico.out" 0 tb_minisoc "$REPO_ROOT/sim/tb_minisoc.v" 1 1 1
        run_and_check "$BUILD_DIR/tb_minisoc_smoke_pico.log" vvp "$BUILD_DIR/tb_minisoc_smoke_pico.out"
        ;;
    minisoc_smoke_dark)
        compile_minisoc_tb "$BUILD_DIR/tb_minisoc_smoke_dark.out" 1 tb_minisoc "$REPO_ROOT/sim/tb_minisoc.v" 1 1 1
        run_and_check "$BUILD_DIR/tb_minisoc_smoke_dark.log" vvp "$BUILD_DIR/tb_minisoc_smoke_dark.out"
        ;;
    freertos_frame_contract)
        FIRMWARE_MAIN="$REPO_ROOT/firmware/tests/freertos_frame_contract.c" \
        FIRMWARE_PROFILE=freertos \
        FREERTOS_CPU_CLOCK_HZ=1000000 \
            compile_minisoc_tb "$BUILD_DIR/tb_freertos_frame_contract.out" 1 \
                tb_minisoc "$REPO_ROOT/sim/tb_minisoc.v" 0 1 1 -1 1 5
        run_and_check "$BUILD_DIR/tb_freertos_frame_contract.log" \
            vvp "$BUILD_DIR/tb_freertos_frame_contract.out"
        ;;
    freertos_first_task)
        FIRMWARE_MAIN="$REPO_ROOT/firmware/tests/freertos_first_task.c" \
        FIRMWARE_PROFILE=freertos \
        FREERTOS_CPU_CLOCK_HZ=4000000 \
            prepare_firmware
        TASK_SYMBOL=$(riscv64-unknown-elf-nm -S --defined-only \
            "${FIRMWARE_MEM%.mem}.elf" | awk '$4 == "first_task" { print $1, $2 }')
        if [ -z "$TASK_SYMBOL" ]; then
            echo "找不到 first_task symbol，无法建立 PC 观测区间" >&2
            exit 1
        fi
        set -- $TASK_SYMBOL
        TASK_PC_START=$1
        TASK_PC_END=$(printf '%08x' $((0x$1 + 0x$2)))
        TRAP_PC_START=$(riscv64-unknown-elf-nm --defined-only \
            "${FIRMWARE_MEM%.mem}.elf" | awk '$3 == "trap_entry" { print $1 }')
        FREERTOS_SOC_CLK_FREQ=4000000
        compile_minisoc_tb "$BUILD_DIR/tb_freertos_first_task.out" 1 \
            tb_freertos_smoke "$REPO_ROOT/sim/tb_freertos_smoke.v"
        run_and_check "$BUILD_DIR/tb_freertos_first_task.log" \
            vvp "$BUILD_DIR/tb_freertos_first_task.out"
        ;;
    freertos_yield_smoke)
        FIRMWARE_MAIN="$REPO_ROOT/firmware/tests/freertos_yield_smoke.c" \
        FIRMWARE_PROFILE=freertos \
        FREERTOS_CPU_CLOCK_HZ=4000000 \
            prepare_firmware
        TASK_SYMBOL=$(riscv64-unknown-elf-nm -S --defined-only \
            "${FIRMWARE_MEM%.mem}.elf" | awk '$4 == "yield_task" { print $1, $2 }')
        if [ -z "$TASK_SYMBOL" ]; then
            echo "找不到 yield_task symbol，无法建立 PC 观测区间" >&2
            exit 1
        fi
        set -- $TASK_SYMBOL
        TASK_PC_START=$1
        TASK_PC_END=$(printf '%08x' $((0x$1 + 0x$2)))
        TRAP_PC_START=$(riscv64-unknown-elf-nm --defined-only \
            "${FIRMWARE_MEM%.mem}.elf" | awk '$3 == "trap_entry" { print $1 }')
        MIN_ECALL_TRAPS=2000
        FREERTOS_SOC_CLK_FREQ=4000000
        FREERTOS_TIMEOUT_CYCLES=3500000
        compile_minisoc_tb "$BUILD_DIR/tb_freertos_yield_smoke.out" 1 \
            tb_freertos_smoke "$REPO_ROOT/sim/tb_freertos_smoke.v"
        run_and_check "$BUILD_DIR/tb_freertos_yield_smoke.log" \
            vvp "$BUILD_DIR/tb_freertos_yield_smoke.out"
        ;;
    freertos_smoke)
        FIRMWARE_MAIN="$REPO_ROOT/firmware/apps/freertos/freertos_smoke.c" \
        FIRMWARE_PROFILE=freertos \
        FREERTOS_CPU_CLOCK_HZ=4000000 \
            prepare_firmware
        TASK_SYMBOL=$(riscv64-unknown-elf-nm -S --defined-only \
            "${FIRMWARE_MEM%.mem}.elf" | awk '$4 == "smoke_task_a" { print $1, $2 }')
        if [ -z "$TASK_SYMBOL" ]; then
            echo "找不到 smoke_task_a symbol，无法建立 PC 观测区间" >&2
            exit 1
        fi
        set -- $TASK_SYMBOL
        TASK_PC_START=$1
        TASK_PC_END=$(printf '%08x' $((0x$1 + 0x$2)))
        TRAP_PC_START=$(riscv64-unknown-elf-nm --defined-only \
            "${FIRMWARE_MEM%.mem}.elf" | awk '$3 == "trap_entry" { print $1 }')
        MIN_TIMER_TRAPS=1000
        REQUIRE_TIMER_STALL=1
        REQUIRE_FREERTOS_UART=1
        FREERTOS_SOC_CLK_FREQ=4000000
        FREERTOS_TIMEOUT_CYCLES=${FREERTOS_TIMEOUT_CYCLES:-4500000}
        compile_minisoc_tb "$BUILD_DIR/tb_freertos_smoke.out" 1 \
            tb_freertos_smoke "$REPO_ROOT/sim/tb_freertos_smoke.v"
        run_and_check "$BUILD_DIR/tb_freertos_smoke.log" \
            vvp "$BUILD_DIR/tb_freertos_smoke.out"
        ;;
    freertos_queue)
        FIRMWARE_MAIN="$REPO_ROOT/firmware/tests/freertos_queue.c" \
        FIRMWARE_PROFILE=freertos \
        FREERTOS_CPU_CLOCK_HZ=4000000 \
            prepare_firmware
        TASK_SYMBOL=$(riscv64-unknown-elf-nm -S --defined-only \
            "${FIRMWARE_MEM%.mem}.elf" | awk '$4 == "queue_consumer_task" { print $1, $2 }')
        if [ -z "$TASK_SYMBOL" ]; then
            echo "找不到 queue_consumer_task symbol，无法建立 PC 观测区间" >&2
            exit 1
        fi
        set -- $TASK_SYMBOL
        TASK_PC_START=$1
        TASK_PC_END=$(printf '%08x' $((0x$1 + 0x$2)))
        TRAP_PC_START=$(riscv64-unknown-elf-nm --defined-only \
            "${FIRMWARE_MEM%.mem}.elf" | awk '$3 == "trap_entry" { print $1 }')
        FREERTOS_SOC_CLK_FREQ=4000000
        FREERTOS_TIMEOUT_CYCLES=3000000
        EXPECT_QUEUE_DEMO=1
        compile_minisoc_tb "$BUILD_DIR/tb_freertos_queue.out" 1 \
            tb_freertos_smoke "$REPO_ROOT/sim/tb_freertos_smoke.v"
        run_and_check "$BUILD_DIR/tb_freertos_queue.log" \
            vvp "$BUILD_DIR/tb_freertos_queue.out"
        ;;
    freertos_acceptance)
        FIRMWARE_MAIN="$REPO_ROOT/firmware/apps/freertos/freertos_acceptance.c" \
        FIRMWARE_PROFILE=freertos \
        FREERTOS_CPU_CLOCK_HZ=4000000 \
            compile_minisoc_tb "$BUILD_DIR/tb_freertos_acceptance.out" 1 \
                tb_minisoc_sdram "$REPO_ROOT/sim/tb_minisoc_sdram.v"
        run_and_check "$BUILD_DIR/tb_freertos_acceptance.log" \
            vvp "$BUILD_DIR/tb_freertos_acceptance.out"
        ;;
    minisoc_timer_irq_dark)
        FIRMWARE_MAIN="$REPO_ROOT/firmware/apps/irq/timer_irq_smoke.c" \
        FIRMWARE_PROFILE=dark_irq \
            compile_minisoc_tb "$BUILD_DIR/tb_minisoc_timer_irq_dark.out" 1 \
                tb_minisoc_timer_irq "$REPO_ROOT/sim/tb_minisoc_timer_irq.v"
        run_and_check "$BUILD_DIR/tb_minisoc_timer_irq_dark.log" \
            vvp "$BUILD_DIR/tb_minisoc_timer_irq_dark.out"
        ;;
    gdb_stub)
        FIRMWARE_MAIN="$REPO_ROOT/firmware/apps/baremetal/gdb_stub_smoke.c" \
        FIRMWARE_PROFILE=gdb_stub \
            prepare_firmware
        GDB_CONTINUE_PC=$(riscv64-unknown-elf-nm --defined-only \
            "${FIRMWARE_MEM%.mem}.elf" | awk '$3 == "gdb_pc_continue_target" { print $1 }')
        if [ -z "$GDB_CONTINUE_PC" ]; then
            echo "找不到 gdb_pc_continue_target symbol" >&2
            exit 1
        fi
        TB_GDB_CONTINUE_PC="$GDB_CONTINUE_PC" TB_GDB_EXPLICIT_PC=1 \
            compile_minisoc_tb "$BUILD_DIR/tb_gdb_stub_explicit_pc.out" 1 \
                tb_gdb_stub "$REPO_ROOT/sim/tb_gdb_stub.v"
        run_and_check "$BUILD_DIR/tb_gdb_stub_explicit_pc.log" \
            vvp "$BUILD_DIR/tb_gdb_stub_explicit_pc.out"
        TB_GDB_CONTINUE_PC="$GDB_CONTINUE_PC" TB_GDB_EXPLICIT_PC=0 \
            compile_minisoc_tb "$BUILD_DIR/tb_gdb_stub_cooperative.out" 1 \
                tb_gdb_stub "$REPO_ROOT/sim/tb_gdb_stub.v"
        run_and_check "$BUILD_DIR/tb_gdb_stub_cooperative.log" \
            vvp "$BUILD_DIR/tb_gdb_stub_cooperative.out"
        TB_GDB_CONTINUE_PC="$GDB_CONTINUE_PC" TB_GDB_EXPLICIT_PC=2 \
            compile_minisoc_tb "$BUILD_DIR/tb_gdb_stub_caddr.out" 1 \
                tb_gdb_stub "$REPO_ROOT/sim/tb_gdb_stub.v"
        run_and_check "$BUILD_DIR/tb_gdb_stub_caddr.log" \
            vvp "$BUILD_DIR/tb_gdb_stub_caddr.out"
        ;;
    minisoc_vga_bitmap_dark)
        FIRMWARE_MAIN="$REPO_ROOT/firmware/apps/baremetal/vga_bitmap_smoke.c" \
            compile_minisoc_tb "$BUILD_DIR/tb_minisoc_vga_bitmap_dark.out" 1 \
                tb_minisoc_vga_bitmap "$REPO_ROOT/sim/tb_minisoc_vga_bitmap.v"
        run_and_check "$BUILD_DIR/tb_minisoc_vga_bitmap_dark.log" \
            vvp "$BUILD_DIR/tb_minisoc_vga_bitmap_dark.out"
        ;;
    minisoc_sdram_pico)
        FIRMWARE_MAIN="$SDRAM_FIRMWARE_MAIN"
        compile_minisoc_tb "$BUILD_DIR/tb_minisoc_sdram_pico.out" 0 tb_minisoc_sdram "$REPO_ROOT/sim/tb_minisoc_sdram.v"
        run_and_check "$BUILD_DIR/tb_minisoc_sdram_pico.log" vvp "$BUILD_DIR/tb_minisoc_sdram_pico.out"
        ;;
    minisoc_sdram_dark)
        FIRMWARE_MAIN="$SDRAM_FIRMWARE_MAIN"
        compile_minisoc_tb "$BUILD_DIR/tb_minisoc_sdram_dark.out" 1 tb_minisoc_sdram "$REPO_ROOT/sim/tb_minisoc_sdram.v"
        run_and_check "$BUILD_DIR/tb_minisoc_sdram_dark.log" vvp "$BUILD_DIR/tb_minisoc_sdram_dark.out"
        ;;
    minisoc_sdram_subword_pico)
        FIRMWARE_MAIN="$REPO_ROOT/firmware/tests/sdram_subword.c" \
            compile_minisoc_tb "$BUILD_DIR/tb_minisoc_sdram_subword_pico.out" 0 tb_minisoc_sdram "$REPO_ROOT/sim/tb_minisoc_sdram.v"
        run_and_check "$BUILD_DIR/tb_minisoc_sdram_subword_pico.log" vvp "$BUILD_DIR/tb_minisoc_sdram_subword_pico.out"
        ;;
    minisoc_sdram_subword_dark)
        FIRMWARE_MAIN="$REPO_ROOT/firmware/tests/sdram_subword.c" \
            compile_minisoc_tb "$BUILD_DIR/tb_minisoc_sdram_subword_dark.out" 1 tb_minisoc_sdram "$REPO_ROOT/sim/tb_minisoc_sdram.v"
        run_and_check "$BUILD_DIR/tb_minisoc_sdram_subword_dark.log" vvp "$BUILD_DIR/tb_minisoc_sdram_subword_dark.out"
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
    minisoc_buzzer_pico)
        compile_minisoc_tb "$BUILD_DIR/tb_minisoc_buzzer_pico.out" 0 tb_minisoc "$REPO_ROOT/sim/tb_minisoc.v" 0 1 1 -1 1 5 0 0 -1 0 -1 1 1
        run_and_check "$BUILD_DIR/tb_minisoc_buzzer_pico.log" vvp "$BUILD_DIR/tb_minisoc_buzzer_pico.out"
        ;;
    minisoc_buzzer_dark)
        compile_minisoc_tb "$BUILD_DIR/tb_minisoc_buzzer_dark.out" 1 tb_minisoc "$REPO_ROOT/sim/tb_minisoc.v" 0 1 1 -1 1 5 0 0 -1 0 -1 1 1
        run_and_check "$BUILD_DIR/tb_minisoc_buzzer_dark.log" vvp "$BUILD_DIR/tb_minisoc_buzzer_dark.out"
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
        FIRMWARE_MAIN="$REPO_ROOT/firmware/apps/baremetal/board_demo.c" \
            compile_minisoc_tb "$BUILD_DIR/tb_board_demo_pico.out" 0 tb_board_demo "$REPO_ROOT/sim/tb_board_demo.v"
        run_and_check "$BUILD_DIR/tb_board_demo_pico.log" vvp "$BUILD_DIR/tb_board_demo_pico.out"
        ;;
    board_demo_dark)
        FIRMWARE_MAIN="$REPO_ROOT/firmware/apps/baremetal/board_demo.c" \
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
    sdram_data_ctrl_probe_reporter)
        iverilog -g2001 -o "$BUILD_DIR/tb_sdram_data_ctrl_probe_reporter.out" \
            "$REPO_ROOT/sim/tb_sdram_data_ctrl_probe_reporter.v" \
            "$REPO_ROOT/rtl/probe/sdram_data_ctrl_probe_reporter.v"
        run_and_check "$BUILD_DIR/tb_sdram_data_ctrl_probe_reporter.log" vvp "$BUILD_DIR/tb_sdram_data_ctrl_probe_reporter.out"
        ;;
    probe_sdram_data_ctrl)
        iverilog -g2001 -o "$BUILD_DIR/tb_probe_sdram_data_ctrl_top.out" \
            "$REPO_ROOT/sim/tb_probe_sdram_data_ctrl_top.v" \
            "$REPO_ROOT/rtl/probe/probe_sdram_data_ctrl_top.v" \
            "$REPO_ROOT/rtl/probe/sdram_data_ctrl_probe_runner.v" \
            "$REPO_ROOT/rtl/probe/sdram_data_ctrl_probe_reporter.v" \
            "$REPO_ROOT/rtl/soc/sdram_data_ctrl.v" \
            "$REPO_ROOT/rtl/periph/uart_tx.v"
        run_and_check "$BUILD_DIR/tb_probe_sdram_data_ctrl_top.log" vvp "$BUILD_DIR/tb_probe_sdram_data_ctrl_top.out"
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
    font_rom_8x8)
        iverilog -g2001 -o "$BUILD_DIR/tb_font_rom_8x8.out" \
            "$REPO_ROOT/sim/tb_font_rom_8x8.v" \
            "$REPO_ROOT/rtl/periph/font_rom_8x8.v"
        run_and_check "$BUILD_DIR/tb_font_rom_8x8.log" vvp "$BUILD_DIR/tb_font_rom_8x8.out"
        ;;
    vga_text_mode)
        iverilog -g2001 -o "$BUILD_DIR/tb_vga_text_mode.out" \
            "$REPO_ROOT/sim/tb_vga_text_mode.v" \
            "$REPO_ROOT/rtl/periph/vga_text_mode.v" \
            "$REPO_ROOT/rtl/periph/font_rom_8x8.v" \
            "$REPO_ROOT/rtl/periph/vga_timing_640x480.v"
        run_and_check "$BUILD_DIR/tb_vga_text_mode.log" vvp "$BUILD_DIR/tb_vga_text_mode.out"
        ;;
    vga_bitmap_1bpp)
        iverilog -g2001 -o "$BUILD_DIR/tb_vga_bitmap_1bpp.out" \
            "$REPO_ROOT/sim/tb_vga_bitmap_1bpp.v" \
            "$REPO_ROOT/rtl/periph/vga_bitmap_1bpp.v" \
            "$REPO_ROOT/rtl/periph/vga_timing_640x480.v"
        run_and_check "$BUILD_DIR/tb_vga_bitmap_1bpp.log" vvp "$BUILD_DIR/tb_vga_bitmap_1bpp.out"
        ;;
    darkriscv_machine_trap)
        need_tool riscv64-unknown-elf-gcc
        need_tool riscv64-unknown-elf-objcopy
        # 新版工具链要求显式声明 Zicsr；旧 GCC 10 只接受 rv32i，
        # 但其 assembler 仍会正确接受 CSR 指令。
        trap_march=rv32i
        if riscv64-unknown-elf-gcc -march=rv32i_zicsr -mabi=ilp32 \
            -E -x c /dev/null -o /dev/null >/dev/null 2>&1; then
            trap_march=rv32i_zicsr
        fi
        riscv64-unknown-elf-gcc -march="$trap_march" -mabi=ilp32 \
            -nostdlib -nostartfiles \
            -T "$REPO_ROOT/tests/riscv_tests/tecplus_p/link.ld" \
            -o "$BUILD_DIR/darkriscv_machine_trap.elf" \
            "$REPO_ROOT/firmware/tests/darkriscv_machine_trap.S"
        riscv64-unknown-elf-objcopy -O binary \
            "$BUILD_DIR/darkriscv_machine_trap.elf" \
            "$BUILD_DIR/darkriscv_machine_trap.bin"
        python3 "$REPO_ROOT/scripts/bin2mem.py" \
            "$BUILD_DIR/darkriscv_machine_trap.bin" \
            "$BUILD_DIR/darkriscv_machine_trap.mem" 16384
        iverilog -g2001 -D__INTERRUPT__ -DSIMULATION -I "$REPO_ROOT/rtl/core" \
            -s tb_darkriscv_machine_trap \
            -P "tb_darkriscv_machine_trap.FIRMWARE_MEM_FILE=\"$BUILD_DIR/darkriscv_machine_trap.mem\"" \
            -o "$BUILD_DIR/tb_darkriscv_machine_trap.out" \
            "$REPO_ROOT/sim/tb_darkriscv_machine_trap.v" \
            "$REPO_ROOT/rtl/core/darkriscv.v"
        run_and_check "$BUILD_DIR/tb_darkriscv_machine_trap.log" vvp "$BUILD_DIR/tb_darkriscv_machine_trap.out"
        ;;
    machine_timer)
        iverilog -g2001 -s tb_machine_timer \
            -o "$BUILD_DIR/tb_machine_timer.out" \
            "$REPO_ROOT/sim/tb_machine_timer.v" \
            "$REPO_ROOT/rtl/periph/machine_timer.v"
        run_and_check "$BUILD_DIR/tb_machine_timer.log" vvp "$BUILD_DIR/tb_machine_timer.out"
        ;;
    *)
        echo "未知仿真目标：$SIM_KIND" >&2
        echo "支持的目标：uart_tx、uart_rx、bootloader_ctrl、bootloader_pico、bootloader_dark、bad_apple_minimal_pico、bad_apple_full、boot_image_verify_pico、boot_image_verify_dark、traffic_light_gpio、buzzer_pwm、probe_led_key、probe_uart_top、bram、bram_dualport、tinybus_decode、mmio_test_exit、minisoc、minisoc_pico、minisoc_dark、minisoc_smoke_pico、minisoc_smoke_dark、freertos_frame_contract、freertos_first_task、freertos_yield_smoke、freertos_smoke、freertos_queue、freertos_acceptance、minisoc_timer_irq_dark、minisoc_vga_bitmap_dark、minisoc_sdram_pico、minisoc_sdram_dark、minisoc_sdram_subword_pico、minisoc_sdram_subword_dark、minisoc_uart_once_pico、minisoc_uart_once_dark、minisoc_uart_echo_pico、minisoc_uart_echo_dark、minisoc_traffic_pico、minisoc_traffic_dark、minisoc_buzzer_pico、minisoc_buzzer_dark、minisoc_perf_pico、minisoc_perf_dark、minisoc_counter_source_pico、minisoc_counter_source_dark、minisoc_counter_reset_pico、minisoc_counter_reset_dark、board_demo_pico、board_demo_dark、sdram_smoke、sdram_data_ctrl、sdram_tester、sdram_tester_fail、sdram_tester_reset、sdram_tester_uart_reporter、sdram_data_ctrl_probe_reporter、probe_sdram_data_ctrl、bigboard_tl、probe_buzzer_uart、probe_vga、font_rom_8x8、vga_text_mode、vga_bitmap_1bpp、darkriscv_machine_trap、machine_timer" >&2
        exit 1
        ;;
esac
