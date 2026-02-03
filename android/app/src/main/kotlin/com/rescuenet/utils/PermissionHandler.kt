package com.rescuenet.utils

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

/**
 * Handles runtime permission requests for Wi-Fi Direct functionality.
 *
 * Android 13+ (API 33+): Requires NEARBY_WIFI_DEVICES permission
 * Android 12 and below: Requires ACCESS_FINE_LOCATION permission
 *
 * This class abstracts the version-specific permission logic so the
 * rest of the app can simply call checkAndRequestPermissions().
 */
class PermissionHandler(private val context: Context) {

    companion object {
        const val PERMISSION_REQUEST_CODE = 1001
        
        // Required for all Android versions
        private val BASE_PERMISSIONS = arrayOf(
            Manifest.permission.ACCESS_WIFI_STATE,
            Manifest.permission.CHANGE_WIFI_STATE,
            Manifest.permission.INTERNET,
            Manifest.permission.ACCESS_NETWORK_STATE
        )
        
        // Required for Android 13+ (API 33+)
        private val ANDROID_13_PERMISSIONS = arrayOf(
            "android.permission.NEARBY_WIFI_DEVICES"
        )
        
        // Required for Android < 13
        private val LOCATION_PERMISSIONS = arrayOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION
        )
        
        // For foreground service
        private const val FOREGROUND_SERVICE_PERMISSION = 
            "android.permission.FOREGROUND_SERVICE"
    }

    /**
     * Returns the list of permissions required for this Android version.
     */
    fun getRequiredPermissions(): Array<String> {
        val permissions = mutableListOf<String>()
        
        // Base permissions for all versions
        permissions.addAll(BASE_PERMISSIONS)
        
        // Version-specific Wi-Fi Direct permissions
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // Android 13+
            permissions.addAll(ANDROID_13_PERMISSIONS)
        } else {
            // Android 12 and below need location for Wi-Fi Direct
            permissions.addAll(LOCATION_PERMISSIONS)
        }
        
        // Foreground service permission (Android 9+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            permissions.add(FOREGROUND_SERVICE_PERMISSION)
        }
        
        return permissions.toTypedArray()
    }

    /**
     * Checks if all required permissions are granted.
     */
    fun hasAllPermissions(): Boolean {
        return getRequiredPermissions().all { permission ->
            ContextCompat.checkSelfPermission(context, permission) == 
                PackageManager.PERMISSION_GRANTED
        }
    }

    /**
     * Gets the list of permissions that are not yet granted.
     */
    fun getMissingPermissions(): Array<String> {
        return getRequiredPermissions().filter { permission ->
            ContextCompat.checkSelfPermission(context, permission) != 
                PackageManager.PERMISSION_GRANTED
        }.toTypedArray()
    }

    /**
     * Checks if Wi-Fi Direct specific permissions are granted.
     */
    fun hasWifiDirectPermissions(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // Android 13+: Need NEARBY_WIFI_DEVICES
            ContextCompat.checkSelfPermission(
                context, 
                "android.permission.NEARBY_WIFI_DEVICES"
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            // Android 12 and below: Need location
            ContextCompat.checkSelfPermission(
                context, 
                Manifest.permission.ACCESS_FINE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
        }
    }

    /**
     * Requests missing permissions from the user.
     *
     * @param activity The activity to use for the permission request.
     * @return true if all permissions are already granted, false if request was made.
     */
    fun requestPermissions(activity: Activity): Boolean {
        val missing = getMissingPermissions()
        
        if (missing.isEmpty()) {
            return true // All granted
        }
        
        ActivityCompat.requestPermissions(
            activity,
            missing,
            PERMISSION_REQUEST_CODE
        )
        
        return false // Request made, need to wait for result
    }

    /**
     * Handles the result of a permission request.
     *
     * @param requestCode The request code from onRequestPermissionsResult.
     * @param permissions The requested permissions.
     * @param grantResults The grant results.
     * @return PermissionResult indicating the outcome.
     */
    fun handlePermissionResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): PermissionResult {
        if (requestCode != PERMISSION_REQUEST_CODE) {
            return PermissionResult.NotHandled
        }
        
        if (grantResults.isEmpty()) {
            return PermissionResult.Denied(permissions.toList())
        }
        
        val denied = mutableListOf<String>()
        val granted = mutableListOf<String>()
        
        permissions.forEachIndexed { index, permission ->
            if (grantResults[index] == PackageManager.PERMISSION_GRANTED) {
                granted.add(permission)
            } else {
                denied.add(permission)
            }
        }
        
        return if (denied.isEmpty()) {
            PermissionResult.AllGranted
        } else {
            PermissionResult.Denied(denied)
        }
    }

    /**
     * Checks if the app should show rationale for any permission.
     */
    fun shouldShowRationale(activity: Activity): Boolean {
        return getMissingPermissions().any { permission ->
            ActivityCompat.shouldShowRequestPermissionRationale(activity, permission)
        }
    }

    /**
     * Returns a user-friendly message explaining why permissions are needed.
     */
    fun getPermissionRationale(): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            "RescueNet Pro needs access to nearby devices to create the " +
            "emergency mesh network. This allows your phone to communicate " +
            "with other devices even without internet connectivity."
        } else {
            "RescueNet Pro needs location access to discover nearby devices " +
            "for the emergency mesh network. Your precise location is also " +
            "included in SOS messages to help rescuers find you."
        }
    }

    /**
     * Returns info about the current permission status.
     */
    fun getPermissionStatus(): PermissionStatus {
        val required = getRequiredPermissions()
        val missing = getMissingPermissions()
        
        return PermissionStatus(
            totalRequired = required.size,
            granted = required.size - missing.size,
            missing = missing.toList(),
            hasWifiDirect = hasWifiDirectPermissions(),
            androidVersion = Build.VERSION.SDK_INT
        )
    }
}

/**
 * Result of a permission request.
 */
sealed class PermissionResult {
    object AllGranted : PermissionResult()
    object NotHandled : PermissionResult()
    data class Denied(val permissions: List<String>) : PermissionResult()
}

/**
 * Current status of app permissions.
 */
data class PermissionStatus(
    val totalRequired: Int,
    val granted: Int,
    val missing: List<String>,
    val hasWifiDirect: Boolean,
    val androidVersion: Int
) {
    val allGranted: Boolean get() = missing.isEmpty()
    val percentage: Int get() = (granted * 100) / totalRequired
}
