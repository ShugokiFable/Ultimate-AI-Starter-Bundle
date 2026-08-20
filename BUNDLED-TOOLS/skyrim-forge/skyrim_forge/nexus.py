from __future__ import annotations

import fnmatch
import json
import os
import re
import shutil
import tempfile
from datetime import date, datetime, timezone
from pathlib import Path, PurePosixPath
from typing import Any
from urllib.parse import urlparse

from .errors import SafetyError, ValidationError
from .release import build_release, validate_release_tree
from .safety import require_approval, require_within
from .strictjson import load
from .util import atomic_write_text, iter_files, json_dump, safe_name, sha256_file, validate_semver

PLAN_SCHEMA = "skyrim-forge-nexus-publication-plan/1"
POLICY_REVIEW_MAX_AGE_DAYS = 90
OFFICIAL_POLICY_HOST = "help.nexusmods.com"
REQUIRED_POLICIES = {
    "terms": "https://help.nexusmods.com/article/18-terms-of-service",
    "file_submission": "https://help.nexusmods.com/article/28-file-submission-guidelines",
    "adult_content": "https://help.nexusmods.com/article/19-adult-content-guidelines",
    "donation_points": "https://help.nexusmods.com/article/68-donation-points-system-terms-of-service",
    "best_practices": "https://help.nexusmods.com/article/136-best-practices-for-mod-authors",
}
PERMISSION_BASES = {
    "owned",
    "open_license",
    "explicit_permission",
    "nexus_permission",
    "game_terms",
    "dependency_not_bundled",
}
PROVENANCE = {
    "original",
    "commissioned",
    "open_source",
    "third_party_mod",
    "game_derived",
    "dependency_only",
    "generated",
}
ASSET_KINDS = {
    "plugin", "papyrus", "native_code", "executable", "mesh", "texture", "animation",
    "audio", "voice", "music", "image", "font", "documentation", "configuration",
    "translation", "archive", "other",
}
RIGHTS_VALUES = {"allowed", "not_allowed", "unknown", "not_applicable"}
RELEASE_TYPES = {"original_mod", "patch", "translation", "compilation", "utility", "modlist_support"}
PERMISSION_SETTING_VALUES = {"not_allowed", "permission_required", "allowed_with_credit", "allowed", "not_applicable"}
AI_AREAS = {"code", "documentation", "image", "texture", "mesh", "audio", "voice", "dialogue", "translation", "other"}
ADULT_KEYS = {
    "pornographic", "sexualised", "nudity", "extreme_violence", "swearing",
    "self_harm", "substance_use", "body_stigma", "other_adult",
}
DECLARATIONS = {
    "rights_and_permissions_complete",
    "credits_complete",
    "game_terms_reviewed",
    "nexus_upload_licence_understood",
    "public_distribution_intended",
    "uploader_age_eligibility_confirmed",
    "public_functional_release",
    "claims_verified",
    "no_pirated_or_original_game_files",
    "no_malware_or_harmful_payload",
    "no_password_or_placeholder_files",
    "no_prohibited_external_links",
    "no_illegal_content",
    "no_third_party_privacy_or_trademark_violation",
    "no_scraped_or_mined_nexus_content",
    "content_classification_complete",
    "privacy_review_complete",
}
KNOWN_GAME_FILE_NAMES = {
    "skyrim.esm", "update.esm", "dawnguard.esm", "hearthfires.esm", "dragonborn.esm",
    "skyrimse.exe", "skyrimlauncher.exe", "creationkit.exe", "papyruscompiler.exe",
    "steam_api64.dll", "bink2w64.dll",
}
KNOWN_GAME_ARCHIVE_PREFIXES = ("skyrim - ", "voices_", "shadersfx")
BINARY_SUFFIXES = {".exe", ".dll", ".sys", ".com", ".scr", ".msi"}
ARCHIVE_SUFFIXES = {".zip", ".7z", ".rar", ".tar", ".gz", ".bz2", ".xz"}
PERFORMANCE_CLAIM = re.compile(r"\b(?:fps|performance|faster|speed(?:up)?|optim(?:i[sz](?:e|ed|ation))|reduce[sd]?\s+(?:lag|stutter)|zero\s+lag)\b", re.I)
AGGRESSIVE_SOLICITATION = re.compile(r"\b(?:donate\s+now|must\s+donate|pay\s+me|endorse\s+now|must\s+endorse)\b", re.I)
PROHIBITED_LINK_HINT = re.compile(r"\b(?:pirate|crack|warez|torrent|mega\.nz|mediafire)\b", re.I)
LICENSE_COPY_REQUIRED = {"MIT", "BSD-2-CLAUSE", "BSD-3-CLAUSE", "ISC", "ZLIB", "APACHE-2.0", "GPL-2.0-ONLY", "GPL-2.0-OR-LATER", "GPL-3.0-ONLY", "GPL-3.0-OR-LATER", "AGPL-3.0-ONLY", "AGPL-3.0-OR-LATER", "LGPL-2.1-ONLY", "LGPL-2.1-OR-LATER", "LGPL-3.0-ONLY", "LGPL-3.0-OR-LATER", "MPL-2.0", "CC-BY-4.0", "CC-BY-SA-4.0", "CC0-1.0"}
SOURCE_REQUIRED = {"GPL-2.0-ONLY", "GPL-2.0-OR-LATER", "GPL-3.0-ONLY", "GPL-3.0-OR-LATER", "AGPL-3.0-ONLY", "AGPL-3.0-OR-LATER", "LGPL-2.1-ONLY", "LGPL-2.1-OR-LATER", "LGPL-3.0-ONLY", "LGPL-3.0-OR-LATER", "MPL-2.0"}
ATTRIBUTION_REQUIRED = {"MIT", "BSD-2-CLAUSE", "BSD-3-CLAUSE", "ISC", "ZLIB", "APACHE-2.0", "CC-BY-4.0", "CC-BY-SA-4.0"}
COPYLEFT_REVIEW = {"GPL-2.0-ONLY", "GPL-2.0-OR-LATER", "GPL-3.0-ONLY", "GPL-3.0-OR-LATER", "AGPL-3.0-ONLY", "AGPL-3.0-OR-LATER", "LGPL-2.1-ONLY", "LGPL-2.1-OR-LATER", "LGPL-3.0-ONLY", "LGPL-3.0-OR-LATER", "MPL-2.0", "CC-BY-SA-4.0"}


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


def _text(value: Any, label: str, *, required: bool = True) -> str:
    if value is None and not required:
        return ""
    if not isinstance(value, str):
        raise ValidationError(f"{label} must be a string")
    result = value.strip()
    if required and not result:
        raise ValidationError(f"{label} must not be empty")
    if "\x00" in result:
        raise ValidationError(f"{label} contains a NUL byte")
    return result


def _boolean(value: Any, label: str) -> bool:
    if not isinstance(value, bool):
        raise ValidationError(f"{label} must be boolean")
    return value


def _url(value: Any, label: str, *, required: bool = True, official_nexus: bool = False) -> str:
    text = _text(value, label, required=required)
    if not text:
        return ""
    parsed = urlparse(text)
    if parsed.scheme != "https" or not parsed.netloc:
        raise ValidationError(f"{label} must be an HTTPS URL")
    if official_nexus and parsed.hostname != OFFICIAL_POLICY_HOST:
        raise ValidationError(f"{label} must use {OFFICIAL_POLICY_HOST}")
    return text


