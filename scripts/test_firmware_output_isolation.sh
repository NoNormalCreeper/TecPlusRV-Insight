#!/usr/bin/env bash
# 验证自定义 firmware 构建彼此隔离，并且不会改写手动构建的默认产物。
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
DEFAULT_OUT="$REPO_ROOT/firmware/build/firmware"
TEST_DIR="$REPO_ROOT/firmware/build/tests/output_isolation"
MAIN_OUT="$TEST_DIR/main/firmware"
PAYLOAD_OUT="$TEST_DIR/boot_payload/payload"
FAILED_OUT="$TEST_DIR/failed/firmware"

fingerprint_default() {
    local ext
    for ext in elf bin mem lst; do
        if [ -f "$DEFAULT_OUT.$ext" ]; then
            sha256sum "$DEFAULT_OUT.$ext"
        else
            echo "missing $DEFAULT_OUT.$ext"
        fi
    done
}

before=$(fingerprint_default)

FIRMWARE_MAIN="$REPO_ROOT/firmware/apps/baremetal/soc_selftest.c" \
FIRMWARE_OUT="firmware/build/tests/output_isolation/main/firmware" \
    "$REPO_ROOT/scripts/build_firmware.sh" >/dev/null

FIRMWARE_MAIN="$REPO_ROOT/firmware/apps/baremetal/boot_payload.c" \
FIRMWARE_OUT="$PAYLOAD_OUT" \
    "$REPO_ROOT/scripts/build_firmware.sh" >/dev/null

for prefix in "$MAIN_OUT" "$PAYLOAD_OUT"; do
    for ext in elf bin mem; do
        if [ ! -f "$prefix.$ext" ]; then
            echo "FAIL: 缺少隔离产物 $prefix.$ext" >&2
            exit 1
        fi
    done
done

if cmp -s "$MAIN_OUT.bin" "$PAYLOAD_OUT.bin"; then
    echo "FAIL: 两个不同入口生成了相同的隔离 payload" >&2
    exit 1
fi

mkdir -p "$(dirname "$FAILED_OUT")"
printf 'stale\n' >"$FAILED_OUT.bin"
if CC=false FIRMWARE_OUT="$FAILED_OUT" \
    "$REPO_ROOT/scripts/build_firmware.sh" >/dev/null 2>&1; then
    echo "FAIL: 故意失败的构建意外成功" >&2
    exit 1
fi

for ext in elf bin mem lst; do
    if [ -e "$FAILED_OUT.$ext" ]; then
        echo "FAIL: 失败构建残留了不可信产物 $FAILED_OUT.$ext" >&2
        exit 1
    fi
done

after=$(fingerprint_default)
if [ "$before" != "$after" ]; then
    echo "FAIL: 自定义构建改写了默认 firmware.*" >&2
    exit 1
fi

echo "PASS: FIRMWARE_OUT 隔离产物且不改写默认 firmware.*"
