package com.example.ultra_pro_rescuenet

import android.annotation.SuppressLint
import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.wifi.p2p.WifiP2pManager
import android.net.wifi.p2p.nsd.WifiP2pDnsSdServiceInfo
import android.net.wifi.p2p.nsd.WifiP2pDnsSdServiceRequest
import android.net.wifi.WifiManager
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
import java.util.zip.CRC32

class WifiP2pHandler(
    private val context: Context,
    private val manager: WifiP2pManager,
    private val channel: WifiP2pManager.Channel
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val TAG = "WifiP2pHandler"
        private const val SERVICE_NAME = "RescueNet"
        // NOTE: Android WifiP2p DNS-SD API expects "_name._tcp" WITHOUT the .local. suffix.
        // The framework appends .local. internally. Passing .local. here causes the type-filtered
        // service request to never match registered services — silence all callbacks.
        private const val SERVICE_TYPE = "_rescuenet._tcp"
        
        private const val DISCOVERY_REFRESH_INTERVAL_MS = 60000L  // 60s — DNS-SD needs time to propagate
        private const val SERVICE_UPDATE_INTERVAL_MS = 60000L
        
        private const val MAX_RETRY_ATTEMPTS = 3
        private const val INITIAL_RETRY_DELAY_MS = 2000L
    }

    private var eventSink: EventChannel.EventSink? = null
    private var discoveryRefreshTimer: Timer? = null
    // peerDiscoveryTimer REMOVED: BUG-01 fix — standalone discoverPeers() kills service discovery
    private var serviceUpdateTimer: Timer? = null
    private var socketServer: SocketServerManager? = null
    
    private var isServiceRegistered = false
    private var isDiscoveryActive = false
    // Guard: only one connectAndSend can be in-flight at a time
    private var isConnecting = false
    // Cooldown: track last send time per device address to avoid rapid reconnects
    private val connectionCooldowns = mutableMapOf<String, Long>()
    // FIX: Reduced from 5000ms → 1500ms. The Dart relay orchestrator now
    // gates packet sends at 6s intervals. The native cooldown only needs to
    // prevent accidental double-taps, not throttle relay storms.
    private val COOLDOWN_MS = 1500L
    // FIX: Reusable connection manager — keeps P2P group alive between sends
    // to avoid repeated "Invitation to connect" dialogs.
    private var activeConnectionManager: ConnectionManager? = null
    private var delayedDisconnectRunnable: Runnable? = null
    private val GROUP_KEEP_ALIVE_MS = 45_000L  // 45 seconds before auto-disconnect
    // Guard: prevent duplicate startMeshNode calls from Flutter
    private var isMeshNodeRunning = false
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

    /**
     * FIX B-7: Returns real Wi-Fi RSSI in dBm.
     * Wi-Fi Direct doesn't expose per-peer RSSI, but the underlying 
     * Wi-Fi interface RSSI is a reasonable proxy — when P2P is active, 
     * the chipset uses the same radio. Falls back to -70 (moderate) if unavailable.
     */
    @Suppress("DEPRECATION")
    private fun getWifiRssi(): Int {
        return try {
            val wifiManager = context.applicationContext
                .getSystemService(Context.WIFI_SERVICE) as WifiManager
            val connectionInfo = wifiManager.connectionInfo
            val rssi = connectionInfo.rssi
            // Sanity check: valid RSSI typically between -100 and 0
            if (rssi in -100..0) rssi else -70
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ Could not read RSSI: ${e.message}")
            -70
        }
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

                // Prevent concurrent connection attempts — only one at a time
                if (isConnecting) {
                    Log.w(TAG, "⚠️ connectAndSend skipped: connection already in progress")
                    result.error("BUSY", "Connection already in progress", null)
                    return
                }
                isConnecting = true
                
                connectAndSendPacket(deviceAddress, packetJson, result)
            }
            
            "getDiagnostics" -> {
                val diagnostics = DiagnosticUtils.checkWifiP2pReadiness(context)
                result.success(diagnostics)
            }

            // FIX B-7: Return real Wi-Fi RSSI instead of hardcoded -50
            "getSignalStrength" -> {
                result.success(getWifiRssi())
            }

            // FIX D-4: Allow Flutter to adjust connection timeout at runtime
            "setConnectionTimeout" -> {
                val attempts = call.arguments as? Int ?: 10
                ConnectionManager.setConnectionTimeout(attempts)
                result.success(true)
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
        
        // FIX DUPLICATE-START: If mesh node is already running, just update metadata
        // and return success. Flutter can call startMeshNode multiple times (e.g. on
        // screen re-entry or BLoC re-init). Re-registering service and discovery from
        // scratch is wasteful and briefly interrupts DNS-SD scans.
        if (isMeshNodeRunning) {
            Log.w(TAG, "⚠️ Mesh node already running — updating metadata only")
            currentMetadata = metadata
            updateMetadata(metadata, result)
            return
        }
        
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
                
                isMeshNodeRunning = true
                
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
        
        // FIX BUG-01: Correct sequence is clearServiceRequests → addServiceRequest → discoverServices.
        // discoverServices() internally triggers peer discovery.
        // NEVER call discoverPeers() before discoverServices() — it holds the scan slot
        // and causes discoverServices() to fail with BUSY (error code 2).
        
        // FIX A-6: Always clear service requests before re-adding to prevent duplicates
        manager.clearServiceRequests(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "✅ Service requests cleared")
                addServiceRequestAndDiscover(onComplete)
            }
            override fun onFailure(code: Int) {
                Log.w(TAG, "⚠️ clearServiceRequests failed (code: $code), proceeding anyway...")
                addServiceRequestAndDiscover(onComplete)
            }
        })
    }
    
    @SuppressLint("MissingPermission")
    private fun addServiceRequestAndDiscover(onComplete: (Boolean) -> Unit) {
        // Use unfiltered DNS-SD request so ALL services are received.
        // We already filter by instanceName/domain in the DnsSdServiceResponseListener
        // and DnsSdTxtRecordListener callbacks. Type-filtered requests have been observed
        // to silently drop records on some Android versions when the type string is not an
        // exact match to what the framework stored internally.
        val serviceRequest = WifiP2pDnsSdServiceRequest.newInstance()
        
        manager.addServiceRequest(channel, serviceRequest, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "✅ Service request added (unfiltered, filtering in callback)")
                
                // FIX BUG-01: Go directly to discoverServices — NO discoverPeers() call!
                // discoverServices() internally triggers the peer scan needed for DNS-SD.
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
                        isDiscoveryActive = false
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

    @SuppressLint("MissingPermission")
    private fun startAllRefreshTimers() {
        Log.d(TAG, "⏰ Starting consolidated discovery refresh timer (${DISCOVERY_REFRESH_INTERVAL_MS}ms)...")

        // FIX TIMER-LEAK: Always cancel the existing timer before creating a new one.
        // Without this, every call to startMeshNode() stacks a new timer on top of the
        // old one. Two overlapping 30s timers fire every ~10s and constantly call
        // clearServiceRequests(), aborting DNS-SD before it can ever deliver results.
        discoveryRefreshTimer?.cancel()
        discoveryRefreshTimer = null
        serviceUpdateTimer?.cancel()
        serviceUpdateTimer = null

        // FIX A-3: Only ONE timer. peerDiscoveryTimer is REMOVED entirely.
        // FIX A-4: Do NOT call setupDnsSdListeners() in the refresh — listeners are
        //          set once in setup() and must NOT be overwritten mid-discovery.
        // FIX D-1: Single consolidated timer replaces all three old timers.
        // FIX DISCOVERY: On refresh, call discoverServices() ONLY — do NOT clear and
        //                re-add the service request. clearServiceRequests kills the active
        //                DNS-SD session mid-scan. The service request is already in place;
        //                just nudge the scan engine again. Full reset only on failure.
        discoveryRefreshTimer = Timer("DiscoveryRefresh", true).apply {
            scheduleAtFixedRate(object : TimerTask() {
                @SuppressLint("MissingPermission")
                override fun run() {
                    mainHandler.post {
                        if (isDiscoveryActive) {
                            Log.d(TAG, "🔄 Refreshing service discovery (lightweight nudge)...")
                            // Lightweight refresh: just call discoverServices() again.
                            // The service request is already registered; no need to clear it.
                            // This keeps DNS-SD alive without resetting the scan session.
                            manager.discoverServices(channel, object : WifiP2pManager.ActionListener {
                                override fun onSuccess() {
                                    Log.d(TAG, "✅ Discovery nudge succeeded")
                                }
                                override fun onFailure(code: Int) {
                                    Log.w(TAG, "⚠️ Discovery nudge failed (code: $code) — doing full reset")
                                    // Only on failure do a full clear → add → discover reset
                                    addServiceRequestAndDiscover { success ->
                                        Log.d(TAG, "🔄 Full reset: ${if (success) "✅" else "❌"}")
                                    }
                                }
                            })
                        }
                    }
                }
            }, DISCOVERY_REFRESH_INTERVAL_MS, DISCOVERY_REFRESH_INTERVAL_MS)
        }

        Log.d(TAG, "✅ Refresh timer started (consolidated, ${DISCOVERY_REFRESH_INTERVAL_MS}ms interval)")
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
        isConnecting = false
        isMeshNodeRunning = false
        
        // FIX: Tear down any active P2P group and cancel delayed disconnect
        delayedDisconnectRunnable?.let { mainHandler.removeCallbacks(it) }
        delayedDisconnectRunnable = null
        activeConnectionManager?.disconnect {
            Log.d(TAG, "✅ Active P2P group torn down on stop")
        }
        activeConnectionManager = null
        
        Log.d(TAG, "✅ Mesh node stopped")
        result.success(true)
    }

    private fun connectAndSendPacket(
        deviceAddress: String,
        packetJson: String,
        result: MethodChannel.Result
    ) {
        // FIX 3.3: Connection cooldown — prevent rapid reconnects to the same device
        val now = System.currentTimeMillis()
        val lastSendTime = connectionCooldowns[deviceAddress] ?: 0L
        if (now - lastSendTime < COOLDOWN_MS) {
            val remaining = COOLDOWN_MS - (now - lastSendTime)
            Log.w(TAG, "⏳ Cooldown active for $deviceAddress (${remaining}ms left), skipping")
            isConnecting = false
            mainHandler.post {
                result.error("COOLDOWN", "Connection cooldown active ($remaining ms remaining)", null)
            }
            return
        }
        connectionCooldowns[deviceAddress] = now

        Log.d(TAG, "═══════════════════════════════════")
        Log.d(TAG, "📤 CONNECT AND SEND")
        Log.d(TAG, "   Target: $deviceAddress")
        Log.d(TAG, "   Packet size: ${packetJson.length} chars")
        Log.d(TAG, "═══════════════════════════════════")

        // FIX: Reuse existing ConnectionManager to keep P2P group alive.
        // Cancel any pending delayed-disconnect since we're about to use the group.
        delayedDisconnectRunnable?.let { mainHandler.removeCallbacks(it) }
        delayedDisconnectRunnable = null

        val connectionManager = activeConnectionManager
            ?: ConnectionManager(context, manager, channel, scope).also {
                activeConnectionManager = it
            }

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

                        // FIX D-8: Send packet with CRC32 integrity check.
                        // Wire format: [4-byte size][4-byte CRC32][data]
                        val dataBytes = packetJson.toByteArray(Charsets.UTF_8)
                        val crc = CRC32()
                        crc.update(dataBytes)
                        val crcValue = crc.value.toInt()

                        val header = ByteBuffer.allocate(8)
                            .putInt(dataBytes.size)
                            .putInt(crcValue)
                        outputStream.write(header.array())
                        outputStream.write(dataBytes)
                        outputStream.flush()
                        
                        Log.d(TAG, "📤 Sent ${dataBytes.size} bytes, waiting for ACK...")

                        // Wait for ACK
                        val ack = inputStream.readByte()
                        socket.close()

                        if (ack == 0x06.toByte()) {
                            Log.d(TAG, "✅ ACK received — keeping P2P group alive for reuse")
                            isConnecting = false
                            ensureSocketServerRunning()
                            // FIX: Schedule delayed disconnect instead of immediate teardown.
                            // This keeps the P2P group alive so subsequent sends to the
                            // same device reuse it — avoiding the invitation dialog.
                            scheduleDelayedDisconnect()
                            mainHandler.post {
                                result.success(true)
                            }
                        } else {
                            Log.e(TAG, "❌ NAK received ($ack)")
                            forceDisconnectAndCleanup(connectionManager) {
                                mainHandler.post {
                                    result.error("NAK", "Packet rejected by receiver", null)
                                }
                            }
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ Socket error: ${e.message}", e)
                        forceDisconnectAndCleanup(connectionManager) {
                            mainHandler.post {
                                result.error("SOCKET_ERROR", e.message, null)
                            }
                        }
                    }
                }
            },
            onFailure = { error ->
                Log.e(TAG, "❌ Connection failed: $error")
                forceDisconnectAndCleanup(connectionManager) {
                    mainHandler.post {
                        result.error("CONNECTION_FAILED", error, null)
                    }
                }
            }
        )
    }

    /**
     * Schedule a delayed disconnect — keeps the P2P group alive for GROUP_KEEP_ALIVE_MS
     * so subsequent sends can reuse it without triggering the invitation dialog.
     */
    private fun scheduleDelayedDisconnect() {
        delayedDisconnectRunnable?.let { mainHandler.removeCallbacks(it) }
        val runnable = Runnable {
            Log.d(TAG, "⏰ Keep-alive expired — tearing down idle P2P group")
            activeConnectionManager?.disconnect {
                activeConnectionManager = null
                ensureSocketServerRunning()
                restartDiscoveryAfterSend()
            } ?: run {
                activeConnectionManager = null
            }
        }
        delayedDisconnectRunnable = runnable
        mainHandler.postDelayed(runnable, GROUP_KEEP_ALIVE_MS)
    }

    /**
     * Immediate disconnect + cleanup after errors (NAK, socket error, connection failure).
     * Resets the active connection manager so the next send starts fresh.
     */
    private fun forceDisconnectAndCleanup(connectionManager: ConnectionManager, onDone: () -> Unit) {
        delayedDisconnectRunnable?.let { mainHandler.removeCallbacks(it) }
        delayedDisconnectRunnable = null
        activeConnectionManager = null
        connectionManager.disconnect {
            isConnecting = false
            ensureSocketServerRunning()
            restartDiscoveryAfterSend()
            onDone()
        }
    }

    /**
     * FIX RELAY-1.2: Lightweight discovery nudge after connect-and-send.
     *
     * The old code (FIX D-5) did a FULL reset: clearServiceRequests → addServiceRequest
     * → discoverServices. That nuked the entire DNS-SD session, causing a 10-30 second
     * blackout where the node sees ZERO neighbors. This is the primary reason why the
     * second relay attempt fails — the relay node is blind when the next SOS arrives.
     *
     * New approach: just call discoverServices() again. The service request is already
     * registered from startMeshNode(). This is the same lightweight pattern used by the
     * consolidated refresh timer, which has proven reliable. Only falls back to a full
     * reset if the lightweight nudge fails.
     */
    @SuppressLint("MissingPermission")
    private fun restartDiscoveryAfterSend() {
        if (!isDiscoveryActive) return
        
        mainHandler.postDelayed({
            Log.d(TAG, "🔄 Lightweight discovery nudge after send...")
            manager.discoverServices(channel, object : WifiP2pManager.ActionListener {
                override fun onSuccess() {
                    Log.d(TAG, "✅ Post-send discovery nudge succeeded")
                }
                override fun onFailure(code: Int) {
                    Log.w(TAG, "⚠️ Post-send nudge failed (code: $code) — doing full reset")
                    // Only on failure do a full clear → add → discover reset
                    addServiceRequestAndDiscover { success ->
                        Log.d(TAG, "🔄 Post-send full reset: ${if (success) "✅" else "❌"}")
                    }
                }
            })
        }, 1500) // 1.5 second delay to let P2P channel stabilize after disconnect
    }

    /**
     * FIX RELAY-2.3: Ensures the socket server is still alive after P2P group teardown.
     *
     * When a P2P group is removed (after connectAndSendPacket), the ServerSocket may
     * become invalid if it was accidentally bound to a P2P interface (old bug) or if
     * the OS closed it. This method checks and restarts if needed.
     *
     * With FIX RELAY-1.1, the server binds to 0.0.0.0 and should survive group
     * teardown. This is a defense-in-depth measure.
     */
    private fun ensureSocketServerRunning() {
        if (socketServer == null || !socketServer!!.isAlive) {
            Log.w(TAG, "⚠️ Socket server not alive after disconnect — restarting")
            socketServer?.stop()
            startSocketServer()
        }
    }

    fun cleanup() {
        Log.d(TAG, "🧹 Cleaning up WifiP2pHandler...")
        
        discoveryRefreshTimer?.cancel()
        discoveryRefreshTimer = null
        serviceUpdateTimer?.cancel()
        serviceUpdateTimer = null
        
        socketServer?.stop()
        socketServer = null
        
        scope.cancel()
        mainHandler.removeCallbacksAndMessages(null)
        
        Log.d(TAG, "✅ Cleanup complete")
    }
}
