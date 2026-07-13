# 板级性能测试流程

本文记录把仿真中已经通过的性能 workload 搬到真实 TEC-PLUS 板上的流程。

## 前置条件

FPGA 中需要先下载 MiniSoC bootloader bitstream，并确认：

- `CPU_IMPL=1`，即 DarkRISCV；
- `BOOTLOADER_ENABLE=1`；
- `UART_BAUD` 与命令里的 `BOOTLOAD_BAUD` 一致；
- Windows 设备管理器能看到 CP2102 `COMx`；
- VSCode Serial Monitor、PuTTY 等工具没有占用该串口。

## 一键运行

在 WSL 仓库根目录执行：

```bash
make board-benchmark PORT=COM9 BOOTLOAD_BAUD=115200
```

每个 case 会依次：

1. 构建对应 firmware；
2. 打开 Windows COM 口；
3. 提示按下并松开 TEC-PLUS RESET；
4. 通过 bootloader 上传；
5. 进入 serial monitor，显示 `RESULT:` 与 `PASS`；
6. 用户按 Enter 结束当前 monitor，进入下一个 case。

结果保存在：

```text
build/board-benchmarks/<UTC 时间戳>/
```

其中：

- `*_build.log`：firmware 构建日志；
- `*_board.log`：真实板级串口日志；
- `results.csv`：从 `RESULT:` 行提取出的结构化数据；
- `summary.md`：便于提交、截图或写报告的汇总表；
- `environment.txt`：commit、串口、baud、工具链等环境快照。

## 当前覆盖的 workload

| workload | 作用 | 说明 |
| --- | --- | --- |
| `perf_mix` | ALU 依赖链、交替分支、BRAM load/store、混合负载 | 与 `make perf` 的仿真入口一致 |
| `system_bench` | 三点滑动窗口滤波 | 同一算法比较 BRAM 与 SDRAM |
| `riscv_tests_median` | upstream median kernel | 比较 BRAM 与 SDRAM 数据区 |
| `riscv_tests_memcpy` | upstream memcpy dataset | 比较 BRAM->BRAM 与 SDRAM->SDRAM |
| `sdram_sum_bench` | SDRAM 顺序读求和 | 简单、直观的外部存储基线 |

## 记录口径

`cycles`、`instret`、`mem_wait` 都来自 firmware 里的 `perf_begin/perf_end` 区间，是真实板子上通过 MMIO 读到的计数器值。

注意：

- 板级结果只对应当前 bitstream、当前 clock 与当前 CPU 配置；
- 与仿真结果比较时，优先看趋势和 CPI，不要把仿真的 `1 MHz` 绝对吞吐直接当作板上频率；
- 若 RTL、CPU、SDRAM controller、baud 或 ISE timing 变化，需要重新采集。

## 后续可以补充的 firmware 性能测试

可以继续加入以下 workload：

- `crc32_bench`：模拟协议包、图像块或存储校验；
- `memset_bench`：覆盖 framebuffer / buffer 清零；
- `pointer_chase_bench`：测试非连续访问和 SDRAM 延迟敏感场景；
- `stride_bench`：比较 stride=1、2、4、16 的访存模式；
- `uart_print_bench`：单独测 UART 输出对 firmware 的阻塞影响；
- `freertos_context_switch_bench`：测 FreeRTOS task 切换和 tick 成本。

这些测试应继续使用统一输出格式：

```text
RESULT: benchmark=<名字> case=<子项> cycles=<周期> instret=<指令数> mem_wait=<等待周期>
```
