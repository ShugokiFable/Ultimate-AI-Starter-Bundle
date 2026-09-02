#!/usr/bin/env python3
"""Rewrite only RTK commands whose output is safe to compress automatically.

The upstream RTK hook rewrites far more than output-only commands: measured at
0.47.0 it also catches mutating Git, lossy diffs/logs, broken compound ``find``
expressions, and file/search commands whose output is no longer pipe-safe. This
hook keeps that broad policy off and delegates only exact ``git status`` plus
standalone, human-facing pytest/cargo/go test runs.

Unknown payloads, missing RTK, unsupported commands, and every error fail open.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys

try:
    from assumption_gate import command_text, read_input, tool_input
except Exception:  # installed beside assumption_gate.py; fail open if incomplete
    raise SystemExit(0)


TIMEOUT = 5
EXPECTED_RTK_VERSION = "0.47.0"
SHELL_META = re.compile(r"[\r\n;&|<>`]|\$\(")
GIT_STATUS = re.compile(r"^\s*git(?:\.exe)?\s+status(?:\s+(?:--short|-s))?\s*$", re.I)
TEST_COMMAND = re.compile(
    r"^\s*(?:"
    r"(?:python(?:3(?:\.\d+)*)?|py)(?:\.exe)?\s+-m\s+pytest"
    r"|pytest(?:\.exe)?"
    r"|cargo(?:\.exe)?\s+test"
    r"|go(?:\.exe)?\s+test"
    r")(?:\s|$)",
    re.I,
)
MACHINE_OUTPUT = re.compile(
    r"(?:^|\s)(?:"
    r"--json(?:-report)?|--output(?:-format)?|--reporter|--junit(?:xml)?|"
    r"--xml|--collect-only|--list|--logger|--log-file|--format|-json|-z"
    r")(?:\s|=|$)",
    re.I,
)


def eligible(command: str) -> bool:
    """True only for the measured, standalone, human-readable surface."""
    if not command or SHELL_META.search(command):
        return False
    if GIT_STATUS.fullmatch(command):
        return True
    return bool(TEST_COMMAND.match(command) and not MACHINE_OUTPUT.search(command))


def rewrite(command: str) -> str:
    """Ask RTK for its rewrite; return empty text for every pass-through/error."""
    rtk = shutil.which("rtk")
    if not rtk and os.environ.get("USERPROFILE"):
        candidate = os.path.join(os.environ["USERPROFILE"], ".local", "bin", "rtk.exe")
        if os.path.isfile(candidate):
            rtk = candidate
    if not rtk:
        return ""
    env = os.environ.copy()
    if not env.get("HOME") and not env.get("CLAUDE_CONFIG_DIR"):
        profile = env.get("USERPROFILE")
        if profile:
            env["CLAUDE_CONFIG_DIR"] = os.path.join(profile, ".claude")
    try:
        version = subprocess.run(
            [rtk, "--version"], capture_output=True, text=True, timeout=2,
            stdin=subprocess.DEVNULL, env=env,
        )
        if version.returncode != 0 or not re.search(
                rf"\b{re.escape(EXPECTED_RTK_VERSION)}\b", version.stdout or ""):
            return ""  # a new rewrite table is raw until it is re-measured
        done = subprocess.run(
            [rtk, "rewrite", command],
            capture_output=True,
            text=True,
            timeout=TIMEOUT,
            stdin=subprocess.DEVNULL,
            env=env,
        )
    except Exception:
        return ""
    if done.returncode != 3:
        return ""
    changed = (done.stdout or "").strip()
    return changed if changed and changed != command else ""


def modification(payload: dict, data: dict, changed: str) -> dict:
    """Return the native modification shape for Hermes or Claude-compatible hosts."""
    updated = dict(data)
    key = next((name for name in ("command", "cmd", "script", "input")
                if isinstance(updated.get(name), str)), "command")
    updated[key] = changed
    if payload.get("hook_event_name") == "pre_tool_call":
        return {"action": "modify", "args": updated}
    return {"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "updatedInput": updated,
    }}


def selftest() -> int:
    allowed = (
        "git status", "git status --short", "git status -s",
        "python -m pytest -q", "pytest tests/test_one.py",
        "cargo test --workspace", "go test ./...",
    )
    denied = (
        "git diff", "git log", "git show HEAD", "git add -A", "git commit -m x",
        "git push", "git status --porcelain -z", "find . -name '*.py'", "cat x",
        "rg needle", "curl https://example.com", "gh pr view", "npm test",
        "python -m unittest", "dotnet test", "pytest --json-report",
        "pytest --junitxml=out.xml", "cargo test -- --format json",
        "go test -json ./...", "pytest -q | tee test.log", "pytest > test.log",
        "git status && git add -A", "$(git status)",
    )
    failures = [f"allowed:{c}" for c in allowed if not eligible(c)]
    failures += [f"denied:{c}" for c in denied if eligible(c)]

    claude = modification(
        {"tool_input": {"command": "git status", "description": "check"}},
        {"command": "git status", "description": "check"},
        "rtk git status",
    )
    hermes = modification(
        {"hook_event_name": "pre_tool_call"},
        {"command": "pytest -q", "timeout": 30},
        "rtk pytest -q",
    )
    if claude.get("hookSpecificOutput", {}).get("updatedInput", {}).get("description") != "check":
        failures.append("claude payload fields not preserved")
    if hermes.get("action") != "modify" or hermes.get("args", {}).get("timeout") != 30:
        failures.append("hermes payload fields not preserved")

    if failures:
        print("RTK SAFE HOOK SELFTEST: FAIL - " + ", ".join(failures))
        return 1
    print("RTK SAFE HOOK SELFTEST: PASS")
    return 0


def main() -> int:
    if "--selftest" in sys.argv:
        return selftest()
    payload = read_input()
    data = tool_input(payload)
    command = command_text(data)
    if not eligible(command):
        return 0
    changed = rewrite(command)
    if changed:
        print(json.dumps(modification(payload, data, changed), separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
