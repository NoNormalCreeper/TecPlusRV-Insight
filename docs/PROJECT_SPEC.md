# TecPlusRV 项目说明

## 项目定位

TecPlusRV 对应北京邮电大学《项目式课程阶段 2》题目 B：基于 FPGA 开发板的处理器设计。目标平台是 TEC-PLUS 核心板，FPGA 为 Spartan-6 XC6SLX9-2FTG256，工具链为 ISE 14.7，RTL 优先使用 Verilog-2001。

本项目不是一次性的 LED 小实验，而是一个资源受限条件下的 RISC-V SoC 课程设计。与此同时，当前仓库的第一版只覆盖“工程框架 + 早期探针 + 本地验证入口”，不假装已经完成完整 SoC。

## 基础目标

- 跑通一个最小 RV32I 级别 CPU，优先建立 PicoRV32 baseline，并保留切换到 DarkRISCV 的能力
- 从片上 BRAM 启动
- 提供 TinyBus 风格 MMIO 译码
- 接入 LED、KEY、UART 和 `test_exit`
- 能构建并运行裸机 firmware 镜像
- 保留本地仿真入口作为早期验证路径

## 进阶目标

- 在选定 CPU 核外构建完整小型 SoC
- 增加 cycle / instret 计数器
- 在同一 SoC 外壳下做非流水线 / 流水线双核对比
- 先做薄版 `Probe 4a`，再做更完整的独立 SDRAM tester，并考虑接入 SoC
- 将 UART 作为主要可观测出口
- 在 Spartan-6 资源限制下比较资源与性能权衡

## 拓展目标

- 增加轻量级加速器，例如 popcount、Hamming distance、DOT4 INT8
- 增加更丰富的调试/可观测机制
- 尝试 Flash / EEPROM 相关启动或配置功能
- 如果时间允许，再增加显示类可观测外设

## 资源受限下的设计权衡

相较于 Nexys4 一类 Artix-7 平台，TEC-PLUS 的资源明显更紧，因此设计上应优先选择：

- 更小的 CPU 配置
- BRAM 优先的启动路径
- 探针优先、板级先行的验证流程
- 先做低风险 MMIO 集成，再做侵入式 CPU 改造
- 对 SDRAM 这类大模块保持诚实延期，不伪造完成状态
- 在完整模块之前，允许用 thin probe 提前做链路确认

重点不是一开始堆功能，而是在 XC6SLX9 上把 bring-up 和调试难度控制住。

## CPU 核 / 开源代码使用边界

PicoRV32、DarkRISCV 或其他开源 RTL 可以参考、审阅并 vendored 进仓库。这里的 `vendored` 指手工引入、自己审阅、随仓库一起管理的第三方源码。课程工作本身仍需要独立完成以下决策：

- 地址映射
- 外设接口
- 总线集成
- 板级约束
- 实验室 bring-up 流程
- 系统验证和调试策略

当前仓库已经把 PicoRV32 和 DarkRISCV 作为 vendored 源码放在 `rtl/core/` 下，但 SoC 集成、地址图、wrapper、约束和验证仍然是本项目自己的工程内容。

## 开发策略：本地优先，实验室验证收口

开发流程分为两条线：

### 本地优先

- 写模块级 testbench
- 本地构建 firmware
- 先打通 memory image 流程
- 在没有板子的情况下运行真实 MiniSoC 板级 top 仿真

### 实验室收口

- ISE 综合与时序检查
- JTAG 下载
- reset 极性确认
- LED / KEY / UART 板级现象验证
- `Probe 4a` 的 SDRAM smoke 现象验证
- `Probe 4` 的独立 SDRAM tester 现象验证
- `Probe 5a` 的 bigboard traffic-light 现象验证
- `tecplus_minisoc_top` 集成后的资源适配验证

第一版骨架的目标是减少实验室盲调时间，而不是替代实验室验证。
