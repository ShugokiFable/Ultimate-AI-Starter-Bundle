# Windows process fixtures

Forge tests must never disguise text scripts as `.exe` files. Windows treats `.exe` as PE binaries and may display an Unsupported 16-Bit Application dialog before returning WinError 193 or 216.

Test workers use `.py` files. `run_process` launches those through the active Forge Python interpreter. Configured `.exe` tools are checked for a valid PE header before Windows `CreateProcess` is called. This prevents malformed fixtures and corrupted executables from spawning compatibility dialogs.

PowerShell workers use an explicit `pwsh` or `powershell` interpreter with `shell=False`. Batch files are not accepted as transparent worker executables.
