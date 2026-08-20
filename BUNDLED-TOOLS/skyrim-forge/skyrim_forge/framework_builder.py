from __future__ import annotations

import os
import re
import tempfile
from pathlib import Path
from typing import Any

from .errors import SafetyError, ValidationError
from .frameworks import KID_TYPES, SPID_TRAITS, SPID_TYPES, lint_file
from .safety import require_approval, require_within
from .strictjson import load
from .util import atomic_write_text

SCHEMA = "skyrim-forge-framework-plan/1"
PROFILES = {
    "spid-7.3": {"framework": "SPID", "version": "7.3", "suffix": "_DISTR.ini"},
    "kid-4.0.6": {"framework": "KID", "version": "4.0.6", "suffix": "_KID.ini"},
    "bos-3.4.1": {"framework": "BOS", "version": "3.4.1", "suffix": "_SWAP.ini"},
    "skypatcher-6.4.2": {"framework": "SkyPatcher", "version": "6.4.2", "suffix": ".ini"},
    "flm-1.8.1": {"framework": "FLM", "version": "1.8.1", "suffix": "_FLM.ini"},
}
FLM_KEYS = {"Alias", "Group", "Collection", "Filter", "ModEvent", "ModEventRemove", "FormList", "Remove", "Plant", "BToys", "GToys", "HairColors", "AtronachForge", "AtronachForgeSigil", "DragonbornSpiderCrafting"}
BOS_SECTIONS = {"Forms", "References", "Transforms", "Properties"}
SKYPATCHER_CATEGORIES = {"npc", "weapon", "armor", "ammo", "race", "spell", "scroll", "alchemy", "book", "cell", "constructibleobject", "container", "enchantment", "formlist", "leveledlist", "location", "magiceffect", "other"}


