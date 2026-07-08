#!/usr/bin/env python3
"""最小可用的测试编排器。"""

from __future__ import annotations

import argparse
import json
import os
import shlex
import subprocess
import sys
import threading
from pathlib import Path
from typing import Iterable


DEFAULT_CATALOG = Path(__file__).with_name("test_catalog.json")
ANSI_RESET = "\033[0m"
ANSI_GREEN = "\033[32m"
ANSI_RED = "\033[31m"


class CatalogError(RuntimeError):
    """catalog 结构或引用不合法。"""


class CaseFailure(RuntimeError):
    """单个 case 或 prerequisite 执行失败。"""

    def __init__(
        self,
        case_id: str,
        returncode: int,
        log_path: Path,
        *,
        passed: int | None = None,
        total: int | None = None,
    ):
        super().__init__(case_id)
        self.case_id = case_id
        self.returncode = returncode
        self.log_path = log_path
        self.passed = passed
        self.total = total


class SuiteFailure(RuntimeError):
    """keep-going 模式下，suite 收集到一个或多个失败。"""

    def __init__(self, suite_id: str, failures: list[CaseFailure], passed: int, total: int):
        super().__init__(suite_id)
        self.suite_id = suite_id
        self.failures = failures
        self.passed = passed
        self.total = total


class Catalog:
    """把 JSON catalog 解析成便于 runner 使用的结构。"""

    def __init__(self, raw: dict, source: Path):
        self.source = source
        self.prerequisites = raw["prerequisites"]
        self.cases = raw["cases"]
        self.suites = raw["suites"]
        self._validate_prerequisites()
        self.case_by_id = self._build_case_index()
        self._validate_cases()
        self.suite_case_ids = self._resolve_suites()
        self._validate_case_requires()
        self.execution_root = self._resolve_execution_root()

    @classmethod
    def load(cls, path: Path) -> "Catalog":
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
        except FileNotFoundError as exc:
            raise CatalogError(f"catalog 不存在: {path}") from exc
        except json.JSONDecodeError as exc:
            raise CatalogError(f"catalog JSON 非法: {path}: {exc}") from exc

        for key in ("prerequisites", "cases", "suites"):
            if key not in raw:
                raise CatalogError(f"catalog 缺少顶层字段: {key}")
        if not isinstance(raw["prerequisites"], dict):
            raise CatalogError("catalog.prerequisites 必须是对象")
        if not isinstance(raw["cases"], list):
            raise CatalogError("catalog.cases 必须是数组")
        if not isinstance(raw["suites"], dict):
            raise CatalogError("catalog.suites 必须是对象")
        return cls(raw, path)

    def _build_case_index(self) -> dict[str, dict]:
        case_by_id: dict[str, dict] = {}
        for case in self.cases:
            if not isinstance(case, dict):
                raise CatalogError("catalog.cases 的每一项都必须是对象")
            case_id = case.get("id")
            if not case_id or not isinstance(case_id, str):
                raise CatalogError("每个 case 都必须有字符串 id")
            if case_id in case_by_id:
                raise CatalogError(f"重复的 case id: {case_id}")
            case_by_id[case_id] = case
        return case_by_id

    def _validate_prerequisites(self) -> None:
        for prereq_name, prereq_value in self.prerequisites.items():
            if not isinstance(prereq_name, str) or not prereq_name:
                raise CatalogError("prerequisites 的 key 必须是非空字符串")
            ensure_argv(prereq_value, f"prerequisite {prereq_name}")

    def _validate_cases(self) -> None:
        for case in self.cases:
            validate_case_schema(case)

    def _resolve_suites(self) -> dict[str, list[str]]:
        resolved: dict[str, list[str]] = {}
        visiting: list[str] = []

        def resolve_suite(suite_id: str) -> list[str]:
            if suite_id in resolved:
                return resolved[suite_id]
            if suite_id in visiting:
                cycle = " -> ".join([*visiting, suite_id])
                raise CatalogError(f"suite 引用出现循环: {cycle}")

            entries = self.suites.get(suite_id)
            if entries is None:
                raise CatalogError(f"未知 suite: {suite_id}")
            if not isinstance(entries, list):
                raise CatalogError(f"suite {suite_id} 必须是 case id 数组")

            visiting.append(suite_id)
            case_ids: list[str] = []
            for entry in ensure_string_list(entries, f"suite {suite_id}"):
                if entry.startswith("@"):
                    child_suite_id = entry[1:]
                    if child_suite_id not in self.suites:
                        raise CatalogError(
                            f"suite {suite_id} 引用了不存在的 suite: {child_suite_id}"
                        )
                    case_ids.extend(resolve_suite(child_suite_id))
                    continue
                if entry not in self.case_by_id:
                    raise CatalogError(f"suite {suite_id} 引用了不存在的 case: {entry}")
                case_ids.append(entry)
            visiting.pop()
            resolved[suite_id] = case_ids
            return case_ids

        for suite_id in self.suites:
            resolve_suite(suite_id)
        return resolved

    def _validate_case_requires(self) -> None:
        for case in self.cases:
            requires = case.get("requires", [])
            if not isinstance(requires, list):
                raise CatalogError(f"case {case['id']} 的 requires 必须是数组")
            for prereq in requires:
                if prereq not in self.prerequisites:
                    raise CatalogError(f"case {case['id']} 引用了不存在的 prerequisite: {prereq}")

    def _resolve_execution_root(self) -> Path:
        base_dir = self.source.resolve().parent
        relative_paths = self._collect_relative_command_paths()
        if not relative_paths:
            return base_dir

        for candidate in [base_dir, *base_dir.parents]:
            if all((candidate / relative_path).exists() for relative_path in relative_paths):
                return candidate
        raise CatalogError(
            "无法根据 catalog 里的相对路径推导执行根目录"
        )

    def _collect_relative_command_paths(self) -> set[Path]:
        relative_paths: set[Path] = set()
        for prereq_value in self.prerequisites.values():
            relative_paths.update(extract_relative_paths(ensure_argv(prereq_value, "prerequisite")))
        for case in self.cases:
            relative_paths.update(extract_relative_paths(build_case_command(case)))
        return relative_paths


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="最小可用的测试 runner")
    subparsers = parser.add_subparsers(dest="command", required=True)

    list_parser = subparsers.add_parser("list", help="列出 suite 与 case")
    list_parser.add_argument("--catalog", default=str(DEFAULT_CATALOG))

    run_case_parser = subparsers.add_parser("run-case", help="运行单个 case")
    run_case_parser.add_argument("case_id")
    run_case_parser.add_argument("--catalog", default=str(DEFAULT_CATALOG))

    run_suite_parser = subparsers.add_parser("run-suite", help="运行一个 suite")
    run_suite_parser.add_argument("suite_id")
    run_suite_parser.add_argument("--keep-going", action="store_true", help="失败后继续执行后续 case")
    run_suite_parser.add_argument("--catalog", default=str(DEFAULT_CATALOG))

    return parser.parse_args(argv)


def iter_command_output(process: subprocess.Popen[str]) -> Iterable[str]:
    assert process.stdout is not None
    for line in process.stdout:
        yield line


def ensure_argv(argv: object, field_name: str) -> list[str]:
    if not isinstance(argv, list) or not argv:
        raise CatalogError(f"{field_name} 必须是非空字符串数组")
    if not all(isinstance(item, str) for item in argv):
        raise CatalogError(f"{field_name} 必须只包含字符串")
    return list(argv)


def ensure_string_list(argv: object, field_name: str) -> list[str]:
    if not isinstance(argv, list):
        raise CatalogError(f"{field_name} 必须是字符串数组")
    if not all(isinstance(item, str) for item in argv):
        raise CatalogError(f"{field_name} 必须只包含字符串")
    return list(argv)


def validate_env_map(env_value: object, field_name: str = "env") -> dict[str, str]:
    if env_value is None:
        return {}
    if not isinstance(env_value, dict):
        raise CatalogError(f"{field_name} 必须是对象")
    for key, value in env_value.items():
        if not isinstance(key, str) or not isinstance(value, str):
            raise CatalogError(f"{field_name} 只能包含字符串键值")
    return dict(env_value)


def validate_timeout(timeout_value: object, case_id: str) -> float | None:
    if timeout_value is None:
        return None
    if isinstance(timeout_value, bool) or not isinstance(timeout_value, (int, float)) or timeout_value <= 0:
        raise CatalogError(f"case {case_id} 的 timeout_sec 必须是正数")
    return float(timeout_value)


def validate_expect_fail(expect_fail: object, case_id: str) -> bool:
    if expect_fail is None:
        return False
    if type(expect_fail) is not bool:
        raise CatalogError(f"case {case_id} 的 expect_fail 必须是布尔值")
    return expect_fail


