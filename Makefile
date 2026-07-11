SHELL := bash
.NOTPARALLEL:
.DEFAULT_GOAL := help

REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
CHECK_ENV := $(REPO_ROOT)/scripts/check_env.sh
BUILD_FIRMWARE := $(REPO_ROOT)/scripts/build_firmware.sh
RUN_SIM := $(REPO_ROOT)/sim/run_sim.sh
COMPARE_CPU_PERF := $(REPO_ROOT)/scripts/compare_cpu_perf.sh
EXPORT_ISE_PROJECT := $(REPO_ROOT)/scripts/export_ise_project.sh
UART_LOADER := $(REPO_ROOT)/scripts/uart_loader.py
TEST_RUNNER := python3 $(REPO_ROOT)/scripts/test_runner.py
WINDOWS_PYTHON ?= py.exe
BOOTLOAD_BAUD ?= 9600
FIRMWARE_PROFILE ?= baremetal
FIRMWARE_MAIN ?= $(REPO_ROOT)/firmware/main.c
BOOTLOAD_FIRMWARE_OUT := $(REPO_ROOT)/firmware/build/bootload/firmware
BAD_APPLE_FIRMWARE_OUT := $(REPO_ROOT)/firmware/build/bad_apple_minimal
BAD_APPLE_ASSET := $(REPO_ROOT)/build/badapple/bad_apple_20s.bin
BAD_APPLE_PREVIEW := $(REPO_ROOT)/build/badapple/bad_apple_20s.gif
BAD_APPLE_REPORT := $(REPO_ROOT)/build/badapple/bad_apple_20s.json
BAD_APPLE_VIDEO := $(REPO_ROOT)/firmware/assets/bad-apple.mp4
BAD_APPLE_MIDI := $(REPO_ROOT)/firmware/assets/badapple-midifull.mid
BOOT_IMAGE_TEST_FIRMWARE_OUT := $(REPO_ROOT)/firmware/build/boot_image_verify
BOOT_IMAGE_TEST_ASSET := $(REPO_ROOT)/build/bootloader-test/pattern.bin
TIMER_IRQ_FIRMWARE_OUT := $(REPO_ROOT)/firmware/build/timer_irq_smoke
DATA_BYTES ?= 65536
SEED ?= 0x12345678

.PHONY: help check-env firmware timer-irq-smoke timer-irq-load bootload boot-image-test-build boot-image-test-load bad-apple-build bad-apple-load rtl-syntax sim test-probe test-platform test-soc test-smoke test-dual-core test-all ci perf benchmark ise-export

help:
	@echo "常用目标："
	@echo "  make check-env                 检查本地工具链"
	@echo "  make firmware                  构建手动默认 firmware 镜像"
	@echo "  make firmware FIRMWARE_OUT=... 构建到指定输出前缀"
	@echo "  make timer-irq-smoke           构建 DarkRISCV timer IRQ 专用镜像"
	@echo "  make timer-irq-load PORT=COM8  构建、上传并监视 timer IRQ 验收镜像"
	@echo "  make bootload PORT=COM8        构建、上传并进入 serial monitor"
	@echo "  make boot-image-test-build     构建 LOAD_IMAGE 全量读回 firmware/asset"
	@echo "  make boot-image-test-load PORT=COM8  上传并显示正确性/吞吐结果"
	@echo "  make bad-apple-build           构建保留的 BAM1 仿真原型与媒体预览"
	@echo "  make bad-apple-load PORT=COM8  重 VGA 资源实验入口（LX9 已知 overmap）"
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
	@echo "  make perf / make benchmark     跑完整双核 benchmark，并生成日志、表格和环境快照"
	@echo "  make ise-export ISE_TARGET=minisoc   导出 ISE 工程所需文件到新目录"

check-env:
	"$(CHECK_ENV)"

firmware:
	FIRMWARE_PROFILE="$(FIRMWARE_PROFILE)" \
		FIRMWARE_MAIN="$(FIRMWARE_MAIN)" \
		"$(BUILD_FIRMWARE)"

timer-irq-smoke:
	FIRMWARE_PROFILE=dark_irq \
		FIRMWARE_MAIN="$(REPO_ROOT)/firmware/tests/timer_irq_smoke.c" \
		FIRMWARE_OUT="$(TIMER_IRQ_FIRMWARE_OUT)" \
		"$(BUILD_FIRMWARE)"

