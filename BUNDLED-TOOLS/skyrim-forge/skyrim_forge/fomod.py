from __future__ import annotations

import copy
import os
import re
import shutil
import tempfile
import xml.etree.ElementTree as ET
from dataclasses import asdict, dataclass
from pathlib import Path, PurePosixPath
from typing import Any, Iterable

from .errors import SafetyError, ValidationError
from .safety import require_approval, require_within
from .strictjson import load
from .util import atomic_write_text, sha256_file

PLAN_SCHEMA = "skyrim-forge-fomod-plan/1"
SCHEMA_LOCATION = "http://qconsulting.ca/fo3/ModConfig5.0.xsd"
# Real installers cite the schema by several equivalent spellings, and the fo3
# document is itself an xs:redefine of the gemm one. All of these describe the
# same ModuleConfig 5.0 structure.
_ACCEPTED_SCHEMA_LOCATIONS = {
    "http://qconsulting.ca/fo3/ModConfig5.0.xsd",
    "https://qconsulting.ca/fo3/ModConfig5.0.xsd",
    "http://qconsulting.ca/gemm/ModConfig5.0.xsd",
    "https://qconsulting.ca/gemm/ModConfig5.0.xsd",
    "ModConfig5.0.xsd",
}
# versionDependency elements added by game-specific redefinitions of the base
# schema. They carry a single `version` attribute and are inert to structural
# validation, so they are recorded as unverified rather than refused.
GAME_VERSION_DEPENDENCIES = {"gameDependency", "fommDependency", "foseDependency", "nvseDependency", "skseDependency"}
XSI = "http://www.w3.org/2001/XMLSchema-instance"
ORDER_VALUES = {"Ascending", "Descending", "Explicit"}
GROUP_TYPES = {"SelectExactlyOne", "SelectAtMostOne", "SelectAtLeastOne", "SelectAll", "SelectAny"}
PLUGIN_TYPES = {"Required", "Optional", "Recommended", "NotUsable", "CouldBeUsable"}
FILE_STATES = {"Active", "Inactive", "Missing"}
BOOL_TEXT = {"true", "false"}
TOP_LEVEL_ORDER = {
    "moduleName": 0,
    "moduleImage": 1,
    "moduleDependencies": 2,
    "requiredInstallFiles": 3,
    "installSteps": 4,
    "conditionalFileInstalls": 5,
}
ROOT_DOC_NAMES = {
    "readme", "readme.md", "readme.txt", "license", "license.md", "license.txt",
    "changelog", "changelog.md", "changelog.txt", "credits", "credits.md", "credits.txt",
}


@dataclass(slots=True)
class MappingEntry:
    kind: str
    source: str
    destination: str
    priority: int
    always_install: bool
    install_if_usable: bool
    owner: str


@dataclass(slots=True)
class FomodReport:
    result: str
    root: str
    module_config: str
    info_xml: str
    errors: list[str]
    warnings: list[str]
    counts: dict[str, int]
    missing_sources: list[str]
    unreferenced_payload: list[str]
    destination_collisions: list[dict[str, Any]]
    defined_flags: list[str]
    referenced_flags: list[str]
    evidence: str


def _tag(element: ET.Element) -> str:
    return element.tag.rsplit("}", 1)[-1]


def _check_xml_attributes(element: ET.Element, allowed: set[str], required: set[str], errors: list[str], label: str) -> None:
    names = {_tag_name for _tag_name in element.attrib}
    unknown = names - allowed
    missing = required - names
    if unknown:
        errors.append(f"{label} has unsupported attribute(s): {sorted(unknown)}")
    if missing:
        errors.append(f"{label} is missing required attribute(s): {sorted(missing)}")


def _dependency_flags(dependency: dict[str, Any] | None) -> set[str]:
    if dependency is None:
        return set()
    key, raw = next(iter(dependency.items()))
    if key in {"all", "any"}:
        result: set[str] = set()
        for child in raw:
            result.update(_dependency_flags(child))
        return result
    if key == "flag":
        return {raw["name"]}
    return set()


