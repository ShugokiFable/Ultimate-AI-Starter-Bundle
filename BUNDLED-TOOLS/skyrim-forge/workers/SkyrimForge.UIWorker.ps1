[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][Alias('job')][string]$JobPath,
    [Parameter(Mandatory=$true)][Alias('result')][string]$ResultPath
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

function Find-Window([string]$Pattern, [int]$ProcessId, [int]$TimeoutSeconds) {
    $Deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $Children = [System.Windows.Automation.AutomationElement]::RootElement.FindAll(
            [System.Windows.Automation.TreeScope]::Children,
            [System.Windows.Automation.Condition]::TrueCondition
        )
        foreach ($Element in $Children) {
            try {
                $PidMatches = $ProcessId -eq 0 -or $Element.Current.ProcessId -eq $ProcessId
                $NameMatches = $Element.Current.Name -like $Pattern
                if ($PidMatches -and $NameMatches) { return $Element }
            } catch {}
        }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $Deadline)
    throw "Window not found within timeout: $Pattern"
}

function Find-Control($Window, $Step) {
    $Conditions = New-Object System.Collections.Generic.List[System.Windows.Automation.Condition]
    if ($Step.automation_id) {
        $Conditions.Add((New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::AutomationIdProperty,
            [string]$Step.automation_id
        )))
    }
    if ($Step.name) {
        $Conditions.Add((New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::NameProperty,
            [string]$Step.name
        )))
    }
    if ($Conditions.Count -eq 0) { throw 'Control selector requires automation_id or name.' }
    $Condition = if ($Conditions.Count -eq 1) { $Conditions[0] } else { New-Object System.Windows.Automation.AndCondition($Conditions.ToArray()) }
    $Control = $Window.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $Condition)
    if ($null -eq $Control) { throw "Control not found: automation_id=$($Step.automation_id) name=$($Step.name)" }
    return $Control
}

# ReadAllText honours UTF-8 where Get-Content -Raw would use the ANSI codepage.
# Convert-Path first: $JobPath is caller-supplied and .NET resolves relative
# paths against the process CWD rather than PowerShell's current location.
$Job = [IO.File]::ReadAllText((Convert-Path -LiteralPath $JobPath)) | ConvertFrom-Json
if ($Job.schema -ne 'skyrim-forge-ui/1') { throw 'Unsupported UI job schema.' }
$ProcessName = [IO.Path]::GetFileNameWithoutExtension([string]$Job.expected_process)
$Process = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $Process) { throw "Expected process is not running: $($Job.expected_process)" }
$Events = @()
$CurrentWindow = $null
foreach ($Step in $Job.steps) {
    $Timeout = if ($Step.timeout_seconds) { [int]$Step.timeout_seconds } else { 30 }
    if ($Step.action -ne 'screenshot') {
        $CurrentWindow = Find-Window ([string]$Step.window_title) $Process.Id $Timeout
    }
    switch ([string]$Step.action) {
        'wait_window' {
            $Events += @{ action='wait_window'; window=$CurrentWindow.Current.Name; status='success' }
        }
        'invoke' {
            $Control = Find-Control $CurrentWindow $Step
            $Pattern = $Control.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
            $Pattern.Invoke()
            $Events += @{ action='invoke'; control=$Control.Current.Name; status='success' }
        }
        'select' {
            $Control = Find-Control $CurrentWindow $Step
            $Pattern = $Control.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
            $Pattern.Select()
            $Events += @{ action='select'; control=$Control.Current.Name; status='success' }
        }
        'set_value' {
            $Control = Find-Control $CurrentWindow $Step
            $Pattern = $Control.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
            $Pattern.SetValue([string]$Step.value)
            $Events += @{ action='set_value'; control=$Control.Current.Name; status='success' }
        }
        'read_text' {
            $Control = Find-Control $CurrentWindow $Step
            $Pattern = $Control.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
            $Value = $Pattern.Current.Value
            if ($Step.expected -and $Value -ne [string]$Step.expected) { throw "Unexpected value: $Value" }
            $Events += @{ action='read_text'; control=$Control.Current.Name; value=$Value; status='success' }
        }
        'screenshot' {
            if ($null -eq $CurrentWindow) { $CurrentWindow = Find-Window '*' $Process.Id 30 }
            $Rect = $CurrentWindow.Current.BoundingRectangle
            if ($Rect.Width -le 0 -or $Rect.Height -le 0) { throw 'Window has no visible screenshot bounds.' }
            $ImagePath = Join-Path ([IO.Path]::GetDirectoryName($ResultPath)) ("ui-$([Guid]::NewGuid().ToString('N')).png")
            $Bitmap = New-Object System.Drawing.Bitmap([int]$Rect.Width, [int]$Rect.Height)
            $Graphics = [System.Drawing.Graphics]::FromImage($Bitmap)
            try {
                $Graphics.CopyFromScreen([int]$Rect.Left, [int]$Rect.Top, 0, 0, $Bitmap.Size)
                $Bitmap.Save($ImagePath, [System.Drawing.Imaging.ImageFormat]::Png)
            } finally { $Graphics.Dispose(); $Bitmap.Dispose() }
            $Events += @{ action='screenshot'; path=$ImagePath; status='success' }
        }
        'close_window' {
            $Pattern = $CurrentWindow.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern)
            $Pattern.Close()
            $Events += @{ action='close_window'; window=$CurrentWindow.Current.Name; status='success' }
        }
        default { throw "Unsupported UI action: $($Step.action)" }
    }
}
$Result = @{ job_id=$Job.job_id; status='success'; process_id=$Process.Id; events=$Events }
$Parent = [IO.Path]::GetDirectoryName($ResultPath)
[IO.Directory]::CreateDirectory($Parent) | Out-Null
$Temp = "$ResultPath.tmp"
$Result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Temp -Encoding UTF8
Move-Item -LiteralPath $Temp -Destination $ResultPath -Force
