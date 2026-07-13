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
WINDOWS_GDB ?= riscv-none-elf-gdb.exe
BOOTLOAD_BAUD ?= 9600
BOOTLOAD_MONITOR_ARG ?= --monitor
FIRMWARE_PROFILE ?= baremetal
FIRMWARE_RUNTIME ?=
FIRMWARE_DEBUG ?= none
FIRMWARE_MAIN ?= $(REPO_ROOT)/firmware/main.c
GDB_STUB_MAIN ?= $(REPO_ROOT)/firmware/tests/gdb_stub_smoke.c
APP ?=
BOOTLOAD_FIRMWARE_OUT := $(REPO_ROOT)/firmware/build/bootload/firmware
BAD_APPLE_FIRMWARE_OUT := $(REPO_ROOT)/firmware/build/bad_apple_minimal
BAD_APPLE_ASSET := $(REPO_ROOT)/build/badapple/bad_apple_20s.bin
BAD_APPLE_PREVIEW := $(REPO_ROOT)/build/badapple/bad_apple_20s.gif
BAD_APPLE_REPORT := $(REPO_ROOT)/build/badapple/bad_apple_20s.json
BAD_APPLE_VIDEO := $(REPO_ROOT)/firmware/assets/bad-apple.mp4
BAD_APPLE_LEGACY_MIDI := $(REPO_ROOT)/firmware/assets/badapple-midifull.mid
BAD_APPLE_FULL_FIRMWARE_OUT := $(REPO_ROOT)/firmware/build/freertos/bad_apple_full/firmware
BAD_APPLE_FULL_DIR := $(REPO_ROOT)/build/badapple_full
BAD_APPLE_FULL_ASSET := $(BAD_APPLE_FULL_DIR)/bad_apple_full.bin
BAD_APPLE_FULL_MEM := $(BAD_APPLE_FULL_DIR)/bad_apple_full.mem
BAD_APPLE_FULL_REPORT := $(BAD_APPLE_FULL_DIR)/bad_apple_full.json
BAD_APPLE_FULL_PREVIEW := $(BAD_APPLE_FULL_DIR)/bad_apple_full_preview.mp4
BAD_APPLE_FULL_PREVIEW_AUDIO := $(BAD_APPLE_FULL_DIR)/bad_apple_full_preview.wav
BAD_APPLE_SOURCE_AUDIO_PREVIEW := $(BAD_APPLE_FULL_DIR)/bad_apple_source_pitch_preview.wav
BAD_APPLE_SOURCE_AUDIO_REPORT := $(BAD_APPLE_FULL_DIR)/bad_apple_source_pitch_preview.json
BAD_APPLE_COMPACT_MIDI := $(REPO_ROOT)/firmware/assets/touhou-bad-apple-featnomico-26035-nonstop2k.com.mid
BAD_APPLE_WINDOW_DIR := $(REPO_ROOT)/build/badapple_window
BAD_APPLE_WINDOW_ASSET := $(BAD_APPLE_WINDOW_DIR)/bad_apple_window.bin
BAD_APPLE_WINDOW_REPORT := $(BAD_APPLE_WINDOW_DIR)/bad_apple_window.json
BAD_APPLE_WINDOW_PREVIEW := $(BAD_APPLE_WINDOW_DIR)/bad_apple_window_preview.mp4
BAD_APPLE_WINDOW_PREVIEW_AUDIO := $(BAD_APPLE_WINDOW_DIR)/bad_apple_window_preview.wav
BAD_APPLE_WINDOW_FIRMWARE_OUT := $(REPO_ROOT)/firmware/build/freertos/bad_apple_window/firmware
BOOT_IMAGE_TEST_FIRMWARE_OUT := $(REPO_ROOT)/firmware/build/boot_image_verify
BOOT_IMAGE_TEST_ASSET := $(REPO_ROOT)/build/bootloader-test/pattern.bin
TIMER_IRQ_FIRMWARE_OUT := $(REPO_ROOT)/firmware/build/timer_irq_smoke
FREERTOS_SMOKE_FIRMWARE_OUT := $(REPO_ROOT)/firmware/build/freertos/smoke/firmware
FREERTOS_QUEUE_FIRMWARE_OUT := $(REPO_ROOT)/firmware/build/freertos/queue/firmware
FREERTOS_ACCEPTANCE_FIRMWARE_OUT := $(REPO_ROOT)/firmware/build/freertos/acceptance/firmware
DATA_BYTES ?= 65536
SEED ?= 0x12345678
START ?= 100
DURATION ?= 40

