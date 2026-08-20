from __future__ import annotations

import argparse
import ast
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib
import unittest
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]


def _single_source_version() -> str:
    """Read the product version from its one source of truth.

    This used to be a literal here, a second literal in the CI workflow, and a
    third in the Go helper. That is how the Windows CI native assertion was
    still demanding 4.2.3 while the product shipped 4.2.4. Every other copy is
    now checked against this one by `validate_version_sources`.
    """
    text = (ROOT / "skyrim_forge" / "version.py").read_text(encoding="utf-8")
    match = re.search(r'^VERSION\s*=\s*"([^"]+)"', text, re.M)
    if not match:
        raise SystemExit("skyrim_forge/version.py does not declare VERSION")
    return match.group(1)


def _pinned_go_toolchain() -> str:
    """The Go version the release profile is defined against, read from CI.

    Reproducibility here is per-Go-version, not just per-flag. CI pins
    go-version 1.23.2, so the published binaries reproduce under that toolchain
    and no other. This check used to build with whatever `go` was on PATH, which
    made its verdict depend on the machine: on a box with a newer Go it reported
    the *shipped* binaries as irreproducible, and "fixing" that by rebuilding
    locally is what broke CI. Verified: 5.1.3 rebuilt under go1.23.2 reproduces
    the published SHA-256 exactly; under go1.26.5 it does not.

    ci.yml is the single source, so this reader and the one in
    scripts/rebuild_native_helpers.py cannot drift apart.
    """
    workflow = None
    for parent in (ROOT, *ROOT.parents):
        candidate = parent / ".github" / "workflows" / "ci.yml"
        if candidate.is_file():
            workflow = candidate
            break
    if workflow is None:
        return ""
    versions = re.findall(r'go-version:\s*"([0-9]+\.[0-9]+(?:\.[0-9]+)?)"',
                          workflow.read_text(encoding="utf-8"))
    if not versions or len(set(versions)) != 1:
        return ""
    return "go" + versions[0]


VERSION = _single_source_version()
GO_TOOLCHAIN = _pinned_go_toolchain()
MODERN_PROTOCOL = "2026-07-28"
EXCLUDED = {".git", ".venv", "venv", ".go-cache", "__pycache__", "dist", "build", ".pytest_cache", "htmlcov", "REPORTS", "INSTALLATION.json"}
REPORTS = {"VALIDATION.json", "BUILD-RECEIPT.json", "MANIFEST.json", "SBOM.spdx.json", "CHECKSUMS-SHA256.txt"}
TEXT_SUFFIXES = {".py", ".go", ".md", ".txt", ".json", ".toml", ".yaml", ".yml", ".xml", ".ps1", ".bat", ".pas", ".cff"}


def sha256(data: "Path | bytes") -> str:
    digest = hashlib.sha256()
    if isinstance(data, bytes):
        digest.update(data)
    else:
        with data.open("rb") as stream:
            while chunk := stream.read(1024 * 1024): digest.update(chunk)
    return digest.hexdigest()


def run(command: list[str], *, cwd: Path = ROOT, timeout: int = 600, env: dict[str, str] | None = None) -> dict[str, Any]:
    full_env = os.environ.copy(); full_env.update(env or {})
    completed = subprocess.run(command, cwd=cwd, text=True, capture_output=True, check=False, timeout=timeout, env=full_env, shell=False)
    return {"command": command, "returncode": completed.returncode, "stdout": completed.stdout, "stderr": completed.stderr}


def repository_files() -> list[Path]:
    result = []
    for path in ROOT.rglob("*"):
        if not path.is_file() or path.is_symlink(): continue
        rel = path.relative_to(ROOT)
        if any(part in EXCLUDED or part.casefold().endswith(".egg-info") for part in rel.parts): continue
        if path.name in REPORTS: continue
        if path.suffix in {".pyc", ".pyo"}: continue
        result.append(path)
    return sorted(result, key=lambda p: p.relative_to(ROOT).as_posix().casefold())


