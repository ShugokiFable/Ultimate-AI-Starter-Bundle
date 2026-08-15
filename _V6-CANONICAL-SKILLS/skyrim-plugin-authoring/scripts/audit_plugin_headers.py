#!/usr/bin/env python3
"""Read-only Skyrim SE/AE plugin structure and extended FormID audit."""
from __future__ import annotations
import argparse, struct, zipfile, sys
from pathlib import Path

SUPPORTED_HEDR=(1.70,1.71)
DEFAULT_FORM_VERSION=44
ESL_FLAG=0x200
LEGACY_LIGHT_MIN=0x800
EXTENDED_LIGHT_MIN=0x001
LIGHT_MAX=0xFFF
GAME_MASTER='skyrim.esm'
class AuditError(Exception): pass

def close(a,b): return abs(a-b)<=0.001

def subrecords(buf,start,end):
    pos=start; extended=None
    while pos+6<=end:
        tag=buf[pos:pos+4]; size=struct.unpack_from('<H',buf,pos+4)[0]; pos+=6
        if tag==b'XXXX':
            if size!=4 or pos+4>end: raise AuditError('invalid XXXX subrecord')
            extended=struct.unpack_from('<I',buf,pos)[0]; pos+=4; continue
        actual=extended if extended is not None else size; extended=None
        if pos+actual>end: raise AuditError(f'subrecord {tag!r} overruns record')
        yield tag,buf[pos:pos+actual]; pos+=actual
    if pos!=end: raise AuditError(f'trailing bytes in subrecord area {pos:#x}!={end:#x}')

def parse_tes4(buf):
    if len(buf)<24 or buf[:4]!=b'TES4': raise AuditError('not a TES4 plugin')
    size,flags=struct.unpack_from('<II',buf,4); fv=struct.unpack_from('<H',buf,20)[0]; end=24+size
    if end>len(buf): raise AuditError('TES4 data size exceeds file')
    hedr=None; masters=[]; onam=[]
    for tag,data in subrecords(buf,24,end):
        if tag==b'HEDR' and len(data)>=12: hedr=struct.unpack_from('<fII',data,0)
        elif tag==b'MAST': masters.append(data.split(b'\0',1)[0].decode('cp1252','replace'))
        elif tag==b'ONAM': onam.append(data)
    return flags,fv,hedr,masters,onam,end

def walk(buf,start,end,master_count,is_light,required_fv):
    records=groups=0; new_locals=[]; override_locals=[]; bad_fv=[]; unusual=[]; bad_idx=[]
    stack=[(start,end)]
    while stack:
        pos,region_end=stack.pop()
        while pos<region_end:
            if pos+24>region_end: raise AuditError(f'truncated header at {pos:#x}')
            tag=buf[pos:pos+4]; size=struct.unpack_from('<I',buf,pos+4)[0]
            if tag==b'GRUP':
                if size<24 or pos+size>region_end: raise AuditError(f'invalid GRUP size at {pos:#x}')
                groups+=1; stack.append((pos+24,pos+size)); pos+=size; continue
            total=24+size
            if pos+total>region_end: raise AuditError(f'record {tag!r} overruns group at {pos:#x}')
            formid=struct.unpack_from('<I',buf,pos+12)[0]; fv=struct.unpack_from('<H',buf,pos+20)[0]
            records+=1; sig=tag.decode('latin1','replace')
            if required_fv is not None and fv!=required_fv: bad_fv.append((sig,formid,fv))
            elif required_fv is None and fv!=DEFAULT_FORM_VERSION: unusual.append((sig,formid,fv))
            if formid:
                idx=(formid>>24)&0xFF; local=formid&0xFFFFFF
                if idx>master_count: bad_idx.append((sig,formid,idx))
                elif idx==master_count: new_locals.append((sig,formid,local))
                else: override_locals.append((sig,formid,idx,local))
            pos+=total
    return records,groups,new_locals,override_locals,bad_fv,unusual,bad_idx

def discover_masters(names,roots):
    result={}
    for name in names:
        for root in roots:
            candidates=[root/name]
            if root.is_dir(): candidates += list(root.rglob(name))
            found=next((p for p in candidates if p.is_file()),None)
            if found:
                try:
                    flags,fv,hedr,masters,onam,start=parse_tes4(found.read_bytes())
                    result[name.casefold()]={'path':found,'hedr':hedr[0] if hedr else None,'masters':masters}
                except Exception as exc:
                    result[name.casefold()]={'path':found,'error':str(exc),'hedr':None,'masters':[]}
                break
    return result

