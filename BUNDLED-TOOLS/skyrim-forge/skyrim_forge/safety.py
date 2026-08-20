from __future__ import annotations

import os
from pathlib import Path
from typing import Iterable

from .errors import ApprovalError, SafetyError, ValidationError
from .util import sha256_file

FORBIDDEN_NAMES = {"data", "mods", "overwrite", "profiles", "saves"}


def resolve_existing_or_parent(path: Path) -> Path:
    candidate = path.expanduser()
    if not candidate.is_absolute():
        candidate = (Path.cwd() / candidate).absolute()
    missing: list[str] = []
    current = candidate
    while not current.exists() and current != current.parent:
        missing.append(current.name)
        current = current.parent
    resolved = current.resolve(strict=current.exists())
    for name in reversed(missing):
        resolved = resolved / name
    return resolved


def is_within(path: Path, roots: Iterable[Path]) -> bool:
    candidate = resolve_existing_or_parent(path)
    for root in roots:
        try:
            candidate.relative_to(resolve_existing_or_parent(root))
            return True
        except ValueError:
            continue
    return False


def reject_symlink_chain(path: Path, *, stop: Path | None = None) -> None:
    candidate = path.expanduser().absolute()
    stop_resolved = stop.expanduser().absolute() if stop else None
    chain: list[Path] = []
    current = candidate
    while True:
        chain.append(current)
        if stop_resolved and current == stop_resolved:
            break
        if current == current.parent:
            break
        current = current.parent
    for item in chain:
        if item.exists() and item.is_symlink():
            raise SafetyError(f"Symlink/reparse-point path is not allowed for writes: {item}")


def require_within(path: Path, root: Path, *, must_exist: bool = False) -> Path:
    candidate = resolve_existing_or_parent(path)
    root_resolved = resolve_existing_or_parent(root)
    try:
        candidate.relative_to(root_resolved)
    except ValueError as exc:
        raise SafetyError(f"Path escapes configured workspace: {path}") from exc
    reject_symlink_chain(path, stop=root)
    if must_exist and not path.exists():
        raise FileNotFoundError(path)
    return candidate


def require_read(path: Path, roots: Iterable[Path]) -> Path:
    if not path.exists():
        raise FileNotFoundError(path)
    if not is_within(path, roots):
        raise SafetyError(f"Read denied outside configured roots: {path}")
    return path.resolve(strict=True)


def require_approval(approved: bool, operation: str) -> None:
    if not approved:
        raise ApprovalError(f"Explicit approval is required for {operation}")


def validate_filename(name: str, suffixes: set[str] | None = None) -> None:
    if not name or name in {".", ".."} or Path(name).name != name:
        raise ValidationError(f"Unsafe filename: {name!r}")
    if any(c in name for c in '<>:"/\\|?*') or name.endswith((" ", ".")):
        raise ValidationError(f"Unsafe Windows filename: {name!r}")
    if suffixes and Path(name).suffix.casefold() not in {x.casefold() for x in suffixes}:
        raise ValidationError(f"Filename must use one of {sorted(suffixes)}: {name}")


__all__ = [
    "ApprovalError", "SafetyError", "sha256_file", "resolve_existing_or_parent", "is_within",
    "require_within", "require_read", "require_approval", "validate_filename",
]
