# 板上 LED + UART Demo 设计说明

## 目标

新增一个独立的裸机用户程序，用于在 TEC-PLUS MiniSoC 上做最小板级确认：

- `LED[3:0]` 依次显示 `1 -> 2 -> 4 -> 8`
- 每一步通过 UART 打印一行状态文本
- 保持与当前 `TinyBus` MMIO、`tecplus_minisoc_top`、`firmware` 驱动接口兼容
- 生成可直接导入 ISE 的 `.mem` 文件

## 约束

- 不引入 bootloader
- 不改当前默认 `firmware/main.c` 的 smoke 行为
- 上板与仿真尽量复用同一份 `board_demo` 程序
- 板上运行需要持续可见，因此程序在写出一次 `test_exit=1` 之后继续循环执行

## 方案选择

采用最小方案：

1. 新增 `firmware/tests/board_demo.c`
2. 新增一个专用 `MiniSoC` testbench，验证：
   - 发生多次 LED 写
   - 发生多次 UART 写
   - `test_exit=1`
   - 写出 `test_exit` 前最后一次 LED 状态为 `4'h8`
3. 用现有 `scripts/build_firmware.sh` 配合 `FIRMWARE_MAIN` 生成镜像，再额外产出 `board_demo.mem`

不做的事：

- 不给 `build_firmware.sh` 增加通用多产物框架
- 不解析 UART 串口位级波形文本内容
- 不修改 ISE 工程自动化

## 验证

- 先让 `board_demo` 专用仿真入口失败
- 再实现 `board_demo.c`
- 通过 `board_demo` 仿真
- 最后生成 `firmware/build/board_demo.mem`
