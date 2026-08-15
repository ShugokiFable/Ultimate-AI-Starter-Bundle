#!/usr/bin/env python3
"""Skyrim workspace guard.

Enforces three laws that are otherwise only prose in CLAUDE.md / AGENTS.md:

  1. Game Data, mod-manager staging, saves, profiles and installed tools are
     read-only.  No agent writes there.
  2. SSEEdit / xEdit / Creation Kit / Synthesis GUI are never launched.
  3. PowerShell Get-Content|Set-Content round-trips corrupt UTF-8 source into
     mojibake.  Use Edit, or sed/perl.

Consumption modes:

    skyrim-guard.py hook          Claude Code PreToolUse, tool JSON on stdin
    skyrim-guard.py path <p>      check one write target   (any AI app)
    skyrim-guard.py cmd  "<c>"    check one shell command  (any AI app)
    skyrim-guard.py --selftest    run the built-in checks

Exit 0 = allowed.  Exit 2 = blocked, reason on stderr.
Set SKYRIM_GUARD=off to bypass.
"""

import json
import os
import re
import sys

# An ancestor directory holding one of these means we are inside a deployed
# game install or a mod manager's realm.  Filesystem evidence, so no drive
# letter, username or folder name is ever assumed.
MARKERS = (
    "skyrimse.exe", "skyrimvr.exe", "tesv.exe", "skse64_loader.exe",
    "modorganizer.exe", "modorganizer.ini", "vortex.exe",
)

# Fallbacks for realms whose marker may be out of reach (saves, profiles,
# staging on another volume).
READONLY_PATTERNS = (
    r"/steamapps/common/skyrim",
    r"/my games/skyrim",
    r"/mod organizer 2/",
    r"/appdata/roaming/vortex/",
    r"/appdata/local/black tree gaming",
)

GUI_TOOLS = re.compile(
    r"\b(?:(?:sse|tes5|tes4|fo3|fo4|enderal|x)edit(?:quickautoclean)?"
    r"|xtesedit"
    r"|creationkit"
    r"|synthesis)"
    r"(?:64)?\.exe\b",
    re.I,
)
SYNTHESIS_CLI = re.compile(r"synthesis\.bethesda\.cli(?:\.exe)?\b", re.I)

PS_WRITE = re.compile(r"\b(?:set-content|out-file|add-content)\b", re.I)
PS_ROUNDTRIP = re.compile(
    r"\bget-content\b[^|]*\|.*\b(?:set-content|out-file|add-content)\b", re.I
)
PS_ENCODING = re.compile(r"-encoding\b", re.I)
SOURCE_EXT = re.compile(
    r"\.(?:psc|ini|json|md|txt|xml|cpp|c|h|hpp|yaml|yml|toml|ps1|bat|py|cs)\b", re.I
)


def norm(path):
    return os.path.abspath(path).replace("\\", "/").lower()


def readonly_reason(path):
    """Return why `path` is a read-only realm, or None if it is writable."""
    n = norm(path)
    for pat in READONLY_PATTERNS:
        if re.search(pat, n):
            return "matches read-only realm pattern %r" % pat
    d = os.path.dirname(os.path.abspath(path))
    for _ in range(12):
        for marker in MARKERS:
            if os.path.exists(os.path.join(d, marker)):
                return "ancestor %s contains %s" % (d.replace("\\", "/"), marker)
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
    return None


def check_path(path):
    why = readonly_reason(path)
    if why:
        return (
            "BLOCKED: %s is a read-only realm (%s).\n"
            "Game Data, mod-manager staging, saves, profiles and installed tools "
            "are never written by an agent. Author inside the mod's own owner root "
            "and version snapshot, then let the user deploy." % (path, why)
        )
    return None


def check_command(command, powershell=False):
    if GUI_TOOLS.search(command) and not SYNTHESIS_CLI.search(command):
        return (
            "BLOCKED: refuses to launch SSEEdit/xEdit/Creation Kit/Synthesis GUI.\n"
            "xEdit and CK are user-side. Ask the user to run it and report findings, "
            "or use typed plugin tooling. (Synthesis.Bethesda.CLI is allowed.)"
        )
    if powershell:
        if PS_ROUNDTRIP.search(command):
            return (
                "BLOCKED: Get-Content | Set-Content round-trip double-encodes UTF-8 "
                "into mojibake.\nUse the Edit tool, or sed/perl via Bash."
            )
        if PS_WRITE.search(command) and SOURCE_EXT.search(command) \
                and not PS_ENCODING.search(command):
            return (
                "BLOCKED: Set-Content/Out-File to a source file without an explicit "
                "-Encoding corrupts UTF-8.\nUse the Edit tool, or sed/perl via Bash. "
                "If PowerShell is genuinely required, pass -Encoding utf8."
            )
    return None


def run_hook():
    try:
        data = json.load(sys.stdin)
    except (ValueError, OSError):
        return None
    tool = data.get("tool_name", "")
    ti = data.get("tool_input") or {}
    for key in ("file_path", "path", "notebook_path"):
        target = ti.get(key)
        if isinstance(target, str) and target:
            reason = check_path(target)
            if reason:
                return reason
    command = ti.get("command")
    if isinstance(command, str) and command:
        return check_command(command, powershell=tool == "PowerShell")
    return None


def selftest():
    assert check_command("SSEEdit.exe -quickautoclean")
    assert check_command('& "C:/Tools/xEdit/SSEEditQuickAutoClean.exe"')
    assert check_command("CreationKit.exe")
    assert check_command("Synthesis.exe")
    assert check_command("Synthesis.Bethesda.CLI.exe run") is None
    assert check_command("forge doctor") is None
    assert check_command("git status") is None

    ps = dict(powershell=True)
    assert check_command("Get-Content a.psc | Set-Content b.psc", **ps)
    assert check_command("Set-Content -Path x.ini -Value $v", **ps)
    assert check_command("Set-Content -Path x.ini -Value $v -Encoding utf8", **ps) is None
    assert check_command("Set-Content -Path x.bin -Value $v", **ps) is None
    assert check_command("Get-Content a.psc | Set-Content b.psc") is None  # bash, not ps
    assert check_command("Get-ChildItem -Recurse", **ps) is None

    assert readonly_reason("C:/Games/steamapps/common/Skyrim Special Edition/Data/x.esp")
    assert readonly_reason("C:/Users/x/Documents/My Games/Skyrim Special Edition/Saves/s.ess")
    assert readonly_reason("C:/Modding/Mod Organizer 2/mods/Foo/foo.esp")
    assert readonly_reason(os.path.join(os.path.dirname(os.path.abspath(__file__)), "x.esp")) is None
    print("selftest ok")


def main():
    if os.environ.get("SKYRIM_GUARD", "").lower() == "off":
        return 0
    argv = sys.argv[1:]
    if not argv:
        sys.stderr.write(__doc__)
        return 1
    mode = argv[0]
    if mode == "--selftest":
        selftest()
        return 0
    if mode == "hook":
        reason = run_hook()
    elif mode == "path" and len(argv) > 1:
        reason = check_path(argv[1])
    elif mode == "cmd" and len(argv) > 1:
        reason = check_command(" ".join(argv[1:]), powershell=True)
    else:
        sys.stderr.write(__doc__)
        return 1
    if reason:
        sys.stderr.write(reason + "\n")
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
