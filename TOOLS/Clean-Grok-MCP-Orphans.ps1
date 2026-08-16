# Clean-Grok-MCP-Orphans.ps1
# Kills orphaned MCP server processes left behind by closed Grok sessions.
#
# Windows does NOT kill child processes when their parent dies. Closing a Grok
# shell (especially after a softlock) leaves its MCP server fleet running, and
# the next session's fleet collides with them: housecarl waits on its own MO2
# lock, codebase-memory on its cohort slot -> tools/list hangs -> softlock.
#
# SAFETY:
#   - Refuses to run while any grok.exe / agent.exe is alive (never kill servers
#     under a live session).
#   - Keeps the codebase-memory daemon (the process listening on the UI port).
#   - Only targets known MCP server fingerprints.
[CmdletBinding()]
param(
    [int]$UiPort = 9749
)
$ErrorActionPreference = 'SilentlyContinue'

$grokRunning = Get-Process -Name grok, agent -ErrorAction SilentlyContinue
if ($grokRunning) {
    Write-Output "ABORT: a grok process is running. Close Grok first."
    exit 1
}

# Keep the daemon that owns the UI port (it re-claims itself otherwise).
$daemonPid = (Get-NetTCPConnection -LocalPort $UiPort -State Listen -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty OwningProcess)

$killed = @()
$procs = Get-CimInstance Win32_Process | Where-Object {
    $_.Name -eq 'housecarl-mcp.exe' -or
    $_.Name -eq 'codebase-memory-mcp.exe' -or
    ($_.Name -eq 'python.exe' -and $_.CommandLine -match 'headroom|skyrim_forge') -or
    ($_.Name -eq 'node.exe' -and $_.CommandLine -match '_npx')
}
foreach ($p in $procs) {
    if ($p.ProcessId -eq $daemonPid) { continue }
    Stop-Process -Id $p.ProcessId -Force
    $killed += $p.ProcessId
}
if ($killed.Count -eq 0) {
    Write-Output "No orphaned MCP servers found. (daemon kept: $daemonPid)"
} else {
    Write-Output "Killed $($killed.Count) orphaned MCP server process(es): $($killed -join ', ')"
    Write-Output "Daemon on port $UiPort kept (PID $daemonPid)."
}
Write-Output "Start Grok fresh; all servers will respawn cleanly."
