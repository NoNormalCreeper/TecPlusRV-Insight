# DOT4 上板人工验证记录

## 结论

本报告记录 issue #29 中 DarkRISCV custom-0 `dot4.s8` 指令的阶段性人工验证结果。当前已经确认：

- `dot4_bench` 在真实开发板 UART 输出 `PASS`；
- scalar 与 custom DOT4 的 checksum 一致；
- custom DOT4 的 `cycles` 与 `instret` 明显低于 scalar 版本；
- ISE Map 阶段资源可放下，错误数为 0；
- `DSP48A1 = 4`，符合四路 signed INT8 乘法被综合为硬件乘法资源的预期。
- ISE timing 对 20 ns / 50 MHz 约束的 SETUP 与 HOLD 检查均通过。
- Map Report 中未检索到 `OVERMAPPED`。

当前尚未确认：

- `g_darkriscv` 在 hierarchy 或 report 中的直接层级名证据。

因此本轮可以写作“DOT4 功能上板通过，Map 资源阶段通过，50 MHz timing 通过”。XST report 已出现 `Unit <u_dot4>`，说明 DOT4 单元没有被整体 trim；`g_darkriscv` 文本检索未命中时，不能把它当作 CPU 路径错误的证据，ISE 可能在综合、Map 或导出流程中 flatten / rename 层级。当前用 `CPU_IMPL=1`、UART `PASS`、checksum 一致、custom cycles 明显降低以及 `DSP48A1=4` 作为 DarkRISCV DOT4 路径工作的证据。

需要注意：issue #29 中提到的“资源增量”尚未完整闭环。当前已经有 DOT4 版本的绝对资源使用量，但还缺共同基线 `35968e6` 上 `minisoc_dark` 的同口径 Map/PAR/Timing 数据，因此暂时不能计算严格的 baseline -> DOT4 增量。

## 验证环境

| 项目 | 内容 |
| --- | --- |
| 分支 | `feat/darkriscv-dot4` |
| 记录 commit | `6b980ac` |
| ISE target | `minisoc_dot4_dark` |
| top module | `tecplus_minisoc_top` |
| CPU 参数 | `CPU_IMPL=1` |
| bootloader 参数 | `BOOTLOADER_ENABLE=1` |
| VGA text 参数 | `VGA_TEXT_ENABLE=0` |
| UART benchmark | `make dot4-load PORT=COM9 BOOTLOAD_BAUD=115200` |

数据来源为本轮人工操作中从 ISE report 与 UART monitor 手动摘录的文本。当前仓库尚未归档完整 `.mrp`、`.par`、`.twr` 或串口原始日志文件。

## Issue #29 Gate 对照

| Gate | 当前状态 | 依据 | 备注 |
| --- | --- | --- | --- |
| ISE Map | 已有结果 | Map errors=0，资源表已记录，未检索到 `OVERMAPPED` | 当前为 DOT4 版本绝对资源 |
| ISE PAR | 已有流程证据 | 已生成 post-route timing，并且 bitstream 可上板运行 UART benchmark | 尚未单独归档 PAR report 原文 |
| ISE Timing | 通过 | 20 ns 约束下 SETUP slack=0.650 ns，HOLD slack=0.343 ns，timing errors=0 | 50 MHz 余量较小，后续改动需重跑 |
| 资源增量 | 未完整 | DOT4 版本资源已记录 | 缺 baseline `35968e6` 的同口径资源与 timing |
| 真实开发板 UART benchmark | 通过 | `dot4_bench` 输出 scalar/custom 两组 `RESULT` 并最终 `PASS` | checksum 一致，custom cycles/instret 更低 |

## 本地 preflight

上板前已运行：

```bash
make dot4-bench
```

本地仿真结果：

| mode | checksum | cycles | instret | mem_wait |
| --- | ---: | ---: | ---: | ---: |
| scalar | `0x00000170` | 694304 | 242721 | 22548 |
| custom | `0x00000170` | 25760 | 6721 | 6164 |

仿真中 custom DOT4 相对 scalar 的 cycle speedup 约为 `26.95x`。

## ISE Map 资源记录

用户从 ISE Map Report 摘录：

| 资源 | 使用量 | 总量 | 利用率 |
| --- | ---: | ---: | ---: |
| Slice | 1319 | 1430 | 92% |
| Slice Registers / FF | 1607 | 11440 | 14% |
| Slice LUTs | 4200 | 5720 | 73% |
| RAMB16BWER | 32 | 32 | 100% |
| RAMB8BWER | 0 | 64 | 0% |
| DSP48A1 | 4 | 16 | 25% |

同时记录：

```text
Number of errors: 0
Number of warnings: 42
```

判断：

- Slice 利用率已经达到 92%，后续继续增加逻辑会很紧张；
- RAMB16BWER 已经 100% 用满，后续不能再轻易增加片上 BRAM；
- DSP48A1 使用 4 个，符合 DOT4 四路乘法的实现预期；
- Map 错误数为 0，是资源阶段可继续推进的正向证据；
- Map Report 中未检索到 `OVERMAPPED`，当前记录为无 overmap 证据。

层级名与 trim 检查：

