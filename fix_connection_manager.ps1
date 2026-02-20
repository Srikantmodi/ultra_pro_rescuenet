$content = @'
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
        Log.d(TAG, "═══════════════════════════════════")
        Log.d(TAG, "CONNECTING TO: $deviceAddress")
        Log.d(TAG, "═══════════════════════════════════")

        manager.removeGroup(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "✅ Previous group removed, waiting ${POST_REMOVE_GROUP_DELAY_MS}ms...")
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
                        // Framework is actively busy — needs much longer settle period.
                        Log.w(TAG, "⚠️ removeGroup returned BUSY — waiting ${POST_REMOVE_BUSY_DELAY_MS}ms")
                        scope.launch {
                            delay(POST_REMOVE_BUSY_DELAY_MS)
                            withContext(Dispatchers.Main) {
                                initiateConnection(deviceAddress, onConnected, onFailure)
                            }
                        }
                    }
                    else -> {
                        // ERROR (code 0) typically means no group existed — safe to proceed quickly.
                        Log.d(TAG, "ℹ️ No previous group (code: ${getErrorMessage(code)}), proceeding")
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
        //   Attempts 1-2: intent=0 (prefer CLIENT — fast IP via groupOwnerAddress)
        //   Attempts 3+:  intent=15 (prefer GO — different negotiation path)
        // Some devices can't handle being passive GO while running discoverServices().
        // Switching the initiator to GO role changes which device drives group creation.
        val goIntent = if (connectAttempt <= 2) 0 else 15

        val config = WifiP2pConfig().apply {
            this.deviceAddress = deviceAddress
            groupOwnerIntent = goIntent
        }

        Log.d(TAG, "➡️ connect() attempt $connectAttempt/$MAX_CONNECT_RETRIES (GO intent=$goIntent)")

        manager.connect(channel, config, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "✅ Connection initiated (attempt $connectAttempt, intent=$goIntent), waiting for group...")

                scope.launch {
                    delay(CONNECTION_RETRY_DELAY_MS)
                    requestConnectionInfo(deviceAddress, onConnected, onFailure)
                }
            }

            override fun onFailure(code: Int) {
                val errorMsg = getErrorMessage(code)

                if (connectAttempt < MAX_CONNECT_RETRIES &&
                    (code == WifiP2pManager.ERROR || code == WifiP2pManager.BUSY)) {

                    Log.w(TAG, "⚠️ connect() returned $errorMsg (attempt $connectAttempt/$MAX_CONNECT_RETRIES), cleaning up before retry...")

                    // Clean framework state before retrying.
                    // Without removeGroup between retries, stale negotiation state
                    // from the failed attempt causes the next attempt to also ERROR.
                    val retryAction: () -> Unit = {
                        scope.launch {
                            delay(CONNECT_RETRY_DELAY_MS)
                            withContext(Dispatchers.Main) {
                                initiateConnection(deviceAddress, onConnected, onFailure, connectAttempt + 1)
                            }
                        }
                    }

                    manager.removeGroup(channel, object : WifiP2pManager.ActionListener {
                        override fun onSuccess() {
                            Log.d(TAG, "✅ Cleanup removeGroup succeeded before retry")
                            retryAction()
                        }
                        override fun onFailure(code2: Int) {
                            Log.d(TAG, "ℹ️ Cleanup removeGroup: ${getErrorMessage(code2)}, retrying anyway")
                            retryAction()
                        }
                    })
                } else {
                    val error = "Connection failed: $errorMsg"
                    Log.e(TAG, "❌ $error (after $connectAttempt attempt(s))")
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
                    Log.d(TAG, "⏳ Connection info null, retrying ($attempt/$maxConnectionAttempts)...")
                    scope.launch {
                        delay(CONNECTION_RETRY_DELAY_MS)
                        requestConnectionInfo(originalDeviceAddress, onConnected, onFailure, attempt + 1)
                    }
                } else {
                    Log.e(TAG, "❌ Connection info unavailable after $maxConnectionAttempts attempts")
                    onFailure("Connection info unavailable")
                }
                return@requestConnectionInfo
            }

            Log.d(TAG, "📋 Connection Info (Attempt $attempt):")
            Log.d(TAG, "   Group Formed: ${'$'}{info.groupFormed}")
            Log.d(TAG, "   Is Group Owner: ${'$'}{info.isGroupOwner}")
            Log.d(TAG, "   Group Owner Address: ${'$'}{info.groupOwnerAddress?.hostAddress}")

            if (!info.groupFormed) {
                if (attempt < maxConnectionAttempts) {
                    Log.d(TAG, "⏳ Group not formed yet, retrying ($attempt/$maxConnectionAttempts)...")
                    scope.launch {
                        delay(CONNECTION_RETRY_DELAY_MS)
                        requestConnectionInfo(originalDeviceAddress, onConnected, onFailure, attempt + 1)
                    }
                } else {
                    Log.e(TAG, "❌ Group not formed after $maxConnectionAttempts attempts")
                    onFailure("P2P group not formed")
                }
                return@requestConnectionInfo
            }

            if (info.isGroupOwner) {
                // We are Group Owner — resolve the client's IP address.
                // This happens when groupOwnerIntent=15 (retry path) or when the
                // framework assigned us GO role during negotiation.
                Log.d(TAG, "👑 We are Group Owner — resolving client IP via requestGroupInfo")
                resolveClientIpFromGroup(originalDeviceAddress, onConnected, onFailure)
            } else {
                // Normal client path: group owner IP is the target
                val targetIp = info.groupOwnerAddress?.hostAddress ?: run {
                    Log.e(TAG, "❌ Group owner address is null")
                    onFailure("Group owner address unavailable")
                    return@requestConnectionInfo
                }

                Log.d(TAG, "═══════════════════════════════════")
                Log.d(TAG, "✅ CONNECTED (client mode) - Target IP: $targetIp")
                Log.d(TAG, "═══════════════════════════════════")

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
                    Log.d(TAG, "⏳ Group info null, retrying ($attempt/$MAX_GROUP_INFO_RETRIES)...")
                    scope.launch {
                        delay(CONNECTION_RETRY_DELAY_MS)
                        resolveClientIpFromGroup(originalDeviceAddress, onConnected, onFailure, attempt + 1)
                    }
                } else {
                    Log.e(TAG, "❌ Group info unavailable after $MAX_GROUP_INFO_RETRIES attempts")
                    manager.removeGroup(channel, object : WifiP2pManager.ActionListener {
                        override fun onSuccess() { onFailure("GO mode: group info unavailable") }
                        override fun onFailure(code: Int) { onFailure("GO mode: group info unavailable, cleanup failed") }
                    })
                }
                return@requestGroupInfo
            }

            val clients = group.clientList
            Log.d(TAG, "📋 Group Info: ${'$'}{clients?.size ?: 0} clients connected")

            if (clients.isNullOrEmpty()) {
                if (attempt < MAX_GROUP_INFO_RETRIES) {
                    Log.d(TAG, "⏳ No clients in group yet, retrying ($attempt/$MAX_GROUP_INFO_RETRIES)...")
                    scope.launch {
                        delay(CONNECTION_RETRY_DELAY_MS)
                        resolveClientIpFromGroup(originalDeviceAddress, onConnected, onFailure, attempt + 1)
                    }
                } else {
                    Log.e(TAG, "❌ No clients connected after $MAX_GROUP_INFO_RETRIES attempts")
                    manager.removeGroup(channel, object : WifiP2pManager.ActionListener {
                        override fun onSuccess() { onFailure("GO with no clients — removed group") }
                        override fun onFailure(code: Int) { onFailure("GO with no clients — cleanup failed") }
                    })
                }
                return@requestGroupInfo
            }

            val targetClient = clients.firstOrNull { it.deviceAddress == originalDeviceAddress }
                ?: clients.first()

            scope.launch {
                Log.d(TAG, "⏳ Waiting ${DHCP_SETTLE_DELAY_MS}ms for client DHCP to settle...")
                delay(DHCP_SETTLE_DELAY_MS)

                var clientIp = resolveIpFromArp(targetClient.deviceAddress)

                if (clientIp == null) {
                    for (retryArp in 1..3) {
                        Log.w(TAG, "⚠️ ARP miss, retrying in 2s (attempt $retryArp/3)...")
                        delay(2000L)
                        clientIp = resolveIpFromArp(targetClient.deviceAddress)
                        if (clientIp != null) break
                    }
                }

                if (clientIp == null) {
                    clientIp = discoverP2pClientIp()
                }

                if (clientIp != null) {
                    Log.d(TAG, "═══════════════════════════════════")
                    Log.d(TAG, "✅ CONNECTED (GO mode) - Client IP: $clientIp")
                    Log.d(TAG, "═══════════════════════════════════")
                    withContext(Dispatchers.Main) {
                        onConnected(clientIp)
                    }
                } else {
                    Log.e(TAG, "❌ Could not resolve client IP from ARP table or subnet scan")
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

    private fun resolveIpFromArp(macAddress: String): String? {
        try {
            val normalizedMac = macAddress.lowercase()
            val arpTable = java.io.File("/proc/net/arp").readText()

            for (line in arpTable.lines()) {
                if (line.lowercase().contains(normalizedMac)) {
                    val ip = line.split("\\s+".toRegex()).firstOrNull()
                    if (ip != null && ip.startsWith("192.168.49.") && ip != "192.168.49.1") {
                        Log.d(TAG, "✅ Resolved client IP from ARP: $ip (MAC: $macAddress)")
                        return ip
                    }
                }
            }

            Log.w(TAG, "⚠️ MAC $macAddress not found in ARP table")
            return null
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error reading ARP table: ${'$'}{e.message}")
            return null
        }
    }

    private suspend fun discoverP2pClientIp(): String? {
        return withContext(Dispatchers.IO) {
            for (i in 2..20) {
                val candidateIp = "192.168.49.$i"
                try {
                    val addr = java.net.InetAddress.getByName(candidateIp)
                    if (addr.isReachable(2000)) {
                        Log.d(TAG, "✅ Found reachable P2P client at $candidateIp (subnet scan)")
                        return@withContext candidateIp
                    }
                } catch (e: Exception) {
                    // Not reachable, continue
                }
            }
            Log.w(TAG, "⚠️ No P2P client found in subnet scan")
            null
        }
    }

    @SuppressLint("MissingPermission")
    fun disconnect(onComplete: () -> Unit) {
        Log.d(TAG, "Disconnecting P2P group...")

        manager.removeGroup(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "✅ P2P group removed")
                onComplete()
            }

            override fun onFailure(code: Int) {
                Log.w(TAG, "⚠️ Failed to remove group: ${'$'}{getErrorMessage(code)}")
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
'@

$filePath = "d:\ultra_pro_rescuenet\android\app\src\main\kotlin\com\example\ultra_pro_rescuenet\ConnectionManager.kt"
[System.IO.File]::WriteAllText($filePath, $content, [System.Text.Encoding]::UTF8)
Write-Host "ConnectionManager.kt rewritten successfully"
Write-Host "Lines: $(($content -split "`n").Count)"
