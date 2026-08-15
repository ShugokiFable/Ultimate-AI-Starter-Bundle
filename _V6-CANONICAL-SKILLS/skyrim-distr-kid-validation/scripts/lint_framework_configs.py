#!/usr/bin/env python3
"""Field-aware validator for source-locked Skyrim framework contracts.

The validator mirrors the pinned parsers instead of reducing every INI to one
key list and one field layout. Parser/runtime evidence outranks this script.
"""
from __future__ import annotations
import argparse
import re
from pathlib import Path

KID_TYPES={
    "Weapon","Armor","Ammo","Magic Effect","Potion","Scroll","Location",
    "Ingredient","Book","Misc Item","Key","Soul Gem","Spell","Activator",
    "Flora","Furniture","Race","Talking Activator","Enchantment"
}
KID_SIGNATURES={
    "WEAP","ARMO","AMMO","MGEF","ALCH","SCRL","LCTN","INGR","BOOK","MISC",
    "KEYM","SLGM","SPEL","ACTI","FLOR","FURN","RACE","TACT","ENCH"
}
SPID_BASE_TYPES={
    "Form","Spell","Perk","Item","Shout","LevSpell","Package","Outfit",
    "Keyword","Faction","SleepOutfit","Skin"
}
SPID_TRAITS={"M","-F","F","-M","U","-U","S","-S","C","-C","L","-L","T","-T","D","-D"}
BOS_SECTIONS={"forms","references","transforms","properties"}
SKYPATCHER_CATEGORIES={
    "npc","weapon","armor","ammo","race","spell","scroll","alchemy","book",
    "cell","constructibleobject","container","enchantment","formlist",
    "leveledlist","location","magiceffect","other"
}
NUMBER=r"(?:\d+(?:\.\d+)?)"
CHANCE_RE=re.compile(rf"^(?:{NUMBER})(?:!)?$")
COUNT_RE=re.compile(r"^\d+(?:-\d+)?$")
SKILL_RE=re.compile(r"^w?\d+\(\d+(?:/\d+)?\)$",re.I)
ACTOR_RANGE_RE=re.compile(r"^\d+/\d+$")
BOS_FUNCTION_RE=re.compile(r"^(pos[RA]|rot[RA]|scaleA?|flagsC?)\(([^()]*)\)$",re.I)
BOS_CHANCE_RE=re.compile(r"^chance[SRL]?\(([^()]*)\)$",re.I)

def strip_inline_comment(line):
    quote=None
    escaped=False
    for i,ch in enumerate(line):
        if escaped:
            escaped=False; continue
        if ch=="\\":
            escaped=True; continue
        if quote:
            if ch==quote: quote=None
            continue
        if ch in {'"',"'"}:
            quote=ch; continue
        if ch==';':
            return line[:i].rstrip()
    return line.rstrip()

def rhs(line): return line.split("=",1)[1].strip() if "=" in line else ""
def pad(fields,n): return fields+[""]*(n-len(fields))

def active_lines(path):
    text=path.read_text(encoding="utf-8-sig",errors="replace")
    rows=[]
    for n,raw in enumerate(text.splitlines(),1):
        line=raw.strip()
        if not line or line.startswith((";","#","//")): continue
        line=strip_inline_comment(line).strip()
        if line: rows.append((n,line))
    return rows

def classify_spid_key(key):
    if key=="ExclusiveGroup": return {"family":"exclusive"}
    original=key
    linked=False; global_scope=False; final=False; death=False
    if key.startswith("Global"):
        global_scope=True; key=key[6:]
    if key.startswith("Linked"):
        linked=True; key=key[6:]
        if key.startswith("Final"):
            final=True; key=key[5:]
        if key.startswith("Death"):
            death=True; key=key[5:]
    else:
        if global_scope: return None
        if key.startswith("Final"):
            final=True; key=key[5:]
        if key.startswith("Death"):
            death=True; key=key[5:]
    if key not in SPID_BASE_TYPES: return None
    return {"family":"linked" if linked else "standard","type":key,"final":final,"death":death,"global":global_scope,"original":original}

def lint_spid_level(value,n,errors):
    if not value or value.upper()=="NONE": return
    for raw in value.split(","):
        token=raw.strip()
        if not token: errors.append((n,"empty SPID LevelFilters token")); continue
        if SKILL_RE.fullmatch(token): continue
        if "/" in token:
            pieces=token.split("/")
            if len(pieces)!=2 or not pieces[0] or not pieces[1]:
                errors.append((n,f"malformed SPID LevelFilters range {token!r}; both endpoints are required"))
            elif not ACTOR_RANGE_RE.fullmatch(token):
                errors.append((n,f"SPID actor-level range must contain two integers: {token!r}"))
        elif not token.isdigit(): errors.append((n,f"unverified/malformed SPID LevelFilters token {token!r}"))

