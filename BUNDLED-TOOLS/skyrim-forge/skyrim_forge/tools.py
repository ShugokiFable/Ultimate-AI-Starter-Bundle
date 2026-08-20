from __future__ import annotations

import os
import re
import shutil
import subprocess
import struct
import sys
from dataclasses import asdict
from pathlib import Path
from typing import Any

from .config import ForgeConfig, ToolConfig
from .errors import ConfigurationError, SafetyError, ToolError
from .util import sha256_file, truncate


def tool_status(config: ForgeConfig, name: str) -> dict[str, Any]:
    if name not in config.tools:
        raise ConfigurationError(f"Unknown tool: {name}")
    tool = config.tools[name]
    executable = tool.executable
    status: dict[str, Any] = {
        "name": name,
        "configured": executable is not None,
        "executable": str(executable or ""),
        "worker": str(tool.worker or ""),
        "pinned_sha256": tool.sha256,
        "pinned_version": tool.version,
        "pinned_worker_sha256": tool.worker_sha256,
        "timeout_seconds": tool.timeout_seconds,
    }
    if executable:
        status["exists"] = executable.is_file()
        if executable.is_file():
            status["sha256"] = sha256_file(executable)
            status["hash_match"] = not tool.sha256 or status["sha256"].casefold() == tool.sha256.casefold()
    if tool.worker:
        status["worker_exists"] = tool.worker.is_file()
        if tool.worker.is_file():
            status["worker_sha256"] = sha256_file(tool.worker)
            status["worker_hash_match"] = not tool.worker_sha256 or status["worker_sha256"].casefold() == tool.worker_sha256.casefold()
    return status


def resolve_tool(config: ForgeConfig, name: str, *, worker: bool = False, require_pin: bool = False) -> tuple[ToolConfig, Path]:
    if not config.allow_external_processes:
        raise SafetyError("External process execution is disabled in Forge configuration")
    if name not in config.tools:
        raise ConfigurationError(f"Unknown tool: {name}")
    tool = config.tools[name]
    path = tool.worker if worker else tool.executable
    if path is None:
        raise ConfigurationError(f"Tool path is not configured: {name}{'.worker' if worker else ''}")
    if not path.is_file():
        raise FileNotFoundError(path)
    pin = tool.worker_sha256 if worker else tool.sha256
    if require_pin and not pin:
        raise SafetyError(f"A pinned SHA-256 is required for {name}{'.worker' if worker else ''}")
    if pin:
        actual = sha256_file(path)
        if actual.casefold() != pin.casefold():
            raise SafetyError(f"Executable hash mismatch for {name}: expected {pin}, got {actual}")
    return tool, path.resolve(strict=True)


WINDOWS_PE_MACHINES = {0x014C: "x86", 0x8664: "x64", 0xAA64: "arm64"}


def _validate_windows_executable(path: Path) -> dict[str, Any]:
    try:
        with path.open("rb") as stream:
            header = stream.read(64)
            if len(header) < 64 or header[:2] != b"MZ":
                raise ToolError(f"Configured .exe is not a Windows PE executable: {path}")
            pe_offset = struct.unpack_from("<I", header, 0x3C)[0]
            if pe_offset < 64 or pe_offset > 64 * 1024 * 1024:
                raise ToolError(f"Configured .exe has an invalid PE header offset: {path}")
            stream.seek(pe_offset)
            signature = stream.read(6)
    except OSError as exc:
        raise ToolError(f"Could not inspect configured executable: {path}: {exc}") from exc
    if len(signature) != 6 or signature[:4] != b"PE\x00\x00":
        raise ToolError(f"Configured .exe is not a valid Windows PE executable: {path}")
    machine = struct.unpack_from("<H", signature, 4)[0]
    if machine not in WINDOWS_PE_MACHINES:
        raise ToolError(f"Unsupported Windows PE machine 0x{machine:04X}: {path}")
    return {"machine": WINDOWS_PE_MACHINES[machine], "machine_code": f"0x{machine:04X}"}


def build_process_command(executable: Path, arguments: list[str]) -> tuple[list[str], str]:
    executable = executable.resolve(strict=True)
    suffix = executable.suffix.casefold()
    if suffix in {".py", ".pyw"}:
        return [sys.executable, str(executable), *arguments], "python"
    if suffix == ".ps1":
        powershell = shutil.which("pwsh") or shutil.which("powershell")
        if not powershell:
            raise ToolError(f"PowerShell is required to run worker script: {executable}")
        return [powershell, "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", str(executable), *arguments], "powershell"
    if os.name == "nt" and suffix == ".exe":
        _validate_windows_executable(executable)
    elif os.name != "nt" and suffix == ".exe":
        raise ToolError(f"Windows executable cannot run directly on this platform: {executable}")
    return [str(executable), *arguments], "direct"


def run_process(
    executable: Path,
    arguments: list[str],
    *,
    cwd: Path,
    timeout_seconds: int,
    environment: dict[str, str] | None = None,
    stdin_text: str | None = None,
) -> dict[str, Any]:
    if not isinstance(arguments, list) or not all(isinstance(item, str) for item in arguments):
        raise SafetyError("External process arguments must be a list of strings")
    if any("\x00" in item for item in arguments):
        raise SafetyError("NUL byte in process argument")
    cwd.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    if environment:
        env.update({str(k): str(v) for k, v in environment.items()})
    command, launcher = build_process_command(executable, arguments)
    startupinfo = None
    creationflags = 0
    if os.name == "nt":
        startupinfo = subprocess.STARTUPINFO()
        startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startupinfo.wShowWindow = 0
        creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    try:
        completed = subprocess.run(
            command,
            cwd=cwd,
            env=env,
            input=stdin_text,
            text=True,
            capture_output=True,
            shell=False,
            timeout=timeout_seconds,
            check=False,
            startupinfo=startupinfo,
            creationflags=creationflags,
        )
    except subprocess.TimeoutExpired as exc:
        raise ToolError(f"Process timed out after {timeout_seconds}s: {executable.name}") from exc
    except OSError as exc:
        raise ToolError(f"Could not launch {executable}: {exc}") from exc
    return {
        "command": command,
        "launcher": launcher,
        "cwd": str(cwd),
        "returncode": completed.returncode,
        "stdout": truncate(completed.stdout),
        "stderr": truncate(completed.stderr),
    }


def discover_executable(names: list[str], roots: list[Path]) -> Path | None:
    for name in names:
        found = shutil.which(name)
        if found:
            return Path(found).resolve()
    for root in roots:
        if not root or not root.exists():
            continue
        for name in names:
            candidates = list(root.rglob(name))
            if candidates:
                return sorted(candidates, key=lambda p: (len(p.parts), p.as_posix().casefold()))[0].resolve()
    return None
