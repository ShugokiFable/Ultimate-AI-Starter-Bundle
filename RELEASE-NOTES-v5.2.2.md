# Ultimate AI Starter Bundle v5.2.2

## Fixed

- Removes or disables stale `headroom-*` scheduled tasks that can flash a terminal window for a fraction of a second.
- Inspects the script path inside scheduled-task arguments, rather than checking only `cmd.exe` or `powershell.exe`.
- Runs orphan-task cleanup during normal installer startup, including when Headroom itself is already missing.
- Preserves valid Headroom deployments with an existing target and deployment manifest.
- Adds a regression test covering missing argument targets, valid tasks, and manifestless deployments.

## Root cause

The previous cleanup only ran inside Grok repair mode. It also treated a task as live whenever its executable existed. For a task shaped like `cmd.exe /c "...\ensure-headroom.cmd"`, `cmd.exe` exists even when the target script has been deleted, so Task Scheduler could continue creating a blink-and-vanish console window.
