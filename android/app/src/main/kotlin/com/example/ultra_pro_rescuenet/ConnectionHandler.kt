package com.example.ultra_pro_rescuenet

import android.annotation.SuppressLint
import android.content.Context
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pGroup
import android.net.wifi.p2p.WifiP2pInfo
import android.net.wifi.p2p.WifiP2pManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class ConnectionHandler(
    private val context: Context,
    private val manager: WifiP2pManager,
    private val channel: WifiP2pManager.Channel
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "ConnectionHandler"
        private const val MAX_CONNECTION_RETRIES = 3
        private const val CONNECTION_TIMEOUT_MS = 10000L
    }

    private var connectionChannel: MethodChannel? = null
    
    // Callback interface to notify SocketHandler about connection info
    var onConnectionInfoAvailable: ((WifiP2pInfo) -> Unit)? = null

    // Track current connection state
    private var isConnecting = false
    private var currentGroupInfo: WifiP2pGroup? = null

    fun setup(messenger: io.flutter.plugin.common.BinaryMessenger) {
        connectionChannel = MethodChannel(messenger, "com.rescuenet/wifi_p2p/connection")
        connectionChannel?.setMethodCallHandler(this)
    }

    @SuppressLint("MissingPermission")
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "connect" -> {
                val address = call.argument<String>("deviceAddress")
                if (address != null) {
                    connect(address, result)
                } else {
                    result.error("INVALID_ARGUMENT", "deviceAddress is null", null)
                }
            }
            "disconnect" -> {
                disconnect(result)
            }
            "removeGroup" -> {
                removeGroup(result)
            }
            "getConnectionInfo" -> {
                requestConnectionInfo(result)
            }
            "getGroupInfo" -> {
                requestGroupInfo(result)
            }
            else -> result.notImplemented()
        }
    }

    @SuppressLint("MissingPermission")
    private fun connect(address: String, result: MethodChannel.Result) {
        if (isConnecting) {
            Log.w(TAG, "Already connecting, ignoring request")
            result.error("BUSY", "Already connecting", null)
            return
        }
        
        Log.d(TAG, "Connecting to device: $address")
        isConnecting = true
        
        val config = WifiP2pConfig().apply {
            deviceAddress = address
            // Let system negotiate group ownership
        }

        attemptConnect(config, result, MAX_CONNECTION_RETRIES)
    }

    @SuppressLint("MissingPermission")
    private fun attemptConnect(config: WifiP2pConfig, result: MethodChannel.Result, retriesLeft: Int) {
        manager.connect(channel, config, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "Connection initiated successfully to ${config.deviceAddress}")
                isConnecting = false
                
                // Wait a moment then get connection info
                Handler(Looper.getMainLooper()).postDelayed({
                    requestConnectionInfoInternal { info ->
                        result.success(mapOf(
                            "success" to true,
                            "groupFormed" to info.groupFormed,
                            "isGroupOwner" to info.isGroupOwner,
                            "groupOwnerAddress" to info.groupOwnerAddress?.hostAddress
                        ))
                    }
                }, 1000)
            }
            override fun onFailure(code: Int) {
                Log.e(TAG, "Connect failed (code: $code, ${getErrorMessage(code)})")
                
                if (retriesLeft > 1 && code == WifiP2pManager.BUSY) {
                    Log.d(TAG, "Retrying connection in 1 second...")
                    Handler(Looper.getMainLooper()).postDelayed({
                        attemptConnect(config, result, retriesLeft - 1)
                    }, 1000)
                } else {
                    isConnecting = false
                    result.error("CONNECT_ERROR", "Failed to connect: ${getErrorMessage(code)}", null)
                }
            }
        })
    }

    @SuppressLint("MissingPermission")
    private fun disconnect(result: MethodChannel.Result) {
        Log.d(TAG, "Cancelling connection...")
        isConnecting = false
        
        manager.cancelConnect(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "Connection cancelled")
                result.success(true)
            }
            override fun onFailure(code: Int) {
                Log.w(TAG, "Failed to cancel connection: $code")
                result.success(false) // Maybe not connecting?
            }
        })
    }

    @SuppressLint("MissingPermission")
    private fun removeGroup(result: MethodChannel.Result) {
        Log.d(TAG, "Removing P2P group...")
        isConnecting = false
        
        manager.removeGroup(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "Group removed")
                currentGroupInfo = null
                result.success(true)
            }
            override fun onFailure(code: Int) {
                Log.w(TAG, "Failed to remove group: $code")
                // Often fails if no group exists, which is fine
                result.success(false)
            }
        })
    }
    
    @SuppressLint("MissingPermission")
    private fun requestConnectionInfo(result: MethodChannel.Result?) {
        requestConnectionInfoInternal { info ->
            result?.success(mapOf(
                "groupFormed" to info.groupFormed,
                "isGroupOwner" to info.isGroupOwner,
                "groupOwnerAddress" to info.groupOwnerAddress?.hostAddress
            ))
        }
    }

    @SuppressLint("MissingPermission")
    private fun requestConnectionInfoInternal(callback: (WifiP2pInfo) -> Unit) {
        manager.requestConnectionInfo(channel) { info ->
            Log.d(TAG, "Connection info: groupFormed=${info.groupFormed}, isGO=${info.isGroupOwner}, goAddr=${info.groupOwnerAddress?.hostAddress}")
            onConnectionInfoAvailable?.invoke(info)
            callback(info)
        }
    }

    @SuppressLint("MissingPermission")
    private fun requestGroupInfo(result: MethodChannel.Result) {
        manager.requestGroupInfo(channel) { group ->
            currentGroupInfo = group
            
            if (group == null) {
                Log.d(TAG, "No group info available")
                result.success(mapOf(
                    "hasGroup" to false
                ))
                return@requestGroupInfo
            }
            
            Log.d(TAG, "Group info: name=${group.networkName}, isGO=${group.isGroupOwner}")
            
            val clients = group.clientList.map { device ->
                mapOf(
                    "deviceName" to (device.deviceName ?: "Unknown"),
                    "deviceAddress" to (device.deviceAddress ?: "")
                )
            }
            
            result.success(mapOf(
                "hasGroup" to true,
                "networkName" to group.networkName,
                "isGroupOwner" to group.isGroupOwner,
                "ownerAddress" to (group.owner?.deviceAddress ?: ""),
                "ownerName" to (group.owner?.deviceName ?: ""),
                "clients" to clients
            ))
        }
    }
    
    // Called from BroadcastReceiver when connection changes
    fun onConnectionChanged() {
        Log.d(TAG, "Connection changed, requesting info...")
        requestConnectionInfoInternal { info ->
            // Also request group info
            manager.requestGroupInfo(channel) { group ->
                currentGroupInfo = group
                Log.d(TAG, "Updated group info after connection change")
            }
        }
    }

    private fun getErrorMessage(code: Int): String {
        return when (code) {
            WifiP2pManager.P2P_UNSUPPORTED -> "P2P_UNSUPPORTED"
            WifiP2pManager.ERROR -> "INTERNAL_ERROR"
            WifiP2pManager.BUSY -> "BUSY"
            WifiP2pManager.NO_SERVICE_REQUESTS -> "NO_SERVICE_REQUESTS"
            else -> "Unknown ($code)"
        }
    }
}
