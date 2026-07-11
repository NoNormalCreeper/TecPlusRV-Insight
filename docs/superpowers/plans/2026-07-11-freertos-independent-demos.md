# FreeRTOS 独立教学 demos Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 增加 heap、notification、mutex、event group、software timer 和 traffic/audio 六个独立 FreeRTOS 教学 payload，并完成自动与上板 Gate。

**Architecture:** 每个 demo 使用独立 firmware 入口，共用现有 FreeRTOS profile 和 MiniSoC benches。纯 kernel demos 使用 BRAM static task/object；heap demo 显式访问 SDRAM `heap_5`；traffic/audio 用 static queue 连接唯一 traffic owner 与唯一 buzzer owner。

**Tech Stack:** FreeRTOS-Kernel V11.3.0、RV32I C、DarkRISCV、Icarus Verilog、MiniSoC MMIO、Xilinx ISE 14.7。

## Global Constraints

- 本计划已写完但暂缓执行；先完成用户要求的全时长真实媒体 Bad Apple。
- 直接在 `master` 工作，不创建 worktree，不使用 sub-agent。
- 不修改用户现有 `.gitignore`、`docs/diary.md` 和 SDRAM issue draft。
- 每个 payload 独立，无统一菜单或 demo framework。
- FreeRTOS 仿真使用逻辑 `4 MHz`，上板使用 `50 MHz`。
- BRAM 48 KiB soft budget、64 KiB hard limit。
- 自动 Gate 通过后才执行 traffic/audio 人工上板；人工 Gate 通过后才进入 stress。

---

### Task 1: heap 独立 demo

**Files:**
- Create: `firmware/tests/freertos_demo_heap.c`
- Modify: `sim/run_sim.sh`
- Modify: `scripts/test_catalog.json`

**Interfaces:**
- Consumes: `freertos_heap_init()`、`pvPortMalloc()`、`vPortFree()`、heap stats。
- Produces: `freertos_demo_heap` case；UART `freertos heap demo pass`。

- [ ] **Step 1: 先接 catalog case，确认未知 sim target 红灯**

```json
{
  "id": "freertos_demo_heap",
  "kind": "sim",
  "sim_target": "freertos_demo_heap",
  "timeout_sec": 180
}
```

Run: `python3 scripts/test_runner.py run-case freertos_demo_heap`

Expected: FAIL，runner 报未知目标。

- [ ] **Step 2: 编写 self-check firmware**

使用 static controller task；依次验证 16-byte alignment、多尺寸 pattern、相邻块合并、
耗尽 hook 和全部释放恢复。成功输出 free/minimum heap 后 `test_pass()`。

- [ ] **Step 3: 复用 SDRAM bench 接入 sim target**

`sim/run_sim.sh` 使用 `FIRMWARE_PROFILE=freertos`、逻辑 4 MHz 和
`tb_minisoc_sdram.v`；testbench 必须观察真实 SDRAM read/write。

- [ ] **Step 4: 跑红绿与提交**

```bash
python3 scripts/test_runner.py run-case freertos_demo_heap
git add firmware/tests/freertos_demo_heap.c sim/run_sim.sh scripts/test_catalog.json
git commit -m "feat: 增加 FreeRTOS heap 独立演示"
```

---

### Task 2: notification 独立 demo

**Files:**
- Create: `firmware/tests/freertos_demo_notify.c`
- Modify: `sim/run_sim.sh`
- Modify: `scripts/test_catalog.json`

**Interfaces:**
- Produces: bits、counting、overwrite-value 三种 notification 自检；UART `freertos notify demo pass`。

- [ ] **Step 1: catalog-first 红灯**

增加 `freertos_demo_notify` case，运行后确认未知 target FAIL。

- [ ] **Step 2: 实现两个 static task**

controller/worker 使用：

```c
xTaskNotify(worker, command_bits, eSetBits);
xTaskNotifyGive(controller);
xTaskNotify(controller, result, eSetValueWithOverwrite);
```

每个 wait 使用 100-tick timeout；结果值由固定 input 计算，不能只检查 notification API
返回成功。

- [ ] **Step 3: 接 `tb_freertos_smoke` 并提交**

Run: `python3 scripts/test_runner.py run-case freertos_demo_notify`

Expected: PASS、LED=5、test_exit=1。

Commit: `feat: 增加 FreeRTOS notification 独立演示`

---

### Task 3: mutex priority inheritance 独立 demo

**Files:**
- Create: `firmware/tests/freertos_demo_mutex.c`
- Modify: `sim/run_sim.sh`
- Modify: `scripts/test_catalog.json`

**Interfaces:**
- Produces: low/mid/high 固定握手、priority inheritance 和共享 counter 证据。

- [ ] **Step 1: 先增加失败 case**

`freertos_demo_mutex` 在 target 尚不存在时必须 FAIL。

- [ ] **Step 2: 实现确定性三 task 场景**

low 持锁后通过 flag 通知 controller；high 阻塞在 mutex；mid 保持 ready。controller 检查
`uxTaskPriorityGet(low)==high_priority` 后允许 low 释放。最终检查 low priority 恢复、high
取得锁、counter 精确等于预期值。

