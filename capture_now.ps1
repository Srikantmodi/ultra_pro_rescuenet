Remove-Item "$env:TEMP\d1_logs.txt" -ErrorAction SilentlyContinue
Remove-Item "$env:TEMP\d2_logs.txt" -ErrorAction SilentlyContinue

$d1 = Start-Job -ScriptBlock {
    adb -s 6XOZ9X599HB6RKCA logcat -v time WifiP2pHandler:D RescueNet:D MeshService:D GeneralHandler:D ConnectionManager:D SocketServer:D AndroidRuntime:E "*:S" 2>&1 | Out-File "$env:TEMP\d1_logs.txt" -Encoding utf8
}
$d2 = Start-Job -ScriptBlock {
    adb -s b02717707d75 logcat -v time WifiP2pHandler:D RescueNet:D MeshService:D GeneralHandler:D ConnectionManager:D SocketServer:D AndroidRuntime:E "*:S" 2>&1 | Out-File "$env:TEMP\d2_logs.txt" -Encoding utf8
}

Write-Host "Jobs started: D1=$($d1.Id) D2=$($d2.Id)"
Write-Host "Waiting 150 seconds for mesh activity..."

Start-Sleep -Seconds 150

Stop-Job $d1
Stop-Job $d2

$c1 = (Get-Content "$env:TEMP\d1_logs.txt" -ErrorAction SilentlyContinue | Measure-Object).Count
$c2 = (Get-Content "$env:TEMP\d2_logs.txt" -ErrorAction SilentlyContinue | Measure-Object).Count

Write-Host "CAPTURE_COMPLETE D1=$c1 D2=$c2"

Remove-Job $d1
Remove-Job $d2
