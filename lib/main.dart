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
    ..connectionTimeout = const Duration(seconds: 4)
    ..badCertificateCallback = ((X509Certificate cert, String host, int port) => true);

  SignalingService({this.baseUrl = kDefaultSignalingServer});

  String _cleanCode(String code) {
    return code.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
  }

  List<String> _possibleCodes(String code) {
    final clean = _cleanCode(code);
    final Set<String> codes = {clean};
    if (clean.startsWith('kid')) {
      final numPart = clean.substring(3);
      if (numPart.isNotEmpty) codes.add(numPart);
    } else {
      codes.add('kid$clean');
    }
    return codes.toList();
  }

  Future<bool> sendOffer(String roomCode, String sdp, String type) async {
    final codes = _possibleCodes(roomCode);
    bool ok = false;
    final payloadMap = {'sdp': sdp, 'type': type, 'timestamp': DateTime.now().millisecondsSinceEpoch};
    final payload = jsonEncode(payloadMap);

    for (final c in codes) {
      // 1. JSON publish with explicit topic field
      try {
        final uri = Uri.parse('https://ntfy.sh');
        final request = await _client.postUrl(uri);
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode({
          'topic': 'kg_signal_${c}_offer',
          'message': payload,
        }));
        final response = await request.close().timeout(const Duration(seconds: 3));
        if (response.statusCode == 200) ok = true;
      } catch (e) {
        debugPrint('ntfy sendOffer JSON ($c): $e');
      }

      // 2. Direct topic path publish with raw text
      try {
        final uri = Uri.parse('https://ntfy.sh/kg_signal_${c}_offer');
        final request = await _client.postUrl(uri);
        request.headers.contentType = ContentType.text;
        request.write(payload);
        final response = await request.close().timeout(const Duration(seconds: 3));
        if (response.statusCode == 200) ok = true;
      } catch (e) {
        debugPrint('ntfy sendOffer text ($c): $e');
      }
    }

    return ok;
  }

  Future<Map<String, dynamic>?> getOffer(String roomCode) async {
    final codes = _possibleCodes(roomCode);
    for (final c in codes) {
      try {
        final uri = Uri.parse('https://ntfy.sh/kg_signal_${c}_offer/json?poll=1');
        final request = await _client.getUrl(uri);
        final response = await request.close().timeout(const Duration(seconds: 3));
        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 3));
          final lines = body.trim().split('\n');
          for (final line in lines.reversed) {
            if (line.trim().isEmpty) continue;
            try {
              final json = jsonDecode(line);
              if (json is Map && json['message'] != null) {
                final msgStr = json['message'].toString();
                final payload = jsonDecode(msgStr);
                if (payload is Map && payload['sdp'] != null) {
                  return Map<String, dynamic>.from(payload);
                }
              }
            } catch (_) {}
          }
        }
      } catch (e) {
        debugPrint('ntfy getOffer ($c): $e');
      }
    }

    return null;
  }

  Future<bool> sendAnswer(String roomCode, String sdp, String type) async {
    final codes = _possibleCodes(roomCode);
    bool ok = false;
    final payloadMap = {'sdp': sdp, 'type': type, 'timestamp': DateTime.now().millisecondsSinceEpoch};
    final payload = jsonEncode(payloadMap);

    for (final c in codes) {
      try {
        final uri = Uri.parse('https://ntfy.sh');
        final request = await _client.postUrl(uri);
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode({
          'topic': 'kg_signal_${c}_answer',
          'message': payload,
        }));
        final response = await request.close().timeout(const Duration(seconds: 3));
        if (response.statusCode == 200) ok = true;
      } catch (_) {}

      try {
        final uri = Uri.parse('https://ntfy.sh/kg_signal_${c}_answer');
        final request = await _client.postUrl(uri);
        request.headers.contentType = ContentType.text;
        request.write(payload);
        final response = await request.close().timeout(const Duration(seconds: 3));
        if (response.statusCode == 200) ok = true;
      } catch (_) {}
    }

    return ok;
  }

  Future<Map<String, dynamic>?> getAnswer(String roomCode) async {
    final codes = _possibleCodes(roomCode);
    for (final c in codes) {
      try {
        final uri = Uri.parse('https://ntfy.sh/kg_signal_${c}_answer/json?poll=1');
        final request = await _client.getUrl(uri);
        final response = await request.close().timeout(const Duration(seconds: 3));
        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 3));
          final lines = body.trim().split('\n');
          for (final line in lines.reversed) {
            if (line.trim().isEmpty) continue;
            try {
              final json = jsonDecode(line);
              if (json is Map && json['message'] != null) {
                final payload = jsonDecode(json['message']);
                if (payload is Map && payload['sdp'] != null) {
                  return Map<String, dynamic>.from(payload);
                }
              }
            } catch (_) {}
          }
        }
      } catch (e) {
        debugPrint('ntfy getAnswer ($c): $e');
      }
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
    final codes = _possibleCodes(roomCode);
    final payload = jsonEncode({
      'candidate': candidate,
      'sdpMid': sdpMid,
      'sdpMLineIndex': sdpMLineIndex,
      'sender': sender,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    for (final c in codes) {
      try {
        final topic = 'kg_signal_${c}_cand_$sender';
        final uri = Uri.parse('https://ntfy.sh');
        final request = await _client.postUrl(uri);
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode({
          'topic': topic,
          'message': payload,
        }));
        await request.close().timeout(const Duration(seconds: 3));
      } catch (_) {}

      try {
        final topic = 'kg_signal_${c}_cand_$sender';
        final uri = Uri.parse('https://ntfy.sh/$topic');
        final request = await _client.postUrl(uri);
        request.headers.contentType = ContentType.text;
        request.write(payload);
        await request.close().timeout(const Duration(seconds: 3));
      } catch (_) {}
    }

    return true;
  }

  Future<List<Map<String, dynamic>>> getCandidates(
    String roomCode,
    String forRole,
    int sinceTimestamp,
  ) async {
    final codes = _possibleCodes(roomCode);
    final targetSender = forRole == 'kid' ? 'parent' : 'kid';
    final List<Map<String, dynamic>> results = [];

    for (final c in codes) {
      try {
        final topic = 'kg_signal_${c}_cand_$targetSender';
        final uri = Uri.parse('https://ntfy.sh/$topic/json?poll=1');
        final request = await _client.getUrl(uri);
        final response = await request.close().timeout(const Duration(seconds: 3));
        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 3));
          final lines = body.trim().split('\n');
          for (final line in lines) {
            if (line.trim().isEmpty) continue;
            try {
              final json = jsonDecode(line);
              if (json is Map && json['message'] != null) {
                final payload = jsonDecode(json['message']);
                if (payload is Map && payload['candidate'] != null) {
                  final ts = payload['timestamp'] as int? ?? 0;
                  if (ts > sinceTimestamp) {
                    results.add(Map<String, dynamic>.from(payload));
                  }
                }
              }
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    return results;
  }
}

// -------------------------------------------------------------
// LOCAL WI-FI / LAN SIGNALING SERVICE (Zero Internet Required)
// Ultra-fast peer discovery & signaling for devices on same Wi-Fi
// -------------------------------------------------------------
class LocalLanSignaling {
  HttpServer? _httpServer;
  RawDatagramSocket? _udpSocket;
  Timer? _beaconTimer;
  String? _lanPeerIp;
  int _lanPeerPort = 8998;

  String cleanCode(String code) {
    return code.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
  }

  static Future<List<String>> getLocalIps() async {
    final List<String> ips = [];
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.address.contains('.')) {
            ips.add(addr.address);
          }
        }
      }
    } catch (_) {}
    return ips;
  }

  // 1. CHILD DEVICE: Start Local HTTP Server & UDP Broadcast
  Future<void> startChild({
    required String roomCode,
    required String Function() getOfferSdp,
    required String Function() getOfferType,
    required Function(String sdp, String type) onAnswerReceived,
    required Function(RTCIceCandidate candidate) onCandidateReceived,
    required List<Map<String, dynamic>> Function() getChildCandidates,
  }) async {
    await stop();
    final clean = cleanCode(roomCode);

    try {
      _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, 8998);
    } catch (_) {
      try {
        _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      } catch (e) {
        debugPrint('Local HTTP server bind error: $e');
      }
    }

    if (_httpServer != null) {
      final assignedPort = _httpServer!.port;
      _lanPeerPort = assignedPort;
      debugPrint("🚀 [LAN] Child HTTP Server live on port $assignedPort");

      _httpServer!.listen((HttpRequest request) async {
        request.response.headers.add('Access-Control-Allow-Origin', '*');
        request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
        request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type');

        if (request.method == 'OPTIONS') {
          request.response.statusCode = HttpStatus.ok;
          await request.response.close();
          return;
        }

        final path = request.uri.path;
        try {
          if (path == '/offer') {
            final sdp = getOfferSdp();
            final type = getOfferType();
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode({
              'sdp': sdp,
              'type': type,
              'code': clean,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            }));
          } else if (path == '/answer' && request.method == 'POST') {
            final body = await utf8.decoder.bind(request).join();
            final data = jsonDecode(body);
            if (data is Map && data['sdp'] != null) {
              onAnswerReceived(data['sdp'], data['type'] ?? 'answer');
            }
            request.response.statusCode = HttpStatus.ok;
            request.response.write(jsonEncode({'success': true}));
          } else if (path == '/candidate' && request.method == 'POST') {
            final body = await utf8.decoder.bind(request).join();
            final data = jsonDecode(body);
            if (data is Map && data['candidate'] != null) {
              final cand = RTCIceCandidate(
                data['candidate'],
                data['sdpMid'],
                data['sdpMLineIndex'],
              );
              onCandidateReceived(cand);
            }
            request.response.statusCode = HttpStatus.ok;
            request.response.write(jsonEncode({'success': true}));
          } else if (path == '/candidates') {
            final cands = getChildCandidates();
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode({'candidates': cands}));
          } else {
            request.response.statusCode = HttpStatus.notFound;
          }
        } catch (e) {
          debugPrint('LAN request error: $e');
        }
        await request.response.close();
      });
    }

    // Start UDP Beacon on 255.255.255.255:8999
    try {
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _udpSocket?.broadcastEnabled = true;

      _beaconTimer = Timer.periodic(const Duration(milliseconds: 1200), (t) async {
        final localIps = await getLocalIps();
        final sdp = getOfferSdp();
        if (sdp.isEmpty) return;

        final beacon = jsonEncode({
          'app': 'kidguard',
          'code': clean,
          'port': _lanPeerPort,
          'ips': localIps,
          'sdp': sdp,
          'type': getOfferType(),
          'ts': DateTime.now().millisecondsSinceEpoch,
        });
        final bytes = utf8.encode(beacon);

        try {
          _udpSocket?.send(bytes, InternetAddress('255.255.255.255'), 8999);
        } catch (_) {}
      });
    } catch (e) {
      debugPrint('LAN UDP Beacon setup error: $e');
    }
  }

  // 2. PARENT DEVICE: Discover Child via Local Wi-Fi
  Future<Map<String, dynamic>?> discoverOnLan(String roomCode) async {
    final clean = cleanCode(roomCode);
    final completer = Completer<Map<String, dynamic>?>();

    RawDatagramSocket? listener;
    Timer? timeoutTimer;

    try {
      listener = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        8999,
        reuseAddress: true,
        reusePort: true,
      );
      listener.broadcastEnabled = true;

      listener.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final dg = listener?.receive();
          if (dg != null) {
            try {
              final str = utf8.decode(dg.data);
              final json = jsonDecode(str);
              if (json is Map && json['app'] == 'kidguard') {
                final c = json['code']?.toString() ?? '';
                if (c == clean || c.contains(clean) || clean.contains(c)) {
                  if (json['ips'] != null && json['ips'] is List && (json['ips'] as List).isNotEmpty) {
                    _lanPeerIp = (json['ips'] as List).first.toString();
                  } else {
                    _lanPeerIp = dg.address.address;
                  }
                  _lanPeerPort = json['port'] as int? ?? 8998;

                  if (json['sdp'] != null && !completer.isCompleted) {
                    completer.complete({
                      'sdp': json['sdp'],
                      'type': json['type'] ?? 'offer',
                      'lanIp': _lanPeerIp,
                      'lanPort': _lanPeerPort,
                    });
                  }
                }
              }
            } catch (_) {}
          }
        }
      });
    } catch (_) {}

    // Subnet probe in parallel (checks nearby local IPs on same Wi-Fi)
    _probeSubnetForChild(clean).then((res) {
      if (res != null && !completer.isCompleted) {
        _lanPeerIp = res['lanIp'];
        _lanPeerPort = res['lanPort'] ?? 8998;
        completer.complete(res);
      }
    });

    timeoutTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
      try {
        listener?.close();
      } catch (_) {}
    });

    final res = await completer.future;
    timeoutTimer.cancel();
    try {
      listener?.close();
    } catch (_) {}
    return res;
  }

  Future<Map<String, dynamic>?> _probeSubnetForChild(String cleanCode) async {
    try {
      final localIps = await getLocalIps();
      for (final ip in localIps) {
        final parts = ip.split('.');
        if (parts.length != 4) continue;
        final subnetPrefix = '${parts[0]}.${parts[1]}.${parts[2]}';
        final myLastOctet = int.tryParse(parts[3]) ?? 0;

        final candidateOctets = <int>[];
        for (int offset = 1; offset <= 20; offset++) {
          if (myLastOctet - offset > 1) candidateOctets.add(myLastOctet - offset);
          if (myLastOctet + offset < 254) candidateOctets.add(myLastOctet + offset);
        }

        final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 250);
        for (final octet in candidateOctets) {
          final targetIp = '$subnetPrefix.$octet';
          try {
            final uri = Uri.parse('http://$targetIp:8998/offer');
            final req = await client.getUrl(uri).timeout(const Duration(milliseconds: 250));
            final resp = await req.close().timeout(const Duration(milliseconds: 250));
            if (resp.statusCode == 200) {
              final body = await resp.transform(utf8.decoder).join();
              final json = jsonDecode(body);
              if (json is Map && json['sdp'] != null) {
                final c = json['code']?.toString() ?? '';
                if (c.isEmpty || c == cleanCode || c.contains(cleanCode) || cleanCode.contains(c)) {
                  client.close();
                  return {
                    'sdp': json['sdp'],
                    'type': json['type'] ?? 'offer',
                    'lanIp': targetIp,
                    'lanPort': 8998,
                  };
                }
              }
            }
          } catch (_) {}
        }
        client.close();
      }
    } catch (_) {}
    return null;
  }

  Future<bool> sendAnswerToLan(String sdp, String type) async {
    if (_lanPeerIp == null) return false;
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final uri = Uri.parse('http://$_lanPeerIp:$_lanPeerPort/answer');
      final req = await client.postUrl(uri);
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'sdp': sdp, 'type': type}));
      final resp = await req.close().timeout(const Duration(seconds: 2));
      client.close();
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> sendCandidateToLan(RTCIceCandidate candidate) async {
    if (_lanPeerIp == null) return;
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
      final uri = Uri.parse('http://$_lanPeerIp:$_lanPeerPort/candidate');
      final req = await client.postUrl(uri);
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      }));
      await req.close().timeout(const Duration(seconds: 1));
      client.close();
    } catch (_) {}
  }

  Future<void> stop() async {
    _beaconTimer?.cancel();
    _beaconTimer = null;
    try {
      _udpSocket?.close();
    } catch (_) {}
    _udpSocket = null;
    try {
      await _httpServer?.close(force: true);
    } catch (_) {}
    _httpServer = null;
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
  final LocalLanSignaling _localLan = LocalLanSignaling();
  final TextEditingController _codeController = TextEditingController(text: 'KID-8429');

  RTCPeerConnection? _peerConnection;
  MediaStream? _screenStream;
  bool _isSharing = false;
  String _statusMessage = 'तैयार है। स्क्रीन शेयर शुरू करें।';
  bool _isParentConnected = false;

  Timer? _answerPollTimer;
  Timer? _candidatePollTimer;
  Timer? _offerHeartbeatTimer;
  int _lastCandidateTimestamp = 0;
  bool _isRemoteDescSet = false;
  final List<RTCIceCandidate> _queuedCandidates = [];
  final List<Map<String, dynamic>> _collectedChildCandidates = [];
  String? _latestOfferSdp;
  String? _latestOfferType;

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

      try {
        await Permission.notification.request();
        await [Permission.camera, Permission.microphone].request();
      } catch (permError) {
        debugPrint('Permission notice: $permError');
      }

      setState(() {
        _statusMessage = '1/4: WebRTC Peer Connection तैयार हो रहा है...';
      });

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
          _collectedChildCandidates.add({
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
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
        _statusMessage = '2/4: स्क्रीन शेयर अनुमति मांग रहे हैं... (कृपया "Entire screen" चुनें)';
      });

      try {
        final ready = await _platformChannel.invokeMethod('prepareScreenCapture');
        if (ready != true) {
          setState(() {
            _statusMessage = 'अनुमति नहीं मिली या रद्द कर दी गई।';
          });
          return;
        }
      } catch (nativeErr) {
        debugPrint('prepareScreenCapture notice: $nativeErr');
      }

      final mediaConstraints = <String, dynamic>{
        'audio': false,
        'video': true,
      };

      MediaStream stream = await navigator.mediaDevices.getDisplayMedia(mediaConstraints);
      _screenStream = stream;

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

      for (final track in stream.getTracks()) {
        await _peerConnection!.addTrack(track, stream);
      }

      setState(() {
        _statusMessage = '4/4: SDP Offer तैयार कर सर्वर पर भेज रहे हैं...';
      });

      RTCSessionDescription offer = await _peerConnection!.createOffer({
        'offerToReceiveVideo': 0,
        'offerToReceiveAudio': 0,
      });
      await _peerConnection!.setLocalDescription(offer);
      _latestOfferSdp = offer.sdp;
      _latestOfferType = offer.type;

      setState(() {
        _isSharing = true;
        _isRemoteDescSet = false;
        _queuedCandidates.clear();
        _collectedChildCandidates.clear();
        _statusMessage = '🔴 ब्रॉडकास्ट चालू है! कोड: $roomCode\nमाता-पिता के जुड़ने की प्रतीक्षा...';
      });

      // 1. Direct Wi-Fi LAN Signaling (Instant connection on same network)
      _localLan.startChild(
        roomCode: roomCode,
        getOfferSdp: () => _latestOfferSdp ?? offer.sdp ?? '',
        getOfferType: () => _latestOfferType ?? offer.type ?? 'offer',
        onAnswerReceived: (sdp, type) async {
          if (_peerConnection != null && !_isRemoteDescSet) {
            _isRemoteDescSet = true;
            await _peerConnection!.setRemoteDescription(RTCSessionDescription(sdp, type));
            _drainQueuedCandidates();
            if (mounted) {
              setState(() {
                _isParentConnected = true;
                _statusMessage = '✅ माता-पिता का फोन (Wi-Fi LAN) जुड़ गया!';
              });
            }
          }
        },
        onCandidateReceived: (cand) async {
          if (_isRemoteDescSet) {
            await _peerConnection?.addCandidate(cand);
          } else {
            _queuedCandidates.add(cand);
          }
        },
        getChildCandidates: () => _collectedChildCandidates,
      );

      // 2. Poll for Parent's Answer on Cloud Relay
      _startPollingForAnswer(roomCode);

      // 3. Send initial Offer asynchronously
      _signaling.sendOffer(roomCode, offer.sdp!, offer.type!).then((ok) {
        if (mounted && _isSharing) {
          setState(() {
            _statusMessage = '🔴 ब्रॉडकास्ट सक्रिय है! कोड: $roomCode\nमाता-पिता के जुड़ने की प्रतीक्षा...';
          });
        }
      });

      // 4. Offer Heartbeat: keep refreshing Offer every 2.5s so parent can connect anytime!
      _offerHeartbeatTimer?.cancel();
      _offerHeartbeatTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
        if (_isSharing && !_isParentConnected && _peerConnection != null) {
          _signaling.sendOffer(roomCode, offer.sdp!, offer.type!);
        }
      });

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
        await _peerConnection!.setRemoteDescription(answer);

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
    _offerHeartbeatTimer?.cancel();
    _offerHeartbeatTimer = null;
    _localLan.stop();
    _collectedChildCandidates.clear();

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

            if (!_isSharing) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withOpacity(0.5)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Colors.amberAccent, size: 22),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'जरूरी सूचना (Android 14/15/16):\nजब स्क्रीन शेयरिंग पॉपअप आए, तो "Entire screen" (पूरी स्क्रीन) ही चुनें।\n"Single app" चुनने पर केवल वही ऐप खुल जाएगा और बाकी फोन स्क्रीन नहीं दिखेगी।',
                        style: TextStyle(fontSize: 12, color: Colors.amberAccent, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

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
  final LocalLanSignaling _localLan = LocalLanSignaling();

  RTCPeerConnection? _peerConnection;
  bool _isConnecting = false;
  bool _isConnected = false;
  bool _hasRemoteVideo = false;
  bool _isLanConnection = false;
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

    // Resolution listener
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
      Map<String, dynamic>? offerData;
      _isLanConnection = false;

      for (int attempt = 1; attempt <= 40; attempt++) {
        if (!mounted || !_isConnecting) return;
        setState(() {
          _statusText = 'बच्चे के फोन से सिग्नल खोज रहे हैं... ($attempt/40)';
        });

        // 1. Direct Wi-Fi LAN search (Instant <200ms when both phones are on same Wi-Fi)
        try {
          final lanOffer = await _localLan.discoverOnLan(roomCode);
          if (lanOffer != null && lanOffer['sdp'] != null) {
            offerData = lanOffer;
            _isLanConnection = true;
            debugPrint("🎯 [Parent] Discovered Child via Direct Wi-Fi LAN!");
            break;
          }
        } catch (_) {}

        // 2. Cloud Relay search (ntfy.sh)
        offerData = await _signaling.getOffer(roomCode);
        if (offerData != null && offerData['sdp'] != null) {
          debugPrint("🎯 [Parent] Discovered Child via Cloud Relay!");
          break;
        }

        await Future.delayed(const Duration(milliseconds: 1000));
      }

      if (offerData == null || offerData['sdp'] == null) {
        setState(() {
          _isConnecting = false;
          _statusText = '⚠️ कोड $roomCode पर कोई एक्टिव स्क्रीन शेयर नहीं मिला।\nजांचें कि बच्चे के फोन में वही कोड ($roomCode) है और स्क्रीन शेयर चालू है।';
        });
        return;
      }

      setState(() {
        _statusText = _isLanConnection
            ? '⚡ वाई-फाई डायरेक्ट सिग्नल मिल गया! स्क्रीन लोड हो रही है...'
            : '✅ बच्चे का क्लाउड सिग्नल मिल गया! लाइव स्क्रीन कनेक्ट हो रही है...';
      });

      _peerConnection = await createPeerConnection(_iceServers);

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

      _peerConnection!.onTrack = (RTCTrackEvent event) async {
        debugPrint("🔥 Track received: ${event.track.kind}, Streams count: ${event.streams.length}");

        if (event.track.kind == 'video') {
          if (event.streams.isNotEmpty) {
            _remoteRenderer.srcObject = event.streams[0];
          } else {
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

      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate.candidate != null) {
          if (_isLanConnection) {
            _localLan.sendCandidateToLan(candidate);
          }
          _signaling.sendCandidate(
            roomCode,
            candidate.candidate!,
            candidate.sdpMid,
            candidate.sdpMLineIndex,
            'parent',
          );
        }
      };

      RTCSessionDescription offer = RTCSessionDescription(
        offerData['sdp'],
        offerData['type'] ?? 'offer',
      );
      await _peerConnection!.setRemoteDescription(offer);
      _isRemoteDescSet = true;

      RTCSessionDescription answer = await _peerConnection!.createAnswer({});
      await _peerConnection!.setLocalDescription(answer);

      // Send Answer to both LAN (if connected) and Cloud Relay
      if (_isLanConnection) {
        _localLan.sendAnswerToLan(answer.sdp!, answer.type!);
      }
      await _signaling.sendAnswer(roomCode, answer.sdp!, answer.type!);

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
    _localLan.stop();
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
