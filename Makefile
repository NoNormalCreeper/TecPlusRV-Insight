SHELL := bash
.NOTPARALLEL:
.DEFAULT_GOAL := help

REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
CHECK_ENV := $(REPO_ROOT)/scripts/check_env.sh
BUILD_FIRMWARE := $(REPO_ROOT)/scripts/build_firmware.sh
RUN_SIM := $(REPO_ROOT)/sim/run_sim.sh
COMPARE_CPU_PERF := $(REPO_ROOT)/scripts/compare_cpu_perf.sh
EXPORT_ISE_PROJECT := $(REPO_ROOT)/scripts/export_ise_project.sh
TEST_RUNNER := python3 $(REPO_ROOT)/scripts/test_runner.py

.PHONY: help check-env firmware rtl-syntax sim test-probe test-platform test-soc test-smoke test-dual-core test-all ci perf ise-export

help:
	@echo "常用目标："
	@echo "  make check-env                 检查本地工具链"
	@echo "  make firmware                  构建 firmware 镜像"
	@echo "  make rtl-syntax                跑 RTL 语法 smoke"
	@echo "  make sim TARGET=minisoc_pico   单独运行一个仿真目标"
	@echo "  make test-probe                跑探针类仿真"
	@echo "  make test-platform             跑平台层仿真"
	@echo "  make test-soc                  跑 MiniSoC 通用 regression / 专项仿真"
	@echo "  make test-smoke                跑当前分支的基础 smoke 与 board-top smoke"
	@echo "  make test-dual-core            跑双核 regression（如果当前分支提供）"
	@echo "  make test-all                  跑全部正确性检查"
	@echo "  make ci                        CI 入口，聚合失败后统一返回非零"
	@echo "  python3 scripts/test_runner.py list   列出 catalog 里的 suite / case"
	@echo "  make perf                      跑双核性能对比（如果当前分支提供）"
	@echo "  make ise-export ISE_TARGET=minisoc   导出 ISE 工程所需文件到新目录"

check-env:
	"$(CHECK_ENV)"

firmware:
	"$(BUILD_FIRMWARE)"

rtl-syntax:
	$(TEST_RUNNER) run-suite rtl_syntax_internal

sim:
ifndef TARGET
	@echo "用法：make sim TARGET=uart_tx"
	@exit 1
else
	"$(RUN_SIM)" "$(TARGET)"
endif

test-probe:
	$(TEST_RUNNER) run-suite probe

test-platform:
	$(TEST_RUNNER) run-suite platform

test-soc:
	$(TEST_RUNNER) run-suite soc

test-smoke:
	$(TEST_RUNNER) run-suite smoke

test-dual-core:
	$(TEST_RUNNER) run-suite dual_core

test-all:
	$(TEST_RUNNER) run-suite all

ci:
	$(TEST_RUNNER) run-suite all --keep-going

perf: firmware rtl-syntax
ifneq ($(wildcard $(COMPARE_CPU_PERF)),)
ifdef PERF_MAIN
		"$(COMPARE_CPU_PERF)" "$(PERF_MAIN)"
else
		"$(COMPARE_CPU_PERF)"
endif
else
	@echo "perf: 当前分支没有 scripts/compare_cpu_perf.sh"
	@exit 1
endif

ISE_TARGET ?= minisoc
ISE_EXPORT_DIR ?= $(REPO_ROOT)/build/ise-export/$(ISE_TARGET)

ise-export:
	"$(EXPORT_ISE_PROJECT)" "$(ISE_TARGET)" "$(ISE_EXPORT_DIR)"