def _relative_pattern(value: Any, label: str) -> str:
    text = _text(value, label).replace("\\", "/")
    if text.startswith("/") or re.match(r"^[A-Za-z]:", text):
        raise ValidationError(f"{label} must be a relative release path pattern")
    parts = PurePosixPath(text).parts
    if not parts or any(part in {"", ".", ".."} for part in parts):
        raise ValidationError(f"{label} contains unsafe path components")
    return text


def _local_evidence_path(value: Any, label: str) -> str:
    text = _text(value, label, required=False).replace("\\", "/")
    if not text:
        return ""
    if text.startswith("/") or re.match(r"^[A-Za-z]:", text):
        raise ValidationError(f"{label} must be relative to the publication plan directory")
    path = PurePosixPath(text)
    if any(part in {"", ".", ".."} for part in path.parts):
        raise ValidationError(f"{label} contains unsafe path components")
    return path.as_posix()


def _iso_date(value: Any, label: str) -> str:
    text = _text(value, label)
    try:
        date.fromisoformat(text)
    except ValueError as exc:
        raise ValidationError(f"{label} must use YYYY-MM-DD") from exc
    return text


def _normalize_policy_review(raw: Any) -> dict[str, Any]:
    value = _as_dict(raw, "policy_review")
    _check_keys(value, {"reviewed_at", "reviewer", "sources"}, "policy_review")
    reviewed_at = _iso_date(value.get("reviewed_at"), "policy_review.reviewed_at")
    reviewer = _text(value.get("reviewer"), "policy_review.reviewer")
    sources: dict[str, str] = {}
    for index, raw_source in enumerate(_as_list(value.get("sources", []), "policy_review.sources")):
        source = _as_dict(raw_source, f"policy_review.sources[{index}]")
        _check_keys(source, {"id", "title", "url", "reviewed"}, f"policy_review.sources[{index}]")
        source_id = _text(source.get("id"), f"policy_review.sources[{index}].id")
        if source_id in sources:
            raise ValidationError(f"Duplicate policy source id: {source_id}")
        if not _boolean(source.get("reviewed"), f"policy_review.sources[{index}].reviewed"):
            raise ValidationError(f"Policy source is not acknowledged as reviewed: {source_id}")
        _text(source.get("title"), f"policy_review.sources[{index}].title")
        sources[source_id] = _url(source.get("url"), f"policy_review.sources[{index}].url", official_nexus=True)
    missing = sorted(set(REQUIRED_POLICIES) - set(sources))
    if missing:
        raise ValidationError(f"Missing required Nexus policy reviews: {missing}")
    for source_id, expected in REQUIRED_POLICIES.items():
        if sources[source_id].rstrip("/") != expected.rstrip("/"):
            raise ValidationError(f"Policy source {source_id} must be {expected}")
    return {"reviewed_at": reviewed_at, "reviewer": reviewer, "sources": sources}


def _normalize_license(raw: Any, label: str) -> dict[str, str]:
    value = _as_dict(raw, label)
    _check_keys(value, {"id", "name", "url", "text_path", "permissions_statement", "notice_path", "source_code_url", "obligations_acknowledged"}, label)
    license_id = _text(value.get("id"), f"{label}.id")
    return {
        "id": license_id,
        "name": _text(value.get("name"), f"{label}.name"),
        "url": _url(value.get("url"), f"{label}.url", required=False),
        "text_path": _text(value.get("text_path"), f"{label}.text_path", required=False).replace("\\", "/"),
        "notice_path": _text(value.get("notice_path"), f"{label}.notice_path", required=False).replace("\\", "/"),
        "source_code_url": _url(value.get("source_code_url"), f"{label}.source_code_url", required=False),
        "obligations_acknowledged": _boolean(value.get("obligations_acknowledged", False), f"{label}.obligations_acknowledged"),
        "permissions_statement": _text(value.get("permissions_statement"), f"{label}.permissions_statement"),
    }


def _normalize_evidence(raw: Any, label: str) -> dict[str, Any]:
    value = _as_dict(raw, label)
    _check_keys(value, {"path", "description", "public"}, label)
    return {
        "path": _local_evidence_path(value.get("path"), f"{label}.path"),
        "description": _text(value.get("description"), f"{label}.description"),
        "public": _boolean(value.get("public", False), f"{label}.public"),
    }


def _normalize_asset(raw: Any, index: int) -> dict[str, Any]:
    label = f"ownership.assets[{index}]"
    value = _as_dict(raw, label)
    _check_keys(value, {
        "id", "paths", "kind", "provenance", "author", "source_url", "source_name",
        "license", "permission_basis", "redistribution", "modification", "commercial_use",
        "donation_points", "credit", "credit_required", "bundled", "evidence", "notes",
    }, label)
    asset_id = _text(value.get("id"), f"{label}.id")
    paths = [_relative_pattern(item, f"{label}.paths[{i}]") for i, item in enumerate(_as_list(value.get("paths", []), f"{label}.paths"))]
    if not paths:
        raise ValidationError(f"{label}.paths must not be empty")
    kind = _text(value.get("kind"), f"{label}.kind")
    if kind not in ASSET_KINDS:
        raise ValidationError(f"{label}.kind must be one of {sorted(ASSET_KINDS)}")
    provenance = _text(value.get("provenance"), f"{label}.provenance")
    if provenance not in PROVENANCE:
        raise ValidationError(f"{label}.provenance must be one of {sorted(PROVENANCE)}")
    permission_basis = _text(value.get("permission_basis"), f"{label}.permission_basis")
    if permission_basis not in PERMISSION_BASES:
        raise ValidationError(f"{label}.permission_basis must be one of {sorted(PERMISSION_BASES)}")
    rights = {}
    for field in ("redistribution", "modification", "commercial_use", "donation_points"):
        right = _text(value.get(field), f"{label}.{field}")
        if right not in RIGHTS_VALUES:
            raise ValidationError(f"{label}.{field} must be one of {sorted(RIGHTS_VALUES)}")
        rights[field] = right
    license_value = value.get("license")
    license_info = _normalize_license(license_value, f"{label}.license") if license_value is not None else None
    evidence = [_normalize_evidence(item, f"{label}.evidence[{i}]") for i, item in enumerate(_as_list(value.get("evidence", []), f"{label}.evidence"))]
    return {
        "id": asset_id,
        "paths": paths,
        "kind": kind,
        "provenance": provenance,
        "author": _text(value.get("author"), f"{label}.author"),
        "source_url": _url(value.get("source_url"), f"{label}.source_url", required=False),
        "source_name": _text(value.get("source_name"), f"{label}.source_name", required=False),
        "license": license_info,
        "permission_basis": permission_basis,
        **rights,
        "credit": _text(value.get("credit"), f"{label}.credit", required=False),
        "credit_required": _boolean(value.get("credit_required", True), f"{label}.credit_required"),
        "bundled": _boolean(value.get("bundled", True), f"{label}.bundled"),
        "evidence": evidence,
        "notes": _text(value.get("notes"), f"{label}.notes", required=False),
    }


def _normalize_dependency(raw: Any, index: int) -> dict[str, Any]:
    label = f"ownership.dependencies[{index}]"
    value = _as_dict(raw, label)
    _check_keys(value, {"name", "url", "required", "bundled", "author", "credit", "license"}, label)
    return {
        "name": _text(value.get("name"), f"{label}.name"),
        "url": _url(value.get("url"), f"{label}.url"),
        "required": _boolean(value.get("required", True), f"{label}.required"),
        "bundled": _boolean(value.get("bundled", False), f"{label}.bundled"),
        "author": _text(value.get("author"), f"{label}.author", required=False),
        "credit": _text(value.get("credit"), f"{label}.credit", required=False),
        "license": _normalize_license(value["license"], f"{label}.license") if value.get("license") is not None else None,
    }


