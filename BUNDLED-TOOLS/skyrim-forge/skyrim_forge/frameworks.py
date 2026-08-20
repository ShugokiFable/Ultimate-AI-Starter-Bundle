from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

from .strictjson import load

KID_TYPES = {
    "Weapon", "Armor", "Ammo", "Magic Effect", "Potion", "Scroll", "Location", "Ingredient",
    "Book", "Misc Item", "Key", "Soul Gem", "Spell", "Activator", "Flora", "Furniture", "Race",
    "Talking Activator", "Enchantment",
}
KID_SIGNATURES = {"WEAP", "ARMO", "AMMO", "MGEF", "ALCH", "SCRL", "LCTN", "INGR", "BOOK", "MISC", "KEYM", "SLGM", "SPEL", "ACTI", "FLOR", "FURN", "RACE", "TACT", "ENCH"}
SPID_TYPES = {"Form", "Spell", "Perk", "Item", "Shout", "LevSpell", "Package", "Outfit", "Keyword", "Faction", "SleepOutfit", "Skin"}
# These are demonstrated generator mistakes, not merely unknown future syntax.
SPID_KNOWN_INVALID_KEYS = {"Weapon"}
SPID_SINGLE_SKILL = "spid-single-value-skill-filter"
SPID_TRAITS = {"M", "-F", "F", "-M", "U", "-U", "S", "-S", "C", "-C", "L", "-L", "T", "-T", "D", "-D"}
# Every category below is attested by an installed mod in the reference corpus.
# outfit, ingestible, misc, ingredient and projectile were missing and produced
# warnings against configurations that ship and work.
SKYPATCHER_CATEGORIES = {"npc", "weapon", "armor", "ammo", "race", "spell", "scroll", "alchemy", "book", "cell", "constructibleobject", "container", "enchantment", "formlist", "leveledlist", "location", "magiceffect", "other", "outfit", "ingestible", "misc", "ingredient", "projectile"}
BOS_SECTIONS = {"forms", "references", "transforms", "properties"}
FLM_KEYS = {"alias", "group", "collection", "filter", "modevent", "modeventremove", "formlist", "remove", "plant", "btoys", "gtoys", "haircolors", "atronachforge", "atronachforgesigil", "dragonbornspidercrafting"}
PROFILE_EVIDENCE = {"spid": "SPID 7.3 documented grammar subset", "kid": "KID 4.0.6 documented grammar subset", "bos": "BOS 3.4.1 documented core grammar", "skypatcher": "SkyPatcher 6.4.2 placement and core rule shape", "flm": "FLM 1.8.1 documented core grammar", "cdf": "Pinned CDF JSON subset"}


def _strip_inline_comment(line: str) -> str:
    quote = ""
    escaped = False
    for index, char in enumerate(line):
        if escaped:
            escaped = False
            continue
        if char == "\\":
            escaped = True
            continue
        if char in {'"', "'"}:
            if not quote:
                quote = char
            elif quote == char:
                quote = ""
            continue
        if char == ";" and not quote:
            return line[:index].rstrip()
    return line.rstrip()


def _active(path: Path) -> list[tuple[int, str]]:
    """Yield the meaningful lines of a framework config.

    `utf-8-sig` removes one leading BOM. Real files carry more: configs
    assembled by concatenation or edited by successive tools appear in the
    reference corpus with three stacked BOMs at the top and with a BOM in the
    middle of the file where two sources were joined. A surviving U+FEFF stops a
    comment from looking like a comment and turns a valid key into an unknown
    one, so every line is stripped of it before anything else looks at it.
    """
    result = []
    for number, raw in enumerate(path.read_text(encoding="utf-8-sig", errors="replace").splitlines(), 1):
        line = _strip_inline_comment(raw).replace("﻿", "").strip()
        if line and not line.startswith((";", "#", "//")):
            result.append((number, line))
    return result


