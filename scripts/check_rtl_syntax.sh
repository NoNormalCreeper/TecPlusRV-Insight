#!/usr/bin/env bash
# RTL 语法 smoke 兼容入口。
# 真实配方已经下沉到 runner catalog + rtl_syntax_case.sh，这里只保留旧入口名。
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
python3 "$REPO_ROOT/scripts/test_runner.py" run-suite rtl_syntax_internal --catalog "$REPO_ROOT/scripts/test_catalog.json"
