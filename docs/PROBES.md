# 探针测试说明

本文档描述 TecPlusRV 第一阶段的 bring-up 探针。这里的“探针”不是项目最终功能，而是最早期风险排查手段，用来快速回答几个问题：

- 板卡时钟是不是正常
- `reset` / `KEY` / `LED` / `UART` 的板级链路是不是通的
- 当前 UCF 假设和实验室实际板卡是不是一致
- 在继续做 CPU / bus / BRAM / MiniSoC 之前，本地和板级最小闭环是不是已经成立

## 当前 Probe 状态总览

| Probe | 名称 | 当前状态 | 当前仓库是否已给出可用文件 |
| --- | --- | --- | --- |
| Probe 0 | `LED / KEY / RESET / CLK` | 已实现 | 是 |
| Probe 1 | `UART TX` | 已实现 | 是 |
| Probe 2a | `PicoRV32 Minimal synthesis probe` | 已定义流程 | 部分 |
| Probe 2b | `DarkRISCV Minimal synthesis probe` | 已定义流程 | 部分 |
| Probe 3 | `MiniSoC dual-core simulation probe` | 已实现 | 是 |
| Probe 4a | `SDRAM smoke probe` | 已实现 | 是 |
| Probe 4 | `SDRAM standalone tester` | 独立 tester 初版已实现 | 是 |
| Probe 5a | `bigboard traffic-light thin probe` | 已实现 | 是 |
| Probe 5 | `显示 / 大板外设探针` | 计划中，full 版未实现 | 否 |

这里要特别说明四点：

- `Probe 4a` 和 `Probe 5a` 是 thin probe，目标是提早排雷，不是假装 full 功能已经完成。
- `Probe 4` 已有独立 tester 初版，但仍然不是 SoC 级通用 SDRAM controller。
- `Probe 5` 的 full 版现在仍然没有对应 RTL 顶层，不是漏做，而是当前任务边界故意停在“基础框架 + 探针测试”。
- 任务说明明确要求不要伪造 `SDRAM controller`，因此当前 `Probe 4` 只宣称“独立 tester”，不宣称已经能给 MiniSoC 当 SDRAM 子系统。

## 先做什么，不要先做什么

如果你第一次把这个仓库带去实验室，建议顺序固定为：

1. `Probe 0`
2. `Probe 1`
3. `Probe 2a`
4. `Probe 2b`
5. `Probe 3` 对照本地结果做联调
6. `Probe 4a`
7. `Probe 4`
8. `Probe 5a`

不建议的顺序：

- 不要在 `Probe 0` 没过时去调 `UART`
- 不要在 `Probe 1` 没过时去调完整 `MiniSoC`
- 不要在 `LED` / `UART` 都还不稳定时就去怀疑 CPU wrapper、bus、BRAM 初始化或 `memory map`

原因很简单：如果最基础的板级输入输出都还没确认，后面出现任何 SoC 级故障时，你会失去最基本的定位手段。

## Probe 0：LED / KEY / RESET / CLK

### 目标

确认 TEC-PLUS 上与最小交互相关的板级链路已经打通：

- `CLK`
- `RESET`（板上实测按低有效处理）
- `KEY[3:0]`
- `LED[3:0]`

### 对应文件

- 顶层：`rtl/probe/probe_led_key_top.v`
- 约束：`constraints/tecplus_led_key.ucf`

### 接口说明

- 输入：`clk`
- 输入：`reset`
- 输入：`key[3:0]`
- 输出：`led[3:0]`

### 设计行为

- `reset=0` 时，`led[3:0]` 全灭
- `reset=1` 后，LED 进入跑马灯
- `KEY1` 改变跑马灯速度
- `KEY2` 切换固定显示模式
- 默认按 `50MHz` 时钟假设设计

### 你在实验室里应该怎么做