def validate_files(errors: list[str], warnings: list[str]) -> dict[str, Any]:
    counts = {"python":0,"json":0,"toml":0,"yaml":0,"xml":0,"powershell":0,"go":0,"pascal":0}
    seen: dict[str, str] = {}
    for path in ROOT.rglob("*"):
        if path.is_symlink(): errors.append(f"symlink in repository: {path.relative_to(ROOT)}")
    for path in repository_files():
        rel = path.relative_to(ROOT).as_posix(); key = rel.casefold()
        if key in seen and seen[key] != rel: errors.append(f"case collision: {seen[key]} and {rel}")
        seen[key] = rel
        suffix = path.suffix.casefold()
        try:
            if suffix == ".py": counts["python"] += 1; ast.parse(path.read_text(encoding="utf-8-sig"), filename=rel)
            elif suffix == ".json": counts["json"] += 1; json.loads(path.read_text(encoding="utf-8-sig"), parse_constant=lambda x: (_ for _ in ()).throw(ValueError(x)))
            elif suffix == ".toml": counts["toml"] += 1; tomllib.loads(path.read_text(encoding="utf-8-sig"))
            elif suffix == ".xml": counts["xml"] += 1; ET.parse(path)
            elif suffix in {".yaml", ".yml"}:
                counts["yaml"] += 1
                try:
                    import yaml
                    yaml.safe_load(path.read_text(encoding="utf-8-sig"))
                except ImportError:
                    warnings.append("PyYAML unavailable; workflow YAML syntax parsing skipped")
            elif suffix == ".ps1": counts["powershell"] += 1
            elif suffix == ".go": counts["go"] += 1
            elif suffix == ".pas": counts["pascal"] += 1
        except Exception as exc: errors.append(f"parse failure {rel}: {exc}")
        if suffix in TEXT_SUFFIXES:
            text = path.read_text(encoding="utf-8-sig", errors="replace")
            if re.search(r"[A-Za-z]:\\Users\\(?!YOU\\|<)", text, flags=re.I): errors.append(f"private Windows path in {rel}")
            if rel != "scripts/validate_repository.py":
                if "/mnt/data/" in text or "/tmp/" in text: errors.append(f"build-environment path in {rel}")
                if "SkyrimForge.Native 2." in text or "Skyrim Forge 2." in text: errors.append(f"stale major version in {rel}")
            if suffix in {".yml", ".yaml"}:
                for match in re.finditer(r"uses:\s*([^\s#]+)", text):
                    ref = match.group(1).rsplit("@",1)[-1]
                    if not re.fullmatch(r"[0-9a-f]{40}", ref): errors.append(f"floating GitHub Action in {rel}: {match.group(1)}")
    required = [
        "README.md", "LICENSE", "SECURITY.md", "CONTRIBUTING.md", "PUBLISH-TO-GITHUB.md",
        "docs/AUTOMATION-FABRIC.md", "docs/CAPABILITY-MATRIX.md", "docs/FOMOD-ENGINEERING.md",
        "docs/FRAMEWORK-ENGINEERING.md", "docs/NATIVE-PLUGIN-ENGINEERING.md", "docs/NATIVE-SOURCE-LOCK.md",
        "docs/NEXUS-PUBLICATION.md", "docs/PAPYRUS-ENGINEERING.md", "docs/PUBLICATION-COMPLIANCE.md",
        "docs/TOOLCHAIN-BROKER.md",
        "schemas/automation-job.schema.json", "schemas/external-worker-job.schema.json", "schemas/fomod-plan.schema.json",
        "schemas/framework-plan.schema.json", "schemas/native-plugin-plan.schema.json", "schemas/nexus-publication-plan.schema.json",
        "schemas/plugin-plan.schema.json", "schemas/ui-job.schema.json",
        "references/AUTOMATION-SOURCE-LOCK.json", "references/ERROR-REGISTRY.json", "references/FOMOD-SOURCE-LOCK.json",
        "references/FRAMEWORK-SOURCE-LOCK.json", "references/NATIVE-SOURCE-LOCK.json", "references/NEXUS-POLICY-LOCK.json",
        "references/TOOL-CATALOG.json", "references/TOOLCHAIN-SOURCE-LOCK.json",
        "resources/xedit/SkyrimForgeCheckErrors.pas", "resources/xedit/SkyrimForgeReportRecords.pas",
        "skyrim_forge/capabilities.py", "skyrim_forge/framework_builder.py", "skyrim_forge/native.py", "skyrim_forge/nexus.py",
        "skyrim_forge/papyrus.py", "skyrim_forge/selftest.py", "skyrim_forge/toolchain.py", "skyrim_forge/tool_adapters.py",
        "writer/published/win-x64/SkyrimForge.Native.exe", "writer/published/linux-x64/SkyrimForge.Native",
        "skyrim_forge/bin/win-x64/SkyrimForge.Native.exe", "skyrim_forge/bin/linux-x64/SkyrimForge.Native",
    ]
    for rel in required:
        if not (ROOT / rel).is_file():
            errors.append(f"required file missing: {rel}")
    schema_names = (
        "automation-job.schema.json", "plugin-plan.schema.json", "external-worker-job.schema.json", "ui-job.schema.json",
        "fomod-plan.schema.json", "framework-plan.schema.json", "native-plugin-plan.schema.json", "nexus-publication-plan.schema.json",
    )
    for name in schema_names:
        if (ROOT / "schemas" / name).read_bytes() != (ROOT / "skyrim_forge" / "schemas" / name).read_bytes():
            errors.append(f"schema copies differ: {name}")
    for name in ("SkyrimForgeCheckErrors.pas", "SkyrimForgeReportRecords.pas"):
        if (ROOT / "resources" / "xedit" / name).read_bytes() != (ROOT / "skyrim_forge" / "resources" / "xedit" / name).read_bytes():
            errors.append(f"xEdit resource copies differ: {name}")
    reference_names = ("AUTOMATION-SOURCE-LOCK.json", "ERROR-REGISTRY.json", "FOMOD-SOURCE-LOCK.json", "FRAMEWORK-SOURCE-LOCK.json", "NATIVE-SOURCE-LOCK.json", "NEXUS-POLICY-LOCK.json", "TOOL-CATALOG.json", "TOOLCHAIN-SOURCE-LOCK.json", "PLUGIN-INVARIANTS.md")
    for name in reference_names:
        if (ROOT / "references" / name).read_bytes() != (ROOT / "skyrim_forge" / "references" / name).read_bytes():
            errors.append(f"reference copies differ: {name}")
    documentation_names = ("AUTOMATION-FABRIC.md", "CAPABILITY-MATRIX.md", "FOMOD-ENGINEERING.md", "FRAMEWORK-ENGINEERING.md", "NATIVE-PLUGIN-ENGINEERING.md", "NATIVE-SOURCE-LOCK.md", "NEXUS-PUBLICATION.md", "PAPYRUS-ENGINEERING.md", "PUBLICATION-COMPLIANCE.md", "TOOLCHAIN-BROKER.md")
    for name in documentation_names:
        if (ROOT / "docs" / name).read_bytes() != (ROOT / "skyrim_forge" / "docs" / name).read_bytes():
            errors.append(f"packaged documentation differs: {name}")
    catalog = json.loads((ROOT / "references" / "TOOL-CATALOG.json").read_text(encoding="utf-8"))
    if any(item.get("public_bundle_allowed") for item in catalog.get("tools", [])):
        errors.append("tool catalog permits public third-party executable bundling")
    forbidden_tool_names = {name.casefold() for item in catalog.get("tools", []) for name in item.get("names", [])}
    bundled_tools = [
        path.relative_to(ROOT).as_posix() for path in repository_files()
        if path.name.casefold() in forbidden_tool_names and "writer/published/" not in path.relative_to(ROOT).as_posix().casefold()
    ]
    if bundled_tools:
        errors.append("third-party catalog executables bundled in repository: " + ", ".join(bundled_tools))
    return {"file_count":len(repository_files()),"counts":counts,"third_party_binary_bundling":"disabled"}


