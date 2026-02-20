
# Add restartDiscoveryAfterSend() to the connection failure path
$handlerFile = "d:\ultra_pro_rescuenet\android\app\src\main\kotlin\com\example\ultra_pro_rescuenet\WifiP2pHandler.kt"
$handler = [System.IO.File]::ReadAllText($handlerFile, [System.Text.Encoding]::UTF8)

# Find the onFailure handler that's missing the discovery restart
$oldFailure = '            onFailure = { error ->
                Log.e(TAG, "' + [char]0x274C + ' Connection failed: $error")
                isConnecting = false
                mainHandler.post {
                    result.error("CONNECTION_FAILED", error, null)
                }
            }'

$newFailure = '            onFailure = { error ->
                Log.e(TAG, "' + [char]0x274C + ' Connection failed: $error")
                isConnecting = false
                // FIX GROUP-FORM: Restart discovery after connection failure
                // since we paused it before attempting to connect.
                restartDiscoveryAfterSend()
                mainHandler.post {
                    result.error("CONNECTION_FAILED", error, null)
                }
            }'

if ($handler.Contains($oldFailure)) {
    $handler = $handler.Replace($oldFailure, $newFailure)
    [System.IO.File]::WriteAllText($handlerFile, $handler, [System.Text.Encoding]::UTF8)
    Write-Host "SUCCESS: Added restartDiscoveryAfterSend() to connection failure path"
} else {
    Write-Host "Pattern not found - checking with different encoding..."
    # Try without the unicode character
    $lines = $handler.Split("`n")
    for ($i = 698; $i -lt [Math]::Min(710, $lines.Length); $i++) {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($lines[$i])
        Write-Host ("Line " + ($i+1) + " (" + $bytes.Length + " bytes): " + $lines[$i].TrimEnd())
    }
}