bootload:
	@if [ -z "$(PORT)" ]; then echo "用法：make bootload PORT=COM8" >&2; exit 1; fi
	@if ! command -v wslpath >/dev/null 2>&1; then echo "bootload 需要在 WSL 中运行" >&2; exit 1; fi
	@if ! command -v "$(WINDOWS_PYTHON)" >/dev/null 2>&1; then echo "找不到 Windows Python：$(WINDOWS_PYTHON)" >&2; exit 1; fi
	@FIRMWARE_PROFILE="$(FIRMWARE_PROFILE)" \
		FIRMWARE_MAIN="$(FIRMWARE_MAIN)" \
		FIRMWARE_OUT="$(BOOTLOAD_FIRMWARE_OUT)" \
		"$(BUILD_FIRMWARE)"
	"$(WINDOWS_PYTHON)" "$$(wslpath -w "$(UART_LOADER)")" \
		--port "$(PORT)" \
		--baud "$(BOOTLOAD_BAUD)" \
		--input "$$(wslpath -w "$(BOOTLOAD_FIRMWARE_OUT).bin")" \
		--monitor

timer-irq-load:
	@$(MAKE) bootload PORT="$(PORT)" \
		FIRMWARE_PROFILE=dark_irq \
		FIRMWARE_MAIN="$(REPO_ROOT)/firmware/tests/timer_irq_smoke.c"

boot-image-test-build:
	python3 "$(REPO_ROOT)/scripts/make_boot_image_test_asset.py" \
		--data-bytes "$(DATA_BYTES)" --seed "$(SEED)" \
		--output "$(BOOT_IMAGE_TEST_ASSET)"
	FIRMWARE_MAIN="$(REPO_ROOT)/firmware/tests/boot_image_verify.c" \
		FIRMWARE_OUT="$(BOOT_IMAGE_TEST_FIRMWARE_OUT)" "$(BUILD_FIRMWARE)"

boot-image-test-load: boot-image-test-build
	@if [ -z "$(PORT)" ]; then echo "用法：make boot-image-test-load PORT=COM8" >&2; exit 1; fi
	@if ! command -v wslpath >/dev/null 2>&1; then echo "boot-image-test-load 需要在 WSL 中运行" >&2; exit 1; fi
	@if ! command -v "$(WINDOWS_PYTHON)" >/dev/null 2>&1; then echo "找不到 Windows Python：$(WINDOWS_PYTHON)" >&2; exit 1; fi
	"$(WINDOWS_PYTHON)" "$$(wslpath -w "$(UART_LOADER)")" \
		--port "$(PORT)" \
		--baud "$(BOOTLOAD_BAUD)" \
		--input "$$(wslpath -w "$(BOOT_IMAGE_TEST_FIRMWARE_OUT).bin")" \
		--sdram-input "$$(wslpath -w "$(BOOT_IMAGE_TEST_ASSET)")" \
		--sdram-address 0x81000000 \
		--monitor

bad-apple-build:
	python3 "$(REPO_ROOT)/scripts/make_bad_apple_minimal_asset.py" \
		--video "$(BAD_APPLE_VIDEO)" --midi "$(BAD_APPLE_MIDI)" \
		--start 30 --duration 20 \
		--output "$(BAD_APPLE_ASSET)" --preview "$(BAD_APPLE_PREVIEW)" \
		--report "$(BAD_APPLE_REPORT)"
	FIRMWARE_MAIN="$(REPO_ROOT)/firmware/tests/bad_apple_minimal.c" \
		FIRMWARE_OUT="$(BAD_APPLE_FIRMWARE_OUT)" "$(BUILD_FIRMWARE)"

bad-apple-load: bad-apple-build
	@if [ -z "$(PORT)" ]; then echo "用法：make bad-apple-load PORT=COM8" >&2; exit 1; fi
	@if ! command -v wslpath >/dev/null 2>&1; then echo "bad-apple-load 需要在 WSL 中运行" >&2; exit 1; fi
	@if ! command -v "$(WINDOWS_PYTHON)" >/dev/null 2>&1; then echo "找不到 Windows Python：$(WINDOWS_PYTHON)" >&2; exit 1; fi
	"$(WINDOWS_PYTHON)" "$$(wslpath -w "$(UART_LOADER)")" \
		--port "$(PORT)" \
		--baud "$(BOOTLOAD_BAUD)" \
		--input "$$(wslpath -w "$(BAD_APPLE_FIRMWARE_OUT).bin")" \
		--sdram-input "$$(wslpath -w "$(BAD_APPLE_ASSET)")" \
		--sdram-address 0x81000000 \
		--monitor

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

perf: benchmark

benchmark: rtl-syntax
	"$(REPO_ROOT)/scripts/run_benchmarks.sh"

ISE_TARGET ?= minisoc
ISE_EXPORT_DIR ?= $(REPO_ROOT)/build/ise-export/$(ISE_TARGET)

ise-export:
	"$(EXPORT_ISE_PROJECT)" "$(ISE_TARGET)" "$(ISE_EXPORT_DIR)"