1. 打开 ISE 14.7，新建工程。
2. 器件选择 `Spartan-6 XC6SLX9-2FTG256`。
3. 把 `rtl/probe/probe_led_key_top.v` 加入工程。
4. 把 `constraints/tecplus_led_key.ucf` 设为约束文件。
5. 运行 `Synthesize`、`Implement Design`、`Generate Programming File`。
6. 用下载器把生成的 bitstream 下载到板卡。
7. 上电后先不要按键，先观察 LED 是否在 `reset` 释放后开始跑马灯。
8. 按 `KEY1`，观察跑马灯速度是否变化。
9. 按 `KEY2`，观察是否切到固定显示模式。
10. 再次按下 `RESET`，确认 LED 会全灭；松开后重新开始。

### 成功标准

- 下载后板卡有稳定、可重复的 LED 现象
- `KEY1` 和 `KEY2` 的作用能明显区分
- `reset` 行为稳定，不是偶发有效

### 如果失败，先查什么

- `clk` 管脚是否绑对
- `reset` 是否确认为低有效，而不是高有效
- `KEY` 是否为低有效，而你在 UCF 或 RTL 假设成了高有效
- `LED` 管脚顺序是否和文档一致
- 实验室板卡版本是否和当前仓库参考文档一致

### 这一步的意义

这一步通过后，你至少知道三件事：

- FPGA 时钟进来了
- bitstream 可以正常下载并运行
- 你对最基本的 `input/output` 管脚理解大概率没有严重偏差

## Probe 1：UART TX

### 目标

确认串口发送链路已经打通：

- FPGA 内部 `uart_tx.v` 工作正常
- `UART TXD` UCF 约束没有明显错误
- 主机侧串口工具参数设置正确
- 板上串口桥链路可用

### 对应文件

- 顶层：`rtl/probe/probe_uart_top.v`
- 约束：`constraints/tecplus_uart.ucf`
- 发送器：`rtl/periph/uart_tx.v`

### 接口说明

- 输入：`clk`
- 输入：`reset`
- 输出：`uart_txd`
- 预留输入：`uart_rxd`

### 设计行为

- `reset=1` 后，周期性发送 `Hello TecPlusRV\r\n`
- 当前只保证 `TX`
- `RX` 这次只是预留，不做 `echo`

### 你在实验室里应该怎么做

1. 在 ISE 里新建或切换到独立工程。
2. 加入 `rtl/probe/probe_uart_top.v` 和 `rtl/periph/uart_tx.v`。
3. 加入 `constraints/tecplus_uart.ucf`。
4. 重新生成 bitstream 并下载到板卡。
5. 用主机打开板载串口对应的终端程序。
6. 串口参数设为 `9600 8N1`，并关闭奇偶校验和流控。
7. 按一次 `reset`，从串口终端开始观察输出。
8. 如果终端持续收到 `Hello TecPlusRV`，说明 `Probe 1` 基本通过。

### 成功标准

- 串口终端能重复看到完整字符串
- 不是乱码，不是偶发一两个字符
- 重置后现象可重复

### 如果失败，先查什么

- `TXD` 管脚是否正确
- 串口工具是不是接到了正确的端口
- 波特率是不是 `9600`
- 帧格式是不是 `8N1`
- `reset` 是否因为低有效理解错误而一直保持在复位状态
- 板卡是否真的是 `50MHz` 时钟前提

### 这一步的意义

这一步通过后，后续调 SoC 时你就有一个最基本的文本输出通道，不用每次都靠 LED 猜状态。

## Probe 2：CPU Minimal synthesis probe

### 目标

在真正做 `MiniSoC` 之前，先判断一个尽量小的 CPU + BRAM + MMIO 组合在 `XC6SLX9` 上是否现实，避免后面做了很多集成工作才发现资源根本不够。

当前建议把这一步拆成两支并排记录：

- `Probe 2a`：PicoRV32 minimal
- `Probe 2b`：DarkRISCV + wrapper

### 当前仓库提供了什么

