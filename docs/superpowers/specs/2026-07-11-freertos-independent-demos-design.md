# FreeRTOS 独立教学 demos 设计

## 目标与阶段边界

在 BRAM smoke 和 SDRAM 综合 acceptance 已完成自动与上板 Gate 后，增加一组可单独
构建、仿真和上板的 FreeRTOS 教学 payload。每个 payload 只突出一个核心概念；最后的
traffic/audio demo 再展示多个模块协作。

本阶段实现：

```text
freertos-demo-heap
freertos-demo-notify
freertos-demo-mutex
freertos-demo-event-group
freertos-demo-timer
freertos-demo-traffic-audio
```

现有 `freertos-queue` 继续作为 queue 独立 demo，不复制第二个 queue-only payload。本阶段
不实现长时间 stress、stream buffer 或 Bad Apple media pipeline。全部 demo 自动 Gate
通过并完成 traffic/audio 上板验证后，才进入 stress。

## 通用约束

- 每个 demo 是独立 firmware 源文件、构建目标和 test catalog case，不增加运行时菜单；
- 复用官方 FreeRTOS API、现有 TecPlusRV port、UART、LED、traffic-light 和 buzzer driver；
- 不建立 demo framework；少量重复代码比跨 demo 抽象更容易教学和定位；
- 成功统一输出稳定的 `<demo name> pass`、LED=`5`、`test_exit=1`；
- 失败使用每个 demo 独立的 `0xfbNNxxxx` 错误码；
- 所有阻塞等待使用有限 timeout，另有 firmware 或 testbench timeout；
- 每个 50 MHz payload 报告 BRAM sections 和 `.bin`，遵守 48 KiB soft budget、64 KiB hard limit；
- 仿真沿用 SoC `1 MHz`、FreeRTOS 逻辑 `4 MHz` 的既有策略，避免 kernel 路径跨 tick 造成低优先级 task 饥饿；
- 自动验证不能替代 traffic-light 实际颜色映射、蜂鸣器响度/音高和 ISE timing，这些保留人工 Gate。

## `freertos-demo-heap`

使用 `freertos_heap_init()` 将 linker 的 64 KiB SDRAM region 交给官方 `heap_5`，再由
一个静态 task 演示：

1. 查询初始 free heap；
2. 分配多种大小、检查 16-byte alignment；
3. 写入并读回跨 block 的 word pattern；
4. 释放相邻 block 后申请更大 block，覆盖 coalescing；
5. 分配到耗尽，确认 malloc-failed hook；
6. 全部释放后确认 free heap 恢复；
7. 输出 free/minimum-ever-free heap。

核心 task 保持 static，只有演示对象来自 SDRAM heap。这样 allocator 自身出错时仍有
BRAM task 能报告错误。

## `freertos-demo-notify`

两个静态 task 演示 task notification 的三种常见语义：

- `eSetBits`：worker 等待 command bits；
- `xTaskNotifyGive` / `ulTaskNotifyTake`：累计完成次数；
- `eSetValueWithOverwrite`：返回一个 32-bit 结果值。

controller 发送固定命令，worker 计算并返回，controller 校验 bit、计数和结果。该 demo
不创建 queue，用来说明 notification 是直接绑定 task 的轻量通信方式。

## `freertos-demo-mutex`

使用三个静态 task 构造低、中、高优先级场景：

- low 取得 mutex 并修改共享 counter；
- high 尝试取得同一 mutex 后阻塞；
- medium 保持 ready，模拟会造成 priority inversion 的工作；
- controller/观测逻辑确认 low 临时继承 high priority，释放 mutex 后恢复原 priority；
- high 最终取得 mutex，并验证共享 counter 的完整结果。

不提供故意产生 data race 的“错误版本”；教学证据来自明确的执行顺序、priority 查询和
最终 counter。

## `freertos-demo-event-group`

三个 worker 分别模拟：

```text
VIDEO_READY
AUDIO_READY
STORAGE_READY
```

