//by ds
SDRAM Data Controller V1 设计说明
1. 目标
在不直接修改 SoC 顶层接线的前提下，先实现并验证一个可独立工作的 SDRAM 数据控制器子系统：

模块：rtl/soc/sdram_data_ctrl.v

Testbench：sim/tb_sdram_data_ctrl.v

V1 的目标是“边界清晰、行为稳定、可本地测穿”，为后续 SoC 接入提供可信基础。

2. 设计决策
2.1 数据宽度方案
采用 单颗 x16 SDRAM（U2） 数据路径。

Host 侧保留 32‑bit 访问语义，控制器内部拆为两个 16‑bit beat（低半字、高半字）。

暂不实现 U2/U3 双片 x32 锁步模式。

理由：与仓库现有 Probe 4a / Probe 4 的单片路径保持一致，状态机和验证矩阵更小，首版风险可控；后续扩展 x32 时不改变本版控制器的命令链路基本结论。

2.2 地址映射（固定）
内部使用半字地址 haddr = byte_addr[24:1]（即 SDRAM 窗口内 byte address >> 1），分解如下：

text
haddr[23:11] → row[12:0]   (13 bits)
haddr[10:9]  → bank[1:0]   (2 bits)
haddr[8:0]   → col[8:0]    (9 bits)
32‑bit 访问对应两个 beat：

text
低半字 beat：col = haddr[8:0]
高半字 beat：col = haddr[8:0] + 1
对齐要求：V1 仅接受 32‑bit 对齐访问（req_addr[1:0] == 2'b00），非对齐请求直接返回 resp_err=1，不执行任何 SDRAM 操作。

2.3 控制策略
固定 closed‑page：每次访问结束后都执行 PRECHARGE。

单 outstanding 请求：当前请求完成前不接收新请求（req_ready 在 IDLE 时有效）。

单次 读 或 写，不支持突发（burst）或缓存。

访问流程固定为：

text
ACT → tRCD → (READ/WRITE beats) → (tWR for write) → PRECHARGE → tRP → RESP
不实现 open‑page、行保持或仲裁。

2.4 刷新策略
使用 refresh_age 统计距离上一次“实际发出 AUTO REFRESH”已经过去的周期数。
当 refresh_age 到达 REFI_CYCLES 时置位 refresh_pending。

HY57V2562 要求 8192 次 refresh / 64 ms，平均间隔不超过 7.8125 µs。板级默认按 50 MHz 使用 `REFI_CYCLES=300`（6.0 µs）和 `REFRESH_DEFER_CYCLES=32`，为正在执行的事务收尾留出余量。

刷新仅在 ST_IDLE 状态启动，不会抢占正在进行的访问（符合单请求模型）。

允许在持续流量下对周期 refresh 做有限延期；当 refresh_age 超过
(REFI_CYCLES + REFRESH_DEFER_CYCLES) 的 overdue 窗口后，会置位 force_refresh，
保证下一次回到 ST_IDLE 时必须先 refresh，避免长期饥饿。

刷新命令发出后进入 ST_REF_TRFC 等待 tRFC，完成后返回 IDLE。

3. 状态机
完整状态机定义如下（状态名与 RTL 一致）：

text
复位/上电：
  ST_PWRUP_WAIT → ST_WAIT_PWRUP（等待 PWRUP_WAIT_CYCLES）

初始化序列：
  ST_INIT_PRE     → 发出 PRECHARGE ALL (A10=1)
  ST_INIT_TRP     → 等待 tRP
  ST_INIT_AR1     → 发出第 1 次 AUTO REFRESH
  ST_INIT_TRFC1   → 等待 tRFC
  ST_INIT_AR2     → 发出第 2 次 AUTO REFRESH
  ST_INIT_TRFC2   → 等待 tRFC
  ST_INIT_MRS     → 发出 LOAD MODE REGISTER
  ST_INIT_TMRD    → 等待 tMRD
  → ST_IDLE