def _normalize_content(raw: Any) -> dict[str, Any]:
    value = _as_dict(raw, "content")
    _check_keys(value, {"adult", "political_references", "msf_branding", "violence", "tags"}, "content")
    adult = _as_dict(value.get("adult", {}), "content.adult")
    _check_keys(adult, ADULT_KEYS, "content.adult")
    adult_values = {key: _boolean(adult.get(key, False), f"content.adult.{key}") for key in sorted(ADULT_KEYS)}
    tags = [_text(item, f"content.tags[{i}]") for i, item in enumerate(_as_list(value.get("tags", []), "content.tags"))]
    return {
        "adult": adult_values,
        "political_references": _boolean(value.get("political_references", False), "content.political_references"),
        "msf_branding": _boolean(value.get("msf_branding", False), "content.msf_branding"),
        "violence": _text(value.get("violence", "none"), "content.violence"),
        "tags": tags,
    }


def validate_plan(data: Any, release_root: Path | None = None) -> dict[str, Any]:
    value = _as_dict(data, "publication plan")
    _check_keys(value, {
        "schema", "intent", "policy_review", "mod", "page", "ownership", "declarations",
        "software", "ai", "content", "permissions", "attestation",
    }, "publication plan")
    if value.get("schema") != PLAN_SCHEMA:
        raise ValidationError(f"publication plan schema must be {PLAN_SCHEMA!r}")
    intent = _text(value.get("intent"), "intent")
    if intent != "nexus_public":
        raise ValidationError("intent must be 'nexus_public' for the Nexus publication gate")
    policy = _normalize_policy_review(value.get("policy_review"))

    mod_raw = _as_dict(value.get("mod"), "mod")
    _check_keys(mod_raw, {"name", "version", "game", "game_terms_url", "uploader", "summary", "category", "tags", "donation_points", "event", "release_type", "value_added_description"}, "mod")
    mod_version = _text(mod_raw.get("version"), "mod.version")
    validate_semver(mod_version)
    release_type = _text(mod_raw.get("release_type", "original_mod"), "mod.release_type")
    if release_type not in RELEASE_TYPES:
        raise ValidationError(f"mod.release_type must be one of {sorted(RELEASE_TYPES)}")
    mod = {
        "name": _text(mod_raw.get("name"), "mod.name"),
        "version": mod_version,
        "game": _text(mod_raw.get("game"), "mod.game"),
        "game_terms_url": _url(mod_raw.get("game_terms_url"), "mod.game_terms_url"),
        "uploader": _text(mod_raw.get("uploader"), "mod.uploader"),
        "summary": _text(mod_raw.get("summary"), "mod.summary"),
        "category": _text(mod_raw.get("category"), "mod.category"),
        "tags": [_text(item, f"mod.tags[{i}]") for i, item in enumerate(_as_list(mod_raw.get("tags", []), "mod.tags"))],
        "donation_points": _boolean(mod_raw.get("donation_points", False), "mod.donation_points"),
        "event": _text(mod_raw.get("event"), "mod.event", required=False),
        "release_type": release_type,
        "value_added_description": _text(mod_raw.get("value_added_description"), "mod.value_added_description", required=False),
    }

    page_raw = _as_dict(value.get("page"), "page")
    _check_keys(page_raw, {"description", "requirements", "installation", "uninstallation", "compatibility", "known_issues", "support", "claims", "changelog", "external_links"}, "page")
    claims = []
    for index, raw_claim in enumerate(_as_list(page_raw.get("claims", []), "page.claims")):
        claim = _as_dict(raw_claim, f"page.claims[{index}]")
        _check_keys(claim, {"text", "evidence"}, f"page.claims[{index}]")
        claims.append({"text": _text(claim.get("text"), f"page.claims[{index}].text"), "evidence": _text(claim.get("evidence"), f"page.claims[{index}].evidence")})
    page = {
        "description": _text(page_raw.get("description"), "page.description"),
        "requirements": [_text(item, f"page.requirements[{i}]") for i, item in enumerate(_as_list(page_raw.get("requirements", []), "page.requirements"))],
        "installation": [_text(item, f"page.installation[{i}]") for i, item in enumerate(_as_list(page_raw.get("installation", []), "page.installation"))],
        "uninstallation": [_text(item, f"page.uninstallation[{i}]") for i, item in enumerate(_as_list(page_raw.get("uninstallation", []), "page.uninstallation"))],
        "compatibility": [_text(item, f"page.compatibility[{i}]") for i, item in enumerate(_as_list(page_raw.get("compatibility", []), "page.compatibility"))],
        "known_issues": [_text(item, f"page.known_issues[{i}]") for i, item in enumerate(_as_list(page_raw.get("known_issues", []), "page.known_issues"))],
        "support": _text(page_raw.get("support"), "page.support"),
        "claims": claims,
        "changelog": [_text(item, f"page.changelog[{i}]") for i, item in enumerate(_as_list(page_raw.get("changelog", []), "page.changelog"))],
        "external_links": [_url(item, f"page.external_links[{i}]") for i, item in enumerate(_as_list(page_raw.get("external_links", []), "page.external_links"))],
    }

    ownership_raw = _as_dict(value.get("ownership"), "ownership")
    _check_keys(ownership_raw, {"original_work", "project_license", "collaborators", "assets", "dependencies"}, "ownership")
    collaborators = []
    for index, raw_collaborator in enumerate(_as_list(ownership_raw.get("collaborators", []), "ownership.collaborators")):
        collaborator = _as_dict(raw_collaborator, f"ownership.collaborators[{index}]")
        _check_keys(collaborator, {"name", "role", "credit"}, f"ownership.collaborators[{index}]")
        collaborators.append({
            "name": _text(collaborator.get("name"), f"ownership.collaborators[{index}].name"),
            "role": _text(collaborator.get("role"), f"ownership.collaborators[{index}].role"),
            "credit": _text(collaborator.get("credit"), f"ownership.collaborators[{index}].credit"),
        })
    assets = [_normalize_asset(item, index) for index, item in enumerate(_as_list(ownership_raw.get("assets", []), "ownership.assets"))]
    ids = [item["id"] for item in assets]
    if len(ids) != len(set(ids)):
        raise ValidationError("ownership.assets contains duplicate ids")
    ownership = {
        "original_work": _boolean(ownership_raw.get("original_work", False), "ownership.original_work"),
        "project_license": _normalize_license(ownership_raw.get("project_license"), "ownership.project_license"),
        "collaborators": collaborators,
        "assets": assets,
        "dependencies": [_normalize_dependency(item, index) for index, item in enumerate(_as_list(ownership_raw.get("dependencies", []), "ownership.dependencies"))],
    }

    declarations_raw = _as_dict(value.get("declarations"), "declarations")
    _check_keys(declarations_raw, DECLARATIONS, "declarations")
    declarations = {name: _boolean(declarations_raw.get(name), f"declarations.{name}") for name in sorted(DECLARATIONS)}

    software_raw = _as_dict(value.get("software", {}), "software")
    _check_keys(software_raw, {"contains_executables", "internet_access", "internet_access_crucial", "source_code_url", "nexus_staff_contact_evidence", "network_disclosure"}, "software")
    software = {
        "contains_executables": _boolean(software_raw.get("contains_executables", False), "software.contains_executables"),
        "internet_access": _boolean(software_raw.get("internet_access", False), "software.internet_access"),
        "internet_access_crucial": _boolean(software_raw.get("internet_access_crucial", False), "software.internet_access_crucial"),
        "source_code_url": _url(software_raw.get("source_code_url"), "software.source_code_url", required=False),
        "nexus_staff_contact_evidence": _local_evidence_path(software_raw.get("nexus_staff_contact_evidence"), "software.nexus_staff_contact_evidence"),
        "network_disclosure": _text(software_raw.get("network_disclosure"), "software.network_disclosure", required=False),
    }

    ai_raw = _as_dict(value.get("ai", {}), "ai")
    _check_keys(ai_raw, {"used", "areas", "human_verified", "disclosure"}, "ai")
    ai_areas = [_text(item, f"ai.areas[{i}]") for i, item in enumerate(_as_list(ai_raw.get("areas", []), "ai.areas"))]
    invalid_ai = sorted(set(ai_areas) - AI_AREAS)
    if invalid_ai:
        raise ValidationError(f"ai.areas contains unsupported values: {invalid_ai}")
    ai = {
        "used": _boolean(ai_raw.get("used", False), "ai.used"),
        "areas": ai_areas,
        "human_verified": _boolean(ai_raw.get("human_verified", False), "ai.human_verified"),
        "disclosure": _text(ai_raw.get("disclosure"), "ai.disclosure", required=False),
    }

    permissions_raw = _as_dict(value.get("permissions"), "permissions")
    permission_text_keys = {"redistribution", "modification", "asset_use", "conversion", "translation", "commercial_use", "donation_points"}
    _check_keys(permissions_raw, permission_text_keys | {"nexus_settings"}, "permissions")
    permissions = {key: _text(permissions_raw.get(key), f"permissions.{key}") for key in sorted(permission_text_keys)}
    settings_raw = _as_dict(permissions_raw.get("nexus_settings", {}), "permissions.nexus_settings")
    setting_keys = {"upload_elsewhere", "modification", "asset_use", "conversion", "translation", "commercial_use", "donation_points"}
    _check_keys(settings_raw, setting_keys, "permissions.nexus_settings")
    settings = {}
    for key in sorted(setting_keys):
        setting = _text(settings_raw.get(key, "not_applicable"), f"permissions.nexus_settings.{key}")
        if setting not in PERMISSION_SETTING_VALUES:
            raise ValidationError(f"permissions.nexus_settings.{key} must be one of {sorted(PERMISSION_SETTING_VALUES)}")
        settings[key] = setting
    permissions["nexus_settings"] = settings

    attestation_raw = _as_dict(value.get("attestation"), "attestation")
    _check_keys(attestation_raw, {"signed_by", "signed_at", "responsibility_accepted"}, "attestation")
    attestation = {
        "signed_by": _text(attestation_raw.get("signed_by"), "attestation.signed_by"),
        "signed_at": _iso_date(attestation_raw.get("signed_at"), "attestation.signed_at"),
        "responsibility_accepted": _boolean(attestation_raw.get("responsibility_accepted"), "attestation.responsibility_accepted"),
    }

    plan = {
        "schema": PLAN_SCHEMA,
        "intent": intent,
        "policy_review": policy,
        "mod": mod,
        "page": page,
        "ownership": ownership,
        "declarations": declarations,
        "software": software,
        "ai": ai,
        "content": _normalize_content(value.get("content", {})),
        "permissions": permissions,
        "attestation": attestation,
    }
    if release_root is not None:
        audit_plan(plan, release_root)
    return plan