def validate_python(errors: list[str]) -> dict[str, Any]:
    compile_result = run([sys.executable, "-m", "compileall", "-q", "skyrim_forge", "tests", "scripts"])
    tests = run([sys.executable, "-m", "unittest", "discover", "-s", "tests", "-v"], timeout=900)
    self_test = run([sys.executable, "-m", "skyrim_forge", "self-test"], timeout=300)
    if compile_result["returncode"]: errors.append("Python compileall failed")
    if tests["returncode"]: errors.append("Python unit tests failed")
    if self_test["returncode"]: errors.append("Forge built-in self-test failed")
    count_match = re.search(r"Ran (\d+) tests", tests["stderr"] + tests["stdout"])
    passed = not compile_result["returncode"] and not tests["returncode"] and not self_test["returncode"]
    return {"compile": compile_result, "tests": tests, "self_test": self_test, "test_count": int(count_match.group(1)) if count_match else None, "result": "PASS" if passed else "FAIL"}


def validate_go(errors: list[str], warnings: list[str]) -> dict[str, Any]:
    go = os.environ.get("SKYRIM_FORGE_GO") or shutil.which("go")
    if not go or not Path(go).is_file():
        warnings.append("Go unavailable; native source and reproducibility checks skipped")
        return {"result":"NOT-RUN"}
    gofmt = str(Path(go).with_name("gofmt.exe" if os.name == "nt" else "gofmt"))
    cwd = ROOT/"writer"/"native-go"
    # Pin the toolchain for every Go call, so this gate answers the same on a
    # maintainer's machine as it does in CI regardless of the installed version.
    goenv = {"GOTOOLCHAIN": GO_TOOLCHAIN} if GO_TOOLCHAIN else None
    fmt = run([gofmt,"-l","."],cwd=cwd); vet=run([go,"vet","./..."],cwd=cwd,env=goenv); tests=run([go,"test","./..."],cwd=cwd,env=goenv); race=run([go,"test","-race","./..."],cwd=cwd,env=goenv)
    if fmt["returncode"] or fmt["stdout"].strip(): errors.append("gofmt failed")
    if vet["returncode"]: errors.append("go vet failed")
    if tests["returncode"]: errors.append("go tests failed")
    if race["returncode"]: errors.append("go race tests failed")
    builds={}
    with tempfile.TemporaryDirectory() as td:
        td=Path(td)
        for target, env in {"linux":{"CGO_ENABLED":"0","GOOS":"linux","GOARCH":"amd64"},"windows":{"CGO_ENABLED":"0","GOOS":"windows","GOARCH":"amd64"}}.items():
            if GO_TOOLCHAIN: env = {**env, "GOTOOLCHAIN": GO_TOOLCHAIN}
            suffix=".exe" if target=="windows" else ""; a=td/f"{target}-a{suffix}"; b=td/f"{target}-b{suffix}"
            for output in (a,b):
                result=run([go,"build","-trimpath","-buildvcs=false","-ldflags=-s -w -buildid=","-o",str(output),"."],cwd=cwd,env=env)
                if result["returncode"]: errors.append(f"{target} native build failed")
            if a.exists() and b.exists():
                bundled=ROOT/"writer"/"published"/("win-x64" if target=="windows" else "linux-x64")/("SkyrimForge.Native.exe" if target=="windows" else "SkyrimForge.Native")
                first_hash=sha256(a); second_hash=sha256(b); bundled_hash=sha256(bundled)
                builds[target]={
                    "first":first_hash,
                    "second":second_hash,
                    "bundled":bundled_hash,
                    "buildvcs":False,
                    "first_metadata":run([go,"version","-m",str(a)],cwd=cwd),
                    "bundled_metadata":run([go,"version","-m",str(bundled)],cwd=cwd),
                    "result":"PASS" if first_hash==second_hash==bundled_hash else "FAIL",
                }
                if builds[target]["result"]!="PASS": errors.append(f"{target} native binary is not reproducible under the -buildvcs=false release profile")
    return {"format":fmt,"vet":vet,"tests":tests,"race":race,"builds":builds,"result":"PASS" if not any(x in errors for x in ["gofmt failed","go vet failed","go tests failed","go race tests failed"]) and all(x.get("result")=="PASS" for x in builds.values()) else "FAIL"}


