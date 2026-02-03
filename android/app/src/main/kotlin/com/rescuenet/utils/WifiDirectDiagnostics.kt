package com.rescuenet.utils

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.wifi.WifiManager
import android.net.wifi.p2p.WifiP2pManager
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * Comprehensive Wi-Fi Direct diagnostics utility.
 * 
 * Runs a full pre-flight check covering:
 * - Hardware support
 * - Wi-Fi state
 * - Location services state
 * - Permission status
 * - Wi-Fi P2P Manager initialization
 */
class WifiDirectDiagnostics(private val context: Context) {
    
    companion object {
        private const val TAG = "WifiDiagnostics"
    }
    
    data class DiagnosticResult(
        val passed: Boolean,
        val issue: String,
        val solution: String
    )
    
    /**
     * Runs all diagnostic checks and logs results.
     * Returns a map of check names to results.
     */
    fun runFullDiagnostics(): Map<String, DiagnosticResult> {
        val results = mutableMapOf<String, DiagnosticResult>()
        
        Log.d(TAG, "════════════════════════════════════════")
        Log.d(TAG, "🔍 WIFI DIRECT DIAGNOSTICS STARTING")
        Log.d(TAG, "════════════════════════════════════════")
        
        // 1. Device Info
        logDeviceInfo()
        
        // 2. Hardware Support
        results["hardware"] = checkHardwareSupport()
        
        // 3. Wi-Fi State
        results["wifi_enabled"] = checkWifiEnabled()
        
        // 4. Location State
        results["location_enabled"] = checkLocationEnabled()
        
        // 5. Permissions
        results["permissions"] = checkPermissions()
        
        // 6. Wi-Fi P2P Manager
        results["p2p_manager"] = checkWifiP2pManager()
        
        // 7. Summary
        printSummary(results)
        
        return results
    }
    
    private fun logDeviceInfo() {
        Log.d(TAG, "📱 DEVICE INFORMATION:")
        Log.d(TAG, "   Manufacturer: ${Build.MANUFACTURER}")
        Log.d(TAG, "   Model: ${Build.MODEL}")
        Log.d(TAG, "   Android Version: ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})")
        Log.d(TAG, "   Build ID: ${Build.ID}")
        Log.d(TAG, "")
    }
    
    private fun checkHardwareSupport(): DiagnosticResult {
        Log.d(TAG, "🔧 HARDWARE SUPPORT:")
        
        val hasWifiDirect = context.packageManager.hasSystemFeature(
            PackageManager.FEATURE_WIFI_DIRECT
        )
        
        val hasWifi = context.packageManager.hasSystemFeature(
            PackageManager.FEATURE_WIFI
        )
        
        Log.d(TAG, "   Wi-Fi Feature: ${if (hasWifi) "✅" else "❌"}")
        Log.d(TAG, "   Wi-Fi Direct Feature: ${if (hasWifiDirect) "✅" else "❌"}")
        Log.d(TAG, "")
        
        return if (hasWifiDirect) {
            DiagnosticResult(true, "", "")
        } else {
            DiagnosticResult(
                false,
                "Device doesn't support Wi-Fi Direct",
                "Use a different device with Wi-Fi Direct support"
            )
        }
    }
    
    private fun checkWifiEnabled(): DiagnosticResult {
        Log.d(TAG, "📡 WIFI STATE:")
        
        val wifiManager = context.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val isEnabled = wifiManager.isWifiEnabled
        
        Log.d(TAG, "   Wi-Fi Enabled: ${if (isEnabled) "✅" else "❌"}")
        
        if (!isEnabled) {
            Log.d(TAG, "   ⚠️ Wi-Fi is OFF - this will prevent discovery")
        }
        Log.d(TAG, "")
        
        return if (isEnabled) {
            DiagnosticResult(true, "", "")
        } else {
            DiagnosticResult(
                false,
                "Wi-Fi is disabled",
                "Go to Settings > Wi-Fi and turn it ON"
            )
        }
    }
    
    private fun checkLocationEnabled(): DiagnosticResult {
        Log.d(TAG, "📍 LOCATION STATE:")
        
        val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val isGpsEnabled = locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)
        val isNetworkEnabled = locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
        val isLocationEnabled = isGpsEnabled || isNetworkEnabled
        
        Log.d(TAG, "   GPS Provider: ${if (isGpsEnabled) "✅" else "❌"}")
        Log.d(TAG, "   Network Provider: ${if (isNetworkEnabled) "✅" else "❌"}")
        Log.d(TAG, "   Overall Status: ${if (isLocationEnabled) "✅ ENABLED" else "❌ DISABLED"}")
        
        if (!isLocationEnabled) {
            Log.d(TAG, "   ⚠️ Location is OFF - Required for Wi-Fi scanning on Android 6+")
        }
        Log.d(TAG, "")
        
