from __future__ import annotations

from dataclasses import asdict, is_dataclass
from pathlib import Path
from typing import Any

from .archive import inspect_archive
from .automation import run_job, validate_job
from .capabilities import get_capability, registry as capability_registry
from .config import ForgeConfig, configure_value, load_config, save_config
from .environment import discover_tools, doctor
from .frameworks import lint_paths, self_test as framework_self_test
from .framework_builder import build as build_framework, validate_plan as validate_framework_plan
from .fomod import build_fomod, self_test as fomod_self_test, simulate_plan, validate_fomod, validate_plan as validate_fomod_plan, write_scaffold
from .loadorder import parse_plugins_file
from .modtree import inspect_mod_directory
from .native import audit_binary as audit_native_binary, audit_project as audit_native_project, build_project as build_native_project, scaffold as scaffold_native, validate_plan as validate_native_plan
from .papyrus import analyze_sources, compile_scripts
from .nexus import audit_plan as audit_nexus_plan, build_publication_bundle, load_and_validate_plan as load_nexus_plan, policy_status as nexus_policy_status, render_mod_page, self_test as nexus_self_test, write_scaffold as write_nexus_scaffold
from .plugin_header import inspect_plugin_header
from .plugin_writer import build_plugin, validate_plan
from .records import query_records
from .release import build_release, validate_release_tree
from .strictjson import load
from .tools import tool_status
from .toolchain import scan_tool_source, import_tool, import_all_tools, configure_existing_tool, resolve_capability, toolchain_status
from .tool_adapters import bsarch_info, bsarch_unpack, bsarch_pack, deadmesh_scan, champollion_decompile, synthesis_run
from .version import VERSION
from .safety import require_approval, require_read, require_within
from .util import atomic_write_text


