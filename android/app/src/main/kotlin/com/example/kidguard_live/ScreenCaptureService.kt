package com.example.kidguard_live

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Native Android Foreground Service for 24/7 Screen Capture without Chrome.
 * Supports Android 7.0 (API 24) to Android 14/15/16 (API 34+).
 * Keeps app alive in background while WebRTC streams the screen.
 * Safely holds user-approved MediaProjection token to prevent Android 14/15/16 SecurityExceptions.
 */
class ScreenCaptureService : Service() {

    companion object {
        const val ACTION_START = "ACTION_START"
        const val ACTION_STOP = "ACTION_STOP"
        const val EXTRA_RESULT_CODE = "EXTRA_RESULT_CODE"
        const val EXTRA_DATA = "EXTRA_DATA"
        const val CHANNEL_ID = "kidguard_screen_channel"
        const val NOTIFICATION_ID = 1001

        var activeMediaProjection: MediaProjection? = null
            private set
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, Activity.RESULT_CANCELED)
                val data: Intent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(EXTRA_DATA, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(EXTRA_DATA)
                }

                // 1. Immediately enter foreground state to satisfy Android 14+ requirements
                startForegroundWithNotification()

                // 2. Initialize MediaProjection with granted token if available
                if (resultCode == Activity.RESULT_OK && data != null) {
                    try {
                        val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                        activeMediaProjection?.stop()
                        activeMediaProjection = mpm.getMediaProjection(resultCode, data)
                        activeMediaProjection?.registerCallback(object : MediaProjection.Callback() {
                            override fun onStop() {
                                super.onStop()
                                activeMediaProjection = null
                            }
                        }, Handler(Looper.getMainLooper()))
                        Log.d("ScreenCaptureService", "MediaProjection successfully acquired")
                    } catch (e: Exception) {
                        Log.e("ScreenCaptureService", "MediaProjection acquisition notice: ${e.message}")
                    }
                }
            }
            ACTION_STOP -> {
                try {
                    activeMediaProjection?.stop()
                    activeMediaProjection = null
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
        }
        return START_NOT_STICKY
    }

    private fun startForegroundWithNotification() {
        try {
            val stopIntent = Intent(this, ScreenCaptureService::class.java).apply {
                action = ACTION_STOP
            }
            val stopPendingIntent = PendingIntent.getService(
                this,
                0,
                stopIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val safeIcon = applicationInfo.icon.takeIf { it != 0 } ?: android.R.drawable.ic_dialog_info

            val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("KidGuard Live: स्क्रीन लाइव प्रसारित हो रही है")
                .setContentText("माता-पिता के फोन पर लाइव दिख रही है (सक्रिय बैकग्राउंड सेवा)")
                .setSmallIcon(safeIcon)
                .setOngoing(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .addAction(android.R.drawable.ic_media_pause, "स्क्रीन शेयर रोकें", stopPendingIntent)
                .build()

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                try {
                    startForeground(
                        NOTIFICATION_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
                    )
                } catch (typeEx: Exception) {
                    Log.w("ScreenCaptureService", "startForeground mediaProjection fallback: ${typeEx.message}")
                    try {
                        startForeground(NOTIFICATION_ID, notification)
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                }
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "KidGuard स्क्रीन प्रसारण सेवा",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "स्क्रीन शेयरिंग के दौरान सक्रिय बैकग्राउंड सेवा"
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            manager?.createNotificationChannel(channel)
        }
    }

    override fun onDestroy() {
        try {
            activeMediaProjection?.stop()
            activeMediaProjection = null
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
