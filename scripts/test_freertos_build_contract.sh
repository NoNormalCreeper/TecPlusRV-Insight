#!/usr/bin/env bash
# 验证 FreeRTOS kernel revision、profile 构建与 BRAM image 上限。
set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
KERNEL="$REPO_ROOT/third_party/FreeRTOS-Kernel"
OUT="$REPO_ROOT/firmware/build/freertos/build-contract/firmware"

if [ ! -f "$KERNEL/tasks.c" ]; then
    echo "FAIL: 缺少 FreeRTOS-Kernel；请运行 git submodule update --init --recursive" >&2
    exit 1
fi

kernel_tag=$(git -C "$KERNEL" describe --tags --exact-match 2>/dev/null || true)
if [ "$kernel_tag" != "V11.3.0" ]; then
    echo "FAIL: FreeRTOS-Kernel 必须固定为 V11.3.0，当前为 ${kernel_tag:-未知 revision}" >&2
    exit 1
fi

FIRMWARE_PROFILE=freertos \
FIRMWARE_MAIN="$REPO_ROOT/firmware/tests/freertos_build_contract.c" \
FIRMWARE_OUT="$OUT" \
FREERTOS_CPU_CLOCK_HZ=1000000 \
    "$REPO_ROOT/scripts/build_firmware.sh"

test -s "$OUT.elf"
test -s "$OUT.bin"
test -s "$OUT.mem"
test -s "$OUT.lst"

bin_bytes=$(wc -c < "$OUT.bin")
if [ "$bin_bytes" -ge 65536 ]; then
    echo "FAIL: FreeRTOS BRAM image 超过 64 KiB：${bin_bytes} bytes" >&2
    exit 1
fi

echo "PASS: FreeRTOS profile 固定 V11.3.0 且 BRAM image=${bin_bytes} bytes"
