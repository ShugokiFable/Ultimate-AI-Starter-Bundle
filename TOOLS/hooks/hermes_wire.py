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
    hermes_wire.py <hermes-exe> <python-exe> <gate.py> [--remove] [--all-tools]
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("SKIP: PyYAML not available; cannot safely edit Hermes config.")
    raise SystemExit(0)

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


def main() -> int:
    if len(sys.argv) < 4:
        print("usage: hermes_wire.py <hermes-exe> <python-exe> <gate.py> [--remove]")
        return 0
    hermes, python, gate = sys.argv[1], sys.argv[2], sys.argv[3]
    remove = "--remove" in sys.argv

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

    if not remove:
        # Forward slashes: they are valid on Windows and survive both YAML
        # quoting and Hermes's shlex.split, where backslashes do not.
        py = python.replace("\\", "/")
        gt = gate.replace("\\", "/")
        entry = {"command": f'"{py}" "{gt}" --pre', "timeout": 20}
        # A gate that inspects file writes must see every tool, and Hermes's
        # tool names are not something to guess at: omitting the matcher is the
        # documented way to match all of them, and the gate ignores any payload
        # shape it does not recognise anyway.
        if "--all-tools" not in sys.argv:
            entry = {"matcher": "terminal", **entry}
        hooks.setdefault("pre_tool_call", []).append(entry)
        hooks.setdefault("pre_verify", []).append({
            "command": f'"{py}" "{gt}" --stop',
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
    print(f"{'removed from' if remove else 'wired into'} {cfg}: {'OK' if ok else 'VERIFY FAILED'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
