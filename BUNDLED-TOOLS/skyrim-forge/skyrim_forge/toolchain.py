from __future__ import annotations

import fnmatch
import hashlib
import json
import os
import shutil
import stat
import struct
import tempfile
import zipfile
from pathlib import Path, PurePosixPath
from typing import Any, Iterable

from .config import ForgeConfig, save_config
from .errors import ConfigurationError, SafetyError, ValidationError
from .safety import require_approval, require_read, require_within
from .util import atomic_write_text, json_dump, sha256_file, utc_now

MAX_ZIP_MEMBERS = 500_000
MAX_ZIP_TOTAL = 16 * 1024 * 1024 * 1024
MAX_ZIP_MEMBER = 4 * 1024 * 1024 * 1024


def catalog_path() -> Path:
    return Path(__file__).resolve().parent / "references" / "TOOL-CATALOG.json"


def load_catalog() -> dict[str, Any]:
    value = json.loads(catalog_path().read_text(encoding="utf-8"))
    if value.get("schema") != "skyrim-forge-tool-catalog/1":
        raise ValidationError("Unsupported Forge tool catalog schema")
    return value


def catalog_entries() -> list[dict[str, Any]]:
    return [dict(item) for item in load_catalog()["tools"]]


def catalog_entry(identifier: str) -> dict[str, Any]:
    for item in catalog_entries():
        if item["id"] == identifier or item["config_key"] == identifier:
            return item
    raise ConfigurationError(f"Unknown catalog tool: {identifier}")


def _pe_info(data: bytes) -> dict[str, Any]:
    if len(data) < 64 or data[:2] != b"MZ":
        return {"format": "not_pe"}
    offset = struct.unpack_from("<I", data, 0x3C)[0]
    if offset < 64 or offset + 24 > len(data) or data[offset:offset+4] != b"PE\x00\x00":
        return {"format": "invalid_pe"}
    machine = struct.unpack_from("<H", data, offset + 4)[0]
    magic = struct.unpack_from("<H", data, offset + 24)[0]
    return {"format": "PE32+" if magic == 0x20B else "PE32" if magic == 0x10B else f"PE-magic-0x{magic:04X}", "machine": {0x14C:"x86",0x8664:"x64",0xAA64:"arm64"}.get(machine, f"0x{machine:04X}")}


def _stream_hash_pe(stream, size: int) -> tuple[str, dict[str, Any]]:
    digest = hashlib.sha256()
    head = b""
    remaining = size
    while remaining:
        chunk = stream.read(min(1024 * 1024, remaining))
        if not chunk:
            raise ValidationError("Executable stream ended before its declared size")
        if len(head) < 1024 * 1024:
            head += chunk[: 1024 * 1024 - len(head)]
        digest.update(chunk)
        remaining -= len(chunk)
    if stream.read(1):
        raise ValidationError("Executable stream exceeded its declared size")
    return digest.hexdigest(), _pe_info(head)

def _match_entry(name: str, full_path: str) -> tuple[dict[str, Any] | None, int]:
    folded = name.casefold()
    path_folded = full_path.casefold()
    best = None
    best_score = -1
    for item in catalog_entries():
        names = {value.casefold() for value in item.get("names", [])}
        if folded not in names:
            continue
        score = int(item.get("priority", 0))
        if any(hint.casefold() in path_folded for hint in item.get("path_hints", [])):
            score += 1000
        if score > best_score:
            best, best_score = item, score
    return best, best_score


