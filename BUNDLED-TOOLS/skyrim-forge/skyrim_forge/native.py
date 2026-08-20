from __future__ import annotations

import json
import os
import re
import shutil
import struct
import tempfile
from pathlib import Path
from typing import Any

from .config import ForgeConfig
from .errors import SafetyError, ToolError, ValidationError
from .safety import require_approval, require_within
from .strictjson import load
from .tools import resolve_tool, run_process
from .util import atomic_write_text, json_dump, safe_name, sha256_file, validate_semver

PLAN_SCHEMA = "skyrim-forge-native-plugin-plan/1"
STRATEGIES = {"address_library", "signature_scanning", "explicit_runtimes"}
PROJECT_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_]{0,63}$")
SOURCE_LOCK = {
    "commonlibsse_package": "commonlibsse-ng",
    "vcpkg_registry": "https://gitlab.com/colorglass/vcpkg-colorglass",
    "vcpkg_registry_baseline": "6fb127f7d425ae3cf3fab0f79005d907c885c0d8",
    "vcpkg_default_registry": "https://github.com/microsoft/vcpkg.git",
    "vcpkg_default_baseline": "cc288af760054fa489574bd8e22d05aa8fa01e5c",
    "reviewed": "2026-07-24",
}


def _obj(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValidationError(f"{label} must be an object")
    return value


def _text(value: Any, label: str, *, required: bool = True) -> str:
    if value is None and not required:
        return ""
    if not isinstance(value, str):
        raise ValidationError(f"{label} must be a string")
    text = value.strip()
    if required and not text:
        raise ValidationError(f"{label} must not be empty")
    if any(char in text for char in "\r\n\x00"):
        raise ValidationError(f"{label} contains an unsafe character")
    return text


def validate_plan(data: Any) -> dict[str, Any]:
    root = _obj(data, "native plan")
    allowed = {"schema", "project", "display_name", "version", "author", "email", "description", "minimum_skse_version", "runtime_strategy", "compatible_runtimes", "struct_dependent", "log_name", "namespace"}
    unknown = set(root) - allowed
    if unknown:
        raise ValidationError(f"Unknown native plan fields: {sorted(unknown)}")
    if root.get("schema") != PLAN_SCHEMA:
        raise ValidationError(f"native plan schema must be {PLAN_SCHEMA!r}")
    project = _text(root.get("project"), "project")
    if not PROJECT_RE.fullmatch(project):
        raise ValidationError("project must be a C/C++ identifier using 1-64 ASCII letters, digits, or underscores")
    version = _text(root.get("version"), "version")
    validate_semver(version)
    minimum_skse = _text(root.get("minimum_skse_version", "0.0.0"), "minimum_skse_version")
    validate_semver(minimum_skse)
    strategy = _text(root.get("runtime_strategy", "address_library"), "runtime_strategy")
    if strategy not in STRATEGIES:
        raise ValidationError(f"runtime_strategy must be one of {sorted(STRATEGIES)}")
    runtimes = root.get("compatible_runtimes", [])
    if not isinstance(runtimes, list) or not all(isinstance(item, str) for item in runtimes):
        raise ValidationError("compatible_runtimes must be a string array")
    runtimes = [item.strip() for item in runtimes]
    for item in runtimes:
        validate_semver(item)
    if len(runtimes) != len(set(runtimes)):
        raise ValidationError("compatible_runtimes contains duplicates")
    if strategy == "explicit_runtimes" and not runtimes:
        raise ValidationError("explicit_runtimes strategy requires compatible_runtimes")
    if strategy != "explicit_runtimes" and runtimes:
        raise ValidationError("compatible_runtimes may only be used with explicit_runtimes")
    namespace = _text(root.get("namespace", project), "namespace")
    if not PROJECT_RE.fullmatch(namespace):
        raise ValidationError("namespace must be a C++ identifier")
    return {
        "schema": PLAN_SCHEMA,
        "project": project,
        "display_name": _text(root.get("display_name", project), "display_name"),
        "version": version,
        "author": _text(root.get("author"), "author"),
        "email": _text(root.get("email", ""), "email", required=False),
        "description": _text(root.get("description"), "description"),
        "minimum_skse_version": minimum_skse,
        "runtime_strategy": strategy,
        "compatible_runtimes": runtimes,
        "struct_dependent": bool(root.get("struct_dependent", False)),
        "log_name": safe_name(_text(root.get("log_name", project), "log_name"), fallback=project),
        "namespace": namespace,
    }


def _cmake(plan: dict[str, Any]) -> str:
    opts = []
    strategy = plan["runtime_strategy"]
    if strategy == "address_library":
        opts.append("USE_ADDRESS_LIBRARY")
    elif strategy == "signature_scanning":
        opts.append("USE_SIGNATURE_SCANNING")
    else:
        opts.append("COMPATIBLE_RUNTIMES " + " ".join(plan["compatible_runtimes"]))
    if plan["struct_dependent"]:
        opts.append("STRUCT_DEPENDENT")
    opts.extend([
        f'NAME "{plan["display_name"]}"',
        f'AUTHOR "{plan["author"]}"',
        f'EMAIL "{plan["email"]}"',
        f'VERSION "{plan["version"]}"',
        f'MINIMUM_SKSE_VERSION "{plan["minimum_skse_version"]}"',
        "SOURCES src/plugin.cpp",
    ])
    options_block = "\n    ".join(opts)
    return f'''cmake_minimum_required(VERSION 3.24)
project({plan["project"]} VERSION {plan["version"]} LANGUAGES CXX)

find_package(CommonLibSSE CONFIG REQUIRED)

add_commonlibsse_plugin(${{PROJECT_NAME}}
    {options_block}
)
target_compile_features(${{PROJECT_NAME}} PRIVATE cxx_std_23)
target_precompile_headers(${{PROJECT_NAME}} PRIVATE src/PCH.h)

if(NOT DEFINED FORGE_OUTPUT_ROOT OR FORGE_OUTPUT_ROOT STREQUAL "")
    message(FATAL_ERROR "FORGE_OUTPUT_ROOT must point to a Forge workspace staging directory")
endif()
set(FORGE_PLUGIN_DIR "${{FORGE_OUTPUT_ROOT}}/SKSE/Plugins")
add_custom_command(TARGET ${{PROJECT_NAME}} POST_BUILD
    COMMAND "${{CMAKE_COMMAND}}" -E make_directory "${{FORGE_PLUGIN_DIR}}"
    COMMAND "${{CMAKE_COMMAND}}" -E copy_if_different "$<TARGET_FILE:${{PROJECT_NAME}}>" "${{FORGE_PLUGIN_DIR}}/$<TARGET_FILE_NAME:${{PROJECT_NAME}}>"
    VERBATIM
)
'''


def _plugin_cpp(plan: dict[str, Any]) -> str:
    namespace = plan["namespace"]
    return f'''#include "PCH.h"

namespace {namespace}
{{
    void OnMessage(SKSE::MessagingInterface::Message* message)
    {{
        if (message == nullptr) {{
            return;
        }}
        if (message->type == SKSE::MessagingInterface::kDataLoaded) {{
            logger::info("Data loaded. Register data-dependent hooks and event sinks here.");
        }}
    }}
}}

SKSEPluginLoad(const SKSE::LoadInterface* skse)
{{
    SKSE::Init(skse);
    auto path = logger::log_directory();
    if (!path) {{
        return false;
    }}
    *path /= "{plan['log_name']}.log";
    auto sink = std::make_shared<spdlog::sinks::basic_file_sink_mt>(path->string(), true);
    auto log = std::make_shared<spdlog::logger>("global log", std::move(sink));
    spdlog::set_default_logger(std::move(log));
    spdlog::set_pattern("[%Y-%m-%d %H:%M:%S.%e] [%l] %v");
    spdlog::set_level(spdlog::level::info);
    spdlog::flush_on(spdlog::level::info);

    auto* messaging = SKSE::GetMessagingInterface();
    if (messaging == nullptr || !messaging->RegisterListener({namespace}::OnMessage)) {{
        logger::critical("Failed to register SKSE messaging listener");
        return false;
    }}
    logger::info("{plan['display_name']} {plan['version']} loaded");
    return true;
}}
'''


def _pch() -> str:
    return '''#pragma once

#include "RE/Skyrim.h"
#include "SKSE/SKSE.h"

#include <spdlog/sinks/basic_file_sink.h>
'''


def scaffold(plan_path: Path, output_dir: Path, workspace_root: Path, *, approved: bool) -> dict[str, Any]:
    require_approval(approved, "native plugin project scaffold")
    plan = validate_plan(load(plan_path))
    target = require_within(output_dir, workspace_root)
    if target.exists():
        raise SafetyError(f"Refusing to overwrite native project: {target}")
    target.parent.mkdir(parents=True, exist_ok=True)
    transaction = Path(tempfile.mkdtemp(prefix=f".{target.name}.native-", dir=target.parent))
    staged = transaction / target.name
    try:
        (staged / "src").mkdir(parents=True)
        atomic_write_text(staged / "CMakeLists.txt", _cmake(plan))
        atomic_write_text(staged / "src" / "PCH.h", _pch())
        atomic_write_text(staged / "src" / "plugin.cpp", _plugin_cpp(plan))
        json_dump(staged / "native-plan.normalized.json", plan)
        json_dump(staged / "vcpkg.json", {"$schema": "https://raw.githubusercontent.com/microsoft/vcpkg-tool/main/docs/vcpkg.schema.json", "name": plan["project"].replace("_", "-").casefold(), "version-string": plan["version"], "dependencies": [SOURCE_LOCK["commonlibsse_package"]]})
        json_dump(staged / "vcpkg-configuration.json", {"default-registry": {"kind": "git", "repository": SOURCE_LOCK["vcpkg_default_registry"], "baseline": SOURCE_LOCK["vcpkg_default_baseline"]}, "registries": [{"kind": "git", "repository": SOURCE_LOCK["vcpkg_registry"], "baseline": SOURCE_LOCK["vcpkg_registry_baseline"], "packages": [SOURCE_LOCK["commonlibsse_package"]]}]})
        atomic_write_text(staged / ".gitignore", "build/\nout/\n.vs/\n*.user\n")
        atomic_write_text(staged / "README.md", f'''# {plan["display_name"]}

{plan["description"]}

This CommonLibSSE-NG project was generated by Skyrim Forge. Build output is refused unless `FORGE_OUTPUT_ROOT` points to a staging directory. Do not deploy directly to Skyrim Data from a build script.

Runtime strategy: `{plan["runtime_strategy"]}`. Struct-dependent: `{str(plan["struct_dependent"]).lower()}`.
''')
        report = audit_project(staged)
        if report["result"] != "PASS":
            raise ValidationError(f"Generated native project failed audit: {report['errors']}")
        os.replace(staged, target)
    finally:
        shutil.rmtree(transaction, ignore_errors=True)
    return {"result": "PASS", "output": str(target), "plan": plan, "audit": report, "source_lock": SOURCE_LOCK}


def audit_project(project_root: Path) -> dict[str, Any]:
    root = project_root.resolve(strict=True)
    errors: list[str] = []
    warnings: list[str] = []
    required = [root / "CMakeLists.txt", root / "vcpkg.json", root / "vcpkg-configuration.json", root / "src" / "plugin.cpp", root / "src" / "PCH.h"]
    for path in required:
        if not path.is_file():
            errors.append(f"Missing native project file: {path.relative_to(root)}")
    if errors:
        return {"result": "FAIL", "errors": errors, "warnings": warnings}
    cmake = (root / "CMakeLists.txt").read_text(encoding="utf-8-sig")
    cpp = (root / "src" / "plugin.cpp").read_text(encoding="utf-8-sig")
    if "add_commonlibsse_plugin" not in cmake:
        errors.append("CMake project does not use add_commonlibsse_plugin")
    strategies = sum(token in cmake for token in ("USE_ADDRESS_LIBRARY", "USE_SIGNATURE_SCANNING", "COMPATIBLE_RUNTIMES"))
    if strategies != 1:
        errors.append("CMake project must choose exactly one runtime compatibility strategy")
    if "FORGE_OUTPUT_ROOT" not in cmake or "FATAL_ERROR" not in cmake:
        errors.append("CMake project does not enforce Forge staging output")
    if re.search(r"(?:Skyrim Special Edition|\\Data|/Data)[\\/\"]", cmake, flags=re.I):
        errors.append("CMake project appears to deploy directly to a live game Data path")
    for token in ("SKSEPluginLoad", "SKSE::Init", "GetMessagingInterface", "RegisterListener", "kDataLoaded"):
        if token not in cpp:
            errors.append(f"Native entry point is missing required lifecycle token: {token}")
    if re.search(r"REL::Relocation\s*<[^>]+>\s*\([^)]*0x[0-9A-Fa-f]+", cpp):
        warnings.append("Source contains an apparent hardcoded relocation address; verify the runtime strategy and signature/address-library evidence")
    if "std::thread" in cpp or "CreateThread" in cpp:
        warnings.append("Source starts a thread; review shutdown, synchronization, and game-thread API access")
    if "SKSE::AllocTrampoline" in cpp and "SKSE::GetTrampoline" not in cpp:
        warnings.append("Trampoline allocation is present without an obvious trampoline acquisition")
    return {"result": "PASS" if not errors else "FAIL", "root": str(root), "errors": errors, "warnings": warnings, "evidence": "Static CommonLibSSE-NG project audit. Compilation and Skyrim runtime testing remain separate."}


def audit_binary(path: Path) -> dict[str, Any]:
    target = path.resolve(strict=True)
    data = target.read_bytes()
    errors: list[str] = []
    if len(data) < 0x100 or data[:2] != b"MZ":
        raise ValidationError(f"Not a Windows PE binary: {target}")
    pe_offset = struct.unpack_from("<I", data, 0x3C)[0]
    if pe_offset + 24 > len(data) or data[pe_offset:pe_offset + 4] != b"PE\0\0":
        raise ValidationError(f"Invalid PE header: {target}")
    machine, sections, timestamp, _, _, opt_size, characteristics = struct.unpack_from("<HHIIIHH", data, pe_offset + 4)
    optional_magic = struct.unpack_from("<H", data, pe_offset + 24)[0] if pe_offset + 26 <= len(data) else 0
    if machine != 0x8664:
        errors.append(f"Expected x86-64 machine 0x8664, got 0x{machine:04X}")
    if optional_magic != 0x20B:
        errors.append(f"Expected PE32+ optional header, got 0x{optional_magic:04X}")
    if not characteristics & 0x2000:
        errors.append("PE file is not marked as a DLL")
    imports: list[str] = []
    tool = shutil.which("objdump") or shutil.which("llvm-objdump")
    if tool:
        process = run_process(Path(tool), ["-p", str(target)], cwd=target.parent, timeout_seconds=120)
        if process["returncode"] == 0:
            imports = sorted(set(re.findall(r"DLL Name:\s*([^\r\n]+)", process["stdout"], flags=re.I)))
    return {"result": "PASS" if not errors else "FAIL", "path": str(target), "sha256": sha256_file(target), "size": len(data), "machine": f"0x{machine:04X}", "architecture": "PE32+" if optional_magic == 0x20B else "unknown", "sections": sections, "timestamp": timestamp, "dll_characteristic": bool(characteristics & 0x2000), "imports": imports, "errors": errors, "limitations": ["Static PE inspection does not prove SKSE loadability or coexistence with other native plugins."]}


def build_project(config: ForgeConfig, project_root: Path, output_root: Path, *, approved: bool, configuration: str = "Release") -> dict[str, Any]:
    require_approval(approved, "native plugin build")
    project = project_root.resolve(strict=True)
    audit = audit_project(project)
    if audit["result"] != "PASS":
        raise ValidationError(f"Native project audit failed: {audit['errors']}")
    if configuration not in {"Debug", "RelWithDebInfo", "Release", "MinSizeRel"}:
        raise ValidationError("Unsupported CMake build configuration")
    _, cmake = resolve_tool(config, "cmake", require_pin=True)
    _, vcpkg = resolve_tool(config, "vcpkg", require_pin=True)
    output = require_within(output_root, config.workspace_root)
    if output.exists() and any(output.iterdir()):
        raise SafetyError(f"Refusing non-empty native build output: {output}")
    output.mkdir(parents=True, exist_ok=True)
    build_dir = output / "build"
    stage_dir = output / "stage"
    toolchain = vcpkg.parent / "scripts" / "buildsystems" / "vcpkg.cmake"
    if not toolchain.is_file():
        raise FileNotFoundError(f"vcpkg toolchain file not found beside configured vcpkg: {toolchain}")
    arguments = ["-S", str(project), "-B", str(build_dir), f"-DCMAKE_TOOLCHAIN_FILE={toolchain}", f"-DFORGE_OUTPUT_ROOT={stage_dir}"]
    ninja = config.tools.get("ninja")
    if ninja and ninja.executable:
        _, ninja_path = resolve_tool(config, "ninja", require_pin=True)
        arguments.extend(["-G", "Ninja", f"-DCMAKE_MAKE_PROGRAM={ninja_path}", f"-DCMAKE_BUILD_TYPE={configuration}"])
    configure = run_process(cmake, arguments, cwd=output, timeout_seconds=config.tools["cmake"].timeout_seconds)
    if configure["returncode"] != 0:
        raise ToolError("CMake configure failed")
    build = run_process(cmake, ["--build", str(build_dir), "--config", configuration], cwd=output, timeout_seconds=config.tools["cmake"].timeout_seconds)
    if build["returncode"] != 0:
        raise ToolError("CMake build failed")
    dlls = sorted((stage_dir / "SKSE" / "Plugins").glob("*.dll")) if (stage_dir / "SKSE" / "Plugins").is_dir() else []
    if len(dlls) != 1:
        raise ToolError(f"Expected exactly one staged SKSE DLL; found {len(dlls)}")
    binary = audit_binary(dlls[0])
    if binary["result"] != "PASS":
        raise ToolError(f"Built DLL failed PE audit: {binary['errors']}")
    return {"result": "PASS", "project_audit": audit, "configure": configure, "build": build, "stage": str(stage_dir), "binary": binary}


def self_test() -> dict[str, Any]:
    plan = {
        "schema": PLAN_SCHEMA, "project": "ForgeSelfTest", "display_name": "Forge Self Test",
        "version": "1.0.0", "author": "Skyrim Forge", "email": "", "description": "Native scaffold self-test",
        "minimum_skse_version": "0.0.0", "runtime_strategy": "address_library",
        "compatible_runtimes": [], "struct_dependent": False,
    }
    with tempfile.TemporaryDirectory() as td:
        root = Path(td); work = root / "work"; work.mkdir(); plan_path = root / "plan.json"; json_dump(plan_path, plan)
        try:
            report = scaffold(plan_path, work / "project", work, approved=True)
            passed = report["result"] == "PASS" and audit_project(work / "project")["result"] == "PASS"
        except Exception as exc:
            return {"result": "FAIL", "error": str(exc)}
    return {"result": "PASS" if passed else "FAIL", "assertions": {"scaffold_and_audit": passed}}