def validate_native(errors: list[str], warnings: list[str]) -> dict[str, Any]:
    linux = ROOT / "writer" / "published" / "linux-x64" / "SkyrimForge.Native"
    windows = ROOT / "writer" / "published" / "win-x64" / "SkyrimForge.Native.exe"
    report: dict[str, Any] = {
        "hashes": {"linux": sha256(linux), "windows": sha256(windows)},
        "linux_elf": linux.read_bytes()[:4] == b"\x7fELF",
        "windows_pe": windows.read_bytes()[:2] == b"MZ" and windows.stat().st_size > 0x40,
    }
    if not report["linux_elf"]:
        errors.append("Linux native helper is not an ELF executable")
    if not report["windows_pe"]:
        errors.append("Windows native helper is not a PE executable")
    package_linux = ROOT / "skyrim_forge" / "bin" / "linux-x64" / "SkyrimForge.Native"
    package_windows = ROOT / "skyrim_forge" / "bin" / "win-x64" / "SkyrimForge.Native.exe"
    report["package_copy_hashes"] = {"linux": sha256(package_linux), "windows": sha256(package_windows)}
    report["package_copies_match"] = report["package_copy_hashes"] == report["hashes"]
    if not report["package_copies_match"]:
        errors.append("packaged native helper copies differ from writer/published binaries")
    native = windows if os.name == "nt" else linux
    platform_name = "windows" if os.name == "nt" else "linux"
    version = run([str(native), "version"])
    self_test = run([str(native), "self-test"])
    if version["returncode"] or version["stdout"].strip() != f"SkyrimForge.Native {VERSION} go":
        errors.append(f"{platform_name} native version mismatch")
    if self_test["returncode"] or "PASS" not in self_test["stdout"]:
        errors.append(f"{platform_name} native self-test failed")
    report.update({"executed_platform": platform_name, "version": version, "self_test": self_test})
    report["result"] = "PASS" if report["linux_elf"] and report["windows_pe"] and report["package_copies_match"] and version["returncode"] == self_test["returncode"] == 0 else "FAIL"
    return report


def validate_packaging(errors: list[str]) -> dict[str, Any]:
    sys.path.insert(0,str(ROOT)); import forge_build_backend
    with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
        wa=Path(a)/forge_build_backend.build_wheel(a); wb=Path(b)/forge_build_backend.build_wheel(b)
        wheel_hash=sha256(wa); wheel_equal=wheel_hash==sha256(wb); wheel_size=wa.stat().st_size
        with zipfile.ZipFile(wa) as archive: crc=archive.testzip(); members=set(archive.namelist())
        required={
            "skyrim_forge/bin/win-x64/SkyrimForge.Native.exe", "skyrim_forge/bin/linux-x64/SkyrimForge.Native",
            "skyrim_forge/capabilities.py", "skyrim_forge/framework_builder.py", "skyrim_forge/native.py",
            "skyrim_forge/nexus.py", "skyrim_forge/papyrus.py", "skyrim_forge/selftest.py",
            "skyrim_forge/toolchain.py", "skyrim_forge/tool_adapters.py",
            "skyrim_forge/resources/xedit/SkyrimForgeCheckErrors.pas",
            "skyrim_forge/schemas/fomod-plan.schema.json", "skyrim_forge/schemas/framework-plan.schema.json",
            "skyrim_forge/schemas/native-plugin-plan.schema.json", "skyrim_forge/schemas/nexus-publication-plan.schema.json",
            "skyrim_forge/docs/FOMOD-ENGINEERING.md", "skyrim_forge/docs/FRAMEWORK-ENGINEERING.md",
            "skyrim_forge/docs/NATIVE-PLUGIN-ENGINEERING.md", "skyrim_forge/docs/NEXUS-PUBLICATION.md",
            "skyrim_forge/docs/PAPYRUS-ENGINEERING.md", "skyrim_forge/docs/PUBLICATION-COMPLIANCE.md",
            "skyrim_forge/docs/TOOLCHAIN-BROKER.md",
            "skyrim_forge/references/FRAMEWORK-SOURCE-LOCK.json", "skyrim_forge/references/NATIVE-SOURCE-LOCK.json",
            "skyrim_forge/references/NEXUS-POLICY-LOCK.json",
            "skyrim_forge/references/TOOL-CATALOG.json", "skyrim_forge/references/TOOLCHAIN-SOURCE-LOCK.json",
        }
    with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
        sa=Path(a)/forge_build_backend.build_sdist(a); sb=Path(b)/forge_build_backend.build_sdist(b)
        sdist_hash=sha256(sa); sdist_equal=sdist_hash==sha256(sb); sdist_size=sa.stat().st_size
    if not wheel_equal or crc or not required.issubset(members): errors.append("wheel packaging failed")
    if not sdist_equal: errors.append("sdist packaging failed")
    return {"wheel":{"result":"PASS" if wheel_equal and not crc and required.issubset(members) else "FAIL","sha256":wheel_hash,"size":wheel_size},"sdist":{"result":"PASS" if sdist_equal else "FAIL","sha256":sdist_hash,"size":sdist_size}}


