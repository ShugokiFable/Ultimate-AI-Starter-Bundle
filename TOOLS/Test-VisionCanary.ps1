<#
.SYNOPSIS
  Prove this agent can actually see image pixels, rather than claiming it can.

.DESCRIPTION
  "Use vision" is the easiest instruction in this pack to fake. A model that
  cannot see pixels can still write "I inspected the screenshot and it looks
  correct" -- the honest report and the fabricated one are the same shape, and no
  wording in a skill file can tell them apart.

  So this is a falsifiable check instead of an instruction.

  TOOLS\vision-canary\vision-canary.png contains one word, one shape, and that
  shape's colour. Open it with whatever image-reading capability you have, then
  report what you saw:

      TOOLS\Test-VisionCanary.ps1 -Word <word> -Shape <shape> -Color <colour>

  The expected answer is stored only as a SHA-256 of '<word>|<shape>|<colour>'
  in lower case, so reading this repository is not a substitute for looking at
  the image. That distinction is the whole point: "a screenshot was captured"
  and "the agent inspected the pixels" are different claims, and only one of them
  supports a completion claim about appearance.

  A FAIL is not a failure of the workflow. It is the answer: this session cannot
  verify appearance. Say so, keep the screenshot as an artifact for someone who
  can, and fall back to DOM/accessibility/runtime evidence -- do not claim visual
  verification happened.

.EXAMPLE
  TOOLS\Test-VisionCanary.ps1 -Word <the word> -Shape <the shape> -Color <its colour>
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Word,
  [Parameter(Mandatory = $true)][string]$Shape,
  [Parameter(Mandatory = $true)][string]$Color,
  [string]$CanaryRoot
)

$ErrorActionPreference = 'Stop'

if (-not $CanaryRoot) { $CanaryRoot = Join-Path $PSScriptRoot 'vision-canary' }
$metaPath = Join-Path $CanaryRoot 'canary.json'
$imagePath = Join-Path $CanaryRoot 'vision-canary.png'

foreach ($p in @($metaPath, $imagePath)) {
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
    throw "vision canary incomplete: $p is missing"
  }
}

$meta = [IO.File]::ReadAllText($metaPath) | ConvertFrom-Json

# Lower case and trimmed, so a correct answer is not failed over capitalisation.
$answer = ('{0}|{1}|{2}' -f $Word.Trim().ToLowerInvariant(),
                            $Shape.Trim().ToLowerInvariant(),
                            $Color.Trim().ToLowerInvariant())

$sha = [System.Security.Cryptography.SHA256]::Create()
try {
  $bytes = [Text.Encoding]::UTF8.GetBytes($answer)
  $digest = -join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })
} finally { $sha.Dispose() }

if ($digest -eq $meta.answer_sha256) {
  Write-Host 'VISION CANARY: PASS' -ForegroundColor Green
  Write-Host '  This session can see image pixels. Visual verification is available:' -ForegroundColor DarkGray
  Write-Host '  render the real output, look at it, and only then call appearance correct.' -ForegroundColor DarkGray
  exit 0
}

Write-Host 'VISION CANARY: FAIL' -ForegroundColor Red
Write-Host '  That is an answer, not an error. Either the image was not actually read,' -ForegroundColor Yellow
Write-Host '  or this client does not deliver image pixels to the model.' -ForegroundColor Yellow
Write-Host ''
Write-Host '  Do NOT claim visual verification in this session. Instead:' -ForegroundColor Yellow
Write-Host '    - keep the screenshot as an artifact for the user or a capable agent;'
Write-Host '    - fall back to DOM / accessibility tree / console / network / layout evidence;'
Write-Host '    - say "visual verification unavailable in this provider/session".'
exit 1
