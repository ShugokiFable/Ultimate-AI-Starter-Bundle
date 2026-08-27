<#
.SYNOPSIS
  Work out whether a GGUF model plus its KV cache actually fits in your VRAM.

.DESCRIPTION
  "Sometimes fast, sometimes hella slow" on a local model is almost never
  another process taking the GPU. It is the KV cache growing with the
  conversation until it no longer fits, at which point it spills to system RAM
  over PCIe and throughput collapses. Fresh chat quick, long chat unusable.

  Nothing about that is visible in the LM Studio UI, so this reads the numbers
  that decide it straight out of the GGUF header and prints the context you can
  actually afford at each cache precision.

  It reads the file. It changes nothing.

  The field that surprises people is key_length. The common value is 128; a
  model shipping 256 costs exactly twice the cache of a same-size model, and
  nothing in the model card mentions it.

.PARAMETER Model
  Path to a .gguf file. Defaults to the largest model under the LM Studio
  models folder, which is usually the one you are actually running.

.PARAMETER VramGB
  Usable VRAM. Defaults to the first NVIDIA GPU's total reported by
  nvidia-smi, minus a desktop reserve.

.PARAMETER ReserveGB
  Held back for the desktop, other apps, and llama.cpp's own compute buffers.
  Default 1.5.

.PARAMETER Sessions
  llm.load.numParallelSessions. EACH parallel session needs its own KV cache,
  so 2 doubles the bill. Default 1.

.EXAMPLE
  .\Get-KvBudget.ps1
  .\Get-KvBudget.ps1 -Model "C:\models\foo.gguf" -VramGB 24 -Sessions 1
#>
[CmdletBinding()]
param(
  [string]$Model,
  [double]$VramGB = 0,
  [double]$ReserveGB = 1.5,
  [ValidateRange(1, 16)][int]$Sessions = 1
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- model ----
if (-not $Model) {
  $root = Join-Path $env:USERPROFILE '.lmstudio\models'
  if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    Write-Error "No -Model given and $root does not exist."
    exit 1
  }
  $Model = (Get-ChildItem -LiteralPath $root -Recurse -Filter *.gguf -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike 'mmproj*' } |
            Sort-Object Length -Descending | Select-Object -First 1).FullName
  if (-not $Model) { Write-Error "No .gguf found under $root."; exit 1 }
}
if (-not (Test-Path -LiteralPath $Model -PathType Leaf)) { Write-Error "Not found: $Model"; exit 1 }

# ------------------------------------------------------------ gguf read ----
# Minimal metadata reader: header, then key/value pairs until we have what the
# KV arithmetic needs. Values are read rather than skipped because the type
# codes are variable-width and there is no length prefix to jump over.
$fs = [IO.File]::OpenRead($Model)
$br = New-Object IO.BinaryReader($fs)
try {
  if ([Text.Encoding]::ASCII.GetString($br.ReadBytes(4)) -ne 'GGUF') {
    Write-Error "Not a GGUF file: $Model"; exit 1
  }
  [void]$br.ReadUInt32()                 # version
  [void]$br.ReadUInt64()                 # tensor count
  $kvCount = $br.ReadUInt64()

  function Read-GgufString { param($r) $n = $r.ReadUInt64(); [Text.Encoding]::UTF8.GetString($r.ReadBytes([int]$n)) }
  function Read-GgufValue {
    param($r, [int]$t)
    switch ($t) {
      0 { $r.ReadByte() }    1 { $r.ReadSByte() }
      2 { $r.ReadUInt16() }  3 { $r.ReadInt16() }
      4 { $r.ReadUInt32() }  5 { $r.ReadInt32() }
      6 { $r.ReadSingle() }  7 { $r.ReadBoolean() }
      8 { Read-GgufString $r }
      9 {
        $et = $r.ReadUInt32(); $n = $r.ReadUInt64()
        for ($i = 0; $i -lt [int]$n; $i++) { [void](Read-GgufValue $r ([int]$et)) }
        $null
      }
      10 { $r.ReadUInt64() } 11 { $r.ReadInt64() } 12 { $r.ReadDouble() }
      default { throw "unknown GGUF type $t" }
    }
  }

  $md = @{}
  for ($i = 0; $i -lt [int]$kvCount; $i++) {
    $key = Read-GgufString $br
    $typ = [int]$br.ReadUInt32()
    $val = Read-GgufValue $br $typ
    if ($null -ne $val) { $md[$key] = $val }
  }
} finally { $br.Dispose(); $fs.Dispose() }

function Get-Md { param([string]$Suffix)
  foreach ($k in $md.Keys) { if ($k.EndsWith($Suffix)) { return $md[$k] } }
  return $null
}

