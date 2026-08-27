<#
.SYNOPSIS
  Write correct per-model load settings into LM Studio, computed from each
  model's own GGUF header and your actual VRAM.

.DESCRIPTION
  LM Studio saves load settings per model, and nothing checks them against the
  card. Measured on the maintainer's machine, four of five saved configs for one
  model family were unloadable as written:

    quant        saved by hand                          asked for
    UD-IQ3_XXS   ctx 65,000  K/V q8_0  1 session        18.32 GiB
    UD-Q3_K_XL   ctx 64,000  K/V q8_0  2 sessions  75%  far over
    UD-Q2_K_XL   ctx 64,000  K/V q8_0  3 sessions       far over
    UD-IQ2_S     ctx 64,000  K/V q8_0  1 session        over
    Q2_K         ctx 66,000  K/V q4_0  1 session        the only correct one

  A 16 GB card has about 14.5 GiB usable on a lean desktop. Every row but the
  last spilled to system RAM over PCIe, which is what "sometimes fast, sometimes
  hella slow" actually is.

  Three settings cause almost all of it, and none of them looks like it costs
  VRAM:

    * K/V cache quantisation -- q8_0 is DOUBLE q4_0, fp16 is quadruple
    * numParallelSessions    -- a MULTIPLIER on the entire cache
    * offloadRatio           -- below 1 puts layers on the CPU

  This script reads the geometry from each GGUF, computes the largest context
  that genuinely fits at q4_0, and writes it back. It backs up first and
  supports -WhatIf.

.PARAMETER ModelsRoot
  LM Studio models folder. Default %USERPROFILE%\.lmstudio\models.

.PARAMETER MaxContext
  Cap. Default 65536 -- the first power of two above the 64,000 floor Hermes
  refuses to start below.

.PARAMETER ReserveGB
  Held back for the desktop and llama.cpp's compute buffers. Default 1.5, which
  assumes a LEAN desktop. Run Get-KvBudget.ps1 to see what is free right now;
  browsers, Discord and vendor tray apps can hold several GB.

.PARAMETER Apply
  Without it, nothing is written -- the table is printed and that is all.

.EXAMPLE
  .\Optimize-LMStudioModelConfig.ps1
  .\Optimize-LMStudioModelConfig.ps1 -Apply
  .\Optimize-LMStudioModelConfig.ps1 -ReserveGB 3 -Apply
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$ModelsRoot,
  [int]$MaxContext = 65536,
  [double]$ReserveGB = 1.5,
  [double]$VramGB = 0,
  [switch]$Apply
)

$ErrorActionPreference = 'Stop'
if (-not $ModelsRoot) { $ModelsRoot = Join-Path $env:USERPROFILE '.lmstudio\models' }
$ConfigRoot = Join-Path $env:USERPROFILE '.lmstudio\.internal\user-concrete-model-default-config'

if (-not (Test-Path -LiteralPath $ModelsRoot -PathType Container)) {
  Write-Error "No LM Studio models folder at $ModelsRoot"; exit 1
}

# ---------------------------------------------------------------- vram ----
if ($VramGB -le 0) {
  try {
    $q = & nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>$null
    if ($q) { $VramGB = [double](($q | Select-Object -First 1).Trim()) / 1024.0 }
  } catch { }
}
if ($VramGB -le 0) { Write-Error 'Could not detect VRAM; pass -VramGB.'; exit 1 }

