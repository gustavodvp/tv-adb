# Passive stream probe: samples Moonlight's performance overlay and logcat, without pressing keys.
#   .\stream-probe.ps1 -Seconds 120   -> logs\probe-<time>.csv and logs\probe-<time>-logcat.txt
param([int]$Seconds = 120)
. "$PSScriptRoot\common.ps1"
$stamp = Get-Date -Format 'HHmmss'
$csv = Join-Path $LogDir "probe-$stamp.csv"
$lc  = Join-Path $LogDir "probe-$stamp-logcat.txt"
Adb-Raw logcat -c
$end = (Get-Date).AddSeconds($Seconds)
$rows = while ((Get-Date) -lt $end) {
    $s = Get-Screen
    $t = ''
    try { [xml]$x = $s.Xml; $t = ($x.SelectNodes('//node[@text!=""]') | ForEach-Object text) -join "`n" } catch {}
    $g = { param($re) [regex]::Match($t, $re).Groups[1].Value }
    [pscustomobject]@{
        t = (Get-Date -Format 'HH:mm:ss'); window = ($s.Focus -replace '.*/', '' -replace '\}', '')
        rx = & $g 'rede:: ([\d,]+) FPS'; render = & $g 'renderizando: ([\d,]+)'; drop = & $g 'dropados pela rede: ([\d,]+)%'
        net = & $g 'rede: (\d+) ms'; jitter = & $g 'varia..o: (\d+) ms'; host = & $g 'average: ([\d,/]+)'; dec = & $g 'decodifica..o: ([\d,]+)'
    }
}
$rows | Export-Csv $csv -NoTypeInformation -Encoding utf8
Adb-Raw logcat -d -v time | Select-String -Pattern '(?i)limelight|moonlight|MediaCodec|amlogic.*(drop|err)|wifi.*(roam|scan|disconnect)|WifiScan' | Set-Content $lc
$rows | Format-Table -AutoSize
Write-Host "csv: $csv`nlogcat: $lc"
