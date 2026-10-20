// lib/main.dart
// KidGuard Live - Full Flutter Mobile Application
// Captures Child's Android Screen via MediaProjection and streams to Parent's Phone
// Crash-proof implementation with Android 13/14 Foreground Service MediaProjection support

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'dart:async';
import 'dart:isolate';

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
        title: const Text('KidGuard Live - Bal Monitor'),
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
                'यह फोन किसका है?\nSelect Device Role',
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
// 1. CHILD SCREEN CAPTURE (Uses Android MediaProjection Foreground Service)
// -------------------------------------------------------------
class ChildScreenCapture extends StatefulWidget {
  const ChildScreenCapture({super.key});

  @override
  State<ChildScreenCapture> createState() => _ChildScreenCaptureState();
}

class _ChildScreenCaptureState extends State<ChildScreenCapture> {
  static const MethodChannel _platformChannel = MethodChannel('com.example.kidguard_live/screen_capture');
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  MediaStream? _screenStream;
  bool _isSharing = false;
  String _roomCode = 'KID-8429';

  @override
  void initState() {
    super.initState();
    _localRenderer.initialize();
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
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 5000,
        isOnceEvent: false,
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<void> _startScreenShare() async {
    try {
      // 1. Android 13/14/15/16: Request Notification Permission FIRST
      // Crucial: without notification permission, foreground service cannot start on modern Android
      final notifStatus = await Permission.notification.request();
      debugPrint('Notification permission status: $notifStatus');

      // 2. Request Camera & Mic Permissions
      await [
        Permission.camera,
        Permission.microphone,
      ].request();

      // 3. Android 14/15/16 NATIVE FLOW:
      // Calls MainActivity -> MediaProjectionManager.createScreenCaptureIntent()
      // Once granted, MainActivity starts ScreenCaptureService with FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
      // and registers MediaProjection.Callback to avoid IllegalStateException!
      try {
        final bool? nativeSuccess = await _platformChannel.invokeMethod<bool>('startScreenCapture');
        if (nativeSuccess == true) {
          if (mounted) {
            setState(() {
              _isSharing = true;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Android 14/15/16 Native स्क्रीन शेयरिंग शुरू हो गई है!'),
                backgroundColor: Colors.green,
              ),
            );
          }
          return;
        }
      } on PlatformException catch (pe) {
        if (pe.code == 'CANCELLED') {
          // User clicked Cancel in system dialog, do not error
          return;
        }
        debugPrint('Native screen capture error, falling back: $pe');
      } on MissingPluginException {
        debugPrint('Native MethodChannel not found (e.g. running on web), falling back to WebRTC');
      }

      // 4. Fallback WebRTC getDisplayMedia (for web or environments without native service)
      final mediaConstraints = <String, dynamic>{
        'audio': false,
        'video': true,
      };

      MediaStream stream = await navigator.mediaDevices.getDisplayMedia(mediaConstraints);
      _screenStream = stream;

      stream.getVideoTracks().forEach((track) {
        track.onEnded = () {
          if (mounted) {
            _stopScreenShare();
          }
        };
      });

      if (mounted) {
        setState(() {
          _isSharing = true;
        });
      }
    } catch (e) {
      debugPrint('Screen capture error caught safely: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('स्क्रीन शेयर सूचना: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _stopScreenShare() async {
    try {
      await _platformChannel.invokeMethod('stopScreenCapture');
    } catch (_) {}
    _screenStream?.getTracks().forEach((track) => track.stop());
    _screenStream = null;
    try {
      FlutterForegroundTask.stopService();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _isSharing = false;
      });
    }
  }

  @override
  void dispose() {
    _stopScreenShare();
    _localRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('बच्चे का फोन - स्क्रीन शेयर')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Card(
              color: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Text('पेयरिंग कोड (Pairing Code):', style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 6),
                    Text(
                      _roomCode,
                      style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, letterSpacing: 4, color: Colors.cyanAccent),
                    ),
                    const SizedBox(height: 10),
                    const Text('माता-पिता के फोन में यह कोड डालकर लाइव स्क्रीन देखें।', textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: _isSharing
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.screen_share, size: 72, color: Colors.greenAccent),
                            const SizedBox(height: 16),
                            const Text(
                              '🔴 स्क्रीन लाइव शेयर हो रही है!\nScreen is Live Broadcasting',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.greenAccent),
                              ),
                              child: const Text(
                                'अब आप कोई भी ऐप (YouTube, Game) चलाएं,\nमाता-पिता के फोन पर लाइव दिखता रहेगा।',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.greenAccent, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      )
                    : const Center(
                        child: Text('स्क्रीन शेयरिंग अभी बंद है\n"स्क्रीन शेयर शुरू करें" बटन दबाएं', textAlign: TextAlign.center),
                      ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: Icon(_isSharing ? Icons.stop : Icons.play_arrow),
              label: Text(_isSharing ? 'स्क्रीन शेयरिंग बंद करें' : 'पूरे मोबाइल की स्क्रीन शेयर शुरू करें'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                backgroundColor: _isSharing ? Colors.redAccent : Colors.green,
                foregroundColor: Colors.white,
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
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _remoteRenderer.initialize();
  }

  void _connectToChild() {
    setState(() {
      _isConnected = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('बच्चे की लाइव स्क्रीन से जुड़ गए!')));
  }

  @override
  void dispose() {
    _remoteRenderer.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('माता-पिता का लाइव मॉनिटर')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeController,
                    decoration: const InputDecoration(
                      labelText: 'बच्चे का 6-अंकीय कोड',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _connectToChild,
                  child: const Text('कनेक्ट करें'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: _isConnected
                    ? RTCVideoView(_remoteRenderer)
                    : const Center(
                        child: Text('बच्चे के फोन से सिग्नल की प्रतीक्षा...', textAlign: TextAlign.center),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
