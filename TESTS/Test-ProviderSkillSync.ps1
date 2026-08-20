<#
.SYNOPSIS
  Windows PowerShell 5.1 regression for bundle-owned provider skill sync.

.DESCRIPTION
  Reproduces the v7.9.1 failure where a previous release's SKILL.md had the
  same name, byte length, timestamp and attributes as the new file but
  different contents. Plain robocopy treated it as "Same" and skipped it.

  This test must run on Windows because it exercises the production PowerShell
  sync and Windows filesystem swap semantics against the original failure shape.
#>
[CmdletBinding()]
param([string]$PackRoot)

$ErrorActionPreference = 'Stop'
if (-not $PackRoot) {
    $here = $PSScriptRoot
    if (-not $here -and $PSCommandPath) { $here = Split-Path -Parent $PSCommandPath }
    $PackRoot = Split-Path -Parent $here
}

. (Join-Path $PackRoot 'TOOLS\V7-Common.ps1')

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('uabs-provider-sync-' + [Guid]::NewGuid().ToString('N'))
$srcRoot = Join-Path $tempRoot 'source skills'
$dstRoot = Join-Path $tempRoot 'installed skills'
$srcSkill = Join-Path $srcRoot 'release-checklist'
$dstSkill = Join-Path $dstRoot 'release-checklist'
$customSkill = Join-Path $dstRoot 'my-custom-skill'

try {
    New-Item -ItemType Directory -Force -Path $srcSkill, $dstSkill, $customSkill | Out-Null

    # Exactly the old failure shape: same byte count and same last-write time,
    # but different bytes. Deterministic release ZIPs normalize timestamps.
    $old = 'release_marker: old-aa'
    $new = 'release_marker: new-bb'
    if ([Text.Encoding]::UTF8.GetByteCount($old) -ne [Text.Encoding]::UTF8.GetByteCount($new)) {
        throw 'test fixture bug: old/new content lengths differ'
    }

    $utf8 = New-Object Text.UTF8Encoding($false)
    $srcFile = Join-Path $srcSkill 'SKILL.md'
    $dstFile = Join-Path $dstSkill 'SKILL.md'
    [IO.File]::WriteAllText($srcFile, $new, $utf8)
    [IO.File]::WriteAllText($dstFile, $old, $utf8)

    $sameTime = [DateTime]::SpecifyKind([DateTime]'2026-08-20T00:00:00', [DateTimeKind]::Local)
    (Get-Item -LiteralPath $srcFile).LastWriteTime = $sameTime
    (Get-Item -LiteralPath $dstFile).LastWriteTime = $sameTime

    # A stale extra file inside a bundle-owned skill must be removed.
    [IO.File]::WriteAllText((Join-Path $dstSkill 'STALE.txt'), 'stale', $utf8)
    # A user-created sibling skill must never be mirrored away.
    $customFile = Join-Path $customSkill 'SKILL.md'
    [IO.File]::WriteAllText($customFile, 'user-owned', $utf8)

    Sync-V5ProviderSkills -From $srcRoot -To $dstRoot

    $actual = [IO.File]::ReadAllText($dstFile)
    if ($actual -cne $new) {
        throw "same-metadata changed content was not overwritten: '$actual'"
    }
    if ((Get-FileHash -LiteralPath $srcFile -Algorithm SHA256).Hash -cne
        (Get-FileHash -LiteralPath $dstFile -Algorithm SHA256).Hash) {
        throw 'destination hash does not match source after sync'
    }
    if (Test-Path -LiteralPath (Join-Path $dstSkill 'STALE.txt')) {
        throw 'bundle-owned skill retained a stale extra file'
    }
    if (-not (Test-Path -LiteralPath $customFile -PathType Leaf)) {
        throw 'unrelated user skill was deleted by bundle sync'
    }
    if ([IO.File]::ReadAllText($customFile) -cne 'user-owned') {
        throw 'unrelated user skill was modified by bundle sync'
    }

    Write-Host 'PROVIDER SKILL SYNC: PASS' -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ('PROVIDER SKILL SYNC: FAIL - ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
