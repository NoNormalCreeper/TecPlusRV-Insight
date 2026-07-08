# VGA Probe 与字符显示骨架设计

## 目标

本轮只实现两类最小 VGA 资产：

1. `VGA thin probe`
   只证明 `R/G/B/HS/VS` 以及可能相关的辅助控制脚能否在板上形成稳定现象。
2. `字符型 VGA 外设骨架`
   先实现一个独立的 text-mode 渲染器和最小写口，不先接入 `TinyBus` / `MiniSoC`。

## 边界

- 不做 framebuffer。
- 不做 SoC 级 MMIO 集成。
- 不做复杂图形系统。
- 不承诺 `Mf / Clr / Qd` 的真实板级语义已经完全搞清；先保留参数化默认值，并在注释中说明需上板确认。

## 方案

### 1. 共享时序模块

新增一个 `640x480@60` 风格的最小时序发生器，默认按 `50MHz -> 25MHz` 分频工作，并允许 testbench 通过参数缩小时序。

### 2. VGA thin probe

新增 `probe_vga_top`，输出：

- 彩条
- 心跳 LED
- 参数化默认值的 `Mf / Clr / Qd`

这个 probe 的职责只是在实验室里回答“显示链路是不是活的”。

### 3. 字符型 VGA 外设骨架

新增 `vga_text_mode`：

- 内部维护一个小型字符 RAM
- 提供一个单拍写口，便于未来包一层 MMIO
- 当前只支持有限字符集，优先覆盖 `A-Z`、`0-9`、空格和少量符号
- reset 后自动装入一行默认 banner，方便脱离 SoC 直接上板观察

另外新增 `probe_vga_text_top` 作为直接上板入口。

## 验证

- `tb_probe_vga_top.v`：验证同步脉冲和活动显示区内存在多种颜色
- `tb_vga_text_mode.v`：验证字符 RAM 初始 banner 与写口确实影响像素输出
- `scripts/check_rtl_syntax.sh`
- `sim/run_sim.sh probe_vga`
- `sim/run_sim.sh vga_text_mode`

## 风险与待确认点

- `Mf / Clr / Qd` 的极性和必要性依赖真实实验环境，需要上板后再收敛。
- `25MHz` 像素时钟由 `50MHz` 简单二分得到，是否被目标显示器稳定接受，需要上板确认。
- 当前字体只做最小子集，后续如果要显示更完整的调试文本，需要扩字模或改为外部字体 ROM。