def _matches(rel: str, patterns: list[str]) -> bool:
    folded = rel.casefold()
    return any(fnmatch.fnmatchcase(folded, pattern.casefold()) for pattern in patterns)


def _evidence_report(plan: dict[str, Any], evidence_base: Path) -> tuple[list[dict[str, Any]], list[str], list[str]]:
    evidence_report: list[dict[str, Any]] = []
    errors: list[str] = []
    warnings: list[str] = []
    for asset in plan["ownership"]["assets"]:
        for evidence in asset["evidence"]:
            path_text = evidence["path"]
            if not path_text:
                continue
            path = (evidence_base / path_text).resolve(strict=False)
            item = {"asset": asset["id"], "description": evidence["description"], "public": evidence["public"], "path_present": path.is_file()}
            if path.is_file():
                item.update({"sha256": sha256_file(path), "size": path.stat().st_size})
            else:
                errors.append(f"Permission evidence file is missing for asset {asset['id']}: {path}")
            evidence_report.append(item)
            if evidence["public"]:
                warnings.append(f"Permission evidence for {asset['id']} is marked public; review it for private messages or personal data before publication")
    staff = plan["software"]["nexus_staff_contact_evidence"]
    if staff:
        path = (evidence_base / staff).resolve(strict=False)
        item = {"asset": "software_network_contact", "description": "Nexus staff contact evidence", "public": False, "path_present": path.is_file()}
        if path.is_file():
            item.update({"sha256": sha256_file(path), "size": path.stat().st_size})
        else:
            errors.append(f"Nexus staff contact evidence file is missing: {path}")
        evidence_report.append(item)
    return evidence_report, errors, warnings


def _audit_license(license_info: dict[str, Any] | None, root: Path, label: str, credit: str, errors: list[str], warnings: list[str]) -> None:
    if license_info is None:
        return
    license_id = license_info["id"].strip().upper()
    if license_id in LICENSE_COPY_REQUIRED and not license_info["text_path"]:
        errors.append(f"{label} uses {license_info['id']} but no licence text path is supplied")
    if license_info["text_path"] and not (root / license_info["text_path"]).is_file():
        errors.append(f"{label} licence text is missing from release: {license_info['text_path']}")
    if license_info["notice_path"] and not (root / license_info["notice_path"]).is_file():
        errors.append(f"{label} NOTICE/attribution file is missing from release: {license_info['notice_path']}")
    if license_id in SOURCE_REQUIRED and not license_info["source_code_url"]:
        errors.append(f"{label} uses {license_info['id']} and requires a corresponding source-code location")
    if license_id in ATTRIBUTION_REQUIRED and not credit:
        errors.append(f"{label} uses {license_info['id']} but required attribution is missing")
    if license_id in COPYLEFT_REVIEW and not license_info["obligations_acknowledged"]:
        errors.append(f"{label} uses copyleft/share-alike licence {license_info['id']} without an obligations acknowledgement")
    known = LICENSE_COPY_REQUIRED | {"CUSTOM", "NOASSERTION", "PROPRIETARY", "ALL-RIGHTS-RESERVED"}
    if license_id not in known and not license_info["obligations_acknowledged"]:
        errors.append(f"{label} uses unmodelled licence {license_info['id']}; manual obligations acknowledgement is required")
    if license_id == "APACHE-2.0" and not license_info["notice_path"]:
        warnings.append(f"{label} uses Apache-2.0; confirm whether the upstream work includes a NOTICE file that must be reproduced")