def validate_mcp(errors: list[str]) -> dict[str, Any]:
    modern_meta = {"_meta": {"io.modelcontextprotocol/protocolVersion": MODERN_PROTOCOL}}
    requests = [
        {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-11-25"}},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
        {"jsonrpc": "2.0", "id": 3, "method": "resources/list", "params": {}},
        {"jsonrpc": "2.0", "id": 4, "method": "prompts/list", "params": {}},
        # Both eras are gated here: a legacy handshake above, and below the
        # modern discovery probe, a modern list, and a rejected version.
        {"jsonrpc": "2.0", "id": 5, "method": "server/discover", "params": dict(modern_meta)},
        {"jsonrpc": "2.0", "id": 6, "method": "tools/list", "params": dict(modern_meta)},
        {"jsonrpc": "2.0", "id": 7, "method": "tools/list", "params": {"_meta": {"io.modelcontextprotocol/protocolVersion": "1900-01-01"}}},
        {"jsonrpc": "2.0", "id": 8, "method": "tools/call", "params": {"name": "forge_version", "arguments": {}, **modern_meta}},
        {"jsonrpc": "2.0", "id": 9, "method": "tools/call", "params": {"name": "forge_version", "arguments": {}}},
    ]
    completed = subprocess.run(
        [sys.executable, "-m", "skyrim_forge", "mcp"], cwd=ROOT,
        input="\n".join(json.dumps(item) for item in requests) + "\n",
        text=True, capture_output=True, timeout=30, shell=False,
        env={**os.environ, "HOME": tempfile.mkdtemp(prefix="forge-mcp-home-")},
    )
    try:
        responses = [json.loads(line) for line in completed.stdout.splitlines() if line.strip()]
        tool_count = len(responses[1]["result"]["tools"])
        resource_uris = {item["uri"] for item in responses[2]["result"]["resources"]}
        prompt_names = {item["name"] for item in responses[3]["result"]["prompts"]}
        required_resources = {
            "forge://capabilities", "forge://schemas/framework-plan", "forge://schemas/native-plugin-plan",
            "forge://schemas/nexus-publication-plan", "forge://references/framework-source-lock",
            "forge://references/native-source-lock", "forge://references/nexus-policy-lock",
            "forge://docs/toolchain-broker", "forge://references/tool-catalog",
        }
        required_prompts = {"verify_mod_release", "build_fomod_installer", "prepare_nexus_release", "build_native_plugin", "build_framework_config", "configure_verified_toolchain"}
        discover = responses[4]["result"]
        modern_tools = responses[5]["result"]
        refused = responses[6]["error"]
        modern_call = responses[7]["result"]
        legacy_call = responses[8]["result"]
        modern = (
            MODERN_PROTOCOL in discover["supportedVersions"]
            and discover["resultType"] == "complete"
            and discover["_meta"]["io.modelcontextprotocol/serverInfo"]["version"] == VERSION
            # Caching hints are mandatory on complete results for these methods.
            and modern_tools["resultType"] == "complete" and modern_tools["ttlMs"] >= 0
            and modern_tools["cacheScope"] in {"public", "private"}
            and len(modern_tools["tools"]) == tool_count
            # An unknown version must be refused, not silently downgraded.
            and refused["code"] == -32022 and MODERN_PROTOCOL in refused["data"]["supported"]
            # A legacy inventory result must not carry modern-only fields.
            and not {"resultType", "ttlMs", "cacheScope"} & set(responses[1]["result"])
            # tools/call must name its result even without `_meta`. Claude Code
            # 2026-07-28 rejects the payload otherwise.
            and modern_call["resultType"] == "complete" and modern_call.get("isError") is False
            and "ttlMs" not in modern_call
            and legacy_call["resultType"] == "complete" and legacy_call.get("isError") is False
        )
        passed = (
            completed.returncode == 0 and responses[0]["result"]["protocolVersion"] == "2025-11-25"
            and tool_count >= 50 and required_resources.issubset(resource_uris) and required_prompts.issubset(prompt_names)
            and modern
        )
    except Exception:
        tool_count = 0; resource_uris = set(); prompt_names = set(); passed = False; modern = False
    if not passed:
        errors.append("MCP handshake/inventory failed")
    return {"result": "PASS" if passed else "FAIL", "protocols": [MODERN_PROTOCOL, "2025-11-25", "2025-06-18", "2024-11-05"], "dual_era": bool(modern), "tools": tool_count, "resources": sorted(resource_uris), "prompts": sorted(prompt_names), "stderr": completed.stderr}


def _powershell_expandable_strings(text: str) -> list[tuple[int, str]]:
    strings: list[tuple[int, str]] = []
    for line_number, line in enumerate(text.splitlines(), 1):
        for match in re.finditer(r'"(?:`.|[^"\r\n])*"', line):
            strings.append((line_number, match.group(0)))
    for match in re.finditer(r'@"\r?\n(.*?)\r?\n"@', text, flags=re.S):
        line_number = text.count("\n", 0, match.start()) + 1
        strings.append((line_number, match.group(1)))
    return strings


def validate_powershell(errors: list[str], warnings: list[str]) -> dict[str, Any]:
    files=sorted(ROOT.glob("*.ps1"))+sorted((ROOT/"workers").glob("*.ps1"))
    batch_files=sorted(ROOT.glob("*.bat"))+sorted(ROOT.glob("*.cmd"))
    findings=[]
    bad_colon_reference = re.compile(r'(?<!`)\$(?!\{|\(|(?:env|global|script|local|private|using):)[A-Za-z_][A-Za-z0-9_]*:')
    for path in files:
        script_text=path.read_text(encoding="utf-8-sig")
        if re.search(r"Invoke-Expression|\biex\b",script_text,re.I): findings.append(f"dynamic expression execution: {path.name}")
        if re.search(r"SkyrimForge\.Native\s+2\.",script_text): findings.append(f"stale native version: {path.name}")
        for line_number, expandable in _powershell_expandable_strings(script_text):
            bad = bad_colon_reference.search(expandable)
            if bad:
                findings.append(f"ambiguous variable followed by colon at {path.name}:{line_number}: {bad.group(0)}")
        # Simple delimiter scan after removing strings/comments is not a parser, but catches accidental truncation.
        scrub=re.sub(r"(?m)#.*$|'(?:''|[^'])*'|\"(?:`.|[^\"])*\"","",script_text)
        for left,right in (("{","}"),("(",")")):
            if scrub.count(left)!=scrub.count(right): findings.append(f"unbalanced {left}{right}: {path.name}")
    quoted_dp0 = re.compile(r'"%~dp0"(?=\s|$)', re.I)
    for path in batch_files:
        for line_number, line in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), 1):
            stripped=line.strip()
            if quoted_dp0.search(line) and not re.match(r'(?i)^(?:cd|pushd)\b', stripped):
                findings.append(f"unsafe standalone quoted %~dp0 argument at {path.name}:{line_number}")
    if findings: errors.extend(findings)
    warnings.append("PowerShell syntax is statically screened here; Windows CI executes the shipped parser gate, the exact START-HERE batch startup path, and every skill-provider installation")
    return {"result":"PASS" if not findings else "FAIL","files":[p.name for p in files],"batch_files":[p.name for p in batch_files],"findings":findings}


