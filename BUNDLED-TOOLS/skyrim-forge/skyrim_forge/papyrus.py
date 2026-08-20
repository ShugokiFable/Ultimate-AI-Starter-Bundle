from __future__ import annotations

import os
import re
import shutil
import tempfile
from pathlib import Path
from typing import Any

from .config import ForgeConfig
from .errors import ToolError, ValidationError
from .safety import require_approval, require_within
from .tools import resolve_tool, run_process
from .util import json_dump, sha256_file

SCRIPT_RE = re.compile(r"(?im)^\s*ScriptName\s+([A-Za-z_][A-Za-z0-9_]*)(?:\s+extends\s+([A-Za-z_][A-Za-z0-9_]*))?")
EVENT_RE = re.compile(r"(?im)^\s*Event\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(")
FUNCTION_RE = re.compile(r"(?im)^\s*(?:[A-Za-z_][A-Za-z0-9_]*(?:\[\])?\s+)?Function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(")


def _source_info(path: Path) -> dict[str, Any]:
    source = path.resolve(strict=True)
    if source.suffix.casefold() != ".psc":
        raise ValidationError(f"Papyrus source must be .psc: {source}")
    text = source.read_text(encoding="utf-8-sig", errors="replace")
    declaration = SCRIPT_RE.search(text)
    errors: list[dict[str, Any]] = []
    warnings: list[dict[str, Any]] = []
    if declaration is None:
        errors.append({"line": 1, "code": "PAPYRUS-NO-SCRIPTNAME", "message": "Source has no ScriptName declaration"})
        identity = source.stem
        parent = ""
    else:
        identity = declaration.group(1)
        parent = declaration.group(2) or ""
        line = text.count("\n", 0, declaration.start()) + 1
        if identity.casefold() != source.stem.casefold():
            errors.append({"line": line, "code": "PAPYRUS-FILENAME-MISMATCH", "message": f"ScriptName {identity!r} does not match filename {source.name!r}"})
        elif identity != source.stem:
            warnings.append({"line": line, "code": "PAPYRUS-CASE-MISMATCH", "message": "ScriptName and filename differ only by case; normalize them for portable archives"})
    lower = text.casefold()
    if "registerforupdate(" in lower and "unregisterforupdate(" not in lower:
        warnings.append({"line": 0, "code": "PAPYRUS-UPDATE-NO-UNREGISTER", "message": "RegisterForUpdate is present without an obvious UnregisterForUpdate; verify lifecycle cleanup"})
    if "registerforupdategametime(" in lower and "unregisterforupdategametime(" not in lower:
        warnings.append({"line": 0, "code": "PAPYRUS-GAMETIME-NO-UNREGISTER", "message": "RegisterForUpdateGameTime is present without an obvious unregister call"})
    for match in re.finditer(r"(?i)RegisterFor(?:Single)?Update\s*\(\s*(0(?:\.\d+)?|1(?:\.0+)?)\s*\)", text):
        try: interval=float(match.group(1))
        except ValueError: continue
        if interval < 1.0:
            warnings.append({"line": text.count("\n",0,match.start())+1,"code":"PAPYRUS-HIGH-FREQUENCY-UPDATE","message":f"Update interval {interval:g}s is below one second; confirm this polling rate is necessary"})
    if re.search(r"(?is)Event\s+OnUpdate\s*\([^)]*\).*?\bWhile\b", text):
        warnings.append({"line": 0, "code": "PAPYRUS-LOOP-IN-UPDATE", "message": "OnUpdate contains a While loop; verify bounded work and yielding"})
    for match in re.finditer(r"(?i)Utility\.Wait\s*\(\s*0(?:\.0+)?\s*\)", text):
        warnings.append({"line": text.count("\n",0,match.start())+1,"code":"PAPYRUS-ZERO-WAIT","message":"Utility.Wait(0) is not a reliable scheduling or optimization primitive"})
    player_calls = len(re.findall(r"(?i)Game\.GetPlayer\s*\(", text))
    if player_calls >= 5:
        warnings.append({"line":0,"code":"PAPYRUS-REPEATED-GETPLAYER","message":f"Game.GetPlayer() appears {player_calls} times; consider caching locally where semantics permit"})
    expensive = re.compile(r"(?i)(FindAllReferencesOfType|GetAllMatchingForms|GetNumItems|GetNthForm)")
    for event in re.finditer(r"(?is)Event\s+(OnUpdate|OnHit|OnObjectEquipped|OnCellAttach)\s*\([^)]*\)(.*?)EndEvent", text):
        if expensive.search(event.group(2)):
            warnings.append({"line":text.count("\n",0,event.start())+1,"code":"PAPYRUS-HOT-EVENT-SCAN","message":f"{event.group(1)} contains a broad/iterative API call; profile before publishing"})
    return {
        "path": str(source), "filename": source.name, "script_name": identity, "parent": parent,
        "sha256": sha256_file(source), "events": sorted(set(EVENT_RE.findall(text)), key=str.casefold),
        "functions": sorted(set(FUNCTION_RE.findall(text)), key=str.casefold),
        "errors": errors, "warnings": warnings,
    }


def _import_index(imports: list[Path]) -> tuple[dict[str, list[dict[str, str]]], list[dict[str, Any]]]:
    index: dict[str, list[dict[str, str]]] = {}
    for order, directory in enumerate(imports):
        root = directory.resolve(strict=True)
        if not root.is_dir():
            raise FileNotFoundError(root)
        for path in root.rglob("*.psc"):
            if not path.is_file(): continue
            key=path.stem.casefold()
            index.setdefault(key,[]).append({"path":str(path),"sha256":sha256_file(path),"import_order":str(order)})
    conflicts=[]
    for name, items in sorted(index.items()):
        hashes={item["sha256"] for item in items}
        if len(hashes)>1:
            conflicts.append({"script":name,"severity":"warning","message":"Multiple import roots provide different source content; the first import directory wins","candidates":items})
    return index,conflicts


