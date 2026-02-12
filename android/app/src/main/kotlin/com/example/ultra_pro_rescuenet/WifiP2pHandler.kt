package com.example.ultra_pro_rescuenet

import android.annotation.SuppressLint
import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.wifi.p2p.WifiP2pManager
import android.net.wifi.p2p.nsd.WifiP2pDnsSdServiceInfo
import android.net.wifi.p2p.nsd.WifiP2pDnsSdServiceRequest
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import com.example.ultra_pro_rescuenet.utils.DiagnosticUtils
import kotlinx.coroutines.*
import java.util.Timer
import java.util.TimerTask
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.ByteBuffer

class WifiP2pHandler(
    private val context: Context,
    private val manager: WifiP2pManager,
    private val channel: WifiP2pManager.Channel
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val TAG = "WifiP2pHandler"
        private const val SERVICE_NAME = "RescueNet"
        private const val SERVICE_TYPE = "_rescuenet._tcp"
        
        private const val DISCOVERY_REFRESH_INTERVAL_MS = 15000L
        private const val PEER_DISCOVERY_INTERVAL_MS = 20000L
        private const val SERVICE_UPDATE_INTERVAL_MS = 30000L
        
        private const val MAX_RETRY_ATTEMPTS = 3
        private const val INITIAL_RETRY_DELAY_MS = 2000L
    }

    private var eventSink: EventChannel.EventSink? = null
    private var discoveryRefreshTimer: Timer? = null
    private var peerDiscoveryTimer: Timer? = null
    private var serviceUpdateTimer: Timer? = null
    private var socketServer: SocketServerManager? = null
    
    private var isServiceRegistered = false
    private var isDiscoveryActive = false
    private var currentServiceInfo: WifiP2pDnsSdServiceInfo? = null
    private var currentMetadata: Map<String, String> = emptyMap()
    
    private val mainHandler = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    fun setup(messenger: io.flutter.plugin.common.BinaryMessenger) {
        Log.d(TAG, "═══════════════════════════════════")
        Log.d(TAG, "🔧 SETTING UP WIFI P2P HANDLER")
        Log.d(TAG, "═══════════════════════════════════")
        
        val methodChan = MethodChannel(messenger, "com.rescuenet/wifi_p2p/discovery")
        methodChan.setMethodCallHandler(this)

        val eventChan = EventChannel(messenger, "com.rescuenet/wifi_p2p/discovery_events")
        eventChan.setStreamHandler(this)
        
        // Setup DNS-SD listeners early to prevent race conditions
        setupDnsSdListeners()
        
        startSocketServer()
        
        Log.d(TAG, "✅ WifiP2pHandler setup complete")
    }

    private fun startSocketServer() {
        socketServer = SocketServerManager { jsonData ->
            Log.d(TAG, "📥 Packet received from socket, forwarding to Flutter...")
            
            val event = mapOf(
                "type" to "packetReceived",
                "data" to jsonData
            )
            
            mainHandler.post {
                eventSink?.success(event)
            }
        }
        
        socketServer?.start()
        Log.d(TAG, "✅ Socket server started")
    }

    @SuppressLint("MissingPermission")
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        Log.d(TAG, "📞 Method call: ${call.method}")
        
        when (call.method) {
            "startMeshNode" -> {
                val metadata = call.arguments as? Map<String, String> ?: emptyMap()
                startMeshNode(metadata, result)
            }
            
            "updateMetadata" -> {
                val metadata = call.arguments as? Map<String, String> ?: emptyMap()
                updateMetadata(metadata, result)
            }
            
            "stopMeshNode" -> {
                stopMeshNode(result)
            }
            
            "connectAndSend" -> {
                val deviceAddress = call.argument<String>("deviceAddress")
                val packetJson = call.argument<String>("packet")
                
                if (deviceAddress == null || packetJson == null) {
                    result.error("INVALID_ARGS", "Missing deviceAddress or packet", null)
                    return
                }
                
                connectAndSendPacket(deviceAddress, packetJson, result)
            }
            
            "getDiagnostics" -> {
                val diagnostics = DiagnosticUtils.checkWifiP2pReadiness(context)
                result.success(diagnostics)
            }
            
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        Log.d(TAG, "📡 Event stream listener attached")
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        Log.d(TAG, "📡 Event stream listener cancelled")
        eventSink = null
    }

    @SuppressLint("MissingPermission")
    private fun startMeshNode(metadata: Map<String, String>, result: MethodChannel.Result) {
        Log.d(TAG, "═══════════════════════════════════")
        Log.d(TAG, "🚀 STARTING MESH NODE")
        Log.d(TAG, "   Metadata: $metadata")
        Log.d(TAG, "═══════════════════════════════════")
        
        DiagnosticUtils.logDiagnosticInfo(context, TAG)
        
        val diagnostics = DiagnosticUtils.checkWifiP2pReadiness(context)
        if (diagnostics["isP2pReady"] != true) {
            val errorMsg = DiagnosticUtils.getStatusMessage(context)
            Log.e(TAG, "❌ Not ready: $errorMsg")
            mainHandler.post {
                result.error("P2P_NOT_READY", errorMsg, diagnostics)
            }
            return
        }
        

        
        currentMetadata = metadata
        
        // Ensure server is running (restart if it was stopped)
        if (socketServer == null) {
            startSocketServer()
        }
        
        // Step 1: Register service (with retry logic)
        registerServicePersistent(metadata) { serviceSuccess ->
            if (!serviceSuccess) {
                mainHandler.post {
                    result.error("SERVICE_FAILED", "Service registration failed after retries", null)
                }
                return@registerServicePersistent
            }
            
            // Step 2: Start discovery
            startDiscoveryPersistent { discoverySuccess ->
                // Step 3: Start refresh timers
                startAllRefreshTimers()
                
                Log.d(TAG, "═══════════════════════════════════")
                Log.d(TAG, "✅ MESH NODE OPERATIONAL")
                Log.d(TAG, "   Service Registered: $serviceSuccess")
                Log.d(TAG, "   Discovery Active: $discoverySuccess")
                Log.d(TAG, "═══════════════════════════════════")
                
                mainHandler.post {
                    result.success(true)
                }
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun registerServicePersistent(
        metadata: Map<String, String>,
        onComplete: (Boolean) -> Unit
    ) {
        Log.d(TAG, "🔄 Clearing existing local services...")
        
        manager.clearLocalServices(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "✅ Local services cleared, attempting registration...")
                attemptRegisterService(metadata, onComplete, MAX_RETRY_ATTEMPTS)
            }
            override fun onFailure(code: Int) {
                Log.w(TAG, "⚠️ Clear services failed (code: $code), attempting registration anyway...")
                attemptRegisterService(metadata, onComplete, MAX_RETRY_ATTEMPTS)
            }
        })
    }

    @SuppressLint("MissingPermission")
    private fun attemptRegisterService(
        metadata: Map<String, String>,
        onComplete: (Boolean) -> Unit,
        attemptsLeft: Int
    ) {
        if (attemptsLeft <= 0) {
            Log.e(TAG, "❌ Service registration failed after all retry attempts")
            onComplete(false)
            return
        }
        
        Log.d(TAG, "📝 Registering service (attempts left: $attemptsLeft)")
        
        val serviceInfo = WifiP2pDnsSdServiceInfo.newInstance(
            SERVICE_NAME,
            SERVICE_TYPE,
            metadata
        )
        
        currentServiceInfo = serviceInfo
        
        manager.addLocalService(channel, serviceInfo, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "═══════════════════════════════════")
                Log.d(TAG, "✅ SERVICE REGISTERED SUCCESSFULLY")
                Log.d(TAG, "   Name: $SERVICE_NAME")
                Log.d(TAG, "   Type: $SERVICE_TYPE")
                Log.d(TAG, "   Metadata: $metadata")
                Log.d(TAG, "═══════════════════════════════════")
                isServiceRegistered = true
                onComplete(true)
            }
            
            override fun onFailure(code: Int) {
                Log.e(TAG, "❌ addLocalService failed (code: $code), retrying in ${INITIAL_RETRY_DELAY_MS}ms...")
                
                if (attemptsLeft > 1) {
                    mainHandler.postDelayed({
                        attemptRegisterService(metadata, onComplete, attemptsLeft - 1)
                    }, INITIAL_RETRY_DELAY_MS)
                } else {
                    Log.e(TAG, "❌ All retry attempts exhausted")
                    onComplete(false)
                }
            }
        })
    }

    @SuppressLint("MissingPermission")
    private fun startDiscoveryPersistent(onComplete: (Boolean) -> Unit) {
        Log.d(TAG, "🔍 Starting discovery sequence...")
        
        // Re-setup listeners to ensure they're active
        setupDnsSdListeners()
        
        val serviceRequest = WifiP2pDnsSdServiceRequest.newInstance()
        
        manager.addServiceRequest(channel, serviceRequest, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "✅ Service request added")
                
                // Start peer discovery first
                manager.discoverPeers(channel, object : WifiP2pManager.ActionListener {
                    override fun onSuccess() {
                        Log.d(TAG, "✅ Peer discovery started")
                        
                        // Then start service discovery
                        manager.discoverServices(channel, object : WifiP2pManager.ActionListener {
                            override fun onSuccess() {
                                Log.d(TAG, "═══════════════════════════════════")
                                Log.d(TAG, "✅ SERVICE DISCOVERY STARTED")
                                Log.d(TAG, "═══════════════════════════════════")
                                isDiscoveryActive = true
                                onComplete(true)
                            }
                            override fun onFailure(code: Int) {
                                Log.e(TAG, "❌ discoverServices failed (code: $code)")
                                onComplete(false)
                            }
                        })
                    }
                    override fun onFailure(code: Int) {
                        Log.e(TAG, "❌ discoverPeers failed (code: $code)")
                        onComplete(false)
                    }
                })
            }
            override fun onFailure(code: Int) {
                Log.e(TAG, "❌ addServiceRequest failed (code: $code)")
                onComplete(false)
            }
        })
    }

    private fun setupDnsSdListeners() {
        Log.d(TAG, "🎧 Setting up DNS-SD response listeners...")
        
        val serviceListener = WifiP2pManager.DnsSdServiceResponseListener { 
            instanceName, registrationType, srcDevice ->
            
            Log.d(TAG, "═══════════════════════════════════")
            Log.d(TAG, "📡 SERVICE FOUND (Name callback)")
            Log.d(TAG, "   Instance: $instanceName")
            Log.d(TAG, "   Type: $registrationType")
            Log.d(TAG, "   Device: ${srcDevice.deviceName}")
            Log.d(TAG, "   Address: ${srcDevice.deviceAddress}")
            Log.d(TAG, "═══════════════════════════════════")
            
            // CRITICAL FIX: Emit device-found event here too, not just in TXT callback
            // This ensures devices are found even if TXT record is lost/corrupted
            if (instanceName.contains("RescueNet", ignoreCase = true)) {
                val event = mapOf(
                    "type" to "servicesFound",
                    "services" to listOf(
                        mapOf(
                            "deviceName" to (srcDevice.deviceName ?: "Unknown"),
                            "deviceAddress" to (srcDevice.deviceAddress ?: ""),
                            "instanceName" to instanceName,
                            "source" to "serviceCallback"
                        )
                    )
                )
                
                mainHandler.post {
                    eventSink?.success(event)
                }
            }
        }
        
        val txtListener = WifiP2pManager.DnsSdTxtRecordListener { 
            fullDomainName, txtRecordMap, srcDevice ->
            
            Log.d(TAG, "═══════════════════════════════════")
            Log.d(TAG, "📋 TXT RECORD RECEIVED")
            Log.d(TAG, "   Domain: $fullDomainName")
            Log.d(TAG, "   Device: ${srcDevice.deviceName}")
            Log.d(TAG, "   Address: ${srcDevice.deviceAddress}")
            Log.d(TAG, "   Data: $txtRecordMap")
            Log.d(TAG, "═══════════════════════════════════")
            
            if (fullDomainName.lowercase().contains("rescuenet")) {
                val event = mapOf(
                    "type" to "servicesFound",
                    "services" to listOf(
                        txtRecordMap + mapOf(
                            "deviceName" to (srcDevice.deviceName ?: "Unknown"),
                            "deviceAddress" to (srcDevice.deviceAddress ?: ""),
                            "source" to "txtCallback"
                        )
                    )
                )
                
                mainHandler.post {
                    eventSink?.success(event)
                }
            }
        }
        
        manager.setDnsSdResponseListeners(channel, serviceListener, txtListener)
        Log.d(TAG, "✅ DNS-SD listeners registered")
    }

    private fun startAllRefreshTimers() {
        Log.d(TAG, "⏰ Starting refresh timers...")
        
        // Discovery refresh timer
        discoveryRefreshTimer = Timer("DiscoveryRefresh", true).apply {
            scheduleAtFixedRate(object : TimerTask() {
                @SuppressLint("MissingPermission")
                override fun run() {
                    mainHandler.post {
                        if (isDiscoveryActive) {
                            Log.d(TAG, "🔄 Refreshing service discovery...")
                            setupDnsSdListeners()
                            manager.discoverServices(channel, object : WifiP2pManager.ActionListener {
                                override fun onSuccess() {
                                    Log.d(TAG, "✅ Service discovery refresh succeeded")
                                }
                                override fun onFailure(code: Int) {
                                    Log.w(TAG, "⚠️ Service discovery refresh failed (code: $code)")
                                }
                            })
                        }
                    }
                }
            }, DISCOVERY_REFRESH_INTERVAL_MS, DISCOVERY_REFRESH_INTERVAL_MS)
        }
        
        // Peer discovery timer
        peerDiscoveryTimer = Timer("PeerRefresh", true).apply {
            scheduleAtFixedRate(object : TimerTask() {
                @SuppressLint("MissingPermission")
                override fun run() {
                    mainHandler.post {
                        if (isDiscoveryActive) {
                            Log.d(TAG, "🔄 Refreshing peer discovery...")
                            manager.discoverPeers(channel, null)
                        }
                    }
                }
            }, PEER_DISCOVERY_INTERVAL_MS, PEER_DISCOVERY_INTERVAL_MS)
        }
        
        Log.d(TAG, "✅ Refresh timers started")
    }

    @SuppressLint("MissingPermission")
    private fun updateMetadata(metadata: Map<String, String>, result: MethodChannel.Result) {
        Log.d(TAG, "📝 Updating metadata: $metadata")
        
        currentMetadata = metadata
        
        if (!isServiceRegistered) {
            Log.w(TAG, "⚠️ Service not registered, cannot update metadata")
            result.success(false)
            return
        }
        
        manager.clearLocalServices(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                attemptRegisterService(metadata, { success ->
                    mainHandler.post {
                        result.success(success)
                    }
                }, MAX_RETRY_ATTEMPTS)
            }
            override fun onFailure(code: Int) {
                Log.e(TAG, "❌ clearLocalServices failed during metadata update (code: $code)")
                result.success(false)
            }
        })
    }

    @SuppressLint("MissingPermission")
    private fun stopMeshNode(result: MethodChannel.Result) {
        Log.d(TAG, "═══════════════════════════════════")
        Log.d(TAG, "🛑 STOPPING MESH NODE")
        Log.d(TAG, "═══════════════════════════════════")
        
        // Cancel timers
        discoveryRefreshTimer?.cancel()
        discoveryRefreshTimer = null
        peerDiscoveryTimer?.cancel()
        peerDiscoveryTimer = null
        serviceUpdateTimer?.cancel()
        serviceUpdateTimer = null
        
        // Clear service requests
        manager.clearServiceRequests(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "✅ Service requests cleared")
            }
            override fun onFailure(code: Int) {
                Log.w(TAG, "⚠️ clearServiceRequests failed (code: $code)")
            }
        })
        
        // Stop peer discovery
        manager.stopPeerDiscovery(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "✅ Peer discovery stopped")
            }
            override fun onFailure(code: Int) {
                Log.w(TAG, "⚠️ stopPeerDiscovery failed (code: $code)")
            }
        })
        
        // Clear local services
        manager.clearLocalServices(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "✅ Local services cleared")
            }
            override fun onFailure(code: Int) {
                Log.w(TAG, "⚠️ clearLocalServices failed (code: $code)")
            }
        })
        
        isServiceRegistered = false
        isDiscoveryActive = false
        
        Log.d(TAG, "✅ Mesh node stopped")
        result.success(true)
    }

    private fun connectAndSendPacket(
        deviceAddress: String,
        packetJson: String,
        result: MethodChannel.Result
    ) {
        Log.d(TAG, "═══════════════════════════════════")
        Log.d(TAG, "📤 CONNECT AND SEND")
        Log.d(TAG, "   Target: $deviceAddress")
        Log.d(TAG, "   Packet size: ${packetJson.length} chars")
        Log.d(TAG, "═══════════════════════════════════")

        val connectionManager = ConnectionManager(context, manager, channel, scope)

        connectionManager.connect(
            deviceAddress,
            onConnected = { targetIp ->
                Log.d(TAG, "✅ Connected, sending to IP: $targetIp")
                
                scope.launch {
                    try {
                        val socket = Socket()
                        
                        // FIX: Bind to specific P2P interface IP
                        val p2pInterface = java.net.NetworkInterface.getNetworkInterfaces().toList().firstOrNull { iface ->
                            iface.inetAddresses.toList().any { addr -> 
                                addr.hostAddress.startsWith("192.168.49.") && !addr.isLoopbackAddress
                            }
                        }

                        if (p2pInterface != null) {
                            val p2pIp = p2pInterface.inetAddresses.toList().first { it.hostAddress.startsWith("192.168.49.") }
                            Log.d(TAG, "🔗 Binding socket to P2P Interface: ${p2pInterface.name} ($p2pIp)")
                            socket.bind(InetSocketAddress(p2pIp, 0))
                        } else {
                             // Fallback: try binding to Wi-Fi network if P2P interface not found (Android 10+ legacy)
                            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                            val wifiNetwork = cm.allNetworks.firstOrNull { net ->
                                val caps = cm.getNetworkCapabilities(net)
                                caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
                            }
                            
                             if (wifiNetwork != null) {
                                Log.d(TAG, "🔗 Binding socket to Wi-Fi network (Fallback): $wifiNetwork")
                                wifiNetwork.bindSocket(socket)
                             } else {
                                Log.w(TAG, "⚠️ No P2P or Wi-Fi network found to bind socket")
                             }
                        }

                        socket.connect(InetSocketAddress(targetIp, 8888), 10000)
                        socket.soTimeout = 5000

                        val outputStream = DataOutputStream(socket.getOutputStream())
                        val inputStream = DataInputStream(socket.getInputStream())

                        // Send packet size (4 bytes, big-endian)
                        val dataBytes = packetJson.toByteArray(Charsets.UTF_8)
                        val sizeBuffer = ByteBuffer.allocate(4).putInt(dataBytes.size)
                        outputStream.write(sizeBuffer.array())
                        outputStream.write(dataBytes)
                        outputStream.flush()
                        
                        Log.d(TAG, "📤 Sent ${dataBytes.size} bytes, waiting for ACK...")

                        // Wait for ACK
                        val ack = inputStream.readByte()
                        socket.close()

                        if (ack == 0x06.toByte()) {
                            Log.d(TAG, "✅ ACK received, disconnecting...")
                            connectionManager.disconnect {
                                mainHandler.post {
                                    result.success(true)
                                }
                            }
                        } else {
                            Log.e(TAG, "❌ NAK received ($ack)")
                            connectionManager.disconnect {
                                mainHandler.post {
                                    result.error("NAK", "Packet rejected by receiver", null)
                                }
                            }
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ Socket error: ${e.message}", e)
                        connectionManager.disconnect {
                            mainHandler.post {
                                result.error("SOCKET_ERROR", e.message, null)
                            }
                        }
                    }
                }
            },
            onFailure = { error ->
                Log.e(TAG, "❌ Connection failed: $error")
                mainHandler.post {
                    result.error("CONNECTION_FAILED", error, null)
                }
            }
        )
    }

    fun cleanup() {
        Log.d(TAG, "🧹 Cleaning up WifiP2pHandler...")
        
        discoveryRefreshTimer?.cancel()
        discoveryRefreshTimer = null
        peerDiscoveryTimer?.cancel()
        peerDiscoveryTimer = null
        serviceUpdateTimer?.cancel()
        serviceUpdateTimer = null
        
        socketServer?.stop()
        socketServer = null
        
        scope.cancel()
        mainHandler.removeCallbacksAndMessages(null)
        
        Log.d(TAG, "✅ Cleanup complete")
    }
}
