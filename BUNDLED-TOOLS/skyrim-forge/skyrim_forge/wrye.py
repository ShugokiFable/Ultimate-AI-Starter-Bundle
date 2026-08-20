from __future__ import annotations

from dataclasses import asdict

from pathlib import Path
from typing import Any

from .config import ForgeConfig
from .external_worker import run_external_worker
from .plugin_header import inspect_plugin_header


def build_bashed_patch(config: ForgeConfig, job_path: Path, result_path: Path, cwd: Path) -> dict[str, Any]:
    result = run_external_worker(config, job_path, result_path, cwd)
    payload = result["worker_result"]
    output = payload.get("output_plugin")
    if payload.get("status") == "success" and output:
        result["plugin_header"] = asdict(inspect_plugin_header(Path(output)))
    return result
