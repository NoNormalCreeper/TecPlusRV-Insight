# 轻量总线整理 Issue 草稿

## 标题

轻量总线整理：从手写 glue 过渡到单主多从 slave 接口

## 建议负责人

SoC 层负责人主导，firmware 层 reviewer，集成负责人审核地址契约

## 背景与地位

当前 `MiniSoC` 已经有一条“总线雏形”，但它还是中间态，而不是一个真正便于扩展的片内互连。现在的结构大致是：

```text
CPU mem_*
-> tecplus_minisoc_top 里的手写分流
-> BRAM 或 TinyBus/MMIO
```

其中 `tinybus_decode.v` 更像一个“写死地址的 MMIO 译码器”，不是统一 slave 接口；`tecplus_minisoc_top.v` 里还保留了较多按外设展开的信号和副作用逻辑。结果就是：每新增一个外设，往往都要同时改地址定义、decode 端口、top 接线、以及部分行为逻辑。

这和当前项目的主线目标并不矛盾，但会拖慢后续开发效率，尤其会让 `M2b / SDRAM data-only MiniSoC 集成`、`bootloader`、以及以后新增外设时的侵入性越来越高。

这个 issue 的目标不是“重做 SoC fabric”，而是做一次**轻量整理**：保持 CPU 仍然是唯一 master，保持 `ifetch_*` 不动，只把当前手写 glue 收敛成统一的单主多从 slave 风格接口，降低后续扩展成本。

## 本 issue 要解决什么

- 定义一个统一的最小 slave 接口，供 BRAM、GPIO、UART、perf、test_exit、SDRAM 等使用
- 让 `tecplus_minisoc_top.v` 从“按外设展开信号”收敛成“单主请求 + 多从命中 + 响应 mux”
- 保持当前 firmware 地址语义不变或尽量少变
- 为后续 `sdram_slave` 接入和新增外设预留稳定接口

## 本 issue 不解决什么

- 不做真正的多主设备仲裁
- 不把 `ifetch_*` 和 `mem_*` 并进统一 fabric
- 不做 cache、burst、DMA、split transaction
- 不改变当前 `BRAM only ifetch` 这个边界
- 不在这里完成 SDRAM controller 本体

## 明确要求

- CPU 仍然是唯一 data master，也就是当前只整理 `mem_*` 这一侧
- `ifetch_*` 继续保持当前直连 BRAM 的小通路，不纳入这次重构
- 第一版 slave 接口只要求支持阻塞式单请求语义，不要求多 outstanding
- 地址图继续由 `tinybus_defs.vh` / `mmio.h` 维持契约，不允许因为这次重构随意改地址
- 允许保留一个很薄的中心 interconnect，但不再接受“每加外设就加一串模块专用端口”的继续扩张

## 推荐接口草案

下面只是推荐方向，不强制逐字照抄，但第一版最好保持这个复杂度级别：

```verilog
input         req_valid
input  [31:0] req_addr
input  [31:0] req_wdata
input  [3:0]  req_wstrb
output        resp_ready
output [31:0] resp_rdata
```

如果某些从设备需要额外状态位，例如 UART `ready` 或 SDRAM `busy`，也尽量通过 `resp_ready` 语义吸收，而不是继续把外设专用握手泄漏到 top 的全局逻辑里。

## 简单实现思路（仅供参考）

最稳的做法不是一下子重写全部，而是按下面顺序小步推进：

1. 先抽出最小 slave 契约，并选两个最简单的设备做样板，例如 `gpio_slave`、`test_exit_slave`
2. 再把 `uart` 和 `perf/debug` 迁过去，验证慢设备和只读设备都能适配
3. 最后再把 `BRAM data path` 和未来的 `sdram_slave` 放进同一个单主多从结构

重构后的形态可以接近下面这样：

```text
CPU mem_*
-> interconnect / address select
-> bram_slave
-> gpio_slave
-> uart_slave
-> perf_slave
-> test_exit_slave
-> future sdram_slave
```

这个 issue 的重点不是“多做功能”，而是让后续新增外设时的改动收敛到：

- 新增一个 `*_slave.v`
- 在地址表中分配地址
- 在 interconnect 中增加一个命中项

而不是每次都去修改一串模块专用签名。

## 建议查阅 / 关键词

- 文件：`rtl/soc/tecplus_minisoc_top.v`、`rtl/soc/tinybus_decode.v`、`rtl/soc/tinybus_defs.vh`、`firmware/drivers/mmio.h`、`docs/darkriscv_wrapper_summary.md`、`docs/项目任务说明.md`
- 关键词：`single master multi slave`、`interconnect`、`blocking handshake`、`mem_valid / mem_ready`、`slave wrapper`、`MMIO decode`

## 测试与验收

具体测试样例可以自定，但必须覆盖“结构整理没有破坏原契约”这个核心风险。模块级需要至少给两个样板 slave 各自提供独立 testbench；子系统级需要覆盖地址命中唯一性，也就是同一请求最多只有一个 slave 响应；SoC 级需要证明原有 `MiniSoC` firmware smoke 不回归，并且新增一个最小外设接入样例时，不需要再修改一串模块专用端口。回归级至少应复跑 `bash scripts/test_local.sh` 以及相关 `minisoc_smoke_pico/dark`。如果这项工作与 `M2b` 一起推进，还要额外证明 `sdram_slave` 可以在这个统一接口下接入，而不会再把 top 变回一堆特判。

## 与主线里程碑的关系

- 如果你想压低主线风险：把这件事当成 `M2b` 的内部整理原则，不单独立 issue
- 如果你想先把结构理顺再接 SDRAM：把这件事作为 `M2b` 之前的独立 SoC 重构 issue
- 如果时间紧：至少先把新增设备都按 slave 风格写，旧 top 可以暂时保留部分 glue，不必一步到位

我个人建议是：**不要把它升级成真正多主 fabric 重构**。你现在要的主要是“开发方便、减少签名侵入”，单主多从已经足够解决大部分痛点。
