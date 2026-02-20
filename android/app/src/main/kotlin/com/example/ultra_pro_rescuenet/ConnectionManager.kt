package com.example.ultra_pro_rescuenet

import android.annotation.SuppressLint
import android.content.Context
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pManager
import android.os.Handler
import android.os.Looper
import android.util.Log

import kotlinx.coroutines.*

class ConnectionManager(
    private val context: Context,
    private val manager: WifiP2pManager,
    private val channel: WifiP2pManager.Channel,
    private val scope: CoroutineScope
) {
    companion object {
        private const val TAG = "ConnectionManager"

        // -- Group-formation polling --
        // After connect() succeeds, we poll requestConnectionInfo() this many times
        // waiting for the P2P group to form. Each poll is 1 second apart.
        // 15 attempts = 15 seconds total.
        var maxConnectionAttempts = 15
            private set
        private const val CONNECTION_RETRY_DELAY_MS = 1000L

        // -- Client-IP resolution (GO mode) --
        private const val MAX_GROUP_INFO_RETRIES = 15
        private const val DHCP_SETTLE_DELAY_MS = 4000L

        // -- connect() retry parameters --
        private const val MAX_CONNECT_RETRIES = 5
        private const val CONNECT_RETRY_DELAY_MS = 2000L
        private const val PEER_REDISCOVERY_DELAY_MS = 3500L

        // -- removeGroup settle delays --
        private const val POST_REMOVE_GROUP_DELAY_MS = 1000L
        // When removeGroup returns BUSY, the framework is actively processing.
        private const val POST_REMOVE_BUSY_DELAY_MS = 2500L

        fun setConnectionTimeout(attempts: Int) {
            maxConnectionAttempts = attempts.coerceIn(3, 30)
        }
    }

    @SuppressLint("MissingPermission")
    fun connect(
        deviceAddress: String,
        onConnected: (String) -> Unit,
        onFailure: (String) -> Unit
    ) {
        Log.d(TAG, "â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•")
        Log.d(TAG, "CONNECTING TO: $deviceAddress")
        Log.d(TAG, "â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•")

        manager.removeGroup(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "âœ… Previous group removed, waiting ${POST_REMOVE_GROUP_DELAY_MS}ms...")
                scope.launch {
                    delay(POST_REMOVE_GROUP_DELAY_MS)
                    withContext(Dispatchers.Main) {
                        initiateConnection(deviceAddress, onConnected, onFailure)
                    }
                }
            }

            override fun onFailure(code: Int) {
                when (code) {
                    WifiP2pManager.BUSY -> {
                        // Framework is actively busy â€” needs much longer settle period.
                        Log.w(TAG, "âš ï¸ removeGroup returned BUSY â€” waiting ${POST_REMOVE_BUSY_DELAY_MS}ms")
                        scope.launch {
                            delay(POST_REMOVE_BUSY_DELAY_MS)
                            withContext(Dispatchers.Main) {
                                initiateConnection(deviceAddress, onConnected, onFailure)
                            }
                        }
                    }
                    else -> {
                        // ERROR (code 0) typically means no group existed â€” safe to proceed quickly.
                        Log.d(TAG, "â„¹ï¸ No previous group (code: ${getErrorMessage(code)}), proceeding")
                        scope.launch {
                            delay(POST_REMOVE_GROUP_DELAY_MS / 2)
                            withContext(Dispatchers.Main) {
                                initiateConnection(deviceAddress, onConnected, onFailure)
                            }
                        }
                    }
                }
            }
        })
    }

    @SuppressLint("MissingPermission")
    private fun initiateConnection(
        deviceAddress: String,
        onConnected: (String) -> Unit,
        onFailure: (String) -> Unit,
        connectAttempt: Int = 1
    ) {
        // Alternate groupOwnerIntent between retries:
        //   Attempts 1-2: intent=0 (prefer CLIENT â€” fast IP via groupOwnerAddress)
        //   Attempts 3+:  intent=15 (prefer GO â€” different negotiation path)
        // Some devices can't handle being passive GO while running discoverServices().
        // Switching the initiator to GO role changes which device drives group creation.
        val goIntent = if (connectAttempt <= 2) 0 else 15

        val config = WifiP2pConfig().apply {
            this.deviceAddress = deviceAddress
            groupOwnerIntent = goIntent
        }

        Log.d(TAG, "âž¡ï¸ connect() attempt $connectAttempt/$MAX_CONNECT_RETRIES (GO intent=$goIntent)")

        manager.connect(channel, config, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "âœ… Connection initiated (attempt $connectAttempt, intent=$goIntent), waiting for group...")

                scope.launch {
                    delay(CONNECTION_RETRY_DELAY_MS)
                    requestConnectionInfo(deviceAddress, onConnected, onFailure)
                }
            }

            override fun onFailure(code: Int) {
                val errorMsg = getErrorMessage(code)

                if (connectAttempt < MAX_CONNECT_RETRIES &&
                    (code == WifiP2pManager.ERROR || code == WifiP2pManager.BUSY)) {

                    Log.w(TAG, "⚠️ connect() returned $errorMsg (attempt $connectAttempt/$MAX_CONNECT_RETRIES)")
                    Log.d(TAG, "🔄 Refreshing peer discovery before retry...")

                    // When connect() returns ERROR, the peer is likely absent from
                    // the framework's discovered peer cache (cleared after disconnect).
                    // Trigger discoverPeers() to refresh the cache before retrying.
                    manager.discoverPeers(channel, object : WifiP2pManager.ActionListener {
                        override fun onSuccess() {
                            Log.d(TAG, "✅ Peer discovery refresh triggered")
                        }
                        override fun onFailure(code2: Int) {
                            Log.w(TAG, "⚠️ Peer discovery refresh failed: ${getErrorMessage(code2)}")
                        }
                    })

                    scope.launch {
                        delay(PEER_REDISCOVERY_DELAY_MS)
                        withContext(Dispatchers.Main) {
                            initiateConnection(deviceAddress, onConnected, onFailure, connectAttempt + 1)
                        }
                    }
                } else {
                    val error = "Connection failed: $errorMsg"
                    Log.e(TAG, "âŒ $error (after $connectAttempt attempt(s))")
                    onFailure(error)
                }
            }
        })
    }

    @SuppressLint("MissingPermission")
    private fun requestConnectionInfo(
        originalDeviceAddress: String,
        onConnected: (String) -> Unit,
        onFailure: (String) -> Unit,
        attempt: Int = 1
    ) {
        manager.requestConnectionInfo(channel) { info ->
            if (info == null) {
                if (attempt < maxConnectionAttempts) {
                    Log.d(TAG, "â³ Connection info null, retrying ($attempt/$maxConnectionAttempts)...")
                    scope.launch {
                        delay(CONNECTION_RETRY_DELAY_MS)
                        requestConnectionInfo(originalDeviceAddress, onConnected, onFailure, attempt + 1)
                    }
                } else {
                    Log.e(TAG, "âŒ Connection info unavailable after $maxConnectionAttempts attempts")
                    onFailure("Connection info unavailable")
                }
                return@requestConnectionInfo
            }

            Log.d(TAG, "ðŸ“‹ Connection Info (Attempt $attempt):")
            Log.d(TAG, "   Group Formed: ${info.groupFormed}")
            Log.d(TAG, "   Is Group Owner: ${info.isGroupOwner}")
            Log.d(TAG, "   Group Owner Address: ${info.groupOwnerAddress?.hostAddress}")

            if (!info.groupFormed) {
                if (attempt < maxConnectionAttempts) {
                    Log.d(TAG, "â³ Group not formed yet, retrying ($attempt/$maxConnectionAttempts)...")
                    scope.launch {
                        delay(CONNECTION_RETRY_DELAY_MS)
                        requestConnectionInfo(originalDeviceAddress, onConnected, onFailure, attempt + 1)
                    }
                } else {
                    Log.e(TAG, "âŒ Group not formed after $maxConnectionAttempts attempts")
                    onFailure("P2P group not formed")
                }
                return@requestConnectionInfo
            }

            if (info.isGroupOwner) {
                // We are Group Owner â€” resolve the client's IP address.
                // This happens when groupOwnerIntent=15 (retry path) or when the
                // framework assigned us GO role during negotiation.
                Log.d(TAG, "ðŸ‘‘ We are Group Owner â€” resolving client IP via requestGroupInfo")
                resolveClientIpFromGroup(originalDeviceAddress, onConnected, onFailure)
            } else {
                // Normal client path: group owner IP is the target
                val targetIp = info.groupOwnerAddress?.hostAddress ?: run {
                    Log.e(TAG, "âŒ Group owner address is null")
                    onFailure("Group owner address unavailable")
                    return@requestConnectionInfo
                }

                Log.d(TAG, "â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•")
                Log.d(TAG, "âœ… CONNECTED (client mode) - Target IP: $targetIp")
                Log.d(TAG, "â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•")

                onConnected(targetIp)
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun resolveClientIpFromGroup(
        originalDeviceAddress: String,
        onConnected: (String) -> Unit,
        onFailure: (String) -> Unit,
        attempt: Int = 1
    ) {
        manager.requestGroupInfo(channel) { group ->
            if (group == null) {
                if (attempt < MAX_GROUP_INFO_RETRIES) {
                    Log.d(TAG, "â³ Group info null, retrying ($attempt/$MAX_GROUP_INFO_RETRIES)...")
                    scope.launch {
                        delay(CONNECTION_RETRY_DELAY_MS)
                        resolveClientIpFromGroup(originalDeviceAddress, onConnected, onFailure, attempt + 1)
                    }
                } else {
                    Log.e(TAG, "âŒ Group info unavailable after $MAX_GROUP_INFO_RETRIES attempts")
                    manager.removeGroup(channel, object : WifiP2pManager.ActionListener {
                        override fun onSuccess() { onFailure("GO mode: group info unavailable") }
                        override fun onFailure(code: Int) { onFailure("GO mode: group info unavailable, cleanup failed") }
                    })
                }
                return@requestGroupInfo
            }

            val clients = group.clientList
            Log.d(TAG, "ðŸ“‹ Group Info: ${clients?.size ?: 0} clients connected")

            if (clients.isNullOrEmpty()) {
                if (attempt < MAX_GROUP_INFO_RETRIES) {
                    Log.d(TAG, "â³ No clients in group yet, retrying ($attempt/$MAX_GROUP_INFO_RETRIES)...")
                    scope.launch {
                        delay(CONNECTION_RETRY_DELAY_MS)
                        resolveClientIpFromGroup(originalDeviceAddress, onConnected, onFailure, attempt + 1)
                    }
                } else {
                    Log.e(TAG, "âŒ No clients connected after $MAX_GROUP_INFO_RETRIES attempts")
                    manager.removeGroup(channel, object : WifiP2pManager.ActionListener {
                        override fun onSuccess() { onFailure("GO with no clients â€” removed group") }
                        override fun onFailure(code: Int) { onFailure("GO with no clients â€” cleanup failed") }
                    })
                }
                return@requestGroupInfo
            }

            val targetClient = clients.firstOrNull { it.deviceAddress == originalDeviceAddress }
                ?: clients.first()

            scope.launch {
                Log.d(TAG, "\u23f3 Waiting ${DHCP_SETTLE_DELAY_MS}ms for client DHCP to settle...")
                delay(DHCP_SETTLE_DELAY_MS)

                // Step 1: Try MAC-based ARP lookup (works if MAC not randomized)
                var clientIp = resolveIpFromArp(targetClient.deviceAddress)

                // Step 2: MAC-free ARP - find any 192.168.49.x that is not .1 (us)
                // P2P device MAC != P2P interface MAC (Android randomizes them)
                if (clientIp == null) {
                    Log.d(TAG, "\uD83D\uDD04 MAC-based ARP failed, trying MAC-free ARP...")
                    clientIp = resolveAnyP2pClientFromArp()
                }

                // Step 3: ARP retry with delay (DHCP may still be settling)
                if (clientIp == null) {
                    for (retryArp in 1..3) {
                        Log.w(TAG, "\u26a0\ufe0f ARP miss, retrying in 2s (attempt $retryArp/3)...")
                        delay(2000L)
                        clientIp = resolveAnyP2pClientFromArp()
                        if (clientIp != null) break
                    }
                }

                // Step 4: Parallel subnet scan (.2 to .254)
                if (clientIp == null) {
                    clientIp = discoverP2pClientIp()
                }

                if (clientIp != null) {
                    Log.d(TAG, "\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550")
                    Log.d(TAG, "\u2705 CONNECTED (GO mode) - Client IP: $clientIp")
                    Log.d(TAG, "\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550")
                    withContext(Dispatchers.Main) {
                        onConnected(clientIp)
                    }
                } else {
                    Log.e(TAG, "\u274c Could not resolve client IP from ARP table or subnet scan")
                    withContext(Dispatchers.Main) {
                        manager.removeGroup(channel, object : WifiP2pManager.ActionListener {
                            override fun onSuccess() { onFailure("Could not resolve client IP") }
                            override fun onFailure(code: Int) { onFailure("Could not resolve client IP, cleanup failed") }
                        })
                    }
                }
            }
        }
    }

    /**
     * MAC-free ARP lookup: find any P2P client in 192.168.49.x subnet.
     * P2P device address (WifiP2pDevice.deviceAddress) is NOT the same as
     * the interface MAC visible in ARP table. Android randomizes P2P MACs.
     * Since we are GO (192.168.49.1), any other 192.168.49.x is our client.
     */
    private fun resolveAnyP2pClientFromArp(): String? {
        try {
            val arpTable = java.io.File("/proc/net/arp").readText()
            Log.d(TAG, "📋 ARP table:\n$arpTable")

            for (line in arpTable.lines()) {
                val parts = line.trim().split("\\s+".toRegex())
                val ip = parts.firstOrNull() ?: continue
                if (ip.startsWith("192.168.49.") && ip != "192.168.49.1") {
                    Log.d(TAG, "\u2705 Found P2P client IP from ARP (MAC-free): $ip")
                    return ip
                }
            }
            Log.w(TAG, "\u26a0\ufe0f No P2P client found in ARP table")
            return null
        } catch (e: Exception) {
            Log.e(TAG, "\u274c Error reading ARP table: ${e.message}")
            return null
        }
    }

    private fun resolveIpFromArp(macAddress: String): String? {
        try {
            val normalizedMac = macAddress.lowercase()
            val arpTable = java.io.File("/proc/net/arp").readText()

            for (line in arpTable.lines()) {
                if (line.lowercase().contains(normalizedMac)) {
                    val ip = line.split("\\s+".toRegex()).firstOrNull()
                    if (ip != null && ip.startsWith("192.168.49.") && ip != "192.168.49.1") {
                        Log.d(TAG, "âœ… Resolved client IP from ARP: $ip (MAC: $macAddress)")
                        return ip
                    }
                }
            }

            Log.w(TAG, "âš ï¸ MAC $macAddress not found in ARP table")
            return null
        } catch (e: Exception) {
            Log.e(TAG, "âŒ Error reading ARP table: ${e.message}")
            return null
        }
    }

    private suspend fun discoverP2pClientIp(): String? {
        return withContext(Dispatchers.IO) {
            Log.d(TAG, "\uD83D\uDD0D Starting parallel subnet scan (192.168.49.2-254)...")
            // Parallel batches of 25 with 500ms timeout each
            val batchSize = 25
            for (batchStart in 2..254 step batchSize) {
                val batchEnd = minOf(batchStart + batchSize - 1, 254)
                val deferreds = (batchStart..batchEnd).map { i ->
                    async {
                        val candidateIp = "192.168.49.$i"
                        try {
                            val addr = java.net.InetAddress.getByName(candidateIp)
                            if (addr.isReachable(500)) candidateIp else null
                        } catch (e: Exception) {
                            null
                        }
                    }
                }
                val results = deferreds.mapNotNull { it.await() }
                if (results.isNotEmpty()) {
                    Log.d(TAG, "\u2705 Found reachable P2P client at ${results.first()} (parallel subnet scan)")
                    return@withContext results.first()
                }
            }
            Log.w(TAG, "\u26a0\ufe0f No P2P client found in subnet scan (2-254)")
            null
        }
    }

    @SuppressLint("MissingPermission")
    fun disconnect(onComplete: () -> Unit) {
        Log.d(TAG, "Disconnecting P2P group...")

        manager.removeGroup(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "âœ… P2P group removed")
                onComplete()
            }

            override fun onFailure(code: Int) {
                Log.w(TAG, "âš ï¸ Failed to remove group: ${getErrorMessage(code)}")
                onComplete()
            }
        })
    }

    private fun getErrorMessage(code: Int): String {
        return when (code) {
            WifiP2pManager.P2P_UNSUPPORTED -> "P2P_UNSUPPORTED"
            WifiP2pManager.ERROR -> "ERROR"
            WifiP2pManager.BUSY -> "BUSY"
            else -> "UNKNOWN_$code"
        }
    }
}