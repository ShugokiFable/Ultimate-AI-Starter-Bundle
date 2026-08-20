from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass(slots=True)
class PluginEntry:
    name: str
    enabled: bool
    position: int


def parse_plugins_file(path: Path) -> list[PluginEntry]:
    entries: list[PluginEntry] = []
    text = path.read_text(encoding="utf-8-sig", errors="replace")
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        enabled = line.startswith("*")
        name = line[1:].strip() if enabled else line
        if not name.lower().endswith((".esp", ".esm", ".esl")):
            continue
        entries.append(PluginEntry(name=name, enabled=enabled, position=len(entries)))
    return entries
