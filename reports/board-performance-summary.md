# 板级固件性能实验总结

## 结论

本轮板级实验把 issue #19 中的性能分析方法延伸到真实 TEC-PLUS 板子：通过 UART bootloader 上传 firmware，在 DarkRISCV MiniSoC 上实际运行 `memset_bench`、`stride_bench` 和 `crc32_bench`。三项 workload 均完成上板运行，BRAM 与 SDRAM 的计算结果一致，性能计数器能够稳定输出 `cycles`、`instret` 和 `mem_wait`。

结果符合 issue #19 的核心判断：当 workload 偏向连续写入或读改写访存时，SDRAM 等待会成为主要开销；当 workload 计算占比更高时，同样从 SDRAM 读取数据，整体 CPI 增幅会明显收敛。

原始板级日志已归档到 [`results/board-benchmarks/20260713T082725Z/`](../results/board-benchmarks/20260713T082725Z/)；本报告只摘录关键数据与结论。

## 与 issue #19 的关系

issue #19 的总结见 [`reports/issue19-performance-summary.md`](issue19-performance-summary.md)。它主要完成了：

- 在 Icarus Verilog 仿真中比较 PicoRV32 与 DarkRISCV；
- 用同一 MiniSoC、同一 firmware 和同一 memory map 建立可复跑基线；
- 证明 SDRAM 访问会显著放大 `mem_wait`，系统瓶颈不只在 CPU core。

本轮实验不是重新做双核仿真对比，而是补充真实板级证据：

- 固定使用当前板上 DarkRISCV bootloader bitstream；
- 通过 `make board-benchmark-new PORT=COM9 BOOTLOAD_BAUD=115200` 上传新增 workload；
- 在真实 UART、真实 SDRAM controller、真实 FPGA 配置下读取性能计数器。

因此，本轮结果可以作为 issue #19 的板级补充：它证明同一类“BRAM vs SDRAM”性能差异不只存在于仿真模型中，也能在板子上通过 firmware 直接观测。

## 实验口径

- 运行编号：`20260713T082725Z`
- 板级入口：`make board-benchmark-new PORT=COM9 BOOTLOAD_BAUD=115200`
- workload：`memset_bench`、`stride_bench`、`crc32_bench`
- 计数区间：firmware `perf_begin/perf_end`
- 指标：`cycles`、`instret`、`mem_wait`、CPI
- 串口：`COM9`
- bootloader baud：`115200`
- 构建工具链：`riscv64-unknown-elf-gcc 13.2.0`

环境快照显示本次运行时仓库处于 `bd75c57` 并带有 8 个未提交修改；这些修改随后已整理为 `9d844f5 feat: 增加 memset/stride/crc32 固件性能测试`。后续若要形成最终验收证据，建议在干净工作区重新运行一次同样命令。

## 核心数据

| workload | scope | cycles | instret | mem_wait | wait % | CPI |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `memset_bench` | BRAM | 22654 | 5158 | 4116 | 18.2% | 4.392 |
| `memset_bench` | SDRAM | 37230 | 5158 | 19716 | 53.0% | 7.218 |
| `stride_bench` | stride1 BRAM | 90176 | 32785 | 16404 | 18.2% | 2.751 |
| `stride_bench` | stride1 SDRAM | 155722 | 32785 | 86045 | 55.3% | 4.750 |
| `stride_bench` | stride2 BRAM | 90176 | 32785 | 16404 | 18.2% | 2.751 |
| `stride_bench` | stride2 SDRAM | 155712 | 32785 | 86036 | 55.3% | 4.749 |
| `stride_bench` | stride4 BRAM | 90176 | 32785 | 16404 | 18.2% | 2.751 |
| `stride_bench` | stride4 SDRAM | 155712 | 32785 | 86036 | 55.3% | 4.749 |
| `stride_bench` | stride8 BRAM | 90176 | 32785 | 16404 | 18.2% | 2.751 |
| `stride_bench` | stride8 SDRAM | 155712 | 32785 | 86036 | 55.3% | 4.749 |
| `stride_bench` | stride16 BRAM | 90176 | 32785 | 16404 | 18.2% | 2.751 |
| `stride_bench` | stride16 SDRAM | 155712 | 32785 | 86036 | 55.3% | 4.749 |
| `crc32_bench` | BRAM | 655428 | 253971 | 16404 | 2.5% | 2.581 |
| `crc32_bench` | SDRAM | 729638 | 253971 | 94710 | 13.0% | 2.873 |

## BRAM 与 SDRAM 对比

| workload | SDRAM / BRAM cycles | SDRAM / BRAM CPI | 观察 |
| --- | ---: | ---: | --- |
| `memset_bench` | 1.64x | 1.64x | 连续写入场景中，SDRAM 等待从 18.2% 升到 53.0% |
| `stride_bench` | 1.73x | 1.73x | 读改写场景中，SDRAM 等待稳定约 55.3% |
| `crc32_bench` | 1.11x | 1.11x | CRC32 位运算占比高，SDRAM 等待存在但不主导总耗时 |

`stride_bench` 中 stride=1/2/4/8/16 的结果几乎一致，这是当前 workload 设计的一个重要现象：每个 case 都执行相同次数的单字读改写，而当前 controller 没有 cache、burst 或 line buffer，所以不同 stride 暂时没有形成明显局部性差异。这个结果并不说明 stride 不重要，只说明当前硬件路径对这些访问都近似按独立事务处理。

## 当前能力与限制

本轮已经验证：

- 新增 firmware 可以通过 bootloader 在板子上运行；
- BRAM / SDRAM 数据结果一致；
- `mem_wait` 能反映 SDRAM 访问带来的等待；
- `board-benchmark-new` 可以自动生成 `results.csv`、`summary.md` 和各 case 原始串口日志。

仍需注意：

- 本轮只覆盖 DarkRISCV 板级路径，不覆盖 PicoRV32 板级对比；
- 本轮数据不是 ISE timing / Fmax 报告，不能单独得出最高运行频率；
- 运行时仓库不是干净状态，最终报告前建议用当前提交重新跑一次；
- `stride_bench` 还不能区分 cache/burst 类局部性收益，因为当前设计没有对应结构。

## 后续建议

1. 在干净工作区重新运行 `make board-benchmark-new PORT=COM9 BOOTLOAD_BAUD=115200`，把新的 run id 作为正式板级证据。
2. 如果要继续扩展性能测试，优先加入 `pointer_chase_bench`。它的每次访存依赖上一次结果，更容易暴露 SDRAM latency。
3. 如果要分析串口日志对程序性能的影响，单独加入 `uart_print_bench`，并明确 baud rate 是实验变量。
4. 若后续引入 cache、burst、DMA 或 line buffer，应保留本报告作为优化前基线，重新比较 `memset`、`stride` 和 `crc32` 的 wait % 与 CPI。
