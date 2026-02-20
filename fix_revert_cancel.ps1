
# Revert cancelConnect — it's breaking connections on Redmi 12
$cmFile = "d:\ultra_pro_rescuenet\android\app\src\main\kotlin\com\example\ultra_pro_rescuenet\ConnectionManager.kt"
$cm = [System.IO.File]::ReadAllText($cmFile, [System.Text.Encoding]::UTF8)

# Replace the cancelConnect → removeGroupThenConnect chain
# with direct removeGroup (the original working flow)
$oldBlock = @'
        // FIX GROUP-FORM: Cancel any stale connection invitation before starting a new one.
        // Without this, Android's P2P framework can silently block new connections
        // if a previous GO negotiation is still pending.
        manager.cancelConnect(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "ℹ️ Stale connection cancelled, proceeding to removeGroup")
                removeGroupThenConnect(deviceAddress, onConnected, onFailure)
            }
            override fun onFailure(code: Int) {
                // Nothing to cancel — proceed
                removeGroupThenConnect(deviceAddress, onConnected, onFailure)
            }
        })
    }

    @SuppressLint("MissingPermission")
    private fun removeGroupThenConnect(
        deviceAddress: String,
        onConnected: (String) -> Unit,
        onFailure: (String) -> Unit
    ) {
        // FIX D-2: Remove any residual P2P group before creating a new connection.
'@

$newBlock = @'
        // FIX D-2: Remove any residual P2P group before creating a new connection.
'@

if ($cm.Contains($oldBlock)) {
    $cm = $cm.Replace($oldBlock, $newBlock)
    [System.IO.File]::WriteAllText($cmFile, $cm, [System.Text.Encoding]::UTF8)
    Write-Host "SUCCESS: cancelConnect removed from ConnectionManager.kt"
} else {
    Write-Host "FAILED: Pattern not found"
    # Debug
    $idx = $cm.IndexOf("cancelConnect")
    Write-Host "cancelConnect at index: $idx"
}
