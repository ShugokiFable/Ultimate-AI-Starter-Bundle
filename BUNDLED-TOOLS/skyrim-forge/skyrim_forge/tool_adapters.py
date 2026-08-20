from __future__ import annotations

import os
import shutil
import uuid
from pathlib import Path
from typing import Any

from .config import ForgeConfig
from .errors import ToolError, ValidationError
from .safety import require_approval, require_read, require_within
from .toolchain import resolve_capability
from .tools import resolve_tool, run_process
from .util import sha256_file


def _selected(config: ForgeConfig, capability: str, config_key: str):
    resolution=resolve_capability(config, capability)
    if not resolution.get("selected") or resolution["selected"]["config_key"] != config_key:
        raise ToolError(f"No eligible hash-pinned {config_key} tool for capability {capability}")
    return resolve_tool(config, config_key, require_pin=True)


def bsarch_info(config: ForgeConfig, archive: Path, *, dump: bool=False) -> dict[str, Any]:
    archive=require_read(archive, config.allowed_read_roots)
    if archive.suffix.casefold() not in {".bsa",".ba2"}: raise ValidationError("BSArch info requires .bsa or .ba2")
    tool,exe=_selected(config,"archive.bsa.inspect","bsarch")
    result=run_process(exe,[str(archive),"-dump" if dump else "-list"],cwd=config.workspace_root,timeout_seconds=tool.timeout_seconds)
    return {"result":"PASS" if result["returncode"]==0 else "FAIL","tool":"BSArch","archive":str(archive),"sha256":sha256_file(archive),"process":result,"evidence":"Output produced by the configured hash-pinned BSArch executable."}


def bsarch_unpack(config: ForgeConfig, archive: Path, output_dir: Path, *, approved: bool) -> dict[str, Any]:
    require_approval(approved,"BSArch archive extraction")
    archive=require_read(archive,config.allowed_read_roots)
    output=require_within(output_dir,config.workspace_root)
    if output.exists(): raise FileExistsError(output)
    tool,exe=_selected(config,"archive.bsa.unpack","bsarch")
    stage=output.parent/("."+output.name+".stage-"+uuid.uuid4().hex)
    stage.mkdir(parents=True)
    try:
        process=run_process(exe,["unpack",str(archive),str(stage),"-mt:yes"],cwd=stage,timeout_seconds=tool.timeout_seconds)
        if process["returncode"]!=0: raise ToolError(f"BSArch unpack failed: {process['stderr'] or process['stdout']}")
        files=[p for p in stage.rglob("*") if p.is_file()]
        if not files: raise ToolError("BSArch reported success but produced no files")
        os.replace(stage,output)
    finally:
        shutil.rmtree(stage,ignore_errors=True)
    return {"result":"PASS","tool":"BSArch","archive":str(archive),"output":str(output),"file_count":len(files),"process":process}


def bsarch_pack(config: ForgeConfig, source_dir: Path, output_archive: Path, *, approved: bool, compress: bool=True) -> dict[str, Any]:
    require_approval(approved,"BSArch Skyrim SE/AE archive creation")
    source=require_within(source_dir,config.workspace_root,must_exist=True)
    if not source.is_dir(): raise ValidationError("BSArch pack source must be a directory")
    output=require_within(output_archive,config.workspace_root)
    if output.suffix.casefold()!=".bsa": raise ValidationError("Skyrim SE/AE BSArch output must be .bsa")
    if output.exists(): raise FileExistsError(output)
    tool,exe=_selected(config,"archive.bsa.pack.sse","bsarch")
    stage=output.with_name("."+output.name+".stage-"+uuid.uuid4().hex)
    args=["pack",str(source),str(stage),"-sse","-mt:yes"]
    if compress: args.append("-z")
    process=run_process(exe,args,cwd=config.workspace_root,timeout_seconds=tool.timeout_seconds)
    if process["returncode"]!=0 or not stage.is_file():
        stage.unlink(missing_ok=True); raise ToolError(f"BSArch pack failed: {process['stderr'] or process['stdout']}")
    if stage.stat().st_size>min(config.max_output_bytes,2_147_000_000):
        stage.unlink(missing_ok=True); raise ToolError("Generated BSA exceeds configured/Skyrim-safe size gate")
    verify=run_process(exe,[str(stage),"-list"],cwd=config.workspace_root,timeout_seconds=tool.timeout_seconds)
    if verify["returncode"]!=0: stage.unlink(missing_ok=True); raise ToolError("Generated BSA failed BSArch reopen verification")
    os.replace(stage,output)
    return {"result":"PASS","tool":"BSArch","source":str(source),"output":str(output),"size":output.stat().st_size,"sha256":sha256_file(output),"process":process,"reopen":verify}


