from __future__ import annotations

from dataclasses import asdict

from pathlib import Path
from typing import Any

from .config import ForgeConfig
from .external_worker import run_external_worker
from .plugin_header import inspect_plugin_header
from .strictjson import load
from .util import sha256_file


def run_ck_worker(config: ForgeConfig, job_path: Path, result_path: Path, cwd: Path) -> dict[str, Any]:
    result = run_external_worker(config, job_path, result_path, cwd)
    payload = result["worker_result"]
    outputs = []
    for raw in payload.get("outputs", []):
        path = Path(raw)
        if path.is_file():
            item = {"path": str(path), "size": path.stat().st_size, "sha256": sha256_file(path)}
            if path.suffix.casefold() in {".esp", ".esm", ".esl"}:
                item["plugin_header"] = asdict(inspect_plugin_header(path))
            outputs.append(item)
    result["verified_outputs"] = outputs
    return result
