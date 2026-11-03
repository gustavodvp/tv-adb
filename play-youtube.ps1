# Opens SmartTube (YouTube without ads) on the TV and plays a video, with visible key presses.
#   .\play-youtube.ps1 "https://youtu.be/dQw4w9WgXcQ"     (link or ID -> opens that exact video)
#   .\play-youtube.ps1 "lofi hip hop radio"                (title -> searches and plays the first result)
param([Parameter(Mandatory)][string]$Video)
. "$PSScriptRoot\common.ps1"
$YT = 'app.smarttube.fdroid'   # Gustavo's restyled SmartTube fork (tv-adb/smarttube-src), 2026-10-19

function Wait-Screen([string]$Why) {
    $s = Get-Screen
    Write-Log "    screen [$Why]: $($s.Focus)" 'DarkGray'
    return $s
}
# YouTube TV draws on a canvas (uiautomator has no text), so the profile picker is recognised
# from a screenshot: only that screen has the red YouTube logo centred at the top.
Add-Type -AssemblyName System.Drawing
function Test-ProfilePicker {
    $p = Join-Path $LogDir 'yt-check.png'
    cmd /c "`"$Adb`" -s $Serial exec-out screencap -p > `"$p`""
    if ((Get-Item $p).Length -lt 1000) { return $false }   # DRM -> blank capture -> a video is on screen
    $bmp = [System.Drawing.Bitmap]::FromFile($p)
    try {
        $sx = $bmp.Width / 1920; $sy = $bmp.Height / 1080; $red = 0; $n = 0
        for ($x = 866; $x -le 920; $x += 6) { for ($y = 150; $y -le 186; $y += 6) {
            $c = $bmp.GetPixel([int]($x * $sx), [int]($y * $sy)); $n++
            if ($c.R -gt 200 -and $c.G -lt 60 -and $c.B -lt 60) { $red++ } } }
        $dark = $bmp.GetPixel([int](200 * $sx), [int](540 * $sy)).GetBrightness() -lt 0.15
        return ($red / $n -gt 0.4 -and $dark)
    } finally { $bmp.Dispose() }
}
# "Who's watching?": confirm the highlighted profile with OK. Never types a password or adds an account.
function Handle-Profile {
    for ($i = 0; $i -lt 3; $i++) {
        Wait-Screen 'profile check' | Out-Null
        if (Test-ProfilePicker) {
            Write-Log "    'Who's watching?' detected -> OK on the highlighted profile" 'Yellow'
            Press DPAD_CENTER 4
        } else { return }
    }
    throw "Still on the profile screen. Pick the profile on the TV, then run again."
}

$id = if ($Video -match '(?:v=|youtu\.be/|shorts/|embed/)([\w-]{11})') { $Matches[1] }
      elseif ($Video -match '^[\w-]{11}$') { $Video } else { $null }

Write-Log "== play-youtube: $Video ==" 'Green'
Press HOME 2
Invoke-Adb shell monkey -p $YT -c android.intent.category.LEANBACK_LAUNCHER 1 | Out-Null
Start-Sleep 5
Handle-Profile

if ($id) {
    Invoke-Adb shell am start -a android.intent.action.VIEW -d "https://www.youtube.com/watch?v=$id" $YT | Out-Null
    Start-Sleep 5
    Handle-Profile
} else {
    Press SEARCH 2                                   # opens YouTube's search screen
    $s = Wait-Screen 'search'
    $q = $Video -replace '[^\p{L}\p{N} ]', '' -replace ' ', '%s'
    Invoke-Adb shell input text "$q" | Out-Null      # typed into the on-screen search box
    Start-Sleep 2
    Press ENTER 4                                    # submit the search
    Press DPAD_DOWN 1.5                              # move focus to the first result
    $s = Wait-Screen 'before OK on first result'
    Press ENTER 5
    Handle-Profile
}

for ($i = 0; $i -lt 6; $i++) {
    if (Test-Playing) { Write-Log 'PLAYING (media_session state=3). Screenshots of the video stay black because of DRM.' 'Green'; return }
    if ($i -eq 2) { Press MEDIA_PLAY 2 } else { Start-Sleep 2 }
}
Write-Log 'Could not confirm playback through media_session. Check the TV.' 'Yellow'
