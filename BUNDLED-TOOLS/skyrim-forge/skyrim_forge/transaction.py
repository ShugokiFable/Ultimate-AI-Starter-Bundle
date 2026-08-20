from __future__ import annotations

import shutil
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from .safety import require_within
from .util import json_dump, sha256_file, utc_now


@dataclass(slots=True)
class Transaction:
    workspace_root: Path
    job_id: str
    root: Path = field(init=False)
    input_dir: Path = field(init=False)
    output_dir: Path = field(init=False)
    logs_dir: Path = field(init=False)
    metadata_dir: Path = field(init=False)

    def __post_init__(self) -> None:
        base = self.workspace_root / ".forge-transactions"
        base.mkdir(parents=True, exist_ok=True)
        self.root = Path(tempfile.mkdtemp(prefix=f"{self.job_id}-", dir=base))
        self.input_dir = self.root / "inputs"
        self.output_dir = self.root / "outputs"
        self.logs_dir = self.root / "logs"
        self.metadata_dir = self.root / "metadata"
        for folder in (self.input_dir, self.output_dir, self.logs_dir, self.metadata_dir):
            folder.mkdir()

    def snapshot(self, source: Path, name: str | None = None) -> dict[str, Any]:
        source = source.resolve(strict=True)
        target = self.input_dir / (name or source.name)
        require_within(target, self.root)
        if source.is_dir():
            shutil.copytree(source, target)
            return {"source": str(source), "snapshot": str(target), "kind": "directory"}
        shutil.copy2(source, target)
        return {"source": str(source), "snapshot": str(target), "kind": "file", "sha256": sha256_file(target), "size": target.stat().st_size}

    def receipt(self, status: str, payload: dict[str, Any]) -> Path:
        outputs = []
        for path in sorted(self.output_dir.rglob("*"), key=lambda p: p.as_posix().casefold()):
            if path.is_file() and not path.is_symlink():
                outputs.append({"path": path.relative_to(self.root).as_posix(), "size": path.stat().st_size, "sha256": sha256_file(path)})
        receipt = {"job_id": self.job_id, "created": utc_now(), "status": status, "root": str(self.root), "outputs": outputs, **payload}
        path = self.metadata_dir / "receipt.json"
        json_dump(path, receipt)
        return path

    def cleanup(self) -> None:
        shutil.rmtree(self.root, ignore_errors=True)
