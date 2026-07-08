# 测试编排收敛到 JSON catalog + Python runner 的设计

## 背景

当前仓库的测试编排存在明显重复：

- `scripts/test_local.sh` 手写维护一长串顺序测试步骤。
- `scripts/check_rtl_syntax.sh` 手写维护一长串 syntax case。
- `Makefile` 里又维护了一份 `probe/platform/soc/smoke` 目标列表。
- `sim/run_sim.sh` 本身还维护了一份仿真 target 分发表。

这会带来两个直接问题：

1. 新增一个测试时，经常需要同时修改多个入口，容易漏挂。
2. 维护者需要记住“这个测试应该加到哪几层”，测试清单本身比测试逻辑更难维护。

本设计只解决“测试编排层重复”和“入口分散”这两个问题，不重写底层仿真执行逻辑。

## 目标

- 让测试清单有一个单一真相源。
- 让 `make` 目标名保持原样，但内部不再手写列表。
- 允许同一个脚本用不同参数复用，不要求所有测试都退化成自由 shell 命令。
- 保留现有 shell 使用习惯，避免文档和组员流程立刻断裂。
- 避免引入第三方依赖，兼容较保守的 `python3` 环境。

## 非目标

- 不把 `sim/run_sim.sh` 的 `case/esac` 分发表改成 Python。
- 不把 probe、firmware、testbench 本体一起重构。
- 不引入 `pytest`、`yaml` 或第三方 Python 包。
- 不做并行执行。
- 不做复杂断言 DSL。
- 不在第一阶段引入 case 之间的依赖图。

## 总体方案

新增两个文件：

- `scripts/test_catalog.json`
- `scripts/test_runner.py`

保留并复用现有底层执行器：

- `sim/run_sim.sh` 继续负责“执行一个仿真 target”。
- `scripts/build_firmware.sh` 继续负责 firmware 构建。
- `scripts/check_env.sh` 继续负责工具链存在性检查。

同时保留旧入口作为兼容壳：

- `scripts/test_local.sh`
- `scripts/check_rtl_syntax.sh`

`Makefile` 的目标名保持不变，但实现改成转调 `test_runner.py` 的 suite。

## Catalog 数据模型

`test_catalog.json` 顶层拆成三块：

- `prerequisites`
- `cases`
- `suites`

### prerequisites

`prerequisites` 描述可复用的前置能力步骤，而不是测试 case：

- `check_env`
- `firmware`
- `rtl_syntax`

每一项对应一个 argv 数组，由 runner 直接执行。

这样 `requires` 就只需要引用前置能力名，不会形成 case 依赖网。

### cases

每个 case 只描述一件事。第一阶段支持三类：

1. `sim`
   - 用于 `sim/run_sim.sh <target>`
   - 关键字段：`sim_target`

2. `script`
   - 用于“同一个脚本，不同参数”的复用场景
   - 关键字段：`script`、`args`

3. `command`
   - 兜底逃生口
   - 直接给 argv 数组

建议字段：

- `id`
- `kind`
- `description`
- `sim_target`
- `script`
- `args`
- `command`
- `env`
- `requires`
- `expect_fail`
- `timeout_sec`

其中：

- `env` 只做少量环境变量覆盖。
- `requires` 只引用 `prerequisites` 名字。
- `expect_fail` 第一阶段只按退出码判断。
- `timeout_sec` 用来避免个别 case 卡死。

### suites

`suites` 只做 case 组装，不重复写命令。

第一阶段至少覆盖这些 suite：

- `rtl_syntax_internal`
- `probe`
- `platform`
- `soc`
- `smoke`
- `dual_core`
- `local`
- `all`

其中：

- `rtl_syntax_internal` 供 `rtl_syntax` prerequisite 和兼容壳入口复用。
- `all` 作为仓库级汇总入口。

## 运行模型

### runner CLI

`test_runner.py` 第一阶段提供这些命令：

- `python3 scripts/test_runner.py list`
- `python3 scripts/test_runner.py run-case <case-id>`
- `python3 scripts/test_runner.py run-suite <suite-id>`

不做更复杂的子命令树，保持易读。

### requires 语义

`requires` 不是“依赖另一个 case”，而是“依赖某个前置能力”。

runner 在执行一个 suite 时：

1. 收集所有 case 的 `requires`
2. 去重
3. 按固定顺序执行前置步骤
4. 再按 suite 顺序执行 case

固定顺序建议为：

1. `check_env`
2. `firmware`
3. `rtl_syntax`

不允许 `case A -> case B` 这种依赖，否则编排层会重新长成隐式 DAG。

### 日志策略

runner 默认把每个 case 的日志写到：

- `sim/build/test_runner/<case-id>.log`

同时终端仍实时打印当前 case 输出，不改成静默批处理。

失败时 runner 只补一个短摘要：

- 失败 case
- 退出码
- 日志路径

这保持当前 shell 脚本“边跑边看”的体验，也方便回查。

### expect_fail

第一阶段只支持按退出码判断：

- `expect_fail=false`：预期返回 0
- `expect_fail=true`：预期返回非 0

第一阶段不把文本匹配断言塞进 catalog，避免 catalog 重新退化成脚本。
如果后续确实有稳定需求，再考虑增加很小的 `expect_stdout_contains`。

## RTL syntax 的边界处理

`scripts/check_rtl_syntax.sh` 现在维护的是“一组具体 iverilog 编译配方”，它和普通 `sim target` 不同，不适合直接把所有 Verilog 文件列表塞进 JSON。

因此第一阶段建议新增一个更细的执行器：

- `scripts/rtl_syntax_case.sh <case-id>`

