#!/usr/bin/env bash
# 导出一个可直接拷走的新目录，只保留 ISE 工程真正需要的输入文件。
# .v / .vh / .ucf 会摊平到导出目录根部，便于在 ISE 里直接 Import Sources；
# 只有 firmware.mem 这类路径敏感文件继续保留相对目录结构。
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_FIRMWARE_SCRIPT="$REPO_ROOT/scripts/build_firmware.sh"

ISE_TARGET=${1:-minisoc}
EXPORT_DIR=${2:-$REPO_ROOT/build/ise-export/$ISE_TARGET}

need_file() {
    local rel="$1"
    if [ ! -f "$REPO_ROOT/$rel" ]; then
        echo "缺少必需文件：$rel" >&2
        exit 1
    fi
}

copy_rel() {
    local rel="$1"
    local src="$REPO_ROOT/$rel"
    local dst="$EXPORT_DIR/$rel"
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    printf '%s\n' "$rel" >>"$EXPORT_DIR/files.list"
}

copy_flat() {
    local rel="$1"
    local src="$REPO_ROOT/$rel"
    local base
    base=$(basename "$rel")
    local dst="$EXPORT_DIR/$base"
    cp "$src" "$dst"
    printf '%s\n' "$base" >>"$EXPORT_DIR/files.list"
}

copy_flat_if_exists() {
    local rel="$1"
    if [ -f "$REPO_ROOT/$rel" ]; then
        copy_flat "$rel"
    fi
}

copy_if_exists() {
    local rel="$1"
    if [ -f "$REPO_ROOT/$rel" ]; then
        copy_rel "$rel"
    fi
}

write_readme() {
    local top_module="$1"
    local ucf_file="$2"
    local notes="$3"

    printf '%s\n' \
        'ISE 导出包' \
        '==========' \
        '' \
        "导出目标：$ISE_TARGET" \
        "建议 top module：$top_module" \
        "约束文件：$ucf_file" \
        '' \
        '使用方式：' \
        '1. 在 ISE 14.7 里新建工程，工程目录直接选这个导出目录或其副本。' \
        '2. 把导出目录根部的 .v / .vh / .ucf 加入工程；如果目录里存在 firmware/build/firmware.mem，也把它加入工程并保持相对路径不变。' \
        "3. 把 top module 设为：$top_module" \
        '4. 跑 Synthesize / Implement Design / Generate Programming File' \
        '' \
        '附加说明：' \
        "$notes" \
        >"$EXPORT_DIR/README.txt"
}

package_probe_led_key() {
    local top="probe_led_key_top"
    local ucf="constraints/tecplus_led_key.ucf"
    need_file "rtl/probe/probe_led_key_top.v"
    need_file "$ucf"
    copy_flat "rtl/probe/probe_led_key_top.v"
    copy_flat "$ucf"
    write_readme "$top" "$(basename "$ucf")" "这是 Probe 0 最小工程，不需要 firmware.mem。"
}

package_probe_uart() {
    local top="probe_uart_top"
    local ucf="constraints/tecplus_uart.ucf"
    need_file "rtl/probe/probe_uart_top.v"
    need_file "rtl/periph/uart_tx.v"
    need_file "$ucf"
    copy_flat "rtl/probe/probe_uart_top.v"
    copy_flat "rtl/periph/uart_tx.v"
    copy_flat "$ucf"
    write_readme "$top" "$(basename "$ucf")" "这是 Probe 1 最小工程，不需要 firmware.mem。"
}

package_probe_sdram_smoke() {
    local top="probe_sdram_smoke_top"
    local ucf="constraints/tecplus_sdram_smoke.ucf"
    need_file "rtl/probe/probe_sdram_smoke_top.v"
    need_file "rtl/probe/sdram_smoke_ctrl.v"
    need_file "$ucf"
    copy_flat "rtl/probe/probe_sdram_smoke_top.v"
    copy_flat "rtl/probe/sdram_smoke_ctrl.v"
    copy_flat "$ucf"
    write_readme "$top" "$(basename "$ucf")" "这是 Probe 4a 最小工程，不需要 firmware.mem。"
}

package_probe_bigboard_tl() {
    local top="probe_bigboard_tl_top"
    local ucf="constraints/tecplus_bigboard_tl.ucf"
    need_file "rtl/probe/probe_bigboard_tl_top.v"
    need_file "$ucf"
    copy_flat "rtl/probe/probe_bigboard_tl_top.v"
    copy_flat "$ucf"
    write_readme "$top" "$(basename "$ucf")" "这是 Probe 5a 最小工程，不需要 firmware.mem。"
}

package_probe_buzzer_uart() {
    local top="probe_buzzer_uart_top"
    local ucf="constraints/tecplus_buzzer_uart.ucf"
    need_file "rtl/probe/probe_buzzer_uart_top.v"
    need_file "rtl/probe/buzzer_tune_player.v"
    need_file "rtl/probe/buzzer_uart_reporter.v"
    need_file "rtl/periph/uart_tx.v"
    need_file "$ucf"
    copy_flat "rtl/probe/probe_buzzer_uart_top.v"
    copy_flat "rtl/probe/buzzer_tune_player.v"
    copy_flat "rtl/probe/buzzer_uart_reporter.v"
    copy_flat "rtl/periph/uart_tx.v"
    copy_flat "$ucf"
    write_readme "$top" "$(basename "$ucf")" "这是蜂鸣器 UART debug probe 最小工程，不需要 firmware.mem。当前旋律、时值近似和 Mf/Clr/S 默认电平都写死在参数与注释里；若板上无声或音高异常，请先检查这些假设。"
}