def audit_plan(plan: dict[str, Any], release_root: Path, *, evidence_base: Path | None = None) -> dict[str, Any]:
    root = release_root.resolve(strict=True)
    evidence_base = (evidence_base or Path.cwd()).resolve(strict=True)
    if not root.is_dir():
        raise ValidationError("release_root must be a directory")
    errors: list[str] = []
    warnings: list[str] = []

    reviewed = date.fromisoformat(plan["policy_review"]["reviewed_at"])
    age = (date.today() - reviewed).days
    if age < 0:
        errors.append("Nexus policy review date is in the future")
    elif age > POLICY_REVIEW_MAX_AGE_DAYS:
        errors.append(f"Nexus policy review is stale ({age} days); review official policies again")

    if plan["mod"]["release_type"] == "compilation" and not plan["mod"]["value_added_description"]:
        errors.append("Compilation releases must explain functionality beyond repackaging")
    if plan["mod"]["release_type"] in {"patch", "translation", "modlist_support"} and not plan["ownership"]["dependencies"]:
        errors.append(f"Release type {plan['mod']['release_type']} must declare the original/required dependency")
    if plan["mod"]["release_type"] == "translation" and any(item["bundled"] for item in plan["ownership"]["dependencies"]):
        errors.append("Translations should depend on the original mod instead of bundling it without a separate rights record and permission")

    false_declarations = [name for name, accepted in plan["declarations"].items() if not accepted]
    if false_declarations:
        errors.append(f"Required uploader declarations are not accepted: {false_declarations}")
    if not plan["attestation"]["responsibility_accepted"]:
        errors.append("Uploader responsibility attestation is not accepted")
    if plan["attestation"]["signed_by"].casefold() != plan["mod"]["uploader"].casefold():
        errors.append("attestation.signed_by must match mod.uploader")

    release_report = validate_release_tree(root)
    errors.extend(f"release: {item}" for item in release_report["errors"])
    warnings.extend(f"release: {item}" for item in release_report["warnings"])

    all_files = [path for path in iter_files(root)]
    rels = [path.relative_to(root).as_posix() for path in all_files]
    coverage: dict[str, list[str]] = {}
    unmapped: list[str] = []
    multiple: list[dict[str, Any]] = []
    for rel in rels:
        owners = [asset["id"] for asset in plan["ownership"]["assets"] if asset["bundled"] and _matches(rel, asset["paths"])]
        coverage[rel] = owners
        if not owners:
            unmapped.append(rel)
        elif len(owners) > 1:
            multiple.append({"path": rel, "assets": owners})
    if unmapped:
        errors.append(f"Release files are not mapped to rights records: {unmapped[:50]}" + (" ..." if len(unmapped) > 50 else ""))
    if multiple:
        errors.append(f"Release files match multiple rights records: {multiple[:25]}")

    missing_asset_payload = []
    for asset in plan["ownership"]["assets"]:
        matched = [rel for rel in rels if _matches(rel, asset["paths"])]
        if asset["bundled"] and not matched:
            missing_asset_payload.append(asset["id"])
        if not asset["bundled"] and matched:
            errors.append(f"Asset {asset['id']} is declared not bundled but matches release files: {matched[:20]}")
        if asset["bundled"] and asset["redistribution"] != "allowed":
            errors.append(f"Bundled asset {asset['id']} is not cleared for redistribution")
        if asset["credit_required"] and not asset["credit"]:
            errors.append(f"Credit is required but missing for asset {asset['id']}")
        if asset["permission_basis"] in {"explicit_permission", "nexus_permission"} and not asset["evidence"]:
            errors.append(f"Asset {asset['id']} requires documented permission evidence")
        if asset["permission_basis"] == "open_license" and not asset["license"]:
            errors.append(f"Asset {asset['id']} uses an open license but no license record is supplied")
        if asset["provenance"] == "third_party_mod" and asset["permission_basis"] not in {"open_license", "explicit_permission", "nexus_permission", "dependency_not_bundled"}:
            errors.append(f"Third-party mod asset {asset['id']} lacks an acceptable permission basis")
        if asset["permission_basis"] == "dependency_not_bundled" and asset["bundled"]:
            errors.append(f"Asset {asset['id']} is marked dependency-only but is bundled")
        if plan["mod"]["donation_points"] and asset["bundled"] and asset["donation_points"] != "allowed":
            errors.append(f"Donation Points are enabled but asset {asset['id']} is not cleared for DP participation")
        _audit_license(asset["license"], root, f"Asset {asset['id']}", asset["credit"], errors, warnings)
    if missing_asset_payload:
        warnings.append(f"Bundled asset mappings matched no release files: {missing_asset_payload}")

    project_license = plan["ownership"]["project_license"]
    _audit_license(project_license, root, "Project licence", plan["mod"]["uploader"], errors, warnings)

    binaries = [rel for rel in rels if Path(rel).suffix.casefold() in BINARY_SUFFIXES]
    if bool(binaries) != plan["software"]["contains_executables"]:
        errors.append(f"software.contains_executables does not match release inventory; binaries={binaries}")
    if binaries and not plan["software"]["source_code_url"]:
        warnings.append("The release contains executable code but no public source-code URL is supplied")
    if plan["software"]["internet_access"]:
        if not plan["software"]["internet_access_crucial"]:
            errors.append("Internet access is declared but not crucial to the mod/utility function")
        if not plan["software"]["source_code_url"]:
            errors.append("Internet-connected software must provide a source-code URL")
        if not plan["software"]["nexus_staff_contact_evidence"]:
            errors.append("Internet-connected software requires evidence that Nexus staff was contacted")
        if not plan["software"]["network_disclosure"]:
            errors.append("Internet-connected software requires a clear user-facing network disclosure")

    denied = []
    nested_archives = []
    for rel in rels:
        name = Path(rel).name.casefold()
        if name in KNOWN_GAME_FILE_NAMES or any(name.startswith(prefix) and Path(rel).suffix.casefold() in {".bsa", ".ba2"} for prefix in KNOWN_GAME_ARCHIVE_PREFIXES):
            denied.append(rel)
        if Path(rel).suffix.casefold() in ARCHIVE_SUFFIXES:
            nested_archives.append(rel)
    if denied:
        errors.append(f"Known original game/tool files are not allowed in the release: {denied}")
    if nested_archives:
        warnings.append(f"Nested archives may trigger quarantine or hide payload contents: {nested_archives}")

    page_text = "\n".join([
        plan["mod"]["summary"], plan["page"]["description"], *plan["page"]["requirements"],
        *plan["page"]["installation"], *plan["page"]["uninstallation"], *plan["page"]["compatibility"],
        *plan["page"]["known_issues"], plan["page"]["support"], *[item["text"] for item in plan["page"]["claims"]],
    ])
    if not plan["page"]["installation"]:
        errors.append("Nexus page requires installation instructions")
    if not plan["page"]["requirements"]:
        warnings.append("No requirements are listed; confirm that the mod is truly standalone")
    if PERFORMANCE_CLAIM.search(page_text) and not plan["page"]["claims"]:
        errors.append("Performance/optimization claims require explicit evidence entries")
    if AGGRESSIVE_SOLICITATION.search(page_text):
        errors.append("Page text contains aggressive donation or endorsement solicitation")
    if PROHIBITED_LINK_HINT.search(page_text):
        errors.append("Page text contains a link or phrase associated with prohibited external distribution; review manually")
    for link in plan["page"]["external_links"]:
        if PROHIBITED_LINK_HINT.search(link):
            errors.append(f"External link requires manual review and may point to prohibited distribution: {link}")

    if plan["ai"]["used"]:
        if not plan["ai"]["human_verified"]:
            errors.append("AI-assisted content must be human-verified before publication")
        if not plan["ai"]["disclosure"]:
            errors.append("AI-assisted publication requires a truthful disclosure in the rights package")
    event = plan["mod"]["event"].casefold()
    if event == "nexus-25th-anniversary-2026":
        if plan["ai"]["used"]:
            errors.append("The Nexus Mods 25th Anniversary Mod Drive prohibits generative AI for assets, code, or dialogue")
        if plan["content"]["violence"].casefold() not in {"none", "non-violent"}:
            errors.append("The selected Nexus event requires non-violent content")
        if plan["content"]["political_references"]:
            errors.append("The selected Nexus event prohibits political references")
        if plan["content"]["msf_branding"]:
            errors.append("The selected Nexus event prohibits MSF branding")

    adult_enabled = any(plan["content"]["adult"].values())
    if adult_enabled and not any("adult" in tag.casefold() or "nudity" in tag.casefold() or "sexual" in tag.casefold() or "violence" in tag.casefold() for tag in plan["content"]["tags"] + plan["mod"]["tags"]):
        errors.append("Adult content is declared but no matching adult-content tag/classification is supplied")

    settings = plan["permissions"]["nexus_settings"]
    bundled_assets = [asset for asset in plan["ownership"]["assets"] if asset["bundled"]]
    if settings["upload_elsewhere"] in {"allowed", "allowed_with_credit"} and any(asset["redistribution"] != "allowed" for asset in bundled_assets):
        errors.append("Nexus upload-elsewhere permission is broader than one or more bundled asset redistribution rights")
    if settings["modification"] in {"allowed", "allowed_with_credit"} and any(asset["modification"] != "allowed" for asset in bundled_assets):
        errors.append("Nexus modification permission is broader than one or more bundled asset modification rights")
    if settings["asset_use"] in {"allowed", "allowed_with_credit"} and any(asset["modification"] != "allowed" for asset in bundled_assets):
        errors.append("Nexus asset-use permission is broader than one or more bundled asset rights")
    if settings["commercial_use"] in {"allowed", "allowed_with_credit"} and any(asset["commercial_use"] != "allowed" for asset in bundled_assets):
        errors.append("Nexus commercial-use permission is broader than one or more bundled asset rights")
    if settings["donation_points"] in {"allowed", "allowed_with_credit"} and any(asset["donation_points"] not in {"allowed", "not_applicable"} for asset in bundled_assets):
        errors.append("Nexus Donation Points permission is broader than one or more bundled asset rights")
    if plan["mod"]["donation_points"] and settings["donation_points"] not in {"allowed", "allowed_with_credit"}:
        errors.append("Donation Points are enabled but the Nexus permission setting does not allow them")

    evidence_report, evidence_errors, evidence_warnings = _evidence_report(plan, evidence_base)
    errors.extend(evidence_errors)
    warnings.extend(evidence_warnings)

    dependencies_bundled = [item["name"] for item in plan["ownership"]["dependencies"] if item["bundled"]]
    if dependencies_bundled:
        errors.append(f"Dependencies must be represented as rights-mapped assets when bundled: {dependencies_bundled}")

    return {
        "result": "PASS" if not errors else "FAIL",
        "share_ready": not errors,
        "target": "Nexus Mods",
        "policy_review_age_days": age,
        "release_root": str(root),
        "file_count": len(rels),
        "mapped_file_count": len(rels) - len(unmapped),
        "unmapped_files": unmapped,
        "multiple_asset_matches": multiple,
        "binaries": binaries,
        "nested_archives": nested_archives,
        "evidence": evidence_report,
        "errors": sorted(set(errors)),
        "warnings": sorted(set(warnings)),
        "limitations": [
            "Forge validates declared evidence and machine-checkable release properties; it cannot determine legal ownership or authenticate a permission conversation.",
            "Nexus Mods policies can change. A policy review older than 90 days blocks share-ready status.",
            "The uploader remains responsible for the upload, game EULA compliance, content classification, and accuracy of every claim.",
        ],
    }


