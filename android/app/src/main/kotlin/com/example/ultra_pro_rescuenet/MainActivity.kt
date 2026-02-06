package com.example.ultra_pro_rescuenet

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.annotation.SuppressLint
import android.net.wifi.p2p.WifiP2pManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity: FlutterActivity() {
    
    companion object {
        private const val TAG = "RescueNet"
    }
    
    private var wifiP2pHandler: WifiP2pHandler? = null
    private var manager: WifiP2pManager? = null
    private var channel: WifiP2pManager.Channel? = null
    private var receiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        Log.d(TAG, "═══════════════════════════════════")
        Log.d(TAG, "🚀 CONFIGURING FLUTTER ENGINE")
        Log.d(TAG, "═══════════════════════════════════")

        // Initialize Wi-Fi P2P Manager
        manager = getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager
        if (manager == null) {
            Log.e(TAG, "❌ WifiP2pManager not available!")
            return
        }
        
        channel = manager!!.initialize(this, mainLooper, null)
        if (channel == null) {
            Log.e(TAG, "❌ Failed to initialize P2P channel!")
            return
        }
        
        Log.d(TAG, "✅ WifiP2pManager initialized")

        // Setup the main P2P handler (handles mesh operations)
        wifiP2pHandler = WifiP2pHandler(this, manager!!, channel!!)
        wifiP2pHandler?.setup(flutterEngine.dartExecutor.binaryMessenger)
        Log.d(TAG, "✅ WifiP2pHandler setup complete")
        
        // Setup general handler (handles permissions and device info)
        val generalHandler = GeneralHandler(this)
        generalHandler.setup(flutterEngine.dartExecutor.binaryMessenger)
        Log.d(TAG, "✅ GeneralHandler setup complete")
    }
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Register BroadcastReceiver for Wi-Fi P2P state changes
        registerP2pReceiver()
    }
    
    @SuppressLint("MissingPermission")
    private fun registerP2pReceiver() {
        val intentFilter = IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
        }
        
        receiver = object : BroadcastReceiver() {
            @SuppressLint("MissingPermission")
            override fun onReceive(context: Context, intent: Intent) {
                when (intent.action) {
                    WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                        val state = intent.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, -1)
                        val enabled = state == WifiP2pManager.WIFI_P2P_STATE_ENABLED
                        Log.d(TAG, "⚡ P2P State Changed: ${if (enabled) "ENABLED" else "DISABLED"}")
                    }
                    
                    WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> {
                        Log.d(TAG, "⚡ Peers Changed Intent Received")
                        
                        // CRITICAL FIX: Request peers immediately when intent fires
                        manager?.requestPeers(channel) { peers ->
                            Log.d(TAG, "═══════════════════════════════════")
                            Log.d(TAG, "📱 Physical Device List: ${peers.deviceList.size} devices")
                            for (device in peers.deviceList) {
                                Log.d(TAG, "   -> ${device.deviceName} (${device.deviceAddress})")
                            }
                            Log.d(TAG, "═══════════════════════════════════")
                        }
                    }
                    
                    WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                        Log.d(TAG, "⚡ Connection Changed Intent Received")
                        
                        manager?.requestConnectionInfo(channel) { info ->
                            if (info != null) {
                                Log.d(TAG, "   Group Formed: ${info.groupFormed}")
                                Log.d(TAG, "   Is Group Owner: ${info.isGroupOwner}")
                                Log.d(TAG, "   Group Owner Address: ${info.groupOwnerAddress?.hostAddress}")
                            }
                        }
                    }
                    
                    WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION -> {
                        Log.d(TAG, "⚡ This Device Changed Intent Received")
                    }
                }
            }
        }
        
        // Register with appropriate flag for Android 14+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            registerReceiver(receiver, intentFilter, Context.RECEIVER_NOT_EXPORTED)
            Log.d(TAG, "✅ BroadcastReceiver registered (with RECEIVER_NOT_EXPORTED)")
        } else {
            registerReceiver(receiver, intentFilter)
            Log.d(TAG, "✅ BroadcastReceiver registered")
        }
    }

    override fun onDestroy() {
        Log.d(TAG, "🛑 MainActivity onDestroy")
        
        // Cleanup handler
        wifiP2pHandler?.cleanup()
        wifiP2pHandler = null
        
        // Unregister receiver
        try {
            receiver?.let { unregisterReceiver(it) }
            receiver = null
            Log.d(TAG, "✅ BroadcastReceiver unregistered")
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ Error unregistering receiver: ${e.message}")
        }
        
        super.onDestroy()
    }
}
