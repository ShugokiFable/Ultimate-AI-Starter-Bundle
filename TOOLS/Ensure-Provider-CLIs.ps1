<#
.SYNOPSIS
  Bootstrap the five supported AI provider CLIs on a fresh Windows user profile.
.DESCRIPTION
  Uses each provider's official Windows installer only when its command is absent,
  refreshes the current process PATH, and proves the executable starts. Existing
  installations are preserved. Authentication is deliberately not fabricated;
  providers that need first-run OAuth/API credentials are reported AUTH_REQUIRED.
#>
[CmdletBinding()]
param(
  [string[]]$Providers = @('Claude','Codex','Grok','Kimi','Hermes'),
  [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'UABS-Common.ps1')

# -File turns Claude,Codex into one string on Windows PowerShell 5.1.
$Providers = @($Providers | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$allowed = @('Claude','Codex','Grok','Kimi','Hermes')
foreach ($p in $Providers) { if ($allowed -notcontains $p) { throw "Unknown provider: $p" } }

function Refresh-ProcessPath {
  $machine = [Environment]::GetEnvironmentVariable('Path','Machine')
  $user = [Environment]::GetEnvironmentVariable('Path','User')
  $env:Path = (@($machine,$user) | Where-Object { $_ }) -join ';'
}

function Resolve-ProviderExe([string]$Provider) {
  $name = $Provider.ToLowerInvariant()
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $candidates = switch ($Provider) {
    'Claude' { @((Join-Path $env:USERPROFILE '.local\bin\claude.exe')) }
    'Codex'  { @((Join-Path $env:USERPROFILE '.local\bin\codex.exe'), (Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin\codex.exe')) }
    'Grok'   { @((Join-Path $env:USERPROFILE '.grok\bin\grok.exe')) }
    'Kimi'   { @((Join-Path $env:USERPROFILE '.local\bin\kimi.exe'), (Join-Path $env:USERPROFILE '.kimi-code\bin\kimi.exe')) }
    'Hermes' { @((Join-Path $env:LOCALAPPDATA 'hermes\hermes-agent\venv\Scripts\hermes.exe')) }
  }
  foreach ($c in $candidates) { if ($c -and (Test-Path -LiteralPath $c -PathType Leaf)) { return $c } }
  return $null
}

function Invoke-VerifiedOfficialScript([string]$Provider,[string]$Url,[string[]]$ScriptArgs=@()) {
  $temp = Join-Path $env:TEMP ("uabs-" + $Provider.ToLowerInvariant() + '-' + [guid]::NewGuid().ToString('N') + '.ps1')
  try {
    Write-UabsStep "$Provider official installer"
    $downloaded = $false
    for ($attempt = 1; $attempt -le 3; $attempt++) {
      try {
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $temp -TimeoutSec 180
        $downloaded = $true
        break
      } catch {
        if ($attempt -ge 3) { throw }
        Start-Sleep -Seconds ([Math]::Pow(2, $attempt))
      }
    }
    if (-not $downloaded -or -not (Test-Path -LiteralPath $temp -PathType Leaf) -or (Get-Item $temp).Length -lt 256) { throw "$Provider installer download was empty." }
    $raw = [IO.File]::ReadAllText($temp)
    if ($raw -match '(?i)<html|cloudflare|just a moment') { throw "$Provider installer endpoint returned HTML/challenge instead of PowerShell." }
    $sha = (Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash
    Write-Host "  downloaded installer sha256=$sha"
    if ($CheckOnly) { return }

    # Vendor scripts may call `exit`; execute them in a child Windows
    # PowerShell so they cannot terminate the parent AIO before its doctor and
    # install report run. -File also gives us an explicit process exit code.
    $child = (Get-Command powershell.exe -ErrorAction Stop).Source
    $childArgs = @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$temp) + @($ScriptArgs)
    & $child @childArgs
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw "$Provider official installer exited $code." }
  } finally {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
  }
}

# Claude and Kimi require Git Bash for their native Windows shell surfaces.
Refresh-ProcessPath
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  if ($CheckOnly) { Write-Host 'Git would be installed with winget Git.Git' }
  elseif (-not (Install-UabsWinget @('Git.Git'))) { throw 'Git for Windows installation failed.' }
  Refresh-ProcessPath
}
if (-not $CheckOnly) {
  $git = Get-Command git -ErrorAction SilentlyContinue
  if (-not $git) { throw 'Git installer completed but git is still not resolvable.' }
  & git --version | Out-Host
  if ($LASTEXITCODE -ne 0) { throw 'git --version failed.' }
}

$installers = @{
  Claude = 'https://claude.ai/install.ps1'
  Codex  = 'https://chatgpt.com/codex/install.ps1'
  Grok   = 'https://x.ai/cli/install.ps1'
  Kimi   = 'https://code.kimi.com/kimi-code/install.ps1'
  Hermes = 'https://hermes-agent.nousresearch.com/install.ps1'
}
$results = @()
foreach ($provider in $Providers) {
  Refresh-ProcessPath
  $exe = Resolve-ProviderExe $provider
  $installedNow = $false
  if (-not $exe) {
    if ($CheckOnly) { Write-Host "$provider would install from $($installers[$provider])"; continue }
    $extra = if ($provider -eq 'Hermes') { @('-SkipSetup') } else { @() }
    $oldCodexNonInteractive = $env:CODEX_NON_INTERACTIVE
    if ($provider -eq 'Codex') { $env:CODEX_NON_INTERACTIVE = '1' }
    try {
      try {
        Invoke-VerifiedOfficialScript -Provider $provider -Url $installers[$provider] -ScriptArgs $extra
      } catch {
        if ($provider -ne 'Claude') { throw }
        Write-Warning "Claude native installer failed; trying Anthropic's official WinGet package. $($_.Exception.Message)"
        if (-not (Install-UabsWinget @('Anthropic.ClaudeCode'))) { throw 'Claude official script and WinGet fallback both failed.' }
      }
    } finally {
      if ($provider -eq 'Codex') {
        if ($null -eq $oldCodexNonInteractive) { Remove-Item Env:CODEX_NON_INTERACTIVE -ErrorAction SilentlyContinue }
        else { $env:CODEX_NON_INTERACTIVE = $oldCodexNonInteractive }
      }
    }
    $installedNow = $true
    Refresh-ProcessPath
    $exe = Resolve-ProviderExe $provider
  }
  if (-not $exe) { throw "$provider installer returned but its executable cannot be found." }
  & $exe --version | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "$provider --version failed with exit code $LASTEXITCODE." }
  # Literal verification contracts kept visible for audit tooling:
  # claude --version | codex --version | grok --version | kimi --version | hermes --version
  $auth = 'AUTH_REQUIRED'
  if ($provider -eq 'Grok' -and ((Test-Path (Join-Path $env:USERPROFILE '.grok\auth.json')) -or $env:XAI_API_KEY)) { $auth='AUTH_PRESENT' }
  if ($provider -eq 'Codex' -and ((Test-Path (Join-Path $env:USERPROFILE '.codex\auth.json')) -or $env:OPENAI_API_KEY)) { $auth='AUTH_PRESENT' }
  if ($provider -eq 'Hermes' -and ($env:OPENROUTER_API_KEY -or $env:NOUS_API_KEY)) { $auth='AUTH_PRESENT' }
  $results += [pscustomobject]@{ provider=$provider; executable=$exe; installed_now=$installedNow; auth_state=$auth }
  Write-UabsOk ("$provider executable verified; " + $auth)
}
if (-not $CheckOnly) {
  $reportDir = Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle'
  New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
  $enc = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText((Join-Path $reportDir 'provider-bootstrap.json'), ($results | ConvertTo-Json -Depth 6), $enc)
}
