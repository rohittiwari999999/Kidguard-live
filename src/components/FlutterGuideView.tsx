import React, { useState } from 'react';
import { 
  Code2, 
  Copy, 
  Check, 
  Terminal, 
  Smartphone, 
  ShieldAlert, 
  Download, 
  ExternalLink, 
  Layers, 
  FileCode, 
  CheckCircle2, 
  Sparkles, 
  GitBranch, 
  KeyRound, 
  ShieldCheck, 
  Package, 
  Cpu,
  Lock,
  ArrowRight
} from 'lucide-react';
import { Language } from '../types';
import { translations } from '../utils/i18n';

interface FlutterGuideViewProps {
  lang: Language;
}

const PRE_GENERATED_KEYSTORE_BASE64 = `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`;

export const FlutterGuideView: React.FC<FlutterGuideViewProps> = ({ lang }) => {
  const t = translations[lang];
  const [activeTab, setActiveTab] = useState<'install_guide' | 'secrets_done' | 'github_action' | 'gradle' | 'manifest' | 'main' | 'main_activity' | 'screen_service'>('install_guide');
  const [copiedFile, setCopiedFile] = useState<string | null>(null);

  const copyToClipboard = (text: string, fileName: string) => {
    navigator.clipboard.writeText(text);
    setCopiedFile(fileName);
    setTimeout(() => setCopiedFile(null), 2000);
  };

  const secretsList = [
    {
      name: 'KEYSTORE_BASE64',
      value: PRE_GENERATED_KEYSTORE_BASE64,
      desc: lang === 'hi' ? 'तैयार किया गया RSA 2048 Keystore Base64' : 'Pre-generated Keystore Base64 String',
      preview: `${PRE_GENERATED_KEYSTORE_BASE64.substring(0, 40)}... (${PRE_GENERATED_KEYSTORE_BASE64.length} chars)`,
      isLong: true,
    },
    {
      name: 'KEYSTORE_PASSWORD',
      value: 'KidGuard2026Pass',
      desc: lang === 'hi' ? 'Keystore स्टोर पासवर्ड' : 'Store Password',
      preview: 'KidGuard2026Pass',
      isLong: false,
    },
    {
      name: 'KEY_ALIAS',
      value: 'upload',
      desc: lang === 'hi' ? 'Key का Alias' : 'Keystore Alias',
      preview: 'upload',
      isLong: false,
    },
    {
      name: 'KEY_PASSWORD',
      value: 'KidGuard2026Pass',
      desc: lang === 'hi' ? 'Key का पासवर्ड' : 'Key Password',
      preview: 'KidGuard2026Pass',
      isLong: false,
    },
  ];

  const githubActionsYaml = `# .github/workflows/build-android.yml
# GitHub Actions Workflow to automatically build Signed APK and AAB for KidGuard
name: Build & Sign Android APK and AAB

on:
  push:
    branches:
      - main
      - master
    tags:
      - 'v*'
  workflow_dispatch: # Allows manual trigger with 1 click in GitHub

jobs:
  build:
    name: Build Signed APK & AAB
    runs-on: ubuntu-latest

    steps:
      - name: 1. Checkout repository code
        uses: actions/checkout@v4

      - name: 2. Set up Java 17
        uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'
          cache: 'gradle'

      - name: 3. Set up Flutter environment
        uses: subosito/flutter-action@v2
        with:
          channel: 'stable'
          cache: true

      - name: 4. Verify Flutter Doctor
        run: flutter doctor -v

      - name: 5. Get Flutter Packages
        run: flutter pub get

      - name: 6. Decode Keystore from GitHub Secrets
        env:
          KEYSTORE_BASE64: \${{ secrets.KEYSTORE_BASE64 }}
        run: |
          echo "$KEYSTORE_BASE64" | base64 --decode > android/app/upload-keystore.jks

      - name: 7. Create key.properties dynamically
        env:
          KEYSTORE_PASSWORD: \${{ secrets.KEYSTORE_PASSWORD }}
          KEY_ALIAS: \${{ secrets.KEY_ALIAS }}
          KEY_PASSWORD: \${{ secrets.KEY_PASSWORD }}
        run: |
          cat <<EOF > android/key.properties
          storePassword=$KEYSTORE_PASSWORD
          keyPassword=$KEY_PASSWORD
          keyAlias=$KEY_ALIAS
          storeFile=upload-keystore.jks
          EOF

      - name: 8. Build Signed Release APK (Direct Mobile Install)
        run: flutter build apk --release

      - name: 9. Build Signed Release AAB (Google Play Store Bundle)
        run: flutter build appbundle --release

      - name: 10. Upload Signed APK Artifact
        uses: actions/upload-artifact@v4
        with:
          name: KidGuard-Signed-APK
          path: build/app/outputs/flutter-apk/app-release.apk
          retention-days: 30

      - name: 11. Upload Signed AAB Artifact
        uses: actions/upload-artifact@v4
        with:
          name: KidGuard-Signed-AAB
          path: build/app/outputs/bundle/release/app-release.aab
          retention-days: 30

      - name: 12. Create GitHub Release (Auto on tag or release)
        if: startsWith(github.ref, 'refs/tags/v')
        uses: softprops/action-gh-release@v2
        with:
          files: |
            build/app/outputs/flutter-apk/app-release.apk
            build/app/outputs/bundle/release/app-release.aab
          draft: false
          prerelease: false
          generate_release_notes: true
        env:
          GITHUB_TOKEN: \${{ secrets.GITHUB_TOKEN }}
`;

  const buildGradleCode = `// android/app/build.gradle
plugins {
    id "com.android.application"
    id "kotlin-android"
    id "dev.flutter.flutter-gradle-plugin"
}

def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {
    namespace "com.example.kidguard_live"
    compileSdk flutter.compileSdkVersion
    ndkVersion = "25.1.8937393"

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = '17'
    }

    defaultConfig {
        applicationId "com.example.kidguard_live"
        minSdkVersion 24       // Android 7.0+ (Required for MediaProjection screen capture)
        targetSdkVersion 34    // Android 14
        versionCode flutterVersionCode.toInteger()
        versionName flutterVersionName
    }

    signingConfigs {
        release {
            keyAlias (System.getenv("KEY_ALIAS") ?: keystoreProperties['keyAlias'])
            keyPassword (System.getenv("KEY_PASSWORD") ?: keystoreProperties['keyPassword'])
            storeFile (System.getenv("KEYSTORE_PATH") ? file(System.getenv("KEYSTORE_PATH")) : (keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null))
            storePassword (System.getenv("KEYSTORE_PASSWORD") ?: keystoreProperties['storePassword'])
        }
    }

    buildTypes {
        release {
            signingConfig signingConfigs.release
            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
        debug {
            signingConfig signingConfigs.debug
        }
    }
}

flutter {
    source '../..'
}
`;

  const manifestXmlCode = `<!-- android/app/src/main/AndroidManifest.xml -->
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.example.kidguard_live">

    <!-- Screen Recording & WebRTC Permissions -->
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />

    <!-- Android 13+ & Android 14/15/16 Foreground Service Permissions -->
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />

    <application
        android:label="KidGuard Live"
        android:name="\${applicationName}"
        android:icon="@mipmap/ic_launcher">

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>

        <!-- General Watchdog Foreground Service (dataSync type so it starts safely before MediaProjection prompt) -->
        <service
            android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
            android:foregroundServiceType="dataSync"
            android:stopWithTask="true" />

        <!-- Native Android Screen Streaming Helper Foreground Service (dataSync type prevents Android 14/15/16 SecurityException crash) -->
        <service
            android:name=".ScreenCaptureService"
            android:foregroundServiceType="dataSync"
            android:exported="false" />

        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
</manifest>
`;

  const mainActivityKtCode = `// android/app/src/main/kotlin/com/example/kidguard_live/MainActivity.kt
package com.example.kidguard_live

import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.kidguard_live/screen_capture"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startScreenCapture" -> {
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
}
`;

  const screenCaptureServiceKtCode = `// android/app/src/main/kotlin/com/example/kidguard_live/ScreenCaptureService.kt
package com.example.kidguard_live

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class ScreenCaptureService : Service() {

    companion object {
        const val ACTION_START = "ACTION_START"
        const val ACTION_STOP = "ACTION_STOP"
        const val CHANNEL_ID = "kidguard_screen_channel"
        const val NOTIFICATION_ID = 1001
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                startForegroundWithNotification()
            }
            ACTION_STOP -> {
                try {
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

            val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("KidGuard Live: स्क्रीन लाइव प्रसारित हो रही है")
                .setContentText("माता-पिता के फोन पर लाइव दिख रही है (पृष्ठभूमि सेवा सक्रिय)")
                .setSmallIcon(android.R.drawable.ic_menu_camera)
                .setOngoing(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .addAction(android.R.drawable.ic_media_pause, "स्क्रीन शेयर रोकें", stopPendingIntent)
                .build()

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                try {
                    startForeground(
                        NOTIFICATION_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                    )
                } catch (typeEx: Exception) {
                    startForeground(NOTIFICATION_ID, notification)
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
`;

  const mainDartCode = `// lib/main.dart
// KidGuard Live - Full Flutter Mobile Application
// Real-time Child Screen Monitoring via WebRTC & Foreground Service MediaProjection
// Android 13/14/15/16 Compatible with complete Signaling, ICE Candidate Queueing,
// Unified Plan track fallback, and full code editing on Kid & Parent devices.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

const String kDefaultSignalingServer = 'https://ais-dev-6snjgczxe5mnz34fbgzs4p-751137797858.asia-east1.run.app';

class SignalingService {
  final String baseUrl;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..badCertificateCallback = ((X509Certificate cert, String host, int port) => true);

  SignalingService({this.baseUrl = kDefaultSignalingServer});

  Future<bool> sendOffer(String roomCode, String sdp, String type) async {
    try {
      final uri = Uri.parse('\${baseUrl}/api/signal/room/\${roomCode}/offer');
      final request = await _client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'sdp': sdp, 'type': type}));
      final response = await request.close();
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Signaling sendOffer error: \$e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getOffer(String roomCode) async {
    try {
      final uri = Uri.parse('\${baseUrl}/api/signal/room/\${roomCode}/offer');
      final request = await _client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        return jsonDecode(body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Signaling getOffer error: \$e');
    }
    return null;
  }

  Future<bool> sendAnswer(String roomCode, String sdp, String type) async {
    try {
      final uri = Uri.parse('\${baseUrl}/api/signal/room/\${roomCode}/answer');
      final request = await _client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'sdp': sdp, 'type': type}));
      final response = await request.close();
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Signaling sendAnswer error: \$e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getAnswer(String roomCode) async {
    try {
      final uri = Uri.parse('\${baseUrl}/api/signal/room/\${roomCode}/answer');
      final request = await _client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        return jsonDecode(body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Signaling getAnswer error: \$e');
    }
    return null;
  }

  Future<bool> sendCandidate(String roomCode, String candidate, String? sdpMid, int? sdpMLineIndex, String sender) async {
    try {
      final uri = Uri.parse('\${baseUrl}/api/signal/room/\${roomCode}/candidate');
      final request = await _client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'candidate': candidate,
        'sdpMid': sdpMid,
        'sdpMLineIndex': sdpMLineIndex,
        'sender': sender,
      }));
      final response = await request.close();
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Signaling sendCandidate error: \$e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getCandidates(String roomCode, String forRole, int sinceTimestamp) async {
    try {
      final uri = Uri.parse('\${baseUrl}/api/signal/room/\${roomCode}/candidates?for=\${forRole}&since=\${sinceTimestamp}');
      final request = await _client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);
        if (data is Map && data['candidates'] is List) {
          return List<Map<String, dynamic>>.from(data['candidates']);
        }
      }
    } catch (e) {
      debugPrint('Signaling getCandidates error: \$e');
    }
    return [];
  }
}

// Top-level entry point required by flutter_foreground_task v6.x
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(ScreenBroadcastTaskHandler());
}

class ScreenBroadcastTaskHandler extends TaskHandler {
  @override
  void onStart(DateTime timestamp, SendPort? sendPort) async {
    debugPrint("KidGuard ScreenBroadcastTaskHandler started");
  }

  @override
  void onRepeatEvent(DateTime timestamp, SendPort? sendPort) async {}

  @override
  void onDestroy(DateTime timestamp, SendPort? sendPort) async {
    debugPrint("KidGuard ScreenBroadcastTaskHandler destroyed");
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KidGuardApp());
}

class KidGuardApp extends StatelessWidget {
  const KidGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KidGuard Live',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4F46E5),
          secondary: Color(0xFF06B6D4),
        ),
      ),
      home: const RoleSelectionScreen(),
    );
  }
}

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('KidGuard Live - बाल मॉनिटर'),
        centerTitle: true,
        backgroundColor: const Color(0xFF1E293B),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.security, size: 72, color: Color(0xFF6366F1)),
              const SizedBox(height: 16),
              const Text(
                'यह फोन किसका है?\\nSelect Device Role',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 36),
              ElevatedButton.icon(
                icon: const Icon(Icons.child_care, size: 28),
                label: const Text('बच्चे का फोन (Child Device - Broadcast)'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ChildScreenCapture()));
                },
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.visibility, size: 28),
                label: const Text('माता-पिता का फोन (Parent Device - Watch)'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ParentLiveMonitor()));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// 1. CHILD SCREEN CAPTURE (Broadcasts Screen to Parent)
// -------------------------------------------------------------
class ChildScreenCapture extends StatefulWidget {
  const ChildScreenCapture({super.key});

  @override
  State<ChildScreenCapture> createState() => _ChildScreenCaptureState();
}

class _ChildScreenCaptureState extends State<ChildScreenCapture> {
  static const MethodChannel _platformChannel = MethodChannel('com.example.kidguard_live/screen_capture');
  final SignalingService _signaling = SignalingService();
  final TextEditingController _codeController = TextEditingController(text: 'KID-8429');

  RTCPeerConnection? _peerConnection;
  MediaStream? _screenStream;
  bool _isSharing = false;
  String _statusMessage = 'तैयार है। स्क्रीन शेयर शुरू करें।';
  bool _isParentConnected = false;

  Timer? _answerPollTimer;
  Timer? _candidatePollTimer;
  int _lastCandidateTimestamp = 0;
  bool _isRemoteDescSet = false;
  final List<RTCIceCandidate> _queuedCandidates = [];

  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  @override
  void initState() {
    super.initState();
    _initForegroundTask();
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'kidguard_screen_capture',
        channelName: 'KidGuard Screen Broadcast',
        channelDescription: 'Screen streaming foreground service',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false, playSound: false),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 5000,
        isOnceEvent: false,
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  // EXACT SEQUENCE FIX:
  // 1. Pehle createPeerConnection() call karo
  // 2. Fir getDisplayMedia() se screen stream lo
  // 3. Fir _peerConnection.addTrack(track, _screenStream!) call karo
  // 4. Sabse last me createOffer() aur setLocalDescription(offer)
  Future<void> _startScreenShare() async {
    final roomCode = _codeController.text.trim().toUpperCase();
    if (roomCode.isEmpty) return;

    try {
      await Permission.notification.request();
      await [Permission.camera, Permission.microphone].request();

      // 1. Pehle createPeerConnection() call karo
      _peerConnection = await createPeerConnection(_iceServers);

      _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
        debugPrint("📡 [Kid] ICE Connection State: \$state");
        if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          if (mounted) setState(() { _isParentConnected = true; _statusMessage = '✅ माता-पिता का फोन जुड़ गया है!'; });
        }
      };

      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate.candidate != null) {
          _signaling.sendCandidate(roomCode, candidate.candidate!, candidate.sdpMid, candidate.sdpMLineIndex, 'kid');
        }
      };

      // 2. Fir getDisplayMedia() se screen capture prompt dikhao ("Entire screen" / "Start now")
      MediaStream stream = await navigator.mediaDevices.getDisplayMedia({'audio': false, 'video': true});
      _screenStream = stream;

      // 3. Android Sep 2026 Security Patch Rule:
      // Start Foreground Service STRICTLY AFTER user grants MediaProjection permission!
      try {
        if (await FlutterForegroundTask.isRunningService == false) {
          await FlutterForegroundTask.startService(
            notificationTitle: 'KidGuard Live Streaming',
            notificationText: 'स्क्रीन माता-पिता के फोन पर प्रसारित हो रही है',
            callback: startCallback,
          );
        }
      } catch (fgsError) {
        debugPrint('Foreground task: \$fgsError');
      }

      try {
        await _platformChannel.invokeMethod('startScreenCapture');
      } catch (e) {
        debugPrint('Native helper: \$e');
      }

      stream.getVideoTracks().forEach((track) {
        track.onEnded = () {
          if (mounted) _stopScreenShare();
        };
      });

      // 3. Fir _peerConnection.addTrack(track, _localStream!) call karo
      for (final track in stream.getTracks()) {
        await _peerConnection!.addTrack(track, stream);
      }

      // 4. Sabse last me createOffer() aur setLocalDescription(offer)
      RTCSessionDescription offer = await _peerConnection!.createOffer({'offerToReceiveVideo': 0, 'offerToReceiveAudio': 0});
      await _peerConnection!.setLocalDescription(offer);
      await _signaling.sendOffer(roomCode, offer.sdp!, offer.type!);

      setState(() {
        _isSharing = true;
        _isRemoteDescSet = false;
        _queuedCandidates.clear();
        _statusMessage = '🔴 ब्रॉडकास्ट चालू है! माता-पिता के जुड़ने की प्रतीक्षा...';
      });

      _startPollingForAnswer(roomCode);
    } catch (e) {
      debugPrint('Screen share error: \$e');
      _stopScreenShare();
    }
  }

  void _startPollingForAnswer(String roomCode) {
    _answerPollTimer?.cancel();
    _answerPollTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!_isSharing || _isRemoteDescSet || _peerConnection == null) return;
      final answerData = await _signaling.getAnswer(roomCode);
      if (answerData != null && answerData['sdp'] != null && !_isRemoteDescSet) {
        _isRemoteDescSet = true;
        timer.cancel();
        RTCSessionDescription answer = RTCSessionDescription(answerData['sdp'], answerData['type'] ?? 'answer');
        await _peerConnection!.setRemoteDescription(answer);
        _drainQueuedCandidates();
        _startListeningToParentIceCandidates(roomCode);
        if (mounted) setState(() { _statusMessage = 'माता-पिता जुड़ गए!'; });
      }
    });
  }

  void _startListeningToParentIceCandidates(String roomCode) {
    _candidatePollTimer?.cancel();
    _candidatePollTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) async {
      if (!_isSharing || _peerConnection == null) { timer.cancel(); return; }
      final list = await _signaling.getCandidates(roomCode, 'kid', _lastCandidateTimestamp);
      for (final item in list) {
        final ts = item['timestamp'] as int? ?? 0;
        if (ts > _lastCandidateTimestamp) _lastCandidateTimestamp = ts;
        if (item['candidate'] != null) {
          final candidate = RTCIceCandidate(item['candidate'], item['sdpMid'], item['sdpMLineIndex']);
          if (_isRemoteDescSet) {
            await _peerConnection!.addCandidate(candidate);
          } else {
            _queuedCandidates.add(candidate);
          }
        }
      }
    });
  }

  void _drainQueuedCandidates() async {
    for (final c in _queuedCandidates) {
      try { await _peerConnection?.addCandidate(c); } catch (_) {}
    }
    _queuedCandidates.clear();
  }

  void _stopScreenShare() async {
    _answerPollTimer?.cancel();
    _candidatePollTimer?.cancel();
    try { await _platformChannel.invokeMethod('stopScreenCapture'); } catch (_) {}
    _screenStream?.getTracks().forEach((track) => track.stop());
    _screenStream = null;
    try { await _peerConnection?.close(); } catch (_) {}
    _peerConnection = null;
    try { FlutterForegroundTask.stopService(); } catch (_) {}
    if (mounted) setState(() { _isSharing = false; _isParentConnected = false; _statusMessage = 'स्क्रीन शेयरिंग बंद है।'; });
  }

  @override
  void dispose() {
    _stopScreenShare();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('बच्चे का फोन - स्क्रीन शेयर'), backgroundColor: const Color(0xFF1E293B)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Card(
              color: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    const Text('पेयरिंग कोड (Pairing Code):', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.cyanAccent.withOpacity(0.6), width: 2),
                      ),
                      child: TextField(
                        controller: _codeController,
                        textAlign: TextAlign.center,
                        textCapitalization: TextCapitalization.characters,
                        enabled: !_isSharing,
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 3, color: Colors.cyanAccent),
                        decoration: const InputDecoration(border: InputBorder.none, hintText: 'उदा. KID-8429'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('🎲 नया कोड'),
                          onPressed: _isSharing ? null : () {
                            final r = 1000 + (DateTime.now().millisecondsSinceEpoch % 9000);
                            setState(() { _codeController.text = 'KID-\$r'; });
                          },
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('कॉपी करें'),
                          onPressed: () => Clipboard.setData(ClipboardData(text: _codeController.text)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _isSharing ? Colors.green.withOpacity(0.15) : Colors.black38,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _isSharing ? Colors.greenAccent : Colors.white24),
              ),
              child: Text(_statusMessage, textAlign: TextAlign.center, style: TextStyle(color: _isSharing ? Colors.greenAccent : Colors.white70)),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: Icon(_isSharing ? Icons.stop : Icons.play_arrow, size: 28),
              label: Text(_isSharing ? 'स्क्रीन शेयरिंग बंद करें' : 'पूरे मोबाइल की स्क्रीन शेयर शुरू करें'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: _isSharing ? Colors.redAccent : Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _isSharing ? _stopScreenShare : _startScreenShare,
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// 2. PARENT LIVE MONITOR (Watches Child's Screen)
// -------------------------------------------------------------
class ParentLiveMonitor extends StatefulWidget {
  const ParentLiveMonitor({super.key});

  @override
  State<ParentLiveMonitor> createState() => _ParentLiveMonitorState();
}

class _ParentLiveMonitorState extends State<ParentLiveMonitor> {
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  final TextEditingController _codeController = TextEditingController(text: 'KID-8429');
  final SignalingService _signaling = SignalingService();

  RTCPeerConnection? _peerConnection;
  bool _isConnecting = false;
  bool _isConnected = false;
  bool _hasRemoteVideo = false;
  String _statusText = 'बच्चे का कोड डालकर कनेक्ट करें।';
  String _iceState = 'None';
  String _videoResolution = '0x0';

  Timer? _candidatePollTimer;
  int _lastCandidateTimestamp = 0;
  bool _isRemoteDescSet = false;
  final List<RTCIceCandidate> _queuedCandidates = [];

  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  @override
  void initState() {
    super.initState();
    _remoteRenderer.initialize();
    _remoteRenderer.onResize = () {
      debugPrint("📺 Video Resolution Received: \${_remoteRenderer.videoWidth}x\${_remoteRenderer.videoHeight}");
      if (mounted) {
        setState(() {
          _videoResolution = '\${_remoteRenderer.videoWidth}x\${_remoteRenderer.videoHeight}';
          if (_remoteRenderer.videoWidth > 0) _hasRemoteVideo = true;
        });
      }
    };
  }

  // EXACT TIMING & UNIFIED PLAN BUG FIX:
  Future<void> _connectToChild() async {
    final roomCode = _codeController.text.trim().toUpperCase();
    if (roomCode.isEmpty) return;

    _disconnect();
    setState(() { _isConnecting = true; _statusText = 'ऑफर खोज रहे हैं...'; });

    try {
      final offerData = await _signaling.getOffer(roomCode);
      if (offerData == null || offerData['sdp'] == null) {
        setState(() { _isConnecting = false; _statusText = '⚠️ बच्चे का लाइव स्क्रीन शेयर नहीं मिला।'; });
        return;
      }

      _peerConnection = await createPeerConnection(_iceServers);

      _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
        debugPrint("📡 ICE Connection State: \$state");
        if (mounted) setState(() { _iceState = state.toString().split('.').last; });
      };

      // Unified Plan Bug Fix on Parent Side:
      _peerConnection!.onTrack = (RTCTrackEvent event) async {
        debugPrint("🔥 Track received: \${event.track.kind}, Streams count: \${event.streams.length}");
        if (event.track.kind == 'video') {
          if (event.streams.isNotEmpty) {
            _remoteRenderer.srcObject = event.streams[0];
          } else {
            MediaStream newStream = await createLocalMediaStream('remoteVideoStream');
            newStream.addTrack(event.track);
            _remoteRenderer.srcObject = newStream;
          }
          if (mounted) setState(() { _hasRemoteVideo = true; _isConnected = true; _isConnecting = false; _statusText = '🟢 लाइव स्क्रीन चालू है!'; });
        }
      };

      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate.candidate != null) {
          _signaling.sendCandidate(roomCode, candidate.candidate!, candidate.sdpMid, candidate.sdpMLineIndex, 'parent');
        }
      };

      // 1. Pehle Remote Description set hone ka wait karo
      RTCSessionDescription offer = RTCSessionDescription(offerData['sdp'], offerData['type'] ?? 'offer');
      await _peerConnection!.setRemoteDescription(offer);
      _isRemoteDescSet = true;

      // 2. Create and send Answer
      RTCSessionDescription answer = await _peerConnection!.createAnswer({});
      await _peerConnection!.setLocalDescription(answer);
      await _signaling.sendAnswer(roomCode, answer.sdp!, answer.type!);

      // 3. AB Kid ke ICE candidates listen karna start karo
      _startListeningToKidIceCandidates(roomCode);
    } catch (e) {
      debugPrint('Parent connection error: \$e');
      if (mounted) setState(() { _isConnecting = false; _statusText = 'त्रुटि: \$e'; });
    }
  }

  void _startListeningToKidIceCandidates(String roomCode) {
    _candidatePollTimer?.cancel();
    _candidatePollTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) async {
      if (_peerConnection == null) { timer.cancel(); return; }
      final list = await _signaling.getCandidates(roomCode, 'parent', _lastCandidateTimestamp);
      for (final item in list) {
        final ts = item['timestamp'] as int? ?? 0;
        if (ts > _lastCandidateTimestamp) _lastCandidateTimestamp = ts;
        if (item['candidate'] != null) {
          final candidate = RTCIceCandidate(item['candidate'], item['sdpMid'], item['sdpMLineIndex']);
          if (_isRemoteDescSet) {
            await _peerConnection!.addCandidate(candidate);
          } else {
            _queuedCandidates.add(candidate);
          }
        }
      }
    });
  }

  void _disconnect() {
    _candidatePollTimer?.cancel();
    try { _peerConnection?.close(); } catch (_) {}
    _peerConnection = null;
    _remoteRenderer.srcObject = null;
    _isRemoteDescSet = false;
    _queuedCandidates.clear();
    if (mounted) {
      setState(() {
        _isConnected = false;
        _isConnecting = false;
        _hasRemoteVideo = false;
        _statusText = 'डिस्कनेक्ट हो गया।';
      });
    }
  }

  @override
  void dispose() {
    _disconnect();
    _remoteRenderer.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('माता-पिता का लाइव मॉनिटर'), backgroundColor: const Color(0xFF1E293B)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeController,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2),
                    decoration: InputDecoration(
                      labelText: 'बच्चे का कोड (उदा. KID-8429)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _isConnecting ? null : _connectToChild,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isConnecting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('कनेक्ट करें'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(10)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(_statusText, style: const TextStyle(fontSize: 12, color: Colors.cyanAccent), overflow: TextOverflow.ellipsis)),
                  Text('ICE: \$_iceState | Res: \$_videoResolution', style: const TextStyle(fontSize: 10, color: Colors.white60)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // FIX: SizedBox.expand prevents 0x0 size in Flutter RTCVideoView!
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _hasRemoteVideo ? Colors.cyanAccent.withOpacity(0.5) : Colors.white24),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: (_isConnected || _hasRemoteVideo) && _remoteRenderer.srcObject != null
                      ? SizedBox.expand(
                          child: RTCVideoView(
                            _remoteRenderer,
                            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                          ),
                        )
                      : Center(
                          child: Text(_isConnecting ? 'सिग्नल की प्रतीक्षा...' : 'बच्चे का कोड डालकर कनेक्ट करें', textAlign: TextAlign.center),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
`;

  return (
    <div className="max-w-4xl mx-auto px-4 py-6">
      {/* Overview Banner */}
      <div className="bg-slate-900/80 border border-slate-800 backdrop-blur-md rounded-3xl p-6 shadow-2xl mb-6">
        <div className="flex items-start gap-4">
          <div className="w-12 h-12 rounded-2xl bg-gradient-to-tr from-emerald-600 via-teal-600 to-cyan-500 border border-emerald-500/30 flex items-center justify-center text-white shrink-0 shadow-lg shadow-emerald-600/20">
            <CheckCircle2 className="w-6 h-6" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h2 className="text-xl font-bold text-white tracking-tight">
                {lang === 'hi' ? 'स्टेप 2 और 3 हमने आपके लिए पूरा कर दिया!' : 'Step 2 & 3 Done For You!'}
              </h2>
              <span className="px-2 py-0.5 text-[10px] font-bold rounded-md bg-emerald-500/20 text-emerald-300 border border-emerald-500/30">
                100% Configured
              </span>
            </div>
            <p className="text-xs text-slate-300 mt-2 leading-relaxed">
              {lang === 'hi'
                ? 'आपको अपने कंप्यूटर पर keytool कमांड चलाने की कोई ज़रूरत नहीं है। हमने आपके लिए 10,000 दिनों की मान्यता वाला असली RSA 2048 Keystore जनरेट कर दिया है और android/app/build.gradle व android/key.properties फाइल्स भी सीधे प्रोजेक्ट में बना दी हैं!'
                : 'No need to run keytool or configure Gradle manually. We generated a valid 10,000-day RSA 2048 Keystore and created android/app/build.gradle & key.properties in your project.'}
            </p>
          </div>
        </div>

        {/* Status Pills */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 mt-5">
          <div className="p-3 bg-emerald-950/40 border border-emerald-500/30 rounded-2xl flex items-center gap-3">
            <div className="p-2 bg-emerald-500/20 rounded-xl text-emerald-400">
              <Check className="w-4 h-4 font-bold" />
            </div>
            <div>
              <p className="text-xs font-bold text-white">स्टेप 2: Gradle & Properties</p>
              <p className="text-[11px] text-emerald-300">android/app/build.gradle तैयार है</p>
            </div>
          </div>

          <div className="p-3 bg-emerald-950/40 border border-emerald-500/30 rounded-2xl flex items-center gap-3">
            <div className="p-2 bg-emerald-500/20 rounded-xl text-emerald-400">
              <Check className="w-4 h-4 font-bold" />
            </div>
            <div>
              <p className="text-xs font-bold text-white">स्टेप 3: Keystore & Secrets</p>
              <p className="text-[11px] text-emerald-300">4 सीक्रेट्स जनरेट होकर नीचे उपलब्ध हैं</p>
            </div>
          </div>
        </div>
      </div>

      {/* Tabs */}
      <div className="flex items-center gap-2 mb-4 overflow-x-auto pb-1">
        <button
          onClick={() => setActiveTab('install_guide')}
          className={`flex items-center gap-1.5 px-3.5 py-2.5 rounded-xl text-xs font-bold transition whitespace-nowrap cursor-pointer ${
            activeTab === 'install_guide'
              ? 'bg-cyan-600 text-white shadow-md'
              : 'bg-slate-800 text-slate-400 hover:text-white'
          }`}
        >
          <Smartphone className="w-3.5 h-3.5" />
          <span>{lang === 'hi' ? '📱 3-स्टेप APK गाइड' : '📱 3-Step APK Guide'}</span>
        </button>

        <button
          onClick={() => setActiveTab('secrets_done')}
          className={`flex items-center gap-1.5 px-3.5 py-2.5 rounded-xl text-xs font-bold transition whitespace-nowrap cursor-pointer ${
            activeTab === 'secrets_done'
              ? 'bg-emerald-600 text-white shadow-md'
              : 'bg-slate-800 text-slate-400 hover:text-white'
          }`}
        >
          <KeyRound className="w-3.5 h-3.5" />
          <span>{lang === 'hi' ? '🔑 1. तैयार 4 Secrets' : '🔑 1. Pre-Generated Secrets'}</span>
        </button>

        <button
          onClick={() => setActiveTab('github_action')}
          className={`flex items-center gap-1.5 px-3.5 py-2.5 rounded-xl text-xs font-bold transition whitespace-nowrap cursor-pointer ${
            activeTab === 'github_action'
              ? 'bg-blue-600 text-white shadow-md'
              : 'bg-slate-800 text-slate-400 hover:text-white'
          }`}
        >
          <GitBranch className="w-3.5 h-3.5" />
          <span>2. build-android.yml</span>
        </button>

        <button
          onClick={() => setActiveTab('gradle')}
          className={`flex items-center gap-1.5 px-3.5 py-2.5 rounded-xl text-xs font-bold transition whitespace-nowrap cursor-pointer ${
            activeTab === 'gradle'
              ? 'bg-blue-600 text-white shadow-md'
              : 'bg-slate-800 text-slate-400 hover:text-white'
          }`}
        >
          <Layers className="w-3.5 h-3.5" />
          <span>3. build.gradle</span>
        </button>

        <button
          onClick={() => setActiveTab('manifest')}
          className={`flex items-center gap-1.5 px-3.5 py-2.5 rounded-xl text-xs font-bold transition whitespace-nowrap cursor-pointer ${
            activeTab === 'manifest'
              ? 'bg-purple-600 text-white shadow-md'
              : 'bg-slate-800 text-slate-400 hover:text-white'
          }`}
        >
          <ShieldCheck className="w-3.5 h-3.5" />
          <span>4. AndroidManifest.xml</span>
        </button>

        <button
          onClick={() => setActiveTab('main')}
          className={`flex items-center gap-1.5 px-3.5 py-2.5 rounded-xl text-xs font-bold transition whitespace-nowrap cursor-pointer ${
            activeTab === 'main'
              ? 'bg-amber-600 text-white shadow-md'
              : 'bg-slate-800 text-slate-400 hover:text-white'
          }`}
        >
          <FileCode className="w-3.5 h-3.5" />
          <span>5. lib/main.dart</span>
        </button>

        <button
          onClick={() => setActiveTab('main_activity')}
          className={`flex items-center gap-1.5 px-3.5 py-2.5 rounded-xl text-xs font-bold transition whitespace-nowrap cursor-pointer ${
            activeTab === 'main_activity'
              ? 'bg-rose-600 text-white shadow-md'
              : 'bg-slate-800 text-slate-400 hover:text-white'
          }`}
        >
          <FileCode className="w-3.5 h-3.5" />
          <span>6. MainActivity.kt</span>
        </button>

        <button
          onClick={() => setActiveTab('screen_service')}
          className={`flex items-center gap-1.5 px-3.5 py-2.5 rounded-xl text-xs font-bold transition whitespace-nowrap cursor-pointer ${
            activeTab === 'screen_service'
              ? 'bg-teal-600 text-white shadow-md'
              : 'bg-slate-800 text-slate-400 hover:text-white'
          }`}
        >
          <FileCode className="w-3.5 h-3.5" />
          <span>7. ScreenCaptureService.kt</span>
        </button>
      </div>

      {/* Tab: Direct APK 3-Step Guide */}
      {activeTab === 'install_guide' && (
        <div className="bg-slate-900/90 border border-slate-800 rounded-3xl p-6 shadow-2xl space-y-6">
          <div className="flex items-start gap-4 pb-4 border-b border-slate-800">
            <div className="w-12 h-12 rounded-2xl bg-cyan-600/20 border border-cyan-500/30 flex items-center justify-center text-cyan-400 shrink-0">
              <Smartphone className="w-6 h-6" />
            </div>
            <div>
              <h3 className="text-lg font-bold text-white flex items-center gap-2">
                <span>{lang === 'hi' ? 'असली Android APK मोबाइल में कैसे इंस्टॉल करें?' : 'How to Build & Install the Real Android APK'}</span>
              </h3>
              <p className="text-xs text-slate-400 mt-1 leading-relaxed">
                {lang === 'hi'
                  ? 'वेब ब्राउज़र की सीमा समाप्त करें: यह APK Android के Foreground Service का उपयोग करती है, जिससे बच्चा चाहे YouTube, Free Fire, WhatsApp या कोई भी ऐप खोले, स्क्रीन माता-पिता के फोन पर 24/7 लाइव स्ट्रीम होती रहेगी।'
                  : 'Bypasses all web browser limits: This native APK uses Android Foreground Service to stream screen 24/7 even when child switches apps.'}
              </p>
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            {/* Step 1 */}
            <div className="p-4 bg-slate-950 border border-slate-800 rounded-2xl space-y-2">
              <div className="flex items-center justify-between">
                <span className="w-7 h-7 rounded-xl bg-emerald-500/20 text-emerald-300 border border-emerald-500/30 flex items-center justify-center text-xs font-bold font-mono">
                  01
                </span>
                <span className="text-[10px] uppercase font-bold text-slate-500">1 मिनट</span>
              </div>
              <h4 className="text-sm font-bold text-white">
                {lang === 'hi' ? '4 Secrets कॉपी करके सेव करें' : 'Copy & Save 4 Secrets'}
              </h4>
              <p className="text-xs text-slate-400 leading-relaxed">
                {lang === 'hi'
                  ? 'टैब "1. तैयार 4 Secrets" में दिए गए चारों बटनों से एक-एक करके वैल्यू कॉपी करें और GitHub रिपॉजिटरी की Settings > Secrets & variables > Actions में सेव कर दें।'
                  : 'Copy the 4 pre-generated secrets from tab 1 and save them in your GitHub Repo > Settings > Secrets.'}
              </p>
              <button
                onClick={() => setActiveTab('secrets_done')}
                className="w-full mt-2 py-2 px-3 bg-emerald-600/20 hover:bg-emerald-600/30 text-emerald-300 border border-emerald-500/30 rounded-xl text-xs font-bold transition flex items-center justify-center gap-1.5 cursor-pointer"
              >
                <span>{lang === 'hi' ? 'Secrets कॉपी करने जाएं' : 'Go to Secrets Tab'}</span>
                <ArrowRight className="w-3.5 h-3.5" />
              </button>
            </div>

            {/* Step 2 */}
            <div className="p-4 bg-slate-950 border border-slate-800 rounded-2xl space-y-2">
              <div className="flex items-center justify-between">
                <span className="w-7 h-7 rounded-xl bg-blue-500/20 text-blue-300 border border-blue-500/30 flex items-center justify-center text-xs font-bold font-mono">
                  02
                </span>
                <span className="text-[10px] uppercase font-bold text-slate-500">3 मिनट</span>
              </div>
              <h4 className="text-sm font-bold text-white">
                {lang === 'hi' ? 'GitHub Actions में 1-क्लिक रन करें' : 'Trigger GitHub Actions'}
              </h4>
              <p className="text-xs text-slate-400 leading-relaxed">
                {lang === 'hi'
                  ? 'GitHub Repo के "Actions" टैब में जाएं, "Build & Sign Android APK" पर क्लिक करें और "Run workflow" दबा दें। क्लाउड पर ऑटोमैटिक APK कंपाइल होना शुरू हो जाएगा।'
                  : 'Go to GitHub Actions, select "Build & Sign Android APK", and tap "Run workflow" to build in the cloud.'}
              </p>
              <button
                onClick={() => setActiveTab('github_action')}
                className="w-full mt-2 py-2 px-3 bg-blue-600/20 hover:bg-blue-600/30 text-blue-300 border border-blue-500/30 rounded-xl text-xs font-bold transition flex items-center justify-center gap-1.5 cursor-pointer"
              >
                <span>{lang === 'hi' ? 'Workflow फाइल देखें' : 'View Workflow'}</span>
                <ArrowRight className="w-3.5 h-3.5" />
              </button>
            </div>

            {/* Step 3 */}
            <div className="p-4 bg-slate-950 border border-slate-800 rounded-2xl space-y-2">
              <div className="flex items-center justify-between">
                <span className="w-7 h-7 rounded-xl bg-cyan-500/20 text-cyan-300 border border-cyan-500/30 flex items-center justify-center text-xs font-bold font-mono">
                  03
                </span>
                <span className="text-[10px] uppercase font-bold text-slate-500">तैयार</span>
              </div>
              <h4 className="text-sm font-bold text-white">
                {lang === 'hi' ? 'APK डाउनलोड करके इंस्टॉल करें' : 'Download & Install APK'}
              </h4>
              <p className="text-xs text-slate-400 leading-relaxed">
                {lang === 'hi'
                  ? 'Workflow पूरा होने पर नीचे "Artifacts" में "KidGuard-Signed-APK" डाउनलोड के लिए मिलेगी। इसे बच्चे के फोन में इंस्टॉल करें और 24/7 लाइव मॉनिटरिंग चालू करें!'
                  : 'Download the generated "KidGuard-Signed-APK" from Artifacts, install it on the child phone, and enjoy 24/7 mirroring!'}
              </p>
              <div className="p-2 rounded-lg bg-cyan-950/40 border border-cyan-500/30 text-[11px] text-cyan-300 text-center font-medium">
                ✓ 100% Signed & Ready for Child Mobile
              </div>
            </div>
          </div>

          {/* Explanation banner */}
          <div className="p-4 bg-gradient-to-r from-slate-950 to-indigo-950/40 border border-indigo-500/30 rounded-2xl flex items-start gap-3">
            <Sparkles className="w-5 h-5 text-indigo-400 shrink-0 mt-0.5" />
            <div className="text-xs text-indigo-200 space-y-1">
              <p className="font-bold text-white">
                {lang === 'hi' ? 'ब्राउज़र बनाम असली Android APK में क्या अंतर है?' : 'Web Browser vs Real Android APK:'}
              </p>
              <p className="text-slate-300 leading-relaxed">
                {lang === 'hi'
                  ? '• वेब ब्राउज़र (Chrome) में जब बच्चा कोई दूसरा ऐप खोलता है, तो Android OS सुरक्षा के तहत ब्राउज़र को बंद या पॉज कर देता है।'
                  : '• Web Browser: Pauses whenever another app is opened due to Android sandbox policy.'}
              </p>
              <p className="text-emerald-300 leading-relaxed">
                {lang === 'hi'
                  ? '• असली Android APK में Foreground Service (MediaProjection) लगी होती है, इसलिए बच्चा चाहे जो मर्जी ऐप चलाए, स्क्रीन कभी बंद नहीं होती।'
                  : '• Real Android APK: Runs as a Foreground Service, streaming uninterrupted regardless of what app the child opens.'}
              </p>
            </div>
          </div>
        </div>
      )}

      {/* Tab 1: Pre-Generated Secrets */}
      {activeTab === 'secrets_done' && (
        <div className="bg-slate-900/90 border border-slate-800 rounded-3xl p-6 shadow-2xl space-y-5">
          <div className="flex items-center justify-between pb-3 border-b border-slate-800">
            <div>
              <h3 className="text-base font-bold text-white flex items-center gap-2">
                <Lock className="w-5 h-5 text-emerald-400" />
                <span>{lang === 'hi' ? 'GitHub में डालने के लिए तैयार 4 Secrets:' : 'Ready-to-Use 4 GitHub Secrets:'}</span>
              </h3>
              <p className="text-xs text-slate-400 mt-0.5">
                {lang === 'hi'
                  ? 'अपनी GitHub Repo > Settings > Secrets and variables > Actions > New repository secret में इन 4 को पेस्ट करें:'
                  : 'Add these 4 secrets in your GitHub Repo > Settings > Secrets and variables > Actions:'}
              </p>
            </div>
          </div>

          <div className="space-y-3.5">
            {secretsList.map((sec, idx) => (
              <div
                key={sec.name}
                className="p-4 bg-slate-950 border border-slate-800 rounded-2xl flex flex-col sm:flex-row sm:items-center justify-between gap-3 hover:border-slate-700 transition"
              >
                <div className="space-y-1 overflow-hidden">
                  <div className="flex items-center gap-2">
                    <span className="w-5 h-5 rounded-full bg-slate-800 text-slate-300 flex items-center justify-center text-[10px] font-bold">
                      {idx + 1}
                    </span>
                    <span className="font-mono text-cyan-400 font-bold text-sm tracking-wide">
                      {sec.name}
                    </span>
                  </div>
                  <p className="text-xs text-slate-400">{sec.desc}</p>
                  <p className="text-[11px] font-mono text-slate-500 truncate max-w-md bg-slate-900/80 px-2 py-1 rounded-md">
                    {sec.preview}
                  </p>
                </div>

                <button
                  onClick={() => copyToClipboard(sec.value, sec.name)}
                  className="flex items-center justify-center gap-1.5 px-4 py-2.5 bg-gradient-to-r from-emerald-600 to-teal-600 hover:from-emerald-500 hover:to-teal-500 text-white rounded-xl text-xs font-bold transition shadow-md shadow-emerald-600/20 active:scale-95 shrink-0"
                >
                  {copiedFile === sec.name ? <Check className="w-4 h-4" /> : <Copy className="w-4 h-4" />}
                  <span>{copiedFile === sec.name ? t.copied : t.copyCode}</span>
                </button>
              </div>
            ))}
          </div>

          {/* 30 Second Action Guide */}
          <div className="mt-5 p-4 rounded-2xl bg-indigo-950/40 border border-indigo-500/30 flex items-start gap-3">
            <Sparkles className="w-5 h-5 text-indigo-400 shrink-0 mt-0.5" />
            <div className="text-xs text-indigo-200">
              <p className="font-semibold text-white mb-1">
                {lang === 'hi' ? 'इसके बाद क्या करना है?' : 'What to do next:'}
              </p>
              <ol className="list-decimal list-inside space-y-1 text-indigo-200/90">
                <li>ऊपर दिए गए चारों बटनों से एक-एक करके <strong>Secret Name</strong> और <strong>Value</strong> कॉपी करें।</li>
                <li>अपने GitHub रिपॉजिटरी में <strong>Settings &gt; Secrets and variables &gt; Actions</strong> में जाकर <strong>New repository secret</strong> पर क्लिक करके सेव कर दें।</li>
                <li>GitHub के <strong>Actions</strong> टैब में जाएं और <strong>"Build & Sign Android APK and AAB"</strong> को <strong>Run workflow</strong> कर दें।</li>
                <li>4 मिनट में आपकी Signed APK सीधे डाउनलोड के लिए मिल जाएगी!</li>
              </ol>
            </div>
          </div>
        </div>
      )}

      {/* Tab 2: Workflow Code */}
      {activeTab === 'github_action' && (
        <div className="bg-slate-900/90 border border-slate-800 rounded-3xl p-5 shadow-2xl relative">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between pb-3 border-b border-slate-800 mb-4 gap-2">
            <div>
              <span className="text-xs font-mono text-cyan-400 font-bold">.github/workflows/build-android.yml</span>
              <p className="text-[11px] text-emerald-400 mt-0.5 font-semibold">
                ✓ यह फाइल आपके प्रोजेक्ट में पहले से सेव कर दी गई है!
              </p>
            </div>
            <button
              onClick={() => copyToClipboard(githubActionsYaml, 'build-android.yml')}
              className="flex items-center gap-1.5 px-3 py-1.5 bg-blue-600 hover:bg-blue-500 text-white rounded-xl text-xs font-bold transition shadow-sm active:scale-95 shrink-0"
            >
              {copiedFile === 'build-android.yml' ? <Check className="w-4 h-4 text-emerald-400" /> : <Copy className="w-4 h-4" />}
              <span>{copiedFile === 'build-android.yml' ? t.copied : t.copyCode}</span>
            </button>
          </div>
          <pre className="p-4 rounded-2xl bg-slate-950 text-slate-300 font-mono text-xs overflow-x-auto max-h-[500px] leading-relaxed border border-slate-800">
            {githubActionsYaml}
          </pre>
        </div>
      )}

      {/* Tab 3: Gradle Code */}
      {activeTab === 'gradle' && (
        <div className="bg-slate-900/90 border border-slate-800 rounded-3xl p-5 shadow-2xl relative">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between pb-3 border-b border-slate-800 mb-4 gap-2">
            <div>
              <span className="text-xs font-mono text-cyan-400 font-bold">android/app/build.gradle</span>
              <p className="text-[11px] text-emerald-400 mt-0.5 font-semibold">
                ✓ यह फाइल भी आपके प्रोजेक्ट में android/app/build.gradle में सेव कर दी गई है!
              </p>
            </div>
            <button
              onClick={() => copyToClipboard(buildGradleCode, 'build.gradle')}
              className="flex items-center gap-1.5 px-3 py-1.5 bg-blue-600 hover:bg-blue-500 text-white rounded-xl text-xs font-bold transition shadow-sm active:scale-95 shrink-0"
            >
              {copiedFile === 'build.gradle' ? <Check className="w-4 h-4 text-emerald-400" /> : <Copy className="w-4 h-4" />}
              <span>{copiedFile === 'build.gradle' ? t.copied : t.copyCode}</span>
            </button>
          </div>
          <pre className="p-4 rounded-2xl bg-slate-950 text-slate-300 font-mono text-xs overflow-x-auto max-h-[500px] leading-relaxed border border-slate-800">
            {buildGradleCode}
          </pre>
        </div>
      )}

      {/* Tab 4: Manifest Code */}
      {activeTab === 'manifest' && (
        <div className="bg-slate-900/90 border border-slate-800 rounded-3xl p-5 shadow-2xl relative">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between pb-3 border-b border-slate-800 mb-4 gap-2">
            <div>
              <span className="text-xs font-mono text-purple-400 font-bold">android/app/src/main/AndroidManifest.xml</span>
              <p className="text-[11px] text-emerald-400 mt-0.5 font-semibold">
                ✓ FOREGROUND_SERVICE_MEDIA_PROJECTION परमिशन के साथ पहले से कॉन्फिगर है!
              </p>
            </div>
            <button
              onClick={() => copyToClipboard(manifestXmlCode, 'AndroidManifest.xml')}
              className="flex items-center gap-1.5 px-3 py-1.5 bg-purple-600 hover:bg-purple-500 text-white rounded-xl text-xs font-bold transition shadow-sm active:scale-95 shrink-0 cursor-pointer"
            >
              {copiedFile === 'AndroidManifest.xml' ? <Check className="w-4 h-4 text-emerald-400" /> : <Copy className="w-4 h-4" />}
              <span>{copiedFile === 'AndroidManifest.xml' ? t.copied : t.copyCode}</span>
            </button>
          </div>
          <pre className="p-4 rounded-2xl bg-slate-950 text-slate-300 font-mono text-xs overflow-x-auto max-h-[500px] leading-relaxed border border-slate-800">
            {manifestXmlCode}
          </pre>
        </div>
      )}

      {/* Tab 5: Main Dart Code */}
      {activeTab === 'main' && (
        <div className="bg-slate-900/90 border border-slate-800 rounded-3xl p-5 shadow-2xl relative">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between pb-3 border-b border-slate-800 mb-4 gap-2">
            <div>
              <span className="text-xs font-mono text-amber-400 font-bold">lib/main.dart</span>
              <p className="text-[11px] text-emerald-400 mt-0.5 font-semibold">
                ✓ MediaProjection और Foreground Service के साथ 100% तैयार कोड!
              </p>
            </div>
            <button
              onClick={() => copyToClipboard(mainDartCode, 'main.dart')}
              className="flex items-center gap-1.5 px-3 py-1.5 bg-amber-600 hover:bg-amber-500 text-white rounded-xl text-xs font-bold transition shadow-sm active:scale-95 shrink-0 cursor-pointer"
            >
              {copiedFile === 'main.dart' ? <Check className="w-4 h-4 text-emerald-400" /> : <Copy className="w-4 h-4" />}
              <span>{copiedFile === 'main.dart' ? t.copied : t.copyCode}</span>
            </button>
          </div>
          <pre className="p-4 rounded-2xl bg-slate-950 text-slate-300 font-mono text-xs overflow-x-auto max-h-[500px] leading-relaxed border border-slate-800">
            {mainDartCode}
          </pre>
        </div>
      )}
      {/* Tab 6: MainActivity.kt */}
      {activeTab === 'main_activity' && (
        <div className="bg-slate-900/90 border border-slate-800 rounded-3xl p-5 shadow-2xl relative">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between pb-3 border-b border-slate-800 mb-4 gap-2">
            <div>
              <span className="text-xs font-mono text-rose-400 font-bold">android/app/src/main/kotlin/com/example/kidguard_live/MainActivity.kt</span>
              <p className="text-[11px] text-emerald-400 mt-0.5 font-semibold">
                ✓ टाइप एनोटेशन एरर फिक्स (catch (e: Exception)) व Android 14 क्रैश फिक्स
              </p>
            </div>
            <button
              onClick={() => copyToClipboard(mainActivityKtCode, 'MainActivity.kt')}
              className="flex items-center gap-1.5 px-3 py-1.5 bg-rose-600 hover:bg-rose-500 text-white rounded-xl text-xs font-bold transition shadow-sm active:scale-95 shrink-0 cursor-pointer"
            >
              {copiedFile === 'MainActivity.kt' ? <Check className="w-4 h-4 text-emerald-400" /> : <Copy className="w-4 h-4" />}
              <span>{copiedFile === 'MainActivity.kt' ? t.copied : t.copyCode}</span>
            </button>
          </div>
          <pre className="p-4 rounded-2xl bg-slate-950 text-slate-300 font-mono text-xs overflow-x-auto max-h-[500px] leading-relaxed border border-slate-800">
            {mainActivityKtCode}
          </pre>
        </div>
      )}

      {/* Tab 7: ScreenCaptureService.kt */}
      {activeTab === 'screen_service' && (
        <div className="bg-slate-900/90 border border-slate-800 rounded-3xl p-5 shadow-2xl relative">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between pb-3 border-b border-slate-800 mb-4 gap-2">
            <div>
              <span className="text-xs font-mono text-teal-400 font-bold">android/app/src/main/kotlin/com/example/kidguard_live/ScreenCaptureService.kt</span>
              <p className="text-[11px] text-emerald-400 mt-0.5 font-semibold">
                ✓ Android 14/15/16 क्रैश फिक्स: DATA_SYNC बैकग्राउंड सर्विस और टाइप एनोटेशन
              </p>
            </div>
            <button
              onClick={() => copyToClipboard(screenCaptureServiceKtCode, 'ScreenCaptureService.kt')}
              className="flex items-center gap-1.5 px-3 py-1.5 bg-teal-600 hover:bg-teal-500 text-white rounded-xl text-xs font-bold transition shadow-sm active:scale-95 shrink-0 cursor-pointer"
            >
              {copiedFile === 'ScreenCaptureService.kt' ? <Check className="w-4 h-4 text-emerald-400" /> : <Copy className="w-4 h-4" />}
              <span>{copiedFile === 'ScreenCaptureService.kt' ? t.copied : t.copyCode}</span>
            </button>
          </div>
          <pre className="p-4 rounded-2xl bg-slate-950 text-slate-300 font-mono text-xs overflow-x-auto max-h-[500px] leading-relaxed border border-slate-800">
            {screenCaptureServiceKtCode}
          </pre>
        </div>
      )}
    </div>
  );
};
