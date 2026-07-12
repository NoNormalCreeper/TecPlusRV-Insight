# Firmware 编译、上传与调试指南

这份文档是 TecPlusRV firmware 的统一用户入口。用户程序放在正确的 `firmware/apps/` 子目录后，只需要选择源文件；构建系统会根据目录决定是否链接 IRQ runtime 或 FreeRTOS。

## 1. 选择应用目录

```text
firmware/apps/
├── baremetal/  # 普通裸机程序
├── irq/        # DarkRISCV machine IRQ 程序
└── freertos/   # DarkRISCV FreeRTOS 程序
```

目录表达程序自身的运行模型：

| 目录 | 适用程序 | 构建内容 |
| --- | --- | --- |
| `baremetal/` | 轮询、MMIO、简单主循环 | startup、基础 runtime、drivers |
| `irq/` | 自己处理 machine timer/trap | bare-metal + canonical trap frame + machine timer |
| `freertos/` | 创建 task、queue、timer | FreeRTOS kernel + TecPlusRV port + machine timer |

GDB 不是第四个目录。它是调试 `baremetal/` 应用的一种启动方式。

现有最小示例：

```text
firmware/apps/baremetal/hello.c
firmware/apps/irq/timer_demo.c
firmware/apps/freertos/queue_demo.c
```

## 2. 编译

普通 bare-metal：

```bash
make firmware APP=baremetal/hello.c
```

IRQ 应用：

```bash
make firmware APP=irq/timer_demo.c
```

FreeRTOS 应用：

```bash
make firmware APP=freertos/queue_demo.c
```

也可以写完整仓库相对路径：

```bash
make firmware APP=firmware/apps/baremetal/hello.c
```

没有 `APP` 时，旧入口保持不变：

```bash
make firmware
```

它仍然构建 `firmware/main.c`。

### 产物

默认输出：

```text
firmware/build/firmware.elf
firmware/build/firmware.bin
firmware/build/firmware.mem
firmware/build/firmware.lst
```

| 文件 | 用途 |
| --- | --- |
| `.elf` | symbol、DWARF、section 和 GDB 输入 |
| `.bin` | Bootloader 实际上传的 BRAM image |
| `.mem` | Verilog `$readmemh` 仿真初始化 |
| `.lst` | 反汇编与地址定位 |

指定隔离输出前缀：

```bash
make firmware \
  APP=baremetal/hello.c \
  FIRMWARE_OUT=firmware/build/manual/hello/firmware
```

## 3. 上传并监视

FPGA 需要已经烧录带 Bootloader 的 MiniSoC bitstream。WSL 中执行：

```bash
make firmware-load \
  APP=baremetal/hello.c \
  PORT=COM8 \
  BOOTLOAD_BAUD=115200
```

运行流程：

```text
WSL 编译 firmware
-> Windows py.exe 打开 COM8
-> 按下并松开 RESET
-> Bootloader 返回 READY
-> 上传 firmware.bin
-> 收到 ACK，CPU 运行
-> serial monitor 显示应用 UART 输出
```

`BOOTLOAD_BAUD` 必须与当前 bitstream 的 `UART_BAUD` 一致。它是硬件参数，不由应用目录推断。

IRQ 和 FreeRTOS 应用使用同一个入口：

```bash
make firmware-load APP=irq/timer_demo.c PORT=COM8 BOOTLOAD_BAUD=115200
make firmware-load APP=freertos/queue_demo.c PORT=COM8 BOOTLOAD_BAUD=115200
```

完整 Windows Python、pyserial、COM 口和 usbipd 说明见 [Windows + WSL2 串口下载](WINDOWS_WSL_UART.md)。Bootloader wire protocol 见 [UART Bootloader v1](BOOTLOADER_PROTOCOL.md)。

## 4. 用 GDB 调试

当前 GDB 只支持 `baremetal/` 应用：

```bash
make firmware-debug \
  APP=baremetal/hello.c \
  PORT=COM8 \
  BOOTLOAD_BAUD=115200
```

它会自动：

1. 以 GDB debug 方式构建同一个应用；
2. 通过原有 Bootloader 上传；
3. 收到 ACK 后释放 COM 口；
4. 启动 Windows `riscv-none-elf-gdb.exe`；
5. 加载同一次构建的 ELF；
6. 设置 WSL/Windows source path mapping；
7. 连接 COM 口。

用户程序不需要调用 `trap_init()`。GDB build 会在进入用户 `main()` 前自动安装 trap 并首次停住。

连接后可以尝试：

```gdb
info registers
list main
p/x hello_value
x/8wx 0x80000000
continue
```

### 放置后续 cooperative breakpoint

当前还没有动态 `Z0/z0` breakpoint 和 single-step。需要在后续位置停住时，使用公共接口：

```c
#include "runtime/debug.h"

int main(void)
{
    initialize_hardware();
    DEBUG_BREAK();
    run_application();
}
```

`DEBUG_BREAK()` 的语义：