def portable(value: Any) -> Any:
    if isinstance(value,dict): return {k:portable(v) for k,v in value.items()}
    if isinstance(value,list): return [portable(v) for v in value]
    if isinstance(value,str): return value.replace(str(ROOT),"<REPOSITORY_ROOT>").replace(str(Path.home()),"<HOME>").replace(tempfile.gettempdir(),"<TEMP>")
    return value


BINARY_SUFFIXES = {".exe", ".dll", ".esp", ".esm", ".esl", ".pex", ".nif", ".dds", ".zip"}


def git_normalized(path: Path) -> bytes:
    """Return the bytes git would store for this file, so manifests match CI.

    .ps1/.bat are CRLF-forced and binary files are untouched by .gitattributes;
    all other text is stored LF.  Binaries are detected by magic bytes, not
    suffix (e.g. the suffix-less Linux ELF helper).
    """
    b = path.read_bytes()
    if b"\r\n" not in b or path.suffix.lower() in {".ps1", ".bat"} | BINARY_SUFFIXES:
        return b
    if b[:4] == b"\x7fELF" or b[:2] == b"MZ" or b"\x00" in b[:1024]:
        return b
    return b.replace(b"\r\n", b"\n")


def manifest() -> dict[str, Any]:
    return {"product": "Skyrim Forge", "version": VERSION, "files": [{"path": p.relative_to(ROOT).as_posix(), "size": len(git_normalized(p)), "sha256": sha256(git_normalized(p)), "executable": bool(p.stat().st_mode & 0o111)} for p in repository_files()]}


