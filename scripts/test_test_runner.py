import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


class TestRunnerCli(unittest.TestCase):
    def setUp(self):
        self._tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmpdir.cleanup)
        self.root = Path(self._tmpdir.name)
        self.trace_path = self.root / "trace.log"
        self.catalog_path = self.root / "test_catalog.json"
        self.runner_path = Path(__file__).resolve().parent / "test_runner.py"

        self._write_script(
            "scripts/record.sh",
            """#!/bin/sh
set -eu
printf '%s\\n' "$1" >> "$TRACE_FILE"
""",
        )
        self._write_script(
            "scripts/fail.sh",
            """#!/bin/sh
set -eu
printf '%s\\n' "$1" >> "$TRACE_FILE"
exit 7
""",
        )
        self._write_script(
            "sim/run_sim.sh",
            """#!/bin/sh
set -eu
printf 'sim:%s\\n' "$1" >> "$TRACE_FILE"
""",
        )

        catalog = {
            "prerequisites": {
                "check_env": ["scripts/record.sh", "prereq:check_env"],
                "firmware": ["scripts/record.sh", "prereq:firmware"],
            },
            "cases": [
                {
                    "id": "standalone_script",
                    "kind": "script",
                    "script": "scripts/record.sh",
                    "args": ["script:standalone_script"],
                    "description": "单个 script case",
                },
                {
                    "id": "dedup_script",
                    "kind": "script",
                    "script": "scripts/record.sh",
                    "args": ["script:dedup_script"],
                    "requires": ["firmware", "check_env"],
                    "description": "用于检查 prerequisites 去重",
                },
                {
                    "id": "probe_vga",
                    "kind": "sim",
                    "sim_target": "probe_vga",
                    "description": "用于检查 sim 转调",
                },
                {
                    "id": "intentional_fail",
                    "kind": "script",
                    "script": "scripts/fail.sh",
                    "args": ["script:intentional_fail"],
                    "expect_fail": True,
                    "description": "用于检查 expect_fail 语义",
                },
            ],
            "suites": {
                "smoke": ["dedup_script", "probe_vga", "intentional_fail"],
                "local": ["standalone_script"],
            },
        }
        self.catalog_path.write_text(json.dumps(catalog, indent=2, ensure_ascii=False), encoding="utf-8")

    def _write_script(self, relative_path, content):
        path = self.root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        path.chmod(0o755)
        return path

    def run_runner(self, *args):
        env = os.environ.copy()
        env["TRACE_FILE"] = str(self.trace_path)
        return subprocess.run(
            [sys.executable, str(self.runner_path), *args],
            cwd=self.root,
            env=env,
            text=True,
            capture_output=True,
        )

    def write_catalog(self, catalog):
        self.catalog_path.write_text(json.dumps(catalog, indent=2, ensure_ascii=False), encoding="utf-8")

    def read_catalog(self):
        return json.loads(self.catalog_path.read_text(encoding="utf-8"))

    def read_trace(self):
        if not self.trace_path.exists():
            return []
        return self.trace_path.read_text(encoding="utf-8").splitlines()

    def test_list_prints_known_suite_and_case(self):
        result = self.run_runner("list", "--catalog", str(self.catalog_path))
        self.assertEqual(result.returncode, 0)
        self.assertIn("suite smoke", result.stdout)
        self.assertIn("case probe_vga", result.stdout)

    def test_run_case_executes_single_script_case(self):
        result = self.run_runner("run-case", "standalone_script", "--catalog", str(self.catalog_path))
        self.assertEqual(result.returncode, 0)
        self.assertEqual(self.read_trace(), ["script:standalone_script"])
        self.assertIn("\x1b[32mPASS 1/1\x1b[0m", result.stdout)

    def test_run_case_executes_non_executable_script_via_shebang(self):
        script_path = self.root / "scripts/record.sh"
        script_path.chmod(0o644)

        result = self.run_runner("run-case", "standalone_script", "--catalog", str(self.catalog_path))
        self.assertEqual(result.returncode, 0)
        self.assertEqual(self.read_trace(), ["script:standalone_script"])

    def test_run_suite_deduplicates_prerequisites(self):
        result = self.run_runner("run-suite", "smoke", "--catalog", str(self.catalog_path))
        self.assertEqual(result.returncode, 0)
        trace = self.read_trace()
        self.assertEqual(trace.count("prereq:check_env"), 1)
        self.assertEqual(trace.count("prereq:firmware"), 1)
        self.assertLess(trace.index("prereq:check_env"), trace.index("script:dedup_script"))
        self.assertLess(trace.index("prereq:check_env"), trace.index("sim:probe_vga"))
        self.assertLess(trace.index("prereq:check_env"), trace.index("script:intentional_fail"))
        self.assertLess(trace.index("prereq:firmware"), trace.index("script:dedup_script"))
        self.assertLess(trace.index("prereq:firmware"), trace.index("sim:probe_vga"))
        self.assertLess(trace.index("prereq:firmware"), trace.index("script:intentional_fail"))

    def test_run_suite_uses_catalog_prerequisite_declaration_order(self):
        catalog = self.read_catalog()
        catalog["prerequisites"] = {
            "firmware": ["scripts/record.sh", "prereq:firmware"],
            "check_env": ["scripts/record.sh", "prereq:check_env"],
            "rtl_syntax": ["scripts/record.sh", "prereq:rtl_syntax"],
        }
        catalog["cases"] = [
            {
                "id": "first_case",
                "kind": "script",
                "script": "scripts/record.sh",
                "args": ["case:first_case"],
                "requires": ["rtl_syntax", "check_env"],
            },
            {
                "id": "second_case",
                "kind": "script",
                "script": "scripts/record.sh",
                "args": ["case:second_case"],
                "requires": ["firmware", "rtl_syntax"],
            },
        ]
        catalog["suites"] = {"ordered": ["first_case", "second_case"]}
        self.write_catalog(catalog)

        result = self.run_runner("run-suite", "ordered", "--catalog", str(self.catalog_path))
        self.assertEqual(result.returncode, 0)
        self.assertEqual(
            self.read_trace(),
            [
                "prereq:firmware",
                "prereq:check_env",
                "prereq:rtl_syntax",
                "case:first_case",
                "case:second_case",
            ],
        )

    def test_expect_fail_case_is_treated_as_pass(self):
        result = self.run_runner("run-case", "intentional_fail", "--catalog", str(self.catalog_path))
        self.assertEqual(result.returncode, 0)
        self.assertEqual(self.read_trace(), ["script:intentional_fail"])

    def test_sim_case_calls_run_sim_with_target(self):
        result = self.run_runner("run-case", "probe_vga", "--catalog", str(self.catalog_path))
        self.assertEqual(result.returncode, 0)
        self.assertEqual(self.read_trace(), ["sim:probe_vga"])

    def test_run_case_executes_command_kind(self):
        catalog = self.read_catalog()
        catalog["cases"].append(
            {
                "id": "command_case",
                "kind": "command",
                "command": ["scripts/record.sh", "command:command_case"],
                "description": "用于检查 command kind",
            }
        )
        self.write_catalog(catalog)

        result = self.run_runner("run-case", "command_case", "--catalog", str(self.catalog_path))
        self.assertEqual(result.returncode, 0)
        self.assertEqual(self.read_trace(), ["command:command_case"])

    def test_run_case_injects_env(self):
        self._write_script(
            "scripts/read_env.sh",
            """#!/bin/sh
set -eu
printf '%s\\n' "$TEST_VALUE" >> "$TRACE_FILE"
""",
        )
        catalog = self.read_catalog()
        catalog["cases"].append(
            {
                "id": "env_case",
                "kind": "script",
                "script": "scripts/read_env.sh",
                "env": {"TEST_VALUE": "env:ok"},
                "description": "用于检查 env 注入",
            }
        )
        self.write_catalog(catalog)

        result = self.run_runner("run-case", "env_case", "--catalog", str(self.catalog_path))
        self.assertEqual(result.returncode, 0)
        self.assertEqual(self.read_trace(), ["env:ok"])

    def test_run_case_from_external_cwd_resolves_commands_and_logs_under_catalog_repo(self):
        external_cwd = self.root / "outside"
        external_cwd.mkdir()
        log_dir = self.root / "sim/build/test_runner"

        env = os.environ.copy()
        env["TRACE_FILE"] = str(self.trace_path)
        result = subprocess.run(
            [
                sys.executable,
                str(self.runner_path),
                "run-case",
                "standalone_script",
                "--catalog",
                str(self.catalog_path),
            ],
            cwd=external_cwd,
            env=env,
            text=True,
            capture_output=True,
        )

        self.assertEqual(result.returncode, 0)
        self.assertEqual(self.read_trace(), ["script:standalone_script"])
        self.assertTrue((log_dir / "standalone_script.log").exists())
        self.assertFalse((external_cwd / "sim/build/test_runner/standalone_script.log").exists())

    def test_invalid_catalog_missing_top_level_field_exits_2(self):
        catalog = self.read_catalog()
        del catalog["suites"]
        self.write_catalog(catalog)

        result = self.run_runner("list", "--catalog", str(self.catalog_path))
        self.assertEqual(result.returncode, 2)
        self.assertIn("ERROR:", result.stderr)
        self.assertIn("catalog 缺少顶层字段: suites", result.stderr)

    def test_unknown_case_exits_2(self):
        result = self.run_runner("run-case", "missing_case", "--catalog", str(self.catalog_path))
        self.assertEqual(result.returncode, 2)
        self.assertIn("未知 case: missing_case", result.stderr)

    def test_unknown_suite_exits_2(self):
        result = self.run_runner("run-suite", "missing_suite", "--catalog", str(self.catalog_path))
        self.assertEqual(result.returncode, 2)
        self.assertIn("未知 suite: missing_suite", result.stderr)

    def test_normal_fail_case_prints_summary_and_returns_1(self):
        self._write_script(
            "scripts/fail_with_output.sh",
            """#!/bin/sh
set -eu
echo "fatal:normal_fail"
exit 7
""",
        )
        catalog = self.read_catalog()
        catalog["cases"].append(
            {
                "id": "normal_fail",
                "kind": "script",
                "script": "scripts/fail_with_output.sh",
                "description": "用于检查普通失败路径",
            }
        )
        self.write_catalog(catalog)

        result = self.run_runner("run-case", "normal_fail", "--catalog", str(self.catalog_path))
        self.assertEqual(result.returncode, 1)
        self.assertIn("\x1b[31mFAIL 0/1 case=normal_fail exit_code=7", result.stderr)
        self.assertIn("sim/build/test_runner/normal_fail.log", result.stderr)
        self.assertIn("----- normal_fail 日志尾部 -----", result.stderr)
        self.assertIn("fatal:normal_fail", result.stderr)
        self.assertEqual(self.read_trace(), [])

    def test_run_suite_failure_prints_progress_summary(self):
        self._write_script(
            "scripts/fail_with_output.sh",
            """#!/bin/sh
set -eu
echo "fatal:fail_after_one"
exit 7
""",
        )
        catalog = self.read_catalog()
        catalog["cases"].append(
            {
                "id": "fail_after_one",
                "kind": "script",
                "script": "scripts/fail_with_output.sh",
                "description": "用于检查 suite 失败进度摘要",
            }
        )
        catalog["suites"] = {
            "fail_suite": ["standalone_script", "fail_after_one"],
        }
        self.write_catalog(catalog)

        result = self.run_runner("run-suite", "fail_suite", "--catalog", str(self.catalog_path))
        self.assertEqual(result.returncode, 1)
        self.assertIn("\x1b[31mFAIL 1/2 case=fail_after_one exit_code=7", result.stderr)
        self.assertIn("fatal:fail_after_one", result.stderr)
        self.assertEqual(self.read_trace(), ["script:standalone_script"])

    def test_run_suite_keep_going_continues_after_failure_and_returns_1(self):
        self._write_script(
            "scripts/fail_with_output.sh",
            """#!/bin/sh
set -eu
echo "fatal:fail_but_continue"
exit 7
""",
        )
        catalog = self.read_catalog()
        catalog["cases"].append(
            {
                "id": "pass_after_failure",
                "kind": "script",
                "script": "scripts/record.sh",
                "args": ["script:pass_after_failure"],
                "description": "用于检查 keep-going 下失败后的继续执行",
            }
        )
        catalog["cases"].append(
            {
                "id": "fail_but_continue",
                "kind": "script",
                "script": "scripts/fail_with_output.sh",
                "description": "用于检查 keep-going 下的失败聚合",
            }
        )
        catalog["suites"] = {
            "keep_going_suite": ["standalone_script", "fail_but_continue", "pass_after_failure"],
        }
        self.write_catalog(catalog)

        result = self.run_runner(
            "run-suite",
            "keep_going_suite",
            "--keep-going",
            "--catalog",
            str(self.catalog_path),
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("\x1b[31mFAIL 1/3 case=fail_but_continue exit_code=7", result.stderr)
        self.assertIn("\x1b[31mFAIL 2/3 failed_cases=1\x1b[0m", result.stderr)
        self.assertIn("fatal:fail_but_continue", result.stderr)
        self.assertEqual(
            self.read_trace(),
            ["script:standalone_script", "script:pass_after_failure"],
        )

    def test_invalid_expect_fail_type_is_rejected_at_load_time(self):
        catalog = self.read_catalog()
        catalog["cases"][3]["expect_fail"] = "yes"
        self.write_catalog(catalog)

        result = self.run_runner("list", "--catalog", str(self.catalog_path))
        self.assertEqual(result.returncode, 2)
        self.assertIn("expect_fail 必须是布尔值", result.stderr)

    def test_invalid_kind_is_rejected_at_load_time(self):
        catalog = self.read_catalog()
        catalog["cases"][0]["kind"] = "unknown"
        self.write_catalog(catalog)

        result = self.run_runner("list", "--catalog", str(self.catalog_path))
        self.assertEqual(result.returncode, 2)
        self.assertIn("kind 不支持", result.stderr)

    def test_invalid_env_type_is_rejected_at_load_time(self):
        catalog = self.read_catalog()
        catalog["cases"][0]["env"] = ["BAD=1"]
        self.write_catalog(catalog)

        result = self.run_runner("list", "--catalog", str(self.catalog_path))
        self.assertEqual(result.returncode, 2)
        self.assertIn("env 必须是对象", result.stderr)

    def test_invalid_timeout_type_is_rejected_at_load_time(self):
        catalog = self.read_catalog()
        catalog["cases"][0]["timeout_sec"] = "slow"
        self.write_catalog(catalog)

        result = self.run_runner("list", "--catalog", str(self.catalog_path))
        self.assertEqual(result.returncode, 2)
        self.assertIn("timeout_sec 必须是正数", result.stderr)

    def test_suite_can_reference_other_suite(self):
        catalog = self.read_catalog()
        catalog["suites"] = {
            "base": ["dedup_script", "probe_vga"],
            "smoke": ["@base", "intentional_fail"],
        }
        self.write_catalog(catalog)

        result = self.run_runner("run-suite", "smoke", "--catalog", str(self.catalog_path))
        self.assertEqual(result.returncode, 0)
        self.assertEqual(
            self.read_trace(),
            [
                "prereq:check_env",
                "prereq:firmware",
                "script:dedup_script",
                "sim:probe_vga",
                "script:intentional_fail",
            ],
        )

    def test_list_expands_referenced_suite_cases(self):
        catalog = self.read_catalog()
        catalog["suites"] = {
            "base": ["probe_vga"],
            "smoke": ["@base", "standalone_script"],
        }
        self.write_catalog(catalog)

        result = self.run_runner("list", "--catalog", str(self.catalog_path))
        self.assertEqual(result.returncode, 0)
        self.assertIn("suite smoke", result.stdout)
        self.assertIn("  case probe_vga", result.stdout)
        self.assertIn("  case standalone_script", result.stdout)

    def test_invalid_suite_reference_is_rejected_at_load_time(self):
        catalog = self.read_catalog()
        catalog["suites"]["smoke"] = ["@missing_suite"]
        self.write_catalog(catalog)

        result = self.run_runner("list", "--catalog", str(self.catalog_path))
        self.assertEqual(result.returncode, 2)
        self.assertIn("suite smoke 引用了不存在的 suite: missing_suite", result.stderr)

    def test_cyclic_suite_reference_is_rejected_at_load_time(self):
        catalog = self.read_catalog()
        catalog["suites"] = {
            "smoke": ["@local"],
            "local": ["@smoke"],
        }
        self.write_catalog(catalog)

        result = self.run_runner("list", "--catalog", str(self.catalog_path))
        self.assertEqual(result.returncode, 2)
        self.assertIn("suite 引用出现循环", result.stderr)


class CiSuiteContractTest(unittest.TestCase):
    def test_ci_is_fast_subset_of_all(self):
        catalog_path = Path(__file__).with_name("test_catalog.json")
        loaded = __import__("scripts.test_runner", fromlist=["Catalog"]).Catalog.load(
            catalog_path
        )
        ci_cases = set(loaded.suite_case_ids["ci"])
        all_cases = set(loaded.suite_case_ids["all"])
        long_cases = {
            "bad_apple_minimal_pico",
            "freertos_yield_smoke",
            "freertos_smoke",
            "bad_apple_full",
            "dual_core_regression",
        }

        self.assertLess(ci_cases, all_cases)
        self.assertTrue(long_cases <= all_cases)
        self.assertTrue(ci_cases.isdisjoint(long_cases))


if __name__ == "__main__":
    unittest.main()
