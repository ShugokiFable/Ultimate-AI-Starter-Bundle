#!/usr/bin/env python3
"""Merge a pack gate into Hermes's real config.yaml.

Two things make this worth a script rather than a text append:

1. **The path is not `~/.hermes/config.yaml`.** Hermes's own documentation says
   it is, but the resolved location honours `HERMES_HOME`, which on this machine
   points at `%LOCALAPPDATA%\\hermes`. Writing to the documented path produced a
   file Hermes never read, and `hermes hooks list` kept reporting nothing while
   looking perfectly installed. The authoritative answer comes from
   `hermes config path`.

2. **The file already holds real user configuration.** Appending text to a YAML
   document that already has structure is how you corrupt it. This parses,
   merges one key, and writes back.

Usage:
    hermes_wire.py <hermes-exe> <python-exe> <gate.py> [--remove] [--all-tools] [--pre-only] [--approve]
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

# Set from the gate being wired, so wiring a second gate cannot strip the first.
MARKER = "completeness_gate.py"


def config_path(hermes: str) -> Path | None:
    """Ask Hermes where its config is. Never guess: the docs are wrong here."""
    try:
        out = subprocess.run([hermes, "config", "path"], capture_output=True,
                             text=True, timeout=60)
        line = (out.stdout or "").strip().splitlines()
        if line:
            p = Path(line[0].strip())
            if p.parent.exists():
                return p
    except Exception:
        pass
    return None


def update_allowlist(cfg: Path, command: str, gate: Path, event: str,
                     *, approve: bool) -> bool:
    """Approve/remove one exact installer-owned Hermes hook command."""
    path = cfg.parent / "shell-hooks-allowlist.json"
    if not approve and not path.exists():
        return True
    original = path.read_text(encoding="utf-8") if path.exists() else ""
    try:
        data = json.loads(original) if original else {"approvals": []}
    except Exception:
        print(f"SKIP: {path} is not valid JSON; refusing to touch it.")
        return False
    if not isinstance(data, dict) or not isinstance(data.get("approvals", []), list):
        print(f"SKIP: {path} has an unknown schema; refusing to touch it.")
        return False

    approvals = [entry for entry in data.get("approvals", [])
                 if not (isinstance(entry, dict)
                         and entry.get("event") == event
                         and entry.get("command") == command)]
    if approve:
        stamp = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
        try:
            mtime = datetime.fromtimestamp(gate.stat().st_mtime, timezone.utc)
            mtime_text = mtime.isoformat().replace("+00:00", "Z")
        except OSError:
            mtime_text = None
        approvals.append({
            "event": event,
            "command": command,
            "approved_at": stamp,
            "script_mtime_at_approval": mtime_text,
        })
    data["approvals"] = approvals

    path.parent.mkdir(parents=True, exist_ok=True)
    if original:
        path.with_suffix(path.suffix + ".bak-gate").write_text(original, encoding="utf-8")
    fd, temp_name = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(data, handle, indent=2, sort_keys=True)
        os.replace(temp_name, path)
    except Exception:
        try:
            os.unlink(temp_name)
        except OSError:
            pass
        raise
    return True


def selftest() -> int:
    with tempfile.TemporaryDirectory(prefix="uabs-hermes-wire-") as root:
        base = Path(root)
        untouched = base / "untouched" / "config.yaml"
        if not update_allowlist(untouched, '"python" "gate" --pre',
                                base / "missing.py", "pre_tool_call", approve=False):
            print("HERMES WIRE SELFTEST: FAIL - absent remove")
            return 1
        if (untouched.parent / "shell-hooks-allowlist.json").exists():
            print("HERMES WIRE SELFTEST: FAIL - absent remove created state")
            return 1
        cfg = base / "config.yaml"
        gate = base / "rtk_safe_hook.py"
        gate.write_text("pass\n", encoding="utf-8")
        command = f'"python" "{gate.as_posix()}" --pre'
        if not update_allowlist(cfg, command, gate, "pre_tool_call", approve=True):
            print("HERMES WIRE SELFTEST: FAIL - approve")
            return 1
        saved = json.loads((base / "shell-hooks-allowlist.json").read_text(encoding="utf-8"))
        if not any(e.get("command") == command for e in saved["approvals"]):
            print("HERMES WIRE SELFTEST: FAIL - approval absent")
            return 1
        if not update_allowlist(cfg, command, gate, "pre_tool_call", approve=False):
            print("HERMES WIRE SELFTEST: FAIL - remove")
            return 1
        saved = json.loads((base / "shell-hooks-allowlist.json").read_text(encoding="utf-8"))
        if any(e.get("command") == command for e in saved["approvals"]):
            print("HERMES WIRE SELFTEST: FAIL - approval survived removal")
            return 1
    print("HERMES WIRE SELFTEST: PASS")
    return 0


def main() -> int:
    if "--selftest" in sys.argv:
        return selftest()
    if len(sys.argv) < 4:
        print("usage: hermes_wire.py <hermes-exe> <python-exe> <gate.py> [--remove] [--pre-only] [--approve]")
        return 0
    try:
        import yaml
    except ImportError:
        print("SKIP: PyYAML not available; cannot safely edit Hermes config.")
        return 0
    hermes, python, gate = sys.argv[1], sys.argv[2], sys.argv[3]
    remove = "--remove" in sys.argv
    pre_only = "--pre-only" in sys.argv

    global MARKER
    MARKER = Path(gate).name  # only ever touch the entries for THIS gate

    cfg = config_path(hermes)
    if cfg is None:
        print("SKIP: could not resolve the Hermes config path.")
        return 0

    text = cfg.read_text(encoding="utf-8") if cfg.exists() else ""
    try:
        data = yaml.safe_load(text) or {}
    except Exception as exc:
        print(f"SKIP: {cfg} is not valid YAML ({type(exc).__name__}); refusing to touch it.")
        return 0
    if not isinstance(data, dict):
        print(f"SKIP: {cfg} is not a mapping; refusing to touch it.")
        return 0

    hooks = data.get("hooks") or {}
    if not isinstance(hooks, dict):
        print("SKIP: existing 'hooks' is not a mapping; refusing to touch it.")
        return 0

    def strip(event: str) -> None:
        entries = [e for e in (hooks.get(event) or [])
                   if not (isinstance(e, dict) and MARKER in str(e.get("command", "")))]
        if entries:
            hooks[event] = entries
        else:
            hooks.pop(event, None)

    strip("pre_tool_call")
    strip("pre_verify")

    py = python.replace("\\", "/")
    gt = gate.replace("\\", "/")
    pre_command = f'"{py}" "{gt}" --pre'
    stop_command = f'"{py}" "{gt}" --stop'

    if not remove:
        # Forward slashes: they are valid on Windows and survive both YAML
        # quoting and Hermes's shlex.split, where backslashes do not.
        entry = {"command": pre_command, "timeout": 20}
        # A gate that inspects file writes must see every tool, and Hermes's
        # tool names are not something to guess at: omitting the matcher is the
        # documented way to match all of them, and the gate ignores any payload
        # shape it does not recognise anyway.
        if "--all-tools" not in sys.argv:
            entry = {"matcher": "terminal", **entry}
        hooks.setdefault("pre_tool_call", []).append(entry)
        if not pre_only:
            hooks.setdefault("pre_verify", []).append({
                "command": stop_command,
                "timeout": 40,
            })

    if hooks:
        data["hooks"] = hooks
    else:
        data.pop("hooks", None)

    if cfg.exists():
        backup = cfg.with_suffix(cfg.suffix + ".bak-gate")
        backup.write_text(text, encoding="utf-8")

    cfg.write_text(yaml.safe_dump(data, sort_keys=False, allow_unicode=True,
                                  default_flow_style=False), encoding="utf-8")

    # Prove it round-trips before claiming success.
    check = yaml.safe_load(cfg.read_text(encoding="utf-8"))
    ok = isinstance(check, dict) and (remove or MARKER in str(check.get("hooks")))
    approve = "--approve" in sys.argv and not remove
    approval_ok = True
    if approve or remove:
        approval_ok = update_allowlist(cfg, pre_command, Path(gate), "pre_tool_call", approve=approve)
        if not pre_only:
            approval_ok = update_allowlist(cfg, stop_command, Path(gate), "pre_verify", approve=approve) and approval_ok
    ok = ok and approval_ok
    print(f"{'removed from' if remove else 'wired into'} {cfg}: {'OK' if ok else 'VERIFY FAILED'}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