# ------------------------------------------------------------ gguf read ----
# Values are read rather than skipped: GGUF type codes are variable-width and
# carry no length prefix to jump over.
function Read-GgufGeometry {
  param([string]$Path)
  $fs = [IO.File]::OpenRead($Path); $br = New-Object IO.BinaryReader($fs)
  try {
    if ([Text.Encoding]::ASCII.GetString($br.ReadBytes(4)) -ne 'GGUF') { return $null }
    [void]$br.ReadUInt32(); [void]$br.ReadUInt64()
    $kvCount = $br.ReadUInt64()
    function RdStr($r) { $n = $r.ReadUInt64(); [Text.Encoding]::UTF8.GetString($r.ReadBytes([int]$n)) }
    function RdVal($r, [int]$t) {
      switch ($t) {
        0 { $r.ReadByte() }   1 { $r.ReadSByte() }  2 { $r.ReadUInt16() } 3 { $r.ReadInt16() }
        4 { $r.ReadUInt32() } 5 { $r.ReadInt32() }  6 { $r.ReadSingle() } 7 { $r.ReadBoolean() }
        8 { RdStr $r }
        9 { $et = $r.ReadUInt32(); $n = $r.ReadUInt64()
            for ($i = 0; $i -lt [int]$n; $i++) { [void](RdVal $r ([int]$et)) }; $null }
        10 { $r.ReadUInt64() } 11 { $r.ReadInt64() } 12 { $r.ReadDouble() }
        default { throw "unknown GGUF type $t" }
      }
    }
    $md = @{}
    for ($i = 0; $i -lt [int]$kvCount; $i++) {
      $k = RdStr $br; $t = [int]$br.ReadUInt32(); $v = RdVal $br $t
      if ($null -ne $v) { $md[$k] = $v }
    }
  } finally { $br.Dispose(); $fs.Dispose() }
  function Get-GgufKey([string]$suffix) { foreach ($k in $md.Keys) { if ($k.EndsWith($suffix)) { return $md[$k] } }; return $null }
  $layers = Get-GgufKey 'block_count'; $kvh = Get-GgufKey 'attention.head_count_kv'
  $kLen = Get-GgufKey 'attention.key_length'; $vLen = Get-GgufKey 'attention.value_length'
  if (-not $kLen) {
    $e = Get-GgufKey 'embedding_length'; $h = Get-GgufKey 'attention.head_count'
    if ($e -and $h) { $kLen = [math]::Floor($e / $h) }
  }
  if (-not $vLen) { $vLen = $kLen }
  if (-not ($layers -and $kvh -and $kLen)) { return $null }
  return [pscustomobject]@{ Layers = $layers; KvHeads = $kvh; KLen = $kLen; VLen = $vLen }
}

# ---------------------------------------------------------------- plan ----
$models = @(Get-ChildItem -LiteralPath $ModelsRoot -Recurse -Filter *.gguf -EA SilentlyContinue |
            Where-Object { $_.Name -notlike 'mmproj*' })
if (-not $models.Count) { Write-Error "No .gguf under $ModelsRoot"; exit 1 }

Write-Host ''
Write-Host ("== LM Studio load settings, computed ==  VRAM {0:N2} GB, reserve {1:N1} GB" -f $VramGB, $ReserveGB) -ForegroundColor Cyan
Write-Host ''
Write-Host ('{0,-46} {1,8} {2,10} {3,10}' -f 'model', 'weights', 'max ctx', 'writing')
Write-Host ('{0,-46} {1,8} {2,10} {3,10}' -f '---------------------------------------------', '-------', '---------', '---------')

$plans = @()
foreach ($m in $models) {
  $g = Read-GgufGeometry -Path $m.FullName
  if (-not $g) { Write-Host ('{0,-46} {1,8} {2,10} {3,10}' -f $m.BaseName, '-', '-', 'unreadable'); continue }
  $perTok = [double]$g.Layers * [double]$g.KvHeads * ([double]$g.KLen + [double]$g.VLen) * 2.0 * 0.25  # q4_0
  $wGB = $m.Length / 1GB
  $free = ($VramGB - $ReserveGB - $wGB) * 1GB
  $maxCtx = if ($free -gt 0) { [math]::Floor($free / $perTok) } else { 0 }
  $ctx = [math]::Min($MaxContext, [math]::Floor($maxCtx / 4096) * 4096)
  if ($ctx -lt 4096) { $ctx = 4096 }   # a context of 0 is not a setting
  $colour = if ($maxCtx -ge $MaxContext) { 'Green' } elseif ($maxCtx -ge 4096) { 'Yellow' } else { 'Red' }
  Write-Host ('{0,-46} {1,7:N2}G {2,10:N0} {3,10:N0}' -f $m.BaseName, $wGB, $maxCtx, $ctx) -ForegroundColor $colour
  $plans += [pscustomobject]@{ File = $m; Ctx = $ctx; MaxCtx = $maxCtx }
}