- `rtl/soc/mmio_test_exit.v`
- `rtl/soc/bram.v`
- `rtl/soc/bram_dualport.v`
- `rtl/soc/tinybus_defs.vh`
- `rtl/soc/tinybus_decode.v`
- `rtl/soc/tecplus_cpu_wrapper.v`
- `rtl/soc/picorv32_adapter.v`
- `rtl/soc/darkriscv_adapter.v`
- `rtl/soc/tecplus_minisoc_top.v`
- `constraints/tecplus_minisoc.ucf`
- `firmware/` 骨架

### 当前仓库没有替你做什么

- 不会伪造资源报告

### 你现在应该怎么做

1. 确认 vendored 的 CPU 核源码已加入 ISE 工程：
   - `Probe 2a`：`rtl/core/picorv32.v`
   - `Probe 2b`：`rtl/core/darkriscv.v`
2. 使用 `tecplus_minisoc_top` 做最小组合：`CPU + 64 KiB BRAM + GPIO + UART TX + test_exit`。
3. 需要时在 ISE 的 `Generics, Parameters` 中覆写：
   - `CPU_IMPL=0`：PicoRV32
   - `CPU_IMPL=1`：DarkRISCV
4. 在 ISE 中跑一次综合/实现，记录 `LUT` / `FF` / `BRAM` / `IOB` / `timing`。
5. 结果按 `2a` 与 `2b` 并排记录，再逐步加 `UART RX`、bootloader 写 BRAM、SDRAM，占用每次单独记录。

### 成功标准

- 能得到可信的综合结果
- 能判断两颗核在同一 SoC 外壳下的资源压力与时序差异
- 能回答“后续还能不能继续加外设”

### 如果失败，先查什么

- vendored 的 CPU 核版本是否包含 ISE 难以接受的写法
- 默认参数是否开了太多功能
- `BRAM` 初始化方式是否影响综合
- Map report 如果是 `IOB` 超限，通常是 top module 选错；如果是 `LUT Memory` 超限，优先检查 `BRAM` 是否被推断成 Block RAM；如果是 `RAMB16BWER` 已满，优先检查当前 64 KiB 启动 BRAM 配置是否过大。

### 这一步的意义

它不是展示 probe，而是资源风险 probe。它回答的是“这条路线值不值得继续堆功能”。

## Probe 3：MiniSoC dual-core simulation probe

### 目标

用真实 `MiniSoC` 板级 top 做本地 smoke。这样即使还没去实验室，也能先验证 PicoRV32 和 DarkRISCV 是否都能通过同一条顶层路径打通 CPU、BRAM、TinyBus、LED 和 UART TX。

### 对应文件

- testbench：`sim/tb_minisoc.v`
- 运行脚本：`sim/run_sim.sh minisoc_smoke_pico`、`sim/run_sim.sh minisoc_smoke_dark`
- `firmware` 构建脚本：`scripts/build_firmware.sh`

### 当前行为

- 如果 CPU 存在并最终写入 `test_exit = 1`，testbench 输出 `PASS`
- 如果写入其他退出码，输出 `FAIL`
- 如果长时间没有写到 `test_exit`，输出 `TIMEOUT`
- 当前默认还要求：UART / LED / `test_exit` 路径都真实发生一次

### 你在本地应该怎么做

1. 先运行：

```bash
scripts/build_firmware.sh
```

2. 再分别运行：

```bash
sim/run_sim.sh minisoc_smoke_pico
sim/run_sim.sh minisoc_smoke_dark
```

3. 看结果属于哪一种：

- `PASS`
- `FAIL`
- `TIMEOUT`

### 结果应该怎么理解

- `PASS`：当前这颗核的 board-top smoke 路径打通
- `FAIL`：CPU 确实跑到了 `test_exit`，但退出码不对
- `TIMEOUT`：CPU 没有在预期时间内完成，通常表示启动链路或地址映射还有问题

### 这一步的意义

它不是通用 firmware regression bench，而是 SoC 集成前的 board-top smoke 防线。后面你改 `memory map`、改 `firmware`、改 `mmio_test_exit` 时，如果只想看软件可见结果是否一致，应优先跑 `minisoc_pico` / `minisoc_dark` 这组通用目标。

