# SDRAM Data Controller V1 设计说明

## 目标

在不直接修改 SoC 顶层接线的前提下，先实现并验证一个可独立工作的 SDRAM 数据控制器子系统：

- 模块：`rtl/soc/sdram_data_ctrl.v`
- testbench：`sim/tb_sdram_data_ctrl.v`

V1 的目标不是“功能最全”，而是“边界清晰、行为稳定、可本地测穿”，为后续 M2b/SoC 接入提供可信基础。

## 设计决策

### 数据宽度方案（V1 定案）

- 采用 **U2 单片 x16** 路径。
- Host 侧保留 32-bit 访问语义，控制器内部拆为两个 16-bit beat（low/high）。
- 暂不做 U2/U3 lockstep x32。

这样选择的原因：

- 与仓库现有 Probe 4a / Probe 4 的单片路径连续。
- 状态机和验证矩阵更小，首版风险更可控。
- 后续扩展到 x32 时，不影响本版控制器基本命令链路结论。

### 地址映射（V1 固定）

内部按 halfword 地址（`byte_addr >> 1`）分解：

- `row`: 12 bit
- `bank`: 2 bit
- `col`: 9 bit

即：

```text
haddr[22:11] -> row[11:0]
haddr[10:9]  -> bank[1:0]
haddr[8:0]   -> col[8:0]
```

32-bit 访问对应：

```text
lo beat: col
hi beat: col + 1
```

并规定：

- V1 仅接受 32-bit 对齐访问（`addr[1:0]==0`）
- misaligned 返回错误响应（`resp_err=1`）

### 控制策略（V1）

- 固定 **closed-page**
- single outstanding request
- 单次 read / write
- 每次访问显式执行：

```text
ACT -> READ/WRITE -> PRECHARGE
```

不要求（且不实现）：

- burst
- cache / prefetch
- 多请求仲裁
- 运行时行保持（open-page policy）

### refresh 策略（V1）

- 使用固定周期计数器产生 refresh 请求（`refresh_pending`）。
- 仅在 `IDLE` 插入 `AUTO REFRESH`。
- 不抢占当前正在执行的请求（V1 单请求模型）。

初始化后 refresh 逻辑持续运行。

## 状态机

V1 建议状态流转：

```text
RESET
 -> INIT_WAIT
 -> INIT_PRECHARGE_ALL
 -> INIT_AR1
 -> INIT_AR2
 -> INIT_MRS
 -> IDLE
 -> (REFRESH 或 REQUEST_PATH)
 -> IDLE
```

请求路径：

- 读：`ACT -> tRCD -> READ(lo) -> CL -> CAP_LO -> READ(hi) -> CL -> CAP_HI -> PRE -> tRP -> RESP`
- 写：`ACT -> tRCD -> WRITE(lo) -> WRITE(hi) -> tWR -> PRE -> tRP -> RESP`

## 接口定义（简化）

Host 侧：

- 输入：`req_valid, req_we, req_addr, req_wdata[31:0], req_wstrb[3:0]`
- 输出：`req_ready, resp_valid, resp_rdata[31:0], resp_err`

SDRAM 侧：

- 命令/地址：`sdram_cke, sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n, sdram_ba, sdram_addr`
- 数据：`dq_in, dq_out, dq_oe, sdram_dqm`

DQ 方向规则：

- 写状态：`dq_oe=1`（FPGA 驱动）
- 读/空闲：`dq_oe=0`（高阻/输入）

`wstrb` 到 DQM：

- low beat 使用 `wstrb[1:0]`
- high beat 使用 `wstrb[3:2]`

## 验收范围（本地不上板）

### 模块级最小覆盖

- 上电初始化完整走通
- 至少一次 refresh 插入
- 单次写、单次读
- 读延迟（CL）等待
- DQ 输出使能切换（写驱动、读高阻）
- reset 打断后回到可服务状态

### 子系统级一致性

- 地址分解自洽（bank/row/column）
- 32-bit 请求拆为两次 16-bit 访问且拼接正确
- misaligned 请求路径有明确错误行为

### 本地命令

```bash
bash scripts/check_rtl_syntax.sh
./sim/run_sim.sh sdram_data_ctrl
```

验收输出建议包含：

- PASS/FAIL 日志
- 关键波形（初始化、读、写、refresh、reset）

## 对应文件

- `rtl/soc/sdram_data_ctrl.v`
- `sim/tb_sdram_data_ctrl.v`

相关参考（仓库内）：

- `rtl/probe/sdram_smoke_ctrl.v`
- `rtl/probe/sdram_tester_ctrl.v`
- `rtl/probe/probe_sdram_smoke_top.v`
- `docs/PROBES.md`
- `docs/02.TEC-PLUS核心板使用指南V2.0.0(出厂版).md`
- `docs/03.TEC-PLUS核心板FPGA引脚定义(更新).md`

## 边界

- 本文档对应 V1；它不是完整 SoC 内存子系统规格。
- V1 结论仅覆盖“可工作的最小 SDRAM 数据控制器”。
- x32 lockstep、burst、仲裁与性能优化留待后续版本。