空闲与刷新：
  ST_IDLE         → 若 force_refresh，则先执行：
                     ST_REF_TRFC  → 发出 AUTO REFRESH 并等待 tRFC → ST_IDLE
                   若无 force_refresh 且有有效主机请求，则优先接收该请求
                   若无 force_refresh、无有效主机请求但 refresh_pending=1，则执行：
                     ST_REF_TRFC  → 发出 AUTO REFRESH 并等待 tRFC → ST_IDLE
                   若以上条件都不满足，则置 req_ready=1
  其中 refresh_pending 表示已到周期 refresh 点，force_refresh 表示已经超过允许延期窗口；
  前者可在持续流量下短暂延后，后者必须在下一次回到 IDLE 时先 refresh。

读操作路径：
  ST_IDLE 接收读请求 → 发出 ACT → ST_TRCD (等待 tRCD)
  ST_RD_CMD_LO   → 发出 READ (低半字) 
  ST_RD_CL_LO    → 等待 CAS 延迟 (CL)
  ST_RD_CAP_LO   → 捕获低半字数据
  ST_RD_CMD_HI   → 发出 READ (高半字)
  ST_RD_CL_HI    → 等待 CAS 延迟 (CL)
  ST_RD_CAP_HI   → 捕获高半字数据
  ST_PRE         → 发出 PRECHARGE (针对当前 bank, A10=0)
  ST_TRP         → 等待 tRP
  ST_RESP        → 返回读取数据 (resp_valid, resp_rdata)

写操作路径：
  ST_IDLE 接收写请求 → 发出 ACT → ST_TRCD (等待 tRCD)
  在 ST_TRCD 最后一个周期提前置 dq_oe=1 并驱动低半字数据
  ST_WR_CMD_LO   → 发出 WRITE (低半字)，应用 wstrb[1:0] 到 DQM
  ST_WR_CMD_HI   → 发出 WRITE (高半字)，应用 wstrb[3:2] 到 DQM，并更新 dq_out 为高半字
  ST_TWR         → 等待 tWR (保持 dq_oe=0)
  ST_PRE         → 发出 PRECHARGE (针对当前 bank)
  ST_TRP         → 等待 tRP
  ST_RESP        → 返回写响应 (resp_valid=1, resp_err=0)
注意：非对齐请求在 ST_IDLE 收到后会直接跳转至 ST_RESP 并置 resp_err=1，不经过 ACT/PRECHARGE 等操作。

4. 接口定义
4.1 Host 请求接口（单 outstanding）
信号	方向	宽度	说明
req_valid	I	1	请求有效
req_ready	O	1	控制器可接受新请求（IDLE 时有效）
req_we	I	1	1=写，0=读
req_addr	I	32	字节地址（必须 4 字节对齐）
req_wdata	I	32	写数据
req_wstrb	I	4	写字节使能（每 bit 对应一个字节）
resp_valid	O	1	响应有效
resp_rdata	O	32	读返回数据
resp_err	O	1	错误标志（非对齐访问）
4.2 SDRAM 物理接口
信号	方向	宽度	说明
sdram_cke	O	1	时钟使能（常高）
sdram_cs_n	O	1	片选（低有效）
sdram_ras_n	O	1	行地址选通
sdram_cas_n	O	1	列地址选通
sdram_we_n	O	1	写使能
sdram_ba	O	2	Bank 地址
sdram_addr	O	13	地址线（含 A10 用于预充电）
sdram_dqm	O	2	数据掩码（低有效，1 表示屏蔽）
dq_in	I	16	SDRAM 输出数据（读）
dq_out	O	16	FPGA 输出数据（写）
dq_oe	O	1	输出使能，1=驱动 dq_out，0=高阻
4.3 DQ 方向与 DQM 规则
读：dq_oe = 0，FPGA 数据总线为输入。

写：dq_oe = 1，FPGA 驱动 dq_out。

