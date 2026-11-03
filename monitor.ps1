# Live monitor: run in a second terminal. Shows each adb command with its timestamp,
# and the logcat lines captured only while that command was running.
. "$PSScriptRoot\common.ps1"
if (-not (Test-Path $CmdLog)) { New-Item -ItemType File $CmdLog | Out-Null }
Write-Host "Monitoring $CmdLog  (Ctrl+C to exit)" -ForegroundColor Green
Get-Content $CmdLog -Tail 0 -Wait | ForEach-Object {
    $c = if ($_ -match '^\[') { 'Cyan' } elseif ($_ -match 'logcat\|') { 'DarkYellow' } elseif ($_ -match 'exit \d') { 'Red' } else { 'Gray' }
    Write-Host $_ -ForegroundColor $c
}
