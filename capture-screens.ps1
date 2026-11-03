# Captures reference screens from the TV over adb (Etapa 1 of story yt-redesign).
# Per screen: screencap (PNG) + uiautomator dump (XML); optionally a screenrecord of the transition.
# Reexecutable: any screen can be recaptured by name, overwriting the previous capture.
#
# Reference (oficial):   .\capture-screens.ps1 -Name 01-home  -Out refs\yt-official
# With a transition:     .\capture-screens.ps1 -Name 03-busca -Out refs\yt-official -Record 15
# "After" of the fork:   .\capture-screens.ps1 -Package app.smarttube.fdroid -Out refs\smarttube-after
#                        (launches/foregrounds the package first; -Name defaults to a timestamp)
#
# Address: -Address, else device.txt (port 5555 added if missing).
param(
    [string]$Name,
    [Parameter(Mandatory)][string]$Out,
    [string]$Package,
    [string]$Address,
    [int]$Record = 0,
    [int]$Wait = 6,
    [switch]$NoDump,
    [switch]$NoPng
)
$ErrorActionPreference = 'Continue'   # adb writes progress to stderr; don't let it be terminating

$Adb = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\Google.PlatformTools_Microsoft.Winget.Source_8wekyb3d8bbwe\platform-tools\adb.exe'
if (-not (Test-Path $Adb)) { $Adb = 'adb' }

$DeviceFile = Join-Path $PSScriptRoot 'device.txt'
if (-not $Address) { $Address = if (Test-Path $DeviceFile) { (Get-Content $DeviceFile -Raw).Trim() } else { $null } }
if (-not $Address) { throw 'No address: pass -Address or create device.txt with the TV address.' }
if ($Address -notmatch ':') { $Address = "${Address}:5555" }

function Get-State { (& $Adb -s $Address get-state 2>&1 | Out-String).Trim() }
$state = Get-State
if ($state -ne 'device') {
    & $Adb connect $Address | Out-Null
    Start-Sleep 2
    $state = Get-State
}
if ($state -ne 'device') { throw "TV not connected (state '$state'). Run .\connect.ps1 $Address first." }

if (-not $Name) { $Name = Get-Date -Format 'yyyyMMdd-HHmmss' }

$dir = if ([System.IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path $PSScriptRoot $Out }
New-Item -ItemType Directory -Force $dir | Out-Null

# Optionally bring the app to the foreground before capturing (e.g. app.smarttube.fdroid for the "after").
if ($Package) {
    & $Adb -s $Address shell monkey -p $Package -c android.intent.category.LEANBACK_LAUNCHER 1 2>&1 | Out-Null
    Start-Sleep $Wait
}

$focus  = (& $Adb -s $Address shell 'dumpsys window | grep -i mCurrentFocus' 2>$null | Out-String).Trim() -replace '.*mCurrentFocus=', ''
$size   = (& $Adb -s $Address shell wm size 2>$null | Out-String).Trim() -replace '\s+', ' '
$density = (& $Adb -s $Address shell wm density 2>$null | Out-String).Trim() -replace '\s+', ' '

if (-not $NoPng) {
    $png = Join-Path $dir "$Name.png"
    # cmd handles the binary redirect; PowerShell's '>' would mangle it.
    cmd /c "`"$Adb`" -s $Address exec-out screencap -p > `"$png`""
}
if (-not $NoDump) {
    & $Adb -s $Address shell uiautomator dump /sdcard/uidump.xml 2>&1 | Out-Null
    & $Adb -s $Address pull /sdcard/uidump.xml (Join-Path $dir "$Name.xml") 2>&1 | Out-Null
}
if ($Record -gt 0) {
    # NB: on this TCL/Amlogic TV screenrecord captures very few frames for UI (see 01-captures.md).
    & $Adb -s $Address shell screenrecord --time-limit $Record --size 1920x1080 --bit-rate 8000000 /sdcard/rec.mp4 2>&1 | Out-Null
    & $Adb -s $Address pull /sdcard/rec.mp4 (Join-Path $dir "$Name.mp4") 2>&1 | Out-Null
}

$pngSize = if (Test-Path (Join-Path $dir "$Name.png")) { (Get-Item (Join-Path $dir "$Name.png")).Length } else { 0 }
$line = "{0,-14} | pkg {1} | {2} | {3} | {4} | png {5} B" -f $Name, $(if ($Package) { $Package } else { '-' }), $focus, $size, $density, $pngSize
Add-Content (Join-Path $dir 'manifest.txt') $line
Write-Host $line
