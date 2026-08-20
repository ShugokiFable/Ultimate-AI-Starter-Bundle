from __future__ import annotations

import os
import shutil
import tomllib
from dataclasses import dataclass, field, fields
from pathlib import Path
from typing import Any

from .errors import ConfigurationError
from .util import atomic_write_text

DEFAULT_HOME = Path.home() / ".skyrim-forge"
DEFAULT_CONFIG = DEFAULT_HOME / "config.toml"


@dataclass(slots=True)
class ToolConfig:
    executable: Path | None = None
    sha256: str = ""
    version: str = ""
    timeout_seconds: int = 900
    worker: Path | None = None
    worker_sha256: str = ""


@dataclass(slots=True)
class ForgeConfig:
    config_path: Path
    workspace_root: Path
    audit_log: Path
    skyrim_data: Path | None = None
    plugins_file: Path | None = None
    loadorder_file: Path | None = None
    mo2_profiles_root: Path | None = None
    mo2_instance: str = ""
    vortex_staging: Path | None = None
    vortex_downloads: Path | None = None
    tools_root: Path | None = None
    tool_vault_root: Path = field(default_factory=lambda: DEFAULT_HOME / "tool-vault")
    seven_zip: Path | None = None
    allow_external_processes: bool = False
    require_approval_for_writes: bool = True
    allow_ui_automation: bool = False
    max_scan_files: int = 250_000
    max_output_bytes: int = 2_000_000_000
    extra_read_roots: list[Path] = field(default_factory=list)
    tools: dict[str, ToolConfig] = field(default_factory=dict)
    papyrus_flags: Path | None = None
    papyrus_imports: list[Path] = field(default_factory=list)
    load_warnings: list[str] = field(default_factory=list)

    @property
    def allowed_read_roots(self) -> list[Path]:
        candidates: list[Path | None] = [
            self.workspace_root,
            Path.home() / "Downloads",
            Path(__file__).resolve().parents[1],
            self.skyrim_data,
            self.plugins_file.parent if self.plugins_file else None,
            self.loadorder_file.parent if self.loadorder_file else None,
            self.mo2_profiles_root,
            self.vortex_staging,
            self.vortex_downloads,
            self.tools_root,
            self.tool_vault_root,
            self.seven_zip.parent if self.seven_zip else None,
            self.papyrus_flags.parent if self.papyrus_flags else None,
            *self.papyrus_imports,
            *self.extra_read_roots,
        ]
        for tool in self.tools.values():
            if tool.executable:
                candidates.append(tool.executable.parent)
            if tool.worker:
                candidates.append(tool.worker.parent)
        return [path for path in candidates if path is not None]


def _path(value: Any, base: Path) -> Path | None:
    if value is None or not str(value).strip():
        return None
    expanded = Path(os.path.expandvars(os.path.expanduser(str(value).strip())))
    return expanded if expanded.is_absolute() else (base / expanded).resolve(strict=False)


def _bool(value: Any, default: bool) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    raise ConfigurationError(f"Expected boolean, received {value!r}")


def _integer(value: Any, default: int, minimum: int, maximum: int) -> int:
    if value is None:
        return default
    if isinstance(value, bool) or not isinstance(value, int):
        raise ConfigurationError(f"Expected integer, received {value!r}")
    return max(minimum, min(maximum, value))


def _default_workspace(*, base: Path, isolated: bool) -> Path:
    """Job staging lives with the live install, never under Documents.

    Isolated/CI configs (`--config` or SKYRIM_FORGE_CONFIG) stay beside that
    file. A normal user config follows SKYRIM_FORGE_ROOT when the installer
    registered it, otherwise `%USERPROFILE%\\.skyrim-forge\\Workspaces`.
    `Documents\\Skyrim Forge` is a leftover product-named folder, not an install.
    """
    if isolated:
        return base / "Workspaces"
    env_root = os.environ.get("SKYRIM_FORGE_ROOT")
    if env_root and env_root.strip():
        return Path(os.path.expandvars(os.path.expanduser(env_root.strip()))) / "Workspaces"
    return DEFAULT_HOME / "Workspaces"


