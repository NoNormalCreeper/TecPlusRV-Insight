# Issue #19：双核、存储层次与性能实验总结

## 结论

本项目已完成 PicoRV32 与 DarkRISCV 在同一 MiniSoC、同一 firmware 和同一 memory map 下的可复跑性能实验。DarkRISCV 在计算、分支和 BRAM 访问 workload 上显著降低 CPI；但两颗核一旦访问 SDRAM，性能都明显受外部存储等待限制。当前系统最主要的优化对象是 SDRAM 数据访问，而不是继续微调纯 ALU 指令。

完整原始数据、构建日志和环境快照见 [`results/issue19-2026-07-10/`](../results/issue19-2026-07-10/)；本报告只解释结论，不替代原始证据。

## 实验口径

- workload：`perf_mix`、系统级三点滑动窗口 `system_bench`、官方 `riscv-tests` 的 `median` 和 `memcpy`；
- 计数区间：firmware `perf_begin/perf_end`，不含初始化、校验和 UART 输出；
- 指标：`cycles`、`instret`、`mem_wait`、CPI；吞吐量按 testbench 的 1 MHz 时钟换算；
- 环境：Icarus Verilog 11.0、`riscv64-unknown-elf-gcc` 10.2.0；详见 [`environment.txt`](../results/issue19-2026-07-10/environment.txt)。

同一 workload 的 Pico/Dark `instret` 一致，因此 CPI 和 cycle 可直接比较。`mem_wait` 只宜比较同一颗核在不同存储位置下的变化；两颗核 wrapper 的 ack 时序不同，绝对值不等同于相同定义的 Cache miss 或 pipeline stall。

## 核心对比

| workload | Pico CPI | Dark CPI | Dark 相对加速 |
| --- | ---: | ---: | ---: |
| `perf_mix` mixed | 5.972 | 2.802 | 2.13x |
| `system_bench` BRAM | 6.277 | 3.112 | 2.02x |
| 官方 `median` BRAM | 7.052 | 4.588 | 1.54x |
| 官方 `memcpy` BRAM | 6.499 | 3.999 | 1.63x |

`alu_dep` 的 Dark/Pico cycle 比约为 2.31x，`branch_alternating` 约为 1.83x。这是“流水线核心在同频下提高吞吐量”的主要量化证据。`perf_mix` 的完整分项数据见 [`summary.md`](../results/issue19-2026-07-10/summary.md)。

## 存储层次结论

| workload | Pico：BRAM → SDRAM CPI | Dark：BRAM → SDRAM CPI | 含义 |
| --- | ---: | ---: | --- |
| `system_bench` | 6.277 → 10.754 | 3.112 → 6.992 | 滑动窗口的重叠读放大 SDRAM 等待 |
| `median` | 7.052 → 13.575 | 4.588 → 10.244 | 官方算法同样受外存访问限制 |
| `memcpy` | 6.499 → 11.345 | 3.999 → 8.174 | 即使对齐 word copy，连续 SDRAM 拷贝仍有较高往返成本 |

以 `system_bench` 为例，Pico 的 `mem_wait` 占比从 BRAM 的 7.1% 升至 SDRAM 的 45.8%，Dark 从 28.5% 升至 71.2%。这说明当前 closed-page、单 outstanding、无 burst 的控制器在正确性和可验证性上是合适的第一版，但连续数据访问的延迟已经成为系统级瓶颈。

## 当前能力与未覆盖项

本次结果使用仿真 `sdram_x16_model`。firmware 从 BRAM 启动后，`startup.S` 复制 `.sdram_data`、清零 `.sdram_bss`，heap/benchmark 再由 CPU 向 `0x8000_0000` SDRAM 窗口写入和读取数据；不依赖预装 SDRAM 内容。

仓库已有 SDRAM probe 的板级记录，但本目录的完整双核 benchmark 尚未形成板级 UART/PPA 证据。因此 1 MHz KIPS 只能作为统一仿真环境的相对吞吐量，不能写作实际板上频率；实际吞吐量应在 ISE post-route 后用 `Fmax / CPI` 计算。

## 优化建议

优先做软件层的寄存器滑动窗口和 BRAM 分块；它们不改变 controller 协议，却能减少 SDRAM 重复读取。下一层再考虑软件 line buffer。burst、DMA 或 D-cache 均属于 RTL/系统结构升级，必须另行建立 controller 回归和上板验证，不能作为本次收口的既有能力。具体路线见 [`docs/FUTURE_PERFORMANCE_PLAN.md`](../docs/FUTURE_PERFORMANCE_PLAN.md)。
