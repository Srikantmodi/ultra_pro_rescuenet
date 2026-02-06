package com.rescuenet.wifi

import android.annotation.SuppressLint
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pManager
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.rescuenet.utils.PermissionHandler
import com.rescuenet.utils.WifiDirectDiagnostics
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

/**
 * Flutter plugin that bridges the Wi-Fi Direct functionality to Dart.
 *
 * This is the main entry point for all mesh network operations from Flutter.
 * It manages:
 * - Wi-Fi P2P initialization and lifecycle
 * - Service Discovery (broadcasting & discovering)
 * - Socket communication (sending & receiving packets)
 * - Permission handling
 * - Foreground service for background operation
 *
 * All operations are exposed via MethodChannel and EventChannel for
 * bidirectional communication with Flutter.
 */
@SuppressLint("MissingPermission")
class WifiP2pPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, 
    ActivityAware, EventChannel.StreamHandler {
    
    companion object {
        private const val TAG = "WifiP2pPlugin"
        
        // Channel names
        private const val METHOD_CHANNEL = "com.rescuenet/wifi_p2p"
        private const val EVENT_CHANNEL_DISCOVERY = "com.rescuenet/discovery_events"
        private const val EVENT_CHANNEL_PACKETS = "com.rescuenet/packet_events"
        
        // Notification
        private const val NOTIFICATION_CHANNEL_ID = "rescuenet_service"
        private const val NOTIFICATION_ID = 1001
    }

    private var context: Context? = null
    private var activity: Activity? = null
    
    private lateinit var methodChannel: MethodChannel
    private lateinit var discoveryEventChannel: EventChannel
    private lateinit var packetEventChannel: EventChannel
    
    private var discoveryEventSink: EventChannel.EventSink? = null
    private var packetEventSink: EventChannel.EventSink? = null
    
    // Wi-Fi P2P components
    private var wifiP2pManager: WifiP2pManager? = null
    private var wifiP2pChannel: WifiP2pManager.Channel? = null
    
    // Managers
    private var serviceDiscoveryManager: ServiceDiscoveryManager? = null
    private var socketTransportManager: SocketTransportManager? = null
    private var groupNegotiationManager: GroupNegotiationManager? = null
    private var permissionHandler: PermissionHandler? = null
    private var diagnostics: WifiDirectDiagnostics? = null
    
    // Broadcast receiver for Wi-Fi P2P state changes
    private var wifiP2pReceiver: BroadcastReceiver? = null
    
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        
        // Set up method channel
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)
        
        // Set up event channels
        discoveryEventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL_DISCOVERY)
        discoveryEventChannel.setStreamHandler(DiscoveryEventHandler())
        
        packetEventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL_PACKETS)
        packetEventChannel.setStreamHandler(PacketEventHandler())
        
        Log.d(TAG, "Plugin attached to engine")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        discoveryEventChannel.setStreamHandler(null)
        packetEventChannel.setStreamHandler(null)
        cleanup()
        Log.d(TAG, "Plugin detached from engine")
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        initializeWifiP2p()
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
        cleanup()
    }

    /**
     * Initializes Wi-Fi P2P system services.
     */
    private fun initializeWifiP2p() {
        val ctx = context ?: return
        
        wifiP2pManager = ctx.getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager
        wifiP2pChannel = wifiP2pManager?.initialize(ctx, ctx.mainLooper, null)
        
        if (wifiP2pManager != null && wifiP2pChannel != null) {
            // Initialize managers
            serviceDiscoveryManager = ServiceDiscoveryManager(wifiP2pManager!!, wifiP2pChannel!!)
            socketTransportManager = SocketTransportManager()
            groupNegotiationManager = GroupNegotiationManager(wifiP2pManager!!, wifiP2pChannel!!)
            permissionHandler = PermissionHandler(ctx)
            diagnostics = WifiDirectDiagnostics(ctx)
            
            // Register broadcast receiver
            registerWifiP2pReceiver()
            
            Log.d(TAG, "Wi-Fi P2P initialized successfully")
        } else {
            Log.e(TAG, "Failed to initialize Wi-Fi P2P")
        }
    }

    /**
     * Registers the broadcast receiver for Wi-Fi P2P state changes.
     */
    private fun registerWifiP2pReceiver() {
        val ctx = context ?: return
        
        val intentFilter = IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
        }
        
        wifiP2pReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                        val state = intent.getIntExtra(
                            WifiP2pManager.EXTRA_WIFI_STATE,
                            WifiP2pManager.WIFI_P2P_STATE_DISABLED
                        )
                        val enabled = state == WifiP2pManager.WIFI_P2P_STATE_ENABLED
                        Log.d(TAG, "Wi-Fi P2P state changed: enabled=$enabled")
                        sendDiscoveryEvent("wifi_state", mapOf("enabled" to enabled))
                    }
                    WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION -> {
                        val device = intent.getParcelableExtra<WifiP2pDevice>(
                            WifiP2pManager.EXTRA_WIFI_P2P_DEVICE
                        )
                        Log.d(TAG, "This device info: ${device?.deviceName}")
                        sendDiscoveryEvent("device_info", mapOf(
                            "name" to (device?.deviceName ?: ""),
                            "address" to (device?.deviceAddress ?: "")
                        ))
                    }
                }
            }
        }
        
        ctx.registerReceiver(wifiP2pReceiver, intentFilter)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // Initialization
            "initialize" -> handleInitialize(result)
            "checkPermissions" -> handleCheckPermissions(result)
            "requestPermissions" -> handleRequestPermissions(result)
            
            // DUAL-MODE: Unified mesh node operation
            "startMeshNode" -> handleStartMeshNode(call, result)
            "stopMeshNode" -> handleStopMeshNode(result)
            
            // Service Discovery (legacy, still supported)
            "startBroadcasting" -> handleStartBroadcasting(call, result)
            "stopBroadcasting" -> handleStopBroadcasting(result)
            "startDiscovery" -> handleStartDiscovery(result)
            "stopDiscovery" -> handleStopDiscovery(result)
            
            // Socket Transport
            "startServer" -> handleStartServer(result)
            "stopServer" -> handleStopServer(result)
            "sendPacket" -> handleSendPacket(call, result)
            "connectAndSendPacket" -> handleConnectAndSendPacket(call, result)
            
            // Group Management
            "connect" -> handleConnect(call, result)
            "disconnect" -> handleDisconnect(result)
            "removeGroup" -> handleRemoveGroup(result)
            
            // Utility
            "getDeviceInfo" -> handleGetDeviceInfo(result)
            "cleanup" -> handleCleanup(result)
            "runDiagnostics" -> handleRunDiagnostics(result)
            
            else -> result.notImplemented()
        }
    }

    // === INITIALIZATION HANDLERS ===

    private fun handleInitialize(result: MethodChannel.Result) {
        if (wifiP2pManager == null) {
            initializeWifiP2p()
        }
        
        val success = wifiP2pManager != null && wifiP2pChannel != null
        result.success(mapOf(
            "success" to success,
            "message" to if (success) "Initialized" else "Wi-Fi P2P not available"
        ))
    }

    private fun handleCheckPermissions(result: MethodChannel.Result) {
        val handler = permissionHandler
        if (handler == null) {
            result.error("NOT_INITIALIZED", "Permission handler not initialized", null)
            return
        }
        
        val status = handler.getPermissionStatus()
        result.success(mapOf(
            "allGranted" to status.allGranted,
            "hasWifiDirect" to status.hasWifiDirect,
            "missing" to status.missing,
            "androidVersion" to status.androidVersion
        ))
    }

    private fun handleRequestPermissions(result: MethodChannel.Result) {
        val handler = permissionHandler
        val act = activity
        
        if (handler == null || act == null) {
            result.error("NOT_INITIALIZED", "Permission handler or activity not available", null)
            return
        }
        
        val allGranted = handler.requestPermissions(act)
        result.success(mapOf("allGranted" to allGranted))
    }

    // === SERVICE DISCOVERY HANDLERS ===

    private fun handleStartBroadcasting(call: MethodCall, result: MethodChannel.Result) {
        val sdm = serviceDiscoveryManager
        if (sdm == null) {
            result.error("NOT_INITIALIZED", "Service discovery not initialized", null)
            return
        }
        
        val nodeId = call.argument<String>("nodeId") ?: ""
        val metadata = call.argument<Map<String, String>>("metadata") ?: emptyMap()
        
        sdm.startBroadcasting(nodeId, metadata) { success, error ->
            result.success(mapOf("success" to success, "error" to error))
        }
    }

    private fun handleStopBroadcasting(result: MethodChannel.Result) {
        serviceDiscoveryManager?.stopBroadcasting {
            result.success(mapOf("success" to true))
        }
    }

    private fun handleStartDiscovery(result: MethodChannel.Result) {
        val sdm = serviceDiscoveryManager
        if (sdm == null) {
            result.error("NOT_INITIALIZED", "Service discovery not initialized", null)
            return
        }
        
        sdm.startDiscovery(
            onDiscovered = { deviceName, metadata, signal ->
                sendDiscoveryEvent("service_found", mapOf(
                    "deviceName" to deviceName,
                    "metadata" to metadata,
                    "signalStrength" to signal
                ))
            },
            onError = { code, message ->
                sendDiscoveryEvent("discovery_error", mapOf(
                    "code" to code,
                    "message" to message
                ))
            }
        )
        
        result.success(mapOf("success" to true))
    }

    private fun handleStopDiscovery(result: MethodChannel.Result) {
        serviceDiscoveryManager?.stopDiscovery()
        result.success(mapOf("success" to true))
    }

    // === SOCKET TRANSPORT HANDLERS ===

    private fun handleStartServer(result: MethodChannel.Result) {
        val stm = socketTransportManager
        if (stm == null) {
            result.error("NOT_INITIALIZED", "Socket transport not initialized", null)
            return
        }
        
        stm.startServer(
            onPacketReceived = { senderIp, packet ->
                sendPacketEvent("packet_received", mapOf(
                    "senderIp" to senderIp,
                    "packet" to packet
                ))
            },
            onError = { exception ->
                sendPacketEvent("server_error", mapOf(
                    "message" to (exception.message ?: "Unknown error")
                ))
            }
        )
        
        result.success(mapOf("success" to true))
    }

    private fun handleStopServer(result: MethodChannel.Result) {
        socketTransportManager?.stopServer()
        result.success(mapOf("success" to true))
    }

    private fun handleSendPacket(call: MethodCall, result: MethodChannel.Result) {
        val stm = socketTransportManager
        if (stm == null) {
            result.error("NOT_INITIALIZED", "Socket transport not initialized", null)
            return
        }
        
        val targetIp = call.argument<String>("targetIp") ?: ""
        val packetJson = call.argument<String>("packetJson") ?: ""
        
        scope.launch {
            val transmissionResult = stm.sendPacket(targetIp, packetJson)
            
            withContext(Dispatchers.Main) {
                when (transmissionResult) {
                    is TransmissionResult.Success -> {
                        result.success(mapOf(
                            "success" to true,
                            "targetIp" to transmissionResult.targetIp
                        ))
                    }
                    is TransmissionResult.Failure -> {
                        result.success(mapOf(
                            "success" to false,
                            "targetIp" to transmissionResult.targetIp,
                            "error" to transmissionResult.error.name,
                            "message" to transmissionResult.message
                        ))
                    }
                }
            }
        }
    }

    // === GROUP MANAGEMENT HANDLERS ===

    private fun handleConnect(call: MethodCall, result: MethodChannel.Result) {
        val gnm = groupNegotiationManager
        if (gnm == null) {
            result.error("NOT_INITIALIZED", "Group negotiation not initialized", null)
            return
        }
        
        val deviceAddress = call.argument<String>("deviceAddress") ?: ""
        
        gnm.connectToDevice(deviceAddress) { success, info, error ->
            result.success(mapOf(
                "success" to success,
                "groupOwnerAddress" to (info?.groupOwnerAddress?.hostAddress ?: ""),
                "isGroupOwner" to (info?.isGroupOwner ?: false),
                "error" to error
            ))
        }
    }

    private fun handleDisconnect(result: MethodChannel.Result) {
        groupNegotiationManager?.disconnect { success, error ->
            result.success(mapOf("success" to success, "error" to error))
        }
    }

    private fun handleRemoveGroup(result: MethodChannel.Result) {
        // CRITICAL: Called before every new connection to kill "zombie groups"
        groupNegotiationManager?.removeGroup { success, error ->
            result.success(mapOf("success" to success, "error" to error))
        }
    }

    // === UTILITY HANDLERS ===

    private fun handleGetDeviceInfo(result: MethodChannel.Result) {
        // Return basic device info
        result.success(mapOf(
            "deviceName" to (Build.MODEL ?: "Unknown"),
            "androidVersion" to Build.VERSION.SDK_INT,
            "isP2pSupported" to (wifiP2pManager != null)
        ))
    }

    private fun handleCleanup(result: MethodChannel.Result) {
        cleanup()
        result.success(mapOf("success" to true))
    }

    private fun handleRunDiagnostics(result: MethodChannel.Result) {
        val diag = diagnostics
        if (diag == null) {
            result.error("NOT_INITIALIZED", "Diagnostics not initialized", null)
            return
        }
        
        val results = diag.runFullDiagnostics()
        result.success(diag.getResultsAsJson(results))
    }

    // === DUAL-MODE HANDLERS ===

    private fun handleStartMeshNode(call: MethodCall, result: MethodChannel.Result) {
        val sdm = serviceDiscoveryManager
        val stm = socketTransportManager
        if (sdm == null || stm == null) {
            result.error("NOT_INITIALIZED", "Managers not initialized", null)
            return
        }

        val nodeId = call.argument<String>("nodeId") ?: ""
        val metadata = call.argument<Map<String, String>>("metadata") ?: emptyMap()

        Log.d(TAG, "Starting mesh node with nodeId: $nodeId")

        // Start socket server first (for receiving packets)
        stm.startServer(
            onPacketReceived = { senderIp, packet ->
                sendPacketEvent("packet_received", mapOf(
                    "senderIp" to senderIp,
                    "packet" to packet
                ))
            },
            onError = { exception ->
                sendPacketEvent("server_error", mapOf(
                    "message" to (exception.message ?: "Unknown error")
                ))
            }
        )

        // Start mesh node in dual-mode (advertising + discovery)
        sdm.startMeshNode(
            nodeId = nodeId,
            metadata = metadata,
            onDiscovered = { deviceName, discoveredMetadata, signal ->
                sendDiscoveryEvent("service_found", mapOf(
                    "deviceName" to deviceName,
                    "metadata" to discoveredMetadata,
                    "signalStrength" to signal
                ))
            },
            onError = { code, message ->
                sendDiscoveryEvent("discovery_error", mapOf(
                    "code" to code,
                    "message" to message
                ))
            },
            onComplete = { success, error ->
                result.success(mapOf(
                    "success" to success,
                    "error" to error
                ))
            }
        )
    }

    private fun handleStopMeshNode(result: MethodChannel.Result) {
        val sdm = serviceDiscoveryManager
        val stm = socketTransportManager

        sdm?.stopMeshNode {
            stm?.stopServer()
            result.success(mapOf("success" to true))
        }
    }

    private fun handleConnectAndSendPacket(call: MethodCall, result: MethodChannel.Result) {
        val gnm = groupNegotiationManager
        val stm = socketTransportManager
        if (gnm == null || stm == null) {
            result.error("NOT_INITIALIZED", "Managers not initialized", null)
            return
        }

        val deviceAddress = call.argument<String>("deviceAddress") ?: ""
        val packetJson = call.argument<String>("packetJson") ?: ""

        if (deviceAddress.isBlank() || packetJson.isBlank()) {
            result.error("INVALID_ARGS", "deviceAddress and packetJson are required", null)
            return
        }

        Log.d(TAG, "═══════════════════════════════════")
        Log.d(TAG, "CONNECT AND SEND PACKET")
        Log.d(TAG, "   Target: $deviceAddress")
        Log.d(TAG, "   Packet size: ${packetJson.length} bytes")
        Log.d(TAG, "═══════════════════════════════════")

        // Step 1: Connect to the device
        gnm.connectToDevice(deviceAddress) { connectSuccess, connectionInfo, connectError ->
            if (!connectSuccess || connectionInfo == null) {
                Log.e(TAG, "❌ Connection failed: $connectError")
                result.success(mapOf(
                    "success" to false,
                    "error" to "CONNECTION_FAILED",
                    "message" to (connectError ?: "Failed to connect")
                ))
                return@connectToDevice
            }

            // Step 2: Get the target IP (group owner's address)
            val targetIp = connectionInfo.groupOwnerAddress?.hostAddress
            if (targetIp == null) {
                Log.e(TAG, "❌ No group owner address available")
                gnm.disconnect { _, _ -> }
                result.success(mapOf(
                    "success" to false,
                    "error" to "NO_TARGET_IP",
                    "message" to "Group owner address not available"
                ))
                return@connectToDevice
            }

            Log.d(TAG, "✅ Connected! Target IP: $targetIp")

            // Step 3: Send the packet via socket
            scope.launch {
                val transmissionResult = stm.sendPacket(targetIp, packetJson)

                // Step 4: Disconnect regardless of result
                gnm.disconnect { _, _ ->
                    Log.d(TAG, "Disconnected after send attempt")
                }

                withContext(Dispatchers.Main) {
                    when (transmissionResult) {
                        is TransmissionResult.Success -> {
                            Log.d(TAG, "✅ Packet sent successfully to $targetIp")
                            result.success(mapOf(
                                "success" to true,
                                "targetIp" to targetIp
                            ))
                        }
                        is TransmissionResult.Failure -> {
                            Log.e(TAG, "❌ Packet send failed: ${transmissionResult.message}")
                            result.success(mapOf(
                                "success" to false,
                                "error" to transmissionResult.error.name,
                                "message" to transmissionResult.message
                            ))
                        }
                    }
                }
            }
        }
    }

    // === EVENT SENDERS ===

    private fun sendDiscoveryEvent(type: String, data: Map<String, Any?>) {
        val event = mapOf("type" to type, "data" to data)
        discoveryEventSink?.success(event)
    }

    private fun sendPacketEvent(type: String, data: Map<String, Any?>) {
        val event = mapOf("type" to type, "data" to data)
        packetEventSink?.success(event)
    }

    // === EVENT HANDLERS ===

    private inner class DiscoveryEventHandler : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            discoveryEventSink = events
        }

        override fun onCancel(arguments: Any?) {
            discoveryEventSink = null
        }
    }

    private inner class PacketEventHandler : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            packetEventSink = events
        }

        override fun onCancel(arguments: Any?) {
            packetEventSink = null
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        // Default implementation for StreamHandler
    }

    override fun onCancel(arguments: Any?) {
        // Default implementation for StreamHandler
    }

    /**
     * Cleans up all resources.
     */
    private fun cleanup() {
        Log.d(TAG, "Cleaning up")
        
        serviceDiscoveryManager?.cleanup()
        socketTransportManager?.cleanup()
        groupNegotiationManager?.cleanup()
        
        wifiP2pReceiver?.let {
            try {
                context?.unregisterReceiver(it)
            } catch (e: Exception) {
                // Ignore if not registered
            }
        }
        
        scope.cancel()
    }
}
