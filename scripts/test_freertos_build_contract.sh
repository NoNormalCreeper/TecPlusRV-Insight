#!/usr/bin/env bash
# 验证 FreeRTOS kernel revision、profile 构建与 BRAM image 上限。
set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
KERNEL="$REPO_ROOT/third_party/FreeRTOS-Kernel"
OUT="$REPO_ROOT/firmware/build/freertos/build-contract/firmware"
NM=${NM:-riscv64-unknown-elf-nm}
BUILD_LOG="$OUT.build.log"
mkdir -p "$(dirname "$OUT")"

if [ ! -f "$KERNEL/tasks.c" ]; then
    echo "FAIL: 缺少 FreeRTOS-Kernel；请运行 git submodule update --init --recursive" >&2
    exit 1
fi

expected_kernel_revision=9b777ae5c5b8e9e456065a00294d1e5f5f9facf5
kernel_revision=$(git -C "$KERNEL" rev-parse HEAD 2>/dev/null || true)
if [ "$kernel_revision" != "$expected_kernel_revision" ]; then
    echo "FAIL: FreeRTOS-Kernel 必须固定为 V11.3.0，当前 revision=${kernel_revision:-未知}" >&2
    exit 1
fi

FIRMWARE_PROFILE=freertos \
FIRMWARE_MAIN="$REPO_ROOT/firmware/tests/freertos_build_contract.c" \
FIRMWARE_OUT="$OUT" \
FREERTOS_CPU_CLOCK_HZ=1000000 \
    "$REPO_ROOT/scripts/build_firmware.sh" >"$BUILD_LOG"
cat "$BUILD_LOG"

test -s "$OUT.elf"
test -s "$OUT.bin"
test -s "$OUT.mem"
test -s "$OUT.lst"

need_symbol() {
    if ! "$NM" "$OUT.elf" | awk '{print $3}' | grep -qx "$1"; then
        echo "FAIL: FreeRTOS profile 缺少符号 $1" >&2
        exit 1
    fi
}

need_symbol vPortDefineHeapRegions
need_symbol xTimerCreate
need_symbol xEventGroupCreate
need_symbol freertos_heap_init

heap_start=$("$NM" -n "$OUT.elf" | awk '$3 == "_heap_start" {print $1}')
heap_end=$("$NM" -n "$OUT.elf" | awk '$3 == "_heap_end" {print $1}')
if [ -z "$heap_start" ] || [ -z "$heap_end" ]; then
    echo "FAIL: linker 未导出完整的 heap 边界" >&2
    exit 1
fi
heap_bytes=$((16#$heap_end - 16#$heap_start))
if [ "$heap_bytes" -ne 65536 ]; then
    echo "FAIL: FreeRTOS heap region 不是 64 KiB：${heap_bytes} bytes" >&2
    exit 1
fi

if ! grep -q '^BRAM sections:' "$BUILD_LOG"; then
    echo "FAIL: firmware 构建没有报告 BRAM section 用量" >&2
    exit 1
fi

grep -q '^freertos-acceptance:' "$REPO_ROOT/Makefile" || {
    echo "FAIL: Makefile 缺少 freertos-acceptance target" >&2
    exit 1
}
grep -q '^freertos-acceptance-load:' "$REPO_ROOT/Makefile" || {
    echo "FAIL: Makefile 缺少 freertos-acceptance-load target" >&2
    exit 1
}
grep -q 'minisoc_freertos_acceptance_dark' \
    "$REPO_ROOT/scripts/export_ise_project.sh" || {
    echo "FAIL: ISE export 缺少 FreeRTOS acceptance target" >&2
    exit 1
}

bin_bytes=$(wc -c < "$OUT.bin")
if [ "$bin_bytes" -ge 65536 ]; then
    echo "FAIL: FreeRTOS BRAM image 超过 64 KiB：${bin_bytes} bytes" >&2
    exit 1
fi

echo "PASS: FreeRTOS profile 固定 V11.3.0 且 BRAM image=${bin_bytes} bytes"
