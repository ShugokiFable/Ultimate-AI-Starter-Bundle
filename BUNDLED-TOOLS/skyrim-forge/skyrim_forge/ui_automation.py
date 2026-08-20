from __future__ import annotations

from pathlib import Path
from typing import Any

from .config import ForgeConfig
from .errors import SafetyError, ValidationError
from .safety import require_approval
from .strictjson import load
from .tools import resolve_tool, run_process

ALLOWED_ACTIONS = {"wait_window", "invoke", "select", "set_value", "read_text", "screenshot", "close_window"}
FORBIDDEN_FIELDS = {"x", "y", "left", "top", "screen_x", "screen_y", "ocr", "image_match"}


def validate_ui_job(path: Path) -> dict[str, Any]:
    job = load(path)
    if not isinstance(job, dict):
        raise ValidationError("UI job root must be an object")
    allowed = {"schema", "job_id", "application", "expected_process", "timeout_seconds", "steps"}
    unknown = set(job) - allowed
    if unknown:
        raise ValidationError(f"Unknown UI job fields: {sorted(unknown)}")
    if job.get("schema") != "skyrim-forge-ui/1":
        raise ValidationError("Unsupported UI job schema")
    steps = job.get("steps")
    if not isinstance(steps, list) or not steps:
        raise ValidationError("UI job steps must be a non-empty array")
    for index, step in enumerate(steps):
        if not isinstance(step, dict):
            raise ValidationError(f"UI step {index} must be an object")
        if set(step) & FORBIDDEN_FIELDS:
            raise SafetyError(f"Coordinate, OCR, and image matching fields are forbidden in UI step {index}")
        if step.get("action") not in ALLOWED_ACTIONS:
            raise ValidationError(f"Unsupported UI action at step {index}: {step.get('action')!r}")
        if not step.get("window_title") and step["action"] not in {"screenshot"}:
            raise ValidationError(f"UI step {index} requires window_title")
        if step["action"] in {"invoke", "select", "set_value", "read_text"} and not (step.get("automation_id") or step.get("name")):
            raise ValidationError(f"UI step {index} requires automation_id or accessible name")
    return job


def run_ui_job(config: ForgeConfig, path: Path, result_path: Path, cwd: Path, *, approved: bool) -> dict[str, Any]:
    require_approval(approved, "Windows UI Automation")
    if not config.allow_ui_automation:
        raise SafetyError("UI Automation is disabled in Forge configuration")
    job = validate_ui_job(path)
    tool, executable = resolve_tool(config, "ui_worker")
    arguments: list[str] = []
    if tool.worker:
        worker_script = tool.worker.resolve(strict=True)
        if not tool.worker_sha256:
            raise SafetyError("A pinned worker_sha256 is required for UI Automation")
        from .util import sha256_file
        actual_worker = sha256_file(worker_script)
        if actual_worker.casefold() != tool.worker_sha256.casefold():
            raise SafetyError(f"UI worker hash mismatch: expected {tool.worker_sha256}, got {actual_worker}")
        if worker_script.suffix.casefold() == ".ps1":
            arguments.extend(["-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", str(worker_script)])
        else:
            arguments.append(str(worker_script))
    arguments.extend(["--job", str(path), "--result", str(result_path)])
    process = run_process(executable, arguments, cwd=cwd, timeout_seconds=min(tool.timeout_seconds, int(job.get("timeout_seconds", tool.timeout_seconds))))
    if process["returncode"] != 0 or not result_path.is_file():
        raise SafetyError("UI Automation worker failed or did not produce a result")
    return {"job": job, "process": process, "result": load(result_path)}
