from __future__ import annotations

from pathlib import Path
from typing import Any

from .config import ForgeConfig
from .errors import SafetyError, ValidationError
from .external_worker import run_external_worker
from .profiles import apply_load_order, read_plugin_list
from .safety import is_within, reject_symlink_chain, require_approval
from .strictjson import load
from .util import utc_now


def validate_sort_plan(path: Path) -> dict[str, Any]:
    data = load(path)
    allowed = {"schema", "generated_by", "profile", "plugins", "messages", "bash_tags", "source_hashes"}
    if not isinstance(data, dict) or set(data) - allowed:
        raise ValidationError(f"Invalid LOOT plan fields: {sorted(set(data) - allowed) if isinstance(data, dict) else 'root'}")
    if data.get("schema") != "skyrim-forge-loot-plan/1":
        raise ValidationError("Unsupported LOOT plan schema")
    plugins = data.get("plugins")
    if not isinstance(plugins, list) or not plugins or not all(isinstance(item, str) and item.strip() for item in plugins):
        raise ValidationError("LOOT plan plugins must be a non-empty string array")
    folded = [item.casefold() for item in plugins]
    if len(folded) != len(set(folded)):
        raise ValidationError("LOOT plan contains duplicate plugin names")
    return data


def analyze_via_worker(config: ForgeConfig, job_path: Path, result_path: Path, cwd: Path) -> dict[str, Any]:
    result = run_external_worker(config, job_path, result_path, cwd)
    payload = result["worker_result"]
    plan_path = payload.get("plan_path")
    if payload.get("status") == "success" and plan_path:
        result["plan"] = validate_sort_plan(Path(plan_path))
    return result


def compare_plan(current: Path, plan_path: Path) -> dict[str, Any]:
    plan = validate_sort_plan(plan_path)
    current_plugins = [line.lstrip("*+") for line in read_plugin_list(current)]
    proposed = plan["plugins"]
    current_positions = {name.casefold(): index for index, name in enumerate(current_plugins)}
    changes = []
    for index, name in enumerate(proposed):
        old = current_positions.get(name.casefold())
        if old != index:
            changes.append({"plugin": name, "from": old, "to": index})
    proposed_folded = {item.casefold() for item in proposed}
    missing = [name for name in current_plugins if name.casefold() not in proposed_folded]
    added = [name for name in proposed if name.casefold() not in current_positions]
    return {"result": "DIFFERENT" if changes or missing or added else "IDENTICAL", "changes": changes, "missing": missing, "added": added, "messages": plan.get("messages", []), "bash_tags": plan.get("bash_tags", {})}


def _authorized_target(config: ForgeConfig, target: Path) -> Path:
    if target.name.casefold() not in {"loadorder.txt", "plugins.txt"}:
        raise ValidationError("LOOT plan target must be loadorder.txt or plugins.txt")
    candidate = target.expanduser().resolve(strict=False)
    exact = [path.resolve(strict=False) for path in (config.plugins_file, config.loadorder_file) if path]
    allowed = candidate in exact
    if not allowed and config.mo2_profiles_root:
        allowed = is_within(candidate, [config.mo2_profiles_root])
    if not allowed:
        raise SafetyError("LOOT plan target is not the configured profile or an MO2 profile path")
    if not candidate.parent.is_dir():
        raise ValidationError(f"LOOT target parent does not exist: {candidate.parent}")
    reject_symlink_chain(candidate)
    return candidate


def apply_plan(config: ForgeConfig, plan_path: Path, target: Path, *, approved: bool) -> dict[str, Any]:
    require_approval(approved, "LOOT plan application")
    plan = validate_sort_plan(plan_path)
    target = _authorized_target(config, target)
    staged_dir = config.workspace_root / ".forge-plans" / utc_now().replace(":", "")
    staged_dir.mkdir(parents=True, exist_ok=False)
    staged = staged_dir / target.name
    if target.name.casefold() == "plugins.txt":
        active = {line.lstrip("*+").casefold(): line.startswith("*") for line in read_plugin_list(target)}
        text = "\n".join(("*" if active.get(name.casefold(), False) else "") + name for name in plan["plugins"]) + "\n"
    else:
        text = "\n".join(plan["plugins"]) + "\n"
    staged.write_text(text, encoding="utf-8")
    return apply_load_order(staged, target, config.workspace_root / ".forge-tool-backups" / "load-order", approved=approved)