controller 使用 `xEventGroupWaitBits(..., wait-for-all)` 等待所有子系统完成初始化，检查
返回 bits 后清除，再执行一次 timeout/partial-bits 检查。这个模型直接对应后续 media
pipeline 启动前的多子系统 barrier。

## `freertos-demo-timer`

使用 static software timer：

- one-shot timer 触发一次状态切换；
- periodic timer 精确触发 5 次后停止；
- callback 只更新计数并用 non-blocking notification 唤醒 controller；
- controller 验证停止后计数不再增长。

不在 timer callback 中打印 UART、等待 queue 或访问慢外设，明确 timer service task 的
使用边界。

## `freertos-demo-traffic-audio`

这是本阶段唯一综合 demo：

```text
traffic controller task
  -> 写 12-bit traffic pattern
  -> 把 tone command 写入 static queue
  -> 等待 audio task notification

audio task
  -> 阻塞等待 queue
  -> 独占 buzzer driver
  -> 播放短音并停止
  -> 通知 controller
```

traffic pattern 使用以下可集中校准的 raw 12-bit 常量：

```text
RED    = 0x249  // 假设每组三位中的 bit 0 是红灯
YELLOW = 0x492  // 假设 bit 1 是黄灯
GREEN  = 0x924  // 假设 bit 2 是绿灯
```

当前仓库只确认 TL0..TL11 raw 输出，尚未确认教学大板每一位对应的实际颜色。因此源码
必须保留这组三个常量和“不确定、上板校准”的中文注释，不把假设埋进 driver。

同一 binary 先执行一个快速 GREEN/YELLOW/RED 验收周期，三个状态分别使用
`880/1320/660 Hz` 音调，写
`freertos traffic audio pass`、LED=`5`、`test_exit=1`；仿真在此结束。真实板上的
`test_exit` 不会停止 CPU，controller 随后改用肉眼可见的较长 duration 无限循环，因此
既能自动结束仿真，也能作为持续演示程序。

自动 testbench 必须观察到 traffic MMIO write、最终 pattern、buzzer register write 和
SPK toggle，不能只相信 firmware 的 UART 文本。

## 构建、测试与上板入口

稳定入口：

```bash
make freertos-demo-heap
make freertos-demo-notify
make freertos-demo-mutex
make freertos-demo-event-group
make freertos-demo-timer
make freertos-demo-traffic-audio
make test-freertos-demos
```

所有 cases 组成 `freertos_demos` suite，并加入现有 `freertos` / `all` 聚合。单 case 使用
已有 MiniSoC benches：heap 走 `tb_minisoc_sdram`；纯 kernel demos 走
`tb_freertos_smoke`；traffic/audio 走具备外设 side-effect checks 的 `tb_minisoc`。

上板只要求综合 demo 的稳定入口：

```bash
make ise-export ISE_TARGET=minisoc_freertos_traffic_audio_dark
make freertos-demo-traffic-audio-load PORT=COM8
```

## 验证 Gate

### Gate D1：独立 build/sim

- 六个 payload 均在 48 KiB BRAM soft budget 内；
- 每个独立 case PASS；
- `make test-freertos-demos` 全绿；
- 现有 `make test-freertos` 不回退。

### Gate D2：全量自动回归

- platform、soc、SDRAM subword、RV32I/RV32MI 和 dual-core 不回退；
- `make test-all` 全绿；
- ISE export 包包含本轮需要的官方 kernel modules、FreeRTOS profile 和 traffic/audio firmware。

### Gate D3：人工上板

- ISE Map/PAR 成功，50 MHz timing slack 为正；
- UART 输出 `freertos traffic audio pass`，LED=`5`；
- traffic-light 持续轮转；若颜色顺序不符，只校准三个 raw pattern 常量并重新跑自动 Gate；
- buzzer 对每个状态发出可区分的短音，持续运行至少两个完整周期；
- 重复 reset 后仍能进入演示。

Gate D3 未回传前，不进入 stress。