def _spid_key(key: str) -> tuple[str, str]:
    if key == "ExclusiveGroup":
        return "exclusive", key
    work = key
    linked = False
    if work.startswith("Linked"):
        linked = True
        work = work[6:]
    final = False
    if work.startswith("Final"):
        final = True
        work = work[5:]
    death = False
    if work.startswith("Death"):
        death = True
        work = work[5:]
    if work not in SPID_TYPES:
        return ("invalid" if work in SPID_KNOWN_INVALID_KEYS else "unverified"), work
    return "linked" if linked else "ordinary", work



def _spid_numeric_range(text: str, *, allow_single: bool, label: str) -> str | None:
    value = text.strip()
    if allow_single and re.fullmatch(r"\d+", value):
        return None
    match = re.fullmatch(r"(\d+)/(\d*)", value)
    if not match:
        return f"Malformed SPID {label} range {text!r}"
    minimum = int(match.group(1))
    maximum_text = match.group(2)
    if maximum_text and minimum > int(maximum_text):
        return f"SPID {label} range minimum exceeds maximum: {text!r}"
    return None


def _lint_spid_level_filters(value: str, line: int) -> list[dict[str, Any]]:
    issues: list[dict[str, Any]] = []
    actor_ranges = 0
    for raw_token in value.split(","):
        token = raw_token.strip()
        if not token or token.upper() == "NONE":
            continue
        skill = re.fullmatch(r"(w?)(\d{1,2})\(([^()]*)\)", token, flags=re.I)
        if skill:
            index = int(skill.group(2))
            if not 0 <= index <= 17:
                issues.append({"severity": "error", "line": line, "message": f"SPID skill index outside 0-17: {token!r}"})
                continue
            inner = skill.group(3).strip()
            if re.fullmatch(r"\d+", inner):
                # A single value here is NOT categorically malformed. In the
                # reference corpus 13,427 such filters are installed across
                # skill indices 12-16 and the SPID runtime log records zero
                # parse failures for them; one row was traced end to end
                # (Abyss `14(20)` -> SPEL:FE059810 distributed). The only
                # runtime rejections observed were five rows using skill index
                # 0 with a single value, alongside an actor-level range. Forge
                # cannot currently tell those apart, and refusing 13,427
                # working rows to catch 5 is the worse error, so this is
                # reported rather than failed.
                issues.append({"severity": "warning", "line": line, "code": SPID_SINGLE_SKILL, "message": f"SPID skill filter {token!r} uses a single value rather than min/max. This form is runtime-proven to work for most skill indices; a few index-0 cases were rejected by SPID. Confirm against po3_SpellPerkItemDistributor.log before changing it."})
                continue
            problem = _spid_numeric_range(inner, allow_single=False, label="skill")
            if problem:
                issues.append({"severity": "error", "line": line, "message": problem})
            continue
        actor_ranges += 1
        problem = _spid_numeric_range(token, allow_single=True, label="actor level")
        if problem:
            issues.append({"severity": "error", "line": line, "message": problem})
    if actor_ranges > 1:
        issues.append({"severity": "warning", "line": line, "message": "SPID accepts only one actor-level expression; only the last one is used"})
    return issues

def _collapse_advisories(issues: list[dict[str, Any]], code: str, summary: str) -> list[dict[str, Any]]:
    """Fold a repeated advisory into one entry naming the first line and count.

    A per-line note is right for a defect and wrong for a house style: one file
    in the reference corpus produces this note on thousands of lines, which
    buries the findings that need acting on.
    """
    tagged = [item for item in issues if item.get("code") == code]
    if len(tagged) <= 1:
        for item in tagged:
            item.pop("code", None)
        return issues
    kept = [item for item in issues if item.get("code") != code]
    first = tagged[0]
    kept.append({"severity": "warning", "line": first["line"],
                 "message": f"{summary} {len(tagged)} lines in this file, first at line {first['line']}. {first['message']}"})
    return sorted(kept, key=lambda item: item.get("line", 0))


