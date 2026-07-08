# 测试编排 JSON Catalog + Python Runner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把仓库当前分散在 shell 与 Makefile 里的测试编排清单收敛到 `scripts/test_catalog.json` 与 `scripts/test_runner.py`，同时保持现有 `make` 目标名和旧 shell 入口可继续使用。

**Architecture:** 保留 `sim/run_sim.sh`、`scripts/build_firmware.sh`、`scripts/check_env.sh` 作为底层执行器，只把“哪些 case 属于哪个 suite、哪些 case 需要哪些前置步骤”收敛到 JSON catalog。Python runner 负责解析 catalog、执行 prerequisites、运行 case、汇总日志；RTL syntax 配方通过单独的 `scripts/rtl_syntax_case.sh` 承接，避免把长文件列表塞进 JSON。

**Tech Stack:** Python 3 标准库、JSON、Bash、Makefile、Icarus Verilog 现有脚本

---

## 文件结构

- Create: `scripts/test_catalog.json`
- Create: `scripts/test_runner.py`
- Create: `scripts/rtl_syntax_case.sh`
- Create: `scripts/test_test_runner.py`
- Modify: `Makefile`
- Modify: `scripts/test_local.sh`
- Modify: `scripts/check_rtl_syntax.sh`
- Modify: `README.md`
- Modify: `docs/DEV_FLOW.md`

## 任务

### Task 1: 先为 runner 写 failing 自测

**Files:**
- Create: `scripts/test_test_runner.py`
- Read: `docs/superpowers/specs/2026-07-08-test-runner-catalog-design.md`

- [ ] **Step 1: 写 catalog 解析与 CLI 行为的 failing tests**

测试覆盖面至少包括：

- `list` 会列出 suite 与 case
- `run-case` 会执行单个 `script` case
- `run-suite` 会先去重执行 prerequisites，再按顺序执行 case
- `expect_fail=true` 的 case 在非零退出时应被视为 PASS
- `sim` case 会转调 `sim/run_sim.sh <target>`

建议测试形态：

```python
class TestRunnerCli(unittest.TestCase):
    def test_list_prints_known_suite_and_case(self):
        result = self.run_runner("list", "--catalog", self.catalog_path)
        self.assertEqual(result.returncode, 0)
        self.assertIn("suite smoke", result.stdout)
        self.assertIn("case probe_vga", result.stdout)

    def test_run_suite_deduplicates_prerequisites(self):
        result = self.run_runner("run-suite", "smoke", "--catalog", self.catalog_path)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(self.read_trace().count("prereq:firmware"), 1)

    def test_expect_fail_case_is_treated_as_pass(self):
        result = self.run_runner("run-case", "intentional_fail", "--catalog", self.catalog_path)
        self.assertEqual(result.returncode, 0)
        self.assertIn("PASS", result.stdout)
```

- [ ] **Step 2: 运行单测，确认它们先失败**

Run: `python3 -m unittest scripts.test_test_runner -v`

Expected:

- 测试失败
- 失败原因是 `scripts/test_runner.py` 尚不存在，或 CLI/行为未实现

- [ ] **Step 3: 补一个最小 mock catalog fixture**

在 `scripts/test_test_runner.py` 里用 `tempfile.TemporaryDirectory()` 写出临时 catalog 与临时脚本，避免依赖真实 `iverilog` 或真实 firmware 构建。fixture 里至少准备：

- 一个会把执行痕迹写到 trace 文件的 mock script
- 一个返回非零的 intentional-fail script
- 一个 `sim` case，验证 runner 会调用到 mock `sim/run_sim.sh`

- [ ] **Step 4: 再跑一次，确认失败变成“行为不匹配失败”而不是 fixture 错误**

Run: `python3 -m unittest scripts.test_test_runner -v`

Expected:

- 仍然 FAIL
- 失败点来自 runner 行为尚未实现，而不是测试脚本自身报错

### Task 2: 实现最小可用的 runner

**Files:**
- Create: `scripts/test_runner.py`
- Test: `scripts/test_test_runner.py`

- [ ] **Step 1: 实现 catalog 读取与基本校验**

