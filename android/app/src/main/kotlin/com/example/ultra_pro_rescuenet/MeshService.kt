package com.example.ultra_pro_rescuenet

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.wifi.p2p.WifiP2pInfo
import android.net.wifi.p2p.WifiP2pManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import java.util.concurrent.TimeUnit

/**
 * MeshService — Android Foreground Service for RescueNet mesh relay.
 *
 * FIX A-7: Registers its own BroadcastReceiver for Wi-Fi P2P intents so that
 *          discovery and connection events are received even when the Activity is
 *          backgrounded or the screen is off.
 *
 * FIX A-8: Wake lock now has a 4-hour timeout to prevent indefinite battery drain.
 *
 * FIX A-9: Exposes a static callback for WIFI_P2P_CONNECTION_CHANGED_ACTION
 *          that ConnectionManager and WifiP2pHandler can subscribe to.
 */
class MeshService : Service() {

    companion object {
        private const val TAG = "MeshService"
        const val CHANNEL_ID = "MeshServiceChannel"
        private const val WAKE_LOCK_TIMEOUT_MS = 4 * 60 * 60 * 1000L // 4 hours

        /**
         * FIX A-9: Static callback for connection-changed events.
         * Set by WifiP2pHandler/ConnectionManager to receive P2P connection updates
         * even in background.
         */
        var onP2pConnectionChanged: ((WifiP2pInfo) -> Unit)? = null
        var onP2pStateChanged: ((Boolean) -> Unit)? = null
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var p2pReceiver: BroadcastReceiver? = null

    // FIX: Initialise WifiP2pManager + Channel ONCE here, not inside broadcast callbacks.
    // Creating a new channel on every WIFI_P2P_CONNECTION_CHANGED_ACTION broadcast
    // leaks channels and crashes after ~4 events (Android hard-limits channels per process).
    private var p2pManager: WifiP2pManager? = null
    private var p2pChannel: WifiP2pManager.Channel? = null

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "═══════════════════════════════════")
        Log.d(TAG, "🚀 MeshService onCreate")
        Log.d(TAG, "═══════════════════════════════════")

        // FIX: Check location permissions BEFORE calling startForeground with
        // foregroundServiceType="location". On Android 14+ (targetSDK 34+),
        // calling startForeground without the required runtime permissions
        // throws a SecurityException and crashes the app.
        if (!hasLocationPermission()) {
            Log.e(TAG, "❌ Location permission not granted — cannot start foreground service")
            stopSelf()
            return
        }

        createNotificationChannel()
        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("RescueNet Mesh Active")
            .setContentText("Listening for emergency packets...")
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setOngoing(true)
            .build()
        try {
            startForeground(1, notification)
        } catch (e: SecurityException) {
            Log.e(TAG, "❌ SecurityException starting foreground: ${e.message}")
            stopSelf()
            return
        }

        // FIX: Initialise WifiP2pManager and Channel once here so the broadcast
        // receiver can reuse them.  Creating a new channel on every broadcast
        // exhausts Android's per-process channel limit (~4) and causes crashes.
        p2pManager = getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager
        p2pChannel = p2pManager?.initialize(this, mainLooper, null)
        if (p2pManager == null || p2pChannel == null) {
            Log.e(TAG, "⚠️ WifiP2pManager unavailable in MeshService — callbacks disabled")
        } else {
            Log.d(TAG, "✅ WifiP2pManager + Channel initialised (service-level)")
        }
        
        // FIX A-8: Acquire Wake Lock WITH timeout (4 hours max)
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "RescueNet:MeshServiceWakeLock"
        )
        wakeLock?.acquire(WAKE_LOCK_TIMEOUT_MS)
        Log.d(TAG, "✅ Wake lock acquired (timeout: ${WAKE_LOCK_TIMEOUT_MS / 3600000}h)")
        
        // FIX A-7: Register BroadcastReceiver for Wi-Fi P2P state changes
        registerP2pReceiver()
    }

    /**
     * FIX A-7: Register for P2P broadcasts in the Service so relay works in background.
     */
    private fun registerP2pReceiver() {
        val intentFilter = IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
        }
        
        p2pReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                when (intent.action) {
                    WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                        val state = intent.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, -1)
                        val enabled = state == WifiP2pManager.WIFI_P2P_STATE_ENABLED
                        Log.d(TAG, "⚡ [Service] P2P State: ${if (enabled) "ENABLED" else "DISABLED"}")
                        onP2pStateChanged?.invoke(enabled)
                    }
                    
                    WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                        Log.d(TAG, "⚡ [Service] Connection Changed")
                        // FIX A-9: Forward connection info to registered callback.
                        // CRITICAL FIX: Reuse the service-level manager/channel instead of
                        // calling manager.initialize() here — creating a new channel on every
                        // broadcast exhausts Android's per-process channel limit and crashes.
                        val mgr = p2pManager
                        val ch  = p2pChannel
                        if (mgr != null && ch != null) {
                            mgr.requestConnectionInfo(ch) { info ->
                                if (info != null && info.groupFormed) {
                                    Log.d(TAG, "   [Service] Group formed, GO=${info.isGroupOwner}, addr=${info.groupOwnerAddress?.hostAddress}")
                                    onP2pConnectionChanged?.invoke(info)
                                }
                            }
                        } else {
                            Log.w(TAG, "⚠️ [Service] P2P manager/channel not available for connection info request")
                        }
                    }
                    
                    WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> {
                        Log.d(TAG, "⚡ [Service] Peers Changed")
                    }
                    
                    WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION -> {
                        Log.d(TAG, "⚡ [Service] This Device Changed")
                    }
                }
            }
        }
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            registerReceiver(p2pReceiver, intentFilter, Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(p2pReceiver, intentFilter)
        }
        Log.d(TAG, "✅ P2P BroadcastReceiver registered in Service")
    }
    
    override fun onDestroy() {
        Log.d(TAG, "🛑 MeshService onDestroy")
        releaseWakeLock()
        unregisterP2pReceiver()
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.d(TAG, "⚠️ MeshService onTaskRemoved")
        // FIX A-8: Release wake lock when task is removed (app swiped away)
        releaseWakeLock()
        super.onTaskRemoved(rootIntent)
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
                Log.d(TAG, "✅ Wake lock released")
            }
        }
        wakeLock = null
    }

    private fun unregisterP2pReceiver() {
        try {
            p2pReceiver?.let { unregisterReceiver(it) }
            p2pReceiver = null
            Log.d(TAG, "✅ P2P BroadcastReceiver unregistered")
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ Error unregistering P2P receiver: ${e.message}")
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "ℹ️ MeshService onStartCommand")
        // FIX: Use START_NOT_STICKY to prevent the system from auto-restarting
        // the service after a crash. START_STICKY caused a crash loop when the
        // service was killed (e.g., due to missing permissions), because the
        // system would keep restarting it without the required permissions.
        return START_NOT_STICKY
    }

    /**
     * Checks whether the app has at least one location permission granted.
     * Required on Android 14+ before calling startForeground with
     * foregroundServiceType="location".
     */
    private fun hasLocationPermission(): Boolean {
        val fine = ContextCompat.checkSelfPermission(
            this, Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        val coarse = ContextCompat.checkSelfPermission(
            this, Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        return fine || coarse
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "Mesh Network Service",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(serviceChannel)
        }
    }
}
