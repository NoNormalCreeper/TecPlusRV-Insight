# 当前 GDB demo 运行与演示指引

推荐把演示控制在 3～5 分钟。主线是：

> GDB 通过 UART 连接 FPGA 内的 cooperative stub，观察并修改 BRAM/SDRAM 数据；CPU 继续执行后使用修改后的数据计算，最后由 LED 给出物理反馈。

当前 WSL 已能找到 `py.exe`、`riscv-none-elf-gdb.exe` 和 RISC-V GCC。

## 一、上板前准备

FPGA 中需要已经下载正确的 MiniSoC Bootloader bitstream：

- `CPU_IMPL=1`，即 DarkRISCV；
- `BOOTLOADER_ENABLE=1`；
- `UART_BAUD=115200`，或与你命令中的 baud 一致；
- CP2102 串口由 Windows 持有；
- 关闭 PuTTY、串口监视器和其他占用 COM 口的软件。

确认实际 COM 口，例如设备管理器显示 `COM8`。按键操作使用板上的 `RESET`，不要按 `CONFIG`。

## 二、启动 demo

在 WSL 仓库根目录运行：

```bash
cd /home/rikka/NexysRV-Insight

make firmware-debug \
  APP=baremetal/gdb_demo.c \
  PORT=COM8 \
  BOOTLOAD_BAUD=115200
```

如果 COM 口不是 `COM8`，替换成实际端口。

成功后通常看到：

```text
Remote debugging using COM8
... in gdb_known_context_break ()
(gdb)
```

## 三、第一站：自动 attach 点

这里是 `__wrap_main()` 在用户 `main()` 之前设置的自动停点，应用数据尚未初始化。

先简单展示寄存器和源码：

```gdb
info registers pc sp ra
frame
list
```

然后执行一次：

```gdb
continue
```

这一步之后才会运行 `gdb_demo.c`，到达用户程序中的第一个 `DEBUG_BREAK()`。

## 四、第二站：观察并修改运行状态

此时板上 LED 应显示 `1`，`phase` 也应为 1。

先查看源码：

```gdb
list gdb_demo.c:34
```

查看 BRAM 中的控制状态：

```gdb
p/x gdb_demo_state
p/x &gdb_demo_state
x/5wx &gdb_demo_state
```

预期内容：

```text
phase      = 0x1
input      = 0x7
multiplier = 0x3
output     = 0x0
checksum   = 0x0
```

再查看 SDRAM：

```gdb
p/x gdb_demo_sdram
p/x &gdb_demo_sdram
x/4wx &gdb_demo_sdram
```

预期数组：

```text
0x10  0x20  0x30  0x40
```

地址上应能看到：

- `gdb_demo_state` 位于低地址 BRAM；
- `gdb_demo_sdram` 位于 `0x80000000` 开始的 SDRAM 范围。

现场修改数据：

```gdb
set var gdb_demo_state.input = 10
set var gdb_demo_state.multiplier = 4
set var gdb_demo_sdram[0] = 0x100
```

立即回读确认：

```gdb
p/x gdb_demo_state
p/x gdb_demo_sdram
```

然后让 CPU 恢复执行：

```gdb
continue
```

## 五、第三站：验证修改真正影响了计算

程序计算：

```text
output   = input × multiplier
checksum = SDRAM 四个元素之和
```

此时会停在第二个 `DEBUG_BREAK()`，LED 应显示 `2`。

检查结果：

```gdb
list gdb_demo.c:44
p/x gdb_demo_state
p/x gdb_demo_state.output
p/x gdb_demo_state.checksum
```

预期：

```text
phase    = 0x2
output   = 0x28
checksum = 0x190
```

计算关系是：

```text
10 × 4 = 40 = 0x28
0x100 + 0x20 + 0x30 + 0x40 = 0x190
```

## 六、最后的板级反馈

执行：

```gdb
continue
```

程序会：

- 将 `phase` 更新为 3；
- 把 `output` 的低 4 bit 写入 LED；
- 进入无限循环。

`0x28` 的低 4 bit 是 `0x8`，因此最终 LED 应显示 `8` 对应的灯型。

此后 GDB 会一直显示 `Continuing`，不会重新出现 prompt，这是正常现象：当前 stub 不支持运行中 Ctrl-C 异步暂停。演示结束后关闭 GDB；要重新演示，需要退出当前 session，重新运行命令并按 `RESET`。


## 边界

- 只支持 DarkRISCV bare-metal；
- `ebreak` 是同步 exception，不是 IRQ；
- 需要预埋 `DEBUG_BREAK()`；
- 不支持 `break main` 等动态断点；
- 不支持 `step`、`next` 和 single-step；
- 不支持运行中 Ctrl-C 异步暂停；
- 不支持 FreeRTOS task/thread 视图；
- GDB session 期间 UART 归 RSP 独占，应用不能用同一个 UART 打普通日志。

完整说明可查看 [GDB_USER_GUIDE.md](/home/rikka/NexysRV-Insight/docs/GDB_USER_GUIDE.md:231)，演示程序在 [gdb_demo.c](/home/rikka/NexysRV-Insight/firmware/apps/baremetal/gdb_demo.c:34)。
