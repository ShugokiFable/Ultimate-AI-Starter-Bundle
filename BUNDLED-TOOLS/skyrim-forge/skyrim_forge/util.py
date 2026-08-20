from __future__ import annotations

import hashlib
import json
import os
import re
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Iterator

from .errors import ValidationError

SEMVER_RE = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z.-]+))?$" )


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def sha256_file(path: Path, chunk_size: int = 1024 * 1024) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(chunk_size):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def atomic_write_bytes(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        try:
            Path(temporary).unlink()
        except FileNotFoundError:
            pass


def atomic_write_text(path: Path, text: str) -> None:
    atomic_write_bytes(path, text.encode("utf-8"))


def json_dump(path: Path, value: Any) -> None:
    atomic_write_text(path, json.dumps(value, indent=2, ensure_ascii=False, sort_keys=True, allow_nan=False, default=str) + "\n")


def iter_files(root: Path) -> Iterator[Path]:
    for path in sorted(root.rglob("*"), key=lambda p: p.as_posix().casefold()):
        if path.is_file() and not path.is_symlink():
            yield path


def validate_semver(value: str) -> tuple[int, int, int, str | None]:
    match = SEMVER_RE.fullmatch(value)
    if not match:
        raise ValidationError(f"Invalid semantic version: {value!r}")
    return int(match.group(1)), int(match.group(2)), int(match.group(3)), match.group(4)


def safe_name(value: str, *, fallback: str = "Project") -> str:
    cleaned = re.sub(r'[<>:"/\\|?*\x00-\x1f]', "_", value).strip().rstrip(".")
    cleaned = re.sub(r"\s+", " ", cleaned)
    return cleaned or fallback


def truncate(text: str, limit: int = 20000) -> str:
    if len(text) <= limit:
        return text
    return text[: limit // 2] + "\n...<truncated>...\n" + text[-limit // 2 :]