def lint_spid_traits(value,n,errors):
    if not value or value.upper()=="NONE": return
    if "," in value: errors.append((n,"SPID TraitFilters combine with '/', not comma"))
    for raw in value.split("/"):
        token=raw.strip()
        if not token: errors.append((n,"empty SPID trait token"))
        elif token not in SPID_TRAITS: errors.append((n,f"invalid/unrecognized SPID trait token {token!r}"))

def lint_spid_count(value,key_type,n,errors):
    if not value or value.upper()=="NONE": return
    if key_type=="Package":
        if not value.isdigit(): errors.append((n,f"SPID Package index must be one integer, got {value!r}"))
    elif not COUNT_RE.fullmatch(value): errors.append((n,f"SPID IndexOrCount must be integer or min-max range, got {value!r}"))

def lint_spid_chance(value,n,errors):
    if not value or value.upper()=="NONE": return
    if not CHANCE_RE.fullmatch(value):
        errors.append((n,f"SPID Chance must be numeric with optional single trailing !, got {value!r}")); return
    chance=float(value[:-1] if value.endswith("!") else value)
    if chance<0 or chance>100: errors.append((n,f"SPID Chance outside 0-100: {value!r}"))

def split_bos_functions(value):
    tokens=[]; start=0; depth=0
    for i,ch in enumerate(value):
        if ch=="(": depth+=1
        elif ch==")":
            depth-=1
            if depth<0: return [],"unbalanced closing parenthesis"
        elif ch=="," and depth==0:
            tokens.append(value[start:i].strip()); start=i+1
    if depth!=0: return [],"unbalanced parentheses"
    tokens.append(value[start:].strip())
    return [x for x in tokens if x],None

def lint_bos_properties(value,n,errors):
    if not value or value.upper()=="NONE": return
    tokens,problem=split_bos_functions(value)
    if problem: errors.append((n,f"BOS property list has {problem}")); return
    for token in tokens:
        m=BOS_FUNCTION_RE.fullmatch(token)
        if not m: errors.append((n,f"unsupported/malformed BOS property token {token!r}")); continue
        fname,args=m.groups()
        if re.search(r"\s",args): errors.append((n,f"BOS {fname} arguments contain whitespace and split in the pinned parser: {token!r}"))
        parts=args.split(",")
        if fname.lower().startswith(("pos","rot")):
            if len(parts)!=3: errors.append((n,f"BOS {fname} requires three comma-separated arguments"))
            for part in parts:
                for endpoint in part.split("/"):
                    try: float(endpoint)
                    except ValueError: errors.append((n,f"BOS {fname} argument is not numeric: {endpoint!r}"))
        elif fname.lower().startswith("scale"):
            if len(parts)!=1: errors.append((n,f"BOS {fname} accepts one value/range"))
            for endpoint in args.split("/"):
                try: float(endpoint)
                except ValueError: errors.append((n,f"BOS {fname} argument is not numeric: {endpoint!r}"))
        elif fname.lower().startswith("flags"):
            if len(parts)!=1 or not re.fullmatch(r"(?:0x)?[0-9a-fA-F]+",args): errors.append((n,f"BOS {fname} requires one hexadecimal/integer flag value"))

def lint_bos_chance(value,n,errors):
    if not value or value.upper()=="NONE": return
    m=BOS_CHANCE_RE.fullmatch(value)
    if not m: errors.append((n,f"unsupported/malformed BOS chance token {value!r}")); return
    args=m.group(1)
    if re.search(r"\s",args): errors.append((n,f"BOS chance arguments contain whitespace: {value!r}"))
    pieces=args.split(",")
    if len(pieces)>2: errors.append((n,"BOS chance accepts percentage and optional seed only"))
    try:
        chance=float(pieces[0])
        if chance<0 or chance>100: errors.append((n,f"BOS chance outside 0-100: {chance}"))
    except ValueError: errors.append((n,f"BOS chance percentage is not numeric: {pieces[0]!r}"))
    if len(pieces)==2 and not pieces[1].isdigit(): errors.append((n,f"BOS chance seed is not an integer: {pieces[1]!r}"))