def _lint_spid(path: Path) -> list[dict[str, Any]]:
    issues = []
    for number, line in _active(path):
        if line.startswith("["):
            continue
        if "=" not in line:
            issues.append({"severity": "error", "line": number, "message": "SPID line lacks ="})
            continue
        key, value = [part.strip() for part in line.split("=", 1)]
        family, base = _spid_key(key)
        fields = [part.strip() for part in value.split("|")]
        if family == "invalid":
            issues.append({"severity": "error", "line": number, "message": f"Known invalid SPID key {key!r}; use the documented distribution key for the form being distributed"})
            continue
        if family == "unverified":
            issues.append({"severity": "warning", "line": number, "message": f"SPID key {key!r} is outside Forge's pinned 7.3 profile; preserve it and verify against the installed SPID documentation/runtime log"})
            continue
        expected = (2, 2) if family == "exclusive" else ((1, 4) if family == "linked" else (1, 7))
        if not expected[0] <= len(fields) <= expected[1]:
            issues.append({"severity": "error", "line": number, "message": f"SPID {key} expects {expected[0]}-{expected[1]} fields; found {len(fields)}"})
            continue
        if family == "ordinary":
            fields += [""] * (7 - len(fields))
            level, traits, count, chance = fields[3], fields[4], fields[5], fields[6]
            if level and level.upper() != "NONE":
                issues.extend(_lint_spid_level_filters(level, number))
            if traits and traits.upper() != "NONE":
                for token in traits.split("/"):
                    if token.strip() not in SPID_TRAITS:
                        issues.append({"severity": "error", "line": number, "message": f"Invalid SPID trait {token.strip()!r}"})
            if chance and chance.upper() != "NONE":
                if not re.fullmatch(r"\d+(?:\.\d+)?!?", chance):
                    issues.append({"severity": "error", "line": number, "message": f"Invalid SPID chance {chance!r}"})
                else:
                    numeric = float(chance.rstrip("!"))
                    if not 0 <= numeric <= 100:
                        issues.append({"severity": "error", "line": number, "message": f"SPID chance outside 0-100: {chance!r}"})
    return _collapse_advisories(issues, SPID_SINGLE_SKILL, "SPID single-value skill filters appear on")


def _lint_kid(path: Path) -> list[dict[str, Any]]:
    issues = []
    for number, line in _active(path):
        if line.startswith("["):
            continue
        if "=" not in line:
            issues.append({"severity": "error", "line": number, "message": "KID line lacks ="})
            continue
        key, value = [part.strip() for part in line.split("=", 1)]
        fields = [part.strip() for part in value.split("|")]
        # KID reads its keys case-insensitively; `keyword = ...` is used by
        # shipping mods and distributes normally.
        folded = key.casefold()
        if folded == "exclusivegroup":
            if len(fields) != 2 or not all(fields):
                issues.append({"severity": "error", "line": number, "message": "KID ExclusiveGroup requires Group|KeywordList"})
            continue
        if folded != "keyword":
            issues.append({"severity": "error", "line": number, "message": f"Invalid KID key {key!r}"})
            continue
        if not 2 <= len(fields) <= 5:
            issues.append({"severity": "error", "line": number, "message": f"KID Keyword requires 2-5 fields; found {len(fields)}"})
            continue
        fields += [""] * (5 - len(fields))
        if fields[1] in KID_SIGNATURES:
            issues.append({"severity": "error", "line": number, "message": f"KID record signature {fields[1]!r} is invalid here; use the exact human-readable type label"})
        elif fields[1] not in KID_TYPES:
            # Field 2 is not always a type label: a two-field line filters by
            # name instead, and such lines are runtime-proven to distribute.
            # Report the unrecognised token without failing the file.
            issues.append({"severity": "warning", "line": number, "message": f"KID field 2 {fields[1]!r} is not a known type label; treated as a filter. Verify against the installed KID version."})
        if fields[4]:
            try:
                chance = float(fields[4])
                if not 0 <= chance <= 100:
                    raise ValueError
            except ValueError:
                issues.append({"severity": "error", "line": number, "message": f"Invalid KID chance {fields[4]!r}"})
    return issues


