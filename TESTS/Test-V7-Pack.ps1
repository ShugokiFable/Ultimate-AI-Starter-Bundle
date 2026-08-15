<#
.SYNOPSIS
  Full v6 pack gate: skill health, PowerShell parseability, offline asset
  integrity, and registry sanity. Exits non-zero on any failure.

.DESCRIPTION
  This is the control that v5 lacked. v5.2.5's registry already WARNED that a
  BOM breaks valid-looking files, and v5.2.5 still shipped seven BOM'd skills
  whose descriptions never loaded. A warning in a document is not a control;
  this script is.

.EXAMPLE
  .\TESTS\Test-V7-Pack.ps1
#>
[CmdletBinding()]
param(
    [string]$PackRoot,
    [switch]$IncludeLiveInstalls
)

# $PSScriptRoot is empty when the script is invoked by a relative -File path
# from some shells, so resolve defensively rather than assuming.
if (-not $PackRoot) {
    $here = $PSScriptRoot
    if (-not $here -and $PSCommandPath) { $here = Split-Path -Parent $PSCommandPath }
    if (-not $here) { $here = (Get-Location).Path }
    $PackRoot = Split-Path -Parent $here
}
if (-not (Test-Path (Join-Path $PackRoot '_V7-CANONICAL-SKILLS'))) {
    throw "PackRoot '$PackRoot' does not look like the v6 pack (no _V7-CANONICAL-SKILLS). Pass -PackRoot explicitly."
}

$ErrorActionPreference = 'Stop'
$fail = 0
$py = (Get-Command python -ErrorAction SilentlyContinue)

