package com.example.ultra_pro_rescuenet

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.wifi.p2p.WifiP2pManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import android.util.Log

class MainActivity : FlutterActivity() {
    private lateinit var manager: WifiP2pManager
    private lateinit var channel: WifiP2pManager.Channel
    private lateinit var receiver: BroadcastReceiver
    
    // Handlers
    private lateinit var discoveryHandler: WifiP2pHandler
    private lateinit var connectionHandler: ConnectionHandler
    private lateinit var socketHandler: SocketHandler

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Note: MeshService is now started from Flutter side (GeneralHandler) 
        // after permissions are confirmed granted. 
        // Use "startService" method channel.
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        manager = getSystemService(Context.WIFI_P2P_SERVICE) as WifiP2pManager
        channel = manager.initialize(this, mainLooper, null)
        
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        
        // Initialize Handlers
        discoveryHandler = WifiP2pHandler(this, manager, channel)
        connectionHandler = ConnectionHandler(this, manager, channel)
        socketHandler = SocketHandler()
        val generalHandler = GeneralHandler(this)
        
        // Setup MethodChannels
        discoveryHandler.setup(messenger)
        connectionHandler.setup(messenger)
        socketHandler.setup(messenger)
        generalHandler.setup(messenger)
        
        // Link Connection info to Socket/UI
        connectionHandler.onConnectionInfoAvailable = { info ->
            // For now, no specific action needed, but could notify socket handler if needed
            Log.d("MainActivity", "Connection Info: ${info.groupOwnerAddress}")
        }
    }

    override fun onResume() {
        super.onResume()
        receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                when(intent.action) {
                    WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                         // Determine if Wifi P2P mode is enabled or not
                         val state = intent.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, -1)
                         if (state == WifiP2pManager.WIFI_P2P_STATE_ENABLED) {
                             Log.d("P2P", "P2P Enabled")
                         } else {
                             Log.d("P2P", "P2P Disabled")
                         }
                    }
                    WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> {
                        // The peer list has changed
                        // We rely on service discovery usually, but can also trigger peer request
                    }
                    WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                        // Connection state changed
                        connectionHandler.onConnectionChanged()
                    }
                    WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION -> {
                        // This device's details changed
                    }
                }
            }
        }
        
        val intentFilter = IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
        }
        
        registerReceiver(receiver, intentFilter)
    }

    override fun onPause() {
        super.onPause()
        unregisterReceiver(receiver)
    }
}