def _as_dict(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValidationError(f"{label} must be an object")
    return value


def _as_list(value: Any, label: str) -> list[Any]:
    if not isinstance(value, list):
        raise ValidationError(f"{label} must be an array")
    return value


def _check_keys(value: dict[str, Any], allowed: set[str], label: str) -> None:
    unknown = set(value) - allowed
    if unknown:
        raise ValidationError(f"Unknown fields for {label}: {sorted(unknown)}")


def _nonempty(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValidationError(f"{label} must be a non-empty string")
    return value.strip()


def _optional_text(value: Any, label: str) -> str:
    if value is None:
        return ""
    if not isinstance(value, str):
        raise ValidationError(f"{label} must be a string")
    return value.strip()


def _bool(value: Any, label: str, default: bool = False) -> bool:
    if value is None:
        return default
    if not isinstance(value, bool):
        raise ValidationError(f"{label} must be boolean")
    return value


def _integer(value: Any, label: str, default: int = 0) -> int:
    if value is None:
        return default
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValidationError(f"{label} must be an integer")
    if not -2_147_483_648 <= value <= 2_147_483_647:
        raise ValidationError(f"{label} is outside signed 32-bit range")
    return value


def _relative_path(value: Any, label: str, *, allow_empty: bool = False) -> str:
    if value is None and allow_empty:
        return ""
    if not isinstance(value, str):
        raise ValidationError(f"{label} must be a string")
    text = value.strip().replace("\\", "/")
    if not text and allow_empty:
        return ""
    if not text:
        raise ValidationError(f"{label} must not be empty")
    path = PurePosixPath(text)
    if path.is_absolute() or text.startswith("/") or re.match(r"^[A-Za-z]:", text):
        raise ValidationError(f"{label} must be a relative archive path: {value!r}")
    if any(part in {"", ".", ".."} for part in path.parts):
        raise ValidationError(f"{label} contains unsafe path components: {value!r}")
    return path.as_posix()


def _version_tuple(text: str) -> tuple[int, ...]:
    if not re.fullmatch(r"\d+(?:\.\d+)*", text.strip()):
        raise ValidationError(f"Invalid dotted numeric version: {text!r}")
    return tuple(int(part) for part in text.split("."))


def _version_at_least(actual: str, required: str) -> bool:
    left = list(_version_tuple(actual))
    right = list(_version_tuple(required))
    length = max(len(left), len(right))
    left.extend([0] * (length - len(left)))
    right.extend([0] * (length - len(right)))
    return tuple(left) >= tuple(right)


def _validate_dependency(value: Any, label: str = "dependency", depth: int = 0, referenced_flags: set[str] | None = None) -> dict[str, Any] | None:
    if value is None:
        return None
    if depth > 32:
        raise ValidationError(f"{label} exceeds maximum nesting depth")
    dependency = _as_dict(value, label)
    allowed = {"all", "any", "file", "flag", "game_version", "fomm_version"}
    _check_keys(dependency, allowed, label)
    selected = [key for key in allowed if key in dependency]
    if len(selected) != 1:
        raise ValidationError(f"{label} must contain exactly one dependency operator")
    key = selected[0]
    raw = dependency[key]
    if key in {"all", "any"}:
        values = _as_list(raw, f"{label}.{key}")
        if not values:
            raise ValidationError(f"{label}.{key} must not be empty")
        return {key: [_validate_dependency(item, f"{label}.{key}[{index}]", depth + 1, referenced_flags) for index, item in enumerate(values)]}
    if key == "file":
        item = _as_dict(raw, f"{label}.file")
        _check_keys(item, {"path", "state"}, f"{label}.file")
        state = _nonempty(item.get("state"), f"{label}.file.state")
        if state not in FILE_STATES:
            raise ValidationError(f"{label}.file.state must be one of {sorted(FILE_STATES)}")
        return {"file": {"path": _relative_path(item.get("path"), f"{label}.file.path"), "state": state}}
    if key == "flag":
        item = _as_dict(raw, f"{label}.flag")
        _check_keys(item, {"name", "value"}, f"{label}.flag")
        name = _nonempty(item.get("name"), f"{label}.flag.name")
        expected = _nonempty(item.get("value"), f"{label}.flag.value")
        if referenced_flags is not None:
            referenced_flags.add(name)
        return {"flag": {"name": name, "value": expected}}
    version = _nonempty(raw, f"{label}.{key}")
    _version_tuple(version)
    return {key: version}


def _validate_mapping(value: Any, label: str, owner: str) -> dict[str, Any]:
    item = _as_dict(value, label)
    _check_keys(item, {"kind", "source", "destination", "priority", "always_install", "install_if_usable"}, label)
    kind = _optional_text(item.get("kind"), f"{label}.kind") or "file"
    if kind not in {"file", "folder"}:
        raise ValidationError(f"{label}.kind must be 'file' or 'folder'")
    return {
        "kind": kind,
        "source": _relative_path(item.get("source"), f"{label}.source"),
        "destination": _relative_path(item.get("destination", ""), f"{label}.destination", allow_empty=True),
        "priority": _integer(item.get("priority"), f"{label}.priority", 0),
        "always_install": _bool(item.get("always_install"), f"{label}.always_install", False),
        "install_if_usable": _bool(item.get("install_if_usable"), f"{label}.install_if_usable", False),
        "owner": owner,
    }


def _validate_type_descriptor(value: Any, label: str, referenced_flags: set[str]) -> dict[str, Any]:
    if isinstance(value, str):
        if value not in PLUGIN_TYPES:
            raise ValidationError(f"{label} must be one of {sorted(PLUGIN_TYPES)}")
        return {"type": value}
    item = _as_dict(value, label)
    _check_keys(item, {"default", "patterns"}, label)
    default = _nonempty(item.get("default"), f"{label}.default")
    if default not in PLUGIN_TYPES:
        raise ValidationError(f"{label}.default must be one of {sorted(PLUGIN_TYPES)}")
    patterns = []
    for index, raw in enumerate(_as_list(item.get("patterns", []), f"{label}.patterns")):
        pattern = _as_dict(raw, f"{label}.patterns[{index}]")
        _check_keys(pattern, {"dependencies", "type"}, f"{label}.patterns[{index}]")
        plugin_type = _nonempty(pattern.get("type"), f"{label}.patterns[{index}].type")
        if plugin_type not in PLUGIN_TYPES:
            raise ValidationError(f"{label}.patterns[{index}].type must be one of {sorted(PLUGIN_TYPES)}")
        dependencies = _validate_dependency(pattern.get("dependencies"), f"{label}.patterns[{index}].dependencies", referenced_flags=referenced_flags)
        if dependencies is None:
            raise ValidationError(f"{label}.patterns[{index}].dependencies is required")
        patterns.append({"dependencies": dependencies, "type": plugin_type})
    if not patterns:
        raise ValidationError(f"{label}.patterns must contain at least one pattern")
    return {"default": default, "patterns": patterns}


def validate_plan_data(plan: Any, source_root: Path | None = None, *, strict_coverage: bool | None = None) -> dict[str, Any]:
    root = _as_dict(plan, "FOMOD plan")
    _check_keys(root, {"schema", "module", "module_dependencies", "required_files", "steps", "steps_order", "conditional_files", "strict_coverage", "xml_encoding"}, "FOMOD plan")
    if root.get("schema") != PLAN_SCHEMA:
        raise ValidationError(f"Unsupported FOMOD plan schema: {root.get('schema')!r}")
    module = _as_dict(root.get("module"), "module")
    _check_keys(module, {"name", "author", "version", "machine_version", "description", "website", "image", "id", "category_id", "groups", "name_position", "name_colour", "image_show", "image_fade", "image_height"}, "module")
    normalized_module = {
        "name": _nonempty(module.get("name"), "module.name"),
        "author": _optional_text(module.get("author"), "module.author"),
        "version": _nonempty(module.get("version"), "module.version"),
        "machine_version": _optional_text(module.get("machine_version"), "module.machine_version") or _nonempty(module.get("version"), "module.version"),
        "description": _optional_text(module.get("description"), "module.description"),
        "website": _optional_text(module.get("website"), "module.website"),
        "image": _relative_path(module.get("image"), "module.image") if module.get("image") else "",
        "id": _optional_text(module.get("id"), "module.id"),
        "category_id": _optional_text(module.get("category_id"), "module.category_id"),
        "groups": [],
        "name_position": _optional_text(module.get("name_position"), "module.name_position") or "Left",
        "name_colour": _optional_text(module.get("name_colour"), "module.name_colour"),
        "image_show": _bool(module.get("image_show"), "module.image_show", True),
        "image_fade": _bool(module.get("image_fade"), "module.image_fade", True),
        "image_height": _integer(module.get("image_height"), "module.image_height", -1),
    }
    _version_tuple(normalized_module["machine_version"])
    if normalized_module["name_position"] not in {"Left", "Right", "RightOfImage"}:
        raise ValidationError("module.name_position must be Left, Right, or RightOfImage")
    if normalized_module["name_colour"] and not re.fullmatch(r"#?[0-9A-Fa-f]{6}", normalized_module["name_colour"]):
        raise ValidationError("module.name_colour must be a six-digit RGB hex value")
    if normalized_module["image_height"] < -1:
        raise ValidationError("module.image_height must be -1 or greater")
    for index, group in enumerate(_as_list(module.get("groups", []), "module.groups")):
        normalized_module["groups"].append(_nonempty(group, f"module.groups[{index}]"))

    defined_flags: set[str] = set()
    referenced_flags: set[str] = set()
    module_dependencies = _validate_dependency(root.get("module_dependencies"), "module_dependencies", referenced_flags=referenced_flags)
    required_files = [_validate_mapping(item, f"required_files[{index}]", "required") for index, item in enumerate(_as_list(root.get("required_files", []), "required_files"))]
    steps = []
    seen_steps: set[str] = set()
    seen_plugins: set[str] = set()
    for si, raw_step in enumerate(_as_list(root.get("steps", []), "steps")):
        step = _as_dict(raw_step, f"steps[{si}]")
        _check_keys(step, {"name", "visible", "groups_order", "groups"}, f"steps[{si}]")
        step_name = _nonempty(step.get("name"), f"steps[{si}].name")
        if step_name.casefold() in seen_steps:
            raise ValidationError(f"Duplicate install step name: {step_name}")
        seen_steps.add(step_name.casefold())
        groups_order = _optional_text(step.get("groups_order"), f"steps[{si}].groups_order") or "Explicit"
        if groups_order not in ORDER_VALUES:
            raise ValidationError(f"steps[{si}].groups_order must be one of {sorted(ORDER_VALUES)}")
        groups = []
        seen_groups: set[str] = set()
        for gi, raw_group in enumerate(_as_list(step.get("groups", []), f"steps[{si}].groups")):
            group = _as_dict(raw_group, f"steps[{si}].groups[{gi}]")
            _check_keys(group, {"name", "type", "plugins_order", "plugins"}, f"steps[{si}].groups[{gi}]")
            group_name = _nonempty(group.get("name"), f"steps[{si}].groups[{gi}].name")
            if group_name.casefold() in seen_groups:
                raise ValidationError(f"Duplicate group name in step {step_name}: {group_name}")
            seen_groups.add(group_name.casefold())
            group_type = _nonempty(group.get("type"), f"steps[{si}].groups[{gi}].type")
            if group_type not in GROUP_TYPES:
                raise ValidationError(f"steps[{si}].groups[{gi}].type must be one of {sorted(GROUP_TYPES)}")
            plugins_order = _optional_text(group.get("plugins_order"), f"steps[{si}].groups[{gi}].plugins_order") or "Explicit"
            if plugins_order not in ORDER_VALUES:
                raise ValidationError(f"steps[{si}].groups[{gi}].plugins_order must be one of {sorted(ORDER_VALUES)}")
            plugins = []
            for pi, raw_plugin in enumerate(_as_list(group.get("plugins", []), f"steps[{si}].groups[{gi}].plugins")):
                plugin = _as_dict(raw_plugin, f"steps[{si}].groups[{gi}].plugins[{pi}]")
                _check_keys(plugin, {"name", "description", "image", "files", "flags", "type"}, f"steps[{si}].groups[{gi}].plugins[{pi}]")
                plugin_name = _nonempty(plugin.get("name"), f"steps[{si}].groups[{gi}].plugins[{pi}].name")
                identity = f"{step_name}/{group_name}/{plugin_name}".casefold()
                if identity in seen_plugins:
                    raise ValidationError(f"Duplicate plugin identity: {step_name}/{group_name}/{plugin_name}")
                seen_plugins.add(identity)
                flags = {}
                raw_flags = _as_dict(plugin.get("flags", {}), f"steps[{si}].groups[{gi}].plugins[{pi}].flags")
                for name, value in raw_flags.items():
                    flag_name = _nonempty(name, f"steps[{si}].groups[{gi}].plugins[{pi}].flags name")
                    flag_value = _nonempty(value, f"steps[{si}].groups[{gi}].plugins[{pi}].flags[{flag_name}]")
                    flags[flag_name] = flag_value
                    defined_flags.add(flag_name)
                owner = f"plugin:{step_name}/{group_name}/{plugin_name}"
                files_present = "files" in plugin
                plugin_files = [_validate_mapping(item, f"steps[{si}].groups[{gi}].plugins[{pi}].files[{fi}]", owner) for fi, item in enumerate(_as_list(plugin.get("files", []), f"steps[{si}].groups[{gi}].plugins[{pi}].files"))]
                if not files_present and not flags:
                    raise ValidationError(f"Plugin {step_name}/{group_name}/{plugin_name} must explicitly contain files or condition flags to satisfy ModuleConfig 5.0")
                plugins.append({
                    "name": plugin_name,
                    "description": _optional_text(plugin.get("description"), f"steps[{si}].groups[{gi}].plugins[{pi}].description"),
                    "image": _relative_path(plugin.get("image"), f"steps[{si}].groups[{gi}].plugins[{pi}].image") if plugin.get("image") else "",
                    "files": plugin_files,
                    "files_present": files_present,
                    "flags": flags,
                    "type": _validate_type_descriptor(plugin.get("type", "Optional"), f"steps[{si}].groups[{gi}].plugins[{pi}].type", referenced_flags),
                })
            if not plugins:
                raise ValidationError(f"Group {step_name}/{group_name} must contain at least one plugin")
            groups.append({"name": group_name, "type": group_type, "plugins_order": plugins_order, "plugins": plugins})
        if not groups:
            raise ValidationError(f"Install step {step_name} must contain at least one group")
        steps.append({
            "name": step_name,
            "visible": _validate_dependency(step.get("visible"), f"steps[{si}].visible", referenced_flags=referenced_flags),
            "groups_order": groups_order,
            "groups": groups,
        })

    conditional_files = []
    for ci, raw in enumerate(_as_list(root.get("conditional_files", []), "conditional_files")):
        pattern = _as_dict(raw, f"conditional_files[{ci}]")
        _check_keys(pattern, {"dependencies", "files"}, f"conditional_files[{ci}]")
        dependencies = _validate_dependency(pattern.get("dependencies"), f"conditional_files[{ci}].dependencies", referenced_flags=referenced_flags)
        if dependencies is None:
            raise ValidationError(f"conditional_files[{ci}].dependencies is required")
        files = [_validate_mapping(item, f"conditional_files[{ci}].files[{fi}]", f"conditional:{ci}") for fi, item in enumerate(_as_list(pattern.get("files", []), f"conditional_files[{ci}].files"))]
        if not files:
            raise ValidationError(f"conditional_files[{ci}].files must contain at least one mapping")
        conditional_files.append({"dependencies": dependencies, "files": files})
    unknown_flags = sorted(referenced_flags - defined_flags)
    if unknown_flags:
        raise ValidationError(f"FOMOD dependencies reference undefined condition flags: {unknown_flags}")
    module_flag_refs = sorted(_dependency_flags(module_dependencies))
    if module_flag_refs:
        raise ValidationError(f"module_dependencies cannot reference selection flags before installation begins: {module_flag_refs}")
    available_flags: set[str] = set()
    for step in steps:
        early_refs = _dependency_flags(step["visible"])
        for group in step["groups"]:
            for plugin in group["plugins"]:
                if "patterns" in plugin["type"]:
                    for pattern in plugin["type"]["patterns"]:
                        early_refs.update(_dependency_flags(pattern["dependencies"]))
        unavailable = sorted(early_refs - available_flags)
        if unavailable:
            raise ValidationError(f"Install step {step['name']!r} references condition flags not defined by earlier steps: {unavailable}")
        for group in step["groups"]:
            static_required = [plugin["name"] for plugin in group["plugins"] if plugin["type"] == {"type": "Required"}]
            if group["type"] in {"SelectExactlyOne", "SelectAtMostOne"} and len(static_required) > 1:
                raise ValidationError(f"Group {step['name']}/{group['name']} has multiple Required plugins but permits at most one selection")
            for plugin in group["plugins"]:
                available_flags.update(plugin["flags"])

    normalized = {
        "schema": PLAN_SCHEMA,
        "module": normalized_module,
        "module_dependencies": module_dependencies,
        "required_files": required_files,
        "steps": steps,
        "steps_order": _optional_text(root.get("steps_order"), "steps_order") or "Explicit",
        "conditional_files": conditional_files,
        "xml_encoding": _optional_text(root.get("xml_encoding"), "xml_encoding") or "utf-8",
        "strict_coverage": _bool(root.get("strict_coverage"), "strict_coverage", True) if strict_coverage is None else strict_coverage,
    }
    if normalized["steps_order"] not in ORDER_VALUES:
        raise ValidationError(f"steps_order must be one of {sorted(ORDER_VALUES)}")
    if normalized["xml_encoding"].casefold() not in {"utf-8", "utf-16"}:
        raise ValidationError("xml_encoding must be utf-8 or utf-16")
    normalized["xml_encoding"] = normalized["xml_encoding"].casefold()
    if source_root is not None:
        source_root = source_root.resolve(strict=True)
        if not source_root.is_dir():
            raise ValidationError("FOMOD source root must be a directory")
        analysis = analyze_plan_files(normalized, source_root, strict_coverage=normalized["strict_coverage"])
        if analysis["errors"]:
            raise ValidationError("FOMOD plan file analysis failed: " + "; ".join(analysis["errors"]))
        normalized["file_analysis"] = analysis
    return normalized


def validate_plan(path: Path, source_root: Path | None = None, *, strict_coverage: bool | None = None) -> dict[str, Any]:
    path = path.resolve(strict=True)
    return validate_plan_data(load(path), source_root, strict_coverage=strict_coverage)


def _mapping_objects(plan: dict[str, Any]) -> list[MappingEntry]:
    result: list[MappingEntry] = []
    def append(items: Iterable[dict[str, Any]]) -> None:
        for item in items:
            result.append(MappingEntry(
                item["kind"], item["source"], item["destination"], item["priority"],
                item["always_install"], item["install_if_usable"], item["owner"],
            ))
    append(plan["required_files"])
    for step in plan["steps"]:
        for group in step["groups"]:
            for plugin in group["plugins"]:
                append(plugin["files"])
    for pattern in plan["conditional_files"]:
        append(pattern["files"])
    return result


def _payload_files(root: Path) -> set[str]:
    result = set()
    for path in root.rglob("*"):
        if not path.is_file() or path.is_symlink():
            continue
        rel = path.relative_to(root).as_posix()
        parts = [part.casefold() for part in PurePosixPath(rel).parts]
        if parts and parts[0] == "fomod":
            continue
        if len(parts) == 1 and parts[0] in ROOT_DOC_NAMES:
            continue
        if len(parts) == 1 and (parts[0].startswith("readme.") or parts[0].startswith("license.") or parts[0].startswith("changelog.")):
            continue
        result.add(rel)
    return result


def _expand_mapping(root: Path, entry: MappingEntry) -> tuple[list[tuple[str, str, int, str, bool, bool]], str | None]:
    source = root.joinpath(*PurePosixPath(entry.source).parts)
    if not source.exists():
        return [], entry.source
    if source.is_symlink():
        return [], entry.source + " (symlink is not allowed)"
    rows = []
    if entry.kind == "file":
        if not source.is_file():
            return [], entry.source + " (expected file)"
        destination = entry.destination or PurePosixPath(entry.source).name
        rows.append((entry.source, destination, entry.priority, entry.owner, entry.always_install, entry.install_if_usable))
    else:
        if not source.is_dir():
            return [], entry.source + " (expected folder)"
        for child in sorted(source.rglob("*"), key=lambda p: p.as_posix().casefold()):
            if not child.is_file() or child.is_symlink():
                continue
            child_rel = child.relative_to(root).as_posix()
            nested = child.relative_to(source).as_posix()
            destination = (PurePosixPath(entry.destination) / nested).as_posix() if entry.destination else nested
            rows.append((child_rel, destination, entry.priority, entry.owner, entry.always_install, entry.install_if_usable))
    return rows, None


def analyze_plan_files(plan: dict[str, Any], source_root: Path, *, strict_coverage: bool = True) -> dict[str, Any]:
    source_root = source_root.resolve(strict=True)
    errors: list[str] = []
    warnings: list[str] = []
    covered: set[str] = set()
    missing: list[str] = []
    destinations: dict[str, list[dict[str, Any]]] = {}
    exclusive_owner_groups: dict[str, str] = {}
    for step in plan["steps"]:
        for group in step["groups"]:
            if group["type"] in {"SelectExactlyOne", "SelectAtMostOne"}:
                group_id = f"{step['name']}/{group['name']}".casefold()
                for plugin in group["plugins"]:
                    exclusive_owner_groups[f"plugin:{step['name']}/{group['name']}/{plugin['name']}".casefold()] = group_id
    entries = _mapping_objects(plan)
    for entry in entries:
        rows, problem = _expand_mapping(source_root, entry)
        if problem:
            missing.append(problem)
            continue
        for source, destination, priority, owner, always_install, install_if_usable in rows:
            covered.add(source)
            key = destination.casefold()
            destinations.setdefault(key, []).append({"source": source, "destination": destination, "priority": priority, "owner": owner, "always_install": always_install, "install_if_usable": install_if_usable})
    for image_owner, image in [("module", plan["module"].get("image", ""))] + [
        (f"plugin:{step['name']}/{group['name']}/{plugin['name']}", plugin.get("image", ""))
        for step in plan["steps"] for group in step["groups"] for plugin in group["plugins"]
    ]:
        if image:
            target = source_root.joinpath(*PurePosixPath(image).parts)
            if not target.is_file():
                missing.append(f"{image} (missing image for {image_owner})")
            else:
                covered.add(image)
    collisions = []
    for rows in destinations.values():
        sources = {row["source"].casefold() for row in rows}
        if len(sources) <= 1:
            continue
        highest = max(row["priority"] for row in rows)
        winners = [row for row in rows if row["priority"] == highest]
        owner_groups = {exclusive_owner_groups.get(row["owner"].casefold()) for row in rows}
        mutually_exclusive = None not in owner_groups and len(owner_groups) == 1 and len({row["owner"].casefold() for row in rows}) == len(rows) and not any(row["always_install"] or row["install_if_usable"] for row in rows)
        resolved_by_priority = len({row["source"].casefold() for row in winners}) == 1
        collision = {
            "destination": rows[0]["destination"],
            "entries": rows,
            "mutually_exclusive": mutually_exclusive,
            "resolved_by_priority": resolved_by_priority,
        }
        collisions.append(collision)
        if mutually_exclusive:
            warnings.append(f"FOMOD destination collision at {rows[0]['destination']!r} is safe because options are mutually exclusive")
        elif not resolved_by_priority:
            errors.append(f"Ambiguous FOMOD destination collision at {rows[0]['destination']!r}: equal highest priority {highest}")
        else:
            warnings.append(f"FOMOD destination collision at {rows[0]['destination']!r} is resolved by priority {highest}")
    payload = _payload_files(source_root)
    unreferenced = sorted(payload - covered, key=str.casefold)
    if unreferenced:
        # Name the files. A gate that reports only a count cannot be acted on,
        # and this one is meant to be the last check before a mod ships.
        shown = ", ".join(unreferenced[:10])
        if len(unreferenced) > 10:
            shown += f", and {len(unreferenced) - 10} more"
        message = f"FOMOD payload contains {len(unreferenced)} unreferenced file(s): {shown}"
        (errors if strict_coverage else warnings).append(message)
    if missing:
        errors.append(f"FOMOD references {len(missing)} missing or invalid source path(s)")
    return {
        "result": "PASS" if not errors else "FAIL",
        "entries": len(entries),
        "mapped_files": len(covered),
        "payload_files": len(payload),
        "missing_sources": sorted(missing, key=str.casefold),
        "unreferenced_payload": unreferenced,
        "destination_collisions": collisions,
        "errors": errors,
        "warnings": warnings,
    }


def _dependency_element(parent: ET.Element, dependency: dict[str, Any] | None) -> None:
    if dependency is None:
        return
    key, raw = next(iter(dependency.items()))
    if key in {"all", "any"}:
        element = ET.SubElement(parent, "dependencies", {"operator": "And" if key == "all" else "Or"})
        for child in raw:
            _dependency_child(element, child)
    else:
        element = ET.SubElement(parent, "dependencies", {"operator": "And"})
        _dependency_child(element, dependency)


def _dependency_child(parent: ET.Element, dependency: dict[str, Any]) -> None:
    key, raw = next(iter(dependency.items()))
    if key in {"all", "any"}:
        nested = ET.SubElement(parent, "dependencies", {"operator": "And" if key == "all" else "Or"})
        for child in raw:
            _dependency_child(nested, child)
    elif key == "file":
        ET.SubElement(parent, "fileDependency", {"file": raw["path"], "state": raw["state"]})
    elif key == "flag":
        ET.SubElement(parent, "flagDependency", {"flag": raw["name"], "value": raw["value"]})
    elif key == "game_version":
        ET.SubElement(parent, "gameDependency", {"version": raw})
    elif key == "fomm_version":
        ET.SubElement(parent, "fommDependency", {"version": raw})
    else:
        raise AssertionError(key)


def _mapping_elements(parent: ET.Element, mappings: list[dict[str, Any]]) -> None:
    for mapping in mappings:
        attributes = {"source": mapping["source"], "destination": mapping["destination"]}
        if mapping["priority"]:
            attributes["priority"] = str(mapping["priority"])
        if mapping["always_install"]:
            attributes["alwaysInstall"] = "true"
        if mapping["install_if_usable"]:
            attributes["installIfUsable"] = "true"
        ET.SubElement(parent, mapping["kind"], attributes)


def _type_descriptor(parent: ET.Element, descriptor: dict[str, Any]) -> None:
    container = ET.SubElement(parent, "typeDescriptor")
    if "type" in descriptor:
        ET.SubElement(container, "type", {"name": descriptor["type"]})
        return
    dynamic = ET.SubElement(container, "dependencyType")
    ET.SubElement(dynamic, "defaultType", {"name": descriptor["default"]})
    patterns = ET.SubElement(dynamic, "patterns")
    for pattern in descriptor["patterns"]:
        node = ET.SubElement(patterns, "pattern")
        _dependency_element(node, pattern["dependencies"])
        ET.SubElement(node, "type", {"name": pattern["type"]})


def plan_to_xml(plan: dict[str, Any]) -> tuple[ET.ElementTree, ET.ElementTree]:
    ET.register_namespace("xsi", XSI)
    config = ET.Element("config", {f"{{{XSI}}}noNamespaceSchemaLocation": SCHEMA_LOCATION})
    name_attrs = {"position": plan["module"]["name_position"]}
    if plan["module"]["name_colour"]:
        name_attrs["colour"] = plan["module"]["name_colour"].lstrip("#")
    ET.SubElement(config, "moduleName", name_attrs).text = plan["module"]["name"]
    include_module_image = bool(plan["module"]["image"]) or not plan["module"]["image_show"] or not plan["module"]["image_fade"] or plan["module"]["image_height"] != -1
    if include_module_image:
        image_attrs = {
            "showImage": str(plan["module"]["image_show"]).lower(),
            "showFade": str(plan["module"]["image_fade"]).lower(),
        }
        if plan["module"]["image"]:
            image_attrs["path"] = plan["module"]["image"]
        if plan["module"]["image_height"] != -1:
            image_attrs["height"] = str(plan["module"]["image_height"])
        ET.SubElement(config, "moduleImage", image_attrs)
    if plan["module_dependencies"]:
        holder = ET.SubElement(config, "moduleDependencies", {"operator": "And"})
        dependency = plan["module_dependencies"]
        key = next(iter(dependency))
        if key in {"all", "any"}:
            holder.set("operator", "And" if key == "all" else "Or")
            for child in dependency[key]:
                _dependency_child(holder, child)
        else:
            _dependency_child(holder, dependency)
    if plan["required_files"]:
        required = ET.SubElement(config, "requiredInstallFiles")
        _mapping_elements(required, plan["required_files"])
    if plan["steps"]:
        install_steps = ET.SubElement(config, "installSteps", {"order": plan["steps_order"]})
        for step in plan["steps"]:
            step_element = ET.SubElement(install_steps, "installStep", {"name": step["name"]})
            if step["visible"]:
                visible = ET.SubElement(step_element, "visible")
                dependency = step["visible"]
                key = next(iter(dependency))
                if key in {"all", "any"}:
                    visible.set("operator", "And" if key == "all" else "Or")
                    for child in dependency[key]:
                        _dependency_child(visible, child)
                else:
                    visible.set("operator", "And")
                    _dependency_child(visible, dependency)
            groups = ET.SubElement(step_element, "optionalFileGroups", {"order": step["groups_order"]})
            for group in step["groups"]:
                group_element = ET.SubElement(groups, "group", {"name": group["name"], "type": group["type"]})
                plugins = ET.SubElement(group_element, "plugins", {"order": group["plugins_order"]})
                for plugin in group["plugins"]:
                    plugin_element = ET.SubElement(plugins, "plugin", {"name": plugin["name"]})
                    ET.SubElement(plugin_element, "description").text = plugin["description"]
                    if plugin["image"]:
                        ET.SubElement(plugin_element, "image", {"path": plugin["image"]})
                    if plugin["files_present"]:
                        files = ET.SubElement(plugin_element, "files")
                        _mapping_elements(files, plugin["files"])
                    if plugin["flags"]:
                        flags = ET.SubElement(plugin_element, "conditionFlags")
                        for name, value in sorted(plugin["flags"].items(), key=lambda item: item[0].casefold()):
                            ET.SubElement(flags, "flag", {"name": name}).text = value
                    _type_descriptor(plugin_element, plugin["type"])
    if plan["conditional_files"]:
        conditional = ET.SubElement(config, "conditionalFileInstalls")
        patterns = ET.SubElement(conditional, "patterns")
        for pattern in plan["conditional_files"]:
            pattern_element = ET.SubElement(patterns, "pattern")
            _dependency_element(pattern_element, pattern["dependencies"])
            files = ET.SubElement(pattern_element, "files")
            _mapping_elements(files, pattern["files"])
    ET.indent(config, space="  ")

    info = ET.Element("fomod")
    ET.SubElement(info, "Name").text = plan["module"]["name"]
    if plan["module"]["author"]:
        ET.SubElement(info, "Author").text = plan["module"]["author"]
    ET.SubElement(info, "Version", {"MachineVersion": plan["module"]["machine_version"]}).text = plan["module"]["version"]
    if plan["module"]["description"]:
        ET.SubElement(info, "Description").text = plan["module"]["description"]
    if plan["module"]["website"]:
        ET.SubElement(info, "Website").text = plan["module"]["website"]
    if plan["module"]["id"]:
        ET.SubElement(info, "Id").text = plan["module"]["id"]
    if plan["module"]["category_id"]:
        ET.SubElement(info, "CategoryId").text = plan["module"]["category_id"]
    if plan["module"]["groups"]:
        groups = ET.SubElement(info, "Groups")
        for name in plan["module"]["groups"]:
            ET.SubElement(groups, "element").text = name
    ET.indent(info, space="  ")
    return ET.ElementTree(config), ET.ElementTree(info)


def _write_xml(tree: ET.ElementTree, path: Path, encoding: str = "utf-8") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tree.write(path, encoding=encoding, xml_declaration=True, short_empty_elements=True)


def _find_casefold(root: Path, *parts: str) -> Path | None:
    current = root
    for part in parts:
        if not current.is_dir():
            return None
        matches = [child for child in current.iterdir() if child.name.casefold() == part.casefold()]
        if len(matches) != 1:
            return None
        current = matches[0]
    return current


def _parse_bool_attr(value: str | None, label: str, errors: list[str]) -> bool:
    if value is None:
        return False
    normalized = value.casefold()
    if normalized not in BOOL_TEXT:
        errors.append(f"{label} must be true or false")
        return False
    return normalized == "true"


def _parse_int_attr(value: str | None, label: str, errors: list[str]) -> int:
    if value is None or value == "":
        return 0
    try:
        return int(value)
    except ValueError:
        errors.append(f"{label} must be an integer")
        return 0


def _xml_dependency(element: ET.Element, errors: list[str], referenced_flags: set[str], label: str, depth: int = 0, warnings: list[str] | None = None) -> dict[str, Any] | None:
    if depth > 32:
        errors.append(f"{label} exceeds maximum dependency nesting depth")
        return None
    tag = _tag(element)
    if tag in {"moduleDependencies", "dependencies", "visible"}:
        _check_xml_attributes(element, {"operator"}, set(), errors, label)
        operator = element.attrib.get("operator", "And")
        if operator not in {"And", "Or"}:
            errors.append(f"{label} has invalid operator {operator!r}")
            operator = "And"
        children = []
        for index, child in enumerate(element):
            parsed = _xml_dependency(child, errors, referenced_flags, f"{label}/{_tag(child)}[{index}]", depth + 1, warnings)
            if parsed is not None:
                children.append(parsed)
        if not children:
            errors.append(f"{label} contains no dependencies")
        return {"all" if operator == "And" else "any": children}
    if tag == "fileDependency":
        _check_xml_attributes(element, {"file", "state"}, {"file", "state"}, errors, label)
        path = element.attrib.get("file", "")
        state = element.attrib.get("state", "")
        try:
            path = _relative_path(path, f"{label}.file")
        except ValidationError as exc:
            errors.append(str(exc)); path = path
        if state not in FILE_STATES:
            errors.append(f"{label}.state must be one of {sorted(FILE_STATES)}")
        return {"file": {"path": path, "state": state}}
    if tag == "flagDependency":
        _check_xml_attributes(element, {"flag", "value"}, {"flag", "value"}, errors, label)
        name = element.attrib.get("flag", "").strip()
        value = element.attrib.get("value", "").strip()
        if not name or not value:
            errors.append(f"{label} requires flag and value attributes")
        if name:
            referenced_flags.add(name)
        return {"flag": {"name": name, "value": value}}
    if tag in GAME_VERSION_DEPENDENCIES:
        # Game-specific redefinitions of ModConfig5.0 add their own
        # versionDependency elements; the fo3 schema Forge names as canonical
        # exists precisely to add foseDependency. Refusing them contradicted the
        # schema this validator asks installers to declare.
        _check_xml_attributes(element, {"version"}, {"version"}, errors, label)
        version = element.attrib.get("version", "")
        try:
            _version_tuple(version)
        except ValidationError as exc:
            errors.append(str(exc))
        key = {"gameDependency": "game_version", "fommDependency": "fomm_version"}.get(tag, f"{tag[:-10]}_version")
        if tag not in {"gameDependency", "fommDependency"} and warnings is not None:
            warnings.append(f"{label} uses {tag}, a game-specific schema extension. Forge records it without verifying the runtime it names.")
        return {key: version}
    errors.append(f"Unsupported dependency element at {label}: {tag}")
    return None


def _xml_mappings(container: ET.Element, errors: list[str], owner: str) -> list[dict[str, Any]]:
    result = []
    for index, element in enumerate(container):
        tag = _tag(element)
        if tag not in {"file", "folder"}:
            errors.append(f"Unsupported file mapping element {tag} in {owner}")
            continue
        _check_xml_attributes(element, {"source", "destination", "priority", "alwaysInstall", "installIfUsable"}, {"source"}, errors, f"{owner}[{index}]")
        try:
            source = _relative_path(element.attrib.get("source", ""), f"{owner}[{index}].source")
            destination_raw = element.attrib["destination"] if "destination" in element.attrib else source
            destination = _relative_path(destination_raw, f"{owner}[{index}].destination", allow_empty=True)
        except ValidationError as exc:
            errors.append(str(exc)); continue
        result.append({
            "kind": tag,
            "source": source,
            "destination": destination,
            "priority": _parse_int_attr(element.attrib.get("priority"), f"{owner}[{index}].priority", errors),
            "always_install": _parse_bool_attr(element.attrib.get("alwaysInstall"), f"{owner}[{index}].alwaysInstall", errors),
            "install_if_usable": _parse_bool_attr(element.attrib.get("installIfUsable"), f"{owner}[{index}].installIfUsable", errors),
            "owner": owner,
        })
    return result


def validate_fomod(root: Path, *, strict_coverage: bool = True) -> dict[str, Any]:
    root = root.resolve(strict=True)
    if not root.is_dir():
        raise ValidationError("FOMOD root must be a directory")
    errors: list[str] = []
    warnings: list[str] = []
    module_path = _find_casefold(root, "fomod", "ModuleConfig.xml")
    info_path = _find_casefold(root, "fomod", "info.xml")
    fomod_dir = _find_casefold(root, "fomod")
    if not fomod_dir:
        return asdict(FomodReport("FAIL", str(root), "", "", ["fomod directory is missing"], [], {}, [], [], [], [], [], "FOMOD 5.0 structural, semantic, source-coverage, and branch metadata validation. Manager execution remains external."))
    if not module_path or not module_path.is_file():
        errors.append("fomod/ModuleConfig.xml is missing")
    if not info_path or not info_path.is_file():
        errors.append("fomod/info.xml is missing")
    csharp_files = [path.relative_to(root).as_posix() for path in fomod_dir.rglob("*.cs") if path.is_file()]
    if csharp_files:
        errors.append("C# scripted FOMOD installers are not supported by Forge because they permit arbitrary code execution")
    if errors:
        return asdict(FomodReport("FAIL", str(root), str(module_path or ""), str(info_path or ""), errors, warnings, {}, [], [], [], [], [], "FOMOD 5.0 structural, semantic, source-coverage, and branch metadata validation. Manager execution remains external."))
    try:
        config_root = ET.parse(module_path).getroot()
    except (ET.ParseError, OSError) as exc:
        errors.append(f"ModuleConfig.xml parse failure: {exc}")
        config_root = ET.Element("invalid")
    try:
        info_root = ET.parse(info_path).getroot()
    except (ET.ParseError, OSError) as exc:
        errors.append(f"info.xml parse failure: {exc}")
        info_root = ET.Element("invalid")
    if _tag(config_root) != "config":
        errors.append("ModuleConfig.xml root element must be config")
    if _tag(info_root) != "fomod":
        errors.append("info.xml root element must be fomod")
    # `xsi:noNamespaceSchemaLocation` is an optional XML *hint*. Nothing in
    # ModConfig5.0.xsd requires it and no mod manager reads it, so treating it
    # as mandatory failed installers that Vortex and MO2 install without
    # complaint - including every FOMOD that simply omits the attribute or
    # spells the URL with https. It is reported, not enforced.
    schema_attribute = f"{{{XSI}}}noNamespaceSchemaLocation"
    declared_schema = config_root.attrib.get(schema_attribute)
    if declared_schema is None:
        warnings.append("ModuleConfig.xml declares no xsi:noNamespaceSchemaLocation; the canonical token is "
                        f"{SCHEMA_LOCATION!r}. Managers do not require it.")
    elif declared_schema.strip().rstrip("/") not in _ACCEPTED_SCHEMA_LOCATIONS:
        warnings.append(f"ModuleConfig.xml declares an unrecognized schema location {declared_schema!r}; "
                        f"the canonical token is {SCHEMA_LOCATION!r}. Structure is validated regardless.")
    unknown_root_attributes = set(config_root.attrib) - {schema_attribute}
    if unknown_root_attributes:
        errors.append(f"config has unsupported attributes: {sorted(unknown_root_attributes)}")
    children = list(config_root)
    last_order = -1
    seen_top: set[str] = set()
    for child in children:
        tag = _tag(child)
        if tag not in TOP_LEVEL_ORDER:
            errors.append(f"Unsupported top-level ModuleConfig element: {tag}")
            continue
        order = TOP_LEVEL_ORDER[tag]
        if order < last_order:
            errors.append(f"ModuleConfig element order is invalid near {tag}")
        last_order = max(last_order, order)
        if tag in seen_top:
            errors.append(f"Duplicate top-level ModuleConfig element: {tag}")
        seen_top.add(tag)
    module_names = [child for child in children if _tag(child) == "moduleName"]
    if len(module_names) != 1 or not (module_names[0].text or "").strip():
        errors.append("ModuleConfig must contain exactly one non-empty moduleName")
    elif module_names:
        _check_xml_attributes(module_names[0], {"position", "colour"}, set(), errors, "moduleName")
        position = module_names[0].attrib.get("position", "Left")
        colour = module_names[0].attrib.get("colour", "")
        if position not in {"Left", "Right", "RightOfImage"}:
            errors.append("moduleName.position must be Left, Right, or RightOfImage")
        if colour and not re.fullmatch(r"#?[0-9A-Fa-f]{6}", colour):
            errors.append("moduleName.colour must be a six-digit RGB hex value")
    module_images = [child for child in children if _tag(child) == "moduleImage"]
    if module_images:
        image = module_images[0]
        _check_xml_attributes(image, {"path", "showImage", "showFade", "height"}, set(), errors, "moduleImage")
        for attribute in ("showImage", "showFade"):
            if attribute in image.attrib:
                _parse_bool_attr(image.attrib.get(attribute), f"moduleImage.{attribute}", errors)
        if "height" in image.attrib:
            height = _parse_int_attr(image.attrib.get("height"), "moduleImage.height", errors)
            if height < -1:
                errors.append("moduleImage.height must be -1 or greater")
    _check_xml_attributes(info_root, set(), set(), errors, "info.xml fomod root")
    info_allowed = {"Name", "Author", "Version", "Description", "Website", "Id", "CategoryId", "Groups"}
    info_children: dict[str, list[ET.Element]] = {}
    for child in info_root:
        tag = _tag(child)
        info_children.setdefault(tag, []).append(child)
        if tag not in info_allowed:
            warnings.append(f"info.xml contains unrecognized metadata element {tag!r}; manager behavior may vary")
    for tag in info_allowed - {"Groups"}:
        if len(info_children.get(tag, [])) > 1:
            errors.append(f"info.xml contains duplicate {tag} elements")
    info_names = info_children.get("Name", [])
    if not info_names:
        warnings.append("info.xml has no Name metadata")
    elif not (info_names[0].text or "").strip():
        warnings.append("info.xml Name metadata is empty")
    info_versions = info_children.get("Version", [])
    if not info_versions:
        warnings.append("info.xml has no Version metadata")
    else:
        _check_xml_attributes(info_versions[0], {"MachineVersion"}, set(), errors, "info.xml Version")
        if not (info_versions[0].text or "").strip():
            warnings.append("info.xml Version metadata is empty")
        if info_versions[0].attrib.get("MachineVersion"):
            try:
                _version_tuple(info_versions[0].attrib["MachineVersion"])
            except ValidationError as exc:
                errors.append(str(exc))
    for tag in {"Name", "Author", "Description", "Website", "Id", "CategoryId"}:
        for node in info_children.get(tag, []):
            _check_xml_attributes(node, set(), set(), errors, f"info.xml {tag}")
            if list(node):
                errors.append(f"info.xml {tag} must not contain child elements")
    groups_nodes = info_children.get("Groups", [])
    if len(groups_nodes) > 1:
        errors.append("info.xml contains duplicate Groups elements")
    if groups_nodes:
        _check_xml_attributes(groups_nodes[0], set(), set(), errors, "info.xml Groups")
        for index, category in enumerate(groups_nodes[0]):
            if _tag(category) != "element":
                errors.append(f"info.xml Groups contains unsupported element {_tag(category)!r}")
                continue
            _check_xml_attributes(category, set(), set(), errors, f"info.xml Groups.element[{index}]")
            if not (category.text or "").strip():
                warnings.append(f"info.xml Groups.element[{index}] is empty")

    normalized = {
        "schema": PLAN_SCHEMA,
        "module": {"name": (module_names[0].text or "").strip() if module_names else "", "author": "", "version": "0", "machine_version": "0", "description": "", "website": "", "image": "", "id": "", "category_id": "", "groups": [], "name_position": "Left", "name_colour": "", "image_show": True, "image_fade": True, "image_height": -1},
        "module_dependencies": None,
        "required_files": [],
        "steps": [],
        "steps_order": "Explicit",
        "conditional_files": [],
        "xml_encoding": "utf-8",
        "strict_coverage": strict_coverage,
    }
    if info_names:
        normalized["module"]["name"] = (info_names[0].text or "").strip() or normalized["module"]["name"]
    for tag, key in (("Author", "author"), ("Description", "description"), ("Website", "website"), ("Id", "id"), ("CategoryId", "category_id")):
        nodes = info_children.get(tag, [])
        if nodes:
            normalized["module"][key] = (nodes[0].text or "").strip()
    if info_versions:
        normalized["module"]["version"] = (info_versions[0].text or "").strip() or "0"
        normalized["module"]["machine_version"] = info_versions[0].attrib.get("MachineVersion", "") or normalized["module"]["version"]
    if groups_nodes:
        normalized["module"]["groups"] = [(node.text or "").strip() for node in groups_nodes[0] if _tag(node) == "element" and (node.text or "").strip()]

    defined_flags: set[str] = set()
    referenced_flags: set[str] = set()
    counts = {"steps": 0, "groups": 0, "plugins": 0, "mappings": 0, "conditional_patterns": 0, "dependencies": 0}
    for child in children:
        tag = _tag(child)
        if tag == "moduleImage":
            if child.attrib.get("path"):
                try:
                    normalized["module"]["image"] = _relative_path(child.attrib.get("path", ""), "moduleImage.path")
                except ValidationError as exc:
                    errors.append(str(exc))
            normalized["module"]["image_show"] = _parse_bool_attr(child.attrib.get("showImage"), "moduleImage.showImage", errors) if "showImage" in child.attrib else True
            normalized["module"]["image_fade"] = _parse_bool_attr(child.attrib.get("showFade"), "moduleImage.showFade", errors) if "showFade" in child.attrib else True
            normalized["module"]["image_height"] = _parse_int_attr(child.attrib.get("height"), "moduleImage.height", errors) if "height" in child.attrib else -1
        elif tag == "moduleDependencies":
            _check_xml_attributes(child, {"operator"}, set(), errors, "moduleDependencies")
            normalized["module_dependencies"] = _xml_dependency(child, errors, referenced_flags, "moduleDependencies", warnings=warnings)
        elif tag == "requiredInstallFiles":
            _check_xml_attributes(child, set(), set(), errors, "requiredInstallFiles")
            normalized["required_files"] = _xml_mappings(child, errors, "required")
            if not normalized["required_files"]:
                errors.append("requiredInstallFiles must contain at least one file or folder")
        elif tag == "installSteps":
            _check_xml_attributes(child, {"order"}, set(), errors, "installSteps")
            order = child.attrib.get("order", "Ascending")
            normalized["steps_order"] = order
            if order not in ORDER_VALUES:
                errors.append(f"installSteps.order must be one of {sorted(ORDER_VALUES)}")
            for si, step_element in enumerate(child):
                if _tag(step_element) != "installStep":
                    errors.append(f"installSteps contains unsupported element {_tag(step_element)}")
                    continue
                _check_xml_attributes(step_element, {"name"}, {"name"}, errors, f"installStep[{si}]")
                step_name = step_element.attrib.get("name", "").strip()
                if not step_name:
                    errors.append(f"installStep[{si}] has no name")
                step = {"name": step_name, "visible": None, "groups_order": "Explicit", "groups": []}
                step_children = list(step_element)
                step_tags = [_tag(node) for node in step_children]
                if step_tags not in (["optionalFileGroups"], ["visible", "optionalFileGroups"]):
                    errors.append(f"installStep {step_name} child order must be optional visible followed by optionalFileGroups")
                if step_children and _tag(step_children[0]) == "visible":
                    _check_xml_attributes(step_children[0], {"operator"}, set(), errors, f"installStep {step_name}.visible")
                    step["visible"] = _xml_dependency(step_children[0], errors, referenced_flags, f"step:{step_name}.visible", warnings=warnings)
                groups_nodes = [node for node in step_children if _tag(node) == "optionalFileGroups"]
                if len(groups_nodes) != 1:
                    errors.append(f"installStep {step_name} must contain exactly one optionalFileGroups")
                    continue
                groups_node = groups_nodes[0]
                _check_xml_attributes(groups_node, {"order"}, set(), errors, f"optionalFileGroups:{step_name}")
                step["groups_order"] = groups_node.attrib.get("order", "Explicit")
                if step["groups_order"] not in ORDER_VALUES:
                    errors.append(f"optionalFileGroups.order in {step_name} is invalid")
                for gi, group_element in enumerate(groups_node):
                    if _tag(group_element) != "group":
                        errors.append(f"optionalFileGroups contains unsupported element {_tag(group_element)}")
                        continue
                    _check_xml_attributes(group_element, {"name", "type"}, {"name", "type"}, errors, f"group[{gi}] in {step_name}")
                    group_name = group_element.attrib.get("name", "").strip()
                    group_type = group_element.attrib.get("type", "")
                    if not group_name:
                        errors.append(f"group[{gi}] in {step_name} has no name")
                    if group_type not in GROUP_TYPES:
                        errors.append(f"group {step_name}/{group_name} has invalid type {group_type!r}")
                    plugins_nodes = [node for node in group_element if _tag(node) == "plugins"]
                    if len(plugins_nodes) != 1:
                        errors.append(f"group {step_name}/{group_name} must contain exactly one plugins element")
                        continue
                    plugins_node = plugins_nodes[0]
                    _check_xml_attributes(plugins_node, {"order"}, set(), errors, f"plugins:{step_name}/{group_name}")
                    plugins_order = plugins_node.attrib.get("order", "Explicit")
                    if plugins_order not in ORDER_VALUES:
                        errors.append(f"plugins.order in {step_name}/{group_name} is invalid")
                    group = {"name": group_name, "type": group_type, "plugins_order": plugins_order, "plugins": []}
                    for pi, plugin_element in enumerate(plugins_node):
                        if _tag(plugin_element) != "plugin":
                            errors.append(f"plugins contains unsupported element {_tag(plugin_element)}")
                            continue
                        _check_xml_attributes(plugin_element, {"name"}, {"name"}, errors, f"plugin[{pi}] in {step_name}/{group_name}")
                        plugin_name = plugin_element.attrib.get("name", "").strip()
                        if not plugin_name:
                            errors.append(f"plugin[{pi}] in {step_name}/{group_name} has no name")
                        plugin = {"name": plugin_name, "description": "", "image": "", "files": [], "files_present": False, "flags": {}, "type": {"type": "Optional"}}
                        descriptors = []
                        plugin_tags = [_tag(node) for node in plugin_element]
                        if not plugin_tags or plugin_tags[0] != "description" or plugin_tags[-1] != "typeDescriptor":
                            errors.append(f"plugin {step_name}/{group_name}/{plugin_name} must begin with description and end with typeDescriptor")
                        # ModConfig5.0.xsd plugin sequence is:
                        #   description, image?, (files, conditionFlags?
                        #                         | conditionFlags, files?), typeDescriptor
                        # The optional image sits between description and the
                        # choice. Omitting it here rejected every option that
                        # carries a screenshot, which is most real installers.
                        middle = plugin_tags[1:-1]
                        if middle[:1] == ["image"]:
                            middle = middle[1:]
                        valid_middle = middle in (["files"], ["conditionFlags"], ["files", "conditionFlags"], ["conditionFlags", "files"])
                        if not valid_middle:
                            errors.append(f"plugin {step_name}/{group_name}/{plugin_name} must contain files or conditionFlags in ModuleConfig 5.0 order")
                        for node in plugin_element:
                            node_tag = _tag(node)
                            if node_tag == "description":
                                _check_xml_attributes(node, set(), set(), errors, f"plugin:{plugin_name}.description")
                                plugin["description"] = node.text or ""
                            elif node_tag == "image":
                                _check_xml_attributes(node, {"path"}, {"path"}, errors, f"plugin:{plugin_name}.image")
                                try:
                                    plugin["image"] = _relative_path(node.attrib.get("path", ""), f"plugin:{plugin_name}.image")
                                except ValidationError as exc:
                                    errors.append(str(exc))
                            elif node_tag == "files":
                                _check_xml_attributes(node, set(), set(), errors, f"plugin:{plugin_name}.files")
                                plugin["files_present"] = True
                                mapped = _xml_mappings(node, errors, f"plugin:{step_name}/{group_name}/{plugin_name}")
                                plugin["files"].extend(mapped)
                            elif node_tag == "conditionFlags":
                                _check_xml_attributes(node, set(), set(), errors, f"plugin:{plugin_name}.conditionFlags")
                                if not list(node):
                                    errors.append(f"plugin {plugin_name} contains an empty conditionFlags element")
                                for flag in node:
                                    if _tag(flag) != "flag":
                                        errors.append(f"conditionFlags contains unsupported element {_tag(flag)}")
                                        continue
                                    _check_xml_attributes(flag, {"name"}, {"name"}, errors, f"plugin:{plugin_name}.flag")
                                    flag_name = flag.attrib.get("name", "").strip()
                                    flag_value = (flag.text or "").strip()
                                    if not flag_name or not flag_value:
                                        errors.append(f"plugin {plugin_name} contains empty condition flag")
                                    else:
                                        plugin["flags"][flag_name] = flag_value
                                        defined_flags.add(flag_name)
                            elif node_tag == "typeDescriptor":
                                _check_xml_attributes(node, set(), set(), errors, f"plugin:{plugin_name}.typeDescriptor")
                                descriptors.append(node)
                            else:
                                errors.append(f"plugin {plugin_name} contains unsupported element {node_tag}")
                        if len(descriptors) != 1:
                            errors.append(f"plugin {step_name}/{group_name}/{plugin_name} must contain exactly one typeDescriptor")
                        else:
                            descriptor_children = list(descriptors[0])
                            if len(descriptor_children) != 1:
                                errors.append(f"plugin {plugin_name} typeDescriptor must contain exactly one child")
                            elif _tag(descriptor_children[0]) == "type":
                                _check_xml_attributes(descriptor_children[0], {"name"}, {"name"}, errors, f"plugin:{plugin_name}.type")
                                type_name = descriptor_children[0].attrib.get("name", "")
                                if type_name not in PLUGIN_TYPES:
                                    errors.append(f"plugin {plugin_name} has invalid type {type_name!r}")
                                plugin["type"] = {"type": type_name}
                            elif _tag(descriptor_children[0]) == "dependencyType":
                                dynamic = descriptor_children[0]
                                _check_xml_attributes(dynamic, set(), set(), errors, f"plugin:{plugin_name}.dependencyType")
                                if [_tag(node) for node in dynamic] != ["defaultType", "patterns"]:
                                    errors.append(f"plugin {plugin_name} dependencyType child order must be defaultType then patterns")
                                defaults = [node for node in dynamic if _tag(node) == "defaultType"]
                                patterns_nodes = [node for node in dynamic if _tag(node) == "patterns"]
                                if defaults:
                                    _check_xml_attributes(defaults[0], {"name"}, {"name"}, errors, f"plugin:{plugin_name}.defaultType")
                                if len(defaults) != 1 or defaults[0].attrib.get("name") not in PLUGIN_TYPES:
                                    errors.append(f"plugin {plugin_name} dependencyType has invalid defaultType")
                                patterns = []
                                if len(patterns_nodes) != 1:
                                    errors.append(f"plugin {plugin_name} dependencyType must contain one patterns element")
                                else:
                                    for pattern_index, pattern_element in enumerate(patterns_nodes[0]):
                                        if _tag(pattern_element) != "pattern":
                                            errors.append(f"dependencyType patterns contains unsupported {_tag(pattern_element)}")
                                            continue
                                        _check_xml_attributes(pattern_element, set(), set(), errors, f"plugin:{plugin_name}.pattern[{pattern_index}]")
                                        if [_tag(node) for node in pattern_element] != ["dependencies", "type"]:
                                            errors.append(f"plugin {plugin_name} pattern[{pattern_index}] child order must be dependencies then type")
                                        deps = [node for node in pattern_element if _tag(node) == "dependencies"]
                                        types = [node for node in pattern_element if _tag(node) == "type"]
                                        if len(deps) != 1 or len(types) != 1:
                                            errors.append(f"plugin {plugin_name} pattern[{pattern_index}] must contain dependencies then type")
                                            continue
                                        _check_xml_attributes(deps[0], {"operator"}, set(), errors, f"plugin:{plugin_name}.pattern[{pattern_index}].dependencies")
                                        _check_xml_attributes(types[0], {"name"}, {"name"}, errors, f"plugin:{plugin_name}.pattern[{pattern_index}].type")
                                        type_name = types[0].attrib.get("name", "")
                                        if type_name not in PLUGIN_TYPES:
                                            errors.append(f"plugin {plugin_name} pattern[{pattern_index}] has invalid type {type_name!r}")
                                        patterns.append({"dependencies": _xml_dependency(deps[0], errors, referenced_flags, f"plugin:{plugin_name}.pattern[{pattern_index}]", warnings=warnings), "type": type_name})
                                plugin["type"] = {"default": defaults[0].attrib.get("name", "") if defaults else "", "patterns": patterns}
                            else:
                                errors.append(f"plugin {plugin_name} has unsupported typeDescriptor child {_tag(descriptor_children[0])}")
                        group["plugins"].append(plugin)
                        counts["plugins"] += 1
                    if not group["plugins"]:
                        errors.append(f"group {step_name}/{group_name} contains no plugins")
                    step["groups"].append(group)
                    counts["groups"] += 1
                normalized["steps"].append(step)
                counts["steps"] += 1
        elif tag == "conditionalFileInstalls":
            _check_xml_attributes(child, set(), set(), errors, "conditionalFileInstalls")
            patterns_nodes = [node for node in child if _tag(node) == "patterns"]
            if len(patterns_nodes) != 1:
                errors.append("conditionalFileInstalls must contain exactly one patterns element")
                continue
            if patterns_nodes:
                _check_xml_attributes(patterns_nodes[0], set(), set(), errors, "conditionalFileInstalls.patterns")
                if not list(patterns_nodes[0]):
                    errors.append("conditionalFileInstalls.patterns must contain at least one pattern")
            for ci, pattern_element in enumerate(patterns_nodes[0] if patterns_nodes else []):
                if _tag(pattern_element) != "pattern":
                    errors.append(f"conditional patterns contains unsupported {_tag(pattern_element)}")
                    continue
                _check_xml_attributes(pattern_element, set(), set(), errors, f"conditional.pattern[{ci}]")
                if [_tag(node) for node in pattern_element] != ["dependencies", "files"]:
                    errors.append(f"conditional pattern[{ci}] child order must be dependencies then files")
                deps = [node for node in pattern_element if _tag(node) == "dependencies"]
                files = [node for node in pattern_element if _tag(node) == "files"]
                if len(deps) != 1 or len(files) != 1:
                    errors.append(f"conditional pattern[{ci}] must contain dependencies and files")
                    continue
                _check_xml_attributes(deps[0], {"operator"}, set(), errors, f"conditional[{ci}].dependencies")
                _check_xml_attributes(files[0], set(), set(), errors, f"conditional[{ci}].files")
                mapped_files = _xml_mappings(files[0], errors, f"conditional:{ci}")
                if not mapped_files:
                    errors.append(f"conditional pattern[{ci}] files must not be empty")
                normalized["conditional_files"].append({"dependencies": _xml_dependency(deps[0], errors, referenced_flags, f"conditional[{ci}]", warnings=warnings), "files": mapped_files})
                counts["conditional_patterns"] += 1
    if not normalized["module_dependencies"] and not normalized["required_files"] and not normalized["steps"] and not normalized["conditional_files"]:
        errors.append("FOMOD has no dependencies, required files, install steps, or conditional files and would have no installation effect")
    unknown_flags = sorted(referenced_flags - defined_flags)
    if unknown_flags:
        errors.append(f"FOMOD dependencies reference undefined condition flags: {unknown_flags}")
    module_flag_refs = sorted(_dependency_flags(normalized["module_dependencies"]))
    if module_flag_refs:
        errors.append(f"moduleDependencies cannot reference selection flags before installation begins: {module_flag_refs}")
    available_flags: set[str] = set()
    for step in normalized["steps"]:
        early_refs = _dependency_flags(step["visible"])
        for group in step["groups"]:
            for plugin in group["plugins"]:
                if "patterns" in plugin["type"]:
                    for pattern in plugin["type"]["patterns"]:
                        early_refs.update(_dependency_flags(pattern["dependencies"]))
        unavailable = sorted(early_refs - available_flags)
        if unavailable:
            errors.append(f"Install step {step['name']!r} references condition flags not defined by earlier steps: {unavailable}")
        for group in step["groups"]:
            static_required = [plugin["name"] for plugin in group["plugins"] if plugin["type"] == {"type": "Required"}]
            if group["type"] in {"SelectExactlyOne", "SelectAtMostOne"} and len(static_required) > 1:
                errors.append(f"Group {step['name']}/{group['name']} has multiple Required plugins but permits at most one selection")
            for plugin in group["plugins"]:
                available_flags.update(plugin["flags"])
    counts["mappings"] = len(_mapping_objects(normalized))
    analysis = analyze_plan_files(normalized, root, strict_coverage=strict_coverage)
    errors.extend(analysis["errors"])
    warnings.extend(analysis["warnings"])
    return asdict(FomodReport(
        "PASS" if not errors else "FAIL", str(root), str(module_path), str(info_path), sorted(set(errors)), sorted(set(warnings)), counts,
        analysis["missing_sources"], analysis["unreferenced_payload"], analysis["destination_collisions"], sorted(defined_flags), sorted(referenced_flags),
        "FOMOD ModuleConfig 5.0 schema-shape, structural, semantic, source-coverage, destination-collision, temporal flag-reference, and XML-order validation. Actual Vortex/MO2 execution remains an external gate.",
    ))


def build_fomod(plan_path: Path, source_root: Path, output_root: Path, workspace_root: Path, *, approved: bool) -> dict[str, Any]:
    require_approval(approved, "FOMOD installer generation")
    plan_path = plan_path.resolve(strict=True)
    source_root = source_root.resolve(strict=True)
    output_root = require_within(output_root, workspace_root)
    if output_root.exists():
        raise SafetyError(f"Refusing to overwrite FOMOD output tree: {output_root}")
    plan = validate_plan(plan_path, source_root)
    transaction_parent = output_root.parent
    transaction_parent.mkdir(parents=True, exist_ok=True)
    transaction = Path(tempfile.mkdtemp(prefix=f".{output_root.name}.forge-fomod-", dir=transaction_parent))
    staged = transaction / output_root.name
    try:
        shutil.copytree(source_root, staged, symlinks=False)
        config_tree, info_tree = plan_to_xml(plan)
        fomod_dir = staged / "fomod"
        _write_xml(config_tree, fomod_dir / "ModuleConfig.xml")
        _write_xml(info_tree, fomod_dir / "info.xml")
        report = validate_fomod(staged, strict_coverage=plan["strict_coverage"])
        if report["result"] != "PASS":
            raise ValidationError("Generated FOMOD failed validation: " + "; ".join(report["errors"]))
        os.replace(staged, output_root)
    finally:
        shutil.rmtree(transaction, ignore_errors=True)
    return {
        "result": "PASS",
        "output": str(output_root),
        "module_config": str(output_root / "fomod" / "ModuleConfig.xml"),
        "info_xml": str(output_root / "fomod" / "info.xml"),
        "validation": validate_fomod(output_root, strict_coverage=plan["strict_coverage"]),
        "plan_sha256": sha256_file(plan_path),
        "evidence": "Typed FOMOD plan generated transactionally, reopened, and validated. Vortex and MO2 UI execution remains external.",
    }


def scaffold_plan(source_root: Path, module_name: str, version: str = "1.0.0") -> dict[str, Any]:
    source_root = source_root.resolve(strict=True)
    _version_tuple(version)
    mappings = []
    children = sorted(source_root.iterdir(), key=lambda path: path.name.casefold())
    payload_children = [child for child in children if child.name.casefold() != "fomod" and not child.is_symlink()]
    if len(payload_children) == 1 and payload_children[0].is_dir() and payload_children[0].name.casefold() == "data":
        mappings.append({"kind": "folder", "source": payload_children[0].name, "destination": "", "priority": 0, "always_install": True, "install_if_usable": False})
        payload_children = []
    for child in payload_children:
        if child.name.casefold() == "fomod" or child.is_symlink():
            continue
        name = child.name
        if child.is_file() and name.casefold() in ROOT_DOC_NAMES:
            continue
        if child.is_file() and (name.casefold().startswith("readme.") or name.casefold().startswith("license.") or name.casefold().startswith("changelog.")):
            continue
        mappings.append({
            "kind": "folder" if child.is_dir() else "file",
            "source": name,
            "destination": name if child.is_file() else name,
            "priority": 0,
            "always_install": True,
            "install_if_usable": False,
        })
    return {
        "schema": PLAN_SCHEMA,
        "module": {"name": module_name, "author": "", "version": version, "machine_version": version, "description": "", "website": "", "image": "", "id": "", "category_id": "", "groups": [], "name_position": "Left", "name_colour": "", "image_show": True, "image_fade": True, "image_height": -1},
        "module_dependencies": None,
        "required_files": mappings,
        "steps": [],
        "steps_order": "Explicit",
        "conditional_files": [],
        "xml_encoding": "utf-8",
        "strict_coverage": True,
    }


def write_scaffold(source_root: Path, output_plan: Path, workspace_root: Path, module_name: str, version: str, *, approved: bool) -> dict[str, Any]:
    require_approval(approved, "FOMOD scaffold creation")
    output_plan = require_within(output_plan, workspace_root)
    if output_plan.exists():
        raise SafetyError(f"Refusing to overwrite FOMOD plan: {output_plan}")
    plan = scaffold_plan(source_root, module_name, version)
    validate_plan_data(plan, source_root)
    import json
    output_plan.parent.mkdir(parents=True, exist_ok=True)
    atomic_write_text(output_plan, json.dumps(plan, indent=2, ensure_ascii=False) + "\n")
    return {"result": "PASS", "output": str(output_plan), "required_entries": len(plan["required_files"]), "source_root": str(source_root.resolve(strict=True))}


def _evaluate_dependency(dependency: dict[str, Any] | None, state: dict[str, Any], flags: dict[str, str]) -> bool:
    if dependency is None:
        return True
    key, raw = next(iter(dependency.items()))
    if key == "all":
        return all(_evaluate_dependency(item, state, flags) for item in raw)
    if key == "any":
        return any(_evaluate_dependency(item, state, flags) for item in raw)
    if key == "flag":
        return flags.get(raw["name"]) == raw["value"]
    if key == "file":
        actual = state.get("files", {}).get(raw["path"], "Missing")
        return actual == raw["state"]
    if key == "game_version":
        actual = str(state.get("game_version", "0"))
        return _version_at_least(actual, raw)
    if key == "fomm_version":
        actual = str(state.get("fomm_version", "0"))
        return _version_at_least(actual, raw)
    raise AssertionError(key)


def _effective_plugin_type(descriptor: dict[str, Any], state: dict[str, Any], flags: dict[str, str]) -> str:
    if "type" in descriptor:
        return descriptor["type"]
    for pattern in descriptor["patterns"]:
        if _evaluate_dependency(pattern["dependencies"], state, flags):
            return pattern["type"]
    return descriptor["default"]


def simulate_plan(plan_data: Any, selections: dict[str, Any] | None = None, state: dict[str, Any] | None = None, source_root: Path | None = None) -> dict[str, Any]:
    plan = validate_plan_data(plan_data, source_root)
    selections = selections or {}
    state = state or {}
    if not isinstance(selections, dict) or not isinstance(state, dict):
        raise ValidationError("selections and state must be objects")
    flags: dict[str, str] = {}
    selected_plugins: list[str] = []
    skipped_steps: list[str] = []
    mappings: list[dict[str, Any]] = list(plan["required_files"])
    errors: list[str] = []
    for step in plan["steps"]:
        if not _evaluate_dependency(step["visible"], state, flags):
            skipped_steps.append(step["name"])
            continue
        for group in step["groups"]:
            key = f"{step['name']}/{group['name']}"
            explicit = selections.get(key)
            effective_types = {plugin["name"]: _effective_plugin_type(plugin["type"], state, flags) for plugin in group["plugins"]}
            required_names = {name for name, plugin_type in effective_types.items() if plugin_type == "Required"}
            if explicit is None:
                chosen = [name for name, plugin_type in effective_types.items() if plugin_type in {"Required", "Recommended"}]
            else:
                if isinstance(explicit, str):
                    chosen = [explicit]
                elif isinstance(explicit, list) and all(isinstance(item, str) for item in explicit):
                    chosen = explicit
                else:
                    raise ValidationError(f"Selection {key!r} must be a string or string array")
                chosen = list(dict.fromkeys([*chosen, *sorted(required_names, key=str.casefold)]))
            available = {plugin["name"]: plugin for plugin in group["plugins"]}
            unknown = sorted(set(chosen) - set(available))
            if unknown:
                errors.append(f"Selection {key!r} contains unknown plugin(s): {unknown}")
                continue
            count = len(set(chosen))
            if group["type"] == "SelectExactlyOne" and count != 1:
                errors.append(f"Selection {key!r} requires exactly one plugin")
            elif group["type"] == "SelectAtMostOne" and count > 1:
                errors.append(f"Selection {key!r} permits at most one plugin")
            elif group["type"] == "SelectAtLeastOne" and count < 1:
                errors.append(f"Selection {key!r} requires at least one plugin")
            elif group["type"] == "SelectAll" and set(chosen) != set(available):
                errors.append(f"Selection {key!r} requires all plugins")
            for name in chosen:
                plugin = available[name]
                plugin_type = _effective_plugin_type(plugin["type"], state, flags)
                if plugin_type == "NotUsable":
                    errors.append(f"Selection {key!r}/{name} is NotUsable under the supplied state")
                    continue
                selected_plugins.append(f"{key}/{name}")
                mappings.extend(plugin["files"])
                flags.update(plugin["flags"])
            selected_set = set(chosen)
            for name, plugin in available.items():
                if name in selected_set:
                    continue
                plugin_type = effective_types[name]
                mappings.extend(mapping for mapping in plugin["files"] if mapping["always_install"] or (mapping["install_if_usable"] and plugin_type != "NotUsable"))
    for pattern in plan["conditional_files"]:
        if _evaluate_dependency(pattern["dependencies"], state, flags):
            mappings.extend(pattern["files"])
    normalized = copy.deepcopy(plan)
    normalized["required_files"] = mappings
    normalized["steps"] = []
    normalized["conditional_files"] = []
    file_analysis = analyze_plan_files(normalized, source_root, strict_coverage=False) if source_root else {"result": "NOT-RUN", "errors": [], "warnings": [], "destination_collisions": []}
    errors.extend(file_analysis.get("errors", []))
    return {
        "result": "PASS" if not errors else "FAIL",
        "selected_plugins": selected_plugins,
        "skipped_steps": skipped_steps,
        "flags": flags,
        "mapping_count": len(mappings),
        "file_analysis": file_analysis,
        "errors": errors,
        "evidence": "Deterministic FOMOD branch simulation against explicit selections, flags, file states, and version state. Manager UI behavior remains external.",
    }


def self_test() -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="forge-fomod-self-test-") as td:
        root = Path(td)
        source = root / "source"
        source.mkdir()
        core = source / "00 Core" / "SKSE" / "Plugins"
        core.mkdir(parents=True)
        (core / "fixture.dll").write_bytes(b"fixture")
        plan_data = {
            "schema": PLAN_SCHEMA,
            "module": {"name": "Forge FOMOD Self-Test", "version": "1.0.0"},
            "required_files": [{"kind": "folder", "source": "00 Core", "destination": "", "always_install": True}],
            "strict_coverage": True,
        }
        plan = validate_plan_data(plan_data, source)
        config_tree, info_tree = plan_to_xml(plan)
        _write_xml(config_tree, source / "fomod" / "ModuleConfig.xml", plan["xml_encoding"])
        _write_xml(info_tree, source / "fomod" / "info.xml", plan["xml_encoding"])
        report = validate_fomod(source, strict_coverage=True)
        assertions = {
            "typed_plan": plan["schema"] == PLAN_SCHEMA,
            "generated_xml": (source / "fomod" / "ModuleConfig.xml").is_file(),
            "strict_validation": report["result"] == "PASS",
        }
        return {"result": "PASS" if all(assertions.values()) else "FAIL", "assertions": assertions, "validation": report}
