from __future__ import annotations

import re
import uuid
from pathlib import Path
from typing import Any

from .audit import write_audit
from .config import ForgeConfig
from .creation_kit import run_ck_worker
from .errors import SafetyError, ValidationError
from .external_worker import run_external_worker
from .frameworks import lint_paths
from .framework_builder import build as build_framework
from .loot import analyze_via_worker, apply_plan, compare_plan
from .mo2 import capture_mo2_profile
from .papyrus import analyze_sources, compile_scripts
from .plugin_writer import build_plugin
from .native import audit_project as audit_native_project, build_project as build_native_project, scaffold as scaffold_native
from .nexus import audit_plan as audit_nexus_plan, build_publication_bundle as build_nexus_bundle, load_and_validate_plan as load_nexus_plan
from .release import build_release, validate_release_tree
from .safety import require_approval, require_read, require_within
from .strictjson import load
from .transaction import Transaction
from .ui_automation import run_ui_job
from .util import json_dump, safe_name, sha256_file, utc_now
from .wrye import build_bashed_patch
from .vortex import snapshot_vortex_staging
from .xedit import check_errors, install_scripts, run_approved_script

OPERATIONS = {
    "framework_lint", "release_validate", "release_build", "plugin_build",
    "xedit_install_scripts", "xedit_check_errors", "xedit_run_approved_script",
    "mo2_snapshot", "vortex_snapshot", "loot_analyze", "loot_compare", "loot_apply",
    "wrye_build_bashed_patch", "creation_kit_worker", "ui_automation",
    "papyrus_compile", "papyrus_analyze", "framework_build",
    "native_scaffold", "native_audit", "native_build",
    "nexus_audit", "nexus_build", "external_worker", "verify_release",
}
READ_ONLY = {"framework_lint", "release_validate", "xedit_check_errors", "loot_compare", "papyrus_analyze", "native_audit", "nexus_audit"}
JOB_FIELDS = {"schema", "job_id", "operation", "inputs", "options", "outputs", "description"}


