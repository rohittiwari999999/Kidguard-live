package com.example.kidguard_live

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.kidguard_live/screen_capture"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startForegroundService", "prepareScreenCapture" -> {
                    try {
                        val serviceIntent = Intent(this, ScreenCaptureService::class.java).apply {
                            action = ScreenCaptureService.ACTION_START
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(serviceIntent)
                        } else {
                            startService(serviceIntent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        e.printStackTrace()
                        // Non-fatal: return true so getDisplayMedia can still proceed safely
                        result.success(true)
                    }
                }
                "upgradeScreenCaptureService" -> {
                    try {
                        val serviceIntent = Intent(this, ScreenCaptureService::class.java).apply {
                            action = ScreenCaptureService.ACTION_UPGRADE
                        }
                        // Service is already running in foreground; startService avoids
                        // ForegroundServiceStartNotAllowedException during Activity resume transition
                        startService(serviceIntent)
                    } catch (e: Exception) {
                        try {
                            val fallbackIntent = Intent(this, ScreenCaptureService::class.java).apply {
                                action = ScreenCaptureService.ACTION_UPGRADE
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(fallbackIntent)
                            } else {
                                startService(fallbackIntent)
                            }
                        } catch (inner: Exception) {
                            inner.printStackTrace()
                        }
                    }
                    result.success(true)
                }
                "stopScreenCapture" -> {
                    try {
                        stopService(Intent(this, ScreenCaptureService::class.java))
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
