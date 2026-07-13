# 性能实验与结果解读

`make perf`（等价于 `make benchmark`）是本项目的统一性能实验入口。它会依次构建并在 PicoRV32、DarkRISCV 上运行以下 workload：

| workload | 作用 | 存储覆盖 |
| --- | --- | --- |
| `perf_mix` | ALU 依赖链、交替分支、BRAM load/store、混合负载 | BRAM |
| `system_bench` | 三点滑动窗口滤波，模拟相邻像素/采样处理 | BRAM 与 SDRAM |
| `riscv_tests_median` | `riscv-tests` upstream `median` kernel 与 dataset | BRAM 与 SDRAM |
| `riscv_tests_memcpy` | `riscv-tests` upstream `memcpy` dataset | BRAM->BRAM 与 SDRAM->SDRAM |
| `memset_bench` | 连续写入，用于清屏、清 buffer、初始化数组等场景 | BRAM 与 SDRAM |
| `stride_bench` | 固定访问次数，比较 stride=1/2/4/8/16 的地址模式 | BRAM 与 SDRAM |
| `crc32_bench` | 读取 buffer 并执行 bitwise CRC32，模拟协议/资源校验 | BRAM 与 SDRAM |

每次运行会创建 `sim/build/benchmarks/<UTC 时间戳>/`，其中包含：

- `*_build.log`：每个 workload 的 firmware 构建记录；
- `*_picorv32.log`、`*_darkriscv.log`：原始 UART / testbench 日志；
- `results.csv`：可导入表格软件的结构化结果；
- `summary.md`：带 CPI、数据口等待占比和 1 MHz 仿真时钟下 KIPS 的汇总表；
- `environment.txt`：commit、工作区修改数、工具版本、时钟和计数口径。

可用固定运行编号，方便复跑和比较：

```bash
BENCHMARK_RUN_ID=before-change make perf
BENCHMARK_RUN_ID=after-change make perf
```

## 指标口径

- `cycles`、`instret`、`mem_wait` 都是 `perf_begin/perf_end` 围出的 workload 区间差值，不含初始化、结果校验和 UART 打印。
- `CPI = cycles / instret`；同一编译镜像在两颗核上运行时，可用它比较核心总体效率。
- `mem_wait` 只统计 CPU 数据口在 `mem_ready` 前保持有效的周期。它可用于定位**同一颗核**中 BRAM/SDRAM 访问的等待热点，但不是 Cache miss 数；当前设计没有 Cache。PicoRV32 与 DarkRISCV 的 wrapper/ack 握手时序不同，因此不要把两颗核的绝对 `mem_wait` 直接解释为完全等价的停顿数，应优先比较同核的存储位置变化与 CPI。
- `KIPS @ 1 MHz = 1000 / CPI` 是 testbench 的 `CLK_FREQ=1 MHz` 下的等效吞吐量。实际上板频率应以 ISE 的 post-route timing report 为准，再按同一 CPI 换算；不能把 1 MHz 仿真值当作板上最高频率。

## 如何据此分析瓶颈

1. 先看同一 workload 的两核 `instret` 是否一致；不一致时，不能把 CPI 差异简单归因于微架构。
2. 对 `system_bench`、`median`、`memset_bench` 和 `crc32_bench` 比较 BRAM / SDRAM 的 `cycles` 与 `wait %`。SDRAM 项显著上升时，瓶颈是外部存储访问，而非纯算术或分支。
3. `stride_bench` 在当前无 Cache、closed-page SDRAM 设计上预期不会随 stride 显著变化；它用于确认固定事务数下的地址模式成本。只有后续加入 Cache、burst 或 open-page 策略后，才能把 stride 差异解释为局部性收益。
4. 对 `perf_mix` 的四项 case 横向比较：`alu_dep`、`branch_alternating` 与 `bram_load_store` 的差异可以区分计算/控制流/片上数据访问贡献；`mixed` 用作更接近一般裸机工作负载的总览。
5. 优化优先级通常是：把热数据放入 BRAM、批量使用 32-bit 对齐的 `memcpy/memset`、减少 SDRAM 往返访问；若后续要继续扩展，再评估小型 Cache 或 burst/line buffer。每项优化前后均应使用固定 `BENCHMARK_RUN_ID` 重跑并保存两份表。

`sdram_overlap_read` 是正确性回归而非性能表项：它以最小滑动窗口重叠读覆盖 DarkRISCV 的 SDRAM 请求重放路径，已加入双核 regression。

## 已归档的 #19 基线

2026-07-10 的完整仿真样本已固定在 [`results/issue19-2026-07-10/`](../results/issue19-2026-07-10/)，课程化的结论见 [`reports/issue19-performance-summary.md`](../reports/issue19-performance-summary.md)。该样本是 Icarus 仿真基线，不是板级 benchmark；后续优化和上板 PPA 的记录方式见 [`docs/FUTURE_PERFORMANCE_PLAN.md`](FUTURE_PERFORMANCE_PLAN.md)。
