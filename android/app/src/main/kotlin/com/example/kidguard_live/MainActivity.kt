package com.example.kidguard_live

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.kidguard_live/screen_capture"
    private val REQUEST_SCREEN_CAPTURE = 2001
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isIgnoringBatteryOptimizations" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
                            result.success(pm?.isIgnoringBatteryOptimizations(packageName) == true)
                        } else {
                            result.success(true)
                        }
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "requestIgnoreBatteryOptimizations" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
                            if (pm?.isIgnoringBatteryOptimizations(packageName) == true) {
                                result.success(true)
                                return@setMethodCallHandler
                            }
                            try {
                                val intent = Intent(
                                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                    Uri.parse("package:$packageName")
                                )
                                startActivity(intent)
                                result.success(true)
                                return@setMethodCallHandler
                            } catch (_: Exception) {
                                val fallback = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                                startActivity(fallback)
                                result.success(true)
                                return@setMethodCallHandler
                            }
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        e.printStackTrace()
                        result.success(false)
                    }
                }
                "startForegroundService" -> {
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
                        result.success(true)
                    }
                }
                "prepareScreenCapture" -> {
                    try {
                        // 1. Pre-start foreground service with safe DATA_SYNC/MICROPHONE while Activity is foreground
                        try {
                            val preIntent = Intent(this, ScreenCaptureService::class.java).apply {
                                action = ScreenCaptureService.ACTION_START
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(preIntent)
                            } else {
                                startService(preIntent)
                            }
                        } catch (svcEx: Exception) {
                            svcEx.printStackTrace()
                        }

                        // 2. Clear any stale pendingResult safely before launching MediaProjection dialog
                        pendingResult?.let { stale ->
                            try {
                                stale.success(false)
                            } catch (_: Exception) {}
                        }
                        pendingResult = result

                        val mediaProjectionManager =
                            getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                        startActivityForResult(
                            mediaProjectionManager.createScreenCaptureIntent(),
                            REQUEST_SCREEN_CAPTURE
                        )
                    } catch (e: Exception) {
                        e.printStackTrace()
                        pendingResult = null
                        result.error("ERROR", e.message, null)
                    }
                }
                "upgradeScreenCaptureService" -> {
                    try {
                        val serviceIntent = Intent(this, ScreenCaptureService::class.java).apply {
                            action = ScreenCaptureService.ACTION_UPGRADE
                        }
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

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_SCREEN_CAPTURE) {
            val callback = pendingResult
            pendingResult = null
            if (resultCode == Activity.RESULT_OK && data != null) {
                // Now that Android OS has granted MediaProjection consent, immediately upgrade
                // ScreenCaptureService to FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION | MICROPHONE
                // BEFORE flutter_webrtc calls getMediaProjection().
                try {
                    val upgradeIntent = Intent(this, ScreenCaptureService::class.java).apply {
                        action = ScreenCaptureService.ACTION_UPGRADE
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(upgradeIntent)
                    } else {
                        startService(upgradeIntent)
                    }
                } catch (e: Exception) {
                    e.printStackTrace()
                }

                // Wait 450ms for startForeground(MEDIA_PROJECTION) to bind before resolving Dart
                Handler(Looper.getMainLooper()).postDelayed({
                    try {
                        callback?.success(true)
                    } catch (_: Exception) {}
                }, 450)
            } else {
                try {
                    stopService(Intent(this, ScreenCaptureService::class.java))
                } catch (_: Exception) {}
                try {
                    callback?.success(false)
                } catch (_: Exception) {}
            }
        }
    }
}
