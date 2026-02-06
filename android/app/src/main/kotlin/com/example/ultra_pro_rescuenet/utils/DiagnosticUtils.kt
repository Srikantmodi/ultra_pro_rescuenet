package com.example.ultra_pro_rescuenet.utils

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.wifi.WifiManager
import android.net.wifi.p2p.WifiP2pManager
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat

object DiagnosticUtils {
    
    fun checkWifiP2pReadiness(context: Context): Map<String, Any> {
        val results = mutableMapOf<String, Any>()
        
        // 1. Check Wi-Fi enabled
        val wifiManager = context.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val wifiEnabled = wifiManager.isWifiEnabled
        results["wifiEnabled"] = wifiEnabled
        
        // 2. Check Location enabled
        val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val locationEnabled = locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                              locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
        results["locationEnabled"] = locationEnabled
        
        // 3. Check permissions
        val permissionsGranted = checkAllPermissions(context)
        results["permissionsGranted"] = permissionsGranted
        
        // 4. Check P2P Manager
        val p2pManager = context.getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager
        results["p2pManagerExists"] = (p2pManager != null)
        
        // Overall readiness
        results["isP2pReady"] = wifiEnabled && locationEnabled && permissionsGranted && (p2pManager != null)
        
        return results
    }
    
    fun checkAllPermissions(context: Context): Boolean {
        val requiredPermissions = mutableListOf(
            Manifest.permission.ACCESS_WIFI_STATE,
            Manifest.permission.CHANGE_WIFI_STATE,
            Manifest.permission.ACCESS_NETWORK_STATE,
            Manifest.permission.CHANGE_NETWORK_STATE,
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION
        )
        
        // Android 13+ specific permission
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            requiredPermissions.add("android.permission.NEARBY_WIFI_DEVICES")
        }
        
        return requiredPermissions.all { permission ->
            ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
        }
    }
    
    fun getStatusMessage(context: Context): String {
        val diagnostics = checkWifiP2pReadiness(context)
        
        return when {
            diagnostics["wifiEnabled"] != true -> "Wi-Fi is disabled. Please enable Wi-Fi."
            diagnostics["locationEnabled"] != true -> "Location is disabled. Please enable Location services."
            diagnostics["permissionsGranted"] != true -> "Missing required permissions. Please grant all permissions."
            diagnostics["p2pManagerExists"] != true -> "Wi-Fi Direct not supported on this device."
            else -> "Unknown error"
        }
    }
    
    fun logDiagnosticInfo(context: Context, tag: String) {
        val diagnostics = checkWifiP2pReadiness(context)
        Log.d(tag, "═══════════════════════════════════")
        Log.d(tag, "Wi-Fi P2P Diagnostics:")
        Log.d(tag, "  Wi-Fi Enabled: ${diagnostics["wifiEnabled"]}")
        Log.d(tag, "  Location Enabled: ${diagnostics["locationEnabled"]}")
        Log.d(tag, "  Permissions Granted: ${diagnostics["permissionsGranted"]}")
        Log.d(tag, "  P2P Manager Exists: ${diagnostics["p2pManagerExists"]}")
        Log.d(tag, "  Overall Ready: ${diagnostics["isP2pReady"]}")
        Log.d(tag, "═══════════════════════════════════")
    }
}
