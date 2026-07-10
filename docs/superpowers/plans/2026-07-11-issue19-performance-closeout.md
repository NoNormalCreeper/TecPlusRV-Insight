# Issue #19 Performance Closeout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将已经验证的 #19 双核性能样本、课程总结和后续优化/上板计划归档，并安全合并回 `master`。

**Architecture:** `results/issue19-2026-07-10/` 保存不可变的原始实验数据，`reports/` 只解释结果并链接数据；未来工作单独放在 `docs/FUTURE_PERFORMANCE_PLAN.md`，不把尚未实现的 burst、Cache 或上板数据写成当前能力。合并在新的干净 linked worktree 完成，原始 `master` 的脏工作区不切换、不修改。

**Tech Stack:** Markdown、CSV、Bash 测试入口、Git worktree、Icarus Verilog、ISE 14.7 后续板级流程。

## Global Constraints

- 面向开发者的文本使用中文，保留常见英文术语。
- 当前结果来自 1 MHz testbench 仿真；不得写成板上实测频率或 SDRAM benchmark 板级证据。
- 保留原始 UART/build 日志、`results.csv` 和环境快照，报告中的数值可追溯。
- 不修改 `/home/rikka/NexysRV-Insight` 原始 `master` 工作区已有的脏文件。

---

### Task 1: 归档结果与编写课程报告

**Files:**
- Create: `results/issue19-2026-07-10/README.md`
- Create: `results/issue19-2026-07-10/{environment.txt,results.csv,summary.md,*_build.log,*_picorv32.log,*_darkriscv.log}`
- Create: `reports/issue19-performance-summary.md`
- Modify: `docs/BENCHMARKS.md`

**Interfaces:**
- Consumes: `/tmp/issue19-final-bench/` 的完成样本。
- Produces: 可由报告相对链接引用的固定证据集。

- [ ] **Step 1: 复制结果文件并检查数量**

Run: `find results/issue19-2026-07-10 -maxdepth 1 -type f | wc -l`

Expected: 包含环境、CSV、汇总、4 个构建日志和 8 个 CPU 原始日志，共 15 个数据文件及 README。

- [ ] **Step 2: 编写报告**

报告必须说明双核 CPI 结论、BRAM/SDRAM 瓶颈、`mem_wait` 的跨核解释边界、仿真/上板证据边界和 PPA 换算公式。

- [ ] **Step 3: 验证引用**

Run: `test -f results/issue19-2026-07-10/results.csv && test -f reports/issue19-performance-summary.md`

Expected: exit 0。

- [ ] **Step 4: Commit**

```bash
git add results reports docs/BENCHMARKS.md
git commit -m "docs: 归档 Issue 19 性能实验结果"
```

### Task 2: 写明未来优化和上板计划

**Files:**
- Create: `docs/FUTURE_PERFORMANCE_PLAN.md`

**Interfaces:**
- Consumes: 当前控制器的 single-request、closed-page、无 burst/Cache 约束。
- Produces: 先软件优化、后 RTL 优化、最后上板 PPA 对比的可执行计划。

- [ ] **Step 1: 写出职责和优先级**

计划须区分寄存器滑动窗口、软件分块/line buffer、硬件 line buffer、burst、Cache 的职责、收益、风险和验证入口。

- [ ] **Step 2: 写出双核上板矩阵**

矩阵须规定同一 firmware、`CPU_IMPL=0/1` 的两个 bitstream、UART 原始日志、三次重复、ISE Map/PAR/Timing 报告和 `Fmax / CPI` 吞吐量换算。

- [ ] **Step 3: Commit**

```bash
git add docs/FUTURE_PERFORMANCE_PLAN.md
git commit -m "docs: 规划后续性能优化与上板验证"
```

### Task 3: 在干净 worktree 合并与验证

**Files:**
- Modify through merge: `master`

**Interfaces:**
- Consumes: `feature/issue-19-performance-finalization` 的独立提交。
- Produces: 包含 #19 功能、数据、报告和计划的本地 `master`。

- [ ] **Step 1: 创建/复用干净 master worktree**

Run: `git worktree add /tmp/NexysRV-Insight-master-merge master`

Expected: 原始工作区不受影响。

- [ ] **Step 2: 合并 feature 分支**

Run: `git merge --no-ff feature/issue-19-performance-finalization -m "merge: 收口 Issue 19 性能实验"`

Expected: 无冲突的 merge commit。

- [ ] **Step 3: 运行最终验证**

Run: `make rtl-syntax && python3 scripts/test_runner.py run-suite performance`

Expected: RTL syntax 33/33，性能 suite 生成新的结果目录并返回 0。

- [ ] **Step 4: 确认 master 状态**

Run: `git status --short && git log --oneline -6`

Expected: status 为空，日志包含 merge commit。
