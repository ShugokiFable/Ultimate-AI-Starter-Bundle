#!/usr/bin/env python3
"""Replace the retired openrouter-extra route in resumable Hermes sessions."""
from __future__ import annotations

import datetime as dt
import json
import os
import sqlite3
import sys
from pathlib import Path

LEGACY = {"openrouter-extra", "custom:openrouter-extra"}


def migrate(db_path: Path) -> int:
    if not db_path.is_file():
        print("migrated=0 state_db=missing")
        return 0

    db = sqlite3.connect(str(db_path), timeout=30)
    db.execute("pragma busy_timeout=30000")
    columns = {row[1] for row in db.execute("pragma table_info(sessions)")}
    required = {"id", "model_config", "billing_provider"}
    if not required.issubset(columns):
        db.close()
        print("migrated=0 sessions_schema=unsupported")
        return 0

    rows = db.execute(
        "select id, model_config, billing_provider from sessions "
        "where coalesce(model_config, '') like '%openrouter-extra%' "
        "or billing_provider = 'openrouter-extra'"
    ).fetchall()
    changes = []
    for session_id, raw_config, billing_provider in rows:
        new_config = raw_config
        original_provider = None
        if raw_config:
            try:
                parsed = json.loads(raw_config)
            except (TypeError, ValueError):
                parsed = None
            if isinstance(parsed, dict):
                original_provider = str(parsed.get("provider") or "").strip()
            if original_provider.lower() in LEGACY:
                parsed["provider"] = "openrouter"
                new_config = json.dumps(parsed, ensure_ascii=False, separators=(",", ":"))
        new_billing = "openrouter" if billing_provider == "openrouter-extra" else billing_provider
        if new_config != raw_config or new_billing != billing_provider:
            changes.append((session_id, raw_config, billing_provider, new_config, new_billing, original_provider))

    if not changes:
        db.close()
        print("migrated=0")
        return 0

    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S%f")
    backup = db_path.with_name(f"{db_path.name}.uabs-openrouter-extra-{stamp}.json")
    backup_tmp = backup.with_name(backup.name + ".tmp")
    payload = {
        "schema": 1,
        "database": str(db_path),
        "rows": [
            {"id": row[0], "provider": row[5], "billing_provider": row[2]}
            for row in changes
        ],
    }
    backup_tmp.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    os.replace(backup_tmp, backup)

    try:
        db.execute("begin immediate")
        for session_id, old_config, old_billing, new_config, new_billing, _ in changes:
            changed = db.execute(
                "update sessions set model_config = ?, billing_provider = ? "
                "where id = ? and model_config is ? and billing_provider is ?",
                (new_config, new_billing, session_id, old_config, old_billing),
            ).rowcount
            if changed != 1:
                raise RuntimeError(f"session changed concurrently: {session_id}")
        for session_id, *_ in changes:
            raw_config, billing_provider = db.execute(
                "select model_config, billing_provider from sessions where id = ?", (session_id,)
            ).fetchone()
            parsed = json.loads(raw_config) if raw_config else {}
            if str(parsed.get("provider") or "").strip().lower() in LEGACY:
                raise RuntimeError(f"legacy provider survived: {session_id}")
            if billing_provider == "openrouter-extra":
                raise RuntimeError(f"legacy billing provider survived: {session_id}")
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()

    print(f"migrated={len(changes)} backup={backup}")
    return len(changes)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: migrate_hermes_state_provider.py <state.db>")
    migrate(Path(sys.argv[1]))