def _lint_bos(path: Path) -> list[dict[str, Any]]:
    issues = []
    section = ""
    transform = re.compile(r"(?:pos[RA]|rot[RA])\(([^)]*)\)", re.I)
    for number, line in _active(path):
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].split("|", 1)[0].strip().casefold()
            if section not in BOS_SECTIONS:
                issues.append({"severity": "warning", "line": number, "message": f"Unknown BOS section {section!r}"})
            continue
        if section not in BOS_SECTIONS:
            continue
        for match in transform.finditer(line):
            arguments = match.group(1)
            if re.search(r"\s", arguments):
                issues.append({"severity": "error", "line": number, "message": f"BOS transform arguments contain whitespace and will split: {match.group(0)!r}"})
            if len(arguments.split(",")) != 3:
                issues.append({"severity": "error", "line": number, "message": f"BOS transform requires three arguments: {match.group(0)!r}"})
    return issues


def _lint_cdf(path: Path) -> list[dict[str, Any]]:
    issues = []
    try:
        root = load(path)
    except Exception as exc:
        return [{"severity": "error", "line": 0, "message": str(exc)}]
    if not isinstance(root, dict) or not isinstance(root.get("rules"), list):
        return [{"severity": "error", "line": 0, "message": "CDF root.rules must be an array"}]
    for ri, rule in enumerate(root["rules"]):
        if not isinstance(rule, dict) or not isinstance(rule.get("changes"), list):
            issues.append({"severity": "error", "line": 0, "message": f"CDF rules[{ri}].changes must be an array"})
            continue
        for ci, change in enumerate(rule["changes"]):
            if not isinstance(change, dict):
                issues.append({"severity": "error", "line": 0, "message": f"CDF rules[{ri}].changes[{ci}] must be an object"})
                continue
            add = change.get("add")
            if add is not None:
                if not isinstance(add, list) or not all(isinstance(item, str) for item in add):
                    issues.append({"severity": "error", "line": 0, "message": f"CDF rules[{ri}].changes[{ci}].add must be a string array"})
                else:
                    for item in add:
                        if item.startswith("*"):
                            issues.append({"severity": "error", "line": 0, "message": f"CDF wildcard-like add form is unsupported: {item!r}"})
    return issues


def _lint_skypatcher(path: Path) -> list[dict[str, Any]]:
    parts = [part.casefold() for part in path.parts]
    issues: list[dict[str, Any]] = []
    if "skypatcher" in parts:
        index = parts.index("skypatcher")
        if index + 1 >= len(parts) - 1:
            issues.append({"severity": "error", "line": 0, "message": "SkyPatcher INI must be beneath a category directory"})
        elif parts[index + 1] not in SKYPATCHER_CATEGORIES:
            issues.append({"severity": "warning", "line": 0, "message": f"SkyPatcher category {parts[index + 1]!r} is not in Forge's pinned profile; leave unchanged until checked against the installed version"})
    for number, line in _active(path):
        if line.startswith("["):
            issues.append({"severity": "warning", "line": number, "message": "Sectioned SkyPatcher syntax is outside Forge's core rule profile and was not semantically validated"})
            continue
        if ":" not in line:
            issues.append({"severity": "warning", "line": number, "message": "SkyPatcher line is outside the modeled filter:patch rule shape; verify with the category documentation/runtime log"})
            continue
        left, right = line.split(":", 1)
        if not left.strip() or not right.strip():
            issues.append({"severity": "error", "line": number, "message": "SkyPatcher rule requires non-empty filter and patch sides"})
        # A rule is `key=value` clauses separated by ':'. A clause VALUE is
        # frequently a comma-separated list of forms:
        #   filterByLLNPCs=Skyrim.esm|0x01E78D:removeFromLLs=A.esp|001DBD, A.esp|001DC8
        # Splitting a side on ',' and demanding '=' in every element therefore
        # reported each form after the first as unmodeled syntax. Validate the
        # clause, not the list items.
        for side_name, side in (("filter", left), ("patch", right)):
            for clause in side.split(":"):
                if clause.strip() and "=" not in clause:
                    issues.append({"severity": "warning", "line": number, "message": f"SkyPatcher {side_name} clause lacks '=' and is outside the modeled profile: {clause.strip()[:80]!r}"})
    return issues


