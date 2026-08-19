#!/usr/bin/env python3
"""Schema and exact-form linter for source-locked CDF JSON."""
from __future__ import annotations
import argparse, json
from pathlib import Path

def load_forms(path):
    if not path: return None
    p=Path(path)
    if p.suffix.lower()==".json":
        data=json.loads(p.read_text(encoding="utf-8"))
        if isinstance(data,dict): data=data.get("forms",[])
        return {str(x).casefold() for x in data}
    return {x.strip().casefold() for x in p.read_text(encoding="utf-8").splitlines() if x.strip()}

def lint(path, known=None):
    errors=[]; warnings=[]
    try:
        root=json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception as e:
        return [f"invalid JSON: {e}"],warnings
    if not isinstance(root,dict):
        return ["root must be an object"],warnings
    rules=root.get("rules")
    if not isinstance(rules,list):
        return ["root.rules must be an array"],warnings
    for ri,rule in enumerate(rules):
        loc=f"rules[{ri}]"
        if not isinstance(rule,dict):
            errors.append(f"{loc} must be an object"); continue
        if not isinstance(rule.get("friendlyName"),str):
            errors.append(f"{loc}.friendlyName must be a string")
        conditions=rule.get("conditions")
        if conditions is not None:
            if not isinstance(conditions,dict):
                errors.append(f"{loc}.conditions must be an object")
            else:
                plugins=conditions.get("plugins")
                if plugins is not None and (not isinstance(plugins,list) or not all(isinstance(x,str) for x in plugins)):
                    errors.append(f"{loc}.conditions.plugins must be an array of strings")
        changes=rule.get("changes")
        if not isinstance(changes,list):
            errors.append(f"{loc}.changes must be an array"); continue
        for ci,change in enumerate(changes):
            cloc=f"{loc}.changes[{ci}]"
            if not isinstance(change,dict):
                errors.append(f"{cloc} must be an object"); continue
            if not any(k in change for k in ("add","remove","removeByKeywords","count")):
                warnings.append(f"{cloc} contains no recognized change")
            count=change.get("count")
            if count is not None and (not isinstance(count,int) or isinstance(count,bool) or count<0):
                errors.append(f"{cloc}.count must be an unsigned integer")
            add=change.get("add")
            if add is not None:
                if not isinstance(add,list) or not all(isinstance(x,str) for x in add):
                    errors.append(f"{cloc}.add must be an array of strings")
                else:
                    for ai,form in enumerate(add):
                        if form.startswith("*"):
                            errors.append(f"{cloc}.add[{ai}] uses unsupported wildcard-like form {form!r}")
                        if known is not None and form.casefold() not in known:
                            errors.append(f"{cloc}.add[{ai}] does not resolve in supplied manifest: {form!r}")
            remove=change.get("remove")
            if remove is not None:
                if not isinstance(remove,str):
                    errors.append(f"{cloc}.remove must be one string")
                elif known is not None and remove.casefold() not in known:
                    errors.append(f"{cloc}.remove does not resolve in supplied manifest: {remove!r}")
            keywords=change.get("removeByKeywords")
            if keywords is not None:
                if not isinstance(keywords,list) or not all(isinstance(x,str) for x in keywords):
                    errors.append(f"{cloc}.removeByKeywords must be an array of strings")
                elif known is not None:
                    for kw in keywords:
                        if kw.casefold() not in known:
                            errors.append(f"{cloc}.removeByKeywords does not resolve: {kw!r}")
    return errors,warnings

def self_test():
    import tempfile
    with tempfile.TemporaryDirectory() as td:
        root=Path(td)
        good=root/"good.json"
        good.write_text(json.dumps({"rules":[{"friendlyName":"Merchant","conditions":{"plugins":["Weapons.esp"]},"changes":[{"add":["SwordA","0x800~Weapons.esp"],"count":1}]}]}))
        assert not lint(good)[0]
        bad=root/"bad.json"
        bad.write_text(json.dumps({"rules":[{"friendlyName":"Merchant","changes":[{"add":["*Claw"],"count":-1}]}]}))
        e,_=lint(bad)
        assert any("wildcard" in x for x in e)
        assert any("unsigned" in x for x in e)
    print("SELF-TEST: PASS")

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("paths",nargs="*")
    ap.add_argument("--forms")
    ap.add_argument("--self-test",action="store_true")
    a=ap.parse_args()
    if a.self_test: self_test(); return
    known=load_forms(a.forms)
    files=[]
    for raw in a.paths:
        p=Path(raw)
        files.extend(p.rglob("*.json") if p.is_dir() else [p])
    failed=False
    for p in files:
        e,w=lint(p,known)
        for x in w: print(f"WARN:{p}: {x}")
        for x in e: print(f"FAIL:{p}: {x}")
        failed |= bool(e)
    print("RESULT:","FAIL" if failed else "PASS")
    raise SystemExit(1 if failed else 0)
if __name__=="__main__": main()
