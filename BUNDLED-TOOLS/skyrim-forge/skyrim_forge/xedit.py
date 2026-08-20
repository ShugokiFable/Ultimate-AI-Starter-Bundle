from __future__ import annotations

import os
import re
import shutil
from pathlib import Path
from typing import Any

from .config import ForgeConfig
from .errors import SafetyError, ToolError, ValidationError
from .mo2 import run_through_mo2
from .safety import require_approval
from .strictjson import load
from .tools import resolve_tool, run_process
from .util import sha256_file, utc_now

ALLOWLISTED_SCRIPTS = {
    "check_errors": "SkyrimForgeCheckErrors.pas",
    "report_records": "SkyrimForgeReportRecords.pas",
}


def _script_source(name: str) -> Path:
    root = Path(__file__).resolve().parents[1]
    path = root / "resources" / "xedit" / name
    if not path.is_file():
        # installed package copy
        path = Path(__file__).resolve().parent / "resources" / "xedit" / name
    if not path.is_file():
        raise FileNotFoundError(f"Bundled xEdit script is missing: {name}")
    return path


def install_scripts(config: ForgeConfig, *, approved: bool) -> dict[str, Any]:
    require_approval(approved, "xEdit script installation")
    _, xedit = resolve_tool(config, "xedit")
    scripts = xedit.parent / "Edit Scripts"
    scripts.mkdir(parents=True, exist_ok=True)
    backup_dir = config.workspace_root / ".forge-tool-backups" / f"xedit-{utc_now().replace(':','')}"
    installed = []
    for filename in ALLOWLISTED_SCRIPTS.values():
        source = _script_source(filename)
        target = scripts / filename
        backup = None
        if target.is_file() and sha256_file(target) != sha256_file(source):
            backup_dir.mkdir(parents=True, exist_ok=True)
            backup = backup_dir / filename
            shutil.copy2(target, backup)
        temporary = target.with_name(f".{target.name}.forge.tmp")
        shutil.copy2(source, temporary)
        os.replace(temporary, target)
        installed.append({"path": str(target), "sha256": sha256_file(target), "backup": str(backup) if backup else None})
    return {"result": "PASS", "installed": installed}


def command_for_check(plugin: str, script_name: str = "SkyrimForgeCheckErrors.pas") -> list[str]:
    if not plugin or Path(plugin).name != plugin or Path(plugin).suffix.casefold() not in {".esp", ".esm", ".esl"}:
        raise ValidationError(f"Unsafe plugin argument for xEdit: {plugin!r}")
    return ["-sse", f"-quickedit:{plugin}", "-autoload", f'-script:{script_name}', "-autoexit", "-nobuildrefs"]


def _log_candidates(xedit: Path) -> list[Path]:
    roots = [xedit.parent]
    local = os.environ.get("LOCALAPPDATA")
    documents = Path.home() / "Documents"
    if local:
        roots.extend([Path(local) / "Skyrim Special Edition", Path(local) / "SSEEdit"])
    roots.append(documents / "My Games" / "Skyrim Special Edition")
    result = []
    for root in roots:
        if root.exists():
            result.extend(root.rglob("*.log"))
    return sorted(set(result), key=lambda p: p.as_posix().casefold())


def _snapshot_logs(paths: list[Path]) -> dict[Path, tuple[int, int]]:
    result = {}
    for path in paths:
        try:
            stat = path.stat()
            result[path] = (stat.st_mtime_ns, stat.st_size)
        except OSError:
            pass
    return result


def _changed_logs(before: dict[Path, tuple[int, int]], after: list[Path]) -> list[Path]:
    changed = []
    for path in after:
        try:
            state = (path.stat().st_mtime_ns, path.stat().st_size)
        except OSError:
            continue
        if before.get(path) != state:
            changed.append(path)
    return changed


