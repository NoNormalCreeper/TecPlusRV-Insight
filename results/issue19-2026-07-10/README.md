# Issue #19 仿真性能结果

这是 #19 收口时保存的完整、不可变仿真样本，运行编号为 `issue19-final`。采集时对应 commit `627e871`，工作区无修改；后续仅补充了文档说明，不改变测量 RTL 或 firmware。

## 内容

- `results.csv`：可导入表格软件的 20 条结构化测量数据；
- `summary.md`：同一数据的可读表格；
- `environment.txt`：commit、工具版本、计数器口径和 1 MHz testbench 时钟；
- `*_build.log`：每个 workload 的 firmware 构建记录；
- `*_picorv32.log`、`*_darkriscv.log`：双核原始 UART / testbench 输出。

## 证据边界

这些是 `Icarus Verilog + sdram_x16_model` 仿真结果，不是板级 SDRAM benchmark 或 ISE PPA 数据。它们证明同一 RTL、同一 firmware 下的功能和相对 cycle/CPI 差异；上板后应以新的运行编号另存 UART 日志、Map/PAR/Timing Report，并保留本目录作为 baseline。
