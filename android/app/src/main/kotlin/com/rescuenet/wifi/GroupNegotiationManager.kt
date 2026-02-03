package com.rescuenet.wifi

import android.annotation.SuppressLint
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pGroup
import android.net.wifi.p2p.WifiP2pInfo
import android.net.wifi.p2p.WifiP2pManager
import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * Manages Wi-Fi Direct group formation and connection lifecycle.
 *
 * This is critical for the "Store-and-Forward" protocol:
 * 1. Connect to target device -> Form P2P group
 * 2. Exchange data via TCP sockets
 * 3. Disconnect -> Remove group
 *
 * **CRITICAL IMPLEMENTATION NOTE:**
 *
 * Before EVERY new connection, we MUST call `removeGroup()` to kill any
 * "zombie groups" from previous failed connections. Android's Wi-Fi Direct
 * often leaves stale group state that prevents new connections.
 *
 * Connection flow:
 * ```
 * removeGroup() -> connect() -> [exchange data] -> disconnect()
 * ```
 *
 * @param manager The WifiP2pManager instance
 * @param channel The WifiP2pManager.Channel
 */
@SuppressLint("MissingPermission")
class GroupNegotiationManager(
    private val manager: WifiP2pManager,
    private val channel: WifiP2pManager.Channel
) {
    companion object {
        private const val TAG = "GroupNegotiationManager"
        
        // Timeout for connection attempts
        const val CONNECTION_TIMEOUT_MS = 15000L
        
        // Delay after removeGroup before attempting connect
        const val POST_REMOVE_DELAY_MS = 500L
    }

    private val handler = Handler(Looper.getMainLooper())
    private var connectionCallback: ((Boolean, WifiP2pInfo?, String?) -> Unit)? = null
    private var isConnecting = false
    private var currentGroupInfo: WifiP2pInfo? = null

    /**
     * Connects to a device with the removeGroup() hack.
     *
     * This is the safe connection method that:
     * 1. First removes any existing group (critical!)
     * 2. Waits briefly for cleanup
     * 3. Then attempts the connection
     *
     * @param deviceAddress MAC address of target device
     * @param callback Called with (success, connectionInfo, errorMessage)
     */
    fun connectToDevice(
        deviceAddress: String,
        callback: (Boolean, WifiP2pInfo?, String?) -> Unit
    ) {
        if (isConnecting) {
            callback(false, null, "Connection already in progress")
            return
        }
        
        Log.d(TAG, "Starting connection to $deviceAddress")
        isConnecting = true
        connectionCallback = callback
        
        // CRITICAL: Always removeGroup first to kill zombie groups
        removeGroup { _, _ ->
            // Wait a bit for cleanup to complete
            handler.postDelayed({
                performConnect(deviceAddress)
            }, POST_REMOVE_DELAY_MS)
        }
    }

    /**
     * Performs the actual connection after group removal.
     */
    private fun performConnect(deviceAddress: String) {
        val config = WifiP2pConfig().apply {
            this.deviceAddress = deviceAddress
            // Use PBC (Push Button Configuration) for auto-accept
            wps.setup = android.net.wifi.WpsInfo.PBC
        }
        
        Log.d(TAG, "Connecting to device: $deviceAddress")
        
        // Set up connection timeout
        val timeoutRunnable = Runnable {
            if (isConnecting) {
                Log.e(TAG, "Connection timeout")
                isConnecting = false
                connectionCallback?.invoke(false, null, "Connection timed out")
                connectionCallback = null
            }
        }
        handler.postDelayed(timeoutRunnable, CONNECTION_TIMEOUT_MS)
        
        manager.connect(channel, config, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "Connection initiated successfully")
                // Note: This only means the connection STARTED.
                // We need to wait for connection info via requestConnectionInfo
                requestConnectionInfo()
            }

            override fun onFailure(reason: Int) {
                handler.removeCallbacks(timeoutRunnable)
                val error = getErrorMessage(reason)
                Log.e(TAG, "Connection failed: $error")
                isConnecting = false
                connectionCallback?.invoke(false, null, error)
                connectionCallback = null
            }
        })
    }

    /**
     * Requests connection info after successful connect initiation.
     */
    private fun requestConnectionInfo() {
        Log.d(TAG, "Requesting connection info")
        
        manager.requestConnectionInfo(channel) { info ->
            if (info != null && info.groupFormed) {
                Log.d(TAG, "Group formed. Owner: ${info.isGroupOwner}, " +
                    "Owner Address: ${info.groupOwnerAddress?.hostAddress}")
                
                currentGroupInfo = info
                isConnecting = false
                connectionCallback?.invoke(true, info, null)
                connectionCallback = null
            } else {
                // Connection not ready yet, retry after a delay
                Log.d(TAG, "Group not yet formed, waiting...")
                handler.postDelayed({
                    if (isConnecting) {
                        requestConnectionInfo()
                    }
                }, 500)
            }
        }
    }

    /**
     * Disconnects from the current group.
     *
     * @param callback Called with (success, errorMessage)
     */
    fun disconnect(callback: (Boolean, String?) -> Unit) {
        Log.d(TAG, "Disconnecting")
        
        manager.cancelConnect(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "Connection cancelled")
                removeGroup(callback)
            }

            override fun onFailure(reason: Int) {
                // Even if cancel fails, try to remove group
                Log.w(TAG, "Cancel connect failed: ${getErrorMessage(reason)}")
                removeGroup(callback)
            }
        })
    }

    /**
     * Removes the current Wi-Fi Direct group.
     *
     * **CRITICAL:** This must be called before every new connection attempt
     * to prevent "zombie group" issues.
     *
     * @param callback Called with (success, errorMessage)
     */
    fun removeGroup(callback: (Boolean, String?) -> Unit) {
        Log.d(TAG, "Removing group")
        
        manager.removeGroup(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "Group removed successfully")
                currentGroupInfo = null
                callback(true, null)
            }

            override fun onFailure(reason: Int) {
                // Failure is often expected if no group exists
                val error = getErrorMessage(reason)
                Log.d(TAG, "Remove group failed (often OK): $error")
                currentGroupInfo = null
                // Still call success - we just want to ensure clean state
                callback(true, null)
            }
        })
    }

    /**
     * Gets information about the current group.
     *
     * @param callback Called with the group info, or null if not in a group
     */
    fun getGroupInfo(callback: (WifiP2pGroup?) -> Unit) {
        manager.requestGroupInfo(channel) { group ->
            callback(group)
        }
    }

    /**
     * Checks if we're currently connected to a group.
     */
    fun isConnected(): Boolean = currentGroupInfo?.groupFormed == true

    /**
     * Gets the group owner's IP address.
     *
     * Used by the client (non-owner) to know where to send data.
     */
    fun getGroupOwnerAddress(): String? {
        return currentGroupInfo?.groupOwnerAddress?.hostAddress
    }

    /**
     * Checks if this device is the group owner.
     *
     * The group owner runs the server socket.
     */
    fun isGroupOwner(): Boolean = currentGroupInfo?.isGroupOwner == true

    /**
     * Performs peer discovery to find nearby devices.
     *
     * Note: For our mesh network, we primarily use DNS-SD for discovery,
     * but this can be useful for direct P2P connections.
     *
     * @param callback Called with (success, errorMessage)
     */
    fun discoverPeers(callback: (Boolean, String?) -> Unit) {
        Log.d(TAG, "Starting peer discovery")
        
        manager.discoverPeers(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "Peer discovery started")
                callback(true, null)
            }

            override fun onFailure(reason: Int) {
                val error = getErrorMessage(reason)
                Log.e(TAG, "Peer discovery failed: $error")
                callback(false, error)
            }
        })
    }

    /**
     * Stops peer discovery.
     */
    fun stopPeerDiscovery(callback: (Boolean, String?) -> Unit) {
        manager.stopPeerDiscovery(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "Peer discovery stopped")
                callback(true, null)
            }

            override fun onFailure(reason: Int) {
                callback(false, getErrorMessage(reason))
            }
        })
    }

    /**
     * Converts Wi-Fi P2P error codes to human-readable messages.
     */
    private fun getErrorMessage(reason: Int): String {
        return when (reason) {
            WifiP2pManager.P2P_UNSUPPORTED -> "P2P not supported on this device"
            WifiP2pManager.ERROR -> "Internal error"
            WifiP2pManager.BUSY -> "Framework busy, try again"
            else -> "Unknown error (code: $reason)"
        }
    }

    /**
     * Cleans up resources.
     */
    fun cleanup() {
        Log.d(TAG, "Cleaning up")
        
        isConnecting = false
        connectionCallback = null
        handler.removeCallbacksAndMessages(null)
        
        // Try to remove any existing group
        removeGroup { _, _ -> }
    }
}