package_probe_vga() {
    local top="probe_vga_top"
    local ucf="constraints/tecplus_vga.ucf"
    need_file "rtl/probe/probe_vga_top.v"
    need_file "rtl/periph/vga_timing_640x480.v"
    need_file "$ucf"
    copy_flat "rtl/probe/probe_vga_top.v"
    copy_flat "rtl/periph/vga_timing_640x480.v"
    copy_flat "$ucf"
    write_readme "$top" "$(basename "$ucf")" "这是 VGA thin probe 最小工程，不需要 firmware.mem。Mf/Clr/Qd 当前只是参数化默认值，若无显示请优先回头检查它们。"
}

package_probe_vga_text() {
    local top="probe_vga_text_top"
    local ucf="constraints/tecplus_vga.ucf"
    need_file "rtl/probe/probe_vga_text_top.v"
    need_file "rtl/periph/vga_text_mode.v"
    need_file "rtl/periph/vga_timing_640x480.v"
    need_file "$ucf"
    copy_flat "rtl/probe/probe_vga_text_top.v"
    copy_flat "rtl/periph/vga_text_mode.v"
    copy_flat "rtl/periph/vga_timing_640x480.v"
    copy_flat "$ucf"
    write_readme "$top" "$(basename "$ucf")" "这是字符型 VGA 骨架的独立上板工程，不接 SoC。默认会显示一行 banner；支持的字模仍是最小子集。"
}

package_minisoc() {
    local top="tecplus_minisoc_top"
    local ucf="constraints/tecplus_minisoc.ucf"
    local cpu_note="如果当前工程支持双核 wrapper，可在 ISE 的 Generics, Parameters 中覆写 CPU_IMPL：0 表示 PicoRV32，1 表示 DarkRISCV。"

    "$BUILD_FIRMWARE_SCRIPT"

    need_file "rtl/periph/uart_tx.v"
    need_file "rtl/periph/uart_rx.v"
    need_file "rtl/periph/traffic_light_gpio.v"
    need_file "rtl/soc/tinybus_decode.v"
    need_file "rtl/soc/mmio_test_exit.v"
    need_file "rtl/soc/tecplus_minisoc_top.v"
    need_file "$ucf"
    need_file "firmware/build/firmware.mem"

    copy_flat "rtl/periph/uart_tx.v"
    copy_flat "rtl/periph/uart_rx.v"
    copy_flat "rtl/periph/traffic_light_gpio.v"
    copy_flat "rtl/soc/tinybus_decode.v"
    copy_flat "rtl/soc/mmio_test_exit.v"
    copy_flat "rtl/soc/tecplus_minisoc_top.v"
    copy_flat_if_exists "rtl/soc/tinybus_defs.vh"
    copy_flat_if_exists "rtl/core/picorv32.v"
    copy_flat_if_exists "rtl/core/darkriscv.v"
    copy_flat_if_exists "rtl/core/darkriscv_config.vh"
    copy_flat_if_exists "rtl/soc/tecplus_cpu_wrapper.v"
    copy_flat_if_exists "rtl/soc/picorv32_adapter.v"
    copy_flat_if_exists "rtl/soc/darkriscv_adapter.v"

    if [ -f "$REPO_ROOT/rtl/soc/bram_dualport.v" ]; then
        copy_flat "rtl/soc/bram_dualport.v"
    else
        copy_flat "rtl/soc/bram.v"
    fi

    copy_flat "$ucf"
    copy_rel "firmware/build/firmware.mem"
    write_readme "$top" "$(basename "$ucf")" "$cpu_note"$'\n'"注意：源码和约束已经摊平到导出目录根部，但 firmware.mem 仍应保持 firmware/build/firmware.mem 这个相对路径。"
}

rm -rf "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"
: >"$EXPORT_DIR/files.list"

case "$ISE_TARGET" in
    probe_led_key|led_key|probe0)
        package_probe_led_key
        ;;
    probe_uart|uart|probe1)
        package_probe_uart
        ;;
    probe_sdram_smoke|sdram_smoke|probe4a)
        package_probe_sdram_smoke
        ;;
    probe_bigboard_tl|bigboard_tl|probe5a)
        package_probe_bigboard_tl
        ;;
    probe_buzzer_uart|buzzer_uart|probe5c)
        package_probe_buzzer_uart
        ;;
    probe_vga|vga|probe5b)
        package_probe_vga
        ;;
    probe_vga_text|vga_text|probe5)
        package_probe_vga_text
        ;;
    minisoc|minisoc_pico|minisoc_dark)
        package_minisoc
        ;;
    *)
        echo "未知 ISE 导出目标：$ISE_TARGET" >&2
        echo "支持：probe_led_key, probe_uart, probe_sdram_smoke, probe_bigboard_tl, probe_buzzer_uart, probe_vga, probe_vga_text, minisoc, minisoc_pico, minisoc_dark" >&2
        exit 1
        ;;
esac

sort -u "$EXPORT_DIR/files.list" -o "$EXPORT_DIR/files.list"

echo "ISE 导出完成：$EXPORT_DIR"
echo "文件清单：$EXPORT_DIR/files.list"