def write_reports(report: dict[str, Any]) -> None:
    report=portable(report); (ROOT/"VALIDATION.json").write_text(json.dumps(report,indent=2,sort_keys=True)+"\n",encoding="utf-8")
    man=manifest(); (ROOT/"MANIFEST.json").write_text(json.dumps(man,indent=2,sort_keys=True)+"\n",encoding="utf-8")
    binaries=[ROOT/"writer"/"published"/"linux-x64"/"SkyrimForge.Native",ROOT/"writer"/"published"/"win-x64"/"SkyrimForge.Native.exe"]
    (ROOT/"CHECKSUMS-SHA256.txt").write_text("\n".join(f"{sha256(p)}  {p.relative_to(ROOT).as_posix()}" for p in binaries)+"\n",encoding="utf-8")
    receipt={"product":"Skyrim Forge","version":VERSION,"result":report["result"],"native":report["checks"]["native"],"go":report["checks"]["go"],"mcp":report["checks"]["mcp"],"limitations":["Windows native helper and PowerShell installers require Windows execution; GitHub CI performs that gate.","Third-party modding tools are not bundled. Their legal local installations may be discovered, imported into the private tool vault when allowed, SHA-256 pinned, and selected only for exact catalog capabilities.","No Skyrim runtime, save, visual, navmesh, animation, or gameplay validation was performed in this environment.","Nexus publication checks validate declared evidence and machine-checkable policy gates; they do not authenticate legal ownership or replace the uploader's responsibility."]}
    (ROOT/"BUILD-RECEIPT.json").write_text(json.dumps(portable(receipt),indent=2,sort_keys=True)+"\n",encoding="utf-8")
    sbom={"spdxVersion":"SPDX-2.3","dataLicense":"CC0-1.0","SPDXID":"SPDXRef-DOCUMENT","name":f"Skyrim-Forge-{VERSION}","documentNamespace":f"https://example.invalid/skyrim-forge/{VERSION}/spdx","creationInfo":{"created":"2026-07-24T00:00:00Z","creators":[f"Tool: Skyrim Forge validator {VERSION}"]},"packages":[{"name":"Skyrim Forge","SPDXID":"SPDXRef-Package","versionInfo":VERSION,"downloadLocation":"NOASSERTION","filesAnalyzed":True,"licenseConcluded":"MIT","licenseDeclared":"MIT","copyrightText":"NOASSERTION"}],"files":[{"fileName":"./"+f["path"],"SPDXID":"SPDXRef-File-"+re.sub(r"[^A-Za-z0-9.-]","-",f["path"]),"checksums":[{"algorithm":"SHA256","checksumValue":f["sha256"]}],"licenseConcluded":"NOASSERTION","licenseInfoInFiles":["NOASSERTION"],"copyrightText":"NOASSERTION"} for f in man["files"]]}
    (ROOT/"SBOM.spdx.json").write_text(json.dumps(sbom,indent=2,sort_keys=True)+"\n",encoding="utf-8")


