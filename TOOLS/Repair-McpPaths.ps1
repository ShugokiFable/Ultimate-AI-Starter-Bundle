<#
.SYNOPSIS
  Find MCP servers wired to absolute paths that no longer exist, and repoint
  them at the version that is actually installed.

.DESCRIPTION
  Every provider stores MCP server commands as a hard absolute path, in its own
  format: Claude JSON, Kimi JSON, Codex TOML, Grok TOML, Hermes YAML. When a
  tool is upgraded in place (Skyrim-Forge-5.1.0 -> 5.1.3) the folder name
  changes, so each config has to be edited by hand -- and one always gets
  missed. The missed one does not fail loudly; the server just never connects.

  Observed: Forge moved to 5.1.3, Kimi/Codex/Grok/Hermes were updated, Claude
  was left pointing at 5.1.0 and its skyrim-forge MCP silently went dead.

  This script does not parse the five formats. It looks for the dead path as a
  literal string and replaces it with the live one, which is format-agnostic
  and cannot reorder or reformat a user's config. Backup first, always.

  Default is report-only. -Apply performs the edit.

.PARAMETER Apply
  Write the repairs. Without it, nothing is modified.

.PARAMETER Quiet
  Only print problems and repairs, not healthy servers.

.EXAMPLE
  .\Repair-McpPaths.ps1
  .\Repair-McpPaths.ps1 -Apply
#>
[CmdletBinding()]
param(
  [switch]$Apply,
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

$configs = @(
  @{ Name = 'Claude'; Path = (Join-Path $env:USERPROFILE '.claude.json') }
  @{ Name = 'Kimi';   Path = (Join-Path $env:USERPROFILE '.kimi-code\mcp.json') }
  @{ Name = 'Codex';  Path = (Join-Path $env:USERPROFILE '.codex\config.toml') }
  @{ Name = 'Grok';   Path = (Join-Path $env:USERPROFILE '.grok\config.toml') }
  @{ Name = 'Hermes'; Path = (Join-Path $env:LOCALAPPDATA 'hermes\config.yaml') }
)

# Claude Desktop (Store app) keeps its own MCP config and does NOT read
# ~/.claude.json for its servers. The package folder is hash-suffixed, so
# glob for the config file instead of hardcoding the package name.
$desktopCfg = Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'Packages') -Filter 'claude_desktop_config.json' -Recurse -Depth 4 -ErrorAction SilentlyContinue | Select-Object -First 1
if ($desktopCfg) {
  $configs += @{ Name = 'Claude Desktop'; Path = $desktopCfg.FullName }
}

