#!/usr/bin/env python3
"""Conservative classifier for common Skyrim runtime-log failures.

This tool recognizes evidence patterns. It does not edit files or identify an
unproven culprit.
"""
from __future__ import annotations
import argparse
import re
from pathlib import Path

SPID_KEYS = {
    "Form","Spell","Perk","Item","Shout","LevSpell","Package","Outfit",
    "Keyword","Faction","SleepOutfit","Skin","FinalOutfit"
}
TRAITS = {"M","-F","F","-M","U","-U","S","-S","C","-C","L","-L","T","-T","D","-D"}
NUM = re.compile(r"^\d+(?:\.\d+)?$")
LEVEL_EXACT = re.compile(r"^\d+$")
SKILL = re.compile(r"^w?\d+\(\d+(?:/\d+)?\)$", re.I)
CHANCE = re.compile(r"^(?:100(?:\.0+)?|\d{1,2}(?:\.\d+)?)(?:!)?$")

def diagnose_spid(key: str, rhs: str, reason: str) -> list[str]:
    out=[]
    fields=[x.strip() for x in rhs.split("|")]
    if key not in SPID_KEYS:
        out.append(f"unsupported SPID key {key!r}; current keys do not include Weapon")
    if len(fields)>7:
        out.append(f"too many SPID value sections: {len(fields)} > 7")
    fields += [""]*(7-len(fields))
    level=fields[3]
    traits=fields[4]
    count=fields[5]
    chance=fields[6]
    if level and level.upper()!="NONE":
        for token in level.split(","):
            token=token.strip()
            if "/" in token and not SKILL.fullmatch(token):
                parts=token.split("/")
                if len(parts)!=2 or not all(parts):
                    out.append(f"malformed LevelFilters range {token!r}: both endpoints are required")
                elif not all(x.isdigit() for x in parts):
                    out.append(f"malformed numeric LevelFilters range {token!r}")
            elif not LEVEL_EXACT.fullmatch(token) and not SKILL.fullmatch(token):
                out.append(f"unverified/malformed LevelFilters token {token!r}")
    if traits and traits.upper()!="NONE":
        if "," in traits:
            out.append("TraitFilters use '/', not comma")
        for token in traits.split("/"):
            if token not in TRAITS:
                out.append(f"invalid/unrecognized TraitFilters token {token!r}")
    if count and count.upper()!="NONE":
        if not re.fullmatch(r"\d+(?:-\d+)?",count):
            out.append(f"invalid index/count {count!r}")
    if chance and chance.upper()!="NONE" and not CHANCE.fullmatch(chance):
        out.append(f"invalid chance {chance!r}; optional trailing ! is allowed")
    if "stoul" in reason.lower() and not out:
        out.append("numeric parse failed; inspect LevelFilters and index/count before blaming traits or deterministic chance")
    return out

def analyze_line(line: str) -> list[str]:
    findings=[]
    m=re.search(r"Failed to parse entry \[([^=\]]+?)\s*=\s*(.*?)\]\s*:\s*(.*)$",line,re.I)
    if m:
        key=m.group(1).strip()
        findings += ["SPID: "+x for x in diagnose_spid(key,m.group(2),m.group(3))]
    if re.search(r"RVA=.*outside \.text",line,re.I):
        findings.append("HOOK: target is outside expected executable .text; feature abort is justified, culprit is unproven")
    m=re.search(r"([A-Za-z0-9_ -]+\.ini) failed to load, feature disabled",line,re.I)
    if m:
        findings.append(f"CS: feature descriptor {m.group(1)!r} was not loaded; inspect Data\\Shaders\\Features and deployed winner")
    if "__folder_managed_by_vortex" in line.lower():
        findings.append("PACKAGE: Vortex bookkeeping marker reached a runtime config scanner; remove it from the owning source package and redeploy")
    if re.search(r"\.hkx",line,re.I) and re.search(r"missing|not found|failed",line,re.I):
        findings.append("ANIMATION: missing HKX requires owner/archive/behavior-path resolution; a generator cannot invent absent custom assets")
    if re.search(r"invalid add data\s*-\s*missing form",line,re.I):
        findings.append("CDF: exact add form did not resolve; wildcard-like strings are not expanded and the change may be skipped")
    if re.search(r"plugin file not found|formid doesn't exist|editorid doesn't exist|does not exist!",line,re.I):
        findings.append("DEPENDENCY: unresolved target; classify required, conditional, optional, or stale before editing")
    if re.search(r"winning swap",line,re.I):
        findings.append("BOS: deterministic winner logged; semantic correctness still requires reference/worldspace/condition review")
    return findings

def self_test():
    cases={
        "Failed to parse entry [Weapon = 0x1~A.esp||||||100]: Unsupported form type Weapon":
            ["unsupported SPID key"],
        "Failed to parse entry [Perk = 0x1~A.esp|ActorTypeNPC||65/|-C/-D||18!]: invalid stoul argument":
            ["malformed LevelFilters range"],
        "Failed to parse entry [Faction = 0x800~A.esp|ActorTypeNPC||||F,-C|0|100]: Too many sections":
            ["too many SPID","invalid index/count"],
        "CombatLootBlocker: UpdateCombat RVA=0x123 outside .text":
            ["culprit is unproven"],
        "ImageBasedLighting.ini failed to load, feature disabled":
            ["Data\\Shaders\\Features"],
        "NWV contains invalid add data - missing form *Claw":
            ["wildcard-like"],
    }
    for line,needles in cases.items():
        result=" | ".join(analyze_line(line))
        for needle in needles:
            assert needle.lower() in result.lower(),(line,result,needle)
    # Valid traits/chance must not be blamed.
    result=" | ".join(analyze_line(
        "Failed to parse entry [Perk = 0x1~A.esp|ActorTypeNPC||65/|-C/-D||18!]: invalid stoul argument"
    ))
    assert "invalid chance" not in result.lower()
    assert "invalid/unrecognized trait" not in result.lower()
    print("SELF-TEST: PASS")

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("logs",nargs="*")
    ap.add_argument("--self-test",action="store_true")
    args=ap.parse_args()
    if args.self_test:
        self_test(); return
    total=0
    for raw in args.logs:
        p=Path(raw)
        for no,line in enumerate(p.read_text(encoding="utf-8",errors="replace").splitlines(),1):
            findings=analyze_line(line)
            for f in findings:
                print(f"{p}:{no}: {f}")
                total+=1
    print(f"FINDINGS: {total}")
if __name__=="__main__":
    main()