def deadmesh_scan(config: ForgeConfig, source: Path, output_report: Path, *, approved: bool, scan_bsa: bool=True) -> dict[str, Any]:
    require_approval(approved,"DeadMesh collision scan report write")
    source=require_read(source,config.allowed_read_roots)
    if not source.is_dir(): raise ValidationError("DeadMesh source must be a directory")
    output=require_within(output_report,config.workspace_root)
    if output.exists(): raise FileExistsError(output)
    output.parent.mkdir(parents=True,exist_ok=True)
    tool,exe=_selected(config,"mesh.collision.scan","deadmesh_cli")
    args=[str(source),"--out",str(output),"--jobs","0"]
    if not scan_bsa: args.append("--no-bsa")
    process=run_process(exe,args,cwd=output.parent,timeout_seconds=tool.timeout_seconds)
    if process["returncode"]!=0: raise ToolError(f"DeadMesh scan failed: {process['stderr'] or process['stdout']}")
    produced=[p for p in output.parent.glob(output.stem+"*") if p.is_file()]
    return {"result":"PASS","tool":"dmscan","source":str(source),"requested_report":str(output),"outputs":[{"path":str(p),"size":p.stat().st_size,"sha256":sha256_file(p)} for p in produced],"process":process,"evidence":"Static collision scan only; flagged meshes require NifSkope/in-game review."}


def champollion_decompile(config: ForgeConfig, pex: Path, output_dir: Path, *, approved: bool, recursive: bool=False) -> dict[str, Any]:
    require_approval(approved,"Champollion Papyrus decompilation")
    source=require_read(pex,config.allowed_read_roots)
    output=require_within(output_dir,config.workspace_root)
    if output.exists(): raise FileExistsError(output)
    output.mkdir(parents=True)
    tool,exe=_selected(config,"papyrus.decompile","champollion")
    args=[]
    if recursive: args.append("-r")
    args.extend(["-d","-p",str(output),str(source)])
    process=run_process(exe,args,cwd=output,timeout_seconds=tool.timeout_seconds)
    if process["returncode"]!=0: shutil.rmtree(output,ignore_errors=True); raise ToolError(f"Champollion failed: {process['stderr'] or process['stdout']}")
    files=[p for p in output.rglob("*.psc") if p.is_file()]
    return {"result":"PASS","tool":"Champollion","source":str(source),"output":str(output),"files":[str(p) for p in files],"process":process,"warning":"Decompiler output is not authoritative original source and conveys no redistribution rights."}


def synthesis_run(config: ForgeConfig, pipeline_settings: Path, output_dir: Path, *, approved: bool, data_folder: Path|None=None, load_order: Path|None=None, profile: str="", target_runtime: str="") -> dict[str, Any]:
    require_approval(approved,"Synthesis CLI pipeline execution")
    settings=require_read(pipeline_settings,config.allowed_read_roots)
    output=require_within(output_dir,config.workspace_root)
    if output.exists(): raise FileExistsError(output)
    output.mkdir(parents=True)
    tool,exe=_selected(config,"synthesis.pipeline.run","synthesis_cli")
    args=["run-pipeline","--OutputDirectory",str(output),"--PipelineSettingsPath",str(settings),"--BlockBuildingWithinMo2","true"]
    if data_folder: args.extend(["--DataFolderPath",str(require_read(data_folder,config.allowed_read_roots))])
    if load_order: args.extend(["--LoadOrderFilePath",str(require_read(load_order,config.allowed_read_roots))])
    if profile: args.extend(["--ProfileIdentifier",profile])
    if target_runtime: args.extend(["--TargetRuntime",target_runtime])
    process=run_process(exe,args,cwd=output,timeout_seconds=tool.timeout_seconds)
    if process["returncode"]!=0: raise ToolError(f"Synthesis CLI failed: {process['stderr'] or process['stdout']}")
    files=[p for p in output.rglob("*") if p.is_file()]
    return {"result":"PASS","tool":"Synthesis.Bethesda.CLI","output":str(output),"files":[{"path":str(p),"size":p.stat().st_size,"sha256":sha256_file(p)} for p in files],"process":process}