Write-Host ''
Write-Host 'Every row is written with K/V cache q4_0, ONE parallel session, and full GPU offload.'
Write-Host 'Those three are where the VRAM goes, and none of them reads like it costs any.'
Write-Host ("Rows under {0:N0} cannot serve Hermes, which refuses a window below 64,000." -f 64000)

if (-not $Apply) {
  Write-Host ''
  Write-Host 'Nothing was written. Re-run with -Apply to save these.' -ForegroundColor Yellow
  exit 0
}

# --------------------------------------------------------------- apply ----
if (-not (Test-Path -LiteralPath $ConfigRoot -PathType Container)) {
  New-Item -ItemType Directory -Force -Path $ConfigRoot | Out-Null
}
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path (Split-Path -Parent $ConfigRoot) ("uabs-backup-$stamp")
if ($PSCmdlet.ShouldProcess($ConfigRoot, 'back up existing per-model configs')) {
  New-Item -ItemType Directory -Force -Path $backup | Out-Null
  Copy-Item -LiteralPath $ConfigRoot -Destination $backup -Recurse -Force -EA SilentlyContinue
  Write-Host ("backup: " + $backup) -ForegroundColor DarkGray
}

foreach ($p in $plans) {
  # LM Studio keys the config by the model's path under the models root.
  $rel = $p.File.FullName.Substring($ModelsRoot.Length).TrimStart('\', '/')
  $dest = Join-Path $ConfigRoot ($rel + '.json')
  $dir = Split-Path -Parent $dest
  if (-not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

  $fields = New-Object System.Collections.Generic.List[object]
  if (Test-Path -LiteralPath $dest -PathType Leaf) {
    try {
      $existing = Get-Content -LiteralPath $dest -Raw | ConvertFrom-Json
      if ($existing.fields) { foreach ($f in $existing.fields) { [void]$fields.Add($f) } }
    } catch { }
  }
  function SetField([string]$Key, $Value) {
    foreach ($f in $fields) { if ($f.key -eq $Key) { $f.value = $Value; return } }
    [void]$fields.Add([pscustomobject]@{ key = $Key; value = $Value })
  }
  SetField 'llm.load.contextLength' $p.Ctx
  SetField 'llm.load.llama.kCacheQuantizationType' ([pscustomobject]@{ checked = $true; value = 'q4_0' })
  SetField 'llm.load.llama.vCacheQuantizationType' ([pscustomobject]@{ checked = $true; value = 'q4_0' })
  SetField 'llm.load.llama.acceleration.offloadRatio' 1
  SetField 'llm.load.numParallelSessions' 1
  SetField 'llm.load.llama.flashAttention' $true

  if ($PSCmdlet.ShouldProcess($dest, "write ctx $($p.Ctx), q4_0 K/V, 1 session, full offload")) {
    $json = ([pscustomobject]@{ fields = $fields } | ConvertTo-Json -Depth 12)
    [IO.File]::WriteAllText($dest, $json + "`n", (New-Object Text.UTF8Encoding $false))
    Write-Host ('  wrote ' + $rel) -ForegroundColor Green
  }
}

Write-Host ''
Write-Host 'Restart LM Studio, then load the model and confirm the reported context.' -ForegroundColor Yellow
Write-Host 'A cold start reads the saved default -- which is what Hermes preloads.' -ForegroundColor DarkGray
exit 0
