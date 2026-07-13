#!/usr/bin/env bash
# 运行 DarkRISCV DOT4 benchmark，并自动验证正确性与性能方向。
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
LOG_FILE="$REPO_ROOT/sim/build/tb_dot4_bench_dark.log"

"$REPO_ROOT/sim/run_sim.sh" dot4_bench_dark

scalar_line=$(sed -n '/RESULT: benchmark=dot4 mode=scalar /p' "$LOG_FILE")
custom_line=$(sed -n '/RESULT: benchmark=dot4 mode=custom /p' "$LOG_FILE")

if [ -z "$scalar_line" ] || [ -z "$custom_line" ]; then
    echo "FAIL: DOT4 benchmark 缺少 scalar/custom 结果行" >&2
    exit 1
fi

field_value() {
    line=$1
    field=$2
    echo "$line" | sed -n "s/.* $field=\\([^ ]*\\).*/\\1/p" | tr -d '\r'
}

scalar_checksum=$(field_value "$scalar_line" checksum)
custom_checksum=$(field_value "$custom_line" checksum)
scalar_cycles=$(field_value "$scalar_line" cycles)
custom_cycles=$(field_value "$custom_line" cycles)
scalar_instret=$(field_value "$scalar_line" instret)
custom_instret=$(field_value "$custom_line" instret)

if [ "$scalar_checksum" != "$custom_checksum" ]; then
    echo "FAIL: DOT4 checksum 不一致 scalar=$scalar_checksum custom=$custom_checksum" >&2
    exit 1
fi
if [ "$custom_cycles" -ge "$scalar_cycles" ]; then
    echo "FAIL: DOT4 custom cycles 未降低 scalar=$scalar_cycles custom=$custom_cycles" >&2
    exit 1
fi
if [ "$custom_instret" -ge "$scalar_instret" ]; then
    echo "FAIL: DOT4 custom instret 未降低 scalar=$scalar_instret custom=$custom_instret" >&2
    exit 1
fi

speedup_x100=$((scalar_cycles * 100 / custom_cycles))
speedup_whole=$((speedup_x100 / 100))
speedup_frac=$((speedup_x100 % 100))
speedup=$(printf '%d.%02d' "$speedup_whole" "$speedup_frac")

echo "PASS: DOT4 benchmark checksum=$custom_checksum cycles=$scalar_cycles->$custom_cycles instret=$scalar_instret->$custom_instret speedup=${speedup}x"
