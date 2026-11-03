# Shared helpers: every adb call goes through Invoke-Adb, which logs it with a timestamp
# and attaches the logcat produced only while that command was running.
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Adb  = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\Google.PlatformTools_Microsoft.Winget.Source_8wekyb3d8bbwe\platform-tools\adb.exe'
if (-not (Test-Path $Adb)) { $Adb = 'adb' }
$LogDir = Join-Path $Root 'logs'
New-Item -ItemType Directory -Force $LogDir | Out-Null
$CmdLog = Join-Path $LogDir 'commands.log'
$DeviceFile = Join-Path $Root 'device.txt'
$Serial = if (Test-Path $DeviceFile) { (Get-Content $DeviceFile -Raw).Trim() } else { $null }

function Write-Log([string]$Line, [string]$Color = 'Gray') {
    Write-Host $Line -ForegroundColor $Color
    Add-Content -Path $CmdLog -Value $Line -Encoding utf8
}

# Raw adb call without logging (used internally, e.g. for the logcat window).
function Adb-Raw { if ($Serial) { & $Adb -s $Serial @args } else { & $Adb @args } }

# Simple (non-advanced) functions on purpose: flags like -d/-s/-3 must reach adb untouched.
function Invoke-Adb      { Invoke-AdbCore $args $true }
function Invoke-AdbQuiet { Invoke-AdbCore $args $false }

function Invoke-AdbCore([object[]]$AdbArgs, [bool]$WithLogcat) {
    $ts = Get-Date -Format 'HH:mm:ss.fff'
    Write-Log "[$ts] adb $($AdbArgs -join ' ')" 'Cyan'
    $since = $null
    if ($WithLogcat -and $Serial) { $since = (Adb-Raw shell date '+%m-%d\ %H:%M:%S.000' 2>$null | Out-String).Trim() }
    $out = Adb-Raw @AdbArgs 2>&1 | Out-String
    $code = $LASTEXITCODE
    if ($out.Trim()) { Write-Log ($out.TrimEnd() -replace '(?m)^', '    ') }
    if ($since) {
        $lc = Adb-Raw logcat -d -v time -T "'$since'" '*:W' 2>$null | Select-Object -Last 15
        if ($lc) { Write-Log (($lc | ForEach-Object { "    logcat| $_" }) -join "`n") 'DarkYellow' }
    }
    if ($code -ne 0) { Write-Log "    (exit $code)" 'Red' }
    return $out
}

function Press([string]$Key, [double]$Pause = 1.0) {
    Invoke-AdbQuiet shell input keyevent "KEYCODE_$Key" | Out-Null
    Start-Sleep -Milliseconds ([int]($Pause * 1000))
}

# Screen text via uiautomator (works on most TV apps; Cobalt/YouTube may expose little).
function Get-Screen {
    Adb-Raw shell uiautomator dump /sdcard/ui.xml 2>$null | Out-Null
    $xml = Adb-Raw exec-out cat /sdcard/ui.xml 2>$null | Out-String
    $focus = Adb-Raw shell dumpsys window 2>$null | Select-String 'mCurrentFocus' | Select-Object -First 1
    [pscustomobject]@{ Xml = $xml; Focus = "$focus".Trim() }
}

# Texts inside the focused element (and its children).
function Get-FocusedText {
    $s = Get-Screen
    try { [xml]$x = $s.Xml } catch { return '' }
    $n = $x.SelectNodes('//node[@focused="true"]') | Select-Object -Last 1
    if (-not $n) { return '' }
    # ListView/RecyclerView keep focus on the list itself; the active row is the outermost "selected" child.
    $row = $n.SelectNodes('.//node[@selected="true"]') | Where-Object { $_.ParentNode.selected -ne 'true' } | Select-Object -First 1
    if ($row) { $n = $row }
    (@($n.text) + @($n.SelectNodes('.//node[@text!=""]') | ForEach-Object text) | Where-Object { $_ } | Select-Object -Unique) -join ' | '
}

# Presses $Key until the focused element matches $Pattern (regex). Checks the screen after every press.
function Focus-On([string]$Pattern, [string]$Key = 'DPAD_DOWN', [int]$Max = 15) {
    for ($i = 0; $i -le $Max; $i++) {
        $f = Get-FocusedText
        if ($f -match $Pattern) { Write-Log "    focus OK: $f" 'Green'; return $true }
        if ($i -lt $Max) { Press $Key 0.8 }
    }
    Write-Log "    could not focus /$Pattern/ (last: $f)" 'Red'
    return $false
}

# Android list dialogs (radio options) don't expose focus to uiautomator: the highlighted row is the
# one with the lightest background in a screenshot. Moves to $Want and presses ENTER only once it is highlighted.
Add-Type -AssemblyName System.Drawing
function Get-DialogState {
    [xml]$x = (Get-Screen).Xml
    $rows = @($x.SelectNodes('//node[@class="android.widget.CheckedTextView"]'))
    $p = Join-Path $LogDir 'dlg.png'
    cmd /c "`"$Adb`" -s $Serial exec-out screencap -p > `"$p`""
    $bmp = [System.Drawing.Bitmap]::FromFile($p)
    try {
        $items = foreach ($r in $rows) {
            $b = [regex]::Matches($r.bounds, '\d+') | ForEach-Object { [int]$_.Value }
            $px = $bmp.GetPixel([math]::Min($b[2] - 12, $bmp.Width - 1), [int](($b[1] + $b[3]) / 2))
            [pscustomobject]@{ Text = $r.text; Checked = ($r.checked -eq 'true'); Light = $px.GetBrightness() }
        }
    } finally { $bmp.Dispose() }
    $max = ($items | Measure-Object Light -Maximum).Maximum
    $min = ($items | Measure-Object Light -Minimum).Minimum
    foreach ($i in $items) { $i | Add-Member Highlighted (($max - $min) -gt 0.02 -and $i.Light -eq $max) }
    return $items
}
function Pick-Option([string]$Want) {
    for ($n = 0; $n -lt 10; $n++) {
        $items = Get-DialogState
        $names = @($items.Text)
        if ($names -notcontains $Want) { Write-Log "    option '$Want' not in: $($names -join ', ')" 'Red'; return $false }
        $h = $items | Where-Object Highlighted | Select-Object -First 1
        if ($h -and $h.Text -eq $Want) { Write-Log "    highlighted: $Want -> ENTER" 'Green'; Press ENTER 1.5; return $true }
        $key = if (-not $h -or [array]::IndexOf($names, $h.Text) -gt [array]::IndexOf($names, $Want)) { 'DPAD_UP' } else { 'DPAD_DOWN' }
        Press $key 0.5
    }
    return $false
}

function Test-Playing {
    $ms = Adb-Raw shell dumpsys media_session 2>$null | Out-String
    return $ms -match 'state=PlaybackState \{state=3'
}
