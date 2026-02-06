package com.rescuenet.wifi

import android.annotation.SuppressLint
import android.net.wifi.p2p.WifiP2pManager
import android.net.wifi.p2p.nsd.WifiP2pDnsSdServiceInfo
import android.net.wifi.p2p.nsd.WifiP2pDnsSdServiceRequest
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.util.Timer
import java.util.TimerTask

/**
 * Manages Wi-Fi Direct Service Discovery (DNS-SD) for the mesh network.
 *
 * This is the "Radar" of the Control Plane - it broadcasts our node's
 * metadata and discovers nearby nodes WITHOUT forming direct connections.
 *
 * **Critical Implementation Notes:**
 * 
 * 1. DNS-SD is FRAGILE on Android. The addLocalService() call often fails
 *    silently. We MUST implement a retry loop with exponential backoff.
 *
 * 2. To UPDATE metadata (e.g., GPS changed), you must:
 *    - removeLocalService()
 *    - addLocalService() with new data
 *
 * 3. Service discovery runs passively, reading TXT records that nearby
 *    devices broadcast every 30 seconds.
 *
 * @param manager The WifiP2pManager instance
 * @param channel The WifiP2pManager.Channel
 */
@SuppressLint("MissingPermission")
class ServiceDiscoveryManager(
    private val manager: WifiP2pManager,
    private val channel: WifiP2pManager.Channel
) {
    companion object {
        private const val TAG = "ServiceDiscoveryManager"
        
        // Service type for RescueNet mesh network
        const val SERVICE_TYPE = "_rescuenet._tcp"
        
        // Instance name prefix
        const val SERVICE_INSTANCE_PREFIX = "RescueNet_"
        
        // Maximum retry attempts for DNS-SD operations
        const val MAX_RETRIES = 5
        
        // Initial retry delay in milliseconds
        const val INITIAL_RETRY_DELAY_MS = 1500L
        
        // Delay after clearing services before adding new ones
        const val CLEAR_SERVICE_DELAY_MS = 500L
        
        // DUAL-MODE: Refresh intervals for persistent operation
        // Android kills discovery after ~120s, so we refresh proactively
        const val DISCOVERY_REFRESH_INTERVAL_MS = 15000L  // 15 seconds
        const val PEER_DISCOVERY_INTERVAL_MS = 20000L     // 20 seconds  
        const val SERVICE_UPDATE_INTERVAL_MS = 30000L     // 30 seconds
        
        // TXT record keys (abbreviated to minimize packet size)
        const val KEY_ID = "id"          // Node ID
        const val KEY_BATTERY = "bat"    // Battery percentage
        const val KEY_INTERNET = "net"   // Has internet (1/0)
        const val KEY_LATITUDE = "lat"   // GPS latitude
        const val KEY_LONGITUDE = "lng"  // GPS longitude
        const val KEY_SIGNAL = "sig"     // Signal strength
        const val KEY_TRIAGE = "tri"     // Triage level (n/g/y/r)
        const val KEY_ROLE = "rol"       // Role (s/r/g/i)
        const val KEY_RELAY = "rel"      // Available for relay (1/0)
    }

    private val handler = Handler(Looper.getMainLooper())
    private var currentServiceInfo: WifiP2pDnsSdServiceInfo? = null
    private var serviceRequest: WifiP2pDnsSdServiceRequest? = null
    private var isDiscovering = false
    
    // DUAL-MODE: Refresh timers for persistent operation
    private var discoveryRefreshTimer: Timer? = null
    private var peerDiscoveryTimer: Timer? = null
    private var serviceUpdateTimer: Timer? = null
    private var currentMetadata: Map<String, String> = emptyMap()
    private var currentNodeId: String = ""

    // Callback interfaces
    private var onServiceDiscovered: ((String, Map<String, String>, Int) -> Unit)? = null
    private var onDiscoveryError: ((Int, String) -> Unit)? = null

    /**
     * Starts broadcasting our node's metadata via DNS-SD TXT records.
     *
     * This implements the retry loop hack for DNS-SD stability.
     *
     * @param nodeId Unique identifier for this node
     * @param metadata Map of metadata to broadcast
     * @param callback Called with success/failure result
     */
    fun startBroadcasting(
        nodeId: String,
        metadata: Map<String, String>,
        callback: (Boolean, String?) -> Unit
    ) {
        Log.d(TAG, "Starting broadcast for node: $nodeId")
        
        // First, clear any existing service using the more reliable clearLocalServices
        stopBroadcasting {
            // Create the service info
            val instanceName = "$SERVICE_INSTANCE_PREFIX$nodeId"
            val serviceInfo = WifiP2pDnsSdServiceInfo.newInstance(
                instanceName,
                SERVICE_TYPE,
                metadata
            )
            
            // CRITICAL FIX: Add delay after clearing to let Android framework settle
            handler.postDelayed({
                // Register with retry loop
                registerServiceSafely(serviceInfo, 0) { success, error ->
                    if (success) {
                        currentServiceInfo = serviceInfo
                        Log.d(TAG, "Successfully broadcasting service: $instanceName")
                    }
                    callback(success, error)
                }
            }, CLEAR_SERVICE_DELAY_MS)
        }
    }

    /**
     * Updates the broadcast metadata.
     *
     * Since DNS-SD doesn't support updating TXT records in place,
     * we must remove and re-add the service.
     *
     * @param nodeId Node identifier
     * @param metadata Updated metadata map
     * @param callback Called with success/failure result
     */
    fun updateMetadata(
        nodeId: String,
        metadata: Map<String, String>,
        callback: (Boolean, String?) -> Unit
    ) {
        Log.d(TAG, "Updating metadata for node: $nodeId")
        
        // Remove existing service first
        stopBroadcasting {
            // Re-register with new metadata
            startBroadcasting(nodeId, metadata, callback)
        }
    }

    /**
     * Registers a local service with retry logic.
     *
     * This is the "DNS-SD Stability Hack" - Android's addLocalService()
     * frequently fails silently. We retry up to MAX_RETRIES times with
     * exponential backoff.
     *
     * @param serviceInfo The service to register
     * @param attempt Current attempt number (0-based)
     * @param callback Called with success/failure result
     */
    private fun registerServiceSafely(
        serviceInfo: WifiP2pDnsSdServiceInfo,
        attempt: Int,
        callback: (Boolean, String?) -> Unit
    ) {
        Log.d(TAG, "Attempting to register service (attempt ${attempt + 1}/$MAX_RETRIES)")
        
        manager.addLocalService(channel, serviceInfo, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "Service registered successfully on attempt ${attempt + 1}")
                callback(true, null)
            }

            override fun onFailure(reason: Int) {
                val errorMsg = getErrorMessage(reason)
                Log.w(TAG, "Service registration failed: $errorMsg (attempt ${attempt + 1})")
                
                if (attempt < MAX_RETRIES - 1) {
                    // Retry with exponential backoff
                    val delay = INITIAL_RETRY_DELAY_MS * (1 shl attempt)
                    Log.d(TAG, "Retrying in ${delay}ms...")
                    
                    handler.postDelayed({
                        registerServiceSafely(serviceInfo, attempt + 1, callback)
                    }, delay)
                } else {
                    Log.e(TAG, "Service registration failed after $MAX_RETRIES attempts")
                    callback(false, "Registration failed after $MAX_RETRIES attempts: $errorMsg")
                }
            }
        })
    }

    /**
     * Stops broadcasting our service.
     *
     * @param callback Called when service is removed (or if none existed)
     */
    fun stopBroadcasting(callback: () -> Unit = {}) {
        Log.d(TAG, "Stopping broadcast (clearing all local services)")
        
        // CRITICAL FIX: Use clearLocalServices() instead of removeLocalService()
        // This is more reliable and clears ALL local services
        manager.clearLocalServices(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "All local services cleared successfully")
                currentServiceInfo = null
                callback()
            }

            override fun onFailure(reason: Int) {
                Log.w(TAG, "Failed to clear local services: ${getErrorMessage(reason)}")
                // Continue anyway - the service might not have been properly registered
                currentServiceInfo = null
                callback()
            }
        })
    }

    /**
     * Starts discovering nearby services.
     *
     * @param onDiscovered Called when a service is found (deviceName, metadata, signalStrength)
     * @param onError Called when discovery fails
     */
    fun startDiscovery(
        onDiscovered: (String, Map<String, String>, Int) -> Unit,
        onError: (Int, String) -> Unit
    ) {
        if (isDiscovering) {
            Log.d(TAG, "Discovery already running")
            return
        }
        
        Log.d(TAG, "Starting service discovery")
        
        this.onServiceDiscovered = onDiscovered
        this.onDiscoveryError = onError
        
        // Set up the DNS-SD response listeners
        setupResponseListeners()
        
        // Create and add service request
        serviceRequest = WifiP2pDnsSdServiceRequest.newInstance()
        
        manager.addServiceRequest(channel, serviceRequest!!, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "Service request added successfully")
                startDiscoverServices()
            }

            override fun onFailure(reason: Int) {
                val error = getErrorMessage(reason)
                Log.e(TAG, "Failed to add service request: $error")
                onError(reason, error)
            }
        })
    }

    /**
     * Sets up the DNS-SD TXT record and service response listeners.
     */
    private fun setupResponseListeners() {
        // Listener for TXT record data
        val txtListener = WifiP2pManager.DnsSdTxtRecordListener { fullDomain, record, device ->
            Log.d(TAG, "TXT record received from ${device.deviceName}: $record")
            
            // Estimate signal strength from device (not directly available, use placeholder)
            val signalStrength = -50 // Default placeholder - actual implementation would vary
            
            onServiceDiscovered?.invoke(device.deviceName, record, signalStrength)
        }
        
        // Listener for service instance availability
        val serviceListener = WifiP2pManager.DnsSdServiceResponseListener { instanceName, _, device ->
            Log.d(TAG, "Service found: $instanceName from ${device.deviceName}")
        }
        
        manager.setDnsSdResponseListeners(channel, serviceListener, txtListener)
    }

    /**
     * Starts the actual discovery process after request is added.
     */
    private fun startDiscoverServices() {
        manager.discoverServices(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "Service discovery initiated successfully")
                isDiscovering = true
            }

            override fun onFailure(reason: Int) {
                val error = getErrorMessage(reason)
                Log.e(TAG, "Failed to start service discovery: $error")
                isDiscovering = false
                onDiscoveryError?.invoke(reason, error)
            }
        })
    }

    /**
     * Stops service discovery.
     */
    fun stopDiscovery() {
        if (!isDiscovering) {
            return
        }
        
        Log.d(TAG, "Stopping service discovery")
        
        serviceRequest?.let { request ->
            manager.removeServiceRequest(channel, request, object : WifiP2pManager.ActionListener {
                override fun onSuccess() {
                    Log.d(TAG, "Service request removed successfully")
                }

                override fun onFailure(reason: Int) {
                    Log.w(TAG, "Failed to remove service request: ${getErrorMessage(reason)}")
                }
            })
        }
        
        serviceRequest = null
        isDiscovering = false
        onServiceDiscovered = null
        onDiscoveryError = null
    }

    /**
     * Creates the metadata map for broadcasting.
     *
     * @param nodeId Unique node identifier
     * @param batteryLevel Battery percentage (0-100)
     * @param hasInternet Whether node has internet connectivity
     * @param latitude GPS latitude
     * @param longitude GPS longitude
     * @param signalStrength Wi-Fi signal strength in dBm
     * @param triageLevel Triage level (none/green/yellow/red)
     * @param role Current role (sender/relay/goal/idle)
     * @param availableForRelay Whether accepting relay connections
     */
    fun createMetadataMap(
        nodeId: String,
        batteryLevel: Int,
        hasInternet: Boolean,
        latitude: Double,
        longitude: Double,
        signalStrength: Int = -50,
        triageLevel: String = "none",
        role: String = "idle",
        availableForRelay: Boolean = true
    ): Map<String, String> {
        return mapOf(
            KEY_ID to nodeId,
            KEY_BATTERY to batteryLevel.toString(),
            KEY_INTERNET to if (hasInternet) "1" else "0",
            KEY_LATITUDE to String.format("%.6f", latitude),
            KEY_LONGITUDE to String.format("%.6f", longitude),
            KEY_SIGNAL to signalStrength.toString(),
            KEY_TRIAGE to triageLevel.take(1), // First char: n/g/y/r
            KEY_ROLE to role.take(1), // First char: s/r/g/i
            KEY_RELAY to if (availableForRelay) "1" else "0"
        )
    }

    /**
     * Checks if service discovery is currently running.
     */
    fun isDiscoveryActive(): Boolean = isDiscovering

    /**
     * Checks if we're currently broadcasting a service.
     */
    fun isBroadcasting(): Boolean = currentServiceInfo != null

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
        stopAllRefreshTimers()
        stopDiscovery()
        stopBroadcasting()
        handler.removeCallbacksAndMessages(null)
    }

    // ═══════════════════════════════════════════════════════════════════
    // DUAL-MODE OPERATION METHODS
    // ═══════════════════════════════════════════════════════════════════

    /**
     * MAIN METHOD: Starts the mesh node in dual-mode (advertising + discovery).
     * 
     * This replaces separate startBroadcasting() and startDiscovery() calls
     * with a unified method that runs BOTH simultaneously.
     */
    fun startMeshNode(
        nodeId: String,
        metadata: Map<String, String>,
        onDiscovered: (String, Map<String, String>, Int) -> Unit,
        onError: (Int, String) -> Unit,
        onComplete: (Boolean, String?) -> Unit
    ) {
        Log.d(TAG, "═══════════════════════════════════════════════════════")
        Log.d(TAG, "🚀 STARTING MESH NODE (DUAL MODE)")
        Log.d(TAG, "   Node ID: $nodeId")
        Log.d(TAG, "   Metadata: $metadata")
        Log.d(TAG, "═══════════════════════════════════════════════════════")

        currentNodeId = nodeId
        currentMetadata = metadata
        this.onServiceDiscovered = onDiscovered
        this.onDiscoveryError = onError

        // Step 1: Register service (advertising) - DON'T touch discovery
        startBroadcasting(nodeId, metadata) { serviceSuccess, serviceError ->
            if (!serviceSuccess) {
                Log.e(TAG, "❌ Service registration failed: $serviceError")
                onComplete(false, serviceError)
                return@startBroadcasting
            }

            Log.d(TAG, "✅ Service registered, now starting discovery...")

            // Step 2: Start discovery (scanning) - DON'T touch service
            startDiscovery(onDiscovered, onError)

            // Step 3: Start all refresh timers for persistent operation
            startAllRefreshTimers()

            Log.d(TAG, "═══════════════════════════════════════════════════════")
            Log.d(TAG, "✅ MESH NODE FULLY OPERATIONAL")
            Log.d(TAG, "   📡 Advertising: YES")
            Log.d(TAG, "   🔍 Discovering: YES")
            Log.d(TAG, "═══════════════════════════════════════════════════════")

            onComplete(true, null)
        }
    }

    /**
     * Stops the mesh node completely.
     */
    fun stopMeshNode(callback: () -> Unit = {}) {
        Log.d(TAG, "Stopping mesh node...")

        stopAllRefreshTimers()
        stopDiscovery()
        stopBroadcasting {
            Log.d(TAG, "✅ Mesh node stopped")
            callback()
        }
    }

    /**
     * Starts all refresh timers for continuous dual-mode operation.
     */
    private fun startAllRefreshTimers() {
        stopAllRefreshTimers()

        // Timer 1: Service Discovery Refresh (every 15s)
        discoveryRefreshTimer = Timer("DiscoveryRefresh", true).apply {
            scheduleAtFixedRate(object : TimerTask() {
                override fun run() {
                    if (isDiscovering) {
                        Log.d(TAG, "🔄 Refreshing service discovery...")

                        // Re-setup listeners (in case they were lost)
                        handler.post { setupResponseListeners() }

                        manager.discoverServices(channel, object : WifiP2pManager.ActionListener {
                            override fun onSuccess() {
                                Log.d(TAG, "✅ Service discovery refreshed")
                            }
                            override fun onFailure(code: Int) {
                                Log.w(TAG, "⚠️ Service discovery refresh failed: ${getErrorMessage(code)}")
                            }
                        })
                    }
                }
            }, DISCOVERY_REFRESH_INTERVAL_MS, DISCOVERY_REFRESH_INTERVAL_MS)
        }

        // Timer 2: Peer Discovery Refresh (every 20s)
        peerDiscoveryTimer = Timer("PeerDiscoveryRefresh", true).apply {
            scheduleAtFixedRate(object : TimerTask() {
                override fun run() {
                    if (isDiscovering) {
                        Log.d(TAG, "🔄 Refreshing peer discovery...")
                        manager.discoverPeers(channel, object : WifiP2pManager.ActionListener {
                            override fun onSuccess() {
                                Log.d(TAG, "✅ Peer discovery refreshed")
                            }
                            override fun onFailure(code: Int) {
                                Log.w(TAG, "⚠️ Peer discovery refresh failed: ${getErrorMessage(code)}")
                            }
                        })
                    }
                }
            }, PEER_DISCOVERY_INTERVAL_MS, PEER_DISCOVERY_INTERVAL_MS)
        }

        // Timer 3: Service Re-registration (every 30s) to keep service alive
        serviceUpdateTimer = Timer("ServiceUpdate", true).apply {
            scheduleAtFixedRate(object : TimerTask() {
                override fun run() {
                    if (currentServiceInfo != null) {
                        Log.d(TAG, "🔄 Re-registering service to keep alive...")

                        manager.addLocalService(channel, currentServiceInfo, object : WifiP2pManager.ActionListener {
                            override fun onSuccess() {
                                Log.d(TAG, "✅ Service re-registered")
                            }
                            override fun onFailure(code: Int) {
                                Log.w(TAG, "⚠️ Service re-registration failed: ${getErrorMessage(code)} - attempting full re-register...")
                                // On failure, try full re-registration
                                if (currentNodeId.isNotEmpty() && currentMetadata.isNotEmpty()) {
                                    handler.post {
                                        startBroadcasting(currentNodeId, currentMetadata) { _, _ -> }
                                    }
                                }
                            }
                        })
                    }
                }
            }, SERVICE_UPDATE_INTERVAL_MS, SERVICE_UPDATE_INTERVAL_MS)
        }

        Log.d(TAG, "✅ All refresh timers started (discovery: ${DISCOVERY_REFRESH_INTERVAL_MS}ms, peer: ${PEER_DISCOVERY_INTERVAL_MS}ms, service: ${SERVICE_UPDATE_INTERVAL_MS}ms)")
    }

    /**
     * Stops all refresh timers.
     */
    private fun stopAllRefreshTimers() {
        discoveryRefreshTimer?.cancel()
        discoveryRefreshTimer = null

        peerDiscoveryTimer?.cancel()
        peerDiscoveryTimer = null

        serviceUpdateTimer?.cancel()
        serviceUpdateTimer = null

        Log.d(TAG, "All refresh timers stopped")
    }
}