def _zip_members(archive: zipfile.ZipFile) -> list[zipfile.ZipInfo]:
    infos = archive.infolist()
    if len(infos) > MAX_ZIP_MEMBERS:
        raise SafetyError(f"ZIP contains too many members: {len(infos)}")
    total = 0
    seen: set[str] = set()
    for info in infos:
        raw = info.filename.replace("\\", "/")
        pure = PurePosixPath(raw)
        if not raw or raw.startswith("/") or pure.is_absolute() or ".." in pure.parts or (pure.parts and pure.parts[0].endswith(":")):
            raise SafetyError(f"Unsafe ZIP member path: {raw}")
        key = raw.casefold()
        if key in seen:
            raise SafetyError(f"Duplicate/case-colliding ZIP member: {raw}")
        seen.add(key)
        mode = (info.external_attr >> 16) & 0xFFFF
        if stat.S_ISLNK(mode):
            raise SafetyError(f"ZIP symlink is not allowed: {raw}")
        if info.flag_bits & 1:
            raise SafetyError(f"Encrypted ZIP member is not allowed: {raw}")
        if info.file_size > MAX_ZIP_MEMBER:
            raise SafetyError(f"ZIP member too large: {raw}")
        total += info.file_size
        if total > MAX_ZIP_TOTAL:
            raise SafetyError("ZIP uncompressed size exceeds Forge safety limit")
    bad = archive.testzip()
    if bad:
        raise ValidationError(f"ZIP CRC failure: {bad}")
    return infos


def _candidate(entry: dict[str, Any] | None, location: str, size: int, digest: str, pe: dict[str, Any], source_kind: str) -> dict[str, Any]:
    return {
        "catalog_id": entry.get("id") if entry else "unknown",
        "config_key": entry.get("config_key") if entry else "",
        "location": location,
        "filename": PurePosixPath(location.replace("\\", "/")).name,
        "size": size,
        "sha256": digest,
        "pe": pe,
        "capabilities": entry.get("capabilities", []) if entry else [],
        "automation": entry.get("automation", "unsupported") if entry else "unsupported",
        "import_mode": entry.get("import_mode", "unsupported") if entry else "unsupported",
        "license": entry.get("license", "unknown") if entry else "unknown",
        "source": entry.get("source", "unknown") if entry else "unknown",
        "public_bundle_allowed": bool(entry.get("public_bundle_allowed", False)) if entry else False,
        "source_kind": source_kind,
        "recognized": entry is not None,
    }


def scan_tool_source(source: Path) -> dict[str, Any]:
    source = source.expanduser().resolve(strict=True)
    candidates: list[dict[str, Any]] = []
    unknown: list[dict[str, Any]] = []
    if source.is_dir():
        count = 0
        for path in sorted(source.rglob("*"), key=lambda p: p.as_posix().casefold()):
            if path.is_symlink():
                raise SafetyError(f"Symlink/reparse point in tool source: {path}")
            if not path.is_file() or path.suffix.casefold() not in {".exe", ".com"}:
                continue
            count += 1
            if count > MAX_ZIP_MEMBERS:
                raise SafetyError("Tool source contains too many executable candidates")
            with path.open("rb") as stream:
                digest, pe = _stream_hash_pe(stream, path.stat().st_size)
            entry, _ = _match_entry(path.name, path.relative_to(source).as_posix())
            item = _candidate(entry, str(path), path.stat().st_size, digest, pe, "directory")
            (candidates if entry else unknown).append(item)
    elif source.suffix.casefold() == ".zip":
        with zipfile.ZipFile(source) as archive:
            infos = _zip_members(archive)
            for info in infos:
                if info.is_dir() or PurePosixPath(info.filename).suffix.casefold() not in {".exe", ".com"}:
                    continue
                with archive.open(info) as stream:
                    digest, pe = _stream_hash_pe(stream, info.file_size)
                entry, _ = _match_entry(PurePosixPath(info.filename).name, info.filename)
                item = _candidate(entry, info.filename, info.file_size, digest, pe, "zip")
                (candidates if entry else unknown).append(item)
    else:
        raise ValidationError("Tool scan source must be a directory or ZIP archive")
    candidates.sort(key=lambda item: (-int(catalog_entry(item["catalog_id"]).get("priority", 0)), item["location"].casefold()))
    return {
        "result": "PASS",
        "source": str(source),
        "recognized": candidates,
        "unknown_executables": unknown,
        "policy": load_catalog()["policy"],
        "evidence": "Static filename/path/hash/PE inspection only. No discovered executable was launched.",
    }


def _excluded(rel: str, patterns: Iterable[str]) -> bool:
    normalized = rel.replace("\\", "/")
    return any(fnmatch.fnmatch(normalized.casefold(), pattern.casefold()) or fnmatch.fnmatch(PurePosixPath(normalized).name.casefold(), pattern.casefold()) for pattern in patterns)