它负责：

- 根据 `case-id` 执行那一条具体 syntax compile

这样职责边界会更清楚：

- `test_runner.py` 只负责编排
- `rtl_syntax_case.sh` 负责单个 syntax case 的真实命令
- `sim/run_sim.sh` 负责单个仿真 target 的真实命令

这也避免把 `test_catalog.json` 变成充满长文件列表的大型命令表。

## Makefile 映射

`Makefile` 继续保留现有目标名，但不再自己维护测试列表。

建议映射如下：

- `make rtl-syntax` -> `run-suite rtl_syntax_internal`
- `make test-probe` -> `run-suite probe`
- `make test-platform` -> `run-suite platform`
- `make test-soc` -> `run-suite soc`
- `make test-smoke` -> `run-suite smoke`
- `make test-dual-core` -> `run-suite dual_core`
- `make test-all` -> `run-suite all`
- `make ci` -> `make test-all`

这样 `Makefile` 退回成一层稳定别名，不再承担维护测试清单的职责。

## 兼容入口策略

第一阶段保留旧入口，但内部只转调 runner：

- `scripts/test_local.sh` -> `run-suite local`
- `scripts/check_rtl_syntax.sh` -> `run-suite rtl_syntax_internal`

这样做的原因：

- 旧文档、issue、组员习惯不会立刻失效
- 新入口可以逐步推广
- 后续是否删除兼容壳，可以等文档迁移稳定后再决定

## 第一阶段迁移范围

第一阶段只收敛编排层，不动底层执行配方：

- 新增 `scripts/test_catalog.json`
- 新增 `scripts/test_runner.py`
- 新增 `scripts/rtl_syntax_case.sh`
- 薄改 `Makefile`
- 薄改 `scripts/test_local.sh`
- 薄改 `scripts/check_rtl_syntax.sh`

不改：

- `sim/run_sim.sh` 内部 `case/esac`
- `scripts/compare_cpu_perf.sh` 内部逻辑
- probe/firmware/testbench 本体

## 示例

一个典型 catalog 片段可以是：

```json
{
  "prerequisites": {
    "check_env": ["bash", "scripts/check_env.sh"],
    "firmware": ["bash", "scripts/build_firmware.sh"],
    "rtl_syntax": ["python3", "scripts/test_runner.py", "run-suite", "rtl_syntax_internal"]
  },
  "cases": [
    {
      "id": "probe_vga",
      "kind": "sim",
      "sim_target": "probe_vga",
      "description": "运行 VGA thin probe 仿真"
    },
    {
      "id": "tb_mode_check",
      "kind": "script",
      "script": "scripts/test_minisoc_tb_modes.sh",
      "args": [],
      "description": "检查 MiniSoC regression bench 和 smoke bench 的语义区分"
    },
    {
      "id": "perf_targets_require_addrs",
      "kind": "script",
      "script": "scripts/test_perf_targets_require_addrs.sh",
      "args": [],
      "requires": ["firmware"],
      "expect_fail": false,
      "description": "检查 perf target 缺参时会 fail fast"
    }
  ],
  "suites": {
    "probe": ["probe_vga"],
    "smoke": ["probe_vga", "tb_mode_check"],
    "local": ["probe_vga", "tb_mode_check", "perf_targets_require_addrs"]
  }
}
```

## 权衡

### 为什么不用 YAML

- 会引入额外解析依赖，或者需要额外工具链假设。
- 当前需求只是结构化清单，不需要 YAML 的复杂表达力。

### 为什么不用 pytest

- 仓库当前主要问题是硬件 smoke orchestration，而不是 Python 业务单测。
- 引入 `pytest` 后，本质上仍会是 `subprocess.run(...)` 包 shell/iverilog 流程，收益不大。
- 还会额外引入 fixture、marker、依赖安装和边界混乱的问题。

### 为什么保留 sim/run_sim.sh

- 它当前扮演的是“单个 target 的编译配方库”。
- 第一阶段同时重构“配方定义”和“测试编排”风险过高。
- 先把编排层收敛，再决定后续是否继续统一底层 target 定义。

## 风险与缓解

### 风险 1：runner 自己长成新框架

缓解：

- 限制第一阶段只支持 `sim/script/command`
- 不做模板系统
- 不做 case DAG
- 不做并行

### 风险 2：syntax case 迁移后可读性变差

缓解：

- 用 `rtl_syntax_case.sh` 保留配方层
- 不把长文件列表直接塞进 JSON

### 风险 3：旧入口断裂

缓解：

- 先保留兼容壳脚本
- `make` 目标名保持不变

## 验收标准

完成第一阶段后，应满足：

1. 新增一个普通仿真回归时，只需要：
   - 在 `sim/run_sim.sh` 增加 target
   - 在 `test_catalog.json` 增加 case，并挂到相应 suite
2. `Makefile` 不再手写维护 `probe/platform/soc/smoke` 测试列表
3. `scripts/test_local.sh` 和 `scripts/check_rtl_syntax.sh` 仍能跑通
4. `python3 scripts/test_runner.py list` 能清楚列出 suite 和 case
5. `python3 scripts/test_runner.py run-case <case-id>` 能单独跑一个 case
6. `python3 scripts/test_runner.py run-suite <suite-id>` 能跑一组 case 并产生日志

## 后续演进

第一阶段完成后，如果事实证明 catalog + runner 方案稳定，再考虑第二阶段：

- 是否把更多 repo 级脚本改成 `script` case
- 是否增加极小的文本断言能力
- 是否继续收敛 `sim/run_sim.sh` 的 target 定义

但这些都不属于本次范围。
