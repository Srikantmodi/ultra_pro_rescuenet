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

        val config = WifiP2pConfig().apply {
            this.deviceAddress = deviceAddress
            groupOwnerIntent = 0
        }

        manager.connect(channel, config, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "✅ Connection initiated, waiting for group info...")

                scope.launch {
                    delay(1000L)
                    requestConnectionInfo(onConnected, onFailure)
                }
            }

            override fun onFailure(code: Int) {
                val error = "Connection failed: ${getErrorMessage(code)}"
                Log.e(TAG, "❌ $error")
                onFailure(error)
            }
        })
    }

    @SuppressLint("MissingPermission")
    private fun requestConnectionInfo(
        onConnected: (String) -> Unit,
        onFailure: (String) -> Unit,
        attempt: Int = 1
    ) {
        val maxAttempts = 15
        
        manager.requestConnectionInfo(channel) { info ->
            if (info == null) {
                if (attempt < maxAttempts) {
                    Log.d(TAG, "⏳ Connection info null, retrying ($attempt/$maxAttempts)...")
                    scope.launch {
                        delay(1000L)
                        requestConnectionInfo(onConnected, onFailure, attempt + 1)
                    }
                } else {
                    Log.e(TAG, "❌ Connection info unavailable after $maxAttempts attempts")
                    onFailure("Connection info unavailable")
                }
                return@requestConnectionInfo
            }

            Log.d(TAG, "📋 Connection Info (Attempt $attempt):")
            Log.d(TAG, "   Group Formed: ${info.groupFormed}")
            Log.d(TAG, "   Is Group Owner: ${info.isGroupOwner}")
            Log.d(TAG, "   Group Owner Address: ${info.groupOwnerAddress?.hostAddress}")

            if (!info.groupFormed) {
                if (attempt < maxAttempts) {
                    Log.d(TAG, "⏳ Group not formed yet, retrying ($attempt/$maxAttempts)...")
                    scope.launch {
                        delay(1000L)
                        requestConnectionInfo(onConnected, onFailure, attempt + 1)
                    }
                } else {
                    Log.e(TAG, "❌ Group not formed after $maxAttempts attempts")
                    onFailure("P2P group not formed")
                }
                return@requestConnectionInfo
            }

            val targetIp = if (info.isGroupOwner) {
                Log.w(TAG, "⚠️ We became group owner unexpectedly")
                "192.168.49.1"
            } else {
                info.groupOwnerAddress?.hostAddress ?: run {
                    Log.e(TAG, "❌ Group owner address is null")
                    onFailure("Group owner address unavailable")
                    return@requestConnectionInfo
                }
            }

            Log.d(TAG, "═══════════════════════════════════")
            Log.d(TAG, "✅ CONNECTED - Target IP: $targetIp")
            Log.d(TAG, "═══════════════════════════════════")

            onConnected(targetIp)
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
                Log.w(TAG, "⚠️ Failed to remove group: ${getErrorMessage(code)}")
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