## Probe 4a：SDRAM smoke probe

### 目标

在不实现通用 `SDRAM controller` 的前提下，尽早确认 U2 SDRAM 的最小命令链路和固定地址读写回读链路是不是活的。

### 对应文件

- 顶层：`rtl/probe/probe_sdram_smoke_top.v`
- 控制器：`rtl/probe/sdram_smoke_ctrl.v`
- 约束：`constraints/tecplus_sdram_smoke.ucf`
- 本地 testbench：`sim/tb_sdram_smoke_ctrl.v`

### 设计行为

- 上电后等待固定 `power-up wait`
- 发 `PRECHARGE ALL`
- 发两次 `AUTO REFRESH`
- 发一次 `LOAD MODE`
- 对固定地址做一次 `write`
- 再对同一固定地址做一次 `read back`
- 比较读回数据和固定测试字
- 用 `LED` 报状态

### LED 状态建议

- `0001`：初始化阶段
- `0010`：写阶段
- `0100`：读阶段
- `1000`：PASS
- `1111`：FAIL

### 你在实验室里应该怎么做

1. 在 ISE 中创建或切换到独立工程。
2. 加入 `rtl/probe/probe_sdram_smoke_top.v` 和 `rtl/probe/sdram_smoke_ctrl.v`。
3. 加入 `constraints/tecplus_sdram_smoke.ucf`。
4. 确认顶层为 `probe_sdram_smoke_top`。
5. 生成 bitstream 并下载到板卡。
6. 观察板载 `LED` 状态是否最终收敛到 `PASS` 或 `FAIL`。

### 成功标准

- 状态机会稳定运行，不是随机闪烁
- 能稳定落到 `PASS`
- 多次按下再松开 `RESET` 后现象可重复

### 如果失败，先查什么

- SDRAM UCF 是否和当前板卡一致
- `sh_clk`、地址线、控制线、数据线是否存在明显绑错
- 当前 `50MHz` 时钟和时序参数是否过于激进
- 板上使用的是不是文档中的 U2 SDRAM 这一组管脚

### 这一步的边界

它不是通用 `SDRAM controller`，不提供任意地址访问、刷新仲裁或 SoC 级接口。它只回答一个更早期的问题：最小命令链路和固定地址回读是否有基本可行性。

## Probe 4：SDRAM standalone tester

### 当前状态

独立 tester 初版已实现。

### 对应文件

- 顶层：`rtl/probe/probe_sdram_tester_top.v`
- 控制器：`rtl/probe/sdram_tester_ctrl.v`
- 约束：`constraints/tecplus_sdram_tester.ucf`
- 本地 testbench：`sim/tb_sdram_tester_ctrl.v`
- 受控失败 testbench：`sim/tb_sdram_tester_fail.v`
- reset 重复 testbench：`sim/tb_sdram_tester_reset.v`

### 设计行为

- 仍然不接 CPU，不接 MiniSoC，不做 runtime、bootloader 或 UART 错误打印。
- 上电后完成 `PRECHARGE ALL`、两次 `AUTO REFRESH`、`LOAD MODE`。
- 对同一 row 内的一段地址窗口逐字写入 pattern。
- 再对同一地址窗口逐字读回并比较。
- 一轮内默认扫描 `4` 组 pattern。
- 若读回不匹配，继续完成 sweep，同时累计 `error_count` 并锁存第一处错误的地址、pattern、期望值和实际值。
- 每完成一轮后短暂停在 PASS 状态，再用新的 `pass_count` 进入下一轮。
- pattern 包含地址和轮次，因此同一地址在不同轮次写入的数据不同。
- 默认每组 pattern 测试 `256` 个 `16-bit` halfword；当前地址发生器限制在同一 row 的 `10-bit` column 窗口内。

### LED 状态建议

- `0001`：初始化阶段
- `0010`：写地址窗口
- `0100`：读地址窗口
- `1000`：本轮 PASS，随后继续下一轮
- `1111`：FAIL，保持到 reset

