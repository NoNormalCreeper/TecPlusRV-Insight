#!/usr/bin/env bash
# 导出一个可直接拷走的新目录。
# 默认 minimal 模式只保留当前 ISE 目标真正需要的输入文件；
# full 模式会把仓库内全部 .v / .vh / .ucf 摊平到导出目录根部，便于一次性导入后在 ISE 里自行选择 top 和约束。
# 只有 firmware.mem 这类路径敏感文件继续保留相对目录结构。
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_FIRMWARE_SCRIPT="$REPO_ROOT/scripts/build_firmware.sh"
FREERTOS_KERNEL="$REPO_ROOT/third_party/FreeRTOS-Kernel"
FREERTOS_EXPECTED_COMMIT="9b777ae5c5b8e9e456065a00294d1e5f5f9facf5"

ISE_TARGET=${1:-minisoc}
EXPORT_DIR=${2:-$REPO_ROOT/build/ise-export/$ISE_TARGET}
ISE_EXPORT_MODE=${ISE_EXPORT_MODE:-minimal}
ISE_FIRMWARE_OUT="$REPO_ROOT/firmware/build/ise/$ISE_TARGET/firmware"

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
    if [ -e "$dst" ] && ! cmp -s "$src" "$dst"; then
        echo "导出时发现同名冲突：$rel -> $base" >&2
        exit 1
    fi
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

copy_firmware_mem() {
    local src="$ISE_FIRMWARE_OUT.mem"
    local bin_src="$ISE_FIRMWARE_OUT.bin"
    local rel="firmware/build/firmware.mem"
    local bin_rel="firmware/build/firmware.bin"
    local dst="$EXPORT_DIR/$rel"
    if [ ! -f "$src" ]; then
        echo "缺少 ISE firmware：$src" >&2
        exit 1
    fi
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    printf '%s\n' "$rel" >>"$EXPORT_DIR/files.list"
    if [ -f "$bin_src" ]; then
        cp "$bin_src" "$EXPORT_DIR/$bin_rel"
        printf '%s\n' "$bin_rel" >>"$EXPORT_DIR/files.list"
    fi
}