def validate_case_schema(case: dict) -> None:
    case_id = case["id"]
    kind = case.get("kind")
    if kind not in ("script", "command", "sim"):
        raise CatalogError(f"case {case_id} 的 kind 不支持: {kind}")
    if kind == "script":
        script = case.get("script")
        if not isinstance(script, str) or not script:
            raise CatalogError(f"case {case_id} 缺少合法 script")
        ensure_string_list(case.get("args", []), f"case {case_id} 的 args")
    elif kind == "command":
        command = case.get("command", case.get("argv"))
        ensure_argv(command, f"case {case_id} 的 command")
    elif kind == "sim":
        sim_target = case.get("sim_target")
        if not isinstance(sim_target, str) or not sim_target:
            raise CatalogError(f"case {case_id} 缺少合法 sim_target")

    validate_env_map(case.get("env"))
    validate_timeout(case.get("timeout_sec"), case_id)
    validate_expect_fail(case.get("expect_fail"), case_id)


def extract_relative_paths(argv: Iterable[str]) -> set[Path]:
    relative_paths: set[Path] = set()
    for item in argv:
        candidate = Path(item)
        if candidate.is_absolute() or len(candidate.parts) <= 1:
            continue
        relative_paths.add(candidate)
    return relative_paths


def build_case_command(case: dict) -> list[str]:
    kind = case.get("kind")
    if kind == "script":
        script = case["script"]
        args = case.get("args", [])
        return [script, *args]
    if kind == "command":
        command = case.get("command", case.get("argv"))
        return ensure_argv(command, f"case {case['id']} 的 command")
    if kind == "sim":
        return ["sim/run_sim.sh", case["sim_target"]]
    raise CatalogError(f"case {case['id']} 的 kind 不支持: {kind}")


def build_prereq_command(prereq_name: str, prereq_value: object) -> list[str]:
    return ensure_argv(prereq_value, f"prerequisite {prereq_name}")


def merge_env(extra_env: object) -> dict[str, str]:
    env = dict(os.environ)
    for key, value in validate_env_map(extra_env).items():
        env[key] = value
    return env


def resolve_command_for_popen(argv: list[str], execution_root: Path) -> list[str]:
    if not argv:
        return argv
    candidate = execution_root / argv[0]
    if not candidate.is_file():
        return argv
    if os.access(candidate, os.X_OK):
        return argv

    try:
        first_line = candidate.read_text(encoding="utf-8", errors="replace").splitlines()[0]
    except IndexError:
        return argv
    if not first_line.startswith("#!"):
        return argv

    interpreter = shlex.split(first_line[2:].strip())
    if not interpreter:
        return argv
    return [*interpreter, argv[0], *argv[1:]]


def run_logged_command(
    item_id: str,
    argv: list[str],
    *,
    execution_root: Path,
    extra_env: object = None,
    timeout_sec: object = None,
    expect_fail: bool = False,
) -> None:
    log_dir = execution_root / "sim/build/test_runner"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / f"{item_id}.log"
    timeout = validate_timeout(timeout_sec, item_id)
    popen_argv = resolve_command_for_popen(argv, execution_root)

    with log_path.open("w", encoding="utf-8") as log_file:
        try:
            process = subprocess.Popen(
                popen_argv,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                cwd=execution_root,
                env=merge_env(extra_env),
            )
        except FileNotFoundError as exc:
            raise CaseFailure(item_id, 127, log_path) from exc
        except PermissionError as exc:
            raise CaseFailure(item_id, 126, log_path) from exc

        def pump_output() -> None:
            for line in iter_command_output(process):
                sys.stdout.write(line)
                sys.stdout.flush()
                log_file.write(line)
                log_file.flush()

        output_thread = threading.Thread(target=pump_output, daemon=True)
        output_thread.start()

        try:
            returncode = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
            output_thread.join()
            sys.stdout.write(f"[timeout] {item_id} 超时\n")
            sys.stdout.flush()
            log_file.write(f"[timeout] {item_id} 超时\n")
            log_file.flush()
            raise CaseFailure(item_id, 124, log_path)
        output_thread.join()

    passed = returncode != 0 if expect_fail else returncode == 0
    if not passed:
        raise CaseFailure(item_id, returncode, log_path)


def ordered_prerequisites(catalog: Catalog, prereq_names: Iterable[str]) -> list[str]:
    requested = set(prereq_names)
    return [name for name in catalog.prerequisites if name in requested]


def colorize(text: str, color: str) -> str:
    return f"{color}{text}{ANSI_RESET}"


