$f = "d:\ultra_pro_rescuenet\android\app\src\main\kotlin\com\example\ultra_pro_rescuenet\ConnectionManager.kt"
$c = [IO.File]::ReadAllText($f)

# Replace 1: Add connectAttempt parameter and retry logic to initiateConnection
$old1 = @'
    private fun initiateConnection(
        deviceAddress: String,
        onConnected: (String) -> Unit,
        onFailure: (String) -> Unit
    ) {
        val config = WifiP2pConfig().apply {
            this.deviceAddress = deviceAddress
            groupOwnerIntent = 0
        }

        manager.connect(channel, config, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
'@

$new1 = @'
    private fun initiateConnection(
        deviceAddress: String,
        onConnected: (String) -> Unit,
        onFailure: (String) -> Unit,
        connectAttempt: Int = 1
    ) {
        val config = WifiP2pConfig().apply {
            this.deviceAddress = deviceAddress
            groupOwnerIntent = 0
        }

        manager.connect(channel, config, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
'@

if ($c.Contains($old1)) {
    $c = $c.Replace($old1, $new1)
    Write-Host "Replacement 1 OK: Added connectAttempt parameter"
} else {
    Write-Host "Replacement 1 FAILED: old text not found"
}

# Replace 2: Add retry logic to onFailure handler
$old2 = @'
            override fun onFailure(code: Int) {
                val error = "Connection failed: ${getErrorMessage(code)}"
                Log.e(TAG, "❌ $error")
                onFailure(error)
            }
        })
    }
'@

$new2 = @'
            override fun onFailure(code: Int) {
                val errorMsg = getErrorMessage(code)
                // FIX CONN-RETRY: Retry on transient ERROR / BUSY instead of
                // failing immediately. The P2P framework can return ERROR when
                // its internal state machine hasn't fully settled after a recent
                // connect/disconnect cycle.
                if (connectAttempt < MAX_CONNECT_RETRIES &&
                    (code == WifiP2pManager.ERROR || code == WifiP2pManager.BUSY)) {
                    Log.w(TAG, "⚠️ connect() returned $errorMsg, retrying in ${CONNECT_RETRY_DELAY_MS}ms " +
                            "(attempt $connectAttempt/$MAX_CONNECT_RETRIES)...")
                    scope.launch {
                        delay(CONNECT_RETRY_DELAY_MS)
                        withContext(Dispatchers.Main) {
                            initiateConnection(deviceAddress, onConnected, onFailure, connectAttempt + 1)
                        }
                    }
                } else {
                    val error = "Connection failed: $errorMsg"
                    Log.e(TAG, "❌ $error (after $connectAttempt attempt(s))")
                    onFailure(error)
                }
            }
        })
    }
'@

if ($c.Contains($old2)) {
    $c = $c.Replace($old2, $new2)
    Write-Host "Replacement 2 OK: Added retry logic to onFailure"
} else {
    Write-Host "Replacement 2 FAILED: old text not found"
}

[IO.File]::WriteAllText($f, $c, [System.Text.Encoding]::UTF8)
Write-Host "File saved successfully"
