# TecPlusRV 第一版骨架实现计划

> **给执行型 agent：** 必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans` 按任务逐步实现。步骤使用复选框 `- [ ]` 跟踪。

**目标：** 构建 TecPlusRV 第一版工程骨架，并补齐本地仿真/构建支持以及实验室验证边界说明。

**架构：** 用独立 probe 顶层做最早期板级验证；用一个小型可复用 UART 外设作为公共模块；用最小 SoC 占位件为后续集成留口；用面向既定 MMIO 地址图的裸机 firmware 骨架承接本地验证。

**技术栈：** Verilog-2001、UCF、shell 脚本、Python 3、RISC-V bare-metal GCC、Icarus Verilog

---

### 任务 1：创建目录结构和基础文档

**文件：**
- 新建：`README.md`
- 新建：`docs/PROJECT_SPEC.md`
- 新建：`docs/PROBES.md`
- 新建：`docs/MEMORY_MAP.md`
- 新建：`rtl/core/.gitkeep`
- 新建：`rtl/soc/.gitkeep`
- 新建：`rtl/periph/.gitkeep`
- 新建：`rtl/accel/.gitkeep`
- 新建：`rtl/probe/.gitkeep`
- 新建：`constraints/.gitkeep`
- 新建：`firmware/drivers/.gitkeep`
- 新建：`firmware/tests/.gitkeep`
- 新建：`sim/.gitkeep`
- 新建：`scripts/.gitkeep`

- [ ] 写清第一版范围、探针目标、MMIO 地址图、本地/实验室验证边界，以及 PicoRV32 的 vendoring 方式。
- [ ] 对照 `docs/项目任务说明 v2.md` 和 TEC-PLUS 的 Markdown 文档，回查引脚、板卡资源和范围限制是否一致。

### 任务 2：加入 probe 和 UART 外设 RTL，以及 UART testbench

**文件：**
- 新建：`rtl/probe/probe_led_key_top.v`
- 新建：`rtl/periph/uart_tx.v`
- 新建：`rtl/probe/probe_uart_top.v`
- 新建：`constraints/tecplus_led_key.ucf`
- 新建：`constraints/tecplus_uart.ucf`
- 新建：`sim/tb_uart_tx.v`
- 新建：`sim/run_sim.sh`

- [ ] 增加一个可综合的 LED/KEY 探针：reset 时灭灯，50MHz 下跑马灯，`KEY1` 改速度，`KEY2` 通过边沿触发切固定模式。
- [ ] 增加一个参数化 8N1 UART TX，接口采用 ready/valid 风格，并提供一个周期性发送 `Hello TecPlusRV\r\n` 的顶层。
- [ ] 增加一个小型 UART testbench，生成 VCD，并在至少发完一帧后自动结束。
- [ ] 让 `sim/run_sim.sh` 在运行前检查 `iverilog` 和 `vvp` 是否存在。

### 任务 3：加入最小 SoC 占位模块

**文件：**
- 新建：`rtl/soc/tinybus_defs.vh`
- 新建：`rtl/soc/tinybus_decode.v`
- 新建：`rtl/soc/bram.v`
- 新建：`rtl/soc/mmio_test_exit.v`
- 新建：`sim/tb_minisoc.v`

- [ ] 用单独头文件统一记录任务说明中的 MMIO 地址。
- [ ] 增加一个简单占位译码器，为 GPIO、UART、计数器和 `test_exit` 提供地址匹配输出。
- [ ] 增加支持同步读写、并允许 `$readmemh` 初始化的 BRAM。
- [ ] 增加 `test_exit` 寄存器模块和一个 MiniSoC testbench 骨架：PicoRV32 缺失时输出 `SKIP`，存在时观察 `PASS / FAIL / TIMEOUT`。

### 任务 4：加入 firmware 和构建辅助脚本

**文件：**
- 新建：`firmware/drivers/mmio.h`
- 新建：`firmware/drivers/uart.h`
- 新建：`firmware/drivers/uart.c`
- 新建：`firmware/drivers/gpio.h`
- 新建：`firmware/drivers/gpio.c`
- 新建：`firmware/main.c`
- 新建：`firmware/linker.ld`
- 新建：`firmware/startup.S`
- 新建：`scripts/build_firmware.sh`
- 新建：`scripts/bin2mem.py`

- [ ] 提供一个最小 RV32I 裸机启动路径和面向 BRAM 启动区的链接布局。
- [ ] 加入和地址图一致的 MMIO 辅助函数和小型驱动桩。
- [ ] 让 firmware 至少完成写 LED、保留 UART 输出路径、最后写 `test_exit = 1`。
- [ ] 让构建脚本生成 `firmware.elf`、`firmware.bin`、`firmware.mem`，并在缺工具时给出明确错误。

### 任务 5：本地环境搭建与验证

**文件：**
- 修改：`README.md`
- 修改：`sim/run_sim.sh`
- 修改：`scripts/build_firmware.sh`

- [ ] 运行 firmware 构建脚本，确认本地能生成 ELF、BIN、MEM。
- [ ] 如果 Icarus 已安装，则运行 UART 仿真；如果没装，则确认脚本会明确报缺工具。
- [ ] 运行 MiniSoC testbench 的当前 skip/占位路径。
- [ ] 在 README 中写清本地命令，以及实验室优先的板级验证顺序。
