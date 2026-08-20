from __future__ import annotations

from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path

from .archive import DATA_ROOT_MARKERS, PLUGIN_EXTENSIONS


@dataclass(slots=True)
class ModTreeReport:
    path: str
    file_count: int
    top_level_entries: list[str]
    extension_counts: dict[str, int]
    direct_data_root_content: bool
    unresolved_data_wrapper: bool
    plugin_files: list[str]
    suspicious_files: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)


def inspect_mod_directory(path: Path, max_files: int = 100_000) -> ModTreeReport:
    if not path.is_dir():
        raise NotADirectoryError(path)
    file_count = 0
    extensions: Counter[str] = Counter()
    tops: set[str] = set()
    plugins: list[str] = []
    suspicious: list[str] = []
    direct = False
    unresolved_data = False

    for item in path.iterdir():
        tops.add(item.name)
        low = item.name.lower()
        if item.is_dir() and low in DATA_ROOT_MARKERS:
            direct = True
        if item.is_dir() and low == "data":
            unresolved_data = True
        if item.is_file() and item.suffix.lower() in PLUGIN_EXTENSIONS:
            direct = True

    for candidate in path.rglob("*"):
        if not candidate.is_file():
            continue
        file_count += 1
        if file_count > max_files:
            raise RuntimeError(f"Directory scan exceeded max_scan_files={max_files}")
        relative = candidate.relative_to(path).as_posix()
        extensions[candidate.suffix.lower() or "<none>"] += 1
        if candidate.suffix.lower() in PLUGIN_EXTENSIONS:
            plugins.append(relative)
        low = candidate.name.lower()
        if low == "meta.ini" or low.endswith(".meta"):
            suspicious.append(relative)

    warnings: list[str] = []
    if unresolved_data:
        warnings.append("Installed mod root contains a literal Data directory; MO2/Vortex may have retained an extra archive level")
    if suspicious:
        warnings.append("Mod-manager metadata is present in the inspected tree")
    if not direct and not unresolved_data:
        warnings.append("No recognizable direct Skyrim Data-root content detected")

    return ModTreeReport(
        path=str(path),
        file_count=file_count,
        top_level_entries=sorted(tops, key=str.lower),
        extension_counts=dict(extensions.most_common()),
        direct_data_root_content=direct,
        unresolved_data_wrapper=unresolved_data,
        plugin_files=sorted(plugins, key=str.lower),
        suspicious_files=sorted(suspicious, key=str.lower),
        warnings=warnings,
    )
