#!/usr/bin/env bash
# 本地一键兼容入口。
# 真实前置步骤和 case 顺序由 test_runner 的 local suite 决定，这里只保留旧入口名。
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
python3 "$REPO_ROOT/scripts/test_runner.py" run-suite local --catalog "$REPO_ROOT/scripts/test_catalog.json"
