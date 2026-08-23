[CmdletBinding()]
param(
    [switch]$BootstrapPython
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$env:PYTHONUTF8 = '1'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Invoke-Checked {
    param([string]$Label, [string]$Command, [object[]]$Arguments = @())
    Write-Host ("  ..  " + $Label + '...') -ForegroundColor DarkCyan
    $Timer = [Diagnostics.Stopwatch]::StartNew()
    $prevEap=$ErrorActionPreference; $ErrorActionPreference='Continue'
    $Output = (& $Command @Arguments 2>&1 | Out-String)
    $ErrorActionPreference=$prevEap
    $ExitCode = $LASTEXITCODE
    $Timer.Stop()
    $Elapsed = $Timer.Elapsed.TotalSeconds
    if ($ExitCode -ne 0) {
        throw ("{0} failed with exit code {1} after {2:N1}s.`n{3}" -f $Label, $ExitCode, $Elapsed, $Output.Trim())
    }
    Write-Host ("  OK  {0} ({1:N1}s)" -f $Label, $Elapsed) -ForegroundColor Green
}

function Find-Python {
    $Candidates = New-Object System.Collections.Generic.List[object]
    $Seen = @{}

    function Add-Candidate {
        param([string]$Executable, [object[]]$Arguments = @(), [string]$Source = '')
        if (-not $Executable) { return }
        $Key = $Executable.ToLowerInvariant() + '|' + ($Arguments -join ' ')
        if (-not $Seen.ContainsKey($Key)) {
            $Seen[$Key] = $true
            $Candidates.Add([pscustomobject]@{Exe=$Executable;Args=@($Arguments);Source=$Source})
        }
    }

    Add-Candidate -Executable (Join-Path $Root '.venv\Scripts\python.exe') -Source 'existing-forge-venv'
    Add-Candidate -Executable $env:SKYRIM_FORGE_PYTHON -Source 'SKYRIM_FORGE_PYTHON'
    foreach ($Name in @('py', 'python', 'python3')) {
        $Command = Get-Command $Name -ErrorAction SilentlyContinue
        if ($Command) {
            $Arguments = if ($Name -eq 'py') { @('-3') } else { @() }
            Add-Candidate -Executable $Command.Source -Arguments $Arguments -Source "PATH:$Name"
        }
    }

    foreach ($RegistryRoot in @(
        'HKCU:\SOFTWARE\Python\PythonCore',
        'HKLM:\SOFTWARE\Python\PythonCore',
        'HKLM:\SOFTWARE\WOW6432Node\Python\PythonCore'
    )) {
        if (-not (Test-Path -LiteralPath $RegistryRoot)) { continue }
        foreach ($VersionKey in @(Get-ChildItem -LiteralPath $RegistryRoot -ErrorAction SilentlyContinue)) {
            $InstallKey = Join-Path $VersionKey.PSPath 'InstallPath'
            if (-not (Test-Path -LiteralPath $InstallKey)) { continue }
            $Properties = Get-ItemProperty -LiteralPath $InstallKey -ErrorAction SilentlyContinue
            $ExecutableProperty = if ($Properties) { $Properties.PSObject.Properties['ExecutablePath'] } else { $null }
            if ($ExecutableProperty -and $ExecutableProperty.Value) {
                Add-Candidate -Executable $ExecutableProperty.Value -Source "registry:$($VersionKey.PSChildName)"
            }
            $DefaultPath = (Get-Item -LiteralPath $InstallKey).GetValue('')
            if ($DefaultPath) {
                Add-Candidate -Executable (Join-Path $DefaultPath 'python.exe') -Source "registry:$($VersionKey.PSChildName)"
            }
        }
    }

    $SearchRoots = @(
        (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs\Python'),
        ([Environment]::GetFolderPath('ProgramFiles')),
        ([Environment]::GetEnvironmentVariable('ProgramFiles(x86)'))
    ) | Where-Object { $_ }
    foreach ($SearchRoot in $SearchRoots) {
        if (-not (Test-Path -LiteralPath $SearchRoot)) { continue }
        foreach ($Directory in @(Get-ChildItem -LiteralPath $SearchRoot -Directory -Filter 'Python3*' -ErrorAction SilentlyContinue)) {
            Add-Candidate -Executable (Join-Path $Directory.FullName 'python.exe') -Source 'standard-location'
        }
    }

    foreach ($Candidate in $Candidates) {
        try {
            if ([IO.Path]::IsPathRooted($Candidate.Exe) -and -not (Test-Path -LiteralPath $Candidate.Exe -PathType Leaf)) { continue }
            $Value = & $Candidate.Exe @($Candidate.Args) -c "import sys; print(sys.version_info.major, sys.version_info.minor)"
            if ($LASTEXITCODE -eq 0) {
                $Parts = $Value.Trim() -split '\s+'
                if ([int]$Parts[0] -gt 3 -or ([int]$Parts[0] -eq 3 -and [int]$Parts[1] -ge 11)) {
                    return $Candidate
                }
            }
        } catch {}
    }
    return $null
}

function Install-PinnedPython {
    $Architecture = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {
        'arm64'
    } elseif ([Environment]::Is64BitOperatingSystem) {
        'amd64'
    } else {
        'win32'
    }
    $Package = switch ($Architecture) {
        'amd64' {
            [pscustomobject]@{
                File='python-3.13.14-amd64.exe'
                Sha256='C54D9B9BBB8A36E6489363DDD01139707FD781D72F1F9E90C7EC65D0061368E0'
            }
        }
        'arm64' {
            [pscustomobject]@{
                File='python-3.13.14-arm64.exe'
                Sha256='3090F98038F332CEECA0BA40D77B7A4D94A4A25B7107E6CF341547E91D983F18'
            }
        }
        default {
            [pscustomobject]@{
                File='python-3.13.14.exe'
                Sha256='012F050539353E6521AC7976A6B63E232102977E1DFCC747CA7FB743357AE8D1'
            }
        }
    }
    $Uri = "https://www.python.org/ftp/python/3.13.14/$($Package.File)"
    $Installer = Join-Path ([IO.Path]::GetTempPath()) ("skyrim-forge-" + [Guid]::NewGuid().ToString('N') + '.exe')
    Write-Host "Downloading pinned Python 3.13.14 from python.org..." -ForegroundColor Cyan
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $Installer
        $ActualHash = (Get-FileHash -LiteralPath $Installer -Algorithm SHA256).Hash
        if ($ActualHash -cne $Package.Sha256) {
            throw "Python installer hash mismatch. Expected $($Package.Sha256); got $ActualHash."
        }
        $Signature = Get-AuthenticodeSignature -LiteralPath $Installer
        if ($Signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
            throw "Python installer signature is not valid: $($Signature.Status)."
        }
        if (-not $Signature.SignerCertificate -or $Signature.SignerCertificate.Subject -notmatch 'Python Software Foundation') {
            throw 'Python installer signature is not owned by the Python Software Foundation.'
        }
        $Process = Start-Process -FilePath $Installer -ArgumentList @(
            '/quiet',
            'InstallAllUsers=0',
            'PrependPath=0',
            'Include_launcher=0',
            'Include_test=0',
            'Include_pip=1',
            'SimpleInstall=1'
        ) -Wait -PassThru
        if ($Process.ExitCode -ne 0) { throw "Python installer failed with exit code $($Process.ExitCode)." }
    } finally {
        Remove-Item -LiteralPath $Installer -Force -ErrorAction SilentlyContinue
    }
}

$Python = Find-Python
if (-not $Python) {
    if (-not $BootstrapPython) {
        throw 'Python 3.11 or newer was not found. Run START-HERE.bat or rerun Install-or-Update.ps1 with -BootstrapPython.'
    }
    Install-PinnedPython
    $Python = Find-Python
    if (-not $Python) { throw 'Python 3.13.14 installed, but Forge could not discover the interpreter.' }
}

$env:SKYRIM_FORGE_BOOTSTRAP_ROOT = $Root
$ExpectedVersion = (& $Python.Exe @($Python.Args) -c "import os,sys; sys.path.insert(0, os.environ['SKYRIM_FORGE_BOOTSTRAP_ROOT']); from skyrim_forge.version import VERSION; print(VERSION)").Trim()
if (-not $ExpectedVersion) { throw 'Could not read the bundled Forge version.' }

$MyDocuments = [Environment]::GetFolderPath('MyDocuments')
if ($MyDocuments) {
    $DocumentsPrefix = $MyDocuments.TrimEnd('\') + '\'
    if ($Root.StartsWith($DocumentsPrefix, [StringComparison]::OrdinalIgnoreCase) -or ($Root.TrimEnd('\') -eq $MyDocuments.TrimEnd('\'))) {
        Write-Warning ('Forge is installing from Documents ({0}). The live product belongs in your Skyrim tools folder as Skyrim-Forge-{1}. Do not keep a second copy in Documents; MCP must point at the tools-folder venv.' -f $Root, $ExpectedVersion)
    }
}

$EnvironmentRegistered = $true
try {
    [Environment]::SetEnvironmentVariable('SKYRIM_FORGE_ROOT', $Root, 'User')
} catch {
    $EnvironmentRegistered = $false
    Write-Warning "Could not register SKYRIM_FORGE_ROOT for future processes: $($_.Exception.Message)"
}
$env:SKYRIM_FORGE_ROOT = $Root
$Native = Join-Path $Root 'writer\published\win-x64\SkyrimForge.Native.exe'
if (-not (Test-Path -LiteralPath $Native -PathType Leaf)) { throw "Bundled native helper is missing: $Native" }
$ExpectedNative = "SkyrimForge.Native $ExpectedVersion go"
$ActualNative = (& $Native version | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $ActualNative -cne $ExpectedNative) { throw "Native helper version check failed. Expected '$ExpectedNative'; got '$ActualNative'." }
Invoke-Checked 'Native helper self-test' $Native @('self-test')

$Venv = Join-Path $Root '.venv'
$VenvPython = Join-Path $Venv 'Scripts\python.exe'
$VenvHealthy = $false
if (Test-Path -LiteralPath $VenvPython -PathType Leaf) {
    try {
        & $VenvPython -c "import sys; raise SystemExit(0 if sys.version_info >= (3,11) else 1)" 2>$null
        $VenvHealthy = ($LASTEXITCODE -eq 0)
    } catch {
        $VenvHealthy = $false
    }
}
if (-not $VenvHealthy) {
    if (Test-Path -LiteralPath $Venv) {
        $ResolvedRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\')
        $ResolvedVenv = [IO.Path]::GetFullPath($Venv).TrimEnd('\')
        if ([IO.Path]::GetDirectoryName($ResolvedVenv) -cne $ResolvedRoot) {
            throw "Refusing to repair a virtual environment outside Forge root: $ResolvedVenv"
        }
        $VenvItem = Get-Item -LiteralPath $Venv -Force
        if (($VenvItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing to repair a virtual environment through a reparse point: $ResolvedVenv"
        }
        Write-Warning "Existing Forge virtual environment is unusable; rebuilding $ResolvedVenv."
        Remove-Item -LiteralPath $ResolvedVenv -Recurse -Force
    }
    Invoke-Checked 'Virtual environment creation' $Python.Exe (@($Python.Args) + @('-m','venv',$Venv))
}
& $VenvPython -c "import sys; raise SystemExit(0 if sys.version_info >= (3,11) else 1)"
if ($LASTEXITCODE -ne 0) { throw 'Forge virtual environment is not Python 3.11 or newer.' }
$SitePackages = (& $VenvPython -c "import sysconfig; print(sysconfig.get_paths()['purelib'])").Trim()
if (-not $SitePackages) { throw 'Could not resolve virtual-environment site-packages.' }
$Pth = Join-Path $SitePackages 'skyrim_forge_local.pth'
$Temp = "$Pth.stage-$([Guid]::NewGuid().ToString('N'))"
try {
    [IO.File]::WriteAllText($Temp, $Root + [Environment]::NewLine, $Utf8NoBom)
    Move-Item -LiteralPath $Temp -Destination $Pth -Force
} finally {
    Remove-Item -LiteralPath $Temp -Force -ErrorAction SilentlyContinue
}

Invoke-Checked 'Forge version check' $VenvPython @('-m','skyrim_forge','version')
Invoke-Checked 'Forge regression self-test' $VenvPython @('-m','skyrim_forge','self-test')
Invoke-Checked 'Forge configuration migration' $VenvPython @('-m','skyrim_forge','config-show')
$UiWorker = Join-Path $Root 'workers\SkyrimForge.UIWorker.ps1'
$PowerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (Test-Path -LiteralPath $UiWorker -PathType Leaf) {
    $UiWorkerHash = (Get-FileHash -LiteralPath $UiWorker -Algorithm SHA256).Hash
    if (Test-Path -LiteralPath $PowerShellExe -PathType Leaf) {
        Invoke-Checked 'Forge UI worker executable update' $VenvPython @('-m','skyrim_forge','config-set','tools.ui_worker.executable',$PowerShellExe)
    }
    Invoke-Checked 'Forge UI worker path update' $VenvPython @('-m','skyrim_forge','config-set','tools.ui_worker.worker',$UiWorker)
    Invoke-Checked 'Forge UI worker hash update' $VenvPython @('-m','skyrim_forge','config-set','tools.ui_worker.worker_sha256',$UiWorkerHash)
    Invoke-Checked 'Forge UI worker version update' $VenvPython @('-m','skyrim_forge','config-set','tools.ui_worker.version',$ExpectedVersion)
}
Invoke-Checked 'Forge doctor' $VenvPython @('-m','skyrim_forge','doctor')

$Descriptor = [ordered]@{
    product = 'Skyrim Forge'
    version = $ExpectedVersion
    root = $Root
    python = $VenvPython
    cli = @($VenvPython, '-m', 'skyrim_forge')
    mcp = @($VenvPython, '-m', 'skyrim_forge', 'mcp')
    environment_registered = $EnvironmentRegistered
}
[IO.File]::WriteAllText(
    (Join-Path $Root 'INSTALLATION.json'),
    ($Descriptor | ConvertTo-Json -Depth 5) + [Environment]::NewLine,
    $Utf8NoBom
)

Write-Host ''
Write-Host "Skyrim Forge $ExpectedVersion installed." -ForegroundColor Green
Write-Host "Python source: $($Python.Source)"
Write-Host "Shared runtime: $VenvPython"
Write-Host "Config: $HOME\.skyrim-forge\config.toml"
Write-Host 'External tools and UI Automation remain disabled until explicitly configured.'
