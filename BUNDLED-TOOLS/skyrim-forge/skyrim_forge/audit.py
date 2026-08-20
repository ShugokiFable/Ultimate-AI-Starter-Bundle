from __future__ import annotations

import json
import threading
from pathlib import Path
from typing import Any

from .util import utc_now

_LOCK = threading.Lock()


def write_audit(path: Path, operation: str, status: str, details: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    entry = {"time": utc_now(), "operation": operation, "status": status, "details": details}
    line = json.dumps(entry, ensure_ascii=False, sort_keys=True, allow_nan=False, default=str) + "\n"
    with _LOCK:
        with path.open("a", encoding="utf-8", newline="\n") as stream:
            stream.write(line)
            stream.flush()