- `firmware-debug`：进入 GDB stub；
- 普通 `make firmware` 或 `firmware-load`：no-op。

应用不应直接包含 `gdb/gdb_stub.h`，也不需要判断 `GDB_STUB_ACTIVE`。

### 当前 GDB 边界

当前不支持：

- 调试 `irq/` 或 `freertos/` 应用；
- 运行中异步 Ctrl-C；
- single-step、`step`、`next`；
- `Z0/z0` 动态软件断点；
- hardware breakpoint/watchpoint；
- FreeRTOS task/thread 枚举；
- 用户程序直接向 GDB UART 输出普通文本。

GDB session 期间 UART 归 RSP 独占。不要调用最终写入 `uart_putc()` 的日志函数；先把状态放入 `volatile` global，再用 GDB 读取。详细演示见 [GDB 使用与演示指南](GDB_USER_GUIDE.md)，实现说明见 [GDB stub 开发说明](GDB_STUB_DEVELOPMENT.md)。

## 5. 三类程序的最小结构

### bare-metal

```c
#include "drivers/gpio.h"

int main(void)
{
    gpio_write_led(1u);
    for (;;) {
    }
}
```

### machine IRQ

IRQ 应用负责实现 `trap_dispatch()`、安装 trap、设置 compare 并开启中断：

```c
#include "drivers/machine_timer.h"
#include "runtime/trap.h"

struct trap_frame *trap_dispatch(struct trap_frame *frame)
{
    if (frame->mcause == 0x80000007u) {
        machine_timer_set_compare(machine_timer_now() + 50000000ull);
    }
    return frame;
}

int main(void)
{
    trap_init();
    machine_timer_set_compare(machine_timer_now() + 50000000ull);
    trap_enable_machine_timer();
    for (;;) {
    }
}
```

### FreeRTOS

FreeRTOS 应用创建 task 后启动 scheduler。scheduler 会安装 trap 并配置 tick，应用不手动调用 `trap_init()`：

```c
#include "FreeRTOS.h"
#include "task.h"

static StaticTask_t task_control;
static StackType_t task_stack[256];

static void task(void *argument)
{
    (void)argument;
    for (;;) {
        vTaskDelay(pdMS_TO_TICKS(100u));
    }
}

int main(void)
{
    xTaskCreateStatic(task, "task", 256u, 0, 1u,
        task_stack, &task_control);
    vTaskStartScheduler();
    for (;;) {
    }
}
```

首次构建 FreeRTOS 前确认 submodule：

```bash
git submodule update --init --recursive
```

## 6. 内部兼容入口

仿真、benchmark、ISE export 和历史脚本仍可显式使用：

```bash
FIRMWARE_PROFILE=dark_irq \
FIRMWARE_MAIN="$PWD/firmware/tests/timer_irq_smoke.c" \
FIRMWARE_OUT=firmware/build/manual/timer/firmware \
  ./scripts/build_firmware.sh
```

内部兼容 profile：

| 旧 profile | 新模型 |
| --- | --- |
| `baremetal` | `baremetal + none` |
| `dark_irq` | `irq + none` |
| `freertos` | `freertos + none` |
| `gdb_stub` | `baremetal + gdb` |

这些变量是工具和 regression 接口，不是新用户首先需要掌握的入口。

## 7. 常见问题

### `未知 APP 运行模型`

检查文件是否位于：

```text
firmware/apps/baremetal/
firmware/apps/irq/
firmware/apps/freertos/
```

### `找不到 APP 文件`

`APP` 使用仓库相对路径，不接受任意仓库外源文件。确认扩展名为 `.c`。

### `当前 GDB 调试尚不支持 irq/freertos 应用`

这是当前 trap dispatcher 的明确边界。用 `firmware-load` 运行该程序，或把不依赖 IRQ/RTOS 的问题缩减成 `baremetal/` 复现程序后调试。

### loader 一直等待 READY

确认 bitstream 已烧录、COM 口正确、其他终端已关闭，然后按下并松开 RESET。不要按 CONFIG。

### 上传成功但 UART 是乱码

`BOOTLOAD_BAUD` 与 bitstream 的 `UART_BAUD` 不一致。重新使用匹配的值上传。

### GDB 找不到 Windows executable

安装包含 `riscv-none-elf-gdb.exe` 的 Windows xPack 工具链，或指定：

```bash
make firmware-debug \
  APP=baremetal/hello.c \
  PORT=COM8 \
  BOOTLOAD_BAUD=115200 \
  WINDOWS_GDB=/mnt/c/Tools/xpack-riscv/bin/riscv-none-elf-gdb.exe
```

## 8. 自动验证

用户入口和三个示例：

```bash
python3 scripts/test_runner.py run-case firmware_app_workflow
```

GDB：

```bash
python3 scripts/test_runner.py run-case gdb_stub_profile_contract
python3 scripts/test_runner.py run-case gdb_stub_load_contract
python3 scripts/test_runner.py run-case gdb_stub
```

FreeRTOS：

```bash
python3 scripts/test_runner.py run-suite freertos --keep-going
```