ifneq ($(strip $(APP)),)
APP_INPUT := $(patsubst firmware/apps/%,%,$(strip $(APP)))
APP_KIND := $(firstword $(subst /, ,$(APP_INPUT)))
APP_CANDIDATE := $(REPO_ROOT)/firmware/apps/$(APP_INPUT)
APP_SOURCE := $(realpath $(APP_CANDIDATE))
APP_ROOT := $(realpath $(REPO_ROOT)/firmware/apps)

ifeq ($(APP_KIND),baremetal)
APP_RUNTIME := baremetal
else ifeq ($(APP_KIND),irq)
APP_RUNTIME := irq
else ifeq ($(APP_KIND),freertos)
APP_RUNTIME := freertos
else ifneq ($(filter ../% /%,$(APP_INPUT)),)
$(error APP 必须位于 firmware/apps/baremetal、irq 或 freertos 目录)
else
$(error 未知 APP 运行模型：$(APP_KIND))
endif

ifeq ($(APP_SOURCE),)
$(error 找不到 APP 文件：$(APP_CANDIDATE))
endif
ifneq ($(filter $(APP_ROOT)/%,$(APP_SOURCE)),$(APP_SOURCE))
$(error APP 必须位于 firmware/apps/baremetal、irq 或 freertos 目录)
endif
APP_IS_FILE := $(shell test -f "$(APP_SOURCE)" && echo yes)
ifneq ($(APP_IS_FILE),yes)
$(error APP 必须是普通 .c 文件：$(APP_SOURCE))
endif
ifneq ($(suffix $(APP_SOURCE)),.c)
$(error APP 必须是 .c 文件：$(APP_SOURCE))
endif
endif

SELECTED_FIRMWARE_PROFILE := $(if $(strip $(APP)),,$(FIRMWARE_PROFILE))
SELECTED_FIRMWARE_RUNTIME := $(if $(strip $(APP)),$(APP_RUNTIME),$(FIRMWARE_RUNTIME))
SELECTED_FIRMWARE_MAIN := $(if $(strip $(APP)),$(APP_SOURCE),$(FIRMWARE_MAIN))

.PHONY: help check-env firmware firmware-load firmware-debug timer-irq-smoke timer-irq-load freertos-smoke freertos-queue freertos-acceptance freertos-load freertos-acceptance-load bootload gdb-stub-load gdb-stub-debug boot-image-test-build boot-image-test-load bad-apple-build bad-apple-load bad-apple-full-build bad-apple-full-preview bad-apple-source-audio-preview bad-apple-compact-midi-preview bad-apple-full-load bad-apple-window-build bad-apple-window-preview bad-apple-window-load rtl-syntax sim test-probe test-platform test-soc test-smoke test-freertos test-dual-core test-all ci ci-full perf benchmark board-benchmark ise-export