def _is_legacy_documents_workspace(path: Path) -> bool:
    parts = path.parts
    return len(parts) >= 3 and parts[-3:] == ("Documents", "Skyrim Forge", "Workspaces")


def _workspace_is_empty(path: Path) -> bool:
    if not path.exists():
        return True
    if not path.is_dir():
        return False
    try:
        next(path.iterdir())
    except StopIteration:
        return True
    return False


def default_tools() -> dict[str, ToolConfig]:
    return {name: ToolConfig() for name in (
        "xedit", "mo2", "loot", "wrye_bash", "creation_kit", "ckpe_loader",
        "papyrus_compiler", "archive", "bsarch", "champollion", "synthesis_cli", "synthesis_gui", "deadmesh_cli", "deadmesh_gui",
        "eslifier", "nif_optimizer", "nif_analyzer", "resaver", "sniff", "cathedral_assets_optimizer",
        "nifskope", "texconv", "bodyslide", "pandora", "nemesis", "xlodgen", "dyndolod",
        "cmake", "vcpkg", "ninja", "ui_worker", "loot_worker", "wrye_worker", "ck_worker",
        "asset_worker", "animation_worker", "bodyslide_worker", "lod_worker", "grass_worker", "synthesis_worker", "audio_worker",
    )}


def load_config(path: str | Path | None = None, *, create: bool = True) -> ForgeConfig:
    environment_path = os.environ.get("SKYRIM_FORGE_CONFIG")
    isolated = path is not None or bool(environment_path)
    requested = Path(path or environment_path or DEFAULT_CONFIG).expanduser()
    base = requested.parent
    data: dict[str, Any] = {}
    warnings: list[str] = []
    if requested.is_file():
        try:
            data = tomllib.loads(requested.read_text(encoding="utf-8-sig"))
        except (OSError, UnicodeError, tomllib.TOMLDecodeError) as exc:
            backup = requested.with_suffix(requested.suffix + ".invalid.bak")
            shutil.copy2(requested, backup)
            warnings.append(f"Invalid configuration backed up to {backup}: {exc}")
            data = {}
    elif requested.exists():
        raise ConfigurationError(f"Configuration path is not a file: {requested}")

    known = {"paths", "safety", "limits", "tools", "papyrus"}
    unknown = set(data) - known
    if unknown:
        raise ConfigurationError(f"Unknown top-level configuration sections: {sorted(unknown)}")
    paths = data.get("paths", {})
    safety = data.get("safety", {})
    limits = data.get("limits", {})
    tools_data = data.get("tools", {})
    papyrus = data.get("papyrus", {})
    if not all(isinstance(section, dict) for section in (paths, safety, limits, tools_data, papyrus)):
        raise ConfigurationError("Configuration sections must be TOML tables")

    workspace_default = _default_workspace(base=base, isolated=isolated)
    audit_default = base / "audit.jsonl" if isolated else Path.home() / ".skyrim-forge" / "audit.jsonl"
    vault_default = base / "tool-vault" if isolated else DEFAULT_HOME / "tool-vault"
    workspace = _path(paths.get("workspace_root"), base) or workspace_default
    if _is_legacy_documents_workspace(workspace) and _workspace_is_empty(workspace):
        workspace = workspace_default
        warnings.append(
            "Empty default workspace was under Documents\\Skyrim Forge; "
            f"using {workspace} instead. The live product belongs in the Skyrim tools folder."
        )
    elif _is_legacy_documents_workspace(workspace):
        warnings.append(
            "workspace_root is still Documents\\Skyrim Forge. Move it under the live "
            "SKYRIM_FORGE_ROOT install with config-set workspace_root; do not keep a second Forge tree in Documents."
        )
    audit = _path(paths.get("audit_log"), base) or audit_default
    tools = default_tools()
    unknown_papyrus = set(papyrus) - {"compiler", "flags", "imports"}
    if unknown_papyrus:
        raise ConfigurationError(f"Unknown fields for papyrus: {sorted(unknown_papyrus)}")
    for name, raw in tools_data.items():
        if name not in tools:
            raise ConfigurationError(f"Unknown tool name: {name}")
        if not isinstance(raw, dict):
            raise ConfigurationError(f"Tool configuration must be a table: {name}")
        unknown_tool = set(raw) - {"executable", "sha256", "version", "timeout_seconds", "worker", "worker_sha256"}
        if unknown_tool:
            raise ConfigurationError(f"Unknown fields for tool {name}: {sorted(unknown_tool)}")
        tools[name] = ToolConfig(
            executable=_path(raw.get("executable"), base),
            sha256=str(raw.get("sha256", "")).strip().casefold(),
            version=str(raw.get("version", "")).strip(),
            timeout_seconds=_integer(raw.get("timeout_seconds"), 900, 1, 86_400),
            worker=_path(raw.get("worker"), base),
            worker_sha256=str(raw.get("worker_sha256", "")).strip().casefold(),
        )

    legacy_papyrus = bool(papyrus)
    legacy_compiler = _path(papyrus.get("compiler"), base)
    if legacy_compiler and not tools["papyrus_compiler"].executable:
        tools["papyrus_compiler"].executable = legacy_compiler
    papyrus_flags = _path(papyrus.get("flags"), base)
    raw_imports = papyrus.get("imports", [])
    if not isinstance(raw_imports, list):
        raise ConfigurationError("papyrus.imports must be a TOML array")
    papyrus_imports = [path for item in raw_imports if (path := _path(item, base))]
    if legacy_papyrus and "compiler" in papyrus:
        warnings.append("Migrated legacy papyrus.compiler into tools.papyrus_compiler.executable")

    config = ForgeConfig(
        config_path=requested,
        workspace_root=workspace,
        audit_log=audit,
        skyrim_data=_path(paths.get("skyrim_data"), base),
        plugins_file=_path(paths.get("plugins_file"), base),
        loadorder_file=_path(paths.get("loadorder_file"), base),
        mo2_profiles_root=_path(paths.get("mo2_profiles_root"), base),
        mo2_instance=str(paths.get("mo2_instance", "")).strip(),
        vortex_staging=_path(paths.get("vortex_staging"), base),
        vortex_downloads=_path(paths.get("vortex_downloads"), base),
        tools_root=_path(paths.get("tools_root"), base),
        tool_vault_root=_path(paths.get("tool_vault_root"), base) or vault_default,
        seven_zip=_path(paths.get("seven_zip"), base),
        allow_external_processes=_bool(safety.get("allow_external_processes"), False),
        require_approval_for_writes=_bool(safety.get("require_approval_for_writes"), True),
        allow_ui_automation=_bool(safety.get("allow_ui_automation"), False),
        max_scan_files=_integer(limits.get("max_scan_files"), 250_000, 100, 5_000_000),
        max_output_bytes=_integer(limits.get("max_output_bytes"), 2_000_000_000, 1_000_000, 64_000_000_000),
        extra_read_roots=[path for item in paths.get("extra_read_roots", []) if (path := _path(item, base))],
        tools=tools,
        papyrus_flags=papyrus_flags,
        papyrus_imports=papyrus_imports,
        load_warnings=warnings,
    )
    if create:
        config.workspace_root.mkdir(parents=True, exist_ok=True)
        config.audit_log.parent.mkdir(parents=True, exist_ok=True)
        config.tool_vault_root.mkdir(parents=True, exist_ok=True)
        if legacy_papyrus and "compiler" in papyrus and requested.is_file():
            backup = requested.with_suffix(requested.suffix + ".pre-3.0.1.bak")
            if not backup.exists():
                shutil.copy2(requested, backup)
        if not requested.exists() or warnings:
            save_config(config)
    return config