write_readme() {
    local top_module="$1"
    local ucf_file="$2"
    local notes="$3"
    local mode_note
    local step_two
    local step_three
    local final_notes="$notes"

    if [ "$ISE_EXPORT_MODE" = "full" ]; then
        final_notes=${final_notes//最小工程/推荐组合}
        mode_note='导出模式：full（根目录包含仓库内全部 .v / .vh / .ucf）'
        step_two='2. 把导出目录根部的 .v / .vh / .ucf 加入工程；如果目录里存在 firmware/build/firmware.mem，也把它加入工程并保持相对路径不变。'
        step_three='3. 在 ISE 里自行选择需要的 top module 和 .ucf；上面的 top / 约束文件只是当前目标的推荐组合。'
        final_notes="full 模式会额外导出仓库内全部可直接 Import 的 RTL/约束文件；当前目标对应的 top / .ucf 仍然是上面的推荐组合。"$'\n'"$final_notes"
    else
        mode_note='导出模式：minimal（只包含当前目标直接需要的文件）'
        step_two='2. 把导出目录根部的 .v / .vh / .ucf 加入工程；如果目录里存在 firmware/build/firmware.mem，也把它加入工程并保持相对路径不变。'
        step_three="3. 把 top module 设为：$top_module"
    fi

    printf '%s\n' \
        'ISE 导出包' \
        '==========' \
        '' \
        "导出目标：$ISE_TARGET" \
        "$mode_note" \
        "建议 top module：$top_module" \
        "约束文件：$ucf_file" \
        '' \
        '使用方式：' \
        '1. 在 ISE 14.7 里新建工程，工程目录直接选这个导出目录或其副本。' \
        "$step_two" \
        "$step_three" \
        '4. 跑 Synthesize / Implement Design / Generate Programming File' \
        '' \
        '附加说明：' \
        "$final_notes" \
        >"$EXPORT_DIR/README.txt"
}

export_full_importable_sources() {
    local rel

    while IFS= read -r rel; do
        copy_flat "$rel"
    done <<EOF
$(cd "$REPO_ROOT" && find rtl -type f \( -name '*.v' -o -name '*.vh' \) | LC_ALL=C sort)
EOF

    while IFS= read -r rel; do
        copy_flat "$rel"
    done <<EOF
$(cd "$REPO_ROOT" && find constraints -type f -name '*.ucf' | LC_ALL=C sort)
EOF
}

package_freertos_sources() {
    local actual_commit
    local rel

    need_file "third_party/FreeRTOS-Kernel/tasks.c"
    need_file "third_party/FreeRTOS-Kernel/queue.c"
    need_file "third_party/FreeRTOS-Kernel/list.c"
    need_file "third_party/FreeRTOS-Kernel/timers.c"
    need_file "third_party/FreeRTOS-Kernel/event_groups.c"
    need_file "third_party/FreeRTOS-Kernel/portable/MemMang/heap_5.c"
    actual_commit=$(git -C "$FREERTOS_KERNEL" rev-parse HEAD 2>/dev/null || true)
    if [ "$actual_commit" != "$FREERTOS_EXPECTED_COMMIT" ]; then
        echo "FreeRTOS-Kernel revision 不匹配：expected=$FREERTOS_EXPECTED_COMMIT actual=${actual_commit:-missing}" >&2
        echo "请运行 git submodule update --init --recursive" >&2
        exit 1
    fi

    copy_rel ".gitmodules"
    copy_rel "third_party/FreeRTOS-Kernel/tasks.c"
    copy_rel "third_party/FreeRTOS-Kernel/queue.c"
    copy_rel "third_party/FreeRTOS-Kernel/list.c"
    copy_rel "third_party/FreeRTOS-Kernel/timers.c"
    copy_rel "third_party/FreeRTOS-Kernel/event_groups.c"
    copy_rel "third_party/FreeRTOS-Kernel/portable/MemMang/heap_5.c"

    while IFS= read -r rel; do
        copy_rel "$rel"
    done <<EOF
$(cd "$REPO_ROOT" && find third_party/FreeRTOS-Kernel/include -type f -name '*.h' | LC_ALL=C sort)
EOF

    while IFS= read -r rel; do
        copy_rel "$rel"
    done <<EOF
$(cd "$REPO_ROOT" && find firmware/freertos -type f | LC_ALL=C sort)
EOF
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
    need_file "rtl/periph/font_rom_8x8.v"
    need_file "rtl/periph/vga_timing_640x480.v"
    need_file "$ucf"
    copy_flat "rtl/probe/probe_vga_text_top.v"
    copy_flat "rtl/periph/vga_text_mode.v"
    copy_flat "rtl/periph/font_rom_8x8.v"
    copy_flat "rtl/periph/vga_timing_640x480.v"
    copy_flat "$ucf"
    write_readme "$top" "$(basename "$ucf")" "这是字符型 VGA 骨架的独立上板工程，不接 SoC。默认会显示一行 banner；支持的字模仍是最小子集。"
}

package_minisoc() {
    local top="tecplus_minisoc_top"
    local ucf="constraints/tecplus_minisoc.ucf"
    local firmware_main="${1:-}"
    local target_note="${2:-}"
    local firmware_profile="${3:-baremetal}"
    local cpu_note="如果当前工程支持双核 wrapper，可在 ISE 的 Generics, Parameters 中覆写 CPU_IMPL：0 表示 PicoRV32，1 表示 DarkRISCV。"

    if [ -n "$firmware_main" ]; then
        FIRMWARE_PROFILE="$firmware_profile" \
        FIRMWARE_MAIN="$firmware_main" FIRMWARE_OUT="$ISE_FIRMWARE_OUT" \
            "$BUILD_FIRMWARE_SCRIPT"
    else
        FIRMWARE_PROFILE="$firmware_profile" \
        FIRMWARE_OUT="$ISE_FIRMWARE_OUT" "$BUILD_FIRMWARE_SCRIPT"
    fi

    need_file "rtl/periph/uart_tx.v"
    need_file "rtl/periph/uart_rx.v"
    need_file "rtl/soc/bootloader_ctrl.v"
    need_file "rtl/periph/traffic_light_gpio.v"
    need_file "rtl/periph/buzzer_pwm.v"
    need_file "rtl/periph/machine_timer.v"
    need_file "rtl/periph/vga_text_mode.v"
    need_file "rtl/periph/vga_bitmap_1bpp.v"
    need_file "rtl/periph/vga_timing_640x480.v"
    need_file "rtl/periph/font_rom_8x8.v"
    need_file "rtl/soc/tinybus_decode.v"
    need_file "rtl/soc/mmio_test_exit.v"
    need_file "rtl/soc/sdram_data_ctrl.v"
    need_file "rtl/soc/tecplus_minisoc_top.v"
    need_file "rtl/accel/dot4_int8.v"
    need_file "$ucf"

    copy_flat "rtl/periph/uart_tx.v"
    copy_flat "rtl/periph/uart_rx.v"
    copy_flat "rtl/soc/bootloader_ctrl.v"
    copy_flat "rtl/periph/traffic_light_gpio.v"
    copy_flat "rtl/periph/buzzer_pwm.v"
    copy_flat "rtl/periph/machine_timer.v"
    copy_flat "rtl/periph/vga_text_mode.v"
    copy_flat "rtl/periph/vga_bitmap_1bpp.v"
    copy_flat "rtl/periph/vga_timing_640x480.v"
    copy_flat "rtl/periph/font_rom_8x8.v"
    copy_flat "rtl/soc/tinybus_decode.v"
    copy_flat "rtl/soc/mmio_test_exit.v"
    copy_flat "rtl/soc/sdram_data_ctrl.v"
    copy_flat "rtl/soc/tecplus_minisoc_top.v"
    copy_flat_if_exists "rtl/soc/tinybus_defs.vh"
    copy_flat_if_exists "rtl/core/picorv32.v"
    copy_flat_if_exists "rtl/core/darkriscv.v"
    copy_flat_if_exists "rtl/core/darkriscv_config.vh"
    copy_flat_if_exists "rtl/soc/tecplus_cpu_wrapper.v"
    copy_flat_if_exists "rtl/soc/picorv32_adapter.v"
    copy_flat_if_exists "rtl/soc/darkriscv_adapter.v"
    copy_flat "rtl/accel/dot4_int8.v"

    if [ -f "$REPO_ROOT/rtl/soc/bram_dualport.v" ]; then
        copy_flat "rtl/soc/bram_dualport.v"
    else
        copy_flat "rtl/soc/bram.v"
    fi

    copy_flat "$ucf"
    copy_firmware_mem
    write_readme "$top" "$(basename "$ucf")" "$target_note"$'\n'"$cpu_note"$'\n'"MiniSoC 已接入 U2 x16 SDRAM；SDRAM_CLK_INVERT 默认沿用 Probe 4 的反相时钟设置。"$'\n'"注意：源码和约束已经摊平到导出目录根部，但 firmware.mem 仍应保持 firmware/build/firmware.mem 这个相对路径。"
}

rm -rf "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"
: >"$EXPORT_DIR/files.list"

case "$ISE_EXPORT_MODE" in
    minimal|full)
        ;;
    *)
        echo "未知 ISE 导出模式：$ISE_EXPORT_MODE" >&2
        echo "支持：minimal, full" >&2
        exit 1
        ;;