help:
	@echo "常用目标："
	@echo "  make check-env                 检查本地工具链"
	@echo "  make firmware                  构建手动默认 firmware 镜像"
	@echo "  make firmware APP=baremetal/hello.c  按 apps 目录构建用户程序"
	@echo "  make firmware-load APP=... PORT=COM8 构建、上传并监视用户程序"
	@echo "  make firmware-debug APP=baremetal/... PORT=COM8  启动 Windows GDB"
	@echo "  make firmware FIRMWARE_OUT=... 构建到指定输出前缀"
	@echo "  make timer-irq-smoke           构建 DarkRISCV timer IRQ 专用镜像"
	@echo "  make timer-irq-load PORT=COM8  构建、上传并监视 timer IRQ 验收镜像"
	@echo "  make freertos-smoke           构建 50 MHz FreeRTOS timer smoke 镜像"
	@echo "  make freertos-queue           构建 50 MHz FreeRTOS 静态 queue 镜像"
	@echo "  make freertos-acceptance      构建 50 MHz FreeRTOS SDRAM 综合验收镜像"
	@echo "  make freertos-load PORT=COM8  构建、上传并监视 FreeRTOS smoke 镜像"
	@echo "  make freertos-acceptance-load PORT=COM8  上传并监视综合验收镜像"
	@echo "  make bootload PORT=COM8        构建、上传并进入 serial monitor"
	@echo "  make gdb-stub-load PORT=COM8   复用 bootloader 上传 GDB stub 并释放串口"
	@echo "  make gdb-stub-debug PORT=COM8  上传后启动 Windows GDB 并连接 COM 口"
	@echo "  make boot-image-test-build     构建 LOAD_IMAGE 全量读回 firmware/asset"
	@echo "  make boot-image-test-load PORT=COM8  上传并显示正确性/吞吐结果"
	@echo "  make bad-apple-build           构建保留的 BAM1 仿真原型与媒体预览"
	@echo "  make bad-apple-load PORT=COM8  重 VGA 资源实验入口（LX9 已知 overmap）"
	@echo "  make bad-apple-full-build      构建完整 219 秒 BAM2 与 FreeRTOS player"
	@echo "  make bad-apple-full-preview    由最终 BAM2 生成带模拟 buzzer 音频的 MP4"
	@echo "  make bad-apple-source-audio-preview  从 MP4 音轨提取单音 pitch WAV"
	@echo "  make bad-apple-compact-midi-preview  试听新增两轨 MIDI 的旋律/click 归约"
	@echo "  make bad-apple-full-load PORT=COM8 [BRAM_ONLY=1]  上传正式 player，可复用板上 asset"
	@echo "  make bad-apple-window-load PORT=COM8 START=100 DURATION=40  快速复现指定原片窗口"
	@echo "  make rtl-syntax                跑 RTL 语法 smoke"
	@echo "  make sim TARGET=minisoc_pico   单独运行一个仿真目标"
	@echo "  make test-probe                跑探针类仿真"
	@echo "  make test-platform             跑平台层仿真"
	@echo "  make test-soc                  跑 MiniSoC 通用 regression / 专项仿真"
	@echo "  make test-smoke                跑当前分支的基础 smoke 与 board-top smoke"
	@echo "  make test-freertos             跑 FreeRTOS build/port/demo 自动回归"
	@echo "  make test-dual-core            跑双核 regression（如果当前分支提供）"
	@echo "  make test-all                  跑全部正确性检查"
	@echo "  make ci                        push/PR 快速 CI，跳过分钟级长仿真"
	@echo "  make ci-full                   手动完整 CI，运行 all suite"
	@echo "  python3 scripts/test_runner.py list   列出 catalog 里的 suite / case"
	@echo "  make perf / make benchmark     跑完整双核 benchmark，并生成日志、表格和环境快照"
	@echo "  make board-benchmark PORT=COM9 BOOTLOAD_BAUD=115200  上板运行性能测试"
	@echo "  make ise-export ISE_TARGET=minisoc   导出 ISE 工程所需文件到新目录"

check-env:
	"$(CHECK_ENV)"

firmware:
	FIRMWARE_PROFILE="$(SELECTED_FIRMWARE_PROFILE)" \
		FIRMWARE_RUNTIME="$(SELECTED_FIRMWARE_RUNTIME)" \
		FIRMWARE_DEBUG="$(FIRMWARE_DEBUG)" \
		FIRMWARE_MAIN="$(SELECTED_FIRMWARE_MAIN)" \
		"$(BUILD_FIRMWARE)"

