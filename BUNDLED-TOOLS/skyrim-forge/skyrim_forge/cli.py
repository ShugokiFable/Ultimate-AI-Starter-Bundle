from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any

from .errors import ForgeError
from .service import ForgeService
from .strictjson import dumps
from .version import VERSION


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(prog="forge", description=f"Skyrim Forge {VERSION} Automation Fabric and publication gate")
    root.add_argument("--config", help="Alternate config.toml")
    root.add_argument("--version", action="version", version=f"Skyrim Forge {VERSION}")
    sub = root.add_subparsers(dest="command", required=True)
    sub.add_parser("version")
    sub.add_parser("doctor")
    sub.add_parser("self-test")
    sub.add_parser("config-show")
    setp = sub.add_parser("config-set"); setp.add_argument("key"); setp.add_argument("value")
    sub.add_parser("discover-tools")
    status = sub.add_parser("tool-status"); status.add_argument("name")
    ts = sub.add_parser("tool-scan"); ts.add_argument("source")
    ti = sub.add_parser("tool-import"); ti.add_argument("source"); ti.add_argument("identifier"); ti.add_argument("--sha256"); ti.add_argument("--approve", action="store_true")
    tia = sub.add_parser("tool-import-all"); tia.add_argument("source"); tia.add_argument("--include-gui", action="store_true"); tia.add_argument("--approve", action="store_true")
    tc = sub.add_parser("tool-configure"); tc.add_argument("identifier"); tc.add_argument("executable"); tc.add_argument("--approve", action="store_true")
    tr = sub.add_parser("tool-resolve"); tr.add_argument("capability")
    sub.add_parser("toolchain-status")
    bai = sub.add_parser("bsarch-info"); bai.add_argument("archive"); bai.add_argument("--dump", action="store_true")
    bau = sub.add_parser("bsarch-unpack"); bau.add_argument("archive"); bau.add_argument("output_dir"); bau.add_argument("--approve", action="store_true")
    bap = sub.add_parser("bsarch-pack"); bap.add_argument("source_dir"); bap.add_argument("output_archive"); bap.add_argument("--no-compress", action="store_true"); bap.add_argument("--approve", action="store_true")
    dms = sub.add_parser("deadmesh-scan"); dms.add_argument("source"); dms.add_argument("output_report"); dms.add_argument("--no-bsa", action="store_true"); dms.add_argument("--approve", action="store_true")
    ch = sub.add_parser("champollion-decompile"); ch.add_argument("pex"); ch.add_argument("output_dir"); ch.add_argument("--recursive", action="store_true"); ch.add_argument("--approve", action="store_true")
    sy = sub.add_parser("synthesis-run"); sy.add_argument("pipeline_settings"); sy.add_argument("output_dir"); sy.add_argument("--data-folder"); sy.add_argument("--load-order"); sy.add_argument("--profile", default=""); sy.add_argument("--target-runtime", default=""); sy.add_argument("--approve", action="store_true")
    info = sub.add_parser("plugin-info"); info.add_argument("path")
    query = sub.add_parser("record-query"); query.add_argument("path"); query.add_argument("--signature", default=""); query.add_argument("--editor-id", default=""); query.add_argument("--form-id", default=""); query.add_argument("--limit", type=int, default=5000)
    plugins = sub.add_parser("plugins"); plugins.add_argument("path", nargs="?")
    archive = sub.add_parser("archive-info"); archive.add_argument("path")
    tree = sub.add_parser("mod-tree"); tree.add_argument("path")
    caps = sub.add_parser("capabilities"); caps.add_argument("identifier", nargs="?")
    lint = sub.add_parser("lint"); lint.add_argument("paths", nargs="+")
    fwpv = sub.add_parser("framework-plan-validate"); fwpv.add_argument("plan")
    fwb = sub.add_parser("framework-build"); fwb.add_argument("plan"); fwb.add_argument("output_root"); fwb.add_argument("--approve", action="store_true")
    pa = sub.add_parser("papyrus-analyze"); pa.add_argument("scripts", nargs="+"); pa.add_argument("--import", dest="imports", action="append", default=[])
    pc = sub.add_parser("papyrus-compile"); pc.add_argument("scripts", nargs="+"); pc.add_argument("output_dir"); pc.add_argument("--import", dest="imports", action="append", default=[]); pc.add_argument("--flags-file"); pc.add_argument("--no-optimize", action="store_true"); pc.add_argument("--approve", action="store_true")
    np = sub.add_parser("native-plan-validate"); np.add_argument("plan")
    nsf = sub.add_parser("native-scaffold"); nsf.add_argument("plan"); nsf.add_argument("output_dir"); nsf.add_argument("--approve", action="store_true")
    npa = sub.add_parser("native-audit"); npa.add_argument("project")
    nba = sub.add_parser("native-binary-audit"); nba.add_argument("dll")
    nbuild = sub.add_parser("native-build"); nbuild.add_argument("project"); nbuild.add_argument("output_root"); nbuild.add_argument("--configuration", choices=["Debug","RelWithDebInfo","Release","MinSizeRel"], default="Release"); nbuild.add_argument("--approve", action="store_true")
    fv = sub.add_parser("fomod-validate"); fv.add_argument("root"); fv.add_argument("--allow-unreferenced", action="store_true")
    fpv = sub.add_parser("fomod-plan-validate"); fpv.add_argument("plan"); fpv.add_argument("--source-root")
    fb = sub.add_parser("fomod-build"); fb.add_argument("plan"); fb.add_argument("source_root"); fb.add_argument("output_root"); fb.add_argument("--approve", action="store_true")
    fs = sub.add_parser("fomod-scaffold"); fs.add_argument("source_root"); fs.add_argument("output_plan"); fs.add_argument("--module-name", required=True); fs.add_argument("--module-version", default="1.0.0"); fs.add_argument("--approve", action="store_true")
    fsm = sub.add_parser("fomod-simulate"); fsm.add_argument("plan"); fsm.add_argument("--selections"); fsm.add_argument("--state"); fsm.add_argument("--source-root")
    rv = sub.add_parser("release-validate"); rv.add_argument("root"); rv.add_argument("--target", choices=["private", "nexus"], default="private"); rv.add_argument("--publication-plan")
    rb = sub.add_parser("release-build"); rb.add_argument("root"); rb.add_argument("output"); rb.add_argument("--target", choices=["private", "nexus"], default="private"); rb.add_argument("--publication-plan"); rb.add_argument("--approve", action="store_true")
    sub.add_parser("nexus-policy-status")
    ns = sub.add_parser("nexus-scaffold"); ns.add_argument("release_root"); ns.add_argument("output_plan"); ns.add_argument("--mod-name", required=True); ns.add_argument("--mod-version", required=True); ns.add_argument("--uploader", required=True); ns.add_argument("--approve", action="store_true")
    npv = sub.add_parser("nexus-plan-validate"); npv.add_argument("plan"); npv.add_argument("--release-root")
    na = sub.add_parser("nexus-audit"); na.add_argument("plan"); na.add_argument("release_root")
    nb = sub.add_parser("nexus-build"); nb.add_argument("plan"); nb.add_argument("release_root"); nb.add_argument("output_root"); nb.add_argument("--approve", action="store_true")
    npage = sub.add_parser("nexus-page-render"); npage.add_argument("plan"); npage.add_argument("--output"); npage.add_argument("--approve", action="store_true")
    pv = sub.add_parser("plugin-plan-validate"); pv.add_argument("path")
    pb = sub.add_parser("plugin-build"); pb.add_argument("path"); pb.add_argument("output_dir"); pb.add_argument("--approve", action="store_true")
    av = sub.add_parser("automation-validate"); av.add_argument("path")
    ar = sub.add_parser("automation-run"); ar.add_argument("path"); ar.add_argument("--approve", action="store_true"); ar.add_argument("--discard-transaction", action="store_true")
    mcp = sub.add_parser("mcp")
    gui = sub.add_parser("gui")
    return root