def lint_file(path):
    errors=[]; warnings=[]; name=path.name.lower(); active=active_lines(path)
    if name.endswith("_kid.ini"):
        for n,line in active:
            if "=" not in line: errors.append((n,"KID line lacks =")); continue
            key=line.split("=",1)[0].strip()
            fields=[x.strip() for x in rhs(line).split("|")]
            if key=="ExclusiveGroup":
                if len(fields)<2: errors.append((n,"KID ExclusiveGroup requires name and at least one keyword Form Filter")); continue
                if not fields[0]: errors.append((n,"KID ExclusiveGroup name is empty"))
                if not fields[1]: errors.append((n,"KID ExclusiveGroup Form Filters are empty"))
                if len(fields)>2: warnings.append((n,"KID ExclusiveGroup extra pipe fields are ignored by the pinned parser"))
                continue
            if key!="Keyword": errors.append((n,f"unsupported KID key {key!r}")); continue
            if not 2<=len(fields)<=5: errors.append((n,f"KID Keyword allows 2-5 value fields; found {len(fields)}")); continue
            fields=pad(fields,5)
            if not fields[0]: errors.append((n,"KID keyword form/editor ID is empty"))
            if not fields[1]: errors.append((n,"KID ordinary Keyword row requires a human-readable type in field 2; blank type is ignored at runtime"))
            elif fields[1].upper() in KID_SIGNATURES: errors.append((n,f"KID record signature {fields[1]!r} is not a human-readable type and resolves to kNone"))
            elif fields[1] not in KID_TYPES: errors.append((n,f"unsupported/current-unverified KID type label: {fields[1]!r}"))
            if fields[4]:
                try:
                    chance=float(fields[4])
                    if chance<0 or chance>100: errors.append((n,"KID chance outside 0-100"))
                except ValueError: errors.append((n,f"KID chance is not numeric: {fields[4]!r}"))
    elif name.endswith("_distr.ini"):
        for n,line in active:
            if "=" not in line: errors.append((n,"SPID line lacks =")); continue
            key=line.split("=",1)[0].strip(); kind=classify_spid_key(key)
            if not kind:
                hint="; weapons and staves use Item or generic Form" if key=="Weapon" else ""
                errors.append((n,f"unsupported SPID distribution key {key!r}{hint}")); continue
            fields=[x.strip() for x in rhs(line).split("|")]
            if kind["family"]=="exclusive":
                if len(fields)!=2: errors.append((n,f"SPID ExclusiveGroup requires exactly 2 value fields; found {len(fields)}")); continue
                if not fields[0]: errors.append((n,"SPID ExclusiveGroup name is empty"))
                if not fields[1]: errors.append((n,"SPID ExclusiveGroup requires at least one Form Filter"))
                continue
            if kind["family"]=="linked":
                if not 1<=len(fields)<=4: errors.append((n,f"SPID linked distribution allows 1-4 value fields; found {len(fields)}"))
                fields=pad(fields[:4],4)
                if not fields[0]: errors.append((n,"SPID linked distributable form is empty"))
                if not fields[1]: errors.append((n,"SPID linked distribution requires at least one parent Form Filter"))
                lint_spid_count(fields[2],kind['type'],n,errors)
                lint_spid_chance(fields[3],n,errors)
            else:
                if not 1<=len(fields)<=7: errors.append((n,f"SPID allows 1-7 value fields; found {len(fields)}"))
                fields=pad(fields[:7],7)
                if not fields[0]: errors.append((n,"SPID distributable form is empty"))
                lint_spid_level(fields[3],n,errors)
                lint_spid_traits(fields[4],n,errors)
                lint_spid_count(fields[5],kind['type'],n,errors)
                lint_spid_chance(fields[6],n,errors)
            if kind.get('final') and kind.get('type')!='Outfit': warnings.append((n,"SPID Final modifier is ignored for non-Outfit keys"))
    elif name.endswith("_swap.ini"):
        section=None
        for n,line in active:
            if line.startswith("[") and line.endswith("]"):
                section=line[1:-1].split("|",1)[0].strip().casefold()
                if section not in BOS_SECTIONS: errors.append((n,f"unsupported/current-unverified BOS section {line!r}"))
                continue
            if section not in BOS_SECTIONS: errors.append((n,"BOS entry must be beneath [Forms], [References], [Transforms], or [Properties]")); continue
            if "=" in line: errors.append((n,"stale Base = Swap-style BOS dialect"))
            fields=[x.strip() for x in line.split("|")]
            if section in {"forms","references"}:
                if not 2<=len(fields)<=4: errors.append((n,f"BOS {section} entry allows 2-4 pipe fields; found {len(fields)}")); continue
                fields=pad(fields,4); lint_bos_properties(fields[2],n,errors); lint_bos_chance(fields[3],n,errors)
            else:
                if not 2<=len(fields)<=3: errors.append((n,f"BOS {section} entry allows 2-3 pipe fields; found {len(fields)}")); continue
                fields=pad(fields,3); lint_bos_properties(fields[1],n,errors); lint_bos_chance(fields[2],n,errors)
    elif "skypatcher" in {p.casefold() for p in path.parts}:
        lower=[p.casefold() for p in path.parts]; idx=lower.index("skypatcher") if "skypatcher" in lower else -1
        if idx<0 or idx+1>=len(lower): errors.append((0,"SkyPatcher file lacks category directory"))
        elif lower[idx+1] not in SKYPATCHER_CATEGORIES: warnings.append((0,f"category {lower[idx+1]!r} must be verified against installed SkyPatcher"))
        for n,line in active:
            if re.search(r"(^|:)itemsRemove\s*=",line,re.I): errors.append((n,"invented/unverified SkyPatcher itemsRemove key; verify exact installed operation"))
            if ":" not in line and "=" in line: warnings.append((n,"SkyPatcher line has no colon-separated operation chain"))
    return errors,warnings

