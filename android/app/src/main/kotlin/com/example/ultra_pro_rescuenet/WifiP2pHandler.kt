package com.example.ultra_pro_rescuenet

import android.annotation.SuppressLint
import android.content.Context
import android.net.wifi.p2p.WifiP2pManager
import android.net.wifi.p2p.nsd.WifiP2pDnsSdServiceInfo
import android.net.wifi.p2p.nsd.WifiP2pDnsSdServiceRequest
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Timer
import java.util.TimerTask

class WifiP2pHandler(
    private val context: Context,
    private val manager: WifiP2pManager,
    private val channel: WifiP2pManager.Channel
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val TAG = "WifiP2pHandler"
        private const val SERVICE_NAME = "RescueNet"
        
        // CRITICAL FIX: Proper DNS-SD service type format
        private const val SERVICE_TYPE = "_rescuenet._tcp"
        
        private const val MAX_RETRY_ATTEMPTS = 5
        private const val DISCOVERY_REFRESH_INTERVAL_MS = 120000L // 2 minutes
        private const val CLEAR_SERVICE_DELAY_MS = 1000L // Increased delay
        private const val INITIAL_RETRY_DELAY_MS = 2000L
    }

    private var eventSink: EventChannel.EventSink? = null
    private var discoveryRefreshTimer: Timer? = null
    private var isServiceRegistered = false
    private var isDiscoveryActive = false
    private var currentServiceInfo: WifiP2pDnsSdServiceInfo? = null

    fun setup(messenger: io.flutter.plugin.common.BinaryMessenger) {
        val methodChan = MethodChannel(messenger, "com.rescuenet/wifi_p2p/discovery")
        methodChan.setMethodCallHandler(this)

        val eventChan = EventChannel(messenger, "com.rescuenet/wifi_p2p/discovery_events")
        eventChan.setStreamHandler(this)
    }

    @SuppressLint("MissingPermission")
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startDiscovery" -> {
                startDiscovery(result)
            }
            "stopDiscovery" -> {
                stopDiscovery(result)
            }
            "registerService" -> {
                val metadata = call.arguments as? Map<String, String> ?: emptyMap()
                registerService(metadata, result)
            }
            "unregisterService" -> {
                unregisterService(result)
            }
            "refreshDiscovery" -> {
                refreshDiscovery(result)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    @SuppressLint("MissingPermission")
    private fun registerService(metadata: Map<String, String>, result: MethodChannel.Result) {
        Log.d(TAG, "═══════════════════════════════════")
        Log.d(TAG, "REGISTER SERVICE CALLED")
        Log.d(TAG, "Metadata: $metadata")
        Log.d(TAG, "═══════════════════════════════════")
        
        // CRITICAL: Run diagnostics FIRST
        DiagnosticUtils.logDiagnosticInfo(context, TAG)
        
        val diagnostics = DiagnosticUtils.checkWifiP2pReadiness(context)
        if (diagnostics["isP2pReady"] != true) {
            val errorMsg = DiagnosticUtils.getStatusMessage(context)
            Log.e(TAG, "❌ Wi-Fi P2P not ready: $errorMsg")
            Handler(Looper.getMainLooper()).post {
                result.error("P2P_NOT_READY", errorMsg, diagnostics)
            }
            return
        }
        
        // CRITICAL FIX: STOP ALL DISCOVERY FIRST
        // You CANNOT have discovery running while registering service
        Log.d(TAG, "Step 1: Stopping ALL discovery operations...")
        
        stopAllDiscovery {
            Log.d(TAG, "Step 2: All discovery stopped, now clearing services...")
            
            // Clear existing services
            manager.clearLocalServices(channel, object : WifiP2pManager.ActionListener {
                override fun onSuccess() {
                    Log.d(TAG, "✅ Cleared existing services")
                    isServiceRegistered = false
                    
                    // Wait before registering
                    Handler(Looper.getMainLooper()).postDelayed({
                        Log.d(TAG, "Step 3: Creating service info...")
                        
                        val serviceInfo = WifiP2pDnsSdServiceInfo.newInstance(
                            SERVICE_NAME,
                            SERVICE_TYPE,  // Using fixed service type
                            metadata
                        )
                        currentServiceInfo = serviceInfo
                        
                        Log.d(TAG, "Step 4: Attempting to add service...")
                        attemptAddService(serviceInfo, result, MAX_RETRY_ATTEMPTS, INITIAL_RETRY_DELAY_MS)
                        
                    }, CLEAR_SERVICE_DELAY_MS)
                }
                
                override fun onFailure(code: Int) {
                    Log.w(TAG, "⚠️ Failed to clear services (${getErrorMessage(code)}), continuing anyway...")
                    
                    Handler(Looper.getMainLooper()).postDelayed({
                        val serviceInfo = WifiP2pDnsSdServiceInfo.newInstance(
                            SERVICE_NAME,
                            SERVICE_TYPE,
                            metadata
                        )
                        currentServiceInfo = serviceInfo
                        
                        attemptAddService(serviceInfo, result, MAX_RETRY_ATTEMPTS, INITIAL_RETRY_DELAY_MS)
                    }, CLEAR_SERVICE_DELAY_MS)
                }
            })
        }
    }

    @SuppressLint("MissingPermission")
    private fun stopAllDiscovery(onComplete: () -> Unit) {
        // Stop service discovery
        manager.clearServiceRequests(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "✅ Service requests cleared")
                
                // Stop peer discovery
                manager.stopPeerDiscovery(channel, object : WifiP2pManager.ActionListener {
                    override fun onSuccess() {
                        Log.d(TAG, "✅ Peer discovery stopped")
                        isDiscoveryActive = false
                        stopDiscoveryRefreshTimer()
                        onComplete()
                    }
                    override fun onFailure(code: Int) {
                        Log.w(TAG, "⚠️ Failed to stop peer discovery: ${getErrorMessage(code)}")
                        isDiscoveryActive = false
                        stopDiscoveryRefreshTimer()
                        onComplete() // Continue anyway
                    }
                })
            }
            override fun onFailure(code: Int) {
                Log.w(TAG, "⚠️ Failed to clear service requests: ${getErrorMessage(code)}")
                
                // Still try to stop peer discovery
                manager.stopPeerDiscovery(channel, object : WifiP2pManager.ActionListener {
                    override fun onSuccess() {
                        Log.d(TAG, "✅ Peer discovery stopped")
                        isDiscoveryActive = false
                        stopDiscoveryRefreshTimer()
                        onComplete()
                    }
                    override fun onFailure(peerCode: Int) {
                        Log.w(TAG, "⚠️ Failed to stop peer discovery: ${getErrorMessage(peerCode)}")
                        isDiscoveryActive = false
                        stopDiscoveryRefreshTimer()
                        onComplete() // Continue anyway
                    }
                })
            }
        })
    }

    @SuppressLint("MissingPermission")
    private fun attemptAddService(
        serviceInfo: WifiP2pDnsSdServiceInfo, 
        result: MethodChannel.Result, 
        attemptsLeft: Int,
        delayMs: Long
    ) {
        Log.d(TAG, "───────────────────────────────────")
        Log.d(TAG, "Attempt ${MAX_RETRY_ATTEMPTS - attemptsLeft + 1}/$MAX_RETRY_ATTEMPTS")
        Log.d(TAG, "Service: $SERVICE_NAME")
        Log.d(TAG, "Type: $SERVICE_TYPE")
        Log.d(TAG, "───────────────────────────────────")
        
        manager.addLocalService(channel, serviceInfo, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "═══════════════════════════════════")
                Log.d(TAG, "✅✅✅ SERVICE REGISTERED SUCCESS ✅✅✅")
                Log.d(TAG, "═══════════════════════════════════")
                isServiceRegistered = true
                
                Handler(Looper.getMainLooper()).post {
                    result.success(true)
                }
            }
            
            override fun onFailure(code: Int) {
                val errorMsg = getErrorMessage(code)
                Log.e(TAG, "❌ addLocalService FAILED: $errorMsg")
                
                if (attemptsLeft > 1) {
                    val nextDelay = minOf(delayMs * 2, 10000L)
                    Log.w(TAG, "⏳ Retrying in ${nextDelay}ms... (${attemptsLeft - 1} attempts left)")
                    
                    Handler(Looper.getMainLooper()).postDelayed({
                        // Clear and retry
                        manager.clearLocalServices(channel, object : WifiP2pManager.ActionListener {
                            override fun onSuccess() {
                                isServiceRegistered = false
                                Handler(Looper.getMainLooper()).postDelayed({
                                    attemptAddService(serviceInfo, result, attemptsLeft - 1, nextDelay)
                                }, 500L)
                            }
                            override fun onFailure(clearCode: Int) {
                                Handler(Looper.getMainLooper()).postDelayed({
                                    attemptAddService(serviceInfo, result, attemptsLeft - 1, nextDelay)
                                }, 500L)
                            }
                        })
                    }, delayMs)
                } else {
                    Log.e(TAG, "═══════════════════════════════════")
                    Log.e(TAG, "❌❌❌ ALL RETRIES EXHAUSTED ❌❌❌")
                    Log.e(TAG, "Final error: $errorMsg")
                    Log.e(TAG, "═══════════════════════════════════")
                    
                    Handler(Looper.getMainLooper()).post {
                        result.error(
                            "ADD_SERVICE_ERROR", 
                            "Failed after $MAX_RETRY_ATTEMPTS attempts: $errorMsg",
                            mapOf(
                                "errorCode" to code,
                                "errorMessage" to errorMsg,
                                "serviceType" to SERVICE_TYPE,
                                "serviceName" to SERVICE_NAME
                            )
                        )
                    }
                }
            }
        })
    }

    @SuppressLint("MissingPermission")
    private fun startDiscovery(result: MethodChannel.Result) {
        Log.d(TAG, "═══════════════════════════════════")
        Log.d(TAG, "START DISCOVERY CALLED")
        Log.d(TAG, "Service registered: $isServiceRegistered")
        Log.d(TAG, "═══════════════════════════════════")
        
        // Note: Instead of blocking, we now try to run both.
        // Some devices support simultaneous service + discovery, some don't.
        // We'll try discovery anyway and handle failure gracefully.
        
        if (isServiceRegistered) {
            Log.w(TAG, "⚠️ Service is registered. Trying discovery anyway (may work on some devices)...")
        }
        
        setupListeners()
        
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
                                Log.d(TAG, "✅ Service discovery started")
                                isDiscoveryActive = true
                                startDiscoveryRefreshTimer()
                                result.success(true)
                            }
                            override fun onFailure(code: Int) {
                                Log.e(TAG, "❌ Service discovery failed: ${getErrorMessage(code)}")
                                // If service is registered and discovery fails, try time-sliced approach
                                if (isServiceRegistered && code == WifiP2pManager.BUSY) {
                                    Log.w(TAG, "⏳ Trying time-sliced discovery (pause service briefly)...")
                                    tryTimeSlicedDiscovery(result)
                                } else {
                                    result.error("DISCOVERY_ERROR", getErrorMessage(code), null)
                                }
                            }
                        })
                    }
                    override fun onFailure(code: Int) {
                        Log.w(TAG, "⚠️ Peer discovery failed: ${getErrorMessage(code)}")
                        // Try service discovery anyway
                        manager.discoverServices(channel, object : WifiP2pManager.ActionListener {
                            override fun onSuccess() {
                                Log.d(TAG, "✅ Service discovery started (without peer)")
                                isDiscoveryActive = true
                                startDiscoveryRefreshTimer()
                                result.success(true)
                            }
                            override fun onFailure(svcCode: Int) {
                                Log.e(TAG, "❌ Service discovery failed: ${getErrorMessage(svcCode)}")
                                if (isServiceRegistered && svcCode == WifiP2pManager.BUSY) {
                                    Log.w(TAG, "⏳ Trying time-sliced discovery...")
                                    tryTimeSlicedDiscovery(result)
                                } else {
                                    result.error("DISCOVERY_ERROR", getErrorMessage(svcCode), null)
                                }
                            }
                        })
                    }
                })
            }
            override fun onFailure(code: Int) {
                Log.e(TAG, "❌ Failed to add service request: ${getErrorMessage(code)}")
                if (isServiceRegistered && code == WifiP2pManager.BUSY) {
                    Log.w(TAG, "⏳ Trying time-sliced discovery...")
                    tryTimeSlicedDiscovery(result)
                } else {
                    result.error("ADD_REQUEST_ERROR", getErrorMessage(code), null)
                }
            }
        })
    }
    
    /**
     * Time-sliced discovery: Temporarily pause service, run discovery scan, then re-register.
     * This allows discovery on devices that can't do both simultaneously.
     */
    @SuppressLint("MissingPermission")
    private fun tryTimeSlicedDiscovery(result: MethodChannel.Result) {
        Log.d(TAG, "═══════════════════════════════════")
        Log.d(TAG, "TIME-SLICED DISCOVERY MODE")
        Log.d(TAG, "Temporarily pausing service for discovery...")
        Log.d(TAG, "═══════════════════════════════════")
        
        // Save current service info for re-registration
        val savedServiceInfo = currentServiceInfo
        
        // Clear local services temporarily
        manager.clearLocalServices(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "✅ Service paused for discovery")
                isServiceRegistered = false
                
                // Now start discovery
                val serviceRequest = WifiP2pDnsSdServiceRequest.newInstance()
                manager.addServiceRequest(channel, serviceRequest, object : WifiP2pManager.ActionListener {
                    override fun onSuccess() {
                        manager.discoverServices(channel, object : WifiP2pManager.ActionListener {
                            override fun onSuccess() {
                                Log.d(TAG, "✅ Discovery started (time-sliced mode)")
                                isDiscoveryActive = true
                                startDiscoveryRefreshTimer()
                                
                                // Schedule service re-registration after discovery window
                                Handler(Looper.getMainLooper()).postDelayed({
                                    if (savedServiceInfo != null) {
                                        Log.d(TAG, "⏰ Re-registering service after discovery window...")
                                        reRegisterServiceAfterDiscovery(savedServiceInfo)
                                    }
                                }, 30000L) // 30 second discovery window
                                
                                result.success(true)
                            }
                            override fun onFailure(code: Int) {
                                Log.e(TAG, "❌ Time-sliced discovery failed: ${getErrorMessage(code)}")
                                // Try to re-register service even if discovery failed
                                if (savedServiceInfo != null) {
                                    reRegisterServiceAfterDiscovery(savedServiceInfo)
                                }
                                result.error("DISCOVERY_ERROR", getErrorMessage(code), null)
                            }
                        })
                    }
                    override fun onFailure(code: Int) {
                        Log.e(TAG, "❌ Failed to add service request in time-sliced mode: ${getErrorMessage(code)}")
                        if (savedServiceInfo != null) {
                            reRegisterServiceAfterDiscovery(savedServiceInfo)
                        }
                        result.error("DISCOVERY_ERROR", getErrorMessage(code), null)
                    }
                })
            }
            override fun onFailure(code: Int) {
                Log.e(TAG, "❌ Failed to pause service for discovery: ${getErrorMessage(code)}")
                result.error("DISCOVERY_ERROR", "Cannot pause service: ${getErrorMessage(code)}", null)
            }
        })
    }
    
    @SuppressLint("MissingPermission")
    private fun reRegisterServiceAfterDiscovery(serviceInfo: WifiP2pDnsSdServiceInfo) {
        Log.d(TAG, "Re-registering service after discovery...")
        
        // First stop discovery
        manager.clearServiceRequests(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                isDiscoveryActive = false
                stopDiscoveryRefreshTimer()
                
                // Now re-register service
                manager.addLocalService(channel, serviceInfo, object : WifiP2pManager.ActionListener {
                    override fun onSuccess() {
                        Log.d(TAG, "✅ Service re-registered after discovery")
                        isServiceRegistered = true
                        currentServiceInfo = serviceInfo
                    }
                    override fun onFailure(code: Int) {
                        Log.e(TAG, "❌ Failed to re-register service: ${getErrorMessage(code)}")
                        // Don't fail silently - the service is now down
                    }
                })
            }
            override fun onFailure(code: Int) {
                Log.w(TAG, "⚠️ Failed to clear service requests: ${getErrorMessage(code)}")
                // Try to re-register anyway
                manager.addLocalService(channel, serviceInfo, object : WifiP2pManager.ActionListener {
                    override fun onSuccess() {
                        Log.d(TAG, "✅ Service re-registered after discovery")
                        isServiceRegistered = true
                        currentServiceInfo = serviceInfo
                    }
                    override fun onFailure(addCode: Int) {
                        Log.e(TAG, "❌ Failed to re-register service: ${getErrorMessage(addCode)}")
                    }
                })
            }
        })
    }

    @SuppressLint("MissingPermission")
    private fun stopDiscovery(result: MethodChannel.Result) {
        Log.d(TAG, "Stopping discovery...")
        stopAllDiscovery {
            result.success(true)
        }
    }

    @SuppressLint("MissingPermission")
    private fun unregisterService(result: MethodChannel.Result) {
        Log.d(TAG, "Unregistering service...")
        
        manager.clearLocalServices(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "✅ Service unregistered")
                isServiceRegistered = false
                currentServiceInfo = null
                result.success(true)
            }
            override fun onFailure(code: Int) {
                Log.w(TAG, "⚠️ Failed to unregister: ${getErrorMessage(code)}")
                isServiceRegistered = false
                result.error("CLEAR_SERVICE_ERROR", getErrorMessage(code), null)
            }
        })
    }

    @SuppressLint("MissingPermission")
    private fun refreshDiscovery(result: MethodChannel.Result) {
        if (!isDiscoveryActive) {
            Log.w(TAG, "Discovery not active, cannot refresh")
            result.error("NOT_ACTIVE", "Discovery not active", null)
            return
        }
        
        manager.discoverServices(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "✅ Discovery refreshed")
                result.success(true)
            }
            override fun onFailure(code: Int) {
                Log.w(TAG, "⚠️ Refresh failed: ${getErrorMessage(code)}")
                startDiscovery(result)
            }
        })
    }

    private fun startDiscoveryRefreshTimer() {
        stopDiscoveryRefreshTimer()
        
        discoveryRefreshTimer = Timer().apply {
            scheduleAtFixedRate(object : TimerTask() {
                @SuppressLint("MissingPermission")
                override fun run() {
                    if (isDiscoveryActive) {
                        Log.d(TAG, "⏰ Periodic refresh...")
                        manager.discoverServices(channel, null)
                    }
                }
            }, DISCOVERY_REFRESH_INTERVAL_MS, DISCOVERY_REFRESH_INTERVAL_MS)
        }
    }

    private fun stopDiscoveryRefreshTimer() {
        discoveryRefreshTimer?.cancel()
        discoveryRefreshTimer = null
    }

    private fun setupListeners() {
        manager.setDnsSdResponseListeners(channel,
            { instanceName, registrationType, srcDevice ->
                Log.d(TAG, "📡 Service: $instanceName ($registrationType) from ${srcDevice.deviceName}")
            },
            { fullDomainName, txtRecordMap, srcDevice ->
                Log.d(TAG, "📋 TXT: $fullDomainName")
                Log.d(TAG, "   Device: ${srcDevice.deviceName} (${srcDevice.deviceAddress})")
                Log.d(TAG, "   Data: $txtRecordMap")
                
                if (fullDomainName.lowercase().contains("rescuenet")) {
                    val event = mapOf(
                        "type" to "servicesFound",
                        "services" to listOf(
                            txtRecordMap + mapOf(
                                "deviceName" to (srcDevice.deviceName ?: "Unknown"),
                                "deviceAddress" to (srcDevice.deviceAddress ?: "")
                            )
                        )
                    )
                    
                    Handler(Looper.getMainLooper()).post {
                        eventSink?.success(event)
                    }
                }
            }
        )
    }

    private fun getErrorMessage(code: Int): String {
        return when (code) {
            WifiP2pManager.P2P_UNSUPPORTED -> "P2P_UNSUPPORTED"
            WifiP2pManager.ERROR -> "INTERNAL_ERROR"
            WifiP2pManager.BUSY -> "BUSY"
            WifiP2pManager.NO_SERVICE_REQUESTS -> "NO_SERVICE_REQUESTS"
            else -> "UNKNOWN_$code"
        }
    }
}