def plain(value: Any) -> Any:
    if is_dataclass(value):
        return {key: plain(item) for key, item in asdict(value).items()}
    if isinstance(value, dict):
        return {str(key): plain(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [plain(item) for item in value]
    if isinstance(value, Path):
        return str(value)
    return value


class ForgeService:
    def __init__(self, config: ForgeConfig | None = None):
        self.config = config or load_config()

    def _read(self, path: str) -> Path:
        return require_read(Path(path), self.config.allowed_read_roots)

    def version(self) -> dict[str, Any]:
        return {"product": "Skyrim Forge", "version": VERSION}

    def doctor(self) -> dict[str, Any]:
        return doctor(self.config)

    def config_show(self) -> dict[str, Any]:
        return plain(self.config)

    def config_set(self, key: str, value: str) -> dict[str, Any]:
        configure_value(self.config, key, value)
        return {"result": "PASS", "config": str(self.config.config_path), "key": key, "value": value}

    def discover(self) -> dict[str, Any]:
        return {"found": discover_tools(self.config)}

    def tool_status(self, name: str) -> dict[str, Any]:
        return tool_status(self.config, name)

    def plugin_info(self, path: str) -> dict[str, Any]:
        return {"header": plain(inspect_plugin_header(self._read(path))), "evidence": "Header inspection only. Semantic and runtime validation not performed."}

    def record_query(self, path: str, signature: str = "", editor_id: str = "", form_id: str = "", limit: int = 5000) -> dict[str, Any]:
        parsed = int(form_id, 0) if form_id else None
        return query_records(self._read(path), signature=signature, editor_id=editor_id, form_id=parsed, limit=limit)

    def plugins(self, path: str | None = None) -> dict[str, Any]:
        target = Path(path) if path else self.config.plugins_file
        if target is None:
            return {"result": "INCOMPLETE", "message": "plugins_file is not configured"}
        return {"path": str(target), "plugins": plain(parse_plugins_file(require_read(target, self.config.allowed_read_roots)))}

    def archive(self, path: str) -> dict[str, Any]:
        target = self._read(path)
        if target.suffix.casefold() in {".bsa", ".ba2"}:
            return bsarch_info(self.config, target)
        return plain(inspect_archive(target, seven_zip=self.config.seven_zip, allow_external=self.config.allow_external_processes))

    def tool_scan(self, source: str) -> dict[str, Any]:
        return scan_tool_source(self._read(source))

    def tool_import(self, source: str, identifier: str, approved: bool, digest: str | None = None) -> dict[str, Any]:
        return import_tool(self.config, self._read(source), identifier, approved=approved, digest=digest)

    def tool_import_all(self, source: str, approved: bool, include_gui: bool = False) -> dict[str, Any]:
        return import_all_tools(self.config, self._read(source), approved=approved, include_gui=include_gui)

    def tool_configure(self, identifier: str, executable: str, approved: bool) -> dict[str, Any]:
        return configure_existing_tool(self.config, identifier, self._read(executable), approved=approved)

    def tool_resolve(self, capability: str) -> dict[str, Any]:
        return resolve_capability(self.config, capability)

    def toolchain_status(self) -> dict[str, Any]:
        return toolchain_status(self.config)

    def bsarch_info(self, archive: str, dump: bool = False) -> dict[str, Any]:
        return bsarch_info(self.config, self._read(archive), dump=dump)

    def bsarch_unpack(self, archive: str, output_dir: str, approved: bool) -> dict[str, Any]:
        return bsarch_unpack(self.config, self._read(archive), Path(output_dir), approved=approved)

    def bsarch_pack(self, source_dir: str, output_archive: str, approved: bool, compress: bool = True) -> dict[str, Any]:
        return bsarch_pack(self.config, Path(source_dir), Path(output_archive), approved=approved, compress=compress)

    def deadmesh_scan(self, source: str, output_report: str, approved: bool, scan_bsa: bool = True) -> dict[str, Any]:
        return deadmesh_scan(self.config, self._read(source), Path(output_report), approved=approved, scan_bsa=scan_bsa)

    def champollion_decompile(self, pex: str, output_dir: str, approved: bool, recursive: bool = False) -> dict[str, Any]:
        return champollion_decompile(self.config, self._read(pex), Path(output_dir), approved=approved, recursive=recursive)

    def synthesis_run(self, pipeline_settings: str, output_dir: str, approved: bool, data_folder: str | None = None, load_order: str | None = None, profile: str = "", target_runtime: str = "") -> dict[str, Any]:
        return synthesis_run(self.config, self._read(pipeline_settings), Path(output_dir), approved=approved, data_folder=self._read(data_folder) if data_folder else None, load_order=self._read(load_order) if load_order else None, profile=profile, target_runtime=target_runtime)

    def mod_tree(self, path: str) -> dict[str, Any]:
        return plain(inspect_mod_directory(self._read(path), self.config.max_scan_files))

    def capabilities(self, identifier: str | None = None) -> dict[str, Any]:
        return get_capability(identifier) if identifier else capability_registry()

    def lint(self, paths: list[str]) -> dict[str, Any]:
        return lint_paths([self._read(path) for path in paths])

    def framework_plan_validate(self, plan: str) -> dict[str, Any]:
        return {"result": "PASS", "plan": validate_framework_plan(load(self._read(plan)))}

    def framework_build(self, plan: str, output_root: str, approved: bool) -> dict[str, Any]:
        return build_framework(self._read(plan), require_within(Path(output_root), self.config.workspace_root), self.config.workspace_root, approved=approved)

    def papyrus_analyze(self, scripts: list[str], imports: list[str] | None = None) -> dict[str, Any]:
        source_paths = [self._read(item) for item in scripts]
        import_paths = [self._read(item) for item in (imports or [])]
        return analyze_sources(source_paths, imports=import_paths)

    def papyrus_compile(self, scripts: list[str], output_dir: str, imports: list[str] | None, flags_file: str | None, approved: bool, optimize: bool = True) -> dict[str, Any]:
        source_paths = [self._read(item) for item in scripts]
        configured_imports = imports if imports else [str(path) for path in self.config.papyrus_imports]
        import_paths = [self._read(item) for item in configured_imports]
        flags_value = flags_file or (str(self.config.papyrus_flags) if self.config.papyrus_flags else "")
        if not flags_value:
            raise ValueError("Papyrus flags file is not configured; pass --flags-file or set papyrus.flags")
        return compile_scripts(
            self.config,
            source_paths,
            require_within(Path(output_dir), self.config.workspace_root),
            imports=import_paths,
            flags_file=self._read(flags_value),
            approved=approved,
            optimize=optimize,
        )

    def native_plan_validate(self, plan: str) -> dict[str, Any]:
        return {"result": "PASS", "plan": validate_native_plan(load(self._read(plan)))}

    def native_scaffold(self, plan: str, output_dir: str, approved: bool) -> dict[str, Any]:
        return scaffold_native(self._read(plan), require_within(Path(output_dir), self.config.workspace_root), self.config.workspace_root, approved=approved)

    def native_audit(self, project: str) -> dict[str, Any]:
        return audit_native_project(self._read(project))

    def native_binary_audit(self, dll: str) -> dict[str, Any]:
        return audit_native_binary(self._read(dll))

    def native_build(self, project: str, output_root: str, approved: bool, configuration: str = "Release") -> dict[str, Any]:
        return build_native_project(self.config, self._read(project), require_within(Path(output_root), self.config.workspace_root), approved=approved, configuration=configuration)

    def fomod_validate(self, root: str, strict_coverage: bool = True) -> dict[str, Any]:
        return validate_fomod(self._read(root), strict_coverage=strict_coverage)

    def fomod_plan_validate(self, plan: str, source_root: str | None = None) -> dict[str, Any]:
        source = self._read(source_root) if source_root else None
        return {"result": "PASS", "plan": validate_fomod_plan(self._read(plan), source)}

    def fomod_build(self, plan: str, source_root: str, output_root: str, approved: bool) -> dict[str, Any]:
        return build_fomod(self._read(plan), self._read(source_root), require_within(Path(output_root), self.config.workspace_root), self.config.workspace_root, approved=approved)

    def fomod_scaffold(self, source_root: str, output_plan: str, module_name: str, module_version: str, approved: bool) -> dict[str, Any]:
        return write_scaffold(self._read(source_root), require_within(Path(output_plan), self.config.workspace_root), self.config.workspace_root, module_name, module_version, approved=approved)

    def fomod_simulate(self, plan: str, selections: str | None = None, state: str | None = None, source_root: str | None = None) -> dict[str, Any]:
        selected = load(self._read(selections)) if selections else {}
        environment = load(self._read(state)) if state else {}
        source = self._read(source_root) if source_root else None
        return simulate_plan(load(self._read(plan)), selected, environment, source)

    def release_validate(self, root: str, target: str = "private", publication_plan: str | None = None) -> dict[str, Any]:
        release_root = self._read(root)
        if target == "nexus":
            if not publication_plan:
                raise ValueError("--publication-plan is required for target=nexus")
            plan_path = self._read(publication_plan)
            return audit_nexus_plan(load_nexus_plan(plan_path), release_root, evidence_base=plan_path.parent)
        return validate_release_tree(release_root)

    def release_build(self, root: str, output: str, approved: bool, target: str = "private", publication_plan: str | None = None) -> dict[str, Any]:
        release_root = self._read(root)
        if target == "nexus":
            if not publication_plan:
                raise ValueError("--publication-plan is required for target=nexus")
            return build_publication_bundle(self._read(publication_plan), release_root, Path(output), self.config.workspace_root, approved=approved)
        return build_release(release_root, require_within(Path(output), self.config.workspace_root), self.config.workspace_root, approved=approved)

    def nexus_policy_status(self) -> dict[str, Any]:
        return nexus_policy_status()

    def nexus_scaffold(self, release_root: str, output_plan: str, mod_name: str, mod_version: str, uploader: str, approved: bool) -> dict[str, Any]:
        return write_nexus_scaffold(self._read(release_root), require_within(Path(output_plan), self.config.workspace_root), mod_name, mod_version, uploader, approved=approved)

    def nexus_plan_validate(self, plan: str, release_root: str | None = None) -> dict[str, Any]:
        plan_path = self._read(plan)
        normalized = load_nexus_plan(plan_path)
        if release_root:
            return audit_nexus_plan(normalized, self._read(release_root), evidence_base=plan_path.parent)
        return {"result": "PASS", "plan": normalized, "evidence": "Plan structure only; run nexus-audit with the release tree for share-ready status."}

    def nexus_audit(self, plan: str, release_root: str) -> dict[str, Any]:
        plan_path = self._read(plan)
        return audit_nexus_plan(load_nexus_plan(plan_path), self._read(release_root), evidence_base=plan_path.parent)

    def nexus_build(self, plan: str, release_root: str, output_root: str, approved: bool) -> dict[str, Any]:
        return build_publication_bundle(self._read(plan), self._read(release_root), Path(output_root), self.config.workspace_root, approved=approved)

    def nexus_page_render(self, plan: str, output: str | None, approved: bool) -> dict[str, Any]:
        text = render_mod_page(load_nexus_plan(self._read(plan)))
        if not output:
            return {"result": "PASS", "bbcode": text}
        require_approval(approved, "Nexus mod-page BBCode write")
        target = require_within(Path(output), self.config.workspace_root)
        if target.exists():
            raise FileExistsError(target)
        atomic_write_text(target, text)
        return {"result": "PASS", "output": str(target)}

    def plan_validate(self, path: str) -> dict[str, Any]:
        return {"result": "PASS", "plan": validate_plan(load(self._read(path)))}

    def plugin_build(self, path: str, output_dir: str, approved: bool) -> dict[str, Any]:
        return build_plugin(self._read(path), require_within(Path(output_dir), self.config.workspace_root), approved=approved)

    def automation_validate(self, path: str) -> dict[str, Any]:
        return {"result": "PASS", "job": validate_job(load(self._read(path)))}

    def automation_run(self, path: str, approved: bool, keep_transaction: bool = True) -> dict[str, Any]:
        return run_job(self.config, Path(path), approved=approved, keep_transaction=keep_transaction)

    def self_test(self) -> dict[str, Any]:
        from .selftest import run_all
        return run_all()