def _select_candidate(report: dict[str, Any], identifier: str, digest: str | None) -> dict[str, Any]:
    matches = [item for item in report["recognized"] if item["catalog_id"] == identifier]
    if digest:
        matches = [item for item in matches if item["sha256"].casefold() == digest.casefold()]
    if not matches:
        raise ValidationError(f"Tool {identifier!r} was not found in the scanned source")
    if len(matches) > 1:
        raise ValidationError(f"Multiple {identifier} candidates found; provide --sha256 to select one")
    return matches[0]


def _members_for_zip(archive: zipfile.ZipFile, candidate: dict[str, Any], entry: dict[str, Any]) -> list[zipfile.ZipInfo]:
    infos = _zip_members(archive)
    by_name = {info.filename.replace("\\", "/"): info for info in infos if not info.is_dir()}
    candidate_name = candidate["location"].replace("\\", "/")
    parent = PurePosixPath(candidate_name).parent
    mode = entry["import_mode"]
    selected: list[zipfile.ZipInfo] = []
    excludes = entry.get("exclude", [])
    for name, info in by_name.items():
        pure = PurePosixPath(name)
        try:
            rel = pure.relative_to(parent).as_posix()
        except ValueError:
            continue
        include = False
        if mode == "single":
            include = name.casefold() == candidate_name.casefold()
        elif mode == "sidecar":
            include = name.casefold() == candidate_name.casefold() or any(fnmatch.fnmatch(rel.casefold(), pattern.casefold()) for pattern in entry.get("sidecars", []))
        elif mode == "directory_runtime":
            include = not _excluded(rel, excludes)
        elif mode == "configure_only":
            raise SafetyError(f"{entry['id']} must be configured in place and cannot be copied into the tool vault")
        if include and not _excluded(rel, excludes):
            selected.append(info)
    if not any(info.filename.replace("\\", "/").casefold() == candidate_name.casefold() for info in selected):
        raise ValidationError("Selected import closure does not include the executable")
    return selected


def _copy_dir_closure(source_root: Path, executable: Path, target: Path, entry: dict[str, Any]) -> Path:
    parent = executable.parent
    mode = entry["import_mode"]
    excludes = entry.get("exclude", [])
    if mode == "configure_only":
        raise SafetyError(f"{entry['id']} must be configured in place and cannot be copied into the tool vault")
    for path in sorted(parent.rglob("*"), key=lambda p: p.as_posix().casefold()):
        if path.is_symlink():
            raise SafetyError(f"Symlink in tool runtime closure: {path}")
        if not path.is_file():
            continue
        rel = path.relative_to(parent).as_posix()
        include = mode == "directory_runtime"
        if mode == "single": include = path == executable
        elif mode == "sidecar": include = path == executable or any(fnmatch.fnmatch(rel.casefold(), pattern.casefold()) for pattern in entry.get("sidecars", []))
        if include and not _excluded(rel, excludes):
            destination = target / rel
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, destination)
    return target / executable.relative_to(parent)


