from __future__ import annotations

from pathlib import Path
from typing import Any

from .config import ForgeConfig
from .errors import ValidationError
from .profiles import snapshot_profile
from .tools import resolve_tool, run_process


def profile_path(config: ForgeConfig, profile: str) -> Path:
    if not profile or any(c in profile for c in '/\\:*?"<>|'):
        raise ValidationError(f"Unsafe MO2 profile name: {profile!r}")
    base = config.mo2_profiles_root
    if base is None:
        mo2 = config.tools["mo2"].executable
        if mo2:
            base = mo2.parent / "profiles"
    if base is None:
        raise ValidationError("MO2 profiles root is not configured")
    return (base / profile).resolve(strict=True)


def build_mo2_command(profile: str, executable: Path, arguments: list[str], instance: str = "") -> list[str]:
    if "--multiple" in arguments:
        raise ValidationError("MO2 --multiple is intentionally prohibited")
    result: list[str] = []
    if instance:
        result.extend(["-i", instance])
    result.extend(["-p", profile, "run", str(executable), *arguments])
    return result


def run_through_mo2(config: ForgeConfig, profile: str, tool_executable: Path, arguments: list[str], cwd: Path) -> dict[str, Any]:
    tool, mo2 = resolve_tool(config, "mo2")
    return run_process(mo2, build_mo2_command(profile, tool_executable, arguments, config.mo2_instance), cwd=cwd, timeout_seconds=tool.timeout_seconds)


def capture_mo2_profile(config: ForgeConfig, profile: str, target: Path) -> dict[str, Any]:
    return snapshot_profile(profile_path(config, profile), target)
