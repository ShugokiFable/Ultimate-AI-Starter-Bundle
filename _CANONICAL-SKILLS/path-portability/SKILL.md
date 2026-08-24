---
name: path-portability
description: Use when code, installers, archives, configs, subprocesses, or scripts handle filesystem paths across machines.
---

# Path Portability

## Core rule
Paths must survive **spaces**, **Unicode**, alternate drives, different user homes, and invocation from a different working directory.

## Contract
- Resolve known roots at runtime; never embed another machine’s home or drive.
- Distinguish **absolute** paths from paths relative to the script/config that owns them.
- Quote only at the boundary that requires quoting; do not store shell-escaped strings as filesystem paths.
- Use path APIs rather than string concatenation.
- For subprocesses, pass argument arrays when the platform/API supports them.
- Test a path containing spaces, non-ASCII characters, and a different current directory.
- For archives, reject traversal (`..`), absolute members, and unsafe device names.

On Windows, verify PowerShell 5.1/cmd quoting separately from POSIX shells. A path that works at `C:\work` is not portability evidence.