def parse_check_output(text: str) -> dict[str, Any]:
    marker = re.search(r"SKYRIM_FORGE_CHECK_ERRORS\s+errors=(\d+)\s+records=(\d+)", text, flags=re.I)
    xedit_errors = [line.strip() for line in text.splitlines() if " -> " in line and not line.lstrip().startswith("[")]
    if marker:
        count = int(marker.group(1))
        records = int(marker.group(2))
        return {"status": "PASS" if count == 0 else "FAIL", "errors": count, "records": records, "marker_found": True, "details": xedit_errors[:1000]}
    return {"status": "INCOMPLETE", "errors": None, "records": None, "marker_found": False, "details": xedit_errors[:1000]}


def check_errors(
    config: ForgeConfig,
    plugin: str,
    *,
    cwd: Path,
    mo2_profile: str | None = None,
    require_marker: bool = True,
) -> dict[str, Any]:
    tool, xedit = resolve_tool(config, "xedit")
    script_target = xedit.parent / "Edit Scripts" / ALLOWLISTED_SCRIPTS["check_errors"]
    if not script_target.is_file() or sha256_file(script_target) != sha256_file(_script_source(script_target.name)):
        raise SafetyError("Approved Forge xEdit script is missing or differs from the bundled allowlisted copy. Run xedit-install-scripts --approve.")
    candidates = _log_candidates(xedit)
    before = _snapshot_logs(candidates)
    arguments = command_for_check(plugin, script_target.name)
    if mo2_profile:
        process = run_through_mo2(config, mo2_profile, xedit, arguments, cwd)
    else:
        process = run_process(xedit, arguments, cwd=cwd, timeout_seconds=tool.timeout_seconds)
    changed = _changed_logs(before, _log_candidates(xedit))
    combined = process["stdout"] + "\n" + process["stderr"]
    log_reports = []
    for path in changed:
        try:
            text = path.read_text(encoding="utf-8-sig", errors="replace")
        except OSError:
            continue
        combined += "\n" + text
        log_reports.append({"path": str(path), "sha256": sha256_file(path), "size": path.stat().st_size})
    parsed = parse_check_output(combined)
    if process["returncode"] != 0:
        parsed["status"] = "FAIL"
    if require_marker and not parsed["marker_found"]:
        parsed["status"] = "INCOMPLETE"
    return {
        "operation": "xedit_check_errors",
        "plugin": plugin,
        "execution": "mo2" if mo2_profile else "direct",
        "profile": mo2_profile,
        "process": process,
        "logs": log_reports,
        "check": parsed,
        "evidence": "Executed by the installed xEdit binary with a fixed allowlisted Forge script. This is not Skyrim runtime validation.",
    }


def run_approved_script(
    config: ForgeConfig,
    plugin: str,
    script_path: Path,
    approved_hashes_path: Path,
    *,
    cwd: Path,
    approved: bool,
    mo2_profile: str | None = None,
) -> dict[str, Any]:
    require_approval(approved, "approved xEdit script execution")
    approved_hashes = load(approved_hashes_path)
    if not isinstance(approved_hashes, dict) or not isinstance(approved_hashes.get("sha256"), list):
        raise ValidationError("Approved-script manifest must contain a sha256 array")
    digest = sha256_file(script_path.resolve(strict=True))
    if digest.casefold() not in {str(item).casefold() for item in approved_hashes["sha256"]}:
        raise SafetyError(f"xEdit script hash is not approved: {digest}")
    tool, xedit = resolve_tool(config, "xedit")
    target = xedit.parent / "Edit Scripts" / script_path.name
    if target.resolve(strict=False) != script_path.resolve(strict=True):
        raise SafetyError("Approved arbitrary xEdit scripts must already reside in xEdit's Edit Scripts directory")
    args = command_for_check(plugin, script_path.name)
    args.remove("-nobuildrefs")
    process = run_through_mo2(config, mo2_profile, xedit, args, cwd) if mo2_profile else run_process(xedit, args, cwd=cwd, timeout_seconds=tool.timeout_seconds)
    return {"operation": "xedit_run_approved_script", "script": str(script_path), "sha256": digest, "process": process}
