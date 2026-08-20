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
    # v7.6.6: only the tailored family remains; 2-OPTIONAL-SHARED-GENERIC was
    # a 97%-identical duplicate the installer never read.
    foreach ($fam in '1-TAILORED-PROVIDER-TREES') {
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
    $man = [IO.File]::ReadAllText($manPath) | ConvertFrom-Json
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

Section '7. Preamble sources are clean UTF-8 and provider-neutral'
$soulF = Join-Path $PackRoot '3-PREAMBLES\SOUL.md'
$aioF  = Join-Path $PackRoot 'AIO-INSTRUCTION.txt'
foreach ($f in @($soulF, $aioF)) {
    if (-not (Test-Path -LiteralPath $f)) { Bad "missing $(Split-Path $f -Leaf)"; continue }
    $txt = [IO.File]::ReadAllText($f)
    $name = Split-Path $f -Leaf
    # Mojibake signature: a UTF-8 sequence that was decoded as Windows-1252.
    if ($txt -match ([char]0x00E2 + [char]0x20AC)) { Bad "$name contains mojibake" }
    else { Good "$name no mojibake" }
    # Get-Content -Raw uses the ANSI codepage on PS 5.1 and silently corrupts
    # non-ASCII. If these two ever disagree, the installer read path is wrong.
    if ((Get-Content -LiteralPath $f -Raw) -cne $txt) { # ansi-intentional
        Good "$name has non-ASCII (installer must use ReadAllText)"
    }
}
# The block is injected into all five providers, so it must not claim to be any
# one of them. v7.6.0 fixed a SOUL.md that told every agent it was Hermes.
$soulTxt = if (Test-Path -LiteralPath $soulF) { [IO.File]::ReadAllText($soulF) } else { '' }
if ($soulTxt -match 'Hermes Agent|Nous Research|You are Claude|created by (Anthropic|OpenAI|xAI|Moonshot)') {
    Bad 'SOUL.md names a specific provider identity; it is installed into all five'
} else { Good 'SOUL.md is provider-neutral' }
if ($soulTxt) {
    $common = [IO.File]::ReadAllText((Join-Path $PackRoot 'TOOLS\V7-Common.ps1'))
    if ($common -match [regex]::Escape('$soul = ([IO.File]::ReadAllText($SoulFile))')) {
        Good 'Install-V5PreambleBlock reads preambles as UTF-8'
    } else { Bad 'Install-V5PreambleBlock no longer uses ReadAllText (mojibake will return)' }
}

Section '7b. No script reads a file with the ANSI codepage'
# PS 5.1's Get-Content decodes with the ANSI codepage unless -Encoding is given,
# so any read of a UTF-8 file that is later written back turns non-ASCII into
# mojibake. Measured: a ConvertFrom-Json/ConvertTo-Json round-trip of a real
# ~/.claude.json destroyed all 26 em dashes. v7.6.1 swept 25 call sites to
# [IO.File]::ReadAllText; this stops them coming back.
# Pattern is concatenated so this test's own source cannot match it.
$rxAnsi = 'Get-' + 'Content[^\r\n]*-Raw'
$scanRoots = @(
    (Join-Path $PackRoot 'TOOLS'),
    (Join-Path $PackRoot 'TESTS'),
    $PackRoot
)
$offenders = @()
foreach ($sr in $scanRoots) {
    $depth = if ($sr -eq $PackRoot) { 0 } else { 99 }
    $files = if ($depth -eq 0) {
        Get-ChildItem -LiteralPath $sr -Filter *.ps1 -File -ErrorAction SilentlyContinue
    } else {
        Get-ChildItem -LiteralPath $sr -Filter *.ps1 -File -Recurse -ErrorAction SilentlyContinue
    }
    foreach ($file in $files) {
        $n = 0
        foreach ($line in [IO.File]::ReadAllLines($file.FullName)) {
            $n++
            if ($line -notmatch $rxAnsi) { continue }
            if ($line -match '-Encoding') { continue }        # explicit, fine
            if ($line -match 'ansi-intentional') { continue }  # opted out on purpose
            if ($line -match '^\s*#') { continue }             # a comment about it
            $offenders += ('{0}:{1}' -f $file.Name, $n)
        }
    }
}
if ($offenders.Count) {
    Bad ("ANSI-decoding reads found (use [IO.File]::ReadAllText): " + ($offenders -join ', '))
} else {
    Good 'no script decodes a file with the ANSI codepage'
}

# Same trap, but in documentation we ship as copy-paste instructions. Prose that
# *discusses* the bug is fine, and every changelog does; a ```powershell fence is
# not prose, it is code the reader will run. 3-PREAMBLES/README.md shipped a
# manual-install snippet doing exactly this until v7.6.3. docs/history is skipped
# on purpose: those records quote the broken form as a before/after.
$docOffenders = @()
$docFiles = @()
$docFiles += Get-ChildItem -LiteralPath $PackRoot -Filter *.md -File -ErrorAction SilentlyContinue
foreach ($sub in @('3-PREAMBLES', 'PROMPTS', 'TOOLS', 'TESTS', 'docs')) {
    $d = Join-Path $PackRoot $sub
    if (Test-Path -LiteralPath $d) {
        $docFiles += Get-ChildItem -LiteralPath $d -Filter *.md -File -ErrorAction SilentlyContinue
    }
}
foreach ($file in $docFiles) {
    $inPs = $false
    $n = 0
    foreach ($line in [IO.File]::ReadAllLines($file.FullName)) {
        $n++
        if ($line -match '^\s*```') {
            if ($inPs) { $inPs = $false }
            elseif ($line -match '^\s*```\s*(powershell|ps1|pwsh)') { $inPs = $true }
            continue
        }
        if (-not $inPs) { continue }
        if ($line -notmatch $rxAnsi) { continue }
        if ($line -match '-Encoding') { continue }
        if ($line -match 'ansi-intentional') { continue }
        if ($line -match '^\s*#') { continue }
        $docOffenders += ('{0}:{1}' -f $file.Name, $n)
    }
}
if ($docOffenders.Count) {
    Bad ("docs teach an ANSI-decoding read in a powershell fence: " + ($docOffenders -join ', '))
} else {
    Good 'no shipped powershell snippet teaches the ANSI trap'
}

# One soul source, not two. v7.6.0 genericised SOUL.md; SOUL-UNIVERSAL.md then
# existed only as a byte-identical duplicate whose README still described it as
# the de-Hermesed copy -- an invitation to put the provider identity back.
$soulSrc = Join-Path (Join-Path $PackRoot '3-PREAMBLES') 'SOUL.md'
$soulDup = Join-Path (Join-Path $PackRoot '3-PREAMBLES') 'SOUL-UNIVERSAL.md'
if (Test-Path -LiteralPath $soulDup) {
    Bad 'SOUL-UNIVERSAL.md is back; there must be exactly one soul source'
} else {
    Good 'exactly one soul source (SOUL.md)'
}
$instTxt = [IO.File]::ReadAllText((Join-Path $PackRoot 'INSTALL-V7-AIO.ps1'))
if ($instTxt -match "Join-Path \`$preDir 'SOUL-UNIVERSAL\.md'") {
    Bad 'installer wires SOUL-UNIVERSAL.md instead of the single SOUL.md'
} else {
    Good 'installer wires the single SOUL.md to every provider'
}

Section '8. Repair-McpPaths resolves a version-stamped path'
$repair = Join-Path $PackRoot (Join-Path 'TOOLS' 'Repair-McpPaths.ps1')
if (-not (Test-Path -LiteralPath $repair)) { Bad 'TOOLS\Repair-McpPaths.ps1 missing' }
else {
    # Sandbox: a dead Widget-1.0.0 and a live Widget-1.2.0, so the resolver has
    # to pick the highest version whose target file actually exists.
    $sandbox = Join-Path $env:TEMP ('v7mcprepair-' + [guid]::NewGuid().ToString('N').Substring(0,8))
    try {
        $liveDir = Join-Path (Join-Path $sandbox 'Widget-1.2.0') 'bin'
        New-Item -ItemType Directory -Force -Path $liveDir | Out-Null
        # Canonicalise both. On the GitHub runner $env:TEMP is the 8.3 short
        # form (C:\Users\RUNNER~1\...) while Get-ChildItem's .FullName -- what
        # the resolver returns -- gives the long form (runneradmin). Same file,
        # two spellings, and a plain string compare fails on the difference.
        $sandbox = (Get-Item -LiteralPath $sandbox).FullName
        $liveDir = (Get-Item -LiteralPath $liveDir).FullName
        # A higher version that is missing the target file must be ignored.
        New-Item -ItemType Directory -Force -Path (Join-Path $sandbox 'Widget-1.3.0') | Out-Null
        $liveExe = Join-Path $liveDir 'tool.exe'
        Set-Content -LiteralPath $liveExe -Value 'x'
        # Dot-source only the two resolver functions, not the whole report.
        $src = [IO.File]::ReadAllText($repair)
        $fn1 = [regex]::Match($src, '(?ms)^function Get-NormalPath.*?^\}').Value
        $fn2 = [regex]::Match($src, '(?ms)^function Resolve-LivePath.*?^\}').Value
        if (-not $fn1 -or -not $fn2) { Bad 'could not extract resolver functions' }
        else {
            . ([scriptblock]::Create($fn1 + "`n" + $fn2))
            $dead = Join-Path (Join-Path (Join-Path $sandbox 'Widget-1.0.0') 'bin') 'tool.exe'
            $got = Resolve-LivePath $dead
            if ($got -eq $liveExe) { Good 'resolver picks highest version that really exists' }
            else { Bad "resolver returned '$got', expected '$liveExe'" }
            # No version-stamped folder in the path: it must refuse to guess.
            $got2 = Resolve-LivePath (Join-Path (Join-Path $sandbox 'nothing') 'here.exe')
            if ($null -eq $got2) { Good 'resolver refuses to guess unversioned paths' }
            else { Bad "resolver invented a replacement: $got2" }

            # Escaping. A JSON config stores every separator doubled; writing a
            # lone backslash back produces an invalid escape and an unparseable
            # config. Two earlier attempts got this wrong in opposite directions
            # (one under-escaped, one produced four), so it is asserted here.
            $fnEsc = [regex]::Match($src, '(?ms)^function ConvertTo-ConfigLiteral.*?^\}').Value
            if (-not $fnEsc) { Bad 'ConvertTo-ConfigLiteral not found in Repair-McpPaths.ps1' }
            else {
                . ([scriptblock]::Create($fnEsc))
                $liveP = 'S:' + [char]92 + 'Tools' + [char]92 + 'App-1.2.0' + [char]92 + 'py.exe'
                $bs = [string][char]92
                $deadJson = 'S:' + $bs + $bs + 'Tools' + $bs + $bs + 'App-1.1.0' + $bs + $bs + 'py.exe'
                $deadToml = 'S:' + $bs + 'Tools' + $bs + 'App-1.1.0' + $bs + 'py.exe'
                $wantJson = 'S:' + $bs + $bs + 'Tools' + $bs + $bs + 'App-1.2.0' + $bs + $bs + 'py.exe'
                $gotJson = ConvertTo-ConfigLiteral -LivePath $liveP -DeadLiteral $deadJson
                if ($gotJson -ceq $wantJson) { Good 'JSON config keeps its doubled separators' }
                else { Bad "escaping wrong: got [$gotJson] want [$wantJson]" }
                $gotToml = ConvertTo-ConfigLiteral -LivePath $liveP -DeadLiteral $deadToml
                if ($gotToml -ceq $liveP) { Good 'TOML/YAML config keeps single separators' }
                else { Bad "escaping wrong: got [$gotToml] want [$liveP]" }
                # End to end: the rewritten JSON must still parse.
                $doc = '{"c":"' + $deadJson + '"}'
                try {
                    $round = ($doc.Replace($deadJson, $gotJson) | ConvertFrom-Json)
                    if ($round.c -ceq $liveP) { Good 'repointed JSON still parses to the live path' }
                    else { Bad "round trip produced $($round.c)" }
                } catch { Bad "repointed JSON no longer parses: $_" }
            }
        }
    } finally {
        Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Section '9. Provider starter settings are portable (no live-machine dump)'
$starterFiles = @(
    '1-TAILORED-PROVIDER-TREES\Claude\COPY-TO-PROVIDER-HOME\settings.json',
    '1-TAILORED-PROVIDER-TREES\Codex\COPY-TO-PROVIDER-HOME\config.toml',
    '1-TAILORED-PROVIDER-TREES\Grok\COPY-TO-PROVIDER-HOME\config.toml',
    '1-TAILORED-PROVIDER-TREES\Kimi\COPY-TO-PROVIDER-HOME\config.toml',
    '1-TAILORED-PROVIDER-TREES\Hermes\COPY-TO-PROVIDER-HOME\config.yaml',
    'TOOLS\Install-Provider-Starter-Settings.ps1'
)
foreach ($rel in $starterFiles) {
    $p = Join-Path $PackRoot $rel
    if (-not (Test-Path -LiteralPath $p)) { Bad "missing $rel"; continue }
    $raw = [IO.File]::ReadAllText($p)
    if ($raw -match '(?i)C:\\Users\\[^\\\s"]+' -or $raw -match '(?i)S:\\Apps\\') {
        Bad "$rel contains a machine path"
    } else { Good $rel }
}
$aio = [IO.File]::ReadAllText((Join-Path $PackRoot 'INSTALL-V7-AIO.ps1'))
if ($aio -match 'Install-Provider-Starter-Settings') { Good 'AIO calls starter-settings installer' }
else { Bad 'INSTALL-V7-AIO.ps1 does not call Install-Provider-Starter-Settings.ps1' }
if ($aio -match 'Copy-Item -LiteralPath \$hCfgSrc -Destination \$hCfg') {
    Bad 'AIO still wholesale-copies Hermes config.yaml over a live home'
} else { Good 'AIO no longer overwrites a live Hermes config.yaml' }
$starterSrc = [IO.File]::ReadAllText((Join-Path $PackRoot 'TOOLS\Install-Provider-Starter-Settings.ps1'))
if ($starterSrc -match '(?mi)\$home\s*=') {
    Bad 'Install-Provider-Starter-Settings.ps1 assigns $HOME (PowerShell constant; aborts the starter pass)'
} else { Good 'starter settings do not assign $HOME' }
$common = [IO.File]::ReadAllText((Join-Path $PackRoot 'TOOLS\V7-Common.ps1'))
if ($common -match "skills = false") {
    Good 'Set-V5GrokCompatCells writes skills = false'
} else { Bad 'V7-Common.ps1 does not write [compat.claude] skills = false' }
if ($aio -match 'Repair-V5GrokDuplicatePlugins') {
    Good 'AIO collapses duplicate Grok superpowers plugins'
} else { Bad 'INSTALL-V7-AIO.ps1 does not call Repair-V5GrokDuplicatePlugins' }
if ($aio -match "Invoke-V5SkillDedupe -Provider 'Grok'") {
    Bad 'AIO still dedupes Grok superpowers copies (TUI then fails with no reason)'
} else { Good 'AIO leaves Grok superpowers copies in ~/.grok/skills' }
if ($aio -match "Invoke-V5SkillDedupe -Provider 'Hermes'") {
    Bad 'AIO still dedupes Hermes superpowers/ponytail copies (slash commands and autofill then disappear)'
} else { Good 'AIO leaves Hermes plugin copies in the skills dir (slash commands load that path)' }
$grokStarter = [IO.File]::ReadAllText((Join-Path $PackRoot '1-TAILORED-PROVIDER-TREES\Grok\COPY-TO-PROVIDER-HOME\config.toml'))
if ($grokStarter -match '(?m)^\s*skills\s*=\s*false\s*$') {
    Good 'Grok starter config.toml sets compat.claude skills = false'
} else { Bad 'Grok starter config.toml missing skills = false' }

Write-Host ''
if ($fail -eq 0) {
    Write-Host "PACK GATE: PASS" -ForegroundColor Green
    exit 0
} else {
    Write-Host "PACK GATE: FAIL ($fail problem(s))" -ForegroundColor Red
    exit 1
}
