
# Fix 1: ConnectionManager.kt - Add cancelConnect() before removeGroup() + reduce timeout
$cmFile = "d:\ultra_pro_rescuenet\android\app\src\main\kotlin\com\example\ultra_pro_rescuenet\ConnectionManager.kt"
$cm = [System.IO.File]::ReadAllText($cmFile, [System.Text.Encoding]::UTF8)

# Fix 1a: Reduce maxConnectionAttempts from 15 to 8
$cm = $cm -replace 'var maxConnectionAttempts = 15', 'var maxConnectionAttempts = 8'

# Fix 1b: Replace the connect() method body to add cancelConnect() before removeGroup()
$oldConnect = @'
        // FIX D-2: Remove any residual P2P group before creating a new connection.
        // Leftover groups from previous connections cause "BUSY" errors on reconnection.
        manager.removeGroup(channel, object : WifiP2pManager.ActionListener {
'@

$newConnect = @'
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
        // Leftover groups from previous connections cause "BUSY" errors on reconnection.
        manager.removeGroup(channel, object : WifiP2pManager.ActionListener {
'@

$cm = $cm.Replace($oldConnect, $newConnect)

[System.IO.File]::WriteAllText($cmFile, $cm, [System.Text.Encoding]::UTF8)
Write-Host "✅ ConnectionManager.kt updated (cancelConnect + timeout reduction)"

# Fix 2: WifiP2pHandler.kt - Pause service discovery before connecting
$handlerFile = "d:\ultra_pro_rescuenet\android\app\src\main\kotlin\com\example\ultra_pro_rescuenet\WifiP2pHandler.kt"
$handler = [System.IO.File]::ReadAllText($handlerFile, [System.Text.Encoding]::UTF8)

$oldConnectAndSend = @'
        val connectionManager = ConnectionManager(context, manager, channel, scope)

        connectionManager.connect(
'@

$newConnectAndSend = @'
        val connectionManager = ConnectionManager(context, manager, channel, scope)

        // FIX GROUP-FORM: Pause service discovery before connecting.
        // Android's P2P driver on many devices cannot handle concurrent
        // discoverServices() and GO negotiation — the negotiation silently
        // fails and the group never forms. Stopping discovery first frees
        // the driver to focus on the connection handshake.
        // Discovery is restarted by restartDiscoveryAfterSend() after
        // the send completes (success or failure).
        manager.stopPeerDiscovery(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "⏸️ Discovery paused for connection attempt")
            }
            override fun onFailure(code: Int) {
                Log.w(TAG, "⚠️ stopPeerDiscovery failed (code: $code), proceeding anyway")
            }
        })

        connectionManager.connect(
'@

$handler = $handler.Replace($oldConnectAndSend, $newConnectAndSend)

[System.IO.File]::WriteAllText($handlerFile, $handler, [System.Text.Encoding]::UTF8)
Write-Host "✅ WifiP2pHandler.kt updated (pause discovery before connect)"

Write-Host ""
Write-Host "All fixes applied:"
Write-Host "  1. cancelConnect() before removeGroup() in ConnectionManager"
Write-Host "  2. maxConnectionAttempts reduced from 15 to 8"
Write-Host "  3. stopPeerDiscovery() before connect in WifiP2pHandler"
