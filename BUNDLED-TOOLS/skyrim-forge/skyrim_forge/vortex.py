from __future__ import annotations

from pathlib import Path
from typing import Any

from .config import ForgeConfig
from .errors import ValidationError
from .modtree import inspect_mod_directory
from .util import sha256_file


def snapshot_vortex_staging(config: ForgeConfig, *, limit_mods: int = 10000) -> dict[str, Any]:
    root = config.vortex_staging
    if root is None or not root.is_dir():
        raise ValidationError("Vortex staging directory is not configured")
    mods = []
    for index, child in enumerate(sorted(root.iterdir(), key=lambda p: p.name.casefold())):
        if index >= limit_mods:
            raise ValidationError(f"Vortex staging scan exceeded limit {limit_mods}")
        if not child.is_dir() or child.is_symlink():
            continue
        report = inspect_mod_directory(child, config.max_scan_files)
        mods.append({
            "name": child.name,
            "path": str(child),
            "file_count": report.file_count,
            "plugins": report.plugin_files,
            "warnings": report.warnings,
        })
    return {
        "result": "PASS",
        "staging": str(root.resolve()),
        "mods": mods,
        "count": len(mods),
        "evidence": "Read-only Vortex staging inventory. Forge does not edit Vortex databases or deployment state.",
    }
