#!/usr/bin/env python3
"""Refuse to call a release finished while it is demonstrably half-done.

The failure this exists for is not stupidity, it is literalism. An agent told
"push the fix" pushes the fix: it bumps the version, commits, pushes, cuts a
release, and never touches the README or the changelog, because nobody asked it
to. The work is wrong in a way the agent cannot see, and the user finds out
later.

Prose does not fix this. Every provider's instructions already say "be
thorough", and it still happens. So this is a control, not a reminder: a
`PreToolUse` hook that refuses the push, and a `Stop` hook that refuses to end
the turn, while a release is internally inconsistent.

Design rules, in priority order:

1. **Precision over recall.** A gate that cries wolf gets disabled, and then it
   protects nothing. Every check here fires only on hard evidence, and the whole
   thing stays silent otherwise. It is better to miss a stale doc than to block
   a correct push.
2. **Cheap.** No network, no model call, no repo walk. It reads a handful of
   files and one `git show --stat`. Token cost is zero when clean, and one short
   paragraph when it fires.
3. **Fail open.** Any error, any unknown shape, any non-repo: exit 0 and say
   nothing. A broken gate must never be able to stop work.

The trigger is deliberately narrow: it only engages when the current commit
*changed a version declaration*. That is the moment a release is happening, and
it is the only moment these checks are meaningful.

Modes
-----
    completeness_gate.py --pre     PreToolUse: deny a push/release
    completeness_gate.py --stop    Stop: keep the turn going
    completeness_gate.py --selftest

Wire it with Install-Completeness-Gate.ps1. Claude and Grok read the
Claude-compatible hook shape. Codex loads a plugin. Hermes is merged by
hermes_wire.py. Kimi has no hook system.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import threading
from pathlib import Path

TIMEOUT = 10

# Files that conventionally declare the product version, in the order we trust
# them. Each entry is (relative path, regex with one capture group).
VERSION_SOURCES: list[tuple[str, str]] = [
    ("VERSION.txt", r"^[A-Za-z][A-Za-z .-]*?([0-9]+\.[0-9]+\.[0-9]+)\s*$"),
    ("VERSION", r"^\s*v?([0-9]+\.[0-9]+\.[0-9]+)\s*$"),
    ("CURRENT.txt", r"^\s*v?([0-9]+\.[0-9]+\.[0-9]+)\s*$"),
    ("package.json", r'"version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)"'),
    ("pyproject.toml", r'^version\s*=\s*"([0-9]+\.[0-9]+\.[0-9]+)"'),
    ("Cargo.toml", r'^version\s*=\s*"([0-9]+\.[0-9]+\.[0-9]+)"'),
]

CHANGELOG_NAMES = ("CHANGELOG.md", "CHANGELOG.txt", "CHANGES.md", "HISTORY.md")
README_NAMES = ("README.md", "README.txt", "README.rst")

# Extensions that mean "this was a real change", not a note to self.
CODE_SUFFIXES = {
    ".py", ".js", ".ts", ".tsx", ".jsx", ".go", ".rs", ".c", ".h", ".cpp", ".hpp",
    ".cs", ".java", ".rb", ".php", ".swift", ".kt", ".ps1", ".psm1", ".sh", ".bat",
    ".psc", ".pas", ".lua", ".sql",
}

PUSH_PATTERNS = (
    re.compile(r"\bgit\s+push\b"),
    re.compile(r"\bgh\s+release\s+create\b"),
    re.compile(r"\bnpm\s+publish\b"),
    re.compile(r"\btwine\s+upload\b"),
    re.compile(r"\bcargo\s+publish\b"),
)


def run(args: list[str], cwd: Path) -> str:
    try:
        # stdin=DEVNULL, never inherited: read_input's reader thread may still
        # be parked on fd 0 when the host left the pipe open, and a child that
        # inherits that handle deadlocks on Windows instead of returning.
        done = subprocess.run(args, cwd=str(cwd), capture_output=True, text=True,
                              timeout=TIMEOUT, shell=False,
                              stdin=subprocess.DEVNULL)
    except Exception:
        return ""
    return done.stdout if done.returncode == 0 else ""


def repo_root(start: Path) -> Path | None:
    out = run(["git", "rev-parse", "--show-toplevel"], start).strip()
    return Path(out) if out else None


def declared_version(root: Path) -> tuple[str, str] | None:
    """Return (version, source file) from the first source that declares one."""
    for rel, pattern in VERSION_SOURCES:
        path = root / rel
        if not path.is_file():
            continue
        try:
            text = path.read_text(encoding="utf-8-sig", errors="replace")
        except OSError:
            continue
        found = re.search(pattern, text, re.M)
        if found:
            return found.group(1), rel
    return None


def head_touched_version(root: Path) -> bool:
    """True when the current commit edited a file that declares the version.

    This is the whole trigger. Outside a release, the gate never speaks.
    """
    changed = run(["git", "show", "--name-only", "--pretty=format:", "HEAD"], root)
    if not changed:
        return False
    names = {line.strip().replace("\\", "/") for line in changed.splitlines() if line.strip()}
    return any(rel.replace("\\", "/") in names for rel, _ in VERSION_SOURCES)


def first_existing(root: Path, names: tuple[str, ...]) -> Path | None:
    for name in names:
        candidate = root / name
        if candidate.is_file():
            return candidate
    return None


def mentions_version(path: Path, version: str) -> bool:
    try:
        text = path.read_text(encoding="utf-8-sig", errors="replace")
    except OSError:
        return True  # unreadable: do not invent a finding
    return re.search(r"(?<![0-9.])" + re.escape(version) + r"(?![0-9])", text) is not None


def uncommitted_code(root: Path) -> list[str]:
    out = run(["git", "status", "--porcelain"], root)
    dirty = []
    for line in out.splitlines():
        if len(line) < 4:
            continue
        status, name = line[:2], line[3:].strip().strip('"')
        if status == "??":
            continue
        if Path(name).suffix.lower() in CODE_SUFFIXES:
            dirty.append(name)
    return dirty


def findings(root: Path) -> list[str]:
    """Return the concrete inconsistencies of an in-progress release."""
    if not head_touched_version(root):
        return []
    found = declared_version(root)
    if not found:
        return []
    version, source = found
    problems: list[str] = []

    changelog = first_existing(root, CHANGELOG_NAMES)
    if changelog is not None and not mentions_version(changelog, version):
        problems.append(
            f"{changelog.name} has no entry for {version} (declared in {source}). "
            f"Add what changed in this release before publishing it."
        )

    readme = first_existing(root, README_NAMES)
    if readme is not None:
        try:
            text = readme.read_text(encoding="utf-8-sig", errors="replace")
        except OSError:
            text = ""
        # Only complain when the README states a version of its own and that
        # statement is now wrong. A README without a version is not stale.
        stated = re.findall(r"(?<![0-9.])([0-9]+\.[0-9]+\.[0-9]+)(?![0-9])", text[:4000])
        if stated and version not in stated:
            problems.append(
                f"{readme.name} still says {stated[0]} while {source} says {version}. "
                f"Update it or remove the version from it."
            )

    dirty = uncommitted_code(root)
    if dirty:
        shown = ", ".join(dirty[:5]) + (f", +{len(dirty) - 5} more" if len(dirty) > 5 else "")
        problems.append(f"uncommitted source changes are not in this release: {shown}")

    return problems


def read_input(timeout: float = 2.0) -> dict:
    """Read the hook payload from stdin without ever blocking the host.

    `sys.stdin.read()` waits for EOF. A host that spawns the hook but never
    closes the pipe (Grok CLI 1.0.4 does not) leaves that read hanging until
    the host's own hook timeout fires -- measured at 60s per turn, two Stop
    hooks at 30s each. Design rule 3 above is "fail open", and a read that can
    hang the caller breaks it. Every field below is optional, so time-box the
    read and continue without the payload rather than hold up a turn.
    """
    box: dict = {}

    def slurp() -> None:
        # os.read on the raw fd, not sys.stdin.read: a thread parked inside
        # sys.stdin's BufferedReader holds that object's lock, and interpreter
        # shutdown then blocks trying to finalise it -- which reintroduces the
        # exact hang this function exists to avoid.
        chunks = []
        try:
            fd = sys.stdin.fileno()
            while True:
                part = os.read(fd, 65536)
                if not part:
                    break
                chunks.append(part)
        except Exception:
            pass
        box["raw"] = b"".join(chunks).decode("utf-8", "replace")

    reader = threading.Thread(target=slurp, daemon=True)
    reader.start()
    reader.join(timeout)
    raw = box.get("raw") or ""
    try:
        return json.loads(raw) if raw.strip() else {}
    except Exception:
        return {}


def command_text(payload: dict) -> str:
    tool_input = payload.get("tool_input") or payload.get("toolInput") or {}
    if isinstance(tool_input, dict):
        for key in ("command", "cmd", "script", "input"):
            value = tool_input.get(key)
            if isinstance(value, str):
                return value
    return ""


def mode_pre(payload: dict, cwd: Path) -> int:
    text = command_text(payload)
    if not text or not any(pattern.search(text) for pattern in PUSH_PATTERNS):
        return 0
    root = repo_root(cwd)
    if root is None:
        return 0
    problems = findings(root)
    if not problems:
        return 0
    reason = ("This release is not finished:\n- " + "\n- ".join(problems) +
              "\nFix those, then run the same command again.")
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }}))
    return 0


def mode_stop(payload: dict, cwd: Path) -> int:
    # Never fight a turn that is already being kept alive by this gate, and
    # never speak on the session-end fire, which has no turn left to continue.
    if payload.get("stopHookActive"):
        return 0
    if payload.get("reason") not in (None, "", "end_turn"):
        return 0
    root = repo_root(cwd)
    if root is None:
        return 0
    problems = findings(root)
    if not problems:
        return 0
    reason = ("You changed the version but the release is inconsistent:\n- " +
              "\n- ".join(problems) +
              "\nFinish those now rather than leaving them for the user to find.")
    print(json.dumps({"decision": "block", "reason": reason}))
    return 0


def selftest() -> int:
    import shutil
    import tempfile

    ok = True
    tmp = Path(tempfile.mkdtemp(prefix="gate-selftest-"))
    try:
        run(["git", "init", "-q"], tmp)
        run(["git", "config", "user.email", "t@example.invalid"], tmp)
        run(["git", "config", "user.name", "t"], tmp)
        (tmp / "VERSION.txt").write_text("Thing 1.0.0\n", encoding="utf-8")
        (tmp / "CHANGELOG.md").write_text("# Changelog\n\n## 1.0.0\n- first\n", encoding="utf-8")
        (tmp / "README.md").write_text("# Thing 1.0.0\n", encoding="utf-8")
        run(["git", "add", "-A"], tmp)
        run(["git", "commit", "-qm", "init"], tmp)

        if findings(tmp):
            print("FAIL: a consistent release must be silent"); ok = False

        # Bump the version and nothing else: the exact reported failure.
        (tmp / "VERSION.txt").write_text("Thing 1.1.0\n", encoding="utf-8")
        run(["git", "add", "-A"], tmp)
        run(["git", "commit", "-qm", "bump"], tmp)
        problems = findings(tmp)
        if not any("CHANGELOG.md" in p for p in problems):
            print("FAIL: missing changelog entry not detected"); ok = False
        if not any("README.md" in p for p in problems):
            print("FAIL: stale README version not detected"); ok = False

        # Fix both: silent again.
        (tmp / "CHANGELOG.md").write_text("# Changelog\n\n## 1.1.0\n- x\n\n## 1.0.0\n- first\n", encoding="utf-8")
        (tmp / "README.md").write_text("# Thing 1.1.0\n", encoding="utf-8")
        run(["git", "add", "-A"], tmp)
        run(["git", "commit", "-qm", "docs"], tmp)
        if findings(tmp):
            print(f"FAIL: should be silent once consistent: {findings(tmp)}"); ok = False

        # A commit that does not touch the version never triggers the gate.
        (tmp / "app.py").write_text("x = 1\n", encoding="utf-8")
        run(["git", "add", "-A"], tmp)
        run(["git", "commit", "-qm", "code"], tmp)
        (tmp / "app.py").write_text("x = 2\n", encoding="utf-8")
        if findings(tmp):
            print("FAIL: ordinary work must never trigger the gate"); ok = False

        # Not a repo at all.
        plain = Path(tempfile.mkdtemp(prefix="gate-plain-"))
        try:
            if repo_root(plain) is not None and findings(plain):
                print("FAIL: non-repo must be silent"); ok = False
        finally:
            shutil.rmtree(plain, ignore_errors=True)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print("completeness gate self-test: " + ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


def main() -> int:
    args = set(sys.argv[1:])
    if "--selftest" in args:
        return selftest()
    payload = read_input()
    # A host may report cwd in a shape this interpreter cannot resolve (a POSIX
    # path under Windows, for one). Falling back keeps the gate working instead
    # of silently disabling it, which is the failure mode that matters.
    reported = payload.get("cwd")
    cwd = Path(reported) if reported and Path(reported).is_dir() else Path(os.getcwd())
    try:
        if "--pre" in args:
            return mode_pre(payload, cwd)
        if "--stop" in args:
            return mode_stop(payload, cwd)
    except Exception:
        return 0  # fail open, always
    return 0


if __name__ == "__main__":
    try:
        _code = main()
    except SystemExit as _exc:
        _code = _exc.code if isinstance(_exc.code, int) else 0
    except Exception:
        _code = 0  # fail open, always
    try:
        sys.stdout.flush()
        sys.stderr.flush()
    except Exception:
        pass
    # os._exit, not SystemExit: read_input's reader thread may still be parked
    # on a stdin pipe the host never closed, and a normal shutdown waits on it.
    os._exit(_code if isinstance(_code, int) else 0)
