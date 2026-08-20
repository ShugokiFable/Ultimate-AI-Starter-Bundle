# Forge external workers

Forge directly automates xEdit and the official Papyrus compiler. LOOT, Wrye Bash, and Creation Kit do not expose one stable, complete public headless interface for every required operation. Forge therefore uses a version-pinned JSON worker contract for those tools.

A worker is a separately configured executable that accepts:

```text
--job <job.json> --result <result.json>
```

The result must contain the matching `job_id`, a `status` of `success`, `failure`, or `blocked`, and explicit output paths. Forge verifies the result and all reported files. Arbitrary shell commands are not part of the protocol.

`SkyrimForge.UIWorker.ps1` is the narrow coordinate-free Windows UI Automation fallback. Configure `tools.ui_worker.executable` as Windows PowerShell and `tools.ui_worker.worker` as the script path. UI automation remains disabled by default.
