package com.rescuenet

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Foreground service that keeps the mesh network running in the background.
 *
 * This service is essential for:
 * 1. Keeping the app alive when the screen is off
 * 2. Maintaining Wi-Fi Direct connections
 * 3. Continuing to relay packets for other users
 * 4. Broadcasting presence via DNS-SD
 *
 * The service runs as a foreground service with a persistent notification
 * to comply with Android's background execution limits.
 */
class MeshService : Service() {
    
    companion object {
        private const val TAG = "MeshService"
        
        // Notification
        private const val NOTIFICATION_CHANNEL_ID = "rescuenet_mesh_service"
        private const val NOTIFICATION_CHANNEL_NAME = "RescueNet Mesh Network"
        private const val NOTIFICATION_ID = 1001
        
        // Actions
        const val ACTION_START = "com.rescuenet.ACTION_START_MESH"
        const val ACTION_STOP = "com.rescuenet.ACTION_STOP_MESH"
        const val ACTION_UPDATE_STATUS = "com.rescuenet.ACTION_UPDATE_STATUS"
        
        // Extras
        const val EXTRA_STATUS_MESSAGE = "status_message"
        const val EXTRA_PEERS_COUNT = "peers_count"
        
        /**
         * Starts the foreground service.
         */
        fun start(context: Context) {
            val intent = Intent(context, MeshService::class.java).apply {
                action = ACTION_START
            }
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
        
        /**
         * Stops the foreground service.
         */
        fun stop(context: Context) {
            val intent = Intent(context, MeshService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }
        
        /**
         * Updates the notification status.
         */
        fun updateStatus(context: Context, message: String, peersCount: Int = 0) {
            val intent = Intent(context, MeshService::class.java).apply {
                action = ACTION_UPDATE_STATUS
                putExtra(EXTRA_STATUS_MESSAGE, message)
                putExtra(EXTRA_PEERS_COUNT, peersCount)
            }
            context.startService(intent)
        }
    }
    
    private var wakeLock: PowerManager.WakeLock? = null
    private var isRunning = false
    private var currentStatus = "Initializing..."
    private var currentPeersCount = 0

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "Service created")
        
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startMeshService()
            ACTION_STOP -> stopMeshService()
            ACTION_UPDATE_STATUS -> {
                currentStatus = intent.getStringExtra(EXTRA_STATUS_MESSAGE) ?: currentStatus
                currentPeersCount = intent.getIntExtra(EXTRA_PEERS_COUNT, currentPeersCount)
                updateNotification()
            }
        }
        
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null // Not a bound service
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "Service destroyed")
        releaseWakeLock()
    }

    /**
     * Starts the mesh service and enters foreground mode.
     */
    private fun startMeshService() {
        if (isRunning) {
            Log.d(TAG, "Service already running")
            return
        }
        
        Log.d(TAG, "Starting mesh service")
        isRunning = true
        
        // Start foreground with notification
        startForeground(NOTIFICATION_ID, createNotification())
        
        // Acquire wake lock to prevent CPU sleep
        acquireWakeLock()
    }

    /**
     * Stops the mesh service.
     */
    private fun stopMeshService() {
        Log.d(TAG, "Stopping mesh service")
        isRunning = false
        
        releaseWakeLock()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    /**
     * Creates the notification channel (required for Android O+).
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                NOTIFICATION_CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows mesh network status"
                setShowBadge(false)
            }
            
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }

    /**
     * Creates the foreground notification.
     */
    private fun createNotification(): Notification {
        // Intent to open the app when tapping notification
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        
        // Stop action
        val stopIntent = Intent(this, MeshService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            0,
            stopIntent,
            PendingIntent.FLAG_IMMUTABLE
        )
        
        val contentText = if (currentPeersCount > 0) {
            "$currentStatus • $currentPeersCount peers"
        } else {
            currentStatus
        }
        
        return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle("RescueNet Pro Active")
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_menu_share) // Replace with actual icon
            .setContentIntent(pendingIntent)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Stop",
                stopPendingIntent
            )
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    /**
     * Updates the notification with new status.
     */
    private fun updateNotification() {
        if (!isRunning) return
        
        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.notify(NOTIFICATION_ID, createNotification())
    }

    /**
     * Acquires a partial wake lock to keep CPU running.
     */
    private fun acquireWakeLock() {
        if (wakeLock != null) return
        
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "RescueNet:MeshWakeLock"
        ).apply {
            setReferenceCounted(false)
            acquire(10 * 60 * 1000L) // 10 minutes, will reacquire
        }
        
        Log.d(TAG, "Wake lock acquired")
    }

    /**
     * Releases the wake lock.
     */
    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
                Log.d(TAG, "Wake lock released")
            }
        }
        wakeLock = null
    }
}
