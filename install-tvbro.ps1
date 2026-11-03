# Installs TV Bro from its official GitHub release (github.com/truefedex/tv-bro).
param([switch]$Gecko)  # -Gecko = bundle Mozilla's engine (150-200 MB, ABI-specific); default uses the system WebView (~7 MB)
. "$PSScriptRoot\common.ps1"
$rel = Invoke-RestMethod https://api.github.com/repos/truefedex/tv-bro/releases/latest
if ($Gecko) {
    $abi = (Adb-Raw shell getprop ro.product.cpu.abi | Out-String).Trim()
    $asset = $rel.assets | Where-Object name -like "*geckoIncluded-$abi.apk" | Select-Object -First 1
} else {
    $asset = $rel.assets | Where-Object name -like '*geckoExcluded.apk' | Select-Object -First 1
}
if (-not $asset) { throw "No matching APK in release $($rel.tag_name)" }
$dl = Join-Path $Root "downloads\tvbro-$($rel.tag_name)"
New-Item -ItemType Directory -Force $dl | Out-Null
$apk = Join-Path $dl $asset.name
Write-Log "Downloading $($asset.browser_download_url)" 'Green'
Invoke-WebRequest $asset.browser_download_url -OutFile $apk
if ((Get-Item $apk).Length -ne $asset.size) { throw 'Size mismatch with GitHub asset' }
Write-Log "SHA256 $((Get-FileHash $apk).Hash)"

$before = Adb-Raw shell pm list packages -3
Invoke-Adb install -r $apk | Out-Null
$new = Compare-Object $before (Adb-Raw shell pm list packages -3) | Where-Object SideIndicator -eq '=>' | ForEach-Object { $_.InputObject -replace '^package:' }
$pkg = if ($new) { $new } else { 'com.phlox.tvwebbrowser' }
Write-Log "Installed: $pkg   (undo: adb uninstall $pkg)" 'Green'
$latest = Join-Path $Root 'backup\LATEST'
if ($new -and (Test-Path $latest)) { Add-Content (Join-Path (Get-Content $latest -Raw).Trim() 'undo.ps1') "Invoke-Adb uninstall $pkg" }
