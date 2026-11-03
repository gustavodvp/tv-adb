# Applies the approved cleanup. Disables only (never uninstalls) and records the undo for each step.
param([string]$ListFile = "$PSScriptRoot\approved-packages.txt", [switch]$SkipSettings)
. "$PSScriptRoot\common.ps1"
$dir = (Get-Content (Join-Path $Root 'backup\LATEST') -Raw).Trim()
$undo = Join-Path $dir 'undo.ps1'

foreach ($pkg in Get-Content $ListFile | Where-Object { $_ -and $_ -notmatch '^\s*#' } | ForEach-Object { $_.Trim() }) {
    $r = Invoke-Adb shell pm disable-user --user 0 $pkg
    if ($r -match 'disabled-user') { Add-Content $undo "Invoke-Adb shell pm enable --user 0 $pkg" }
}

if (-not $SkipSettings) {
    foreach ($k in 'window_animation_scale','transition_animation_scale','animator_duration_scale') {
        Invoke-Adb shell settings put global $k 0.5 | Out-Null
    }
    Invoke-Adb shell settings put global private_dns_mode hostname | Out-Null
    Invoke-Adb shell settings put global private_dns_specifier dns.adguard-dns.com | Out-Null
}
Write-Log "Done. Undo script: $undo" 'Green'