def _exit_code(value: Any) -> int:
    if isinstance(value, dict):
        status = str(value.get("result", value.get("status", ""))).upper()
        if status in {"FAIL", "BLOCKED", "INVALID", "INCOMPLETE", "CANCELLED"}:
            return 2
    return 0


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    if args.command == "version":
        print(dumps({"product": "Skyrim Forge", "version": VERSION}))
        return 0
    if args.command == "self-test":
        from .selftest import run_all
        value = run_all()
        print(dumps(value))
        return _exit_code(value)
    if args.command == "mcp":
        from .mcp_server import serve
        serve(args.config)
        return 0
    if args.command == "gui":
        from .gui import run_gui
        run_gui(args.config)
        return 0
    from .config import load_config
    service = ForgeService(load_config(args.config))
    try:
        match args.command:
            case "doctor": value = service.doctor()
            case "config-show": value = service.config_show()
            case "config-set": value = service.config_set(args.key, args.value)
            case "discover-tools": value = service.discover()
            case "tool-status": value = service.tool_status(args.name)
            case "tool-scan": value = service.tool_scan(args.source)
            case "tool-import": value = service.tool_import(args.source, args.identifier, args.approve, args.sha256)
            case "tool-import-all": value = service.tool_import_all(args.source, args.approve, args.include_gui)
            case "tool-configure": value = service.tool_configure(args.identifier, args.executable, args.approve)
            case "tool-resolve": value = service.tool_resolve(args.capability)
            case "toolchain-status": value = service.toolchain_status()
            case "bsarch-info": value = service.bsarch_info(args.archive, args.dump)
            case "bsarch-unpack": value = service.bsarch_unpack(args.archive, args.output_dir, args.approve)
            case "bsarch-pack": value = service.bsarch_pack(args.source_dir, args.output_archive, args.approve, not args.no_compress)
            case "deadmesh-scan": value = service.deadmesh_scan(args.source, args.output_report, args.approve, not args.no_bsa)
            case "champollion-decompile": value = service.champollion_decompile(args.pex, args.output_dir, args.approve, args.recursive)
            case "synthesis-run": value = service.synthesis_run(args.pipeline_settings, args.output_dir, args.approve, args.data_folder, args.load_order, args.profile, args.target_runtime)
            case "plugin-info": value = service.plugin_info(args.path)
            case "record-query": value = service.record_query(args.path, args.signature, args.editor_id, args.form_id, args.limit)
            case "plugins": value = service.plugins(args.path)
            case "archive-info": value = service.archive(args.path)
            case "mod-tree": value = service.mod_tree(args.path)
            case "capabilities": value = service.capabilities(args.identifier)
            case "lint": value = service.lint(args.paths)
            case "framework-plan-validate": value = service.framework_plan_validate(args.plan)
            case "framework-build": value = service.framework_build(args.plan, args.output_root, args.approve)
            case "papyrus-analyze": value = service.papyrus_analyze(args.scripts, args.imports)
            case "papyrus-compile": value = service.papyrus_compile(args.scripts, args.output_dir, args.imports, args.flags_file, args.approve, not args.no_optimize)
            case "native-plan-validate": value = service.native_plan_validate(args.plan)
            case "native-scaffold": value = service.native_scaffold(args.plan, args.output_dir, args.approve)
            case "native-audit": value = service.native_audit(args.project)
            case "native-binary-audit": value = service.native_binary_audit(args.dll)
            case "native-build": value = service.native_build(args.project, args.output_root, args.approve, args.configuration)
            case "fomod-validate": value = service.fomod_validate(args.root, not args.allow_unreferenced)
            case "fomod-plan-validate": value = service.fomod_plan_validate(args.plan, args.source_root)
            case "fomod-build": value = service.fomod_build(args.plan, args.source_root, args.output_root, args.approve)
            case "fomod-scaffold": value = service.fomod_scaffold(args.source_root, args.output_plan, args.module_name, args.module_version, args.approve)
            case "fomod-simulate": value = service.fomod_simulate(args.plan, args.selections, args.state, args.source_root)
            case "release-validate": value = service.release_validate(args.root, args.target, args.publication_plan)
            case "release-build": value = service.release_build(args.root, args.output, args.approve, args.target, args.publication_plan)
            case "nexus-policy-status": value = service.nexus_policy_status()
            case "nexus-scaffold": value = service.nexus_scaffold(args.release_root, args.output_plan, args.mod_name, args.mod_version, args.uploader, args.approve)
            case "nexus-plan-validate": value = service.nexus_plan_validate(args.plan, args.release_root)
            case "nexus-audit": value = service.nexus_audit(args.plan, args.release_root)
            case "nexus-build": value = service.nexus_build(args.plan, args.release_root, args.output_root, args.approve)
            case "nexus-page-render": value = service.nexus_page_render(args.plan, args.output, args.approve)
            case "plugin-plan-validate": value = service.plan_validate(args.path)
            case "plugin-build": value = service.plugin_build(args.path, args.output_dir, args.approve)
            case "automation-validate": value = service.automation_validate(args.path)
            case "automation-run": value = service.automation_run(args.path, args.approve, not args.discard_transaction)
            case _: raise AssertionError(args.command)
        print(dumps(value))
        return _exit_code(value)
    except Exception as exc:
        print(dumps({"result": "FAIL", "error": type(exc).__name__, "message": str(exc)}), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