### 你在实验室里应该怎么做

1. 在 ISE 中创建或切换到独立工程。
2. 加入 `rtl/probe/probe_sdram_tester_top.v` 和 `rtl/probe/sdram_tester_ctrl.v`。
3. 加入 `constraints/tecplus_sdram_tester.ucf`。
4. 确认顶层为 `probe_sdram_tester_top`。
5. 生成 bitstream 并下载到板卡。
6. 观察 LED 是否重复经历写、读、PASS，且不会稳定到 `1111`。

### 成功标准

- 下载后不是随机闪烁或长期卡在初始化。
- 能重复进入 `1000`，并在 PASS hold 后继续下一轮。
- 多次 reset 后现象可重复。

### 本地验证

```bash
sim/run_sim.sh sdram_tester
sim/run_sim.sh sdram_tester_fail
sim/run_sim.sh sdram_tester_reset
scripts/check_rtl_syntax.sh
```

### 这一步的边界

它是独立 SDRAM tester，不是 SoC 可复用的 SDRAM slave。当前实现优先验证 U2 SDRAM 的初始化、单字写读、DQ 三态、地址/数据/control/UCF 链路，以及“地址 + 轮次”pattern 的读回一致性。它还没有提供 CPU 总线接口、刷新仲裁、burst 访问、完整地址空间遍历或错误地址 UART 打印。

## Probe 5a：bigboard traffic-light thin probe

### 目标

在不引入复杂显示控制逻辑的前提下，先确认大板交通灯输出那组信号是否真的能从 FPGA 打到外设侧。

### 对应文件

- 顶层：`rtl/probe/probe_bigboard_tl_top.v`
- 约束：`constraints/tecplus_bigboard_tl.ucf`
- 本地 testbench：`sim/tb_bigboard_tl.v`

### 设计行为

- `tl[11:0]` 输出一个慢速 one-hot 轮转图样
- 板载 `LED` 作为辅助心跳显示
- 不接 SoC、不接 bus、不接 firmware

### 你在实验室里应该怎么做

1. 确认核心板与大板已经按教学环境要求连接好。
2. 在 ISE 中加入 `rtl/probe/probe_bigboard_tl_top.v`。
3. 加入 `constraints/tecplus_bigboard_tl.ucf`。
4. 生成 bitstream 并下载到板卡。
5. 观察交通灯输出是否按 one-hot 图样轮转。
6. 同时观察板载 `LED` 是否也有辅助变化。

### 成功标准

- 交通灯输出存在稳定、可重复的轮转现象
- 板载 `LED` 也能同步给出辅助心跳
- 多次按下再松开 `RESET` 后现象一致

### 如果失败，先查什么

- 核心板与大板是否真的连接正确
- 交通灯那组管脚约束是否和教学环境一致
- 实验室是否需要额外排线或特定插座连接
- 观察到的是不是大板这一路外设，而不是别的实验区域

### 这一步的边界

它不是完整显示/大板外设系统，也不验证复杂时序外设。它只是回答“这组最小外设输出链路是不是活的”。

## Probe 5：显示 / 大板外设探针

### 当前状态

计划中，full 版当前仍未实现。

### 为什么现在没有

- 第一阶段最关键的是把核心板最小链路打通
- 显示和大板外设 bring-up 会显著增加 UCF、时序、接口和现象判断复杂度
- 如果 `Probe 0` 和 `Probe 1` 还没稳定，就提前接显示类外设，排障成本会迅速失控
- 当前已经先落了 `Probe 5a`，full 版没有必要在第一阶段一起完成

### 这类 Probe 以后应该覆盖什么

- 数码管 / 显示接口
- 更复杂的 GPIO 扩展
- 与大板连接后的额外外设链路

### 当前建议

先把 `LED`、`KEY`、`UART`、双核资源可行性和 `MiniSoC dual-core simulation probe` 稳住，再决定要不要引入这类外设。