$layers  = Get-Md 'block_count'
$kvHeads = Get-Md 'attention.head_count_kv'
$kLen    = Get-Md 'attention.key_length'
$vLen    = Get-Md 'attention.value_length'
$embed   = Get-Md 'embedding_length'
$heads   = Get-Md 'attention.head_count'

# Not every model declares key_length/value_length. When absent the usual
# convention is embedding_length / head_count -- state the fallback rather than
# printing a number whose origin is invisible.
$derived = $false
if (-not $kLen -and $embed -and $heads) { $kLen = [math]::Floor($embed / $heads); $derived = $true }
if (-not $vLen) { $vLen = $kLen }

if (-not ($layers -and $kvHeads -and $kLen)) {
  Write-Error "This GGUF does not declare block_count / head_count_kv / key_length; cannot compute."
  exit 1
}

# ------------------------------------------------------------- budget ------
if ($VramGB -le 0) {
  try {
    $q = & nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>$null
    if ($q) { $VramGB = [double](($q | Select-Object -First 1).Trim()) / 1024.0 }
  } catch { }
}
if ($VramGB -le 0) { Write-Error "Could not detect VRAM; pass -VramGB."; exit 1 }

$weightsGB = (Get-Item -LiteralPath $Model).Length / 1GB
$usableGB  = $VramGB - $ReserveGB - $weightsGB

Write-Host ''
Write-Host '== KV cache budget ==' -ForegroundColor Cyan
Write-Host ("model            : " + (Split-Path -Leaf $Model))
Write-Host ("weights          : {0:N2} GB" -f $weightsGB)
Write-Host ("VRAM total       : {0:N2} GB   (reserve {1:N1} GB for desktop + compute buffers)" -f $VramGB, $ReserveGB)
Write-Host ("left for KV      : {0:N2} GB" -f $usableGB)
Write-Host ("parallel sessions: {0}{1}" -f $Sessions, $(if ($Sessions -gt 1) { "   <-- each one pays the full cache again" } else { '' }))
Write-Host ''
Write-Host ("layers {0}  kv_heads {1}  key_len {2}  value_len {3}{4}" -f $layers, $kvHeads, $kLen, $vLen, $(if ($derived) { '   (key_len derived from embedding/head_count)' } else { '' }))
if ($kLen -ge 256) {
  Write-Host ("  key_length {0} is double the common 128 -- this model costs twice the cache of a same-size model." -f $kLen) -ForegroundColor Yellow
}

$perTokenFp16 = [double]$layers * [double]$kvHeads * ([double]$kLen + [double]$vLen) * 2.0
Write-Host ("KV per token     : {0:N0} bytes at fp16  ({1:N3} MB)" -f $perTokenFp16, ($perTokenFp16 / 1MB))

if ($usableGB -le 0) {
  Write-Host ''
  Write-Host "The weights alone do not fit. Use a smaller quant or a smaller model." -ForegroundColor Red
  exit 2
}

Write-Host ''
Write-Host ('{0,-10} {1,-16} {2,-14} {3}' -f 'K/V quant', 'bytes/token', 'max context', 'at 65,536 ctx')
Write-Host ('{0,-10} {1,-16} {2,-14} {3}' -f '---------', '-----------', '-----------', '-------------')
foreach ($q in @(
    @{ n = 'fp16'; f = 1.0 },
    @{ n = 'q8_0'; f = 0.5 },
    @{ n = 'q4_0'; f = 0.25 })) {
  $perTok = $perTokenFp16 * $q.f
  $maxCtx = [math]::Floor(($usableGB * 1GB) / ($perTok * $Sessions))
  $at64k  = (65536.0 * $perTok * $Sessions) / 1GB
  $verdict = if ($at64k -le $usableGB) { 'fits' } else { ('needs {0:N1} GB' -f $at64k) }
  $colour = if ($at64k -le $usableGB) { 'Green' } else { 'DarkGray' }
  Write-Host ('{0,-10} {1,-16:N0} {2,-14:N0} {3}' -f $q.n, $perTok, $maxCtx, $verdict) -ForegroundColor $colour
}

Write-Host ''
Write-Host 'Hermes refuses a context window under 64,000, so a row that cannot reach 65,536'
Write-Host 'is not an option for Hermes use -- only for bare LM Studio chat at lower context.'
Write-Host ''
Write-Host 'Set K and V cache quantisation, context length and parallel sessions in the'
Write-Host "model's load settings, or apply the shipped preset:" -ForegroundColor Yellow
Write-Host '    .\Install-LMStudio-Presets.ps1' -ForegroundColor Yellow
exit 0