def import_tool(config: ForgeConfig, source: Path, identifier: str, *, approved: bool, digest: str | None = None, configure: bool = True) -> dict[str, Any]:
    require_approval(approved, f"local import of third-party tool {identifier}")
    source = require_read(source, config.allowed_read_roots)
    entry = catalog_entry(identifier)
    if entry["import_mode"] == "configure_only":
        raise SafetyError(f"{identifier} is configure-only. Point tools.{entry['config_key']}.executable at the legal installation and pin its SHA-256.")
    report = scan_tool_source(source)
    candidate = _select_candidate(report, entry["id"], digest)
    vault = config.tool_vault_root.resolve(strict=False)
    workspace = config.workspace_root.resolve(strict=False)
    repository = Path(__file__).resolve().parents[1]
    if vault == workspace or workspace in vault.parents or vault == repository or repository in vault.parents:
        raise SafetyError("Tool vault must be outside the Forge workspace and repository to prevent accidental redistribution")
    vault.mkdir(parents=True, exist_ok=True)
    target = vault / entry["id"] / candidate["sha256"][:16]
    existing_exe = target / PurePosixPath(candidate["location"].replace("\\", "/")).name
    if target.exists():
        receipt_path = target / "TOOL-RECEIPT.json"
        if not existing_exe.is_file() or sha256_file(existing_exe).casefold() != candidate["sha256"].casefold() or not receipt_path.is_file():
            raise SafetyError(f"Existing tool-vault entry is incomplete or does not match its scanned hash: {target}")
        if configure:
            tool = config.tools[entry["config_key"]]
            tool.executable = existing_exe
            tool.sha256 = candidate["sha256"]
            tool.version = tool.version or "local-import"
            save_config(config)
        return {
            "result":"PASS", "tool":entry["id"], "executable":str(existing_exe),
            "sha256":candidate["sha256"], "vault":str(target), "configured":configure,
            "files":sum(1 for item in target.rglob("*") if item.is_file()),
            "public_bundle_allowed":False, "receipt":str(receipt_path), "reused":True,
        }
    stage = Path(tempfile.mkdtemp(prefix=f".{entry['id']}-", dir=vault))
    try:
        payload = stage / "payload"
        payload.mkdir()
        if source.is_dir():
            executable = Path(candidate["location"])
            imported_exe = _copy_dir_closure(source, executable, payload, entry)
        else:
            with zipfile.ZipFile(source) as archive:
                members = _members_for_zip(archive, candidate, entry)
                parent = PurePosixPath(candidate["location"]).parent
                for info in members:
                    pure = PurePosixPath(info.filename.replace("\\", "/"))
                    rel = pure.relative_to(parent)
                    destination = payload / Path(*rel.parts)
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    with archive.open(info) as src, destination.open("xb") as dst:
                        shutil.copyfileobj(src, dst, length=1024*1024)
                imported_exe = payload / PurePosixPath(candidate["location"]).name
        if not imported_exe.is_file() or sha256_file(imported_exe) != candidate["sha256"]:
            raise ValidationError("Imported executable hash differs from scanned candidate")
        files=[]
        for path in sorted(payload.rglob("*"), key=lambda p:p.as_posix().casefold()):
            if path.is_file():
                files.append({"path":path.relative_to(payload).as_posix(),"size":path.stat().st_size,"sha256":sha256_file(path)})
        receipt={
            "schema":"skyrim-forge-tool-receipt/1","created":utc_now(),"tool":entry["id"],"config_key":entry["config_key"],
            "source":str(source),"source_kind":candidate["source_kind"],"source_location":candidate["location"],"executable_sha256":candidate["sha256"],
            "license":entry["license"],"upstream":entry["source"],"public_bundle_allowed":False,"files":files,
            "warning":"This local import does not grant redistribution rights. Forge public releases exclude the local tool vault."
        }
        json_dump(payload/"TOOL-RECEIPT.json", receipt)
        target.parent.mkdir(parents=True, exist_ok=True)
        os.replace(payload, target)
    finally:
        shutil.rmtree(stage, ignore_errors=True)
    final_exe = target / imported_exe.relative_to(payload)
    if configure:
        tool = config.tools[entry["config_key"]]
        tool.executable = final_exe
        tool.sha256 = candidate["sha256"]
        tool.version = tool.version or "local-import"
        save_config(config)
    return {"result":"PASS","tool":entry["id"],"executable":str(final_exe),"sha256":candidate["sha256"],"vault":str(target),"configured":configure,"files":len(files),"public_bundle_allowed":False,"receipt":str(target/"TOOL-RECEIPT.json"),"reused":False}