esac

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
    minisoc|minisoc_pico)
        package_minisoc
        ;;
    minisoc_dark)
        package_minisoc "$REPO_ROOT/firmware/apps/irq/timer_irq_smoke.c" "这是 DarkRISCV machine timer IRQ 验收目标。请在 ISE 的 Generics, Parameters 中设置 CPU_IMPL=1、BOOTLOADER_ENABLE=1、VGA_TEXT_ENABLE=0。导出包同时包含 firmware/build/firmware.bin，可通过共用 bootloader 装载；仓库中也可运行 make timer-irq-load PORT=COM8。UART 输出 timer irq pass: ticks=<次数> loops=<前台循环次数> 表示 firmware 验收通过。2026-07-11 当前 revision 已完成 Map/PAR 与真实上板：50 MHz post-route timing slack 为 0.462 ns，上板输出 ticks=3 loops=46；后续 RTL 或约束变化必须重新验收。" "dark_irq"
        ;;
    minisoc_freertos_dark|freertos_dark)
        FREERTOS_CPU_CLOCK_HZ=50000000 \
            package_minisoc "$REPO_ROOT/firmware/apps/freertos/freertos_smoke.c" "这是 DarkRISCV FreeRTOS timer/preemption/delay/critical smoke 上板目标。请在 ISE 的 Generics, Parameters 中设置 CPU_IMPL=1、BOOTLOADER_ENABLE=1、VGA_TEXT_ENABLE=0。导出包的 firmware/build/firmware.bin 可通过共用 bootloader 装载；仓库中也可运行 make freertos-load PORT=COM8。LED=5 且 test_exit=1 表示 smoke 完成。导出包内的 third_party/ 与 firmware/freertos/ 是 payload 可复现源码，不要作为 RTL source 加入 ISE。真实 Map/PAR/timing 与上板 UART 仍属于人工 Gate。" "freertos"
        package_freertos_sources
        ;;
    minisoc_freertos_acceptance_dark|freertos_acceptance_dark)
        FREERTOS_CPU_CLOCK_HZ=50000000 \
            package_minisoc "$REPO_ROOT/firmware/apps/freertos/freertos_acceptance.c" "这是 DarkRISCV FreeRTOS SDRAM 综合验收上板目标。请在 ISE 的 Generics, Parameters 中设置 CPU_IMPL=1、BOOTLOADER_ENABLE=1、VGA_TEXT_ENABLE=0。验收依次覆盖 heap_5、scheduler、queue/notification、semaphore/mutex、event group、software timer 和 dynamic object；UART 输出 freertos acceptance pass、LED=5 表示通过。仓库中可运行 make freertos-acceptance-load PORT=COM8。当前只完成自动仿真，Map/PAR/timing 与真实上板属于人工 Gate。" "freertos"
        package_freertos_sources
        ;;
    minisoc_vga_bitmap_dark|vga_bitmap_dark)
        package_minisoc "$REPO_ROOT/firmware/apps/baremetal/vga_bitmap_smoke.c" "这是 64x48 1bpp VGA MMIO 的 DarkRISCV 上板验收目标。请在 ISE 的 Generics, Parameters 中设置 CPU_IMPL=1、BOOTLOADER_ENABLE=1、VGA_BITMAP_ENABLE=1、VGA_TEXT_ENABLE=0。烧录后运行 make firmware-load APP=baremetal/vga_bitmap_smoke.c PORT=COM8；屏幕应显示白色边框和中心十字，UART 应输出 vga bitmap smoke pass。动态写入可运行 make firmware-load APP=baremetal/vga_bitmap_animation.c PORT=COM8。2026-07-11 已通过 ISE 综合与 PAR：4216/5720 LUT（73%）、1585/11440 registers（13%），framebuffer 已推断为 LUT Memory，50 MHz slack 为 +0.620 ns；固件真实上板显示仍待验证。"
        ;;
    bad_apple_full_dark|bad_apple_full)
        FREERTOS_CPU_CLOCK_HZ=50000000 \
            package_minisoc "$REPO_ROOT/firmware/apps/freertos/bad_apple_full.c" "这是全时长 Bad Apple BAM2 上板目标。请在 ISE Generics, Parameters 中设置 CPU_IMPL=1、BOOTLOADER_ENABLE=1、VGA_BITMAP_ENABLE=1、VGA_TEXT_ENABLE=0；UART_BAUD 必须与 make bad-apple-full-load 使用的 BOOTLOAD_BAUD 一致，默认均为 9600。先烧录 bitstream，再运行 make bad-apple-full-load PORT=COM8。约 219 秒后 UART 输出 bad apple full pass、LED=5 并循环。" "freertos"
        package_freertos_sources
        ;;
    minisoc_bootloader|bootloader)
        package_minisoc "$REPO_ROOT/firmware/apps/baremetal/boot_payload.c" "这是 UART bootloader 目标。请在 ISE 的 Generics, Parameters 中设置 BOOTLOADER_ENABLE=1、VGA_TEXT_ENABLE=0，并让 UART_BAUD 与 host --baud 一致；程序复位后等待 READY。LOAD_IMAGE 全量读回与吞吐测试见 docs/BOOTLOADER_BOARD_TEST.md。"
        ;;
    bad_apple_minimal|bad_apple)
        package_minisoc "$REPO_ROOT/firmware/apps/baremetal/bad_apple_minimal.c" "这是保留的 BAM1 仿真/资源实验原型，不是当前可上板目标。若要重现实验，请显式设置 BOOTLOADER_ENABLE=1、VGA_TEXT_ENABLE=1；已知 writable text/tile RAM 会让 LX9 MiniSoC overmap。后续 1bpp 改造见 docs/BAD_APPLE_FUTURE.md。"
        ;;
    probe_minisoc_sdram|minisoc_sdram_probe|m2b_probe)
        package_minisoc "$REPO_ROOT/firmware/apps/baremetal/sdram_memtest.c" "这是 M2b 板级 probe：真实 CPU 从 BRAM 取指，经数据总线访问 BRAM、TinyBus MMIO 与 U2 SDRAM。LED=5 且 UART 打印 all patterns verified 表示通过。"
        ;;
    *)
        echo "未知 ISE 导出目标：$ISE_TARGET" >&2
        echo "支持：probe_led_key, probe_uart, probe_sdram_smoke, probe_minisoc_sdram, probe_bigboard_tl, probe_buzzer_uart, probe_vga, probe_vga_text, minisoc, minisoc_pico, minisoc_dark, minisoc_freertos_dark, minisoc_freertos_acceptance_dark, minisoc_vga_bitmap_dark, bad_apple_minimal, bad_apple_full_dark" >&2
        exit 1
        ;;
esac

if [ "$ISE_EXPORT_MODE" = "full" ]; then
    export_full_importable_sources
fi

sort -u "$EXPORT_DIR/files.list" -o "$EXPORT_DIR/files.list"

echo "ISE 导出完成：$EXPORT_DIR"
echo "文件清单：$EXPORT_DIR/files.list"