def load_and_validate_plan(path: Path, release_root: Path | None = None) -> dict[str, Any]:
    plan = validate_plan(load(path))
    if release_root is not None:
        audit_plan(plan, release_root, evidence_base=path.resolve(strict=True).parent)
    return plan


def policy_status() -> dict[str, Any]:
    return {
        "result": "PASS",
        "target": "Nexus Mods",
        "required_sources": [{"id": key, "url": url} for key, url in REQUIRED_POLICIES.items()],
        "maximum_review_age_days": POLICY_REVIEW_MAX_AGE_DAYS,
        "automation_boundary": "Forge does not scrape Nexus Mods. Policy and permission evidence must be reviewed and supplied by the user or an authorized API workflow.",
    }


def _bb_list(items: list[str]) -> str:
    if not items:
        return "[i]None listed.[/i]"
    return "[list]\n" + "\n".join(f"[*]{item}" for item in items) + "\n[/list]"


def render_mod_page(plan: dict[str, Any]) -> str:
    credits = []
    for collaborator in plan["ownership"]["collaborators"]:
        credits.append(f"{collaborator['name']} — {collaborator['role']}: {collaborator['credit']}")
    for asset in plan["ownership"]["assets"]:
        if asset["credit"] and asset["credit"] not in credits:
            credits.append(asset["credit"])
    requirements = list(plan["page"]["requirements"])
    requirements.extend(f"{item['name']}: {item['url']}" for item in plan["ownership"]["dependencies"] if item["required"])
    ai_text = plan["ai"]["disclosure"] if plan["ai"]["used"] else "No generative AI assistance is declared for this release."
    settings_list = [f"{key.replace('_', ' ').title()}: {value}" for key, value in plan["permissions"]["nexus_settings"].items()]
    permissions_text = (
        f"[heading]Permissions and Licensing[/heading]\n{plan['ownership']['project_license']['permissions_statement']}\n\n"
        f"[b]Redistribution:[/b] {plan['permissions']['redistribution']}\n"
        f"[b]Modification:[/b] {plan['permissions']['modification']}\n"
        f"[b]Asset use:[/b] {plan['permissions']['asset_use']}\n"
        f"[b]Translations:[/b] {plan['permissions']['translation']}\n"
        f"[b]Conversions:[/b] {plan['permissions']['conversion']}\n"
        f"[b]Commercial use:[/b] {plan['permissions']['commercial_use']}\n"
        f"[b]Donation Points:[/b] {plan['permissions']['donation_points']}\n\n"
        f"[b]Recommended Nexus permission settings:[/b]\n{_bb_list(settings_list)}"
    )
    sections = [
        f"[center][size=6][b]{plan['mod']['name']}[/b][/size]\n[size=3]Version {plan['mod']['version']}[/size][/center]",
        f"[heading]Overview[/heading]\n{plan['page']['description']}",
        f"[heading]Requirements[/heading]\n{_bb_list(requirements)}",
        f"[heading]Installation[/heading]\n{_bb_list(plan['page']['installation'])}",
        f"[heading]Uninstallation[/heading]\n{_bb_list(plan['page']['uninstallation'])}",
        f"[heading]Compatibility[/heading]\n{_bb_list(plan['page']['compatibility'])}",
        f"[heading]Known Issues and Limitations[/heading]\n{_bb_list(plan['page']['known_issues'])}",
        f"[heading]Credits[/heading]\n{_bb_list(credits)}",
        permissions_text,
        f"[heading]AI Assistance Disclosure[/heading]\n{ai_text}",
        f"[heading]Support[/heading]\n{plan['page']['support']}",
        f"[heading]Changelog[/heading]\n{_bb_list(plan['page']['changelog'])}",
    ]
    return "\n\n".join(sections).strip() + "\n"