        return if (isLocationEnabled) {
            DiagnosticResult(true, "", "")
        } else {
            DiagnosticResult(
                false,
                "Location services are disabled",
                "Go to Settings > Location and turn it ON"
            )
        }
    }
    
    private fun checkPermissions(): DiagnosticResult {
        Log.d(TAG, "🔐 PERMISSIONS CHECK:")
        
        val requiredPermissions = mutableMapOf<String, Boolean>()
        
        // Core Wi-Fi permissions
        requiredPermissions["ACCESS_WIFI_STATE"] = checkPermission(Manifest.permission.ACCESS_WIFI_STATE)
        requiredPermissions["CHANGE_WIFI_STATE"] = checkPermission(Manifest.permission.CHANGE_WIFI_STATE)
        requiredPermissions["ACCESS_NETWORK_STATE"] = checkPermission(Manifest.permission.ACCESS_NETWORK_STATE)
        requiredPermissions["CHANGE_NETWORK_STATE"] = checkPermission(Manifest.permission.CHANGE_NETWORK_STATE)
        
        // Location permissions
        requiredPermissions["ACCESS_FINE_LOCATION"] = checkPermission(Manifest.permission.ACCESS_FINE_LOCATION)
        requiredPermissions["ACCESS_COARSE_LOCATION"] = checkPermission(Manifest.permission.ACCESS_COARSE_LOCATION)
        
        // Android 13+ specific
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            requiredPermissions["NEARBY_WIFI_DEVICES"] = checkPermission(
                "android.permission.NEARBY_WIFI_DEVICES"
            )
        }
        
        // Print results
        requiredPermissions.forEach { (permission, granted) ->
            Log.d(TAG, "   $permission: ${if (granted) "✅" else "❌"}")
        }
        
        val allGranted = requiredPermissions.values.all { it }
        val deniedPermissions = requiredPermissions.filter { !it.value }.keys
        
        Log.d(TAG, "")
        if (!allGranted) {
            Log.d(TAG, "   ⚠️ MISSING PERMISSIONS:")
            deniedPermissions.forEach { perm ->
                Log.d(TAG, "      - $perm")
            }
        } else {
            Log.d(TAG, "   ✅ All permissions granted")
        }
        Log.d(TAG, "")
        
        return if (allGranted) {
            DiagnosticResult(true, "", "")
        } else {
            DiagnosticResult(
                false,
                "Missing permissions: ${deniedPermissions.joinToString(", ")}",
                "Grant all required permissions in app settings"
            )
        }
    }
    
    private fun checkPermission(permission: String): Boolean {
        return ContextCompat.checkSelfPermission(
            context,
            permission
        ) == PackageManager.PERMISSION_GRANTED
    }
    
    private fun checkWifiP2pManager(): DiagnosticResult {
        Log.d(TAG, "🔌 WIFI P2P MANAGER:")
        
        return try {
            val manager = context.getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager
            
            if (manager == null) {
                Log.d(TAG, "   ❌ WifiP2pManager is NULL")
                Log.d(TAG, "   This means Wi-Fi Direct is not available on this device")
                Log.d(TAG, "")
                
                return DiagnosticResult(
                    false,
                    "WifiP2pManager is null",
                    "Device doesn't support Wi-Fi Direct"
                )
            }
            
            Log.d(TAG, "   ✅ WifiP2pManager obtained successfully")
            
            // Try to initialize channel
            val channel = manager.initialize(context, context.mainLooper, null)
            
            if (channel == null) {
                Log.d(TAG, "   ❌ Channel initialization failed")
                Log.d(TAG, "")
                
                return DiagnosticResult(
                    false,
                    "Channel initialization failed",
                    "Restart the app or reboot the device"
                )
            }
            
            Log.d(TAG, "   ✅ Channel initialized successfully")
            Log.d(TAG, "")
            
            DiagnosticResult(true, "", "")
            
        } catch (e: Exception) {
            Log.d(TAG, "   ❌ Exception: ${e.message}")
            Log.d(TAG, "")
            
            DiagnosticResult(
                false,
                "Exception during initialization: ${e.message}",
                "Check logcat for stack trace"
            )
        }
    }
    
    private fun printSummary(results: Map<String, DiagnosticResult>) {
        Log.d(TAG, "════════════════════════════════════════")
        Log.d(TAG, "📊 DIAGNOSTIC SUMMARY")
        Log.d(TAG, "════════════════════════════════════════")
        
        val allPassed = results.values.all { it.passed }
        
        if (allPassed) {
            Log.d(TAG, "✅ ALL CHECKS PASSED - Wi-Fi Direct should work!")
        } else {
            Log.d(TAG, "❌ ISSUES FOUND:")
            Log.d(TAG, "")
            results.filter { !it.value.passed }.forEach { (check, result) ->
                Log.d(TAG, "🔴 $check:")
                Log.d(TAG, "   Problem: ${result.issue}")
                Log.d(TAG, "   Solution: ${result.solution}")
                Log.d(TAG, "")
            }
        }
        
        Log.d(TAG, "════════════════════════════════════════")
    }
    
    /**
     * Converts results to a JSON-compatible map for Flutter.
     */
    fun getResultsAsJson(results: Map<String, DiagnosticResult>): Map<String, Any> {
        return results.mapValues { (_, result) ->
            mapOf(
                "passed" to result.passed,
                "issue" to result.issue,
                "solution" to result.solution
            )
        }
    }
    
    /**
     * Quick check if all pre-conditions are met for Wi-Fi P2P.
     */
    fun isReadyForP2p(): Boolean {
        return try {
            val wifiManager = context.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
            
            val wifiEnabled = wifiManager.isWifiEnabled
            val locationEnabled = locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                                  locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
            val hasLocationPerm = checkPermission(Manifest.permission.ACCESS_FINE_LOCATION)
            val hasNearbyPerm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                checkPermission("android.permission.NEARBY_WIFI_DEVICES")
            } else {
                true
            }
            
            wifiEnabled && locationEnabled && (hasLocationPerm || hasNearbyPerm)
        } catch (e: Exception) {
            false
        }
    }
}