firmware-load:
	$(if $(APP),,$(error firmware-load 需要 APP，例如 APP=baremetal/hello.c))
	$(if $(PORT),,$(error firmware-load 需要 PORT，例如 PORT=COM8))
	@$(MAKE) bootload PORT="$(PORT)" \
		FIRMWARE_PROFILE= \
		FIRMWARE_RUNTIME="$(APP_RUNTIME)" \
		FIRMWARE_MAIN="$(APP_SOURCE)"

firmware-debug:
	$(if $(APP),,$(error firmware-debug 需要 APP，例如 APP=baremetal/hello.c))
	$(if $(PORT),,$(error firmware-debug 需要 PORT，例如 PORT=COM8))
	$(if $(filter baremetal,$(APP_RUNTIME)),,$(error 当前 GDB 调试尚不支持 $(APP_RUNTIME) 应用))
	@$(MAKE) gdb-stub-debug PORT="$(PORT)" GDB_STUB_MAIN="$(APP_SOURCE)"

timer-irq-smoke:
	FIRMWARE_PROFILE=dark_irq \
		FIRMWARE_MAIN="$(REPO_ROOT)/firmware/tests/timer_irq_smoke.c" \
		FIRMWARE_OUT="$(TIMER_IRQ_FIRMWARE_OUT)" \
		"$(BUILD_FIRMWARE)"

freertos-smoke:
	FIRMWARE_PROFILE=freertos \
		FREERTOS_CPU_CLOCK_HZ=50000000 \
		FIRMWARE_MAIN="$(REPO_ROOT)/firmware/tests/freertos_smoke.c" \
		FIRMWARE_OUT="$(FREERTOS_SMOKE_FIRMWARE_OUT)" \
		"$(BUILD_FIRMWARE)"

freertos-queue:
	FIRMWARE_PROFILE=freertos \
		FREERTOS_CPU_CLOCK_HZ=50000000 \
		FIRMWARE_MAIN="$(REPO_ROOT)/firmware/tests/freertos_queue.c" \
		FIRMWARE_OUT="$(FREERTOS_QUEUE_FIRMWARE_OUT)" \
		"$(BUILD_FIRMWARE)"

freertos-acceptance:
	FIRMWARE_PROFILE=freertos \
		FREERTOS_CPU_CLOCK_HZ=50000000 \
		FIRMWARE_MAIN="$(REPO_ROOT)/firmware/tests/freertos_acceptance.c" \
		FIRMWARE_OUT="$(FREERTOS_ACCEPTANCE_FIRMWARE_OUT)" \
		"$(BUILD_FIRMWARE)"

bootload:
	@if [ -z "$(PORT)" ]; then echo "用法：make bootload PORT=COM8" >&2; exit 1; fi
	@if ! command -v wslpath >/dev/null 2>&1; then echo "bootload 需要在 WSL 中运行" >&2; exit 1; fi
	@if ! command -v "$(WINDOWS_PYTHON)" >/dev/null 2>&1; then echo "找不到 Windows Python：$(WINDOWS_PYTHON)" >&2; exit 1; fi
	@FIRMWARE_PROFILE="$(FIRMWARE_PROFILE)" \
		FIRMWARE_RUNTIME="$(FIRMWARE_RUNTIME)" \
		FIRMWARE_DEBUG="$(FIRMWARE_DEBUG)" \
		FIRMWARE_MAIN="$(FIRMWARE_MAIN)" \
		FIRMWARE_OUT="$(BOOTLOAD_FIRMWARE_OUT)" \
		"$(BUILD_FIRMWARE)"
	PYTHONUTF8=1 PYTHONIOENCODING=utf-8 \
		"$(WINDOWS_PYTHON)" "$$(wslpath -w "$(UART_LOADER)")" \
		--port "$(PORT)" \
		--baud "$(BOOTLOAD_BAUD)" \
		--input "$$(wslpath -w "$(BOOTLOAD_FIRMWARE_OUT).bin")" $(BOOTLOAD_MONITOR_ARG)