- [ ] **Step 3: 仿真与提交**

Run: `python3 scripts/test_runner.py run-case freertos_demo_mutex`

Commit: `feat: 增加 FreeRTOS mutex 独立演示`

---

### Task 4: event group 与 software timer 独立 demos

**Files:**
- Create: `firmware/tests/freertos_demo_event_group.c`
- Create: `firmware/tests/freertos_demo_timer.c`
- Modify: `sim/run_sim.sh`
- Modify: `scripts/test_catalog.json`

**Interfaces:**
- Produces: `freertos_demo_event_group`、`freertos_demo_timer` 两个独立 cases。

- [ ] **Step 1: 分别增加两个 catalog 红灯**

Run:

```bash
python3 scripts/test_runner.py run-case freertos_demo_event_group
python3 scripts/test_runner.py run-case freertos_demo_timer
```

Expected: 两者均因未知 target FAIL。

- [ ] **Step 2: 实现 event barrier**

三个 static worker 设置 `VIDEO_READY/AUDIO_READY/STORAGE_READY`；controller 使用
wait-for-all 检查全部 bits，再验证 partial bits + timeout 不会误通过。

- [ ] **Step 3: 实现 timer demo**

one-shot 精确一次；periodic 精确五次后 callback 以 `xTimerStop(timer, 0)` 停止；callback
只做计数和 non-blocking notify。controller 延迟后确认计数不再增长。

- [ ] **Step 4: 仿真与提交**

Run: 两个独立 cases，Expected: PASS。

Commit: `feat: 增加 FreeRTOS event 与 timer 独立演示`

---

### Task 5: traffic/audio 综合 demo

**Files:**
- Create: `firmware/tests/freertos_demo_traffic_audio.c`
- Modify: `sim/run_sim.sh`
- Modify: `scripts/test_catalog.json`

**Interfaces:**
- Consumes: static queue、traffic-light driver、buzzer driver、task notification。
- Produces: UART `freertos traffic audio pass`；持续 traffic/audio 板级演示。

- [ ] **Step 1: 增加外设 side-effect 红灯 case**

case 使用 `tb_minisoc.v` 并要求 traffic write、最终 `0x249`、buzzer write 和 SPK toggle。
目标缺失时先 FAIL。

- [ ] **Step 2: 实现双 owner task**

定义可校准 raw patterns：

```c
#define TRAFFIC_RED    0x249u
#define TRAFFIC_YELLOW 0x492u
#define TRAFFIC_GREEN  0x924u
```

controller 唯一写 traffic，audio task 唯一写 buzzer；二者只通过 static queue 与
notification 通信。

- [ ] **Step 3: 同 binary 分离自动验收与持续演示**

先用短 duration 播放 GREEN/YELLOW/RED，输出 PASS、LED=5、test_exit=1；随后不停止
task，在真实板继续使用 500/200/500 ms duration 无限循环。

- [ ] **Step 4: 仿真与提交**

Run: `python3 scripts/test_runner.py run-case freertos_demo_traffic_audio`

Expected: firmware PASS，testbench 同时确认 traffic 与 buzzer side effects。

Commit: `feat: 增加 FreeRTOS traffic audio 综合演示`

---

### Task 6: 构建、suite、ISE 与文档 Gate

**Files:**
- Modify: `Makefile`
- Modify: `scripts/test_catalog.json`
- Modify: `scripts/export_ise_project.sh`
- Modify: `docs/FREERTOS_PORT_DESIGN.md`

**Interfaces:**
- Produces: 六个 build targets、`test-freertos-demos`、traffic/audio load 和 ISE target。

- [ ] **Step 1: build contract 先要求稳定入口**

检查六个 `freertos-demo-*` targets、`test-freertos-demos`、
`minisoc_freertos_traffic_audio_dark`；当前应 FAIL。

- [ ] **Step 2: 增加隔离输出与 suite**

所有 build target 使用 50 MHz 和 `firmware/build/freertos/<demo>/firmware`；
`freertos_demos` suite 纳入 `freertos/all`。

- [ ] **Step 3: 增加 ISE/load 入口**

```bash
make ise-export ISE_TARGET=minisoc_freertos_traffic_audio_dark
make freertos-demo-traffic-audio-load PORT=COM8
```

- [ ] **Step 4: 跑自动 Gate**

```bash
make test-freertos-demos
make test-freertos
make test-all
```

Expected: 全绿，六个 payload 均低于 48 KiB soft budget。

- [ ] **Step 5: 更新文档并提交**

记录 cases、尺寸、命令和 raw color mapping 不确定性。

Commit: `build: 接入 FreeRTOS 独立 demos 验收入口`

- [ ] **Step 6: 人工 Gate**

用户回传 Map/PAR、50 MHz slack、UART、LED、traffic 实际颜色顺序、buzzer 音调和重复
reset 结果。若 raw mapping 需校准，只改三个常量并重新跑 Task 6 自动 Gate。