def _lint_flm(path: Path) -> list[dict[str, Any]]:
    issues: list[dict[str, Any]] = []
    for number, line in _active(path):
        if "=" not in line:
            issues.append({"severity": "error", "line": number, "message": "FLM line lacks ="})
            continue
        key, value = [part.strip() for part in line.split("=", 1)]
        if key.casefold() not in FLM_KEYS:
            issues.append({"severity": "warning", "line": number, "message": f"FLM key {key!r} is not in Forge's 1.8.1 core profile; verify before editing"})
        if not value:
            issues.append({"severity": "error", "line": number, "message": f"FLM {key} has no value"})
        if key.casefold() in {"formlist", "remove", "modevent", "modeventremove", "alias", "collection", "filter"} and "|" not in value:
            issues.append({"severity": "error", "line": number, "message": f"FLM {key} requires pipe-delimited fields"})
    return issues


def lint_file(path: Path) -> list[dict[str, Any]]:
    name = path.name.casefold()
    if name.endswith("_distr.ini"):
        return _lint_spid(path)
    if name.endswith("_kid.ini"):
        return _lint_kid(path)
    if name.endswith("_swap.ini"):
        return _lint_bos(path)
    if path.suffix.casefold() == ".json" and "cdf" in name:
        return _lint_cdf(path)
    if path.suffix.casefold() == ".ini" and "skypatcher" in [part.casefold() for part in path.parts]:
        return _lint_skypatcher(path)
    if name.endswith("_flm.ini") or (path.suffix.casefold() == ".ini" and "flm" in [part.casefold() for part in path.parts]):
        return _lint_flm(path)
    return []


def lint_paths(paths: list[Path]) -> dict[str, Any]:
    files = []
    for path in paths:
        if path.is_dir():
            files.extend(item for item in path.rglob("*") if item.is_file() and item.suffix.casefold() in {".ini", ".json"})
        else:
            files.append(path)
    reports = []
    errors = warnings = 0
    for path in sorted(set(files), key=lambda p: p.as_posix().casefold()):
        issues = lint_file(path)
        if issues:
            reports.append({"path": str(path), "issues": issues})
        errors += sum(item["severity"] == "error" for item in issues)
        warnings += sum(item["severity"] == "warning" for item in issues)
    return {
        "result": "PASS" if errors == 0 else "FAIL",
        "files_scanned": len(set(files)),
        "errors": errors,
        "warnings": warnings,
        "reports": reports,
        "profiles": PROFILE_EVIDENCE,
        "evidence": "Static version-profile grammar and placement validation. Unknown/version-specific syntax is warning-level where possible. Runtime form resolution and logs remain separate.",
    }


def self_test() -> dict[str, Any]:
    import tempfile
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        good = root / "good_DISTR.ini"
        good.write_text("DeathItem = 0x123~A.esp||||||18! ; comment\nExclusiveGroup = G|0x123~A.esp\n", encoding="utf-8")
        composite = root / "composite_DISTR.ini"
        composite.write_text("Perk = 0x1~A.esp|||25/255,0(55/255)|||100\n", encoding="utf-8")
        bad = root / "bad_DISTR.ini"
        bad.write_text("Weapon = 0x1~A.esp|||10/24,0(25)|||10\n", encoding="utf-8")
        kid = root / "test_KID.ini"
        kid.write_text("ExclusiveGroup = G|A,B\nKeyword = MyKeyword|Weapon|||100\n", encoding="utf-8")
        kid_bad = root / "bad_KID.ini"
        kid_bad.write_text("Keyword = MyKeyword|WEAP|||100\n", encoding="utf-8")
        bos = root / "test_SWAP.ini"
        bos.write_text("[Transforms]\n0x1~A.esp|rotR(147.9, 355.9, 82.7)\n", encoding="utf-8")
        assertions = {
            "spid_special_keys": not _lint_spid(good),
            "spid_actor_and_skill_range": not _lint_spid(composite),
            "spid_single_value_skill_rejected": bool(_lint_spid(bad)),
            "kid_exclusive_and_type": not _lint_kid(kid),
            "kid_signature_rejected": bool(_lint_kid(kid_bad)),
            "bos_whitespace_rejected": bool(_lint_bos(bos)),
        }
        return {"result": "PASS" if all(assertions.values()) else "FAIL", "assertions": assertions}