def _credits_markdown(plan: dict[str, Any]) -> str:
    rows = ["# Credits", "", "## Project contributors", ""]
    if plan["ownership"]["collaborators"]:
        rows.extend(f"- **{item['name']}** — {item['role']}: {item['credit']}" for item in plan["ownership"]["collaborators"])
    else:
        rows.append("- No additional collaborators declared.")
    rows.extend(["", "## Bundled assets and code", ""])
    for asset in plan["ownership"]["assets"]:
        if not asset["bundled"]:
            continue
        source = f" ({asset['source_url']})" if asset["source_url"] else ""
        license_text = asset["license"]["name"] if asset["license"] else asset["permission_basis"]
        rows.append(f"- **{asset['id']}** — {asset['credit'] or asset['author']}{source}; permission basis: {license_text}.")
    rows.extend(["", "## Required dependencies not redistributed", ""])
    if plan["ownership"]["dependencies"]:
        rows.extend(f"- **{item['name']}** — {item['url']}" for item in plan["ownership"]["dependencies"])
    else:
        rows.append("- None declared.")
    return "\n".join(rows) + "\n"


def _third_party_notices(plan: dict[str, Any]) -> str:
    rows = ["# Third-Party Notices", ""]
    third_party = [asset for asset in plan["ownership"]["assets"] if asset["provenance"] not in {"original", "generated"}]
    if not third_party:
        rows.append("No bundled third-party assets are declared.")
    for asset in third_party:
        rows.extend([
            f"## {asset['id']}", "",
            f"- Author: {asset['author']}",
            f"- Source: {asset['source_url'] or asset['source_name'] or 'Not publicly linked'}",
            f"- Permission basis: {asset['permission_basis']}",
            f"- License: {(asset['license'] or {}).get('name', 'Custom permission')}",
            f"- Credit: {asset['credit'] or 'No separate credit text supplied'}", "",
        ])
    return "\n".join(rows).rstrip() + "\n"


def _rights_manifest(plan: dict[str, Any], audit: dict[str, Any]) -> dict[str, Any]:
    public_assets = []
    for asset in plan["ownership"]["assets"]:
        public_assets.append({key: asset[key] for key in (
            "id", "paths", "kind", "provenance", "author", "source_url", "source_name", "permission_basis",
            "redistribution", "modification", "commercial_use", "donation_points", "credit", "bundled", "notes",
        )} | {"license": asset["license"], "permission_evidence_verified": bool(asset["evidence"])})
    return {
        "schema": "skyrim-forge-public-rights-manifest/1",
        "mod": plan["mod"],
        "project_license": plan["ownership"]["project_license"],
        "assets": public_assets,
        "dependencies": plan["ownership"]["dependencies"],
        "collaborators": plan["ownership"]["collaborators"],
        "ai": plan["ai"],
        "content": plan["content"],
        "permissions": plan["permissions"],
        "publication_gate": {"result": audit["result"], "policy_review_age_days": audit["policy_review_age_days"], "file_count": audit["file_count"]},
        "note": "Private permission messages and local evidence paths are intentionally excluded from this public manifest.",
    }


def write_scaffold(release_root: Path, output_plan: Path, mod_name: str, version: str, uploader: str, *, approved: bool) -> dict[str, Any]:
    require_approval(approved, "Nexus publication-plan scaffold creation")
    root = release_root.resolve(strict=True)
    if not root.is_dir():
        raise ValidationError("release_root must be a directory")
    if output_plan.exists():
        raise SafetyError(f"Refusing to overwrite publication plan: {output_plan}")
    validate_semver(version)
    today = date.today().isoformat()
    plan = {
        "schema": PLAN_SCHEMA,
        "intent": "nexus_public",
        "policy_review": {
            "reviewed_at": today,
            "reviewer": "REPLACE WITH HUMAN/AI REVIEWER",
            "sources": [{"id": key, "title": key.replace("_", " ").title(), "url": url, "reviewed": False} for key, url in REQUIRED_POLICIES.items()],
        },
        "mod": {
            "name": mod_name, "version": version, "game": "Skyrim Special Edition / Anniversary Edition",
            "game_terms_url": "https://REPLACE-WITH-OFFICIAL-GAME-TERMS", "uploader": uploader,
            "summary": "REPLACE WITH ACCURATE SUMMARY", "category": "REPLACE", "tags": [],
            "donation_points": False, "event": "", "release_type": "original_mod", "value_added_description": "",
        },
        "page": {
            "description": "REPLACE WITH ACCURATE DESCRIPTION", "requirements": [],
            "installation": ["Install with a supported mod manager or follow the documented manual layout."],
            "uninstallation": ["Disable and remove the mod according to the included documentation."],
            "compatibility": [], "known_issues": [], "support": "Use the Nexus Mods page for support.",
            "claims": [], "changelog": [f"{version}: Initial publication-plan scaffold."], "external_links": [],
        },
        "ownership": {
            "original_work": False,
            "project_license": {"id": "CUSTOM", "name": "Custom Nexus permissions", "url": "", "text_path": "LICENSE.md", "notice_path": "", "source_code_url": "", "obligations_acknowledged": True, "permissions_statement": "REPLACE WITH EXPLICIT PERMISSIONS"},
            "collaborators": [],
            "assets": [{
                "id": "REVIEW-ALL-RELEASE-FILES", "paths": ["**"], "kind": "other", "provenance": "original",
                "author": uploader, "source_url": "", "source_name": "", "license": None,
                "permission_basis": "owned", "redistribution": "unknown", "modification": "unknown",
                "commercial_use": "unknown", "donation_points": "unknown", "credit": uploader,
                "credit_required": True, "bundled": True, "evidence": [],
                "notes": "Split this catch-all record into accurate asset groups before publication.",
            }],
            "dependencies": [],
        },
        "declarations": {name: False for name in sorted(DECLARATIONS)},
        "software": {"contains_executables": False, "internet_access": False, "internet_access_crucial": False, "source_code_url": "", "nexus_staff_contact_evidence": "", "network_disclosure": ""},
        "ai": {"used": True, "areas": ["code", "documentation"], "human_verified": False, "disclosure": "REPLACE WITH TRUTHFUL DISCLOSURE"},
        "content": {"adult": {name: False for name in sorted(ADULT_KEYS)}, "political_references": False, "msf_branding": False, "violence": "none", "tags": []},
        "permissions": {"redistribution": "REPLACE", "modification": "REPLACE", "asset_use": "REPLACE", "conversion": "REPLACE", "translation": "REPLACE", "commercial_use": "REPLACE", "donation_points": "REPLACE", "nexus_settings": {"upload_elsewhere": "permission_required", "modification": "permission_required", "asset_use": "permission_required", "conversion": "permission_required", "translation": "allowed_with_credit", "commercial_use": "not_allowed", "donation_points": "not_applicable"}},
        "attestation": {"signed_by": uploader, "signed_at": today, "responsibility_accepted": False},
    }
    output_plan.parent.mkdir(parents=True, exist_ok=True)
    json_dump(output_plan, plan)
    return {"result": "PASS", "output": str(output_plan), "release_files": len(list(iter_files(root))), "status": "INCOMPLETE_BY_DESIGN"}