至少实现：

- 读取 JSON
- 校验顶层存在 `prerequisites`、`cases`、`suites`
- 建立 `case id -> case dict` 索引
- 检查重复 case id、缺失 suite 引用

- [ ] **Step 2: 先实现 `list`，让最简单的测试转绿**

CLI 先支持：

- `python3 scripts/test_runner.py list`
- `python3 scripts/test_runner.py list --catalog <path>`

输出保持人类可读，例如：

```text
suite smoke
  case probe_vga
  case minisoc_smoke_pico
```

- [ ] **Step 3: 运行单测，确认 `list` 相关测试通过，其余仍失败**

Run: `python3 -m unittest scripts.test_test_runner.TestRunnerCli.test_list_prints_known_suite_and_case -v`

Expected: PASS

Run: `python3 -m unittest scripts.test_test_runner -v`

Expected: 其余测试仍 FAIL

- [ ] **Step 4: 实现 `run-case` 与 `run-suite` 的最小执行路径**

至少实现：

- `script` case：`[script] + args`
- `command` case：直接执行 argv
- `sim` case：固定执行 `sim/run_sim.sh <sim_target>`
- `env` 注入
- `timeout_sec`
- `requires` 收集与去重执行

- [ ] **Step 5: 实现日志目录与 PASS/FAIL 汇总**

行为约束：

- 日志路径为 `sim/build/test_runner/<case-id>.log`
- 子进程输出实时打印到终端
- 同时落盘到对应 log
- 失败时打印 case id、退出码、日志路径

- [ ] **Step 6: 实现 `expect_fail` 退出码反转逻辑**

判定规则：

- 正常 case：退出码 0 才 PASS
- `expect_fail=true`：退出码非 0 才 PASS

- [ ] **Step 7: 跑完整单测，确认 runner 自测转绿**

Run: `python3 -m unittest scripts.test_test_runner -v`

Expected: 全部 PASS

### Task 3: 把 RTL syntax 配方拆成单 case 执行器

**Files:**
- Create: `scripts/rtl_syntax_case.sh`
- Modify: `scripts/check_rtl_syntax.sh`

- [ ] **Step 1: 抽出单 case syntax 配方**

在 `scripts/rtl_syntax_case.sh` 中以 `case_id` 分发至少这些现有 syntax 目标：

- `probe_led_key_top`
- `probe_uart_top`
- `sdram_smoke_ctrl`
- `sdram_data_ctrl`
- `sdram_tester_ctrl`
- `probe_buzzer_uart_top`
- `probe_vga_top`
- `vga_text_mode`
- `probe_vga_text_top`
- `tinybus_decode`
- `bram`
- `bram_dualport`
- `mmio_test_exit`
- `picorv32_adapter`
- `darkriscv_adapter`
- `tecplus_cpu_wrapper`
- `tecplus_minisoc_top`

- [ ] **Step 2: 保持 `scripts/check_rtl_syntax.sh` 变成兼容壳**

新的壳行为：

Run: `python3 scripts/test_runner.py run-suite rtl_syntax_internal`

壳脚本仍保留旧 shebang 与中文说明，避免旧入口失效。

- [ ] **Step 3: 为 `rtl_syntax_case.sh` 至少补一个 runner 级 case**

在 catalog 中为每个 syntax 配方建立 `script` case：

```json
{
  "id": "rtl_probe_vga_top",
  "kind": "script",
  "script": "scripts/rtl_syntax_case.sh",
  "args": ["probe_vga_top"],
  "description": "语法检查：probe_vga_top"
}
```

- [ ] **Step 4: 运行 syntax suite，确认兼容壳仍可工作**

Run: `bash scripts/check_rtl_syntax.sh`

Expected: 与重构前一样完成全部 syntax smoke checks

### Task 4: 建立真实 catalog 并接回 Makefile/旧入口

**Files:**
- Create: `scripts/test_catalog.json`
- Modify: `Makefile`
- Modify: `scripts/test_local.sh`

- [ ] **Step 1: 在 catalog 中声明 prerequisites**

至少包括：

