SHELL := bash
.NOTPARALLEL:
.DEFAULT_GOAL := help

REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
CHECK_ENV := $(REPO_ROOT)/scripts/check_env.sh
BUILD_FIRMWARE := $(REPO_ROOT)/scripts/build_firmware.sh
CHECK_RTL_SYNTAX := $(REPO_ROOT)/scripts/check_rtl_syntax.sh
RUN_SIM := $(REPO_ROOT)/sim/run_sim.sh
DUAL_CORE_REGRESSION := $(REPO_ROOT)/scripts/test_dual_core_regression.sh
COMPARE_CPU_PERF := $(REPO_ROOT)/scripts/compare_cpu_perf.sh

PROBE_TARGETS := probe_led_key probe_uart_top uart_tx sdram_smoke bigboard_tl
PLATFORM_TARGETS := bram tinybus_decode mmio_test_exit
SOC_TARGETS := minisoc

ifneq ($(wildcard $(REPO_ROOT)/rtl/soc/bram_dualport.v),)
PLATFORM_TARGETS += bram_dualport
endif

ifneq ($(wildcard $(REPO_ROOT)/rtl/core/darkriscv.v),)
SOC_TARGETS := minisoc_pico minisoc_dark
ifneq ($(wildcard $(REPO_ROOT)/sim/tb_minisoc_counter_source.v),)
SOC_TARGETS += minisoc_counter_source_pico minisoc_counter_source_dark
endif
endif

define run_sim_list
for target in $(1); do \
    echo "==> 运行 $$target"; \
    "$(RUN_SIM)" "$$target"; \
done
endef

.PHONY: help check-env firmware rtl-syntax sim test-probe test-platform test-soc test-smoke test-dual-core test-all ci perf

help:
	@echo "常用目标："
	@echo "  make check-env                 检查本地工具链"
	@echo "  make firmware                  构建 firmware 镜像"
	@echo "  make rtl-syntax                跑 RTL 语法 smoke"
	@echo "  make sim TARGET=minisoc        单独运行一个仿真目标"
	@echo "  make test-probe                跑探针类仿真"
	@echo "  make test-platform             跑平台层仿真"
	@echo "  make test-soc                  跑 MiniSoC 相关仿真"
	@echo "  make test-smoke                跑当前分支的基础 smoke"
	@echo "  make test-dual-core            跑双核 regression（如果当前分支提供）"
	@echo "  make test-all                  跑全部正确性检查"
	@echo "  make ci                        CI 入口，等价于 make test-all"
	@echo "  make perf                      跑双核性能对比（如果当前分支提供）"

check-env:
	"$(CHECK_ENV)"

firmware:
	"$(BUILD_FIRMWARE)"

rtl-syntax:
	"$(CHECK_RTL_SYNTAX)"

sim:
ifndef TARGET
	@echo "用法：make sim TARGET=uart_tx"
	@exit 1
else
	"$(RUN_SIM)" "$(TARGET)"
endif

test-probe: rtl-syntax
	@$(call run_sim_list,$(PROBE_TARGETS))

test-platform: rtl-syntax
	@$(call run_sim_list,$(PLATFORM_TARGETS))

test-soc: firmware rtl-syntax
	@$(call run_sim_list,$(SOC_TARGETS))

test-smoke: check-env firmware test-probe test-platform test-soc

test-dual-core: firmware rtl-syntax
ifneq ($(wildcard $(DUAL_CORE_REGRESSION)),)
	"$(DUAL_CORE_REGRESSION)"
else
	@echo "test-dual-core: 当前分支没有 scripts/test_dual_core_regression.sh，跳过。"
endif

test-all: test-smoke test-dual-core

ci: test-all

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
