# Connects to the TV.  .\connect.ps1 192.168.0.50   (or 192.168.0.50:37123 for Wireless debugging)
# If refused:          .\connect.ps1 <ip>:<connect-port> -PairAddr <ip>:<pair-port> -Code 123456
param([Parameter(Mandatory)][string]$Address, [string]$PairAddr, [string]$Code)
. "$PSScriptRoot\common.ps1"
if ($Address -notmatch ':') { $Address = "${Address}:5555" }
if ($PairAddr) { Invoke-AdbQuiet pair $PairAddr $Code | Out-Null }
$r = Invoke-AdbQuiet connect $Address
if ($r -notmatch 'connected to') { Write-Log 'Not connected. Accept the prompt on the TV, or use Wireless debugging pairing.' 'Red'; return }
Start-Sleep 2
$state = (& $Adb -s $Address get-state 2>&1 | Out-String).Trim()
if ($state -ne 'device') { Write-Log "State: $state  -> press OK on 'Allow USB debugging?' on the TV (tick 'Always allow'), then run again." 'Yellow'; return }
Set-Content $DeviceFile $Address
$Serial = $Address
foreach ($p in 'ro.product.manufacturer','ro.product.model','ro.build.version.release','ro.build.characteristics','ro.product.cpu.abi') {
    Write-Log ("{0,-28} {1}" -f $p, (Adb-Raw shell getprop $p | Out-String).Trim())
}
$tv = Adb-Raw shell pm has-feature android.software.leanback | Out-String
Write-Log "Android TV (leanback): $($tv.Trim())" 'Green'
