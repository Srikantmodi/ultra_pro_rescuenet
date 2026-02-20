$ErrorActionPreference = "SilentlyContinue"

# Clear logs
adb -s 6XOZ9X599HB6RKCA logcat -c
adb -s b02717707d75 logcat -c
Write-Host "Logs cleared. Starting 150s capture..."

# Start background logcat jobs
$j1 = Start-Job { adb -s 6XOZ9X599HB6RKCA logcat -s "WifiP2pHandler:D" "RescueNet:D" "MeshService:D" "GeneralHandler:D" "ConnectionManager:D" "SocketServer:D" "AndroidRuntime:E" 2>&1 }
$j2 = Start-Job { adb -s b02717707d75 logcat -s "WifiP2pHandler:D" "RescueNet:D" "MeshService:D" "GeneralHandler:D" "ConnectionManager:D" "SocketServer:D" "AndroidRuntime:E" 2>&1 }

Write-Host "Jobs: $($j1.Id), $($j2.Id)"

# Wait 150 seconds
Start-Sleep -Seconds 150

# Collect
$d1 = Receive-Job -Id $j1.Id
$d2 = Receive-Job -Id $j2.Id
Stop-Job $j1.Id, $j2.Id
Remove-Job $j1.Id, $j2.Id

# Save
$d1 | Out-File "$env:TEMP\d1_log.txt" -Encoding utf8
$d2 | Out-File "$env:TEMP\d2_log.txt" -Encoding utf8

Write-Host "DONE: D1=$($d1.Count) lines, D2=$($d2.Count) lines"