def print_pass_summary(passed: int, total: int) -> None:
    print(colorize(f"PASS {passed}/{total}", ANSI_GREEN))


def read_log_tail(log_path: Path, max_lines: int = 40) -> list[str]:
    try:
        lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
    except FileNotFoundError:
        return []
    return lines[-max_lines:]


def print_failure_summary(exc: CaseFailure) -> None:
    progress = ""
    if exc.passed is not None and exc.total is not None:
        progress = f"{exc.passed}/{exc.total} "
    print(
        colorize(
            f"FAIL {progress}case={exc.case_id} exit_code={exc.returncode} log={exc.log_path}",
            ANSI_RED,
        ),
        file=sys.stderr,
    )
    log_tail = read_log_tail(exc.log_path)
    if not log_tail:
        return
    print(f"----- {exc.case_id} 日志尾部 -----", file=sys.stderr)
    for line in log_tail:
        print(line, file=sys.stderr)


def print_suite_failure_summary(exc: SuiteFailure) -> None:
    print(
        colorize(
            f"FAIL {exc.passed}/{exc.total} failed_cases={len(exc.failures)}",
            ANSI_RED,
        ),
        file=sys.stderr,
    )
    for failure in exc.failures:
        print(
            f"  case={failure.case_id} exit_code={failure.returncode} log={failure.log_path}",
            file=sys.stderr,
        )


def print_list(catalog: Catalog) -> int:
    for suite_id in catalog.suites:
        print(f"suite {suite_id}")
        for case_id in catalog.suite_case_ids[suite_id]:
            print(f"  case {case_id}")
    return 0


def run_case(catalog: Catalog, case_id: str) -> int:
    case = catalog.case_by_id.get(case_id)
    if case is None:
        raise CatalogError(f"未知 case: {case_id}")

    try:
        for prereq_name in ordered_prerequisites(catalog, case.get("requires", [])):
            run_prerequisite(catalog, prereq_name)
        execute_case(catalog, case)
    except CaseFailure as exc:
        exc.passed = 0
        exc.total = 1
        raise
    print_pass_summary(1, 1)
    return 0


def run_prerequisite(catalog: Catalog, prereq_name: str) -> None:
    argv = build_prereq_command(prereq_name, catalog.prerequisites[prereq_name])
    run_logged_command(prereq_name, argv, execution_root=catalog.execution_root)


def execute_case(catalog: Catalog, case: dict) -> None:
    case_id = case["id"]
    argv = build_case_command(case)
    run_logged_command(
        case_id,
        argv,
        execution_root=catalog.execution_root,
        extra_env=case.get("env"),
        timeout_sec=case.get("timeout_sec"),
        expect_fail=validate_expect_fail(case.get("expect_fail"), case_id),
    )


def run_suite(catalog: Catalog, suite_id: str, *, keep_going: bool = False) -> int:
    case_ids = catalog.suite_case_ids.get(suite_id)
    if case_ids is None:
        raise CatalogError(f"未知 suite: {suite_id}")

    passed = 0
    failures: list[CaseFailure] = []
    try:
        prereq_names: list[str] = []
        for case_id in case_ids:
            prereq_names.extend(catalog.case_by_id[case_id].get("requires", []))
        for prereq_name in ordered_prerequisites(catalog, prereq_names):
            run_prerequisite(catalog, prereq_name)

        for case_id in case_ids:
            try:
                execute_case(catalog, catalog.case_by_id[case_id])
            except CaseFailure as exc:
                exc.passed = passed
                exc.total = len(case_ids)
                if not keep_going:
                    raise
                print_failure_summary(exc)
                failures.append(exc)
                continue
            passed += 1
    except CaseFailure as exc:
        exc.passed = passed
        exc.total = len(case_ids)
        raise
    if failures:
        raise SuiteFailure(suite_id, failures, passed, len(case_ids))
    print_pass_summary(passed, len(case_ids))
    return 0


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    catalog = Catalog.load(Path(args.catalog))

    if args.command == "list":
        return print_list(catalog)
    if args.command == "run-case":
        return run_case(catalog, args.case_id)
    if args.command == "run-suite":
        return run_suite(catalog, args.suite_id, keep_going=args.keep_going)
    raise CatalogError(f"未知命令: {args.command}")


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except CatalogError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(2)
    except CaseFailure as exc:
        print_failure_summary(exc)
        raise SystemExit(1)
    except SuiteFailure as exc:
        print_suite_failure_summary(exc)
        raise SystemExit(1)
