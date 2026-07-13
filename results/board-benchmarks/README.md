# 板级性能测试结果

这里保存真实 TEC-PLUS 板子上通过 UART bootloader 运行 firmware benchmark 得到的原始证据。`results/` 只记录测试数据与日志；结论、解释和后续判断放在 [`reports/benchmark-validation-summary.md`](../../reports/benchmark-validation-summary.md) 与 [`reports/board-performance-summary.md`](../../reports/board-performance-summary.md)。

## 内容

- `20260713T075127Z/`：旧 benchmark 的板级运行结果，包含 `perf_mix`、`system_bench`、`riscv_tests_median`、`riscv_tests_memcpy` 和 `sdram_sum_bench`。
- `20260713T082725Z/`：新增 benchmark 的板级运行结果，包含 `memset_bench`、`stride_bench` 和 `crc32_bench`。
- 每个运行目录中的 `results.csv`：结构化结果，可导入表格工具。
- 每个运行目录中的 `summary.md`：同一批结果的可读表格。
- 每个运行目录中的 `environment.txt`：运行编号、commit、串口、baud、工具链和计数器口径。
- `*_board.log`：真实板子串口原始输出。
- `*_build.log`：对应 firmware 构建日志。

## 证据边界

这些数据来自 DarkRISCV bootloader bitstream 的真实板级运行，不是 Icarus Verilog 仿真结果，也不是 ISE timing / Fmax / 资源利用率报告。`cycles`、`instret` 和 `mem_wait` 来自 firmware `perf_begin/perf_end` 区间差值。

两次运行的 `environment.txt` 都记录了采集时工作区存在未提交修改，因此它们适合作为当前阶段的板级证据归档；如果要作为最终验收样本，建议在干净工作区重新运行并保存新的 run id。

`sdram_sum_bench` 的历史输出不是统一的 `RESULT:` 格式，因此没有进入 `results.csv`，但原始串口日志中保留了 `cycles` 与 `instret`，报告中对它单独标注。