def validate_job(job: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(job, dict):
        raise ValidationError("Automation job root must be an object")
    unknown = set(job) - JOB_FIELDS
    if unknown:
        raise ValidationError(f"Unknown automation job fields: {sorted(unknown)}")
    if job.get("schema") != "skyrim-forge-automation/1":
        raise ValidationError("Unsupported automation job schema")
    if job.get("operation") not in OPERATIONS:
        raise ValidationError(f"Unsupported automation operation: {job.get('operation')!r}")
    job_id = job.get("job_id")
    if not isinstance(job_id, str) or not re.fullmatch(r"[A-Za-z0-9_.-]{1,80}", job_id):
        raise ValidationError("job_id must use 1-80 safe characters")
    for name in ("inputs", "options", "outputs"):
        if not isinstance(job.get(name, {}), dict):
            raise ValidationError(f"{name} must be an object")
    return job


def _path(value: Any, name: str) -> Path:
    if not isinstance(value, str) or not value.strip():
        raise ValidationError(f"{name} path is required")
    return Path(value).expanduser()


def _read(config: ForgeConfig, value: Any, name: str) -> Path:
    return require_read(_path(value, name), config.allowed_read_roots)


def _workspace(config: ForgeConfig, value: Any, name: str) -> Path:
    return require_within(_path(value, name), config.workspace_root)


def run_job(config: ForgeConfig, job_path: Path, *, approved: bool = False, keep_transaction: bool = True) -> dict[str, Any]:
    job_path = require_read(job_path, config.allowed_read_roots)
    job = validate_job(load(job_path))
    operation = job["operation"]
    if config.require_approval_for_writes and operation not in READ_ONLY:
        require_approval(approved, operation)
    transaction = Transaction(config.workspace_root, safe_name(job["job_id"], fallback="job"))
    transaction.snapshot(job_path, "job.json")
    result: dict[str, Any]
    try:
        inputs = job.get("inputs", {})
        options = job.get("options", {})
        outputs = job.get("outputs", {})
        if operation == "framework_lint":
            paths = [_read(config, item, "framework input") for item in inputs.get("paths", [])]
            result = lint_paths(paths)
        elif operation == "release_validate":
            result = validate_release_tree(_read(config, inputs.get("root"), "release root"))
        elif operation == "release_build":
            result = build_release(
                _read(config, inputs.get("root"), "release root"),
                _workspace(config, outputs.get("archive"), "release archive"),
                config.workspace_root,
                approved=approved,
            )
        elif operation == "plugin_build":
            result = build_plugin(_read(config, inputs.get("plan"), "plugin plan"), _workspace(config, outputs.get("directory"), "plugin output directory"), approved=approved)
        elif operation == "xedit_install_scripts":
            result = install_scripts(config, approved=approved)
        elif operation == "xedit_check_errors":
            result = check_errors(config, str(inputs.get("plugin", "")), cwd=transaction.root, mo2_profile=options.get("mo2_profile"), require_marker=bool(options.get("require_marker", True)))
        elif operation == "xedit_run_approved_script":
            result = run_approved_script(
                config,
                str(inputs.get("plugin", "")),
                _read(config, inputs.get("script"), "xEdit script"),
                _read(config, inputs.get("allowlist"), "xEdit allowlist"),
                cwd=transaction.root,
                approved=approved,
                mo2_profile=options.get("mo2_profile"),
            )
        elif operation == "mo2_snapshot":
            result = capture_mo2_profile(config, str(options.get("profile", "")), transaction.output_dir / "profile")
        elif operation == "vortex_snapshot":
            result = snapshot_vortex_staging(config)
        elif operation == "loot_analyze":
            result_path = transaction.output_dir / "loot-result.json"
            result = analyze_via_worker(config, _read(config, inputs.get("worker_job"), "LOOT worker job"), result_path, transaction.root)
        elif operation == "loot_compare":
            result = compare_plan(_read(config, inputs.get("current"), "current load order"), _read(config, inputs.get("plan"), "LOOT plan"))
        elif operation == "loot_apply":
            result = apply_plan(config, _read(config, inputs.get("plan"), "LOOT plan"), _path(outputs.get("target"), "load-order target"), approved=approved)
        elif operation == "wrye_build_bashed_patch":
            result = build_bashed_patch(config, _read(config, inputs.get("worker_job"), "Wrye worker job"), transaction.output_dir / "wrye-result.json", transaction.root)
        elif operation == "creation_kit_worker":
            result = run_ck_worker(config, _read(config, inputs.get("worker_job"), "Creation Kit worker job"), transaction.output_dir / "ck-result.json", transaction.root)
        elif operation == "ui_automation":
            result = run_ui_job(config, _read(config, inputs.get("ui_job"), "UI job"), transaction.output_dir / "ui-result.json", transaction.root, approved=approved)
        elif operation == "papyrus_compile":
            result = compile_scripts(
                config,
                [_read(config, item, "Papyrus source") for item in inputs.get("scripts", [])],
                _workspace(config, outputs.get("directory"), "Papyrus output"),
                imports=[_read(config, item, "Papyrus import") for item in options.get("imports", config.papyrus_imports)],
                flags_file=_read(config, options.get("flags_file", config.papyrus_flags), "Papyrus flags"),
                approved=approved,
                optimize=bool(options.get("optimize", True)),
            )
        elif operation == "papyrus_analyze":
            result = analyze_sources(
                [_read(config, item, "Papyrus source") for item in inputs.get("scripts", [])],
                imports=[_read(config, item, "Papyrus import") for item in options.get("imports", [])],
            )
        elif operation == "framework_build":
            result = build_framework(
                _read(config, inputs.get("plan"), "framework plan"),
                _workspace(config, outputs.get("directory"), "framework output"),
                config.workspace_root,
                approved=approved,
            )
        elif operation == "native_scaffold":
            result = scaffold_native(
                _read(config, inputs.get("plan"), "native plan"),
                _workspace(config, outputs.get("directory"), "native project output"),
                config.workspace_root,
                approved=approved,
            )
        elif operation == "native_audit":
            result = audit_native_project(_read(config, inputs.get("project"), "native project"))
        elif operation == "native_build":
            result = build_native_project(
                config,
                _read(config, inputs.get("project"), "native project"),
                _workspace(config, outputs.get("directory"), "native build output"),
                approved=approved,
                configuration=str(options.get("configuration", "Release")),
            )
        elif operation == "nexus_audit":
            plan_path = _read(config, inputs.get("plan"), "Nexus publication plan")
            result = audit_nexus_plan(load_nexus_plan(plan_path), _read(config, inputs.get("root"), "release root"), evidence_base=plan_path.parent)
        elif operation == "nexus_build":
            result = build_nexus_bundle(
                _read(config, inputs.get("plan"), "Nexus publication plan"),
                _read(config, inputs.get("root"), "release root"),
                _workspace(config, outputs.get("directory"), "Nexus publication output"),
                config.workspace_root,
                approved=approved,
            )
        elif operation == "external_worker":
            result = run_external_worker(
                config,
                _read(config, inputs.get("worker_job"), "external worker job"),
                transaction.output_dir / "external-worker-result.json",
                transaction.root,
            )
        elif operation == "verify_release":
            release_root = _read(config, inputs.get("root"), "release root")
            report = validate_release_tree(release_root)
            framework = lint_paths([release_root])
            result = {"result": "PASS" if report["result"] == framework["result"] == "PASS" else "FAIL", "release": report, "frameworks": framework}
            plugin = inputs.get("plugin")
            if plugin:
                result["xedit"] = check_errors(config, str(plugin), cwd=transaction.root, mo2_profile=options.get("mo2_profile"), require_marker=True)
                if result["xedit"]["check"]["status"] != "PASS":
                    result["result"] = "FAIL"
        else:
            raise AssertionError(operation)
        status = str(result.get("result", result.get("status", "PASS"))).upper()
        receipt = transaction.receipt(status, {"operation": operation, "job": job, "result": result})
        payload = {"job_id": job["job_id"], "operation": operation, "transaction": str(transaction.root), "receipt": str(receipt), "result": result}
        write_audit(config.audit_log, operation, status, {"job_id": job["job_id"], "job_sha256": sha256_file(job_path), "transaction": str(transaction.root)})
        return payload
    except Exception as exc:
        receipt = transaction.receipt("FAIL", {"operation": operation, "job": job, "error": {"type": type(exc).__name__, "message": str(exc)}})
        write_audit(config.audit_log, operation, "FAIL", {"job_id": job["job_id"], "error": str(exc), "transaction": str(transaction.root)})
        raise
    finally:
        if not keep_transaction:
            transaction.cleanup()