gdb-stub-load:
	@$(MAKE) bootload PORT="$(PORT)" \
		FIRMWARE_PROFILE=gdb_stub \
		FIRMWARE_MAIN="$(GDB_STUB_MAIN)" \
		BOOTLOAD_MONITOR_ARG=

gdb-stub-debug: gdb-stub-load
	@if ! command -v "$(WINDOWS_GDB)" >/dev/null 2>&1; then echo "找不到 Windows GDB：$(WINDOWS_GDB)" >&2; exit 1; fi
	"$(WINDOWS_GDB)" "$$(wslpath -w "$(BOOTLOAD_FIRMWARE_OUT).elf")" \
		-ex "set serial baud $(BOOTLOAD_BAUD)" \
		-ex "set substitute-path $(REPO_ROOT) $$(wslpath -m "$(REPO_ROOT)")" \
		-ex "target remote $(PORT)"

timer-irq-load:
	@$(MAKE) bootload PORT="$(PORT)" \
		FIRMWARE_PROFILE=dark_irq \
		FIRMWARE_MAIN="$(REPO_ROOT)/firmware/tests/timer_irq_smoke.c"

freertos-load:
	@$(MAKE) bootload PORT="$(PORT)" \
		FIRMWARE_PROFILE=freertos \
		FIRMWARE_MAIN="$(REPO_ROOT)/firmware/tests/freertos_smoke.c"

freertos-acceptance-load:
	@$(MAKE) bootload PORT="$(PORT)" \
		FIRMWARE_PROFILE=freertos \
		FIRMWARE_MAIN="$(REPO_ROOT)/firmware/tests/freertos_acceptance.c"

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
		--video "$(BAD_APPLE_VIDEO)" --midi "$(BAD_APPLE_LEGACY_MIDI)" \
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

bad-apple-full-build:
	python3 "$(REPO_ROOT)/scripts/make_bad_apple_full_asset.py" \
		--video "$(BAD_APPLE_VIDEO)" --midi "$(BAD_APPLE_COMPACT_MIDI)" \
		--midi-mode compact-piano --midi-time-scale 1.0 --midi-tail-align 217.080 \
		--transpose -12 \
		--output "$(BAD_APPLE_FULL_ASSET)" --mem "$(BAD_APPLE_FULL_MEM)" \
		--report "$(BAD_APPLE_FULL_REPORT)"
	FIRMWARE_PROFILE=freertos FREERTOS_CPU_CLOCK_HZ=50000000 \
		FIRMWARE_MAIN="$(REPO_ROOT)/firmware/tests/bad_apple_full.c" \
		FIRMWARE_OUT="$(BAD_APPLE_FULL_FIRMWARE_OUT)" "$(BUILD_FIRMWARE)"

bad-apple-full-preview: bad-apple-full-build
	python3 "$(REPO_ROOT)/scripts/make_bad_apple_full_asset.py" \
		--preview-input "$(BAD_APPLE_FULL_ASSET)" \
		--preview "$(BAD_APPLE_FULL_PREVIEW)" \
		--preview-audio "$(BAD_APPLE_FULL_PREVIEW_AUDIO)"

bad-apple-source-audio-preview:
	python3 "$(REPO_ROOT)/scripts/make_bad_apple_source_audio.py" \
		--video "$(BAD_APPLE_VIDEO)" \
		--output "$(BAD_APPLE_SOURCE_AUDIO_PREVIEW)" \
		--report "$(BAD_APPLE_SOURCE_AUDIO_REPORT)"

bad-apple-compact-midi-preview: bad-apple-full-preview
	@echo "兼容别名：正式 bad-apple-full-preview 已使用 compact-piano MIDI 路径"