def build_publication_bundle(plan_path: Path, release_root: Path, output_root: Path, workspace_root: Path, *, approved: bool) -> dict[str, Any]:
    require_approval(approved, "Nexus publication bundle creation")
    plan = load_and_validate_plan(plan_path)
    audit = audit_plan(plan, release_root, evidence_base=plan_path.resolve(strict=True).parent)
    if audit["result"] != "PASS":
        raise ValidationError(f"Nexus publication gate failed: {audit['errors']}")
    target = require_within(output_root, workspace_root)
    if target.exists():
        raise SafetyError(f"Refusing to overwrite publication bundle: {target}")
    target.parent.mkdir(parents=True, exist_ok=True)
    transaction = Path(tempfile.mkdtemp(prefix=f".{target.name}.nexus-", dir=target.parent))
    staged = transaction / target.name
    release_copy = staged / "release-tree"
    audit_dir = staged / "private-audit"
    try:
        shutil.copytree(release_root.resolve(strict=True), release_copy, symlinks=False)
        audit_dir.mkdir(parents=True)
        atomic_write_text(release_copy / "NEXUS-MOD-PAGE.bbcode", render_mod_page(plan))
        atomic_write_text(release_copy / "CREDITS.md", _credits_markdown(plan))
        atomic_write_text(release_copy / "THIRD-PARTY-NOTICES.md", _third_party_notices(plan))
        atomic_write_text(release_copy / "AI-DISCLOSURE.md", "# AI Assistance Disclosure\n\n" + (plan["ai"]["disclosure"] if plan["ai"]["used"] else "No generative AI assistance is declared for this release.") + "\n")
        atomic_write_text(release_copy / "NEXUS-PERMISSIONS.md", "# Permissions\n\n" + "\n".join(f"- **{key.replace('_', ' ').title()}:** {value}" for key, value in plan["permissions"].items()) + "\n")
        json_dump(release_copy / "RIGHTS-MANIFEST.json", _rights_manifest(plan, audit))
        checklist = [
            "# Nexus Mods Publication Checklist", "", "- [x] Machine-checkable release gate passed.",
            "- [x] All bundled files are mapped to rights records.", "- [x] Credits and permissions documents generated.",
            "- [x] Uploader attestation accepted.", "- [ ] Upload through Nexus Mods and select matching permissions/content tags.",
            "- [ ] Install the exact uploaded archive with Vortex and MO2 before publishing.",
            "- [ ] Review the generated Nexus BBCode and every claim one final time.", "",
            "Forge cannot authenticate legal ownership or substitute for the uploader's responsibility.",
        ]
        atomic_write_text(release_copy / "NEXUS-PUBLISH-CHECKLIST.md", "\n".join(checklist) + "\n")
        json_dump(audit_dir / "NEXUS-COMPLIANCE-AUDIT.json", audit)
        json_dump(audit_dir / "PUBLICATION-PLAN.normalized.json", plan)
        final_release_report = validate_release_tree(release_copy)
        if final_release_report["result"] != "PASS":
            raise ValidationError(f"Generated release tree failed final validation: {final_release_report['errors']}")
        filename = safe_name(f"{plan['mod']['name']}-{plan['mod']['version']}") + ".zip"
        archive_report = build_release(release_copy, staged / filename, staged, approved=True)
        os.replace(staged, target)
    finally:
        shutil.rmtree(transaction, ignore_errors=True)
    return {
        "result": "PASS", "share_ready": True, "target": "Nexus Mods", "output_root": str(target),
        "release_tree": str(target / "release-tree"), "private_audit": str(target / "private-audit"),
        "archive": str(target / filename), "archive_sha256": archive_report["sha256"],
        "file_count": final_release_report["file_count"],
        "human_final_steps": ["Install-test the final archive in Vortex and MO2", "Select matching Nexus permissions and content classifications", "Review the mod page and claims before pressing Publish"],
    }


def self_test() -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="forge-nexus-selftest-") as td:
        root = Path(td)
        release = root / "release"
        release.mkdir()
        (release / "Example.esp").write_bytes(b"TES4")
        (release / "LICENSE.md").write_text("Custom permissions\n", encoding="utf-8")
        today = date.today().isoformat()
        plan = {
            "schema": PLAN_SCHEMA,
            "intent": "nexus_public",
            "policy_review": {"reviewed_at": today, "reviewer": "Self-test", "sources": [{"id": key, "title": key, "url": url, "reviewed": True} for key, url in REQUIRED_POLICIES.items()]},
            "mod": {"name": "Example", "version": "1.0.0", "game": "Skyrim Special Edition", "game_terms_url": "https://example.com/eula", "uploader": "Tester", "summary": "Example release", "category": "Utilities", "tags": ["utility"], "donation_points": False, "event": "", "release_type": "original_mod", "value_added_description": ""},
            "page": {"description": "Example release.", "requirements": ["Skyrim Special Edition"], "installation": ["Install with a mod manager."], "uninstallation": ["Remove the mod."], "compatibility": [], "known_issues": [], "support": "Use the mod page.", "claims": [], "changelog": ["1.0.0: Test."], "external_links": []},
            "ownership": {"original_work": True, "project_license": {"id": "CUSTOM", "name": "Custom", "url": "", "text_path": "LICENSE.md", "notice_path": "", "source_code_url": "", "obligations_acknowledged": True, "permissions_statement": "No redistribution without permission."}, "collaborators": [], "assets": [{"id": "plugin", "paths": ["Example.esp"], "kind": "plugin", "provenance": "original", "author": "Tester", "source_url": "", "source_name": "", "license": None, "permission_basis": "owned", "redistribution": "allowed", "modification": "not_allowed", "commercial_use": "not_allowed", "donation_points": "not_applicable", "credit": "Tester", "credit_required": True, "bundled": True, "evidence": [], "notes": ""}, {"id": "license", "paths": ["LICENSE.md"], "kind": "documentation", "provenance": "original", "author": "Tester", "source_url": "", "source_name": "", "license": None, "permission_basis": "owned", "redistribution": "allowed", "modification": "not_allowed", "commercial_use": "not_allowed", "donation_points": "not_applicable", "credit": "Tester", "credit_required": True, "bundled": True, "evidence": [], "notes": ""}], "dependencies": []},
            "declarations": {name: True for name in DECLARATIONS},
            "software": {"contains_executables": False, "internet_access": False, "internet_access_crucial": False, "source_code_url": "", "nexus_staff_contact_evidence": "", "network_disclosure": ""},
            "ai": {"used": True, "areas": ["documentation"], "human_verified": True, "disclosure": "AI assisted documentation; the uploader reviewed the final release."},
            "content": {"adult": {name: False for name in ADULT_KEYS}, "political_references": False, "msf_branding": False, "violence": "none", "tags": []},
            "permissions": {"redistribution": "No redistribution without permission.", "modification": "Ask first.", "asset_use": "Ask first.", "conversion": "Ask first.", "translation": "Allowed with credit.", "commercial_use": "Not allowed.", "donation_points": "Not applicable.", "nexus_settings": {"upload_elsewhere": "permission_required", "modification": "permission_required", "asset_use": "permission_required", "conversion": "permission_required", "translation": "allowed_with_credit", "commercial_use": "not_allowed", "donation_points": "not_applicable"}},
            "attestation": {"signed_by": "Tester", "signed_at": today, "responsibility_accepted": True},
        }
        normalized = validate_plan(plan)
        report = audit_plan(normalized, release, evidence_base=root)
        return {"result": report["result"], "share_ready": report["share_ready"], "files": report["file_count"]}
