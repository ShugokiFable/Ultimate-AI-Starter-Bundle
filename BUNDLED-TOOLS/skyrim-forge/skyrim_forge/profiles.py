from __future__ import annotations

import shutil
from pathlib import Path
from typing import Any

from .errors import ValidationError
from .safety import require_approval, require_within
from .util import json_dump, sha256_file, utc_now

PROFILE_FILES = ("plugins.txt", "loadorder.txt", "modlist.txt", "skyrim.ini", "skyrimprefs.ini", "archives.txt", "lockedorder.txt")


def snapshot_profile(profile: Path, target: Path) -> dict[str, Any]:
    profile = profile.resolve(strict=True)
    if not profile.is_dir():
        raise ValidationError(f"MO2 profile is not a directory: {profile}")
    target.mkdir(parents=True, exist_ok=False)
    copied = []
    for name in PROFILE_FILES:
        source = profile / name
        if source.is_file():
            destination = target / name
            shutil.copy2(source, destination)
            copied.append({"name": name, "sha256": sha256_file(destination), "size": destination.stat().st_size})
    if not copied:
        raise ValidationError(f"No recognized MO2 profile files found in {profile}")
    report = {"profile": str(profile), "snapshot": str(target), "created": utc_now(), "files": copied}
    json_dump(target / "snapshot.json", report)
    return report


def read_plugin_list(path: Path) -> list[str]:
    if not path.is_file():
        return []
    result = []
    for raw in path.read_text(encoding="utf-8-sig", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        result.append(line)
    return result


def apply_load_order(proposed: Path, live: Path, backup_root: Path, *, approved: bool) -> dict[str, Any]:
    require_approval(approved, "load-order update")
    proposed = proposed.resolve(strict=True)
    live_parent = live.parent.resolve(strict=True)
    if proposed.name.casefold() not in {"plugins.txt", "loadorder.txt"}:
        raise ValidationError("Proposed load-order file must be plugins.txt or loadorder.txt")
    if live.name.casefold() != proposed.name.casefold():
        raise ValidationError("Proposed and target load-order filenames differ")
    lines = read_plugin_list(proposed)
    if not lines:
        raise ValidationError("Proposed load order is empty")
    backup_root.mkdir(parents=True, exist_ok=True)
    backup = backup_root / f"{live.name}.{utc_now().replace(':','')}.bak"
    if live.is_file():
        shutil.copy2(live, backup)
    temporary = live.with_name(f".{live.name}.forge.tmp")
    shutil.copy2(proposed, temporary)
    temporary.replace(live)
    return {"result": "PASS", "target": str(live), "backup": str(backup) if backup.exists() else None, "entries": len(lines), "sha256": sha256_file(live)}