- XST report 中出现 `Unit <u_dot4>`，这是 DOT4 单元存在的直接证据；
- XST 同时报告 `u_dot4` 内部部分 `result_*` FF/Latch 等价并被移除，例如 `result_17` 等价于若干高位 result 寄存器；
- 这类优化不是 `u_dot4` 被整体 trim，而是 XST 对等价寄存器位做合并/删除；DOT4 signed 结果存在符号扩展和等价高位时，出现这类优化是可以接受的；
- 用户在 report / hierarchy 文本中尚未检索到 `g_darkriscv`；这不等价于 CPU 路径错误，因为 ISE 可能 flatten / rename 层级；
- 如需更强证据，可在 ISE 中开启 `Keep Hierarchy = Yes` 后重新综合，或保存 Technology Schematic / FPGA Editor 中对应 DOT4 乘法路径的截图。

## 资源增量状态

当前只有 DOT4 版本的绝对资源数据：

| 配置 | Slice | LUT | FF | RAMB16BWER | DSP48A1 | 50 MHz setup slack |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| DarkRISCV + DOT4 (`6b980ac`) | 1319 | 4200 | 1607 | 32 | 4 | 0.650 ns |
| DarkRISCV baseline (`35968e6`) | 待补充 | 待补充 | 待补充 | 待补充 | 待补充 | 待补充 |
| 增量 | 待计算 | 待计算 | 待计算 | 待计算 | 待计算 | 待计算 |

因此现在可以报告“DOT4 版本资源可放下”，但不能报告“DOT4 相比 baseline 的资源增量”。若要完成资源增量，需要对 `build/ise-export/minisoc_dark_baseline-35968e6` 运行同样 ISE 设置，并记录同口径 Map/PAR/Timing。

## 上板 UART benchmark

用户从串口 monitor 摘录：

```text
RESULT: benchmark=dot4 mode=scalar vectors=32 rounds=16 checksum=0x00000170 cycles=694304 instret=242721 mem_wait=22548
RESULT: benchmark=dot4 mode=custom vectors=32 rounds=16 checksum=0x00000170 cycles=25760 instret=6721 mem_wait=6164
PASS
```

结构化结果：

| mode | checksum | cycles | instret | mem_wait |
| --- | ---: | ---: | ---: | ---: |
| scalar | `0x00000170` | 694304 | 242721 | 22548 |
| custom | `0x00000170` | 25760 | 6721 | 6164 |

计算得到：

| 指标 | 数值 |
| --- | ---: |
| cycle speedup | 26.95x |
| instret reduction | 36.11x |
| mem_wait reduction | 3.66x |

判断：

- checksum 一致，说明 custom DOT4 与 scalar 参考实现计算结果一致；
- `PASS` 出现，说明 firmware 内部 correctness 与 performance expectation 均通过；
- custom 的 cycle / instret 显著下降，符合 issue #29 的性能预期。

## Timing 状态

用户从 ISE timing summary 摘录：

```text
Constraint: TS_clk_grp = PERIOD TIMEGRP "clk_grp" 20 ns HIGH 50%
SETUP Worst Case Slack: 0.650 ns
SETUP Best Case Achievable: 19.350 ns
SETUP Timing Errors: 0
SETUP Timing Score: 0
HOLD Worst Case Slack: 0.343 ns
HOLD Timing Errors: 0
HOLD Timing Score: 0
```

判断：

- 目标时钟为 50 MHz，对应周期为 20 ns；
- SETUP slack 为 `0.650 ns`，为正；
- HOLD slack 为 `0.343 ns`，为正；
- timing errors 为 0，timing score 为 0；
- `Best Case Achievable = 19.350 ns`，折合约 `51.68 MHz`，说明对 50 MHz 约束有约 `0.650 ns` 余量。

因此当前记录为：

```text
Target period: 20 ns
50 MHz setup slack: 0.650 ns
50 MHz hold slack: 0.343 ns
Best case achievable period: 19.350 ns
Best case achievable frequency: 51.68 MHz
Timing conclusion: PASS
```

注意：这组 timing 余量不大，后续再增加逻辑、打开 VGA text 或修改约束后必须重新跑 Post-Place & Route timing。

## PAR 状态

当前没有单独摘录 PAR report 的 `Place & Route completed successfully` 原文。不过本轮已经拿到 post-place & route timing summary，并且生成的 bitstream 已经完成真实开发板 UART benchmark，因此可以作为 PAR 流程已跑通的证据。

为了报告更严谨，后续可以补充 PAR report 中的 summary 原文，例如：

```text
Place & Route completed successfully
Number of errors: 0
```

## 当前收口状态

| Gate | 状态 | 说明 |
| --- | --- | --- |
| DOT4 RTL / MiniSoC 仿真 | 通过 | `make dot4-bench` 通过，cycle speedup 约 26.95x |
| ISE Map 资源 | 阶段通过 | Map errors=0，资源可放下；Slice/RAMB 使用率较高 |
| 资源增量 | 待补充 | 已记录 DOT4 版本绝对资源；缺 baseline `35968e6` 同口径数据 |
| DSP 推断 | 有正向证据 | DSP48A1=4 |
| 真实开发板 UART benchmark | 通过 | checksum 一致，输出 `PASS` |
| OVERMAPPED 显式检查 | 通过 | Map Report 中未检索到 `OVERMAPPED` |
| `u_dot4` 层级名检查 | 通过 | XST report 出现 `Unit <u_dot4>`；仅内部等价 `result_*` FF 被优化 |
| `g_darkriscv` 层级名检查 | 未取得直接证据 | 文本检索未命中；以 `CPU_IMPL=1`、DSP48A1=4 与 UART PASS 作为间接证据 |
| 50 MHz post-route timing | 通过 | SETUP slack=0.650 ns，HOLD slack=0.343 ns，timing errors=0 |