def _obj(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValidationError(f"{label} must be an object")
    return value


def _list(value: Any, label: str) -> list[Any]:
    if not isinstance(value, list):
        raise ValidationError(f"{label} must be an array")
    return value


def _text(value: Any, label: str, *, required: bool = True, allow_pipe: bool = True, allow_colon: bool = True, allow_equals: bool = True) -> str:
    if value is None and not required:
        return ""
    if not isinstance(value, str):
        raise ValidationError(f"{label} must be a string")
    text = value.strip()
    if required and not text:
        raise ValidationError(f"{label} must not be empty")
    if any(char in text for char in "\r\n\x00"):
        raise ValidationError(f"{label} contains a control character")
    for allowed, char in ((allow_pipe, "|"), (allow_colon, ":"), (allow_equals, "=")):
        if not allowed and char in text:
            raise ValidationError(f"{label} contains reserved delimiter {char!r}")
    return text


def _safe_filename(value: Any, profile: str) -> str:
    name = _text(value, "output_file").replace("\\", "/")
    if "/" in name or name in {".", ".."} or re.match(r"^[A-Za-z]:", name):
        raise ValidationError("output_file must be a simple filename")
    if not name.casefold().endswith(PROFILES[profile]["suffix"].casefold()):
        raise ValidationError(f"output_file for {profile} must end with {PROFILES[profile]['suffix']}")
    return name


def _string_array(value: Any, label: str, **kwargs: Any) -> list[str]:
    return [_text(item, f"{label}[{i}]", **kwargs) for i, item in enumerate(_list(value, label))]


def validate_plan(data: Any) -> dict[str, Any]:
    root = _obj(data, "framework plan")
    allowed = {"schema", "profile", "output_file", "category", "header", "entries"}
    unknown = set(root) - allowed
    if unknown:
        raise ValidationError(f"Unknown framework plan fields: {sorted(unknown)}")
    if root.get("schema") != SCHEMA:
        raise ValidationError(f"framework plan schema must be {SCHEMA!r}")
    profile = _text(root.get("profile"), "profile")
    if profile not in PROFILES:
        raise ValidationError(f"Unsupported framework profile: {profile!r}")
    entries = _list(root.get("entries", []), "entries")
    if not entries:
        raise ValidationError("entries must not be empty")
    normalized: list[dict[str, Any]] = []
    if profile == "spid-7.3":
        for i, raw in enumerate(entries):
            label=f"entries[{i}]"; item=_obj(raw,label)
            fields={"type","form","string_filters","form_filters","level_filters","traits","count","chance","linked_path","exclusive_group","comment"}
            if set(item)-fields: raise ValidationError(f"Unknown SPID fields in {label}: {sorted(set(item)-fields)}")
            key=_text(item.get("type"),f"{label}.type")
            work=key
            for prefix in ("Linked","Final","Death"):
                if work.startswith(prefix): work=work[len(prefix):]
            if key != "ExclusiveGroup" and work not in SPID_TYPES: raise ValidationError(f"Unsupported SPID type: {key}")
            if key == "ExclusiveGroup":
                normalized.append({"type":key,"exclusive_group":_text(item.get("exclusive_group"),f"{label}.exclusive_group"),"form":_text(item.get("form"),f"{label}.form"),"comment":_text(item.get("comment",""),f"{label}.comment",required=False)})
            elif key.startswith("Linked"):
                normalized.append({"type":key,"form":_text(item.get("form"),f"{label}.form"),"linked_path":_text(item.get("linked_path"),f"{label}.linked_path"),"comment":_text(item.get("comment",""),f"{label}.comment",required=False)})
            else:
                traits=_string_array(item.get("traits",[]),f"{label}.traits",allow_pipe=False)
                invalid=sorted(set(traits)-SPID_TRAITS)
                if invalid: raise ValidationError(f"Unsupported SPID traits: {invalid}")
                normalized.append({"type":key,"form":_text(item.get("form"),f"{label}.form"),"string_filters":_string_array(item.get("string_filters",[]),f"{label}.string_filters",allow_pipe=False),"form_filters":_string_array(item.get("form_filters",[]),f"{label}.form_filters",allow_pipe=False),"level_filters":_string_array(item.get("level_filters",[]),f"{label}.level_filters",allow_pipe=False),"traits":traits,"count":_text(item.get("count",""),f"{label}.count",required=False,allow_pipe=False),"chance":_text(item.get("chance",""),f"{label}.chance",required=False,allow_pipe=False),"comment":_text(item.get("comment",""),f"{label}.comment",required=False)})
    elif profile == "kid-4.0.6":
        for i, raw in enumerate(entries):
            label=f"entries[{i}]"; item=_obj(raw,label); fields={"keyword","record_type","filters","traits","chance","exclusive_group","comment"}
            if set(item)-fields: raise ValidationError(f"Unknown KID fields in {label}: {sorted(set(item)-fields)}")
            if item.get("exclusive_group"):
                normalized.append({"exclusive_group":_text(item["exclusive_group"],f"{label}.exclusive_group"),"keyword":_text(item.get("keyword"),f"{label}.keyword"),"comment":_text(item.get("comment",""),f"{label}.comment",required=False)})
            else:
                record_type=_text(item.get("record_type"),f"{label}.record_type")
                if record_type not in KID_TYPES: raise ValidationError(f"Unsupported KID type label: {record_type}")
                normalized.append({"keyword":_text(item.get("keyword"),f"{label}.keyword"),"record_type":record_type,"filters":_string_array(item.get("filters",[]),f"{label}.filters",allow_pipe=False),"traits":_string_array(item.get("traits",[]),f"{label}.traits",allow_pipe=False),"chance":_text(item.get("chance",""),f"{label}.chance",required=False,allow_pipe=False),"comment":_text(item.get("comment",""),f"{label}.comment",required=False)})
    elif profile == "bos-3.4.1":
        for i, raw in enumerate(entries):
            label=f"entries[{i}]"; item=_obj(raw,label); fields={"section","conditions","originals","replacements","properties","chance","comment"}
            if set(item)-fields: raise ValidationError(f"Unknown BOS fields in {label}: {sorted(set(item)-fields)}")
            section=_text(item.get("section"),f"{label}.section")
            if section not in BOS_SECTIONS: raise ValidationError(f"Unsupported BOS section: {section}")
            originals=_string_array(item.get("originals",[]),f"{label}.originals",allow_pipe=False)
            if not originals: raise ValidationError(f"{label}.originals must not be empty")
            replacements=_string_array(item.get("replacements",[]),f"{label}.replacements",allow_pipe=False)
            if section in {"Forms","References"} and not replacements: raise ValidationError(f"{label}.replacements must not be empty")
            normalized.append({"section":section,"conditions":_string_array(item.get("conditions",[]),f"{label}.conditions",allow_pipe=False),"originals":originals,"replacements":replacements,"properties":_string_array(item.get("properties",[]),f"{label}.properties",allow_pipe=False),"chance":_text(item.get("chance",""),f"{label}.chance",required=False,allow_pipe=False),"comment":_text(item.get("comment",""),f"{label}.comment",required=False)})
    elif profile == "skypatcher-6.4.2":
        category=_text(root.get("category"),"category").casefold()
        if category not in SKYPATCHER_CATEGORIES: raise ValidationError(f"Unsupported SkyPatcher category: {category}")
        for i, raw in enumerate(entries):
            label=f"entries[{i}]"; item=_obj(raw,label); fields={"filters","patches","comment"}
            if set(item)-fields: raise ValidationError(f"Unknown SkyPatcher fields in {label}: {sorted(set(item)-fields)}")
            def pairs(raw_pairs:Any,name:str)->list[dict[str,str]]:
                result=[]
                for j,pair_raw in enumerate(_list(raw_pairs,name)):
                    pair=_obj(pair_raw,f"{name}[{j}]")
                    if set(pair)!={"key","value"}: raise ValidationError(f"{name}[{j}] requires exactly key and value")
                    result.append({"key":_text(pair["key"],f"{name}[{j}].key",allow_colon=False,allow_equals=False),"value":_text(pair["value"],f"{name}[{j}].value",allow_colon=False)})
                return result
            filters=pairs(item.get("filters",[]),f"{label}.filters"); patches=pairs(item.get("patches",[]),f"{label}.patches")
            if not filters or not patches: raise ValidationError(f"{label} requires at least one filter and one patch")
            normalized.append({"filters":filters,"patches":patches,"comment":_text(item.get("comment",""),f"{label}.comment",required=False)})
    else:
        for i, raw in enumerate(entries):
            label=f"entries[{i}]"; item=_obj(raw,label); fields={"key","fields","comment"}
            if set(item)-fields: raise ValidationError(f"Unknown FLM fields in {label}: {sorted(set(item)-fields)}")
            key=_text(item.get("key"),f"{label}.key")
            if key not in FLM_KEYS: raise ValidationError(f"Unsupported FLM key: {key}")
            values=_string_array(item.get("fields",[]),f"{label}.fields",allow_pipe=False)
            if not values: raise ValidationError(f"{label}.fields must not be empty")
            normalized.append({"key":key,"fields":values,"comment":_text(item.get("comment",""),f"{label}.comment",required=False)})
    return {"schema":SCHEMA,"profile":profile,"output_file":_safe_filename(root.get("output_file"),profile),"category":root.get("category","").strip().casefold() if isinstance(root.get("category",""),str) else "","header":_text(root.get("header","Generated by Skyrim Forge"),"header",required=False),"entries":normalized}


def render(plan: dict[str, Any]) -> str:
    profile=plan["profile"]; rows=[]
    if plan["header"]: rows.append(f"; {plan['header']}")
    if profile == "spid-7.3":
        for item in plan["entries"]:
            if item["comment"]: rows.append(f"; {item['comment']}")
            if item["type"] == "ExclusiveGroup": rows.append(f"ExclusiveGroup = {item['exclusive_group']}|{item['form']}")
            elif item["type"].startswith("Linked"): rows.append(f"{item['type']} = {item['form']}|{item['linked_path']}")
            else:
                fields=[item["form"],",".join(item["string_filters"]),",".join(item["form_filters"]),",".join(item["level_filters"]),"/".join(item["traits"]),item["count"],item["chance"]]
                while fields and fields[-1] == "": fields.pop()
                rows.append(f"{item['type']} = " + "|".join(fields))
    elif profile == "kid-4.0.6":
        for item in plan["entries"]:
            if item["comment"]: rows.append(f"; {item['comment']}")
            if "exclusive_group" in item: rows.append(f"ExclusiveGroup = {item['exclusive_group']}|{item['keyword']}")
            else:
                fields=[item["keyword"],item["record_type"],",".join(item["filters"]),",".join(item["traits"]),item["chance"]]
                while fields and fields[-1] == "": fields.pop()
                rows.append("Keyword = " + "|".join(fields))
    elif profile == "bos-3.4.1":
        current=None
        for item in plan["entries"]:
            section=item["section"] + (("|" + ",".join(item["conditions"])) if item["conditions"] else "")
            if section != current: rows.append(f"[{section}]"); current=section
            if item["comment"]: rows.append(f"; {item['comment']}")
            fields=[",".join(item["originals"]),",".join(item["replacements"]),",".join(item["properties"]),item["chance"]]
            while fields and fields[-1] == "": fields.pop()
            rows.append("|".join(fields))
    elif profile == "skypatcher-6.4.2":
        for item in plan["entries"]:
            if item["comment"]: rows.append(f"; {item['comment']}")
            left=",".join(f"{pair['key']}={pair['value']}" for pair in item["filters"])
            right=",".join(f"{pair['key']}={pair['value']}" for pair in item["patches"])
            rows.append(f"{left}:{right}")
    else:
        for item in plan["entries"]:
            if item["comment"]: rows.append(f"; {item['comment']}")
            rows.append(f"{item['key']} = " + "|".join(item["fields"]))
    return "\n".join(rows)+"\n"


def build(plan_path: Path, output_root: Path, workspace_root: Path, *, approved: bool) -> dict[str, Any]:
    require_approval(approved,"framework configuration build")
    plan=validate_plan(load(plan_path))
    root=require_within(output_root,workspace_root)
    root.mkdir(parents=True,exist_ok=True)
    if plan["profile"] == "skypatcher-6.4.2":
        target=root/"SKSE"/"Plugins"/"SkyPatcher"/plan["category"]/plan["output_file"]
    else:
        target=root/plan["output_file"]
    if target.exists(): raise SafetyError(f"Refusing to overwrite framework file: {target}")
    target.parent.mkdir(parents=True,exist_ok=True)
    text=render(plan)
    transaction=Path(tempfile.mkdtemp(prefix=f".{target.name}.framework-",dir=target.parent))
    staged=transaction/target.name
    try:
        atomic_write_text(staged,text)
        issues=lint_file(staged)
        if plan["profile"] == "skypatcher-6.4.2":
            # Placement is part of the SkyPatcher contract, so validate through a staged canonical tree.
            canonical=transaction/"SKSE"/"Plugins"/"SkyPatcher"/plan["category"]/target.name
            canonical.parent.mkdir(parents=True,exist_ok=True)
            os.replace(staged,canonical)
            staged=canonical
            issues=lint_file(staged)
        errors=[item for item in issues if item["severity"]=="error"]
        if errors: raise ValidationError(f"Generated framework file failed profile lint: {errors}")
        target.parent.mkdir(parents=True,exist_ok=True)
        os.replace(staged,target)
    finally:
        import shutil
        shutil.rmtree(transaction,ignore_errors=True)
    return {"result":"PASS","profile":plan["profile"],"output":str(target),"sha256":__import__("hashlib").sha256(target.read_bytes()).hexdigest(),"issues":lint_file(target),"evidence":"Generated from a typed pinned profile. Runtime form resolution and framework logs remain required."}


def self_test() -> dict[str, Any]:
    fixtures = {
        "spid": {"schema": SCHEMA, "profile": "spid-7.3", "output_file": "Self_DISTR.ini", "entries": [{"type": "Perk", "form": "0x1~A.esp", "level_filters": ["25/255", "0(55/255)"], "chance": "100"}]},
        "kid": {"schema": SCHEMA, "profile": "kid-4.0.6", "output_file": "Self_KID.ini", "entries": [{"keyword": "SelfKeyword", "record_type": "Weapon", "filters": ["IronSword"], "chance": "100"}]},
        "bos": {"schema": SCHEMA, "profile": "bos-3.4.1", "output_file": "Self_SWAP.ini", "entries": [{"section": "Forms", "originals": ["0x1~A.esp"], "replacements": ["0x2~B.esp"]}]},
        "skypatcher": {"schema": SCHEMA, "profile": "skypatcher-6.4.2", "category": "weapon", "output_file": "Self.ini", "entries": [{"filters": [{"key": "filterByKeywords", "value": "Skyrim.esm|1E715"}], "patches": [{"key": "attackDamage", "value": "30"}]}]},
        "flm": {"schema": SCHEMA, "profile": "flm-1.8.1", "output_file": "Self_FLM.ini", "entries": [{"key": "FormList", "fields": ["0x1~A.esp", "0x2~B.esp"]}]},
    }
    assertions: dict[str, bool] = {}
    with tempfile.TemporaryDirectory() as td:
        root = Path(td); workspace = root / "work"; workspace.mkdir()
        for name, value in fixtures.items():
            plan = root / f"{name}.json"
            import json
            plan.write_text(json.dumps(value), encoding="utf-8")
            try:
                report = build(plan, workspace / name, workspace, approved=True)
                assertions[name] = report["result"] == "PASS" and Path(report["output"]).is_file()
            except Exception:
                assertions[name] = False
    return {"result": "PASS" if all(assertions.values()) else "FAIL", "assertions": assertions}
