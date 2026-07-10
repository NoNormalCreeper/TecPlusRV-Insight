# 后续性能优化与上板验证计划

本计划从当前已经验证的 data-only SDRAM、双核 wrapper 和性能计数器继续推进。它不把以下事项视为当前能力：SDRAM burst、DMA、D-cache、完整板级双核 benchmark、ISE PPA 对比。

## 优化职责与优先级

| 优化 | 职责层 | 做法 | 预计收益 | 当前优先级 |
| --- | --- | --- | --- | --- |
| 寄存器滑动窗口 | firmware | `prev/curr/next` 复用，迭代只读取一个新元素 | 降低重复读 | P0 |
| 软件分块 | firmware + linker placement | SDRAM 块搬至 BRAM 数组，计算后写回 | 降低外存往返 | P0 |
| 软件 line buffer | firmware | 二维算法保留 2~3 行 BRAM 缓冲 | 降低邻域重复读 | P1 |
| 硬件 line buffer | accelerator / VGA RTL | 流式数据路径保留相邻行 | 面向专用流处理 | P2 |
| SDRAM burst | controller / DMA RTL | 一次命令连续传输相邻 word | 提高连续访问带宽 | P2 |
| D-cache | CPU 数据通路 RTL | 小型 tag/data RAM、替换和 MMIO bypass | 覆盖一般局部性 | P3 |

寄存器滑动窗口不需要新增硬件。三点一维算法可把 `a[i-1]、a[i]、a[i+1]` 的重复访问改为保存三个局部变量，每轮只从 SDRAM 读取一个新 word。二维 3x3 算法需要的“line buffer”首先应实现为 firmware 中显式放在 BRAM 的 2~3 行数组；只有做流式 accelerator/VGA 时，line buffer 才应下沉到 RTL。

## P0：软件优化实验

1. 新增 `system_bench_optimized.c`，保持输入、输出 checksum 和测量口径与 `system_bench.c` 一致。
2. 第一项只做寄存器滑动窗口；第二项以 256 或 512 word 为固定 tile，使用现有 32-bit 对齐 `rt_memcpy` 在 SDRAM/BRAM 间搬运。
3. 对 Pico/Dark 各运行 BRAM baseline、直接 SDRAM、滑动窗口、分块四组；记录 `cycles / instret / mem_wait / CPI`。
4. 只有 checksum 与 baseline 相同、`scripts/test_dual_core_regression.sh` 双核通过时，才把优化结果加入 `results/<run-id>/`。

这一步是最小、最可解释的优化：不改 `sdram_data_ctrl`，也不需要 DMA 或缓存一致性设计。

## P1：软件 line buffer

针对二维图像、矩阵 stencil 或未来的 tile 数据：

1. 每次从 SDRAM 搬入一个新行到 BRAM；
2. BRAM 中保持前一行、当前行、下一行；
3. 算完当前输出行后轮换三行缓冲，仅读取下一条新行；
4. 输出行按块写回 SDRAM。

这仍是用户程序的职责。缓冲大小必须与 64 KiB BRAM 中的 firmware、stack 和其他静态对象共同预算，不能默认整帧都能放入 BRAM。

## P2：burst 与硬件 line buffer

当前 `sdram_data_ctrl` 为 closed-page、single outstanding、单次 32-bit 访问；burst 指一次 SDRAM READ/WRITE 命令后连续传输多个相邻 word，而不是每个 word 都重新 ACT/PRECHARGE。它属于 controller 或 DMA 设计，不是普通 C 循环能“打开”的选项。

只有在 P0/P1 仍显示连续访问成本主导时，再建立独立 issue：

1. 定义 block/burst request 接口及最大长度；
2. 保持 MMIO 非缓存、非 burst，明确 BRAM/SDRAM 边界；
3. 扩展 `sdram_x16_model` 测试，覆盖 burst 中断、边界、refresh 和错误收口；
4. 先做 controller 仿真，再做 MiniSoC regression，最后上板。

硬件 line buffer 同样只应服务明确的流式模块，例如图像 accelerator 或 VGA 数据通路；不要为一般 CPU 负载先做一套专用硬件。

## P3：Cache 的准入条件

D-cache 需要 tag RAM、valid/dirty、替换、写策略、MMIO bypass、flush/错误处理和更大验证面。只有满足下列条件时才启动：

- P0/P1 的软件优化已量化但不足；
- 目标 workload 有稳定的空间/时间局部性；
- 资源报告仍有足够 BRAM/LUT；
- 可以为 Pico/Dark 统一定义数据访问行为。

第一版若实施，应选择小型 direct-mapped、write-through，并把 MMIO 固定 bypass；不要一开始实现 write-back 或多级 Cache。

## 上板验证矩阵

完整板级性能结论需要以下两份 bitstream 和同一份 firmware：

| 项目 | Pico | Dark |
| --- | --- | --- |
| 顶层 parameter | `CPU_IMPL=0` | `CPU_IMPL=1` |
| firmware / 输入 | 完全相同 | 完全相同 |
| 功能门槛 | `sdram_memtest` UART PASS、LED=5 | 同左 |
| benchmark | `perf_mix`、`system_bench`、`median`、`memcpy` | 同左 |
| 重复次数 | 每项复位重跑至少 3 次 | 每项复位重跑至少 3 次 |
| PPA 证据 | XST、Map、PAR、Timing Report | 同左 |

每轮必须保存：bitstream/firmware 的 commit 与 hash、ISE 工程参数、UART 原始日志、`cycles / instret / mem_wait`、LUT/FF/BRAM、timing slack/Fmax。对相同 firmware，先确认两核 `instret` 一致，再讨论 CPI；用 post-route `Fmax / CPI` 计算实际吞吐量，不用 1 MHz 仿真 KIPS 代替板级结果。

当前 `probe_minisoc_sdram` ISE export 固定打包 `sdram_memtest`。开始此矩阵前，应先给 export 脚本增加显式 firmware 覆盖入口，避免人工替换 `firmware.mem` 导致不可复现。