bad-apple-full-load: bad-apple-full-build
	@if [ -z "$(PORT)" ]; then echo "用法：make bad-apple-full-load PORT=COM8" >&2; exit 1; fi
	@if ! command -v wslpath >/dev/null 2>&1; then echo "bad-apple-full-load 需要在 WSL 中运行" >&2; exit 1; fi
	@if ! command -v "$(WINDOWS_PYTHON)" >/dev/null 2>&1; then echo "找不到 Windows Python：$(WINDOWS_PYTHON)" >&2; exit 1; fi
	"$(WINDOWS_PYTHON)" "$$(wslpath -w "$(UART_LOADER)")" \
		--port "$(PORT)" --baud "$(BOOTLOAD_BAUD)" \
		--input "$$(wslpath -w "$(BAD_APPLE_FULL_FIRMWARE_OUT).bin")" \
		$(if $(filter 1,$(BRAM_ONLY)),,--sdram-input "$$(wslpath -w "$(BAD_APPLE_FULL_ASSET)")" --sdram-address 0x81000000) \
		--monitor

bad-apple-window-build:
	python3 "$(REPO_ROOT)/scripts/make_bad_apple_full_asset.py" \
		--video "$(BAD_APPLE_VIDEO)" --midi "$(BAD_APPLE_COMPACT_MIDI)" \
		--midi-mode compact-piano --midi-time-scale 1.0 --midi-tail-align 217.080 \
		--transpose -12 --start "$(START)" --duration "$(DURATION)" \
		--output "$(BAD_APPLE_WINDOW_ASSET)" --report "$(BAD_APPLE_WINDOW_REPORT)"
	FIRMWARE_PROFILE=freertos FREERTOS_CPU_CLOCK_HZ=50000000 \
		FIRMWARE_MAIN="$(REPO_ROOT)/firmware/tests/bad_apple_full.c" \
		FIRMWARE_OUT="$(BAD_APPLE_WINDOW_FIRMWARE_OUT)" "$(BUILD_FIRMWARE)"

bad-apple-window-preview: bad-apple-window-build
	python3 "$(REPO_ROOT)/scripts/make_bad_apple_full_asset.py" \
		--preview-input "$(BAD_APPLE_WINDOW_ASSET)" \
		--preview "$(BAD_APPLE_WINDOW_PREVIEW)" \
		--preview-audio "$(BAD_APPLE_WINDOW_PREVIEW_AUDIO)"

bad-apple-window-load: bad-apple-window-build
	@if [ -z "$(PORT)" ]; then echo "用法：make bad-apple-window-load PORT=COM8 START=100 DURATION=40" >&2; exit 1; fi
	@if ! command -v wslpath >/dev/null 2>&1; then echo "bad-apple-window-load 需要在 WSL 中运行" >&2; exit 1; fi
	@if ! command -v "$(WINDOWS_PYTHON)" >/dev/null 2>&1; then echo "找不到 Windows Python：$(WINDOWS_PYTHON)" >&2; exit 1; fi
	"$(WINDOWS_PYTHON)" "$$(wslpath -w "$(UART_LOADER)")" \
		--port "$(PORT)" --baud "$(BOOTLOAD_BAUD)" \
		--input "$$(wslpath -w "$(BAD_APPLE_WINDOW_FIRMWARE_OUT).bin")" \
		--sdram-input "$$(wslpath -w "$(BAD_APPLE_WINDOW_ASSET)")" \
		--sdram-address 0x81000000 --monitor

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

test-freertos:
	$(TEST_RUNNER) run-suite freertos

test-dual-core:
	$(TEST_RUNNER) run-suite dual_core

test-all:
	$(TEST_RUNNER) run-suite all

ci:
	$(TEST_RUNNER) run-suite ci --keep-going

ci-full:
	$(TEST_RUNNER) run-suite all --keep-going

perf: benchmark

benchmark: rtl-syntax
	"$(REPO_ROOT)/scripts/run_benchmarks.sh"

board-benchmark:
	"$(REPO_ROOT)/scripts/run_board_benchmarks.sh"

ISE_TARGET ?= minisoc
ISE_EXPORT_DIR ?= $(REPO_ROOT)/build/ise-export/$(ISE_TARGET)

ise-export:
	"$(EXPORT_ISE_PROJECT)" "$(ISE_TARGET)" "$(ISE_EXPORT_DIR)"