def audit_bytes(buf,label,expect,target_header,esl_range,required_fv,master_roots):
    errors=[]; warnings=[]
    try:
        flags,tes4_fv,hedr,masters,onam,start=parse_tes4(buf); header=hedr[0] if hedr else None; light=bool(flags&ESL_FLAG)
        if expect=='light' and not light: errors.append('expected ESL flag 0x200')
        if expect=='full' and light: errors.append('expected full plugin but ESL flag is set')
        if required_fv is not None and tes4_fv!=required_fv: errors.append(f'TES4 formVersion {tes4_fv}, expected {required_fv}')
        elif required_fv is None and tes4_fv!=DEFAULT_FORM_VERSION: warnings.append(f'TES4 formVersion {tes4_fv}; inspect historical structure before normalization')
        if hedr is None: errors.append('missing HEDR')
        elif target_header!='auto' and not close(header,float(target_header)): errors.append(f'HEDR {header:.6f}, expected {target_header}')
        elif target_header=='auto' and not any(close(header,v) for v in SUPPORTED_HEDR): errors.append(f'unrecognized Skyrim SE/AE HEDR {header:.6f}')
        recs=groups=0; new=[]; overrides=[]; bad_fv=[]; unusual=[]; bad_idx=[]
        if start<len(buf): recs,groups,new,overrides,bad_fv,unusual,bad_idx=walk(buf,start,len(buf),len(masters),light,required_fv)
        if hedr and hedr[1]!=recs+groups: errors.append(f'HEDR numRecords {hedr[1]} != records+groups {recs+groups}')
        if bad_fv: errors.append(f'{len(bad_fv)} record(s) violate required formVersion {required_fv}')
        if unusual: warnings.append(f'{len(unusual)} record(s) do not use formVersion {DEFAULT_FORM_VERSION}')
        if bad_idx: errors.append(f'{len(bad_idx)} record(s) use an impossible master index')
        new_ids=[local for _,_,local in new]
        extended_used=bool(light and any(EXTENDED_LIGHT_MIN<=x<LEGACY_LIGHT_MIN for x in new_ids))
        if light:
            min_id=LEGACY_LIGHT_MIN if esl_range=='legacy' else EXTENDED_LIGHT_MIN if esl_range=='extended' else (EXTENDED_LIGHT_MIN if header is not None and close(header,1.71) else LEGACY_LIGHT_MIN)
            bad=[x for x in new if not min_id<=x[2]<=LIGHT_MAX]
            if bad: errors.append(f'{len(bad)} new light record(s) outside {min_id:#05x}-{LIGHT_MAX:#05x}')
        if esl_range=='extended' and light: extended_used=True
        if extended_used:
            if header is None or not close(header,1.71): errors.append('extended local FormID range requires HEDR 1.71')
            if not masters or masters[0].casefold()!=GAME_MASTER: errors.append('extended FormID range requires Skyrim.esm as first master')
        master_info=discover_masters(masters,[Path(x) for x in master_roots]) if master_roots else {}
        if master_roots:
            for i,name in enumerate(masters):
                info=master_info.get(name.casefold())
                if not info: warnings.append(f'master not found for header-chain audit: {name}'); continue
                if info.get('error'): errors.append(f'cannot parse master {name}: {info["error"]}'); continue
                mh=info.get('hedr')
                if mh is not None and close(mh,1.71) and (header is None or not close(header,1.71)):
                    errors.append(f'master {name} uses HEDR 1.71 but dependent module does not')
                required=[x.casefold() for x in info.get('masters',[])]
                prior=[x.casefold() for x in masters[:i]]
                missing=[x for x in required if x not in prior]
                if missing: errors.append(f'master {name} requires earlier master(s) missing/out of order: {missing}')
        print(f'FILE: {label}')
        print(f'FLAGS: {flags:#x} LIGHT={light}')
        print(f'HEDR: {hedr} TES4_FORM_VERSION={tes4_fv}')
        print(f'MASTERS: {masters}')
        print(f'NEW_LOCAL_IDS: {len(new_ids)} EXTENDED_USED={extended_used}')
        print(f'SCANNED: records={recs} groups={groups}')
        for w in warnings: print('WARN:',w)
        for e in errors: print('FAIL:',e)
        print('RESULT:', 'FAIL' if errors else 'PASS')
        return not errors
    except Exception as exc:
        print(f'FILE: {label}\nFAIL: {type(exc).__name__}: {exc}\nRESULT: FAIL'); return False

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('paths',nargs='+')
    g=ap.add_mutually_exclusive_group(); g.add_argument('--expect-light',action='store_true'); g.add_argument('--expect-full',action='store_true')
    ap.add_argument('--target-header',choices=('auto','1.70','1.71'),default='auto')
    ap.add_argument('--esl-range',choices=('auto','legacy','extended'),default='auto')
    ap.add_argument('--require-form-version',type=int)
    ap.add_argument('--master-root',action='append',default=[],help='directory containing masters; repeatable')
    args=ap.parse_args(); expect='light' if args.expect_light else 'full' if args.expect_full else 'auto'; ok=True
    for raw in args.paths:
        p=Path(raw)
        try:
            if p.suffix.lower()=='.zip':
                with zipfile.ZipFile(p) as z:
                    members=[n for n in z.namelist() if n.lower().endswith(('.esp','.esm','.esl')) and not n.endswith('/')]
                    if not members: print(f'FILE: {p}\nFAIL: no plugin in archive\nRESULT: FAIL'); ok=False
                    for member in members: ok=audit_bytes(z.read(member),f'{p}!{member}',expect,args.target_header,args.esl_range,args.require_form_version,args.master_root) and ok
            else: ok=audit_bytes(p.read_bytes(),str(p),expect,args.target_header,args.esl_range,args.require_form_version,args.master_root) and ok
        except Exception as exc: print(f'FILE: {p}\nFAIL: {type(exc).__name__}: {exc}\nRESULT: FAIL'); ok=False
    raise SystemExit(0 if ok else 1)
if __name__=='__main__': main()