```json
"prerequisites": {
  "check_env": ["bash", "scripts/check_env.sh"],
  "firmware": ["bash", "scripts/build_firmware.sh"],
  "rtl_syntax": ["python3", "scripts/test_runner.py", "run-suite", "rtl_syntax_internal"]
}
```

- [ ] **Step 2: 先录入现有 probe/platform/soc/smoke/local case**

第一阶段至少覆盖这些现有入口内容：

- `probe_led_key`
- `probe_uart_top`
- `bram`
- `bram_dualport`
- `tinybus_decode`
- `mmio_test_exit`
- `uart_tx`
- `sdram_smoke`
- `sdram_data_ctrl`
- `sdram_tester`
- `sdram_tester_fail`
- `sdram_tester_reset`
- `sdram_tester_uart_reporter`
- `bigboard_tl`
- `probe_buzzer_uart`
- `probe_vga`
- `vga_text_mode`
- `minisoc_smoke_pico`
- `minisoc_smoke_dark`
- `minisoc_counter_source_pico`
- `minisoc_counter_source_dark`
- `minisoc_counter_reset_pico`
- `minisoc_counter_reset_dark`
- `tb_mode_check`
- `uart_once_regression`
- `perf_targets_require_addrs`
- `dual_core_regression`

- [ ] **Step 3: 给 suite 建立稳定映射**

至少建立：

- `rtl_syntax_internal`
- `probe`
- `platform`
- `soc`
- `smoke`
- `dual_core`
- `local`
- `all`

- [ ] **Step 4: 把 `scripts/test_local.sh` 改成兼容壳**

新的壳行为：

Run: `python3 scripts/test_runner.py run-suite local`

- [ ] **Step 5: 把 `Makefile` 改成 suite 别名层**

需要改动的目标：

- `rtl-syntax`
- `test-probe`
- `test-platform`
- `test-soc`
- `test-smoke`
- `test-dual-core`
- `test-all`
- `ci`

要求：

- 目标名保持不变
- 列表不再散落在 `Makefile`
- `help` 输出补充 `python3 scripts/test_runner.py list`

- [ ] **Step 6: 跑最小真实链路验证**

Run:

- `python3 scripts/test_runner.py list`
- `python3 scripts/test_runner.py run-case probe_vga`
- `python3 scripts/test_runner.py run-suite smoke`

Expected:

- `list` 能列出 suite/case
- `run-case` 单独跑通
- `run-suite smoke` 会自动处理前置项并顺序执行 smoke case

### Task 5: 更新文档并做最终验证

**Files:**
- Modify: `README.md`
- Modify: `docs/DEV_FLOW.md`

- [ ] **Step 1: 更新 README 的测试入口说明**

要点：

- 新推荐入口是 `python3 scripts/test_runner.py`
- `make` 目标名保持不变
- `scripts/test_local.sh`、`scripts/check_rtl_syntax.sh` 仍可用，但属于兼容壳

- [ ] **Step 2: 更新 DEV_FLOW 的本地验证流程**

要点：

- catalog 是测试编排单一真相源
- 新增/挂载测试优先改 `scripts/test_catalog.json`
- `run_sim.sh` 与 `rtl_syntax_case.sh` 仍是底层配方层

- [ ] **Step 3: 跑 runner 单测**

Run: `python3 -m unittest scripts.test_test_runner -v`

Expected: PASS

- [ ] **Step 4: 跑最关键的真实入口回归**

Run:

- `bash scripts/check_rtl_syntax.sh`
- `python3 scripts/test_runner.py run-case probe_vga`
- `python3 scripts/test_runner.py run-suite smoke`
- `bash scripts/test_local.sh`

Expected:

- syntax suite 通过
- 单 case 入口通过
- smoke suite 通过
- 兼容壳 `test_local.sh` 通过

- [ ] **Step 5: 检查工作区改动范围**

Run: `git diff -- scripts/ Makefile README.md docs/DEV_FLOW.md docs/superpowers/plans/2026-07-08-test-runner-catalog.md`

Expected:

- 改动集中在 runner/catalog/入口壳/文档
- 没有误碰 RTL、testbench 或 firmware 本体
