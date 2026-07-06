# 探针测试说明

本文档描述第一批 bring-up 探针。它们的角色是尽早暴露平台风险，不是项目亮点本身。

## 探针 0：LED / KEY / RESET / CLK

### 目标

确认 TEC-PLUS 的时钟、复位、LED、按键链路可用，并初步验证 UCF 引脚映射是否合理。

### RTL 与约束

- 顶层：`rtl/probe/probe_led_key_top.v`
- 约束：`constraints/tecplus_led_key.ucf`

### 输入输出

- 输入：`clk`、`reset`、`key[3:0]`
- 输出：`led[3:0]`

### 预期现象

- 复位有效时，LED 全灭
- 复位释放后，LED 跑马灯
- 按下 `KEY1` 可切换跑马灯速度
- 按下 `KEY2` 可切换到固定显示模式

### 实验室操作步骤

1. 在 ISE 中创建 Spartan-6 XC6SLX9-2FTG256 工程。
2. 加入 `probe_led_key_top.v` 和 `tecplus_led_key.ucf`。
3. 完成综合、布局布线并生成 bitstream。
4. 通过 JTAG 下载到板卡。
5. 观察 LED 空闲状态、reset 响应和按键响应。

### 失败排查方向

- UCF 管脚绑定错误
- 复位极性和实际板卡不一致
- key 极性或消抖假设不成立
- 50MHz 板载时钟未正常进入
- 实验室使用的约束文件和当前仓库版本不一致

## 探针 1：UART TX

### 目标

确认 CP2102 串口输出、UART TX 管脚映射和终端波特率设置正常。

### RTL 与约束

- 顶层：`rtl/probe/probe_uart_top.v`
- 约束：`constraints/tecplus_uart.ucf`
- 外设：`rtl/periph/uart_tx.v`

### 输入输出

- 输入：`clk`、`reset`
- 输出：`uart_txd`
- 预留输入：`uart_rxd`

### 预期现象

- 复位释放后，周期性发送 `Hello TecPlusRV\r\n`
- 当前版本不要求 RX 或 echo

### 实验室操作步骤

1. 在 ISE 中使用 `probe_uart_top.v` 和 `tecplus_uart.ucf` 建工程。
2. 下载到板卡。
3. 在主机上打开 CP2102 对应串口。
4. 设置 `9600 8N1`。
5. 观察周期性串口输出。

### 失败排查方向

- TXD / RXD 接反
- 波特率假设不对
- 串口终端 COM 口或帧格式设置错误
- 复位一直处于有效状态
- 板卡连线或 UCF 和当前版本不一致

## 探针 2：PicoRV32 Minimal 综合探针

### 目标

在投入更多 SoC 工作前，先判断一个很小的 PicoRV32 配置能否在 XC6SLX9 上放下。

### 输入输出

- CPU 核 + 小 BRAM + `test_exit`
- 后续按需要逐步加 UART / GPIO / 计数器

### 预期现象

- 输出一组综合/资源数据，而不是板上演示

### 实验室操作步骤

1. 将 `rtl/core/picorv32.v` vendored 进仓库。
2. 从 CPU + `test_exit` 的最小组合开始。
3. 逐步加 BRAM、UART TX、GPIO、计数器。
4. 每一步记录 LUT / FF / BRAM 占用和 timing slack。

### 失败排查方向

- vendored CPU 文件与 ISE 不兼容
- 默认 PicoRV32 参数导致资源暴涨
- 内存初始化方式在综合时不成立

## 探针 3：本地 MiniSoC 仿真

### 目标

给后续 CPU 集成提供一个不依赖板卡的本地保护线。

### 输入输出

- firmware 镜像
- 可选的 vendored PicoRV32 文件
- `test_exit` 监视点

### 预期现象

- PicoRV32 不存在时输出 `SKIP`
- firmware 写 `test_exit = 1` 时输出 `PASS`
- 写其他退出码时输出 `FAIL`
- 长时间没有到达 `test_exit` 时输出 `TIMEOUT`

### 本地 / 实验室操作步骤

1. 本地先构建 firmware。
2. 运行 `sim/run_sim.sh minisoc`。
3. 如果 PicoRV32 还没放入仓库，确认 skip 路径明确可见。
4. 后续 PicoRV32 接入后，继续使用同一条命令作为上板前检查。

### 失败排查方向

- 缺少 vendored CPU 文件
- firmware 镜像不匹配
- `test_exit` 相关 MMIO 译码错误
- CPU 复位或启动地址假设错误
