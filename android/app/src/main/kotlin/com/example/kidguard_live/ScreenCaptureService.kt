package com.example.kidguard_live

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.media.projection.MediaProjection
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/**
 * Native Android Foreground Service for 24/7 Screen Capture & Mic Audio without Chrome.
 * Supports Android 7.0 (API 24) to Android 14/15/16 (API 34+).
 *
 * Crash-Free Staged Startup on Android 14/15/16:
 * 1. ACTION_START (before MediaProjection dialog): starts with DATA_SYNC (+ MICROPHONE if granted).
 *    Never attempts MEDIA_PROJECTION before user consent, preventing SecurityException / FGS crash.
 * 2. ACTION_UPGRADE (after user picks "Share entire screen -> OK"): upgrades types safely to keep
 *    both microphone and screen capture alive in the background.
 */
class ScreenCaptureService : Service() {

    companion object {
        const val ACTION_START = "ACTION_START"
        const val ACTION_UPGRADE = "ACTION_UPGRADE"
        const val ACTION_STOP = "ACTION_STOP"
        const val CHANNEL_ID = "kidguard_screen_channel"
        const val NOTIFICATION_ID = 1001

        var activeMediaProjection: MediaProjection? = null
            private set
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                startForegroundSafe(allowMediaProjection = false)
                Log.d("ScreenCaptureService", "Foreground service started safely (pre-projection)")
            }
            ACTION_UPGRADE -> {
                startForegroundSafe(allowMediaProjection = true)
                Log.d("ScreenCaptureService", "Foreground service upgraded (post-projection)")
            }
            ACTION_STOP -> {
                cleanupAndStop()
                return START_NOT_STICKY
            }
            else -> {
                // Ensure startForeground contract is always satisfied if started without action or restarted
                startForegroundSafe(allowMediaProjection = false)
            }
        }
        return START_STICKY
    }

    private fun hasRecordAudioPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun acquireWakeLock() {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
            if (wakeLock == null) {
                wakeLock = powerManager?.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "KidGuard::LiveAudioWakeLock"
                )
            }
            if (wakeLock?.isHeld != true) {
                wakeLock?.acquire(24 * 60 * 60 * 1000L)
            }
        } catch (pEx: Exception) {
            Log.w("ScreenCaptureService", "WakeLock notice: ${pEx.message}")
        }

        try {
            val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            if (wifiLock == null) {
                val lockType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                } else {
                    @Suppress("DEPRECATION")
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF
                }
                wifiLock = wifiManager?.createWifiLock(lockType, "KidGuard::LiveNetworkWifiLock")
                wifiLock?.setReferenceCounted(false)
            }
            if (wifiLock?.isHeld != true) {
                wifiLock?.acquire()
            }
        } catch (wEx: Exception) {
            Log.w("ScreenCaptureService", "WifiLock notice: ${wEx.message}")
        }
    }

    private fun releaseLocks() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
            wakeLock = null
        } catch (_: Exception) {}
        try {
            if (wifiLock?.isHeld == true) {
                wifiLock?.release()
            }
            wifiLock = null
        } catch (_: Exception) {}
    }

    private fun startForegroundSafe(allowMediaProjection: Boolean) {
        try {
            acquireWakeLock()

            val safeIcon = applicationInfo.icon.takeIf { it != 0 } ?: android.R.drawable.ic_dialog_info

            // Locked non-dismissible notification without a stop button
            val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("KidGuard Live: स्क्रीन व लाइव माइक सक्रिय है")
                .setContentText("माता-पिता के फोन से सुरक्षित लाइव कनेक्टेड (बैकग्राउंड माइक चालू)")
                .setSmallIcon(safeIcon)
                .setOngoing(true)
                .setAutoCancel(false)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .build()

            val micGranted = hasRecordAudioPermission()

            if (Build.VERSION.SDK_INT >= 34) {
                // Android 14, 15, 16 (API 34+): Try safest highest-privilege combination first,
                // then gracefully fall back so startForeground NEVER fails or throws SecurityException.
                val candidates = mutableListOf<Int>()
                if (allowMediaProjection) {
                    if (micGranted) {
                        candidates.add(
                            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION or
                                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                        )
                    }
                    candidates.add(ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
                }
                if (micGranted) {
                    candidates.add(ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
                    candidates.add(
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC or
                            ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                    )
                }
                candidates.add(ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)

                var started = false
                for (fgType in candidates) {
                    try {
                        startForeground(NOTIFICATION_ID, notification, fgType)
                        Log.d("ScreenCaptureService", "startForeground succeeded with type=$fgType")
                        started = true
                        break
                    } catch (ex: Exception) {
                        Log.w("ScreenCaptureService", "startForeground type=$fgType skipped: ${ex.message}")
                    }
                }
                if (!started) {
                    try {
                        startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
                    } catch (e: Exception) {
                        Log.e("ScreenCaptureService", "Final fallback startForeground failed: ${e.message}")
                    }
                }
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val fgType = when {
                    allowMediaProjection && micGranted ->
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                    allowMediaProjection ->
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
                    micGranted ->
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                    else ->
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                }
                try {
                    startForeground(NOTIFICATION_ID, notification, fgType)
                } catch (ex: Exception) {
                    startForeground(NOTIFICATION_ID, notification)
                }
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val fgType = if (allowMediaProjection) {
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
                } else {
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                }
                try {
                    startForeground(NOTIFICATION_ID, notification, fgType)
                } catch (ex: Exception) {
                    startForeground(NOTIFICATION_ID, notification)
                }
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            Log.e("ScreenCaptureService", "startForegroundSafe error: ${e.message}")
        }
    }

    private fun cleanupAndStop() {
        try {
            activeMediaProjection?.stop()
            activeMediaProjection = null
            releaseLocks()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            stopSelf()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "KidGuard स्क्रीन व ऑडियो प्रसारण सेवा",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "स्क्रीन और माइक्रोफोन शेयरिंग के दौरान सक्रिय बैकग्राउंड सेवा"
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            manager?.createNotificationChannel(channel)
        }
    }

    override fun onDestroy() {
        try {
            activeMediaProjection?.stop()
            activeMediaProjection = null
            releaseLocks()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        super.onDestroy()
    }
}
