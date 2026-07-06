# TecPlusRV Thin Probes 设计说明

## 目标

在不越过当前课程阶段边界的前提下，为 `Probe 4` 和 `Probe 5` 增加更薄的早期验证版本：

- `Probe 4a`：`SDRAM smoke probe`
- `Probe 5a`：`bigboard traffic-light thin probe`

目标不是补齐完整功能，而是更早暴露：

- UCF/管脚假设错误
- 板级链路不通
- 最小外设现象不存在
- SDRAM 最小命令链路明显失效

## 设计决策

### Probe 4a

- 不做通用 `SDRAM controller`
- 只做脚本式状态机
- 固定流程：`PRECHARGE ALL -> AUTO REFRESH x2 -> LOAD MODE -> WRITE -> READ -> COMPARE`
- 用板载 `LED` 报 `INIT/WRITE/READ/PASS/FAIL`
- 本地只验证命令序列和读回比较控制流

### Probe 5a

- 不做显示系统
- 不接 SoC / bus / firmware
- 只对大板交通灯输出打一组 one-hot 轮转图样
- 用板载 `LED` 做辅助心跳
- 本地只验证图样轮转

## 边界

- `Probe 4a` 不代表 SDRAM 已可供 SoC 使用
- `Probe 5a` 不代表显示/大板外设系统已完成
- full `Probe 4 / 5` 仍然保留为后续阶段工作