def self_test():
    import tempfile
    with tempfile.TemporaryDirectory() as td:
        root=Path(td)
        good={
            "KID2_KID.ini":"Keyword = MyKW|Weapon\n",
            "KIDComment_KID.ini":"Keyword = MyKW|Weapon|*Sword||100 ; runtime comment\n",
            "KIDGroup_KID.ini":"ExclusiveGroup = OCFWeapons|OCF_WeaponSword,OCF_WeaponAxe\n",
            "SPID_Item_DISTR.ini":"Item = 0x800~Weapons.esp|Bandit|FactionA,FactionB|25/100,14(10)|F/-U/-C|2|50!\n",
            "SPID_Exclusive_DISTR.ini":"ExclusiveGroup = RMBArmors|0x800~Armor.esp,0x801~Armor.esp ; valid comment\n",
            "SPID_Death_DISTR.ini":"DeathItem = 0x800~Loot.esp|ActorTypeNPC||||1|100 ; valid death key\n",
            "SPID_Linked_DISTR.ini":"GlobalLinkedFinalDeathOutfit = 0x800~Outfits.esp|0x123~NPCs.esp|1|100!\n",
            "SPID_Perk_DISTR.ini":"Perk = 0xD7B~ForHonorBFCO.esp|ActorTypeNPC||65|-C/-D||18!\n",
            "Forms_SWAP.ini":"[Forms]\nBaseA|BaseB|posR(1.0,5.0,50.0/100.0),scale(1.0/1.5)|chanceS(50)\n",
            "Transforms_SWAP.ini":"[Transforms]\nBaseA|rotR(147.9,355.9,82.7)|chanceR(50,123)\n",
            "SKSE/Plugins/SkyPatcher/npc/Test.ini":"filterByNpcs=Skyrim.esm|0x123:objectsToRemove=IronSword\n",
        }
        for rel,text in good.items():
            p=root/rel; p.parent.mkdir(parents=True,exist_ok=True); p.write_text(text)
            e,w=lint_file(p); assert not e,(rel,e,w)
        bad={
            "Staves_DISTR.ini":"Weapon = 0x29B73~MysticismMagic.esp|ActorTypeNPC|||||10\n",
            "ForHonor_DISTR.ini":"Perk = 0xD7B~ForHonorBFCO.esp|ActorTypeNPC||65/|-C/-D||18!\n",
            "Amazon_DISTR.ini":"Faction = 0x800~A.esp|ActorTypeNPC||||F,-C|0|100\n",
            "BadKIDBlank_KID.ini":"Keyword = MyKW||*Sword||100\n",
            "BadKIDSig_KID.ini":"Keyword = MyKW|WEAP|*Sword||100\n",
            "BadBOS_SWAP.ini":"[Transforms]\nBaseA|rotR(147.9, 355.9, 82.7)\n",
            "SKSE/Plugins/SkyPatcher/Test.ini":"filterByNpcs=A:itemsRemove=B\n",
        }
        for rel,text in bad.items():
            p=root/rel; p.parent.mkdir(parents=True,exist_ok=True); p.write_text(text)
            e,w=lint_file(p); assert e,f"expected failure: {rel}"
        e,_=lint_file(root/'ForHonor_DISTR.ini'); joined=' '.join(x[1] for x in e)
        assert 'LevelFilters' in joined and 'trait' not in joined.lower() and 'chance' not in joined.lower()
    print('SELF-TEST: PASS')

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('paths',nargs='*'); ap.add_argument('--self-test',action='store_true'); args=ap.parse_args()
    if args.self_test: self_test(); return
    files=[]
    for raw in args.paths:
        p=Path(raw); files.extend(x for x in p.rglob('*.ini')) if p.is_dir() else files.append(p)
    failed=False
    for p in files:
        e,w=lint_file(p)
        if e or w:
            print(f'FILE: {p}')
            for n,msg in w: print(f'WARN:{n}: {msg}')
            for n,msg in e: print(f'FAIL:{n}: {msg}')
        failed|=bool(e)
    print('RESULT:','FAIL' if failed else 'PASS'); raise SystemExit(1 if failed else 0)
if __name__=='__main__': main()
