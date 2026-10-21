package com.example.kidguard_live

import android.app.Activity
import android.content.Context
import android.content.Intent
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
                "prepareScreenCapture" -> {
                    // No separate native dialog! flutter_webrtc will show the single system dialog.
                    result.success(true)
                }
                "stopScreenCapture" -> {
                    try {
                        val serviceIntent = Intent(this, ScreenCaptureService::class.java).apply {
                            action = ScreenCaptureService.ACTION_STOP
                        }
                        startService(serviceIntent)
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
        // Android 14/15/16 Single-Dialog Solution:
        // When flutter_webrtc's single screen capture dialog completes with RESULT_OK:
        // 1. Immediately launch ScreenCaptureService (foreground service of type mediaProjection)
        // 2. Postpone super.onActivityResult by 450ms so the service transitions to active foreground
        // 3. flutter_webrtc then calls getMediaProjection() successfully without SecurityException!
        if (resultCode == Activity.RESULT_OK && data != null) {
            try {
                val serviceIntent = Intent(this, ScreenCaptureService::class.java).apply {
                    action = ScreenCaptureService.ACTION_START
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(serviceIntent)
                } else {
                    startService(serviceIntent)
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }

            // Give 450ms for the Android OS to register the mediaProjection foreground service
            Handler(Looper.getMainLooper()).postDelayed({
                super.onActivityResult(requestCode, resultCode, data)
            }, 450)
            return
        }

        super.onActivityResult(requestCode, resultCode, data)
    }
}