def _quote(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def save_config(config: ForgeConfig) -> None:
    rows = ["[paths]", f"workspace_root = {_quote(str(config.workspace_root))}", f"audit_log = {_quote(str(config.audit_log))}"]
    for name in ("skyrim_data", "plugins_file", "loadorder_file", "mo2_profiles_root", "vortex_staging", "vortex_downloads", "tools_root", "tool_vault_root", "seven_zip"):
        rows.append(f"{name} = {_quote(str(getattr(config, name) or ''))}")
    rows.append(f"mo2_instance = {_quote(config.mo2_instance)}")
    roots = ", ".join(_quote(str(path)) for path in config.extra_read_roots)
    rows.append(f"extra_read_roots = [{roots}]")
    rows.extend([
        "", "[papyrus]",
        f"flags = {_quote(str(config.papyrus_flags or ''))}",
        "imports = [" + ", ".join(_quote(str(path)) for path in config.papyrus_imports) + "]",
        "", "[safety]",
        f"allow_external_processes = {str(config.allow_external_processes).lower()}",
        f"require_approval_for_writes = {str(config.require_approval_for_writes).lower()}",
        f"allow_ui_automation = {str(config.allow_ui_automation).lower()}",
        "", "[limits]",
        f"max_scan_files = {config.max_scan_files}",
        f"max_output_bytes = {config.max_output_bytes}",
    ])
    for name in sorted(config.tools):
        tool = config.tools[name]
        rows.extend([
            "", f"[tools.{name}]",
            f"executable = {_quote(str(tool.executable or ''))}",
            f"worker = {_quote(str(tool.worker or ''))}",
            f"sha256 = {_quote(tool.sha256)}",
            f"version = {_quote(tool.version)}",
            f"worker_sha256 = {_quote(tool.worker_sha256)}",
            f"timeout_seconds = {tool.timeout_seconds}",
        ])
    config.config_path.parent.mkdir(parents=True, exist_ok=True)
    atomic_write_text(config.config_path, "\n".join(rows) + "\n")


def configure_value(config: ForgeConfig, dotted: str, value: str) -> ForgeConfig:
    if dotted.startswith("tools."):
        _, name, field_name = dotted.split(".", 2)
        if name not in config.tools or field_name not in {"executable", "worker", "sha256", "worker_sha256", "version", "timeout_seconds"}:
            raise ConfigurationError(f"Unsupported configuration key: {dotted}")
        tool = config.tools[name]
        if field_name in {"executable", "worker"}:
            setattr(tool, field_name, Path(value).expanduser().resolve(strict=False) if value else None)
        elif field_name == "timeout_seconds":
            tool.timeout_seconds = _integer(int(value), 900, 1, 86_400)
        else:
            setattr(tool, field_name, value.strip())
    elif dotted in {"workspace_root", "skyrim_data", "plugins_file", "loadorder_file", "mo2_profiles_root", "vortex_staging", "vortex_downloads", "tools_root", "tool_vault_root", "seven_zip"}:
        setattr(config, dotted, Path(value).expanduser().resolve(strict=False) if value else None)
        if dotted == "workspace_root" and config.workspace_root:
            config.workspace_root.mkdir(parents=True, exist_ok=True)
        if dotted == "tool_vault_root" and config.tool_vault_root:
            config.tool_vault_root.mkdir(parents=True, exist_ok=True)
    elif dotted == "mo2_instance":
        config.mo2_instance = value.strip()
    elif dotted == "papyrus.flags":
        config.papyrus_flags = Path(value).expanduser().resolve(strict=False) if value else None
    elif dotted == "papyrus.imports":
        config.papyrus_imports = [Path(item.strip()).expanduser().resolve(strict=False) for item in value.split(";") if item.strip()]
    elif dotted in {"allow_external_processes", "require_approval_for_writes", "allow_ui_automation"}:
        normalized = value.strip().casefold()
        if normalized not in {"true", "false", "1", "0", "yes", "no", "on", "off"}:
            raise ConfigurationError(f"Expected boolean for {dotted}")
        setattr(config, dotted, normalized in {"true", "1", "yes", "on"})
    else:
        raise ConfigurationError(f"Unsupported configuration key: {dotted}")
    save_config(config)
    return config
