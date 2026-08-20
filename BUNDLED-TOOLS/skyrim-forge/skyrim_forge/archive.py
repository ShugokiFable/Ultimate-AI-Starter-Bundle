from __future__ import annotations

import re
import stat
import subprocess
import zipfile
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path, PurePosixPath

from .errors import SafetyError, ToolError, ValidationError

DATA_ROOT_MARKERS = {"skse", "scripts", "meshes", "textures", "interface", "sound", "music", "seq", "strings", "video", "grass", "lodsettings", "shadersfx"}
PLUGIN_EXTENSIONS = {".esp", ".esm", ".esl"}
ARCHIVE_EXTENSIONS = {".zip", ".7z", ".rar"}
MAX_MEMBERS = 250_000
MAX_UNCOMPRESSED = 64 * 1024 * 1024 * 1024
MAX_MEMBER = 16 * 1024 * 1024 * 1024


@dataclass(slots=True)
class ArchiveReport:
    path: str
    format: str
    file_count: int
    total_uncompressed_bytes: int | None
    top_level_entries: list[str]
    extension_counts: dict[str, int]
    has_fomod: bool
    has_module_config: bool
    has_data_directory: bool
    direct_data_root_content: bool
    wrapper_depth: int
    suspicious_files: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)


def _normalize(name: str) -> str:
    return name.replace("\\", "/").lstrip("./")


def _validate_name(name: str) -> str:
    raw = name.replace("\\", "/")
    pure = PurePosixPath(raw)
    if not raw or raw.startswith("/") or pure.is_absolute() or ".." in pure.parts:
        raise SafetyError(f"Unsafe archive member path: {name}")
    if pure.parts and (pure.parts[0].endswith(":") or pure.parts[0] in {"", "."}):
        raise SafetyError(f"Unsafe archive member path: {name}")
    return _normalize(raw)


def _list_zip(path: Path) -> tuple[list[str], int, list[str]]:
    warnings: list[str] = []
    with zipfile.ZipFile(path) as archive:
        infos = archive.infolist()
        if len(infos) > MAX_MEMBERS:
            raise SafetyError(f"Archive has too many members: {len(infos)}")
        bad = archive.testzip()
        if bad:
            raise ValidationError(f"ZIP CRC failure: {bad}")
        names: list[str] = []
        total = 0
        seen: dict[str, str] = {}
        for info in infos:
            name = _validate_name(info.filename)
            key = name.casefold()
            if key in seen and seen[key] != name:
                raise SafetyError(f"Case-colliding archive entries: {seen[key]} and {name}")
            if key in seen:
                raise SafetyError(f"Duplicate archive entry: {name}")
            seen[key] = name
            mode = (info.external_attr >> 16) & 0xFFFF
            if stat.S_ISLNK(mode):
                raise SafetyError(f"Archive symlink is not allowed: {name}")
            if info.flag_bits & 1:
                raise SafetyError(f"Encrypted ZIP entry is not allowed: {name}")
            if info.file_size > MAX_MEMBER:
                raise SafetyError(f"Archive member exceeds size limit: {name}")
            total += info.file_size
            if total > MAX_UNCOMPRESSED:
                raise SafetyError("Archive exceeds total uncompressed size limit")
            if not info.is_dir():
                names.append(name)
        return names, total, warnings


def _list_7z(path: Path, seven_zip: Path) -> tuple[list[str], int | None, list[str]]:
    completed = subprocess.run([str(seven_zip), "l", "-slt", str(path)], check=False, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=120, shell=False, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    if completed.returncode != 0:
        raise ToolError(f"7z listing failed ({completed.returncode}): {completed.stderr[-2000:]}")
    names: list[str] = []
    total = 0
    in_entries = False
    seen: set[str] = set()
    for line in completed.stdout.splitlines():
        if line.startswith("----------"):
            in_entries = True
            continue
        if not in_entries:
            continue
        if line.startswith("Path = "):
            value = _validate_name(line[7:].strip())
            if value and value != path.name:
                key = value.casefold()
                if key in seen:
                    raise SafetyError(f"Duplicate/case-colliding archive entry: {value}")
                seen.add(key)
                names.append(value)
        elif line.startswith("Size = "):
            try:
                size = int(line[7:].strip())
                if size > MAX_MEMBER:
                    raise SafetyError("Archive member exceeds size limit")
                total += size
                if total > MAX_UNCOMPRESSED:
                    raise SafetyError("Archive exceeds total uncompressed size limit")
            except ValueError:
                pass
    if len(names) > MAX_MEMBERS:
        raise SafetyError(f"Archive has too many members: {len(names)}")
    return names, total, ["7z/RAR listing cannot independently verify entry CRC without extraction"]


def _common_wrapper_depth(paths: list[PurePosixPath]) -> int:
    if not paths:
        return 0
    parts = [path.parts for path in paths if path.parts]
    depth = 0
    for columns in zip(*parts):
        if len({item.casefold() for item in columns}) != 1:
            break
        depth += 1
    return depth


def inspect_archive(path: Path, *, seven_zip: Path | None = None, allow_external: bool = False) -> ArchiveReport:
    path = path.resolve(strict=True)
    suffix = path.suffix.casefold()
    if suffix not in ARCHIVE_EXTENSIONS:
        raise ValidationError(f"Unsupported archive type: {suffix}")
    if suffix == ".zip":
        names, total, listing_warnings = _list_zip(path); fmt = "zip"
    else:
        if not allow_external:
            raise SafetyError("7z/RAR inspection requires external process execution")
        if not seven_zip or not seven_zip.is_file():
            raise FileNotFoundError("Configured seven_zip executable was not found")
        names, total, listing_warnings = _list_7z(path, seven_zip); fmt = suffix[1:]
    paths = [PurePosixPath(name) for name in names]
    tops = sorted({item.parts[0] for item in paths if item.parts}, key=str.casefold)
    extensions = Counter(item.suffix.casefold() or "<none>" for item in paths)
    lower = [name.casefold() for name in names]
    has_module_config = any(name.endswith("fomod/moduleconfig.xml") for name in lower)
    has_fomod = any(name.startswith("fomod/") or "/fomod/" in f"/{name}" for name in lower)
    has_data = any(item.parts and item.parts[0].casefold() == "data" for item in paths)
    direct = any(item.parts and (item.parts[0].casefold() in DATA_ROOT_MARKERS or item.suffix.casefold() in PLUGIN_EXTENSIONS) for item in paths)
    suspicious = [name for name in names if PurePosixPath(name).name.casefold() == "meta.ini" or name.casefold().endswith(".meta")]
    warnings = list(listing_warnings)
    errors: list[str] = []
    wrapper_depth = _common_wrapper_depth(paths)
    if not direct and not has_data and not has_module_config:
        errors.append("No recognizable Skyrim Data-root content or FOMOD ModuleConfig.xml")
    if wrapper_depth >= 2 and not has_module_config:
        warnings.append(f"Archive appears to have {wrapper_depth} common wrapper directories")
    if has_fomod and not has_module_config:
        errors.append("fomod directory exists but ModuleConfig.xml was not found")
    if has_data and direct:
        warnings.append("Archive mixes a Data directory with direct Data-root content")
    if suspicious:
        warnings.append("MO2 metadata or sidecars appear bundled")
    return ArchiveReport(str(path), fmt, len(names), total, tops[:100], dict(extensions.most_common()), has_fomod, has_module_config, has_data, direct, wrapper_depth, sorted(suspicious)[:500], warnings, errors)
