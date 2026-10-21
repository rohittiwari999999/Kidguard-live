// lib/main.dart
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

// -------------------------------------------------------------
// SIGNALING CONFIGURATION & CLIENT
// -------------------------------------------------------------
const String kDefaultSignalingServer = 'https://ais-dev-6snjgczxe5mnz34fbgzs4p-751137797858.asia-east1.run.app';

class SignalingService {
  final String baseUrl;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..badCertificateCallback = ((X509Certificate cert, String host, int port) => true);

  SignalingService({this.baseUrl = kDefaultSignalingServer});

  Future<bool> sendOffer(String roomCode, String sdp, String type) async {
    try {
      final uri = Uri.parse('$baseUrl/api/signal/room/$roomCode/offer');
      final request = await _client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'sdp': sdp, 'type': type}));
      final response = await request.close();
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Signaling sendOffer error: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getOffer(String roomCode) async {
    try {
      final uri = Uri.parse('$baseUrl/api/signal/room/$roomCode/offer');
      final request = await _client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        return jsonDecode(body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Signaling getOffer error: $e');
    }
    return null;
  }

  Future<bool> sendAnswer(String roomCode, String sdp, String type) async {
    try {
      final uri = Uri.parse('$baseUrl/api/signal/room/$roomCode/answer');
      final request = await _client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'sdp': sdp, 'type': type}));
      final response = await request.close();
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Signaling sendAnswer error: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getAnswer(String roomCode) async {
    try {
      final uri = Uri.parse('$baseUrl/api/signal/room/$roomCode/answer');
      final request = await _client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        return jsonDecode(body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Signaling getAnswer error: $e');
    }
    return null;
  }

  Future<bool> sendCandidate(
    String roomCode,
    String candidate,
    String? sdpMid,
    int? sdpMLineIndex,
    String sender,
  ) async {
    try {
      final uri = Uri.parse('$baseUrl/api/signal/room/$roomCode/candidate');
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
      debugPrint('Signaling sendCandidate error: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getCandidates(
    String roomCode,
    String forRole,
    int sinceTimestamp,
  ) async {
    try {
      final uri = Uri.parse('$baseUrl/api/signal/room/$roomCode/candidates?for=$forRole&since=$sinceTimestamp');
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
      debugPrint('Signaling getCandidates error: $e');
    }
    return [];
  }

  Future<void> deleteRoom(String roomCode) async {
    try {
      final uri = Uri.parse('$baseUrl/api/signal/room/$roomCode');
      final request = await _client.deleteUrl(uri);
      await request.close();
    } catch (_) {}
  }
}

// -------------------------------------------------------------
// TOP-LEVEL ENTRY POINT FOR FOREGROUND SERVICE (v6.5.0)
// -------------------------------------------------------------
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

// -------------------------------------------------------------
// ROLE SELECTION SCREEN
// -------------------------------------------------------------
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

  // EXACT SEQUENCE FIX (createOffer se pehle addTrack hona zaroori hai):
  // 1. Pehle createPeerConnection() call karo
  // 2. Fir getDisplayMedia() se screen stream lo
  // 3. Fir _peerConnection.addTrack(track, _screenStream!) call karo
  // 4. Sabse last me createOffer() aur setLocalDescription(offer) call karo aur server par save karo!
  Future<void> _startScreenShare() async {
    final roomCode = _codeController.text.trim().toUpperCase();
    if (roomCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('कृपया पेयरिंग कोड दर्ज करें')),
      );
      return;
    }

    try {
      setState(() {
        _statusMessage = 'अनुमतियां जांच रहे हैं...';
      });

      // 1. Android 13/14/15/16: Notification & Core Permissions
      try {
        await Permission.notification.request();
        await [Permission.camera, Permission.microphone].request();
      } catch (permError) {
        debugPrint('Permission notice: $permError');
      }

      setState(() {
        _statusMessage = '1/4: WebRTC Peer Connection तैयार हो रहा है...';
      });

      // STEP 1: Pehle createPeerConnection() call karo
      _peerConnection = await createPeerConnection(_iceServers);

      _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
        debugPrint("📡 [Kid] ICE Connection State: $state");
        if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          if (mounted) {
            setState(() {
              _isParentConnected = true;
              _statusMessage = '✅ माता-पिता का फोन सफलतापूर्वक जुड़ गया है!';
            });
          }
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          if (mounted) {
            setState(() {
              _isParentConnected = false;
              _statusMessage = 'माता-पिता का कनेक्शन डिस्कनेक्ट हो गया।';
            });
          }
        }
      };

      // Handle ICE Candidates generated on Kid side
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate.candidate != null) {
          _signaling.sendCandidate(
            roomCode,
            candidate.candidate!,
            candidate.sdpMid,
            candidate.sdpMLineIndex,
            'kid',
          );
        }
      };

      setState(() {
        _statusMessage = '2/4: स्क्रीन कैप्चर अनुमति मांग रहे हैं...';
      });

      // STEP 2: getDisplayMedia() se screen capture prompt dikhao
      // (User chooses "Entire screen" / "Start now")
      final mediaConstraints = <String, dynamic>{
        'audio': false,
        'video': true,
      };

      MediaStream stream = await navigator.mediaDevices.getDisplayMedia(mediaConstraints);
      _screenStream = stream;

      // STEP 3: Android Sep 2026 Security Patch Rule:
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
        debugPrint('FlutterForegroundTask notice: $fgsError');
      }

      // Native Foreground Service helper (Android 14/15/16 compliant)
      try {
        await _platformChannel.invokeMethod('startScreenCapture');
      } catch (e) {
        debugPrint('startScreenCapture notice: $e');
      }

      stream.getVideoTracks().forEach((track) {
        track.onEnded = () {
          debugPrint('Screen capture track ended');
          if (mounted) {
            _stopScreenShare();
          }
        };
      });

      setState(() {
        _statusMessage = '3/4: वीडियो ट्रैक PeerConnection में जोड़ रहे हैं...';
      });

      // STEP 3: Fir _peerConnection.addTrack(track, _localStream!) call karo
      for (final track in stream.getTracks()) {
        await _peerConnection!.addTrack(track, stream);
      }

      setState(() {
        _statusMessage = '4/4: SDP Offer तैयार कर सर्वर पर भेज रहे हैं...';
      });

      // STEP 4: Sabse last me createOffer() aur setLocalDescription(offer)
      RTCSessionDescription offer = await _peerConnection!.createOffer({
        'offerToReceiveVideo': 0,
        'offerToReceiveAudio': 0,
      });
      await _peerConnection!.setLocalDescription(offer);

      // Save Offer to Signaling Server
      final offerSuccess = await _signaling.sendOffer(roomCode, offer.sdp!, offer.type!);
      if (!offerSuccess) {
        debugPrint('Warning: Could not save offer to signaling server, will retry');
      }

      setState(() {
        _isSharing = true;
        _isRemoteDescSet = false;
        _queuedCandidates.clear();
        _statusMessage = '🔴 ब्रॉडकास्ट चालू है! माता-पिता के फोन के जुड़ने की प्रतीक्षा...';
      });

      // Poll for Parent's Answer & Candidates
      _startPollingForAnswer(roomCode);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ कोड $roomCode पर स्क्रीन ब्रॉडकास्ट शुरू हो गया!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Screen share error: $e');
      if (mounted) {
        setState(() {
          _statusMessage = 'त्रुटि: $e';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('त्रुटि: $e'), backgroundColor: Colors.redAccent),
        );
      }
      _stopScreenShare();
    }
  }

  // Listen / Poll for Parent's Answer
  void _startPollingForAnswer(String roomCode) {
    _answerPollTimer?.cancel();
    _answerPollTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!_isSharing || _isRemoteDescSet || _peerConnection == null) return;

      final answerData = await _signaling.getAnswer(roomCode);
      if (answerData != null && answerData['sdp'] != null && !_isRemoteDescSet) {
        _isRemoteDescSet = true;
        timer.cancel();

        RTCSessionDescription answer = RTCSessionDescription(
          answerData['sdp'],
          answerData['type'] ?? 'answer',
        );

        debugPrint('Parent answer received! Setting Remote Description...');
        // 1. Pehle Remote Description set hone ka wait karo
        await _peerConnection!.setRemoteDescription(answer);

        // 2. Ab Parent ke queued & new ICE candidates listen karna start karo
        _drainQueuedCandidates();
        _startListeningToParentIceCandidates(roomCode);

        if (mounted) {
          setState(() {
            _statusMessage = 'माता-पिता का उत्तर मिल गया! कनेक्शन स्थापित हो रहा है...';
          });
        }
      }
    });
  }

  void _startListeningToParentIceCandidates(String roomCode) {
    _candidatePollTimer?.cancel();
    _candidatePollTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) async {
      if (!_isSharing || _peerConnection == null) {
        timer.cancel();
        return;
      }

      final list = await _signaling.getCandidates(roomCode, 'kid', _lastCandidateTimestamp);
      for (final item in list) {
        final cStr = item['candidate'] as String?;
        final sdpMid = item['sdpMid'] as String?;
        final sdpMLineIndex = item['sdpMLineIndex'] as int?;
        final ts = item['timestamp'] as int? ?? 0;
        if (ts > _lastCandidateTimestamp) {
          _lastCandidateTimestamp = ts;
        }

        if (cStr != null) {
          final candidate = RTCIceCandidate(cStr, sdpMid, sdpMLineIndex);
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
    for (final candidate in _queuedCandidates) {
      try {
        await _peerConnection?.addCandidate(candidate);
      } catch (e) {
        debugPrint('Candidate add error: $e');
      }
    }
    _queuedCandidates.clear();
  }

  void _stopScreenShare() async {
    _answerPollTimer?.cancel();
    _candidatePollTimer?.cancel();
    try {
      await _platformChannel.invokeMethod('stopScreenCapture');
    } catch (_) {}
    _screenStream?.getTracks().forEach((track) => track.stop());
    _screenStream = null;
    try {
      await _peerConnection?.close();
    } catch (_) {}
    _peerConnection = null;
    try {
      FlutterForegroundTask.stopService();
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isSharing = false;
        _isParentConnected = false;
        _isRemoteDescSet = false;
        _statusMessage = 'स्क्रीन शेयरिंग बंद है।';
      });
    }
  }

  void _generateRandomCode() {
    final randomNum = 1000 + (DateTime.now().millisecondsSinceEpoch % 9000);
    setState(() {
      _codeController.text = 'KID-$randomNum';
    });
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
      appBar: AppBar(
        title: const Text('बच्चे का फोन - स्क्रीन शेयर'),
        backgroundColor: const Color(0xFF1E293B),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Code Customization Box (Fully Editable)
            Card(
              color: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    const Text(
                      'पेयरिंग कोड (Pairing Code):',
                      style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),

                    // DIRECT EDITABLE TEXTFIELD (No lock, zero friction)
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
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 3,
                          color: Colors.cyanAccent,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'उदा. KID-8429 या 123456',
                          hintStyle: TextStyle(fontSize: 16, color: Colors.grey, letterSpacing: 0),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('🎲 नया रैंडम कोड'),
                          onPressed: _isSharing ? null : _generateRandomCode,
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('कॉपी करें'),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _codeController.text));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('कोड कॉपी हो गया!')),
                            );
                          },
                        ),
                      ],
                    ),
                    const Text(
                      'माता-पिता के फोन में यही समान कोड डालकर कनेक्ट करें।',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Status Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _isSharing ? Colors.green.withOpacity(0.15) : Colors.black38,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isSharing ? Colors.greenAccent : Colors.white24,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    _isSharing ? Icons.screen_share : Icons.mobile_screen_share,
                    size: 48,
                    color: _isSharing ? Colors.greenAccent : Colors.white54,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _isSharing ? Colors.greenAccent : Colors.white70,
                    ),
                  ),
                  if (_isSharing) ...[
                    const SizedBox(height: 8),
                    Text(
                      _isParentConnected ? '🟢 पेरेंट एक्टिव मॉनिटर कर रहे हैं' : '🟡 पेरेंट के कोड डालने का इंतजार...',
                      style: TextStyle(
                        fontSize: 12,
                        color: _isParentConnected ? Colors.cyanAccent : Colors.amberAccent,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Action Button
            ElevatedButton.icon(
              icon: Icon(_isSharing ? Icons.stop : Icons.play_arrow, size: 28),
              label: Text(
                _isSharing ? 'स्क्रीन शेयरिंग बंद करें (Stop)' : 'पूरे मोबाइल की स्क्रीन शेयर शुरू करें',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
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

    // Debug Check 2: Resolution listener
    _remoteRenderer.onResize = () {
      debugPrint("📺 Video Resolution Received: ${_remoteRenderer.videoWidth}x${_remoteRenderer.videoHeight}");
      if (mounted) {
        setState(() {
          _videoResolution = '${_remoteRenderer.videoWidth}x${_remoteRenderer.videoHeight}';
          if (_remoteRenderer.videoWidth > 0 && _remoteRenderer.videoHeight > 0) {
            _hasRemoteVideo = true;
          }
        });
      }
    };
  }

  // EXACT SEQUENCE FIX FOR PARENT SIDE:
  // 1. Pehle Kid ka offer le kar await _peerConnection.setRemoteDescription(offer) poora hone do
  // 2. Uske baad hi Kid ke iceCandidates collection ko listen karke addCandidate() me daalo
  // 3. onTrack me Unified Plan Fallback lagao taaki event.streams empty aane par bhi screen blank na rahe!
  Future<void> _connectToChild() async {
    final roomCode = _codeController.text.trim().toUpperCase();
    if (roomCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('कृपया बच्चे का 6-अंकीय कोड दर्ज करें')),
      );
      return;
    }

    _disconnect();

    setState(() {
      _isConnecting = true;
      _statusText = 'बच्चे के फोन से ऑफर खोज रहे हैं...';
    });

    try {
      // 1. Fetch Kid's Offer from Signaling Server
      final offerData = await _signaling.getOffer(roomCode);
      if (offerData == null || offerData['sdp'] == null) {
        setState(() {
          _isConnecting = false;
          _statusText = '⚠️ बच्चे के फोन से कोई एक्टिव स्क्रीन शेयर नहीं मिला।\nपहले बच्चे के फोन में "स्क्रीन शेयर शुरू करें" दबाएं।';
        });
        return;
      }

      setState(() {
        _statusText = 'PeerConnection तैयार हो रहा है...';
      });

      // 2. Create PeerConnection
      _peerConnection = await createPeerConnection(_iceServers);

      // Debug Check 1: ICE Connection State listener
      _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
        debugPrint("📡 ICE Connection State: $state");
        if (mounted) {
          setState(() {
            _iceState = state.toString().split('.').last;
            if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
                state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
              _isConnected = true;
              _isConnecting = false;
              _statusText = '🟢 लाइव स्ट्रीम कनेक्ट हो गई!';
            } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
                state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
              _statusText = '⚠️ कनेक्शन टूट गया। पुनः प्रयास करें।';
            }
          });
        }
      };

      // FIX 2: UNIFIED PLAN BUG FIX ON PARENT SIDE
      // Agar event.streams empty aaye toh nayi MediaStream bana kar track bind karo!
      _peerConnection!.onTrack = (RTCTrackEvent event) async {
        debugPrint("🔥 Track received: ${event.track.kind}, Streams count: ${event.streams.length}");

        if (event.track.kind == 'video') {
          if (event.streams.isNotEmpty) {
            _remoteRenderer.srcObject = event.streams[0];
          } else {
            // Fallback: Agar stream empty aaye toh nayi MediaStream bana kar track bind karo
            MediaStream newStream = await createLocalMediaStream('remoteVideoStream');
            newStream.addTrack(event.track);
            _remoteRenderer.srcObject = newStream;
          }
          if (mounted) {
            setState(() {
              _hasRemoteVideo = true;
              _isConnected = true;
              _isConnecting = false;
              _statusText = '🟢 लाइव स्क्रीन दिख रही है!';
            });
          }
        }
      };

      // Send Parent ICE candidates to server
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate.candidate != null) {
          _signaling.sendCandidate(
            roomCode,
            candidate.candidate!,
            candidate.sdpMid,
            candidate.sdpMLineIndex,
            'parent',
          );
        }
      };

      // FIX 3: TIMING RULE - Pehle Kid ka offer le kar setRemoteDescription poora hone do!
      RTCSessionDescription offer = RTCSessionDescription(
        offerData['sdp'],
        offerData['type'] ?? 'offer',
      );
      await _peerConnection!.setRemoteDescription(offer);
      _isRemoteDescSet = true;

      // Create Answer
      RTCSessionDescription answer = await _peerConnection!.createAnswer({});
      await _peerConnection!.setLocalDescription(answer);

      // Send Answer to Server
      await _signaling.sendAnswer(roomCode, answer.sdp!, answer.type!);

      // AB Kid ke ICE candidates listen karna start karo
      _startListeningToKidIceCandidates(roomCode);

      setState(() {
        _statusText = 'उत्तर भेजा गया! वीडियो लोड हो रहा है...';
      });
    } catch (e) {
      debugPrint('Parent connection error: $e');
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _statusText = 'त्रुटि: $e';
        });
      }
    }
  }

  void _startListeningToKidIceCandidates(String roomCode) {
    _candidatePollTimer?.cancel();
    _candidatePollTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) async {
      if (_peerConnection == null) {
        timer.cancel();
        return;
      }

      final list = await _signaling.getCandidates(roomCode, 'parent', _lastCandidateTimestamp);
      for (final item in list) {
        final cStr = item['candidate'] as String?;
        final sdpMid = item['sdpMid'] as String?;
        final sdpMLineIndex = item['sdpMLineIndex'] as int?;
        final ts = item['timestamp'] as int? ?? 0;
        if (ts > _lastCandidateTimestamp) {
          _lastCandidateTimestamp = ts;
        }

        if (cStr != null) {
          final candidate = RTCIceCandidate(cStr, sdpMid, sdpMLineIndex);
          if (_isRemoteDescSet) {
            try {
              await _peerConnection!.addCandidate(candidate);
            } catch (e) {
              debugPrint('Error adding kid candidate: $e');
            }
          } else {
            _queuedCandidates.add(candidate);
          }
        }
      }
    });
  }

  void _disconnect() {
    _candidatePollTimer?.cancel();
    try {
      _peerConnection?.close();
    } catch (_) {}
    _peerConnection = null;
    _remoteRenderer.srcObject = null;
    _isRemoteDescSet = false;
    _queuedCandidates.clear();
    if (mounted) {
      setState(() {
        _isConnected = false;
        _isConnecting = false;
        _hasRemoteVideo = false;
        _iceState = 'None';
        _videoResolution = '0x0';
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
      appBar: AppBar(
        title: const Text('माता-पिता का लाइव मॉनिटर'),
        backgroundColor: const Color(0xFF1E293B),
        actions: [
          if (_isConnected || _isConnecting)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'रीकनेक्ट करें',
              onPressed: _connectToChild,
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Code Input Row
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
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                  child: _isConnecting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('कनेक्ट करें', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Diagnostics Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _statusText,
                      style: const TextStyle(fontSize: 12, color: Colors.cyanAccent),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    'ICE: $_iceState | Res: $_videoResolution',
                    style: const TextStyle(fontSize: 10, color: Colors.white60),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // FIX 4: FLUTTER UI RTCVIDEOVIEW SIZE 0x0 FIX
            // Parent UI me SizedBox.expand use karo taaki video container height aur width non-zero rahe!
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _hasRemoteVideo ? Colors.cyanAccent.withOpacity(0.5) : Colors.white24,
                  ),
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
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _isConnecting ? Icons.wifi_protected_setup : Icons.tv_off,
                                  size: 64,
                                  color: Colors.white38,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _isConnecting
                                      ? 'बच्चे के फोन से सिग्नल की प्रतीक्षा...'
                                      : 'बच्चे का कोड डालकर "कनेक्ट करें" बटन दबाएं',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            if (_isConnected || _hasRemoteVideo)
              ElevatedButton.icon(
                icon: const Icon(Icons.stop, color: Colors.white),
                label: const Text('डिस्कनेक्ट करें'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _disconnect,
              ),
          ],
        ),
      ),
    );
  }
}