# A path inside a config may be written with \ or /. Compare on a normalized
# form so "S:/x/y" and "S:\x\y" are recognized as the same file.
# JSON escapes every separator, so the literal in the file reads "S:\\x\\y".
# Collapse that doubling before touching the filesystem, or Test-Path and the
# version splitter both see empty path segments.
function Get-NormalPath([string]$p) { return (($p -replace '/', '\') -replace '\\{2,}', '\') }

# Re-apply whatever escaping the config literal used, so a JSON file keeps its
# doubled separators and a TOML/YAML one keeps its single ones. Writing a lone
# backslash into JSON produces an invalid escape and an unparseable config.
# String.Replace, not -replace: the latter is regex on BOTH sides, and getting
# the replacement-side backslash count right is a coin flip (one pass produced
# "S:\.venv\\Scripts", the next "S:\\\\Apps"). Plain string replacement has no
# escape semantics, so what is written is what is meant.
function ConvertTo-ConfigLiteral([string]$LivePath, [string]$DeadLiteral) {
  $single = $LivePath.Replace('/', '\')
  if ($DeadLiteral -match '/') { return $single.Replace('\', '/') }
  if ($DeadLiteral.Contains('\\')) { return $single.Replace('\', '\\') }
  return $single
}

# Absolute Windows paths that look like a program, in either slash style.
$rxPath = '(?<p>[A-Za-z]:[\\/](?:[^"''\r\n]*?)\.(?:exe|cmd|bat|ps1|py))'

<#
  Repointing rule: if a dead path contains a version-stamped directory
  (Name-1.2.3), look for a sibling directory with the same stem and a different
  version, and prefer the highest one whose target file exists. Anything that
  does not fit that shape is reported but never guessed at.
#>
function Resolve-LivePath([string]$dead) {
  $norm = Get-NormalPath $dead
  $parts = $norm -split '\\'
  for ($i = 0; $i -lt $parts.Count; $i++) {
    if ($parts[$i] -notmatch '^(?<stem>.+?)-(?<ver>\d+(?:\.\d+)*)$') { continue }
    $stem = $Matches['stem']
    $parent = ($parts[0..($i - 1)] -join '\')
    if (-not $parent -or -not (Test-Path -LiteralPath $parent)) { continue }
    $tailParts = @()
    if ($i -lt ($parts.Count - 1)) { $tailParts = $parts[($i + 1)..($parts.Count - 1)] }
    $tail = $tailParts -join '\'
    $cands = @()
    foreach ($d in (Get-ChildItem -LiteralPath $parent -Directory -ErrorAction SilentlyContinue)) {
      if ($d.Name -notmatch ('^' + [regex]::Escape($stem) + '-(?<ver>\d+(?:\.\d+)*)$')) { continue }
      $full = if ($tail) { Join-Path $d.FullName $tail } else { $d.FullName }
      if (-not (Test-Path -LiteralPath $full)) { continue }
      $v = $null
      # [version] needs at least two parts; pad so "5" parses.
      $vs = $Matches['ver']
      while (($vs -split '\.').Count -lt 2) { $vs = $vs + '.0' }
      if (-not [version]::TryParse($vs, [ref]$v)) { continue }
      $cands += [pscustomobject]@{ Version = $v; Full = $full }
    }
    if ($cands.Count) {
      return (($cands | Sort-Object Version -Descending)[0]).Full
    }
    # No version-stamped sibling found. The user may have renamed the folder
    # to drop the version suffix (Skyrim-Forge-5.1.6 -> Skyrim-Forge), which
    # the regex above cannot match. Fall back to the bare stem as a sibling.
    $bare = Join-Path $parent $stem
    if (Test-Path -LiteralPath $bare) {
      $full = if ($tail) { Join-Path $bare $tail } else { $bare }
      if (Test-Path -LiteralPath $full) { return $full }
    }
  }
  # The bundle registers houseCARL via the HOUSECARL_MCP user env. It is the
  # one server whose live root is NOT a version-stamped sibling of the dead
  # path (users move it to a tools drive; the sibling rule cannot cross
  # drives, so the loop above finds nothing and this used to report
  # "no replacement found" for a perfectly live server). That env is the
  # bundle's own registry - repoint from it, never guess.
  if ((Get-NormalPath $dead) -match '(?i)housecarl-mcp\.exe$') {
    $envMcp = [Environment]::GetEnvironmentVariable('HOUSECARL_MCP','User')
    if (-not $envMcp) { $envMcp = $env:HOUSECARL_MCP }
    if ($envMcp -and (Test-Path -LiteralPath (Get-NormalPath $envMcp))) { return (Get-NormalPath $envMcp) }
  }
  return $null
}

$problems = 0
$repairs = 0

foreach ($c in $configs) {
  if (-not (Test-Path -LiteralPath $c.Path)) {
    if (-not $Quiet) { Write-Host ("{0,-7} not installed" -f $c.Name) -ForegroundColor DarkGray }
    continue
  }
  $text = [IO.File]::ReadAllText($c.Path)
  $seen = New-Object 'System.Collections.Generic.HashSet[string]'
  $dead = @()
  foreach ($m in [regex]::Matches($text, $rxPath)) {
    $p = $m.Groups['p'].Value
    if (-not $seen.Add((Get-NormalPath $p).ToLowerInvariant())) { continue }
    if (Test-Path -LiteralPath (Get-NormalPath $p)) { continue }
    $dead += $p
  }
  if (-not $dead.Count) {
    if (-not $Quiet) { Write-Host ("{0,-7} OK" -f $c.Name) -ForegroundColor Green }
    continue
  }
  $newText = $text
  $changed = $false
  foreach ($d in $dead) {
    $problems++
    $live = Resolve-LivePath $d
    if (-not $live) {
      Write-Host ("{0,-7} DEAD (no replacement found)" -f $c.Name) -ForegroundColor Red
      Write-Host ("          $d") -ForegroundColor Red
      continue
    }
    # Preserve the slash style AND the escaping the config already used, so the
    # diff is one version number, not a whole-path restyle or a broken escape.
    $liveStyled = ConvertTo-ConfigLiteral -LivePath $live -DeadLiteral $d
    Write-Host ("{0,-7} REPOINT" -f $c.Name) -ForegroundColor Yellow
    Write-Host ("          from $d") -ForegroundColor DarkYellow
    Write-Host ("          to   $liveStyled") -ForegroundColor DarkYellow
    $newText = $newText.Replace($d, $liveStyled)
    $changed = $true
    $repairs++
  }
  if ($changed -and $Apply) {
    $bytes = [IO.File]::ReadAllBytes($c.Path)
    $hadBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $bak = $c.Path + '.before-mcprepair-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.bak'
    Copy-Item -LiteralPath $c.Path -Destination $bak -Force
    [IO.File]::WriteAllText($c.Path, $newText, (New-Object System.Text.UTF8Encoding $hadBom))
    Write-Host ("          written (backup: " + (Split-Path $bak -Leaf) + ")") -ForegroundColor Green
  }
}

Write-Host ''
if ($problems -eq 0) {
  Write-Host 'All MCP command paths resolve.' -ForegroundColor Green
} elseif ($Apply) {
  Write-Host ("Repaired {0} of {1} dead path(s)." -f $repairs, $problems) -ForegroundColor Green
} else {
  Write-Host ("{0} dead path(s); {1} can be repaired. Re-run with -Apply." -f $problems, $repairs) -ForegroundColor Yellow
}
if ($problems -gt $repairs) { exit 3 }
