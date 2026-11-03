# Reads the TV screen (uiautomator) and prints visible texts; ">>" marks the focused/selected row.
#   .\ui.ps1            -> list rows
#   .\ui.ps1 -Raw       -> also save the raw xml to logs\ui.xml
param([switch]$Raw)
. "$PSScriptRoot\common.ps1"
$s = Get-Screen
if ($Raw) { $s.Xml | Set-Content (Join-Path $LogDir 'ui.xml') -Encoding utf8 }
Write-Host $s.Focus -ForegroundColor DarkGray
try { [xml]$x = $s.Xml } catch { Write-Host 'no ui dump (canvas app?)' -ForegroundColor Yellow; return }
# Walk clickable/focusable containers; show their texts joined, flag focused ones.
$nodes = $x.SelectNodes('//node[@focusable="true" or @clickable="true"]')
foreach ($n in $nodes) {
    $texts = @($n.SelectNodes('.//node[@text!=""]') | ForEach-Object text)
    if ($n.text) { $texts = @($n.text) + $texts }
    $t = ($texts | Select-Object -Unique) -join ' | '
    if (-not $t) { continue }
    $mark = if ($n.focused -eq 'true' -or $n.selected -eq 'true') { '>>' } else { '  ' }
    "$mark $t"
}
