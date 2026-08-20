from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .errors import ValidationError


def _pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValidationError(f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def _constant(value: str) -> Any:
    raise ValidationError(f"Non-finite JSON number is not allowed: {value}")


def loads(text: str) -> Any:
    try:
        return json.loads(text, object_pairs_hook=_pairs, parse_constant=_constant)
    except ValidationError:
        raise
    except json.JSONDecodeError as exc:
        raise ValidationError(f"Invalid JSON at line {exc.lineno}, column {exc.colno}: {exc.msg}") from exc


def load(path: Path) -> Any:
    return loads(path.read_text(encoding="utf-8-sig"))


def dumps(value: Any, *, pretty: bool = True) -> str:
    return json.dumps(value, indent=2 if pretty else None, ensure_ascii=False, sort_keys=True, allow_nan=False, default=str)
