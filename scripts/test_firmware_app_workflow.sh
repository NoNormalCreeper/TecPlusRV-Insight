#!/usr/bin/env bash
# 验证用户 APP 目录推断、统一 compile/load/debug 入口与旧入口兼容。
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
tmp_dir=$(mktemp -d)
fake_app_dir="$repo_root/firmware/apps/baremetal/not_a_file.c"

cleanup() {
    rmdir "$fake_app_dir" 2>/dev/null || true
    rm -rf "$tmp_dir"
}

trap cleanup EXIT

expect_success_contains() {
    local needle=$1
    shift
    local output

    output=$(make --no-print-directory -n -C "$repo_root" "$@")
    if ! grep -F "$needle" <<<"$output" >/dev/null; then
        echo "FAIL: make $* 输出缺少：$needle" >&2
        exit 1
    fi
}

expect_failure_contains() {
    local needle=$1
    shift
    local output

    if output=$(make --no-print-directory -n -C "$repo_root" "$@" 2>&1); then
        echo "FAIL: make $* 意外成功" >&2
        exit 1
    fi
    if ! grep -F "$needle" <<<"$output" >/dev/null; then
        echo "FAIL: make $* 错误缺少：$needle" >&2
        echo "$output" >&2
        exit 1
    fi
}

expect_success_contains 'FIRMWARE_RUNTIME="baremetal"' \
    firmware APP=baremetal/hello.c
expect_success_contains 'firmware/apps/baremetal/hello.c' \
    firmware APP=baremetal/hello.c
expect_success_contains 'FIRMWARE_RUNTIME="irq"' \
    firmware APP=firmware/apps/irq/timer_demo.c
expect_success_contains 'FIRMWARE_RUNTIME="freertos"' \
    firmware-load APP=freertos/queue_demo.c PORT=COM8
expect_success_contains 'bootload PORT="COM8"' \
    firmware-load APP=baremetal/hello.c PORT=COM8
expect_success_contains "FIRMWARE_MAIN=\"$repo_root/firmware/apps/baremetal/hello.c\"" \
    firmware-debug APP=baremetal/hello.c PORT=COM8
expect_success_contains 'FIRMWARE_PROFILE="gdb_stub"' \
    firmware-debug APP=baremetal/hello.c PORT=COM8

expect_failure_contains '未知 APP 运行模型：unknown' \
    firmware APP=unknown/demo.c
expect_failure_contains 'APP 必须位于 firmware/apps' \
    firmware APP=../tests/smoke.c
expect_failure_contains '找不到 APP 文件' \
    firmware APP=baremetal/missing.c
mkdir "$fake_app_dir"
expect_failure_contains 'APP 必须是普通 .c 文件' \
    firmware APP=baremetal/not_a_file.c
rmdir "$fake_app_dir"
expect_failure_contains '当前 GDB 调试尚不支持 irq 应用' \
    firmware-debug APP=irq/timer_demo.c PORT=COM8
expect_failure_contains '当前 GDB 调试尚不支持 freertos 应用' \
    firmware-debug APP=freertos/queue_demo.c PORT=COM8
expect_failure_contains 'firmware-load 需要 PORT' \
    firmware-load APP=baremetal/hello.c

expect_success_contains 'firmware/apps/baremetal/soc_selftest.c' firmware
expect_success_contains 'FIRMWARE_MAIN="/tmp/gdb_user_program.c"' \
    gdb-stub-debug PORT=COM8 GDB_STUB_MAIN=/tmp/gdb_user_program.c

for app in baremetal/hello.c irq/timer_demo.c freertos/queue_demo.c; do
    name=${app%.*}
    name=${name//\//-}
    make --no-print-directory -C "$repo_root" firmware APP="$app" \
        FIRMWARE_OUT="$tmp_dir/$name/firmware" >/dev/null
    for extension in elf bin mem; do
        if [ ! -f "$tmp_dir/$name/firmware.$extension" ]; then
            echo "FAIL: $app 缺少 firmware.$extension" >&2
            exit 1
        fi
    done
done

for app in \
    baremetal/board_demo.c \
    baremetal/soc_selftest.c \
    baremetal/gdb_demo.c \
    baremetal/vga_bitmap_animation.c \
    baremetal/benchmarks/memset_bench.c \
    baremetal/benchmarks/stride_bench.c \
    baremetal/benchmarks/crc32_bench.c \
    baremetal/benchmarks/dot4_bench.c \
    baremetal/benchmarks/system_bench.c \
    irq/timer_irq_smoke.c \
    freertos/bad_apple_full.c; do
    if [ ! -f "$repo_root/firmware/apps/$app" ]; then
        echo "FAIL: 缺少应位于 firmware/apps 的上板程序：$app" >&2
        exit 1
    fi
done

legacy_board_sources='firmware/tests/(board_demo|boot_payload|boot_image_verify|buzzer_tone|gdb_stub_smoke|sdram_memtest|traffic_light_mmio|vga_bitmap_smoke|vga_bitmap_animation|timer_irq_smoke|freertos_smoke|freertos_acceptance|bad_apple_minimal|bad_apple_full|perf_mix|system_bench|sdram_sum_bench|riscv_bench_median|riscv_bench_memcpy|memset_bench|stride_bench|crc32_bench|dot4_bench)\.c'
if grep -E "$legacy_board_sources" \
    "$repo_root/Makefile" \
    "$repo_root/scripts/export_ise_project.sh" \
    "$repo_root/scripts/run_benchmarks.sh" \
    "$repo_root/scripts/run_board_benchmarks.sh" >/dev/null; then
    echo "FAIL: 上板入口仍引用 firmware/tests 中的单用户程序" >&2
    exit 1
fi

if grep -F 'firmware/main.c' \
    "$repo_root/Makefile" "$repo_root/scripts/build_firmware.sh" \
    "$repo_root/sim/run_sim.sh" >/dev/null; then
    echo "FAIL: 默认上板程序仍位于 firmware/apps 之外" >&2
    exit 1
fi

grep -F 'make firmware APP=baremetal/hello.c' \
    "$repo_root/docs/FIRMWARE_GUIDE.md" >/dev/null
grep -F 'make firmware-load' "$repo_root/docs/FIRMWARE_GUIDE.md" >/dev/null
grep -F 'make firmware-debug' "$repo_root/docs/FIRMWARE_GUIDE.md" >/dev/null
grep -F 'DEBUG_BREAK()' "$repo_root/docs/FIRMWARE_GUIDE.md" >/dev/null
grep -F 'docs/FIRMWARE_GUIDE.md' "$repo_root/README.md" >/dev/null
grep -F 'uart_puts("PASS\n");' "$repo_root/firmware/tests/testlib.h" >/dev/null
grep -F '缺少 RESULT' "$repo_root/scripts/run_board_benchmarks.sh" >/dev/null
grep -F '缺少 PASS' "$repo_root/scripts/run_board_benchmarks.sh" >/dev/null
grep -F '0xc0e65e2bu' \
    "$repo_root/firmware/apps/baremetal/benchmarks/crc32_bench.c" >/dev/null

echo "PASS: firmware APP 目录推断、统一入口与旧命令兼容"
