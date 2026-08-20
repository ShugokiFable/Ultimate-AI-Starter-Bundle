from __future__ import annotations

from copy import deepcopy
from pathlib import Path
from typing import Any

from .config import ForgeConfig
from .errors import ToolError, ValidationError
from .safety import require_within
from .strictjson import load
from .tools import resolve_tool, run_process
from .util import json_dump, safe_name, sha256_file

ALLOWED_WORKER_TYPES = {"loot", "wrye_bash", "creation_kit", "asset", "animation", "bodyslide", "lod", "grass_cache", "synthesis", "audio"}
PATH_RESULT_FIELDS = {"plan_path", "output_plugin", "archive_path", "manifest_path", "log_path"}


def validate_worker_job(job: dict[str, Any]) -> dict[str, Any]:
    allowed = {"schema", "job_id", "worker_type", "operation", "inputs", "output_dir", "options"}
    unknown = set(job) - allowed
    if unknown:
        raise ValidationError(f"Unknown external-worker job fields: {sorted(unknown)}")
    if job.get("schema") != "skyrim-forge-external-worker/1":
        raise ValidationError("Unsupported external-worker job schema")
    if job.get("worker_type") not in ALLOWED_WORKER_TYPES:
        raise ValidationError(f"Unsupported worker type: {job.get('worker_type')!r}")
    if not isinstance(job.get("job_id"), str) or not job["job_id"].strip():
        raise ValidationError("worker job_id is required")
    safe_name(job["job_id"], fallback="worker-job")
    if not isinstance(job.get("operation"), str) or not job["operation"].strip():
        raise ValidationError("worker operation is required")
    if not isinstance(job.get("inputs", {}), dict) or not isinstance(job.get("options", {}), dict):
        raise ValidationError("worker inputs/options must be objects")
    return job


def _confined_output(raw: Any, output_root: Path, field: str) -> str:
    if not isinstance(raw, str) or not raw.strip():
        raise ToolError(f"Worker result field {field} must be a path string")
    candidate = Path(raw).expanduser()
    if not candidate.is_absolute():
        candidate = output_root / candidate
    return str(require_within(candidate, output_root))


def _validate_result_paths(payload: dict[str, Any], output_root: Path) -> None:
    outputs = payload.get("outputs", [])
    if not isinstance(outputs, list):
        raise ToolError("Worker result outputs must be an array")
    payload["outputs"] = [_confined_output(raw, output_root, "outputs") for raw in outputs]
    for field in PATH_RESULT_FIELDS:
        if field in payload and payload[field] not in {None, ""}:
            payload[field] = _confined_output(payload[field], output_root, field)


def run_external_worker(config: ForgeConfig, job_path: Path, result_path: Path, cwd: Path) -> dict[str, Any]:
    job = validate_worker_job(load(job_path))
    name = {
        "loot": "loot_worker", "wrye_bash": "wrye_worker", "creation_kit": "ck_worker",
        "asset": "asset_worker", "animation": "animation_worker", "bodyslide": "bodyslide_worker",
        "lod": "lod_worker", "grass_cache": "grass_worker", "synthesis": "synthesis_worker", "audio": "audio_worker",
    }[job["worker_type"]]
    tool, worker = resolve_tool(config, name, require_pin=True)

    cwd = require_within(cwd, config.workspace_root)
    cwd.mkdir(parents=True, exist_ok=True)
    result_path = require_within(result_path, cwd)
    if result_path.exists():
        raise ValidationError(f"Worker result path already exists: {result_path}")

    broker_root = cwd / ".forge-worker" / safe_name(job["job_id"], fallback="worker-job")
    output_root = require_within(broker_root / "outputs", cwd)
    output_root.mkdir(parents=True, exist_ok=False)
    effective_job_path = broker_root / "job.effective.json"
    effective_job = deepcopy(job)
    effective_job["output_dir"] = str(output_root)
    json_dump(effective_job_path, effective_job)

    result = run_process(
        worker,
        ["--job", str(effective_job_path), "--result", str(result_path)],
        cwd=cwd,
        timeout_seconds=tool.timeout_seconds,
        environment={"SKYRIM_FORGE_OUTPUT_DIR": str(output_root)},
    )
    if result["returncode"] != 0:
        raise ToolError(f"{name} failed with exit code {result['returncode']}: {result['stderr']}")
    if not result_path.is_file():
        raise ToolError(f"{name} returned success but did not create {result_path}")
    payload = load(result_path)
    if not isinstance(payload, dict) or payload.get("job_id") != job["job_id"] or payload.get("status") not in {"success", "failure", "blocked"}:
        raise ToolError(f"Invalid worker result contract: {result_path}")
    _validate_result_paths(payload, output_root)
    json_dump(result_path, payload)
    return {
        "process": result,
        "worker_result": payload,
        "effective_job": str(effective_job_path),
        "output_root": str(output_root),
        "result_sha256": sha256_file(result_path),
    }