def import_all_tools(config: ForgeConfig, source: Path, *, approved: bool, include_gui: bool = False) -> dict[str, Any]:
    require_approval(approved, "bulk local import of recognized third-party tools")
    source = require_read(source, config.allowed_read_roots)
    scan = scan_tool_source(source)
    identifiers: list[str] = []
    for candidate in scan["recognized"]:
        identifier = candidate["catalog_id"]
        if identifier not in identifiers:
            identifiers.append(identifier)
    imported=[]; skipped=[]; failed=[]
    for identifier in identifiers:
        entry=catalog_entry(identifier)
        if entry["import_mode"] == "configure_only":
            skipped.append({"tool":identifier,"reason":"configure_only"}); continue
        if entry["automation"] == "human_gate" and not include_gui:
            skipped.append({"tool":identifier,"reason":"human_gate; pass include_gui=true to import"}); continue
        matches=[item for item in scan["recognized"] if item["catalog_id"]==identifier]
        if len(matches)!=1:
            skipped.append({"tool":identifier,"reason":"multiple candidates require explicit hash selection"}); continue
        try:
            imported.append(import_tool(config,source,identifier,approved=True,digest=matches[0]["sha256"]))
        except Exception as exc:
            failed.append({"tool":identifier,"error":type(exc).__name__,"message":str(exc)})
    return {"result":"PASS" if not failed else "INCOMPLETE","source":str(source),"imported":imported,"skipped":skipped,"failed":failed,"include_gui":include_gui,"rule":"No imported binary is eligible for public Forge or mod packaging."}

def configure_existing_tool(config: ForgeConfig, identifier: str, executable: Path, *, approved: bool) -> dict[str, Any]:
    require_approval(approved, f"configuration of existing third-party tool {identifier}")
    entry = catalog_entry(identifier)
    executable = require_read(executable, config.allowed_read_roots)
    if executable.name.casefold() not in {name.casefold() for name in entry["names"]}:
        raise ValidationError(f"Executable name does not match catalog entry {identifier}: {executable.name}")
    digest = sha256_file(executable)
    tool = config.tools[entry["config_key"]]
    tool.executable = executable
    tool.sha256 = digest
    tool.version = tool.version or "configured-existing"
    save_config(config)
    return {"result":"PASS","tool":entry["id"],"executable":str(executable),"sha256":digest,"configured":True,"copied":False}


def resolve_capability(config: ForgeConfig, capability: str) -> dict[str, Any]:
    candidates=[]
    for entry in catalog_entries():
        if capability not in entry.get("capabilities", []):
            continue
        tool = config.tools.get(entry["config_key"])
        state={"tool":entry["id"],"config_key":entry["config_key"],"automation":entry["automation"],"priority":entry.get("priority",0),"configured":False,"eligible":False,"reason":"not configured"}
        if tool and tool.executable:
            state["configured"]=True; state["executable"]=str(tool.executable); state["pinned_sha256"]=tool.sha256
            expected_names = {name.casefold() for name in entry.get("names", [])}
            if not tool.executable.is_file(): state["reason"]="configured executable is missing"
            elif tool.executable.suffix.casefold() in {".exe", ".com"} and tool.executable.name.casefold() not in expected_names: state["reason"]="configured executable name does not match this catalog tool"
            elif not tool.sha256: state["reason"]="executable is not SHA-256 pinned"
            else:
                actual=sha256_file(tool.executable); state["actual_sha256"]=actual
                if actual.casefold()!=tool.sha256.casefold(): state["reason"]="hash mismatch"
                elif entry["automation"] not in {"direct","profiled","adapter","worker_contract"}: state["reason"]="catalog marks tool as human-gated"
                else: state["eligible"]=True; state["reason"]="exact capability match with valid hash pin"
        candidates.append(state)
    candidates.sort(key=lambda item:(not item["eligible"],-int(item["priority"]),item["tool"]))
    selected=next((item for item in candidates if item["eligible"]),None)
    return {"result":"PASS" if selected else "INCOMPLETE","capability":capability,"selected":selected,"candidates":candidates,"rule":load_catalog()["policy"]["selection_rule"]}


def toolchain_status(config: ForgeConfig) -> dict[str, Any]:
    configured=[]
    for entry in catalog_entries():
        tool=config.tools.get(entry["config_key"])
        if not tool or not tool.executable: continue
        actual=sha256_file(tool.executable) if tool.executable.is_file() else ""
        configured.append({"tool":entry["id"],"config_key":entry["config_key"],"executable":str(tool.executable),"exists":tool.executable.is_file(),"pinned":bool(tool.sha256),"hash_match":bool(actual and tool.sha256 and actual.casefold()==tool.sha256.casefold()),"capabilities":entry["capabilities"],"automation":entry["automation"]})
    return {"result":"PASS","tool_vault_root":str(config.tool_vault_root),"configured":configured,"catalog_count":len(catalog_entries()),"public_binary_bundling":"disabled"}