def validate_version_sources(errors: list[str]) -> dict[str, Any]:
    """Require every declared copy of the version to match version.py.

    The 4.2.4 release shipped with Windows CI still asserting 4.2.3 because the
    version is restated in files that cannot import each other: a Go constant, a
    workflow literal, packaging metadata, and plain-text pointers. Restating is
    unavoidable; drifting silently is not.
    """
    sources: dict[str, str | None] = {"skyrim_forge/version.py": VERSION}

    def capture(rel: str, pattern: str) -> None:
        path = ROOT / rel
        if not path.exists():
            sources[rel] = None
            errors.append(f"missing version source {rel}")
            return
        found = re.search(pattern, path.read_text(encoding="utf-8"), re.M)
        sources[rel] = found.group(1) if found else None
        if sources[rel] is None:
            errors.append(f"no version declaration found in {rel}")

    capture("writer/native-go/main.go", r'^const version = "([^"]+)"')
    capture("pyproject.toml", r'^version\s*=\s*"([^"]+)"')
    capture("CURRENT.txt", r"^\s*([0-9]+\.[0-9]+\.[0-9]+)\s*$")
    capture("VERSION.txt", r"^Skyrim Forge ([0-9]+\.[0-9]+\.[0-9]+)")
    # The first line a user sees on Windows, and the first to look abandoned.
    capture("START-HERE.bat", r"^title Skyrim Forge ([0-9]+\.[0-9]+\.[0-9]+)")
    capture("README.md", r"^# Skyrim Forge ([0-9]+\.[0-9]+\.[0-9]+)")

    # The installed AI skill states the series, not the patch. Its `description`
    # is the only line an agent reads when deciding whether to load Forge at
    # all, and it was still advertising 4.2 from inside a 5.0 install on every
    # provider home.
    series = ".".join(VERSION.split(".")[:2])
    skill = ROOT / "integrations" / "skyrim-forge" / "SKILL.md"
    skill_versions = re.findall(r"Skyrim Forge ([0-9]+\.[0-9]+)", skill.read_text(encoding="utf-8")) if skill.exists() else []
    if not skill_versions:
        errors.append("no version declaration found in integrations/skyrim-forge/SKILL.md")
    stale_skill = sorted({v for v in skill_versions if v != series})
    if stale_skill:
        errors.append(f"integrations/skyrim-forge/SKILL.md advertises {stale_skill} but the product series is {series}")
    sources["integrations/skyrim-forge/SKILL.md (series)"] = series if skill_versions and not stale_skill else (stale_skill[0] if stale_skill else None)
    # The workflow must derive the expected native string rather than hardcode
    # it; a literal here is exactly what went stale before.
    #
    # Forge ships inside the Ultimate AI Starter Bundle monorepo, so the
    # workflow that runs these jobs lives at the CHECKOUT root and not in this
    # subtree -- GitHub only reads .github/workflows from the repository root.
    # Walk up to find it, and check every workflow it holds rather than one
    # remembered filename.
    workflow_dir = next(
        (parent / ".github" / "workflows"
         for parent in (ROOT, *ROOT.parents)
         if (parent / ".github" / "workflows").is_dir()),
        None,
    )
    hardcoded: list[str] = []
    # An extracted install carries no .github at all. There is no workflow to be
    # wrong about, so absence is not a finding.
    for path in sorted(workflow_dir.glob("*.yml")) if workflow_dir else []:
        found = re.findall(r"SkyrimForge\.Native [0-9]+\.[0-9]+\.[0-9]+ go", path.read_text(encoding="utf-8"))
        if found:
            errors.append(f"{path.name} hardcodes a native version string: {sorted(set(found))}")
            hardcoded += found
    # The archive builder names the release directory and must not restate it.
    archive_builder = (ROOT / "scripts" / "build_release_archive.py").read_text(encoding="utf-8")
    literal = re.findall(r'^VERSION\s*=\s*"[0-9]+\.[0-9]+\.[0-9]+"', archive_builder, re.M)
    if literal:
        errors.append("scripts/build_release_archive.py hardcodes VERSION instead of deriving it")
    hardcoded = hardcoded + literal
    # The enumerated sources above only prove that the files someone REMEMBERED
    # to list agree. 5.2.0 shipped with `forge --help`, the GUI window title and
    # the Go self-test fixture all still announcing the 4.2 series, because none
    # of those three files was on the list and nothing swept for the product
    # name in code. Enumeration cannot find what it does not enumerate, so sweep
    # every shipped source as well: a product-name literal carrying a
    # major.minor outside the prose and history files must name the current
    # series, or be interpolated from VERSION.
    stale_literals: list[str] = []
    for path in sorted(ROOT.rglob("*")):
        if path.suffix.lower() not in {".py", ".ps1", ".bat", ".go"} or not path.is_file():
            continue
        rel_parts = path.relative_to(ROOT).parts
        if any(part in {".venv", "__pycache__", ".git", "docs"} for part in rel_parts):
            continue
        for number, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            for found_series in re.findall(r"Skyrim Forge ([0-9]+\.[0-9]+)", line):
                if found_series != series:
                    stale_literals.append(f"{path.relative_to(ROOT).as_posix()}:{number} says {found_series}, series is {series}")
    if stale_literals:
        errors.append("stale product-version literal in shipped source: " + "; ".join(stale_literals))
    hardcoded = hardcoded + stale_literals
    # Entries marked "(series)" declare major.minor only and are checked above.
    mismatched = sorted(rel for rel, value in sources.items() if not rel.endswith("(series)") and value != VERSION)
    if mismatched:
        errors.append(f"version drift against skyrim_forge/version.py in {mismatched}")
    return {"result": "PASS" if not mismatched and not hardcoded else "FAIL", "version": VERSION, "sources": sources, "hardcoded_in_ci": sorted(set(hardcoded))}


VALIDATION_SCOPES = {
    "python": ("files", "powershell", "python", "packaging", "mcp", "version"),
    "full": ("files", "powershell", "python", "native", "go", "packaging", "mcp", "version"),
}


def validation_checks(scope: str) -> tuple[str, ...]:
    try:
        return VALIDATION_SCOPES[scope]
    except KeyError as exc:
        raise ValueError(f"Unknown validation scope: {scope}") from exc


def validate(scope: str = "full") -> dict[str, Any]:
    errors=[]; warnings=[]; checks={}
    selected = validation_checks(scope)
    if "files" in selected: checks["files"]=validate_files(errors,warnings)
    if "powershell" in selected: checks["powershell"]=validate_powershell(errors,warnings)
    if "python" in selected: checks["python"]=validate_python(errors)
    if "native" in selected: checks["native"]=validate_native(errors,warnings)
    if "go" in selected: checks["go"]=validate_go(errors,warnings)
    if "packaging" in selected: checks["packaging"]=validate_packaging(errors)
    if "mcp" in selected: checks["mcp"]=validate_mcp(errors)
    if "version" in selected: checks["version"]=validate_version_sources(errors)
    return {"product":"Skyrim Forge","version":VERSION,"scope":scope,"result":"PASS" if not errors else "FAIL","errors":sorted(set(errors)),"warnings":sorted(set(warnings)),"checks":checks}


def main() -> int:
    parser=argparse.ArgumentParser()
    parser.add_argument("--write-reports",action="store_true")
    parser.add_argument("--ci",action="store_true",help="Deprecated alias retained for compatibility")
    parser.add_argument("--scope",choices=sorted(VALIDATION_SCOPES),default="full")
    args=parser.parse_args()
    report=validate(args.scope)
    if args.write_reports:
        if args.scope != "full":
            parser.error("--write-reports requires --scope full")
        write_reports(report)
    print(json.dumps(portable(report),indent=2,sort_keys=True))
    return 0 if report["result"]=="PASS" else 1

if __name__=="__main__": raise SystemExit(main())
