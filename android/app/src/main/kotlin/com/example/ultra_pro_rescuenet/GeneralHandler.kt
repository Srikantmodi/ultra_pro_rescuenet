package com.example.ultra_pro_rescuenet

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class GeneralHandler(
    private val activity: Activity
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "GeneralHandler"
        private const val REQUEST_CODE_PERMISSIONS = 1001
        private const val REQUEST_CODE_BG_LOCATION = 1002
    }

    fun setup(messenger: io.flutter.plugin.common.BinaryMessenger) {
        val channel = MethodChannel(messenger, "com.rescuenet/wifi_p2p")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> {
                // Already initialized in MainActivity
                result.success(mapOf("success" to true))
            }
            "checkPermissions" -> {
                checkPermissions(result)
            }
            "requestPermissions" -> {
                requestPermissions(result)
            }
            "getDeviceInfo" -> {
                result.success(mapOf(
                    "deviceName" to (android.provider.Settings.Global.getString(activity.contentResolver, "device_name") ?: Build.MODEL),
                    "androidVersion" to Build.VERSION.SDK_INT,
                    "isP2pSupported" to activity.packageManager.hasSystemFeature(PackageManager.FEATURE_WIFI_DIRECT)
                ))
            }
            "startMeshService" -> {
                try {
                    val serviceIntent = android.content.Intent(activity, MeshService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        activity.startForegroundService(serviceIntent)
                    } else {
                        activity.startService(serviceIntent)
                    }
                    result.success(true)
                } catch (e: Exception) {
                    result.error("SERVICE_START_FAILED", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun checkPermissions(result: MethodChannel.Result) {
        val permissions = getRequiredPermissions()
        val missing = permissions.filter {
            ContextCompat.checkSelfPermission(activity, it) != PackageManager.PERMISSION_GRANTED
        }
        
        // Check background location separately (Android 10+)
        val needsBackgroundLocation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ContextCompat.checkSelfPermission(activity, Manifest.permission.ACCESS_BACKGROUND_LOCATION) != PackageManager.PERMISSION_GRANTED
        } else {
            false
        }
        
        // Check location permission
        val hasLocation = ContextCompat.checkSelfPermission(
            activity, 
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        
        Log.d(TAG, "Permissions check: missing=${missing}, needsBgLocation=$needsBackgroundLocation")
        
        result.success(mapOf(
            "allGranted" to (missing.isEmpty() && !needsBackgroundLocation),
            "hasWifiDirect" to activity.packageManager.hasSystemFeature(PackageManager.FEATURE_WIFI_DIRECT),
            "hasLocation" to hasLocation,
            "hasForegroundService" to true, // Always true - declared in manifest
            "missing" to missing,
            "needsBackgroundLocation" to needsBackgroundLocation,
            "androidVersion" to Build.VERSION.SDK_INT
        ))
    }

    private fun requestPermissions(result: MethodChannel.Result) {
        val permissions = getRequiredPermissions()
        val missing = permissions.filter {
            ContextCompat.checkSelfPermission(activity, it) != PackageManager.PERMISSION_GRANTED
        }
        
        // First request foreground permissions
        if (missing.isNotEmpty()) {
            Log.d(TAG, "Requesting foreground permissions: $missing")
            ActivityCompat.requestPermissions(activity, missing.toTypedArray(), REQUEST_CODE_PERMISSIONS)
            result.success(mapOf("allGranted" to false, "status" to "requesting_foreground"))
            return
        }
        
        // Then request background location for Android 10+ (must be done AFTER foreground location is granted)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val hasBackgroundLocation = ContextCompat.checkSelfPermission(
                activity, 
                Manifest.permission.ACCESS_BACKGROUND_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
            
            if (!hasBackgroundLocation) {
                Log.d(TAG, "Requesting background location permission")
                ActivityCompat.requestPermissions(
                    activity, 
                    arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION), 
                    REQUEST_CODE_BG_LOCATION
                )
                result.success(mapOf("allGranted" to false, "status" to "requesting_background_location"))
                return
            }
        }
        
        Log.d(TAG, "All permissions granted")
        result.success(mapOf("allGranted" to true, "status" to "complete"))
    }

    private fun getRequiredPermissions(): List<String> {
        val perms = mutableListOf<String>()
        
        // Location permissions (required for WiFi P2P)
        perms.add(Manifest.permission.ACCESS_FINE_LOCATION)
        
        // WiFi state permissions
        perms.add(Manifest.permission.ACCESS_WIFI_STATE)
        perms.add(Manifest.permission.CHANGE_WIFI_STATE)
        
        // Android 13+ requires NEARBY_WIFI_DEVICES
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            perms.add(Manifest.permission.NEARBY_WIFI_DEVICES)
        }
        
        // Note: ACCESS_BACKGROUND_LOCATION is requested separately after foreground location is granted
        // This is a requirement from Android 11+ (must request separately)
        
        return perms
    }
}