def analyze_sources(scripts: list[Path], *, imports: list[Path] | None = None) -> dict[str, Any]:
    reports=[_source_info(path) for path in scripts]
    errors=[]; warnings=[]
    by_name: dict[str,list[dict[str,Any]]]={}
    for report in reports:
        by_name.setdefault(report["script_name"].casefold(),[]).append(report)
        errors.extend({"script":report["script_name"],**item} for item in report["errors"])
        warnings.extend({"script":report["script_name"],**item} for item in report["warnings"])
    for name, items in by_name.items():
        if len(items)>1:
            errors.append({"script":name,"line":0,"code":"PAPYRUS-DUPLICATE-IDENTITY","message":f"Multiple source files declare the same case-insensitive ScriptName: {[item['path'] for item in items]}"})
    graph={report["script_name"].casefold():report["parent"].casefold() for report in reports if report["parent"]}
    for start in graph:
        seen=[]; current=start
        while current in graph:
            if current in seen:
                cycle=seen[seen.index(current):]+[current]
                errors.append({"script":start,"line":0,"code":"PAPYRUS-INHERITANCE-CYCLE","message":"Inheritance cycle: "+" -> ".join(cycle)})
                break
            seen.append(current); current=graph[current]
    import_conflicts=[]; import_count=0
    if imports is not None:
        index,import_conflicts=_import_index(imports); import_count=sum(len(items) for items in index.values()); warnings.extend(import_conflicts)
    return {"result":"PASS" if not errors else "FAIL","scripts":reports,"script_count":len(reports),"errors":errors,"warnings":warnings,"inheritance_graph":graph,"import_source_count":import_count,"import_conflicts":import_conflicts,"evidence":"Static Papyrus identity/dependency analysis. Performance findings are heuristics requiring review and runtime profiling."}


def compile_scripts(config: ForgeConfig, scripts: list[Path], output_dir: Path, *, imports: list[Path], flags_file: Path, approved: bool, optimize: bool = True) -> dict[str, Any]:
    require_approval(approved, "Papyrus compilation")
    tool, compiler = resolve_tool(config, "papyrus_compiler", require_pin=True)
    output_dir = require_within(output_dir, config.workspace_root)
    if not flags_file.is_file(): raise FileNotFoundError(flags_file)
    analysis=analyze_sources(scripts,imports=imports)
    if analysis["result"] != "PASS": raise ValidationError(f"Papyrus source analysis failed: {analysis['errors']}")
    output_dir.parent.mkdir(parents=True,exist_ok=True)
    transaction=Path(tempfile.mkdtemp(prefix=f".{output_dir.name}.papyrus-",dir=output_dir.parent))
    stage=transaction/"compiled"; stage.mkdir()
    results=[]
    try:
        for source_raw in scripts:
            source=source_raw.resolve(strict=True); target=stage/f"{source.stem}.pex"
            args=[str(source),f"-f={flags_file}",f"-i={';'.join(str(path.resolve(strict=True)) for path in imports)}",f"-o={stage}","-quiet"]
            if optimize: args.append("-optimize")
            process=run_process(compiler,args,cwd=source.parent,timeout_seconds=tool.timeout_seconds)
            if process["returncode"] != 0 or not target.is_file() or target.stat().st_size == 0:
                raise ToolError(f"Papyrus compilation failed or produced no PEX for {source.name}")
            results.append({"source":str(source),"source_sha256":sha256_file(source),"process":process,"staged_output":str(target),"sha256":sha256_file(target),"size":target.stat().st_size})
        backups=transaction/"backups"; backups.mkdir(); output_dir.mkdir(parents=True,exist_ok=True); installed=[]
        try:
            for item in results:
                staged=Path(item["staged_output"]); target=output_dir/staged.name; backup=backups/staged.name
                if target.exists(): shutil.copy2(target,backup)
                temp=output_dir/("."+target.name+".stage")
                shutil.copy2(staged,temp); os.replace(temp,target); installed.append(target)
                item["output"]=str(target); item["fresh"]=True
        except Exception:
            for target in installed:
                backup=backups/target.name
                if backup.exists(): shutil.copy2(backup,target)
                else: target.unlink(missing_ok=True)
            raise
        manifest={"result":"PASS","optimized":optimize,"compiler":str(compiler),"compiler_sha256":sha256_file(compiler),"flags":str(flags_file),"flags_sha256":sha256_file(flags_file),"imports":[str(path.resolve(strict=True)) for path in imports],"analysis":analysis,"compiled":results}
        json_dump(output_dir/"PAPYRUS-BUILD-MANIFEST.json",manifest)
        return manifest
    finally:
        shutil.rmtree(transaction,ignore_errors=True)


def self_test() -> dict[str, Any]:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        good = root / "Good.psc"; good.write_text("ScriptName Good extends Quest\nEvent OnInit()\nEndEvent\n", encoding="utf-8")
        hot = root / "Hot.psc"; hot.write_text("ScriptName Hot extends Quest\nEvent OnUpdate()\nWhile True\nUtility.Wait(0)\nEndWhile\nEndEvent\n", encoding="utf-8")
        good_report = analyze_sources([good])
        hot_report = analyze_sources([hot])
        assertions = {"valid_identity": good_report["result"] == "PASS", "hot_event_warning": any(item["code"] == "PAPYRUS-LOOP-IN-UPDATE" for item in hot_report["warnings"])}
        return {"result": "PASS" if all(assertions.values()) else "FAIL", "assertions": assertions}