DQM 映射：

低半字 beat 使用 ~wstrb[1:0]（即需写出的字节对应 DQM=0，屏蔽的字节 DQM=1）

高半字 beat 使用 ~wstrb[3:2]

注意：写数据在 ST_TRCD 最后一个周期提前驱动 dq_out 为低半字，以满足 SDRAM 的写数据建立时间要求。

5. 时序参数与配置
所有时序参数均通过模块参数传递，仿真时可缩短，实际使用根据 SDRAM 芯片和时钟频率配置。

参数名	默认值	说明
PWRUP_WAIT_CYCLES	10000	上电等待周期数
TRP_CYCLES	3	预充电周期
TRFC_CYCLES	7	刷新周期
TMRD_CYCLES	2	模式寄存器设置周期
TRCD_CYCLES	3	行激活到读写命令延时
TWR_CYCLES	3	写恢复时间
CAS_LATENCY_CYCLES	2	CAS 延迟（读取时）
REFI_CYCLES	300	刷新间隔（50 MHz 下 6.0 µs）
REFRESH_DEFER_CYCLES	32	允许的延期窗口，之后强制在下一个 IDLE 刷新
MODE_REG_VALUE	13'h220	模式寄存器值（BL=1, 顺序, CL=2）
6. 复位行为
复位（reset=1）将状态机置于 ST_PWRUP_WAIT，所有输出信号置为默认安全值（dq_oe=0，命令为 NOP 等）。

退出复位后自动执行完整的初始化序列，完成后进入 ST_IDLE 并置 req_ready=1。

复位期间不响应主机请求。

7. 验证与验收（本地仿真）
7.1 测试覆盖点（tb_sdram_data_ctrl.v）
✅ 上电初始化顺序正确（PRECHARGE ALL → 2 × AUTO REFRESH → LOAD MODE）。

✅ 初始化完成后至少观察到一次刷新命令。

✅ 对齐的 32‑bit 写 / 读回验证。

✅ 对仅相差 A12 的低/高半区地址分别写读，确认 16/32 MiB 不发生 alias。

✅ 部分写（字节使能）后读回校验。

✅ 非对齐访问返回 resp_err，且不访问 SDRAM。

✅ 读、写命令期间 dq_oe 电平正确（写=1，读=0）。

✅ 读数据在 CAS 延迟后正确返回。

✅ 强制刷新机制在长时间忙碌时插入刷新（基于 refresh_age 与延期窗口观察）。

8. M2.5 firmware 验收与 benchmark baseline

`sdram_memtest` 覆盖固定 pattern、跨 bank/row 的散列地址、16/32 MiB 边界不 alias，以及连续 64 个 word 的顺序写读回。默认双核 regression 已包含该测试：

```bash
TESTS="smoke alu_branch load_store counters perf_mix sdram_memtest" \
  bash scripts/test_dual_core_regression.sh
```

固定求和 benchmark 使用 `1024` 个 32-bit word，填充 `a[i] = i` 后顺序求和。运行方式：

```bash
FIRMWARE_MAIN="$PWD/firmware/tests/sdram_sum_bench.c" \
  ./sim/run_sim.sh minisoc_sdram_pico
FIRMWARE_MAIN="$PWD/firmware/tests/sdram_sum_bench.c" \
  ./sim/run_sim.sh minisoc_sdram_dark
```

在当前 RTL、`1 MHz` testbench 时钟配置下，基线如下：

| CPU | words | sum | cycle delta | instret delta |
| --- | ---: | ---: | ---: | ---: |
| PicoRV32 | 1024 | `0x0007fe00` | 51401 | 4101 |
| DarkRISCV | 1024 | `0x0007fe00` | 34832 | 4101 |

这里的 `cycle/instret` 是 firmware 测量区间内的 core counter 差值，只用于相同输入规模和相同 RTL 配置下的后续对比；CPU、控制器或时序策略变化后应重新采集。
