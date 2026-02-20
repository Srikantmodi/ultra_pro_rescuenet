
# Fix the async chaining: stopPeerDiscovery MUST complete before connect is called
$handlerFile = "d:\ultra_pro_rescuenet\android\app\src\main\kotlin\com\example\ultra_pro_rescuenet\WifiP2pHandler.kt"
$handler = [System.IO.File]::ReadAllText($handlerFile, [System.Text.Encoding]::UTF8)

# Step 1: Replace the stopPeerDiscovery block + immediate connectionManager.connect(
# with val doConnect lambda wrapping connectionManager.connect(
$oldPattern = @'
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

$newPattern = @'
        // FIX GROUP-FORM: Wrap the entire connect logic in a lambda so it can be
        // triggered from the stopPeerDiscovery callback (properly chained).
        val doConnect: () -> Unit = {
            connectionManager.connect(
'@

$handler = $handler.Replace($oldPattern, $newPattern)

# Step 2: Find the end of connectionManager.connect() block and the closing } of connectAndSendPacket
# The current ending is:
#             }
#         )
#     }
# We need to change it to close the lambda, then add the stopPeerDiscovery that calls doConnect()
$oldEnding = @'
            onFailure = { error ->
                Log.e(TAG, "❌ Connection failed: $error")
                isConnecting = false
                mainHandler.post {
                    result.error("CONNECTION_FAILED", error, null)
                }
            }
        )
    }
'@

$newEnding = @'
            onFailure = { error ->
                Log.e(TAG, "❌ Connection failed: $error")
                isConnecting = false
                mainHandler.post {
                    result.error("CONNECTION_FAILED", error, null)
                }
            }
        )
        }

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
                doConnect()
            }
            override fun onFailure(code: Int) {
                Log.w(TAG, "⚠️ stopPeerDiscovery failed (code: $code), proceeding anyway")
                doConnect()
            }
        })
    }
'@

$handler = $handler.Replace($oldEnding, $newEnding)

[System.IO.File]::WriteAllText($handlerFile, $handler, [System.Text.Encoding]::UTF8)
Write-Host "Done - stopPeerDiscovery properly chained with connect"
