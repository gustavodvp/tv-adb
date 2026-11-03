# check-resolutions.ps1 — switch and capture screen resolution over adb (wm size / wm density).
# Story yt-redesign, Etapa 3 (QA): "720p e 4K em emulador (wm size/wm density)".
# Serves BOTH an Android TV emulator (AVD) and the real TV (TCL) — the wm commands are the same.
# Runbook / how to bring up the emulator: .harness/runs/yt-redesign/01-resolutions.md
#
#   .\check-resolutions.ps1 -Query                       # print current wm size/density only
#   .\check-resolutions.ps1 -Preset 720p -Out refs\res -Name 720p
#   .\check-resolutions.ps1 -All -Out refs\res           # 720p -> 1080p -> 4k, then reset
#   .\check-resolutions.ps1 -All -Out refs\res -Package app.smarttube.fdroid
#   .\check-resolutions.ps1 -Size 1280x720 -Density 213 -Out refs\res
#   .\check-resolutions.ps1 -Reset                       # clear size and density overrides
#
# Address: -Address, else device.txt (port 5555 added for TCP addresses; 'emulator-5554' left as is).
param(
    [string]$Address,
    [string]$Out,
    [string]$Name,
    [ValidateSet('native','720p','1080p','4k')][string]$Preset,
    [string]$Size,                       # free-form override (e.g. 1280x720) or 'reset'
    [string]$Density,                    # free-form override (e.g. 213) or 'reset'
    [switch]$Query,
    [switch]$Reset,
    [switch]$All,
    [string]$Package,
    [int]$Wait = 5,
    [switch]$NoPng
)
$ErrorActionPreference = 'Continue'   # adb writes progress to stderr; don't let it be terminating

$Adb = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\Google.PlatformTools_Microsoft.Winget.Source_8wekyb3d8bbwe\platform-tools\adb.exe'
if (-not (Test-Path $Adb)) { $Adb = 'adb' }

$DeviceFile = Join-Path $PSScriptRoot 'device.txt'
if (-not $Address) { $Address = if (Test-Path $DeviceFile) { (Get-Content $DeviceFile -Raw).Trim() } else { $null } }
if (-not $Address) { throw 'No address: pass -Address or create device.txt with the TV/emulator address.' }
# 'emulator-5554' is a local serial, not a TCP host: don't append a port to it.
$isTcp = $Address -match ':'
if (-not $isTcp) { $isTcp = $Address -match '^\d{1,3}(\.\d{1,3}){3}$' }
if ($isTcp -and $Address -notmatch ':') { $Address = "${Address}:5555" }

function Get-State { (& $Adb -s $Address get-state 2>$null | Out-String).Trim() }
$state = Get-State
if ($state -ne 'device' -and $isTcp) {
    & $Adb connect $Address | Out-Null
    Start-Sleep 2
    $state = Get-State
}
if ($state -ne 'device') { throw "Device not connected (state '$state'). Run .\connect.ps1 $Address first." }

# Presets keep the same logical dp width as the 1080p reference: 320 @ 1920x1080 = 960dp.
# Scaling the density with the size (720/1080 and 2x) changes only the pixel grid, so the
# layout should stay identical and "nothing clipped or overlapping" is a fair test.
$Presets = @{
    'native' = @{ Size = $null;       Density = $null; Note = 'physical panel (no override)' }
    '720p'   = @{ Size = '1280x720';  Density = '213'; Note = 'HD 720p' }
    '1080p'  = @{ Size = '1920x1080'; Density = '320'; Note = 'Full HD 1080p (reference baseline)' }
    '4k'     = @{ Size = '3840x2160'; Density = '640'; Note = 'Ultra HD 4K' }
}

function Get-Wm([string]$prop) { (& $Adb -s $Address shell wm $prop 2>&1 | Out-String).Trim() -replace '\s+', ' ' }

function Show-Current([string]$Tag) {
    $model = (& $Adb -s $Address shell getprop ro.product.model 2>&1 | Out-String).Trim()
    $chars = (& $Adb -s $Address shell getprop ro.build.characteristics 2>&1 | Out-String).Trim()
    $qemu  = (& $Adb -s $Address shell getprop ro.kernel.qemu 2>&1 | Out-String).Trim()
    $kind  = if ($qemu -eq '1') { 'emulator' } else { 'device' }
    $line  = "{0,-6} | {1} | {2} | {3} | {4} | {5}" -f $Tag, $kind, $model, $chars, (Get-Wm 'size'), (Get-Wm 'density')
    Write-Host $line
    return $line
}

function Apply([hashtable]$P) {
    if ($P.Size)    { & $Adb -s $Address shell wm size $P.Size 2>&1 | Out-Null }    else { & $Adb -s $Address shell wm size reset 2>&1 | Out-Null }
    if ($P.Density) { & $Adb -s $Address shell wm density $P.Density 2>&1 | Out-Null } else { & $Adb -s $Address shell wm density reset 2>&1 | Out-Null }
    Start-Sleep $Wait
}

if ($Query) { Show-Current 'now'; return }

$dir = if ($Out) { if ([System.IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path $PSScriptRoot $Out } } else { $null }
if ($dir) { New-Item -ItemType Directory -Force $dir | Out-Null }

# Build the queue of (Tag, hashtable) to apply and capture.
$queue = @()
if ($Reset) {
    $queue += @{ Tag = 'reset'; Size = $null; Density = $null }
} elseif ($Size -or $Density) {
    $queue += @{ Tag = $(if ($Name) { $Name } else { 'custom' }); Size = $Size; Density = $Density }
} elseif ($All) {
    foreach ($p in '720p','1080p','4k') { $queue += @{ Tag = $p; Size = $Presets[$p].Size; Density = $Presets[$p].Density } }
} elseif ($Preset) {
    $queue += @{ Tag = $Preset; Size = $Presets[$Preset].Size; Density = $Presets[$Preset].Density }
} else {
    Show-Current 'now'
    Write-Host 'Nothing to do: pass -Preset <native|720p|1080p|4k>, -All, -Size/-Density, -Reset or -Query.'
    return
}

# Optionally bring the app to the foreground once, before the resolution walk.
if ($Package) {
    & $Adb -s $Address shell monkey -p $Package -c android.intent.category.LEANBACK_LAUNCHER 1 2>&1 | Out-Null
    Start-Sleep $Wait
}

foreach ($item in $queue) {
    Apply $item
    if (-not $Name -or $queue.Count -gt 1) { $tag = $item.Tag } else { $tag = $Name }
    $line = Show-Current $tag
    if ($dir) {
        if (-not $NoPng) {
            $png = Join-Path $dir "$tag.png"
            # cmd handles the binary redirect; PowerShell's '>' would mangle it.
            cmd /c "`"$Adb`" -s $Address exec-out screencap -p > `"$png`""
        }
        $pngSize = if (Test-Path (Join-Path $dir "$tag.png")) { (Get-Item (Join-Path $dir "$tag.png")).Length } else { 0 }
        Add-Content (Join-Path $dir 'manifest.txt') ("{0} | pkg {1} | png {2} B" -f $line, $(if ($Package) { $Package } else { '-' }), $pngSize)
    }
}

# -All leaves the device on 4k; put it back on the physical panel so the next run starts clean.
if ($All) { Apply @{ Size = $null; Density = $null }; Show-Current 'native' }
