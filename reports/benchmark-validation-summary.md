# Benchmark 验证总览

## 总结

当前仓库的性能测试可以分成两层：

- issue #19：在仿真中建立 PicoRV32 / DarkRISCV、BRAM / SDRAM 的性能基线；
- 板级补充：在真实 TEC-PLUS 板子上通过 UART bootloader 运行 DarkRISCV firmware benchmark。

截至本报告，旧 benchmark 已有 issue #19 仿真总结与一次完整板级运行；新增 `memset_bench`、`stride_bench`、`crc32_bench` 已接入仿真和板级入口，并完成一次板级运行。整体结论仍然一致：纯计算或 BRAM workload 主要体现 CPU core 效率；一旦数据落到 SDRAM，`mem_wait` 会显著上升，访存密集型 workload 更容易被外部存储拖住。

## 证据目录

| 类型 | 路径 | 说明 |
| --- | --- | --- |
| issue #19 仿真总结 | [`reports/issue19-performance-summary.md`](issue19-performance-summary.md) | 双核、存储层次与性能实验总结 |
| issue #19 原始结果 | [`results/issue19-2026-07-10/`](../results/issue19-2026-07-10/) | `make perf` 生成的仿真基线归档 |
| 旧 benchmark 板级结果 | [`results/board-benchmarks/20260713T075127Z/`](../results/board-benchmarks/20260713T075127Z/) | `perf_mix`、`system_bench`、`median`、`memcpy`、`sdram_sum_bench` |
| 新增 benchmark 板级结果 | [`results/board-benchmarks/20260713T082725Z/`](../results/board-benchmarks/20260713T082725Z/) | `memset_bench`、`stride_bench`、`crc32_bench` |
| 新增 benchmark 板级总结 | [`reports/board-performance-summary.md`](board-performance-summary.md) | 本轮新增 workload 的板级分析 |

`results/board-benchmarks/*` 是从本地 `build/board-benchmarks/*` 复制出来的板级证据归档，保留了 `summary.md`、`results.csv`、`environment.txt`、`*_board.log` 和 `*_build.log`。`reports/` 中的文件负责记录结论、解释和后续判断。

## 数据关系与可靠性检查

- `reports/issue19-performance-summary.md` 解释仿真基线，数据源是 `results/issue19-2026-07-10/`。
- 本报告的旧 benchmark 板级表格来自 `results/board-benchmarks/20260713T075127Z/results.csv` 与同目录 `summary.md`。
- 本报告的新增 benchmark 板级表格来自 `results/board-benchmarks/20260713T082725Z/results.csv` 与同目录 `summary.md`。
- `sdram_sum_bench` 没有统一 `RESULT:` 输出，因此没有进入 `results.csv`；报告中的 `34834 cycles / 4104 instret / CPI 8.488` 来自 `results/board-benchmarks/20260713T075127Z/sdram_sum_bench_board.log`。
- 原始串口日志中的 `RESULT:` 行与 `results.csv` 数值一致；`summary.md` 是同一数据的 Markdown 展示。
- 两次板级运行的 `environment.txt` 都记录了采集时工作区存在未提交修改，因此当前数据可作为阶段性上板证据；若要作为最终验收样本，应在干净工作区重新运行并另存新的 run id。

## Benchmark 矩阵

| benchmark | 类型 | 主要覆盖 | 仿真确认 | 板级确认 | 结果位置 |
| --- | --- | --- | --- | --- | --- |
| `perf_mix` | CPU / BRAM microbenchmark | ALU 依赖链、分支、BRAM load/store、mixed | issue #19 已归档，PicoRV32/DarkRISCV 均通过 | `20260713T075127Z` 已输出 4 组 `RESULT:` | `results/issue19-2026-07-10/`、`results/board-benchmarks/20260713T075127Z/` |
| `system_bench` | 系统级数据处理 | 三点滑动窗口，BRAM vs SDRAM | issue #19 已归档，PicoRV32/DarkRISCV 均通过 | `20260713T075127Z` 已输出 BRAM / SDRAM 结果 | 同上 |
| `riscv_tests_median` | upstream kernel | 官方 median 数据集，BRAM vs SDRAM | issue #19 已归档，PicoRV32/DarkRISCV 均通过 | `20260713T075127Z` 已输出 BRAM / SDRAM 结果 | 同上 |
| `riscv_tests_memcpy` | upstream memory kernel | 官方 memcpy 数据集，BRAM->BRAM vs SDRAM->SDRAM | issue #19 已归档，PicoRV32/DarkRISCV 均通过 | `20260713T075127Z` 已输出 BRAM / SDRAM 结果 | 同上 |
| `sdram_sum_bench` | SDRAM 简单基线 | 1024 word 顺序写入与求和 | 已在历史 SDRAM benchmark 中使用 | `20260713T075127Z` 已输出 `sum/cycles/instret`，但不是 `RESULT:` 格式 | `results/board-benchmarks/20260713T075127Z/sdram_sum_bench_board.log` |
| `memset_bench` | 新增写密集 workload | 4096 byte 连续写入，BRAM vs SDRAM | 本轮已用 `minisoc_sdram_pico/dark` 手动验证通过，并已接入 `make perf` | `20260713T082725Z` 已输出 BRAM / SDRAM 结果 | `results/board-benchmarks/20260713T082725Z/` |
| `stride_bench` | 新增访问模式 workload | stride=1/2/4/8/16 的读改写，BRAM vs SDRAM | 本轮已用 `minisoc_sdram_pico/dark` 手动验证通过，并已接入 `make perf` | `20260713T082725Z` 已输出 10 组结果 | 同上 |
| `crc32_bench` | 新增混合计算 workload | 4096 byte CRC32，BRAM vs SDRAM | 本轮已用 `minisoc_sdram_pico/dark` 手动验证通过，并已接入 `make perf` | `20260713T082725Z` 已输出 BRAM / SDRAM 结果 | 同上 |