function Section($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Bad($m) { Write-Host "  FAIL $m" -ForegroundColor Red; $script:fail++ }
function Good($m) { Write-Host "  ok   $m" -ForegroundColor Green }

Section '1. Skill health (all trees)'
if (-not $py) {
    Bad 'python not found; skill audit skipped'
} else {
    $trees = @(Join-Path $PackRoot '_V7-CANONICAL-SKILLS')
    foreach ($fam in '1-RECOMMENDED-SEPARATE-TAILORED', '2-OPTIONAL-SHARED-GENERIC') {
        foreach ($prov in 'Claude', 'Codex', 'Grok', 'Hermes', 'Kimi') {
            $p = Join-Path $PackRoot "$fam\$prov\COPY-TO-SKILLS-DIRECTORY\skills"
            if (Test-Path $p) { $trees += $p }
        }
    }
    if ($IncludeLiveInstalls) {
        foreach ($h in '.claude', '.grok', '.codex', '.kimi-code') {
            $p = Join-Path $env:USERPROFILE "$h\skills"
            if (Test-Path $p) { $trees += $p }
        }
    }
    foreach ($t in $trees) {
        $out = & $py.Source (Join-Path $PackRoot 'TOOLS\audit_skills.py') $t 2>&1
        $res = ($out | Select-String 'RESULT:').ToString().Trim()
        $short = $t.Replace($PackRoot, '').TrimStart('\')
        if ($res -match 'PASS') { Good "$short  $res" } else { Bad "$short  $res" }
    }
}

Section '2. PowerShell parses (excluding BUNDLED-TOOLS)'
$n = 0; $bad = 0
Get-ChildItem -Path $PackRoot -Recurse -Include *.ps1, *.psm1 -File |
    Where-Object { $_.FullName -notlike '*BUNDLED-TOOLS*' } |
    ForEach-Object {
        $n++
        $err = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$err)
        if ($err.Count) { $bad++; Bad "$($_.Name) : $($err[0].Message)" }
    }
if ($bad -eq 0) { Good "$n scripts parsed" }

Section '3. BOM-less scripts containing non-ASCII (PS 5.1 will mis-decode)'
$risk = 0
Get-ChildItem -Path $PackRoot -Recurse -Include *.ps1, *.psm1, *.bat, *.cmd -File |
    Where-Object { $_.FullName -notlike '*BUNDLED-TOOLS*' } |
    ForEach-Object {
        $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
        $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
        $nonAscii = @($bytes | Where-Object { $_ -gt 127 }).Count
        if (-not $hasBom -and $nonAscii -gt 0) {
            $risk++
            Bad "$($_.Name): no BOM, $nonAscii non-ASCII bytes"
        }
    }
if ($risk -eq 0) { Good 'no at-risk scripts' }

Section '4. Offline assets match OFFLINE-MANIFEST.json'
$manPath = Join-Path $PackRoot 'BUNDLED-TOOLS\OFFLINE-MANIFEST.json'
if (-not (Test-Path $manPath)) {
    Bad 'OFFLINE-MANIFEST.json missing'
} else {
    $man = Get-Content $manPath -Raw | ConvertFrom-Json
    foreach ($a in $man.assets) {
        $p = Join-Path $PackRoot "BUNDLED-TOOLS\offline\$($a.file)"
        if (-not (Test-Path $p)) { Bad "missing asset $($a.file)"; continue }
        $h = (Get-FileHash $p -Algorithm SHA256).Hash.ToLower()
        if ($h -ne $a.sha256) { Bad "$($a.file) sha256 mismatch" }
        else { Good "$($a.file)" }
    }
}

Section '5. Evidence registry sanity'
if ($py) {
    $reg = Join-Path $PackRoot '_V7-CANONICAL-SKILLS\skyrim-memory\references\ERROR-REGISTRY.json'
    if (Test-Path $reg) {
        # `sources` is required of NEW evidence at merge time (merge_registry.py
        # enforces it). It is deliberately NOT required here: 29 v4.3-era rows
        # were derived from documentation rather than a session citation, and
        # they are otherwise complete. Structural check only.
        $code = @'
import json,sys,io
d=json.load(io.open(sys.argv[1],encoding='utf-8-sig'))
e=d['entries']
req=('id','title','symptom','root_cause','prevention','evidence_status')
bad=[x.get('id','?') for x in e if not all(x.get(f) for f in req)]
ids=[x['id'] for x in e]
dup=[i for i in set(ids) if ids.count(i)>1]
nosrc=sum(1 for x in e if not x.get('sources'))
print('entries=%d dup=%s incomplete=%s | %d legacy rows without sources (allowed)'
      %(len(e),dup or 'none',bad or 'none',nosrc))
sys.exit(1 if (dup or bad) else 0)
'@
        $tmp = Join-Path $env:TEMP 'v6regcheck.py'
        Set-Content -Path $tmp -Value $code -Encoding utf8
        $out = & $py.Source $tmp $reg 2>&1
        if ($LASTEXITCODE -eq 0) { Good $out } else { Bad $out }
    } else { Bad 'ERROR-REGISTRY.json not found' }
}

Section '6. Gate self-tests'
$gateDir = Join-Path $PackRoot 'TOOLS\hooks'
foreach ($g in @('completeness_gate.py', 'assumption_gate.py')) {
    $gp = Join-Path $gateDir $g
    if (-not (Test-Path -LiteralPath $gp)) { Bad "$g missing"; continue }
    if (-not $py) { Bad "python not found; $g --selftest skipped"; continue }
    $out = & $py.Source $gp --selftest 2>&1 | Out-String
    if ($out -match 'PASS') { Good "$g  self-test PASS" } else { Bad "$g self-test failed: $out" }
}
$wire = Join-Path $gateDir 'hermes_wire.py'
if (Test-Path -LiteralPath $wire) { Good 'hermes_wire.py present' } else { Bad 'hermes_wire.py missing' }

Write-Host ''
if ($fail -eq 0) {
    Write-Host "PACK GATE: PASS" -ForegroundColor Green
    exit 0
} else {
    Write-Host "PACK GATE: FAIL ($fail problem(s))" -ForegroundColor Red
    exit 1
}