## 板级结果摘录

旧 benchmark 的板级运行 `20260713T075127Z`：

| benchmark | scope | cycles | instret | mem_wait | CPI |
| --- | --- | ---: | ---: | ---: | ---: |
| `perf_mix` | mixed | 100748 | 35959 | 16404 | 2.802 |
| `system_bench` | stencil_bram | 54966 | 17308 | 16276 | 3.176 |
| `system_bench` | stencil_sdram | 125908 | 17308 | 91079 | 7.275 |
| `riscv_tests_median` | bram | 23350 | 5610 | 6396 | 4.162 |
| `riscv_tests_median` | sdram | 51312 | 5609 | 35881 | 9.148 |
| `riscv_tests_memcpy` | bram_to_bram | 128126 | 32036 | 32020 | 3.999 |
| `riscv_tests_memcpy` | sdram_to_sdram | 261822 | 32034 | 173435 | 8.173 |
| `sdram_sum_bench` | sdram_sum | 34834 | 4104 | 未输出 | 8.488 |

新增 benchmark 的板级运行 `20260713T082725Z`：

| benchmark | scope | cycles | instret | mem_wait | CPI |
| --- | --- | ---: | ---: | ---: | ---: |
| `memset_bench` | bram | 22654 | 5158 | 4116 | 4.392 |
| `memset_bench` | sdram | 37230 | 5158 | 19716 | 7.218 |
| `stride_bench` | stride1_bram | 90176 | 32785 | 16404 | 2.751 |
| `stride_bench` | stride1_sdram | 155722 | 32785 | 86045 | 4.750 |
| `crc32_bench` | bram | 655428 | 253971 | 16404 | 2.581 |
| `crc32_bench` | sdram | 729638 | 253971 | 94710 | 2.873 |

`stride_bench` 的 stride=2/4/8/16 与 stride=1 结果几乎一致：BRAM 都约 `90176 cycles`，SDRAM 都约 `155712 cycles`。这说明在当前无 cache、无 burst、无 line buffer 的 controller 下，这些访问都近似按独立事务付费。

## 主要结论

1. DarkRISCV 板级结果与 issue #19 的仿真方向一致：访问 SDRAM 后，CPI 和 `mem_wait` 都明显上升。
2. `system_bench`、`median`、`memcpy` 的板级数据再次说明：真实算法一旦把数据放到 SDRAM，外部存储等待会成为主要成本。
3. 新增 `memset_bench` 说明连续写入也会受到 SDRAM 等待影响，SDRAM cycles 约为 BRAM 的 `1.64x`。
4. 新增 `stride_bench` 说明读改写访问对 SDRAM 更敏感，SDRAM cycles 约为 BRAM 的 `1.73x`。
5. 新增 `crc32_bench` 计算占比更高，SDRAM cycles 只约为 BRAM 的 `1.11x`；这说明并不是所有 workload 都同等受 SDRAM 影响，计算/访存比例很关键。

## 还需要补强的地方

- `sdram_sum_bench` 应改成统一 `RESULT:` 输出，便于自动进入 `results.csv`。
- `results/board-benchmarks/20260713T075127Z/environment.txt` 与 `results/board-benchmarks/20260713T082725Z/environment.txt` 都显示运行时存在未提交修改；最终归档前应在干净工作区重新跑一次。
- 新增 workload 已经接入 `make perf`，但尚未形成类似 `results/issue19-2026-07-10/` 的正式仿真归档。
- 板级当前只覆盖 DarkRISCV bootloader bitstream；如果课程报告需要双核板级对比，还需要额外准备 PicoRV32 板级 bitstream 与同样流程。

## 建议收口方式

1. 保留 issue #19 作为仿真基线报告。
2. 保留 [`reports/board-performance-summary.md`](board-performance-summary.md) 作为新增三项板级分析报告。
3. 使用本文件作为“所有 benchmark 是否已经总结与确认”的总览入口。
4. 最终提交前，在干净工作区重跑：

```bash
make board-benchmark PORT=COM9 BOOTLOAD_BAUD=115200
make board-benchmark-new PORT=COM9 BOOTLOAD_BAUD=115200
```

若要节省时间，第二条已经包含在第一条之后的新增测试补充中，也可以只跑 `board-benchmark-new` 来刷新新增项证据。
