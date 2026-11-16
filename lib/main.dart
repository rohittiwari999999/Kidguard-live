// lib/main.dart
// KidGuard Live - Full Flutter Mobile Application
// Real-time Child Screen Monitoring via WebRTC & Foreground Service MediaProjection
// Android 13/14/15/16 Compatible with complete Signaling, ICE Candidate Queueing,
// Unified Plan track fallback, TURN Relay support, and background WakeLock/WifiLock persistence.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' show Random;

// -------------------------------------------------------------
// ICE / STUN / TURN CONFIGURATION SERVICE (Mobile Data CGNAT Fix)
// -------------------------------------------------------------
class IceConfigService {
  static final Random _rng = Random();

  static String generateId(String prefix) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final r = _rng.nextInt(999999);
    return '${prefix}_${now}_$r';
  }

  static File _configFile() => File('${Directory.systemTemp.path}/kidguard_turn_cfg.json');

  static Future<Map<String, String>> loadSettings() async {
    try {
      final f = _configFile();
      if (await f.exists()) {
        final raw = await f.readAsString();
        final map = jsonDecode(raw);
        if (map is Map) {
          return {
            'meteredUrl': (map['meteredUrl'] ?? '').toString(),
            'turnUrl': (map['turnUrl'] ?? '').toString(),
            'username': (map['username'] ?? '').toString(),
            'credential': (map['credential'] ?? '').toString(),
          };
        }
      }
    } catch (_) {}
    return {'meteredUrl': '', 'turnUrl': '', 'username': '', 'credential': ''};
  }

  static Future<void> saveSettings({
    String meteredUrl = '',
    String turnUrl = '',
    String username = '',
    String credential = '',
  }) async {
    try {
      final f = _configFile();
      await f.writeAsString(jsonEncode({
        'meteredUrl': meteredUrl.trim(),
        'turnUrl': turnUrl.trim(),
        'username': username.trim(),
        'credential': credential.trim(),
      }));
    } catch (_) {}
  }

  static Future<bool> hasTurnConfigured() async {
    final s = await loadSettings();
    return (s['meteredUrl'] ?? '').isNotEmpty || (s['turnUrl'] ?? '').isNotEmpty;
  }

  static Future<List<Map<String, dynamic>>> getCustomTurnServers() async {
    final List<Map<String, dynamic>> turnServers = [];
    final cfg = await loadSettings();
    final meteredUrl = (cfg['meteredUrl'] ?? '').trim();
    final manualTurn = (cfg['turnUrl'] ?? '').trim();
    final user = (cfg['username'] ?? '').trim();
    final cred = (cfg['credential'] ?? '').trim();

    if (meteredUrl.isNotEmpty) {
      try {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 4)
          ..badCertificateCallback = ((X509Certificate cert, String host, int port) => true);
        final req = await client.getUrl(Uri.parse(meteredUrl));
        final resp = await req.close().timeout(const Duration(seconds: 4));
        if (resp.statusCode == 200) {
          final body = await resp.transform(utf8.decoder).join().timeout(const Duration(seconds: 4));
          final decoded = jsonDecode(body);
          if (decoded is List) {
            for (final item in decoded) {
              if (item is Map) {
                turnServers.add(Map<String, dynamic>.from(item));
              }
            }
          }
        } else {
          await resp.drain<void>();
        }
        client.close();
      } catch (e) {
        debugPrint('Metered TURN fetch notice: $e');
      }
    }

    if (manualTurn.isNotEmpty) {
      final entry = <String, dynamic>{'urls': manualTurn};
      if (user.isNotEmpty) entry['username'] = user;
      if (cred.isNotEmpty) entry['credential'] = cred;
      turnServers.add(entry);
    }

    return turnServers;
  }

  static Future<Map<String, dynamic>> buildIceConfig({
    List<Map<String, dynamic>>? extraTurnServers,
  }) async {
    final List<Map<String, dynamic>> servers = [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun.cloudflare.com:3478'},
      {'urls': 'stun:stun.relay.metered.ca:80'},
    ];

    final localTurns = await getCustomTurnServers();
    servers.addAll(localTurns);

    if (extraTurnServers != null && extraTurnServers.isNotEmpty) {
      for (final t in extraTurnServers) {
        if (t['urls'] != null) {
          servers.add(Map<String, dynamic>.from(t));
        }
      }
    }

    return {
      'iceServers': servers,
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
      'iceCandidatePoolSize': 4,
    };
  }
}

// -------------------------------------------------------------
// SIGNALING CONFIGURATION & CLIENT (ntfy.sh Cloud + Optional Server)
// -------------------------------------------------------------
const String kDefaultSignalingServer = '';

class SignalingService {
  final String baseUrl;
  bool _serverDisabled = false;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..maxConnectionsPerHost = 12
    ..badCertificateCallback = ((X509Certificate cert, String host, int port) => true);

  SignalingService({this.baseUrl = kDefaultSignalingServer}) {
    if (baseUrl.trim().isEmpty) {
      _serverDisabled = true;
    }
  }

  String _cleanCode(String code) {
    return code.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
  }

  List<String> _possibleCodes(String code) {
    final clean = _cleanCode(code);
    final Set<String> codes = {clean};
    if (clean.startsWith('kid')) {
      final numPart = clean.substring(3);
      if (numPart.isNotEmpty) codes.add(numPart);
    } else if (clean.isNotEmpty) {
      codes.add('kid$clean');
    }
    return codes.toList();
  }

  Future<bool> _postNtfy(String topic, String payload) async {
    try {
      final uri = Uri.parse('https://ntfy.sh/$topic');
      final request = await _client.postUrl(uri);
      request.headers.contentType = ContentType.text;
      request.write(payload);
      final response = await request.close().timeout(const Duration(seconds: 4));
      await response.drain<void>().timeout(const Duration(seconds: 2), onTimeout: () {});
      if (response.statusCode == 200) return true;
      debugPrint('ntfy POST $topic HTTP ${response.statusCode}');
    } catch (e) {
      debugPrint('ntfy POST $topic error: $e');
    }
    return false;
  }

  Future<List<Map<String, dynamic>>> _getNtfyMessages(String topic, {String since = '2m'}) async {
    final List<Map<String, dynamic>> out = [];
    try {
      final uri = Uri.parse('https://ntfy.sh/$topic/json?poll=1&since=$since');
      final request = await _client.getUrl(uri);
      final response = await request.close().timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 4));
        final lines = body.trim().split('\n');
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          try {
            final json = jsonDecode(line);
            if (json is Map && json['message'] != null) {
              final payload = jsonDecode(json['message'].toString());
              if (payload is Map) {
                out.add({
                  'ntfyId': json['id']?.toString() ?? '',
                  'ntfyTime': json['time'] as int? ?? 0,
                  'payload': Map<String, dynamic>.from(payload),
                });
              }
            }
          } catch (_) {}
        }
      } else {
        await response.drain<void>().timeout(const Duration(seconds: 2), onTimeout: () {});
        debugPrint('ntfy GET $topic HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('ntfy GET $topic error: $e');
    }
    return out;
  }

  Future<bool> sendOffer(
    String roomCode,
    String sdp,
    String type, {
    String? offerId,
    String? replyToReqId,
    List<Map<String, dynamic>>? turnServers,
  }) async {
    final codes = _possibleCodes(roomCode);
    bool ok = false;
    final payloadMap = <String, dynamic>{
      'sdp': sdp,
      'type': type,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      if (offerId != null) 'offerId': offerId,
      if (replyToReqId != null) 'replyToReqId': replyToReqId,
      if (turnServers != null && turnServers.isNotEmpty) 'turnServers': turnServers,
    };
    final payload = jsonEncode(payloadMap);

    for (final c in codes) {
      if (await _postNtfy('kg_signal_${c}_offer', payload)) {
        ok = true;
      }
    }
    return ok;
  }

  Future<Map<String, dynamic>?> getOffer(
    String roomCode, {
    String? reqId,
    bool requireMatchingReqId = false,
    Set<String>? excludeOfferIds,
  }) async {
    final codes = _possibleCodes(roomCode);
    Map<String, dynamic>? bestFallback;

    for (final c in codes) {
      final msgs = await _getNtfyMessages('kg_signal_${c}_offer', since: '2m');
      for (final m in msgs.reversed) {
        final payload = m['payload'] as Map<String, dynamic>;
        if (payload['sdp'] == null) continue;
        final oId = payload['offerId']?.toString();
        if (oId != null && excludeOfferIds != null && excludeOfferIds.contains(oId)) {
          continue;
        }
        if (reqId != null && payload['replyToReqId']?.toString() == reqId) {
          return payload;
        }
        if (!requireMatchingReqId) {
          bestFallback ??= payload;
        }
      }
    }
    return requireMatchingReqId ? null : bestFallback;
  }

  Future<void> requestFreshOffer(
    String roomCode,
    int reqTimestamp, {
    String? reqId,
    List<Map<String, dynamic>>? turnServers,
  }) async {
    final codes = _possibleCodes(roomCode);
    final payload = jsonEncode({
      'request': 'offer',
      'timestamp': reqTimestamp,
      if (reqId != null) 'reqId': reqId,
      if (turnServers != null && turnServers.isNotEmpty) 'turnServers': turnServers,
    });
    for (final c in codes) {
      await _postNtfy('kg_signal_${c}_req', payload);
    }
  }

  Future<Map<String, dynamic>?> getLatestRequest(String roomCode) async {
    final codes = _possibleCodes(roomCode);
    for (final c in codes) {
      final msgs = await _getNtfyMessages('kg_signal_${c}_req', since: '35s');
      for (final m in msgs.reversed) {
        final payload = m['payload'] as Map<String, dynamic>;
        if (payload['timestamp'] != null || payload['reqId'] != null) {
          return {
            ...payload,
            '_ntfyId': m['ntfyId'],
            '_ntfyTime': m['ntfyTime'],
          };
        }
      }
    }
    return null;
  }

  Future<void> sendDisconnect(String roomCode, {String? offerId}) async {
    final codes = _possibleCodes(roomCode);
    final payload = jsonEncode({
      'event': 'disconnect',
      'disconnectId': IceConfigService.generateId('disc'),
      if (offerId != null) 'offerId': offerId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    for (final c in codes) {
      await _postNtfy('kg_signal_${c}_disconnect', payload);
    }
  }

  Future<Map<String, dynamic>?> getLatestDisconnect(String roomCode) async {
    final codes = _possibleCodes(roomCode);
    for (final c in codes) {
      final msgs = await _getNtfyMessages('kg_signal_${c}_disconnect', since: '30s');
      for (final m in msgs.reversed) {
        final payload = m['payload'] as Map<String, dynamic>;
        if (payload['timestamp'] != null || payload['disconnectId'] != null) {
          return {
            ...payload,
            '_ntfyId': m['ntfyId'],
            '_ntfyTime': m['ntfyTime'],
          };
        }
      }
    }
    return null;
  }

  Future<bool> sendAnswer(String roomCode, String sdp, String type, {String? offerId}) async {
    final codes = _possibleCodes(roomCode);
    bool ok = false;
    final payload = jsonEncode({
      'sdp': sdp,
      'type': type,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      if (offerId != null) 'offerId': offerId,
    });

    for (final c in codes) {
      if (await _postNtfy('kg_signal_${c}_answer', payload)) {
        ok = true;
      }
    }
    return ok;
  }

  Future<Map<String, dynamic>?> getAnswer(String roomCode, {String? expectedOfferId}) async {
    final codes = _possibleCodes(roomCode);
    Map<String, dynamic>? fallback;
    for (final c in codes) {
      final msgs = await _getNtfyMessages('kg_signal_${c}_answer', since: '90s');
      for (final m in msgs.reversed) {
        final payload = m['payload'] as Map<String, dynamic>;
        if (payload['sdp'] == null) continue;
        final ansOfferId = payload['offerId']?.toString();
        if (expectedOfferId != null && ansOfferId != null) {
          if (ansOfferId == expectedOfferId) return payload;
          continue; // Answer belongs to a different offerId
        }
        fallback ??= payload;
      }
    }
    return fallback;
  }

  Future<bool> sendCandidatesBatch(
    String roomCode,
    List<Map<String, dynamic>> candidates,
    String sender, {
    String? offerId,
  }) async {
    if (candidates.isEmpty) return true;
    final codes = _possibleCodes(roomCode);
    final payload = jsonEncode({
      'sender': sender,
      if (offerId != null) 'offerId': offerId,
      'candidates': candidates,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    bool ok = false;
    for (final c in codes) {
      if (await _postNtfy('kg_signal_${c}_cand_$sender', payload)) {
        ok = true;
      }
    }
    return ok;
  }

  Future<bool> sendCandidate(
    String roomCode,
    String candidate,
    String? sdpMid,
    int? sdpMLineIndex,
    String sender, {
    String? offerId,
  }) async {
    return sendCandidatesBatch(
      roomCode,
      [
        {
          'candidate': candidate,
          'sdpMid': sdpMid,
          'sdpMLineIndex': sdpMLineIndex,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }
      ],
      sender,
      offerId: offerId,
    );
  }

  Future<List<Map<String, dynamic>>> getCandidates(
    String roomCode,
    String forRole, {
    String? expectedOfferId,
  }) async {
    final codes = _possibleCodes(roomCode);
    final targetSender = forRole == 'kid' ? 'parent' : 'kid';
    final List<Map<String, dynamic>> results = [];

    for (final c in codes) {
      final msgs = await _getNtfyMessages('kg_signal_${c}_cand_$targetSender', since: '2m');
      for (final m in msgs) {
        final payload = m['payload'] as Map<String, dynamic>;
        final msgOfferId = payload['offerId']?.toString();
        if (expectedOfferId != null && msgOfferId != null && msgOfferId != expectedOfferId) {
          continue; // Stale ICE candidate batch from an older offer
        }
        if (payload['candidates'] is List) {
          for (final item in payload['candidates']) {
            if (item is Map && item['candidate'] != null) {
              results.add(Map<String, dynamic>.from(item));
            }
          }
        } else if (payload['candidate'] != null) {
          results.add(payload);
        }
      }
    }

    return results;
  }

  Future<bool> sendAction(String roomCode, Map<String, dynamic> actionData) async {
    final codes = _possibleCodes(roomCode);
    final payload = jsonEncode({
      ...actionData,
      'actionId': IceConfigService.generateId('act'),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    bool ok = false;
    for (final c in codes) {
      if (await _postNtfy('kg_signal_${c}_action', payload)) {
        ok = true;
      }

      if (!_serverDisabled && baseUrl.isNotEmpty) {
        try {
          final uri = Uri.parse('$baseUrl/api/signal/room/$c/action');
          final request = await _client.postUrl(uri);
          request.followRedirects = false;
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode({
            'action': actionData['type'] ?? 'REMOTE_ACTION',
            'payload': actionData,
          }));
          final resp = await request.close().timeout(const Duration(seconds: 2));
          await resp.drain<void>().timeout(const Duration(seconds: 1), onTimeout: () {});
          if (resp.statusCode == 302 || resp.statusCode == 401 || resp.statusCode == 403) {
            _serverDisabled = true;
          } else if (resp.statusCode == 200) {
            ok = true;
          }
        } catch (_) {}
      }
    }
    return ok;
  }

  Future<List<Map<String, dynamic>>> getActions(String roomCode, int sinceTimestamp) async {
    final List<Map<String, dynamic>> actions = [];
    final codes = _possibleCodes(roomCode);
    for (final c in codes) {
      if (!_serverDisabled && baseUrl.isNotEmpty) {
        try {
          final uri = Uri.parse('$baseUrl/api/signal/room/$c/actions?since=$sinceTimestamp');
          final request = await _client.getUrl(uri);
          request.followRedirects = false;
          final response = await request.close().timeout(const Duration(seconds: 2));
          if (response.statusCode == 302 || response.statusCode == 401 || response.statusCode == 403) {
            _serverDisabled = true;
            await response.drain<void>();
          } else if (response.statusCode == 200) {
            final body = await response.transform(utf8.decoder).join();
            final json = jsonDecode(body);
            if (json is Map && json['actions'] is List) {
              for (final a in json['actions']) {
                if (a is Map && a['payload'] is Map) {
                  actions.add(Map<String, dynamic>.from(a['payload']));
                }
              }
            }
          } else {
            await response.drain<void>();
          }
        } catch (_) {}
      }

      if (actions.isNotEmpty) return actions;

      final msgs = await _getNtfyMessages('kg_signal_${c}_action', since: '30s');
      for (final m in msgs) {
        final payload = m['payload'] as Map<String, dynamic>;
        actions.add({
          ...payload,
          '_ntfyId': m['ntfyId'],
        });
      }
      if (actions.isNotEmpty) break;
    }
    return actions;
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
    required String Function() getOfferId,
    required Future<Map<String, dynamic>> Function(String? reqId) onRequestFreshOffer,
    required Function() onParentDisconnected,
    required Function(String sdp, String type) onAnswerReceived,
    required Function(RTCIceCandidate candidate) onCandidateReceived,
    required List<Map<String, dynamic>> Function() getChildCandidates,
    Function(Map<String, dynamic> action)? onActionReceived,
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
            final isRefresh = request.uri.queryParameters['refresh'] == '1' || request.method == 'POST';
            final reqId = request.uri.queryParameters['reqId'];
            String sdp;
            String type;
            String offerId;
            if (isRefresh) {
              final freshData = await onRequestFreshOffer(reqId);
              sdp = freshData['sdp'] ?? '';
              type = freshData['type'] ?? 'offer';
              offerId = freshData['offerId'] ?? getOfferId();
            } else {
              sdp = getOfferSdp();
              type = getOfferType();
              offerId = getOfferId();
            }
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode({
              'sdp': sdp,
              'type': type,
              'offerId': offerId,
              'code': clean,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            }));
          } else if (path == '/request-offer') {
            final reqId = request.uri.queryParameters['reqId'];
            final freshData = await onRequestFreshOffer(reqId);
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode({
              'sdp': freshData['sdp'] ?? '',
              'type': freshData['type'] ?? 'offer',
              'offerId': freshData['offerId'] ?? getOfferId(),
              'code': clean,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            }));
          } else if (path == '/disconnect') {
            onParentDisconnected();
            request.response.statusCode = HttpStatus.ok;
            request.response.write(jsonEncode({'success': true}));
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
          } else if (path == '/action' && request.method == 'POST') {
            final body = await utf8.decoder.bind(request).join();
            final data = jsonDecode(body);
            if (data is Map && onActionReceived != null) {
              onActionReceived(Map<String, dynamic>.from(data));
            }
            request.response.statusCode = HttpStatus.ok;
            request.response.write(jsonEncode({'success': true}));
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
          'offerId': getOfferId(),
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

  // 2. PARENT DEVICE: Discover Child via Local Wi-Fi (race-free: at most ONE refresh call!)
  Future<Map<String, dynamic>?> discoverOnLan(
    String roomCode, {
    bool requestFresh = false,
    String? reqId,
  }) async {
    final clean = cleanCode(roomCode);
    final completer = Completer<Map<String, dynamic>?>();
    bool cancelled = false;

    RawDatagramSocket? listener;
    Timer? timeoutTimer;

    void finishDiscovery(Map<String, dynamic>? result) {
      if (!completer.isCompleted) {
        cancelled = true;
        completer.complete(result);
      }
    }

    try {
      listener = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        8999,
        reuseAddress: true,
        reusePort: true,
      );
      listener.broadcastEnabled = true;

      listener.listen((RawSocketEvent event) {
        if (cancelled) return;
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

                  if (!cancelled && json['sdp'] != null) {
                    finishDiscovery({
                      'sdp': json['sdp'],
                      'type': json['type'] ?? 'offer',
                      'offerId': json['offerId'],
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

    // Read-only subnet probe in parallel (never calls ?refresh=1 blindly!)
    _probeSubnetForChild(clean, isCancelled: () => cancelled).then((res) {
      if (res != null && !cancelled) {
        _lanPeerIp = res['lanIp'];
        _lanPeerPort = res['lanPort'] ?? 8998;
        finishDiscovery(res);
      }
    });

    timeoutTimer = Timer(const Duration(milliseconds: 1100), () {
      finishDiscovery(null);
      try {
        listener?.close();
      } catch (_) {}
    });

    final discovered = await completer.future;
    timeoutTimer.cancel();
    try {
      listener?.close();
    } catch (_) {}

    if (discovered != null && requestFresh && _lanPeerIp != null) {
      final fresh = await requestFreshOfferFromLan(reqId: reqId);
      if (fresh != null) return fresh;
    }
    return discovered;
  }

  Future<Map<String, dynamic>?> _probeSubnetForChild(
    String cleanCode, {
    required bool Function() isCancelled,
  }) async {
    try {
      final localIps = await getLocalIps();
      for (final ip in localIps) {
        if (isCancelled()) return null;
        final parts = ip.split('.');
        if (parts.length != 4) continue;
        // Only probe private LAN subnets (skip cellular CGNAT IPs)
        if (ip.startsWith('10.') || ip.startsWith('192.168.') || ip.startsWith('172.')) {
          final subnetPrefix = '${parts[0]}.${parts[1]}.${parts[2]}';
          final myLastOctet = int.tryParse(parts[3]) ?? 0;

          final candidateOctets = <int>[];
          for (int offset = 1; offset <= 20; offset++) {
            if (myLastOctet - offset > 1) candidateOctets.add(myLastOctet - offset);
            if (myLastOctet + offset < 254) candidateOctets.add(myLastOctet + offset);
          }

          final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 220);
          for (final octet in candidateOctets) {
            if (isCancelled()) break;
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
                      'offerId': json['offerId'],
                      'lanIp': targetIp,
                      'lanPort': 8998,
                    };
                  }
                }
              } else {
                await resp.drain<void>();
              }
            } catch (_) {}
          }
          client.close();
        }
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> requestFreshOfferFromLan({String? reqId}) async {
    if (_lanPeerIp == null) return null;
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final q = reqId != null ? '?refresh=1&reqId=${Uri.encodeComponent(reqId)}' : '?refresh=1';
      final uri = Uri.parse('http://$_lanPeerIp:$_lanPeerPort/offer$q');
      final req = await client.getUrl(uri);
      final resp = await req.close().timeout(const Duration(seconds: 2));
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        final json = jsonDecode(body);
        client.close();
        if (json is Map && json['sdp'] != null) {
          return {
            'sdp': json['sdp'],
            'type': json['type'] ?? 'offer',
            'offerId': json['offerId'],
            'lanIp': _lanPeerIp,
            'lanPort': _lanPeerPort,
          };
        }
      } else {
        await resp.drain<void>();
      }
      client.close();
    } catch (_) {}
    return null;
  }

  Future<List<Map<String, dynamic>>> fetchCandidatesFromLan() async {
    if (_lanPeerIp == null) return [];
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
      final uri = Uri.parse('http://$_lanPeerIp:$_lanPeerPort/candidates');
      final req = await client.getUrl(uri);
      final resp = await req.close().timeout(const Duration(seconds: 1));
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        final json = jsonDecode(body);
        client.close();
        if (json is Map && json['candidates'] is List) {
          return (json['candidates'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } else {
        await resp.drain<void>();
      }
      client.close();
    } catch (_) {}
    return [];
  }

  Future<void> sendDisconnectToLan() async {
    if (_lanPeerIp == null) return;
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
      final uri = Uri.parse('http://$_lanPeerIp:$_lanPeerPort/disconnect');
      final req = await client.postUrl(uri);
      final resp = await req.close().timeout(const Duration(seconds: 1));
      await resp.drain<void>();
      client.close();
    } catch (_) {}
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
      await resp.drain<void>();
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
      final resp = await req.close().timeout(const Duration(seconds: 1));
      await resp.drain<void>();
      client.close();
    } catch (_) {}
  }

  Future<bool> sendActionToLan(Map<String, dynamic> actionData) async {
    if (_lanPeerIp == null) return false;
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
      final uri = Uri.parse('http://$_lanPeerIp:$_lanPeerPort/action');
      final req = await client.postUrl(uri);
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(actionData));
      final resp = await req.close().timeout(const Duration(seconds: 1));
      await resp.drain<void>();
      client.close();
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
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
// TURN RELAY SETTINGS DIALOG (For Strict Mobile Data / 4G / 5G CGNAT)
// -------------------------------------------------------------
Future<void> showTurnSettingsDialog(BuildContext context) async {
  final current = await IceConfigService.loadSettings();
  final meteredCtrl = TextEditingController(text: current['meteredUrl'] ?? '');
  final turnCtrl = TextEditingController(text: current['turnUrl'] ?? '');
  final userCtrl = TextEditingController(text: current['username'] ?? '');
  final credCtrl = TextEditingController(text: current['credential'] ?? '');

  if (!context.mounted) return;
  await showDialog(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.cell_tower, color: Colors.cyanAccent),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'मोबाइल डेटा TURN Relay सेटिंग',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'अगर Wi-Fi पर ऐप चलता है लेकिन 4G/5G मोबाइल डेटा पर CGNAT ब्लॉक के कारण कनेक्ट नहीं होता, तो यहाँ फ्री Metered.ca API URL या Custom TURN सर्वर डालें (केवल एक फोन में डालने पर भी दोनों में काम करेगा):',
                style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.35),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: meteredCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  labelText: 'Metered API URL (वैकल्पिक)',
                  hintText: 'https://xxx.metered.live/api/v1/turn/credentials?apiKey=...',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: turnCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  labelText: 'Custom TURN URL (वैकल्पिक)',
                  hintText: 'turn:global.relay.metered.ca:80?transport=tcp',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: userCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  labelText: 'TURN Username',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: credCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  labelText: 'TURN Credential / Password',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await IceConfigService.saveSettings();
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('TURN सेटिंग रीसेट कर दी गई।')),
                );
              }
            },
            child: const Text('साफ़ करें', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0891B2),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              await IceConfigService.saveSettings(
                meteredUrl: meteredCtrl.text,
                turnUrl: turnCtrl.text,
                username: userCtrl.text,
                credential: credCtrl.text,
              );
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ मोबाइल डेटा TURN Relay सेटिंग सेव हो गई!'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('सेव करें'),
          ),
        ],
      );
    },
  );
  meteredCtrl.dispose();
  turnCtrl.dispose();
  userCtrl.dispose();
  credCtrl.dispose();
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
        actions: [
          IconButton(
            icon: const Icon(Icons.cell_tower, color: Colors.cyanAccent),
            tooltip: 'मोबाइल डेटा TURN सेटिंग',
            onPressed: () => showTurnSettingsDialog(context),
          ),
        ],
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
              const SizedBox(height: 24),
              TextButton.icon(
                icon: const Icon(Icons.settings_ethernet, size: 18, color: Colors.cyanAccent),
                label: const Text(
                  'मोबाइल डेटा (4G/5G) TURN Relay सेटिंग',
                  style: TextStyle(color: Colors.cyanAccent, fontSize: 13),
                ),
                onPressed: () => showTurnSettingsDialog(context),
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

class _ChildScreenCaptureState extends State<ChildScreenCapture> with WidgetsBindingObserver {
  static const MethodChannel _platformChannel = MethodChannel('com.example.kidguard_live/screen_capture');
  final SignalingService _signaling = SignalingService();
  final LocalLanSignaling _localLan = LocalLanSignaling();
  final TextEditingController _codeController = TextEditingController(text: 'KID-8429');

  RTCPeerConnection? _peerConnection;
  MediaStream? _screenStream;
  bool _isSharing = false;
  bool _isStartingShare = false;
  bool _isPreparingPc = false;
  String _statusMessage = 'तैयार है। स्क्रीन शेयर शुरू करें।';
  bool _isParentConnected = false;
  String _parentPin = '1234'; // Security PIN to stop broadcast or change settings

  // Live Audio & Remote Touch state
  MediaStream? _micStream;
  MediaStreamTrack? _micAudioTrack;
  bool _isMicActive = true;
  RTCDataChannel? _childDataChannel;
  Offset? _lastRemoteTouchPoint;
  String? _remoteActionFeedback;
  Timer? _actionFeedbackTimer;
  Timer? _actionPollTimer;
  int _lastActionTimestamp = 0;
  final Set<String> _handledActionIds = {};

  Timer? _answerPollTimer;
  Timer? _candidatePollTimer;
  Timer? _offerHeartbeatTimer;
  Timer? _reconnectListenTimer;
  Timer? _iceDisconnectGraceTimer;
  Timer? _candidateFlushTimer;
  int _offerCreatedAtMs = 0;
  String _currentOfferId = '';
  String? _currentReplyReqId;
  String? _latestOfferSdp;
  String? _latestOfferType;
  bool _isRemoteDescSet = false;
  final Set<String> _handledReqIds = {};
  final Set<String> _handledDisconnectIds = {};
  final Set<String> _addedRemoteCandidateKeys = {};
  final List<RTCIceCandidate> _queuedCandidates = [];
  final List<Map<String, dynamic>> _collectedChildCandidates = [];
  final List<Map<String, dynamic>> _outgoingCandidateBuffer = [];
  List<Map<String, dynamic>>? _remoteTurnServers;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initForegroundTask();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isSharing) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // Keep mic and foreground service alive when Poco/Xiaomi enters background
      _micAudioTrack?.enabled = _isMicActive;
      _platformChannel.invokeMethod('upgradeScreenCaptureService').catchError((_) {});
    } else if (state == AppLifecycleState.resumed) {
      _micAudioTrack?.enabled = _isMicActive;
    }
  }

  void _handleIncomingRemoteAction(String rawJson) {
    try {
      final map = jsonDecode(rawJson);
      if (map is! Map) return;
      final type = map['type'] as String? ?? map['action'] as String? ?? '';

      if (type == 'TOGGLE_AUDIO') {
        final enabled = map['enabled'] as bool? ?? true;
        if (mounted) {
          setState(() {
            _isMicActive = enabled;
            _remoteActionFeedback = enabled ? '🎙️ माता-पिता ने ऑडियो चालू किया (माइक लाइव)' : '🔇 माता-पिता ने ऑडियो म्यूट किया';
          });
        }
        _micAudioTrack?.enabled = enabled;
        _resetFeedbackTimer();
      } else if (type == 'REMOTE_TOUCH') {
        final x = (map['x'] as num?)?.toDouble() ?? 0.5;
        final y = (map['y'] as num?)?.toDouble() ?? 0.5;
        HapticFeedback.lightImpact();
        if (mounted) {
          setState(() {
            _lastRemoteTouchPoint = Offset(x, y);
            _remoteActionFeedback = '👆 माता-पिता का रिमोट टच: ${(x * 100).toStringAsFixed(0)}%, ${(y * 100).toStringAsFixed(0)}%';
          });
        }
        _resetFeedbackTimer();
      } else if (type == 'REMOTE_NAV') {
        final key = map['key'] as String? ?? map['action'] as String? ?? '';
        HapticFeedback.mediumImpact();
        if (mounted) {
          setState(() {
            _remoteActionFeedback = '👆 रिमोट नेविगेशन: $key';
          });
        }
        _resetFeedbackTimer();
      }
    } catch (e) {
      debugPrint("Remote action parse error: $e");
    }
  }

  void _resetFeedbackTimer() {
    _actionFeedbackTimer?.cancel();
    _actionFeedbackTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _lastRemoteTouchPoint = null;
          _remoteActionFeedback = null;
        });
      }
    });
  }

  void _toggleLocalMic() {
    setState(() {
      _isMicActive = !_isMicActive;
      _micAudioTrack?.enabled = _isMicActive;
      _remoteActionFeedback = _isMicActive
          ? '🎙️ लाइव ऑडियो चालू है (माइक एक्टिव)'
          : '🔇 लाइव ऑडियो म्यूट किया गया';
    });
    _resetFeedbackTimer();
  }

  void _startPollingForActions(String roomCode) {
    _actionPollTimer?.cancel();
    _lastActionTimestamp = DateTime.now().millisecondsSinceEpoch;
    _handledActionIds.clear();
    _actionPollTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) async {
      if (!_isSharing) return;
      final actions = await _signaling.getActions(roomCode, _lastActionTimestamp);
      for (final a in actions) {
        final aid = (a['actionId'] ?? a['_ntfyId'] ?? '').toString();
        final ts = a['timestamp'] as int? ?? 0;
        if (aid.isNotEmpty) {
          if (_handledActionIds.contains(aid)) continue;
          _handledActionIds.add(aid);
          // Only process actions created close to or after broadcast started
          if (ts > 0 && ts < _lastActionTimestamp - 15000) continue;
          _handleIncomingRemoteAction(jsonEncode(a));
        } else if (ts > _lastActionTimestamp) {
          _lastActionTimestamp = ts;
          _handleIncomingRemoteAction(jsonEncode(a));
        }
      }
    });
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

  void _scheduleCandidateBatchFlush(String roomCode, String offerId) {
    _candidateFlushTimer?.cancel();
    _candidateFlushTimer = Timer(const Duration(milliseconds: 350), () {
      if (_outgoingCandidateBuffer.isEmpty || !_isSharing) return;
      final batch = List<Map<String, dynamic>>.from(_outgoingCandidateBuffer);
      _outgoingCandidateBuffer.clear();
      _signaling.sendCandidatesBatch(roomCode, batch, 'kid', offerId: offerId);
    });
  }

  void _setupChildPeerConnectionListeners(String roomCode, String offerId) {
    if (_peerConnection == null) return;

    try {
      final dcInit = RTCDataChannelInit();
      _peerConnection!.createDataChannel('controlChannel', dcInit).then((dc) {
        _childDataChannel = dc;
        _childDataChannel!.onMessage = (RTCDataChannelMessage msg) {
          _handleIncomingRemoteAction(msg.text);
        };
      }).catchError((_) {});
    } catch (_) {}

    _peerConnection!.onDataChannel = (RTCDataChannel channel) {
      _childDataChannel = channel;
      _childDataChannel!.onMessage = (RTCDataChannelMessage msg) {
        _handleIncomingRemoteAction(msg.text);
      };
    };

    _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
      debugPrint("📡 [Kid] ICE Connection State: $state");
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _iceDisconnectGraceTimer?.cancel();
        _iceDisconnectGraceTimer = null;
        if (mounted) {
          setState(() {
            _isParentConnected = true;
            _statusMessage = '✅ माता-पिता का फोन सफलतापूर्वक जुड़ गया है!';
          });
        }
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        // Grace period: WebRTC often self-recovers in 1-3s when app goes to background!
        // Never tear down the PeerConnection immediately on transient Disconnected!
        if (mounted) {
          setState(() {
            _statusMessage = '🔄 नेटवर्क अस्थायी रूप से धीमा है — कनेक्शन बनाए रख रहे हैं...';
          });
        }
        _iceDisconnectGraceTimer?.cancel();
        _iceDisconnectGraceTimer = Timer(const Duration(seconds: 8), () {
          if (!_isSharing || _screenStream == null) return;
          if (mounted) {
            setState(() {
              _isParentConnected = false;
              _statusMessage = 'माता-पिता का फोन डिस्कनेक्ट हो गया। पुनः जुड़ने की प्रतीक्षा...';
            });
          }
          _prepareFreshPeerConnection(roomCode, force: true);
        });
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _iceDisconnectGraceTimer?.cancel();
        _iceDisconnectGraceTimer = null;
        if (mounted) {
          setState(() {
            _isParentConnected = false;
            _statusMessage = 'कनेक्शन असफल (मोबाइल डेटा पर TURN सेटिंग जांचें)। पुनः प्रयास प्रतीक्षा...';
          });
        }
        _prepareFreshPeerConnection(roomCode, force: true);
      }
    };

    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null) {
        final item = {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };
        _collectedChildCandidates.add(item);
        _outgoingCandidateBuffer.add(item);
        _scheduleCandidateBatchFlush(roomCode, offerId);
      }
    };
  }

  // Generates a brand new PeerConnection from the EXISTING running screen stream
  // ZERO PERMISSION PROMPT REQUIRED! Screen continues streaming continuously!
  Future<Map<String, dynamic>> _prepareFreshPeerConnection(
    String roomCode, {
    String? reqId,
    List<Map<String, dynamic>>? extraTurnServers,
    bool force = false,
  }) async {
    if (!_isSharing || _screenStream == null) {
      return {
        'sdp': _latestOfferSdp ?? '',
        'type': _latestOfferType ?? 'offer',
        'offerId': _currentOfferId,
      };
    }

    if (reqId != null && reqId.isNotEmpty) {
      if (_handledReqIds.contains(reqId)) {
        debugPrint("⏭️ [Kid] Skipping duplicate reqId=$reqId");
        return {
          'sdp': _latestOfferSdp ?? '',
          'type': _latestOfferType ?? 'offer',
          'offerId': _currentOfferId,
        };
      }
      _handledReqIds.add(reqId);
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (!force &&
        !_isRemoteDescSet &&
        !_isParentConnected &&
        _offerCreatedAtMs > 0 &&
        (nowMs - _offerCreatedAtMs) < 3500 &&
        _latestOfferSdp != null) {
      debugPrint("⏭️ [Kid] Keeping freshly created offer (${nowMs - _offerCreatedAtMs}ms old)");
      return {
        'sdp': _latestOfferSdp ?? '',
        'type': _latestOfferType ?? 'offer',
        'offerId': _currentOfferId,
      };
    }

    if (_isPreparingPc) {
      debugPrint("⏭️ [Kid] Already preparing PeerConnection, returning active offer");
      return {
        'sdp': _latestOfferSdp ?? '',
        'type': _latestOfferType ?? 'offer',
        'offerId': _currentOfferId,
      };
    }

    _isPreparingPc = true;
    debugPrint("🔄 [Kid] Generating fresh WebRTC offer (reqId=$reqId, screen stream kept alive)...");

    _iceDisconnectGraceTimer?.cancel();
    _iceDisconnectGraceTimer = null;
    _candidateFlushTimer?.cancel();
    _outgoingCandidateBuffer.clear();
    _answerPollTimer?.cancel();
    _candidatePollTimer?.cancel();

    try {
      await _peerConnection?.close();
    } catch (_) {}
    _peerConnection = null;
    _isRemoteDescSet = false;
    _isParentConnected = false;
    _queuedCandidates.clear();
    _collectedChildCandidates.clear();
    _addedRemoteCandidateKeys.clear();

    if (extraTurnServers != null && extraTurnServers.isNotEmpty) {
      _remoteTurnServers = extraTurnServers;
    }

    try {
      final newOfferId = IceConfigService.generateId('off');
      _currentOfferId = newOfferId;
      _currentReplyReqId = reqId;
      _offerCreatedAtMs = DateTime.now().millisecondsSinceEpoch;

      final iceConfig = await IceConfigService.buildIceConfig(extraTurnServers: _remoteTurnServers);
      _peerConnection = await createPeerConnection(iceConfig);
      _setupChildPeerConnectionListeners(roomCode, newOfferId);

      for (final track in _screenStream!.getTracks()) {
        await _peerConnection!.addTrack(track, _screenStream!);
      }
      if (_micAudioTrack != null && _micStream != null) {
        await _peerConnection!.addTrack(_micAudioTrack!, _micStream!);
      }

      RTCSessionDescription offer = await _peerConnection!.createOffer({
        'offerToReceiveVideo': 0,
        'offerToReceiveAudio': 0,
      });
      await _peerConnection!.setLocalDescription(offer);
      _latestOfferSdp = offer.sdp;
      _latestOfferType = offer.type;

      final localTurnServers = await IceConfigService.getCustomTurnServers();
      _startPollingForAnswer(roomCode, newOfferId);
      _signaling.sendOffer(
        roomCode,
        offer.sdp!,
        offer.type!,
        offerId: newOfferId,
        replyToReqId: reqId,
        turnServers: localTurnServers,
      );

      if (mounted) {
        setState(() {
          _isParentConnected = false;
          _statusMessage = '🔴 ब्रॉडकास्ट सक्रिय है! कोड: $roomCode\nमाता-पिता के जुड़ने की प्रतीक्षा...';
        });
      }

      return {
        'sdp': offer.sdp ?? '',
        'type': offer.type ?? 'offer',
        'offerId': newOfferId,
      };
    } catch (e) {
      debugPrint("Error preparing fresh peer connection: $e");
      return {
        'sdp': _latestOfferSdp ?? '',
        'type': _latestOfferType ?? 'offer',
        'offerId': _currentOfferId,
      };
    } finally {
      _isPreparingPc = false;
    }
  }

  void _startListeningForReconnectRequests(String roomCode) {
    _reconnectListenTimer?.cancel();
    _reconnectListenTimer = Timer.periodic(const Duration(milliseconds: 1400), (_) async {
      if (!_isSharing || _screenStream == null) return;

      // 1. Check parent connect request (matched purely by unique reqId — zero clock skew!)
      final reqData = await _signaling.getLatestRequest(roomCode);
      if (reqData != null) {
        final reqId = (reqData['reqId'] ?? reqData['_ntfyId'] ?? '').toString();

        List<Map<String, dynamic>>? extraTurn;
        if (reqData['turnServers'] is List) {
          extraTurn = (reqData['turnServers'] as List)
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();
        }

        final bool isNewReqId = reqId.isNotEmpty && !_handledReqIds.contains(reqId);
        if (isNewReqId) {
          debugPrint("⚡ [Kid] Received fresh connection request from Parent (reqId=$reqId)");
          await _prepareFreshPeerConnection(
            roomCode,
            reqId: reqId,
            extraTurnServers: extraTurn,
            force: true,
          );
          return;
        }
      }

      // 2. Check explicit parent disconnect event ONLY when an active session exists
      if (_isParentConnected || _isRemoteDescSet) {
        final discData = await _signaling.getLatestDisconnect(roomCode);
        if (discData != null) {
          final discId = (discData['disconnectId'] ?? discData['_ntfyId'] ?? '').toString();
          final discOfferId = discData['offerId']?.toString();
          final bool isNewDisc = discId.isNotEmpty && !_handledDisconnectIds.contains(discId);
          final bool matchesActiveOffer = discOfferId == null || discOfferId == _currentOfferId;
          if (isNewDisc && matchesActiveOffer) {
            _handledDisconnectIds.add(discId);
            debugPrint("⚡ [Kid] Received explicit disconnect for offer $_currentOfferId ($discId)");
            await _prepareFreshPeerConnection(roomCode, force: true);
          } else if (discId.isNotEmpty) {
            _handledDisconnectIds.add(discId);
          }
        }
      }
    });
  }

  Future<void> _startScreenShare() async {
    if (_isStartingShare || _isSharing) return;
    final roomCode = _codeController.text.trim().toUpperCase();
    if (roomCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('कृपया पेयरिंग कोड दर्ज करें')),
      );
      return;
    }

    _isStartingShare = true;
    try {
      setState(() {
        _statusMessage = 'अनुमतियां जांच रहे हैं...';
      });

      try {
        bool askedPerm = false;
        if (!await Permission.notification.isGranted) {
          await Permission.notification.request();
          askedPerm = true;
        }
        if (!await Permission.microphone.isGranted) {
          await Permission.microphone.request();
          askedPerm = true;
        }
        if (askedPerm) {
          await Future.delayed(const Duration(milliseconds: 250));
        }
      } catch (permError) {
        debugPrint('Permission notice: $permError');
      }

      // Ask for Battery Optimization exemption so HyperOS/Poco C71 doesn't kill Wi-Fi/socket in background
      try {
        final ignoring = await _platformChannel.invokeMethod('isIgnoringBatteryOptimizations');
        if (ignoring != true) {
          await _platformChannel.invokeMethod('requestIgnoreBatteryOptimizations');
          await Future.delayed(const Duration(milliseconds: 400));
        }
      } catch (batErr) {
        debugPrint('Battery optimization prompt notice: $batErr');
      }

      setState(() {
        _statusMessage = '1/4: WebRTC Peer Connection तैयार हो रहा है...';
      });

      final initialOfferId = IceConfigService.generateId('off');
      _currentOfferId = initialOfferId;
      _currentReplyReqId = null;
      _offerCreatedAtMs = DateTime.now().millisecondsSinceEpoch;
      _handledReqIds.clear();
      _handledDisconnectIds.clear();
      _addedRemoteCandidateKeys.clear();
      _outgoingCandidateBuffer.clear();

      // Seed any stale disconnect/request messages already sitting in ntfy before we start
      try {
        final preDisc = await _signaling.getLatestDisconnect(roomCode);
        if (preDisc != null) {
          final id = (preDisc['disconnectId'] ?? preDisc['_ntfyId'] ?? '').toString();
          if (id.isNotEmpty) _handledDisconnectIds.add(id);
        }
      } catch (_) {}

      final iceConfig = await IceConfigService.buildIceConfig(extraTurnServers: _remoteTurnServers);
      _peerConnection = await createPeerConnection(iceConfig);
      _setupChildPeerConnectionListeners(roomCode, initialOfferId);

      setState(() {
        _statusMessage = '2/4: स्क्रीन शेयर अनुमति मांग रहे हैं... (कृपया "Entire screen" चुनें)';
      });

      try {
        final ready = await _platformChannel.invokeMethod('prepareScreenCapture');
        if (ready != true) {
          try {
            await _peerConnection?.close();
          } catch (_) {}
          _peerConnection = null;
          if (mounted) {
            setState(() {
              _statusMessage = 'स्क्रीन शेयर अनुमति रद्द कर दी गई।';
            });
          }
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

      // Allow Android 14/15/16 (HyperOS/FuntouchOS) Activity to finish resuming after system dialog
      await Future.delayed(const Duration(milliseconds: 350));

      // Safely upgrade foreground service now that screen share consent has been granted
      try {
        await _platformChannel.invokeMethod('upgradeScreenCaptureService');
      } catch (upgradeErr) {
        debugPrint('upgradeScreenCaptureService notice: $upgradeErr');
      }

      stream.getVideoTracks().forEach((track) {
        track.onEnded = () {
          debugPrint('Screen capture track ended');
          if (mounted) {
            _stopScreenShare();
          }
        };
      });

      // Capture Microphone Audio for Parent Live Listening with Android 14/15/16 fallback
      try {
        try {
          _micStream = await navigator.mediaDevices.getUserMedia({
            'audio': {
              'mandatory': {
                'echoCancellation': true,
                'noiseSuppression': true,
                'autoGainControl': true,
              },
            },
            'video': false,
          });
        } catch (_) {
          _micStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
        }
        if (_micStream != null && _micStream!.getAudioTracks().isNotEmpty) {
          _micAudioTrack = _micStream!.getAudioTracks().first;
          _micAudioTrack!.enabled = _isMicActive;
          debugPrint('🎙️ [Kid] Mic capture initialized: enabled=${_micAudioTrack!.enabled}');
        }
      } catch (micErr) {
        debugPrint('🎙️ [Kid] Mic capture note (non-fatal): $micErr');
      }

      setState(() {
        _statusMessage = '3/4: वीडियो व ऑडियो ट्रैक PeerConnection में जोड़ रहे हैं...';
      });

      for (final track in stream.getTracks()) {
        await _peerConnection!.addTrack(track, stream);
      }
      if (_micAudioTrack != null && _micStream != null) {
        await _peerConnection!.addTrack(_micAudioTrack!, _micStream!);
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
      _offerCreatedAtMs = DateTime.now().millisecondsSinceEpoch;

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
        getOfferId: () => _currentOfferId,
        onRequestFreshOffer: (reqId) => _prepareFreshPeerConnection(roomCode, reqId: reqId),
        onParentDisconnected: () => _prepareFreshPeerConnection(roomCode, force: true),
        onActionReceived: (actionMap) {
          _handleIncomingRemoteAction(jsonEncode(actionMap));
        },
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
          final key = cand.candidate ?? '';
          if (key.isNotEmpty && _addedRemoteCandidateKeys.contains(key)) return;
          if (key.isNotEmpty) _addedRemoteCandidateKeys.add(key);
          if (_isRemoteDescSet) {
            await _peerConnection?.addCandidate(cand);
          } else {
            _queuedCandidates.add(cand);
          }
        },
        getChildCandidates: () => _collectedChildCandidates,
      );

      // Start action polling on Cloud Relay
      _startPollingForActions(roomCode);

      // 2. Poll for Parent's Answer on Cloud Relay
      _startPollingForAnswer(roomCode, initialOfferId);

      // 3. Listen for reconnection/offer requests from Parent
      _startListeningForReconnectRequests(roomCode);

      // 4. Send initial Offer asynchronously
      final initialTurns = await IceConfigService.getCustomTurnServers();
      _signaling
          .sendOffer(
            roomCode,
            offer.sdp!,
            offer.type!,
            offerId: initialOfferId,
            turnServers: initialTurns,
          )
          .then((ok) {
        if (mounted && _isSharing) {
          setState(() {
            _statusMessage = '🔴 ब्रॉडकास्ट सक्रिय है! कोड: $roomCode\nमाता-पिता के जुड़ने की प्रतीक्षा...';
          });
        }
      });

      // 5. Low-frequency Offer Heartbeat (every 12s, prevents ntfy.sh 429 rate-limit!)
      _offerHeartbeatTimer?.cancel();
      _offerHeartbeatTimer = Timer.periodic(const Duration(seconds: 12), (_) async {
        if (_isSharing && !_isParentConnected && _peerConnection != null && _latestOfferSdp != null) {
          final turns = await IceConfigService.getCustomTurnServers();
          _signaling.sendOffer(
            roomCode,
            _latestOfferSdp!,
            _latestOfferType ?? 'offer',
            offerId: _currentOfferId,
            replyToReqId: _currentReplyReqId,
            turnServers: turns,
          );
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
    } finally {
      _isStartingShare = false;
    }
  }

  // Listen / Poll for Parent's Answer
  void _startPollingForAnswer(String roomCode, String expectedOfferId) {
    _answerPollTimer?.cancel();
    _answerPollTimer = Timer.periodic(const Duration(milliseconds: 1200), (timer) async {
      if (!_isSharing || _isRemoteDescSet || _peerConnection == null) return;

      final answerData = await _signaling.getAnswer(roomCode, expectedOfferId: expectedOfferId);
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
        _startListeningToParentIceCandidates(roomCode, expectedOfferId);

        if (mounted) {
          setState(() {
            _statusMessage = 'माता-पिता का उत्तर मिल गया! कनेक्शन स्थापित हो रहा है...';
          });
        }
      }
    });
  }

  void _startListeningToParentIceCandidates(String roomCode, String expectedOfferId) {
    _candidatePollTimer?.cancel();
    _candidatePollTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) async {
      if (!_isSharing || _peerConnection == null) {
        timer.cancel();
        return;
      }

      final list = await _signaling.getCandidates(
        roomCode,
        'kid',
        expectedOfferId: expectedOfferId,
      );
      for (final item in list) {
        final cStr = item['candidate'] as String?;
        final sdpMid = item['sdpMid'] as String?;
        final sdpMLineIndex = item['sdpMLineIndex'] as int?;

        if (cStr != null && !_addedRemoteCandidateKeys.contains(cStr)) {
          _addedRemoteCandidateKeys.add(cStr);
          final candidate = RTCIceCandidate(cStr, sdpMid, sdpMLineIndex);
          if (_isRemoteDescSet) {
            try {
              await _peerConnection!.addCandidate(candidate);
            } catch (e) {
              debugPrint('Candidate add error: $e');
            }
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
    _reconnectListenTimer?.cancel();
    _reconnectListenTimer = null;
    _iceDisconnectGraceTimer?.cancel();
    _iceDisconnectGraceTimer = null;
    _candidateFlushTimer?.cancel();
    _candidateFlushTimer = null;
    _actionPollTimer?.cancel();
    _actionPollTimer = null;
    _actionFeedbackTimer?.cancel();
    _actionFeedbackTimer = null;
    _localLan.stop();
    _latestOfferSdp = null;
    _latestOfferType = null;
    _currentOfferId = '';
    _currentReplyReqId = null;
    _offerCreatedAtMs = 0;
    _collectedChildCandidates.clear();
    _outgoingCandidateBuffer.clear();
    _addedRemoteCandidateKeys.clear();

    try {
      await _platformChannel.invokeMethod('stopScreenCapture');
    } catch (_) {}
    try {
      _screenStream?.getTracks().forEach((track) => track.stop());
      await _screenStream?.dispose();
    } catch (_) {}
    _screenStream = null;
    try {
      _micAudioTrack?.stop();
      await _micStream?.dispose();
    } catch (_) {}
    _micAudioTrack = null;
    _micStream = null;
    try {
      await _childDataChannel?.close();
    } catch (_) {}
    _childDataChannel = null;
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

  void _promptPinToStop() {
    final pinController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.lock, color: Colors.amberAccent),
              SizedBox(width: 10),
              Text('सुरक्षा पिन (PIN Lock)', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'स्क्रीन शेयरिंग बंद करने के लिए माता-पिता का 4-अंकीय पिन दर्ज करें:\n(डिफ़ॉल्ट पिन: 1234)',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: pinController,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 4,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 26, letterSpacing: 8, color: Colors.cyanAccent, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '••••',
                  hintStyle: const TextStyle(color: Colors.grey, letterSpacing: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('रद्द करें', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                if (pinController.text == _parentPin) {
                  Navigator.pop(ctx);
                  _stopScreenShare();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✅ पिन सत्यापित: स्क्रीन शेयर बंद हो गया।')),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('❌ गलत पिन! केवल माता-पिता ही इसे बंद कर सकते हैं।'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('सत्यापित करें व बंद करें'),
            ),
          ],
        );
      },
    );
  }

  void _generateRandomCode() {
    final randomNum = 1000 + (DateTime.now().millisecondsSinceEpoch % 9000);
    setState(() {
      _codeController.text = 'KID-$randomNum';
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
        actions: [
          IconButton(
            icon: const Icon(Icons.cell_tower, color: Colors.cyanAccent),
            tooltip: 'मोबाइल डेटा TURN सेटिंग',
            onPressed: () => showTurnSettingsDialog(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Live Audio Status & Toggle Banner on Child Mobile Screen
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _isMicActive ? const Color(0xFF064E3B).withOpacity(0.85) : const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isMicActive ? Colors.greenAccent : Colors.white24,
                  width: 1.5,
                ),
                boxShadow: _isMicActive
                    ? [
                        BoxShadow(
                          color: Colors.greenAccent.withOpacity(0.25),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ]
                    : [],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isMicActive ? Colors.greenAccent.withOpacity(0.25) : Colors.white10,
                    ),
                    child: Icon(
                      _isMicActive ? Icons.mic : Icons.mic_off,
                      color: _isMicActive ? Colors.greenAccent : Colors.white54,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isMicActive ? '🎙️ लाइव ऑडियो: चालू (माइक एक्टिव)' : '🔇 लाइव ऑडियो: म्यूट (बंद)',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isMicActive
                              ? 'माता-पिता आपके फोन की लाइव आवाज सुन सकते हैं'
                              : 'माइक्रोफोन म्यूट है (कोई आवाज नहीं जा रही)',
                          style: TextStyle(
                            color: _isMicActive ? Colors.greenAccent.shade100 : Colors.white60,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isMicActive ? Colors.green : Colors.grey.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: const Size(60, 34),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _toggleLocalMic,
                    child: Text(
                      _isMicActive ? 'म्यूट' : 'चालू',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),

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

            if (_remoteActionFeedback != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF312E81).withOpacity(0.5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.cyanAccent.withOpacity(0.8), width: 1.5),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.touch_app, color: Colors.cyanAccent, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _remoteActionFeedback!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

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

            // Action Button with PIN Lock protection
            ElevatedButton.icon(
              icon: Icon(_isSharing ? Icons.lock_outline : Icons.play_arrow, size: 28),
              label: Text(
                _isSharing ? 'स्क्रीन शेयरिंग बंद करें (पिन आवश्यक)' : 'पूरे मोबाइल की स्क्रीन शेयर शुरू करें',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: _isSharing ? Colors.redAccent.shade700 : Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _isSharing ? _promptPinToStop : _startScreenShare,
            ),

            if (_isSharing) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amberAccent.withOpacity(0.5)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock, size: 16, color: Colors.amberAccent),
                    SizedBox(width: 8),
                    Text(
                      '🔒 पिन लॉक सुरक्षा सक्रिय (डिफ़ॉल्ट पिन: 1234) — बिना पिन ऐप बंद नहीं होगा',
                      style: TextStyle(fontSize: 11, color: Colors.amberAccent, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
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

  // Remote Touch & Live Audio Controls
  bool _isLiveAudioOn = false;
  bool _isRemoteTouchOn = false;
  MediaStreamTrack? _remoteAudioTrack;
  RTCDataChannel? _parentDataChannel;
  Offset? _touchFeedbackPos;
  Timer? _touchFeedbackTimer;

  Timer? _candidatePollTimer;
  Timer? _candidateFlushTimer;
  String? _activeOfferId;
  bool _isRemoteDescSet = false;
  final Set<String> _addedRemoteCandidateKeys = {};
  final List<RTCIceCandidate> _queuedCandidates = [];
  final List<Map<String, dynamic>> _outgoingCandidateBuffer = [];

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

  void _sendRemoteAction(Map<String, dynamic> actionData) {
    final roomCode = _codeController.text.trim().toUpperCase();
    if (roomCode.isEmpty) return;

    final fullData = {
      ...actionData,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    // 1. DataChannel (instant zero-latency WebRTC)
    try {
      if (_parentDataChannel != null) {
        _parentDataChannel!.send(RTCDataChannelMessage(jsonEncode(fullData)));
      }
    } catch (_) {}

    // 2. Direct LAN (if on same Wi-Fi)
    if (_isLanConnection) {
      _localLan.sendActionToLan(fullData);
    }

    // 3. Cloud Relay (ntfy)
    _signaling.sendAction(roomCode, fullData);
  }

  Future<void> _toggleLiveAudio() async {
    setState(() {
      _isLiveAudioOn = !_isLiveAudioOn;
    });

    if (_remoteAudioTrack != null) {
      _remoteAudioTrack!.enabled = _isLiveAudioOn;
    }

    // Route WebRTC voice output to loudspeaker instead of low-volume earpiece!
    try {
      await Helper.setSpeakerphoneOn(_isLiveAudioOn);
    } catch (_) {}

    _sendRemoteAction({
      'type': 'TOGGLE_AUDIO',
      'enabled': _isLiveAudioOn,
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isLiveAudioOn
              ? '🔊 लाइव ऑडियो चालू: बच्चे के फोन की आवाज सुनाई दे रही है'
              : '🔇 लाइव ऑडियो म्यूट किया गया'),
          duration: const Duration(seconds: 1),
          backgroundColor: _isLiveAudioOn ? Colors.teal : Colors.blueGrey,
        ),
      );
    }
  }

  void _toggleRemoteTouch() {
    setState(() {
      _isRemoteTouchOn = !_isRemoteTouchOn;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isRemoteTouchOn
            ? '👆 रिमोट टच चालू: स्क्रीन पर कहीं भी टैप करें'
            : '👆 रिमोट टच मोड बंद किया गया'),
        duration: const Duration(seconds: 1),
        backgroundColor: _isRemoteTouchOn ? Colors.green : Colors.blueGrey,
      ),
    );
  }

  void _handleRemoteScreenTap(Offset localPos, BoxConstraints constraints) {
    if (!_isRemoteTouchOn) return;

    final normX = (localPos.dx / constraints.maxWidth).clamp(0.0, 1.0);
    final normY = (localPos.dy / constraints.maxHeight).clamp(0.0, 1.0);

    setState(() {
      _touchFeedbackPos = localPos;
    });

    _touchFeedbackTimer?.cancel();
    _touchFeedbackTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) {
        setState(() {
          _touchFeedbackPos = null;
        });
      }
    });

    HapticFeedback.lightImpact();

    _sendRemoteAction({
      'type': 'REMOTE_TOUCH',
      'action': 'TAP',
      'x': normX,
      'y': normY,
    });
  }

  void _sendRemoteNavAction(String key, String label) {
    HapticFeedback.mediumImpact();
    _sendRemoteAction({
      'type': 'REMOTE_NAV',
      'key': key,
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('👆 रिमोट एक्शन भेजा: $label'),
        duration: const Duration(milliseconds: 700),
      ),
    );
  }

  void _scheduleParentCandidateBatchFlush(String roomCode, String? offerId) {
    _candidateFlushTimer?.cancel();
    _candidateFlushTimer = Timer(const Duration(milliseconds: 350), () {
      if (_outgoingCandidateBuffer.isEmpty) return;
      final batch = List<Map<String, dynamic>>.from(_outgoingCandidateBuffer);
      _outgoingCandidateBuffer.clear();
      _signaling.sendCandidatesBatch(roomCode, batch, 'parent', offerId: offerId);
    });
  }

  Future<void> _connectToChild() async {
    final roomCode = _codeController.text.trim().toUpperCase();
    if (roomCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('कृपया बच्चे का 6-अंकीय कोड दर्ज करें')),
      );
      return;
    }

    // Do NOT emit Cloud sendDisconnect when starting a fresh connection —
    // otherwise Child reads that disconnect 1.5s later and kills the new PeerConnection!
    _cleanupConnectionOnly(emitDisconnect: false);

    setState(() {
      _isConnecting = true;
      _statusText = 'बच्चे के फोन से ऑफर खोज रहे हैं...';
    });

    try {
      final reqTimestamp = DateTime.now().millisecondsSinceEpoch;
      final reqId = IceConfigService.generateId('req');
      final customTurnOnly = await IceConfigService.getCustomTurnServers();
      _isLanConnection = false;

      Map<String, dynamic>? offerData;
      bool sentCloudRequest = false;
      final Set<String> triedOfferIds = {};

      for (int attempt = 1; attempt <= 35; attempt++) {
        if (!mounted || !_isConnecting) return;
        setState(() {
          _statusText = 'बच्चे के फोन से सिग्नल खोज रहे हैं... ($attempt/35)';
        });

        // 1. Direct Wi-Fi LAN search (Instant when both phones are on same Wi-Fi)
        if (attempt == 1 || attempt % 5 == 0) {
          try {
            final lanOffer = await _localLan.discoverOnLan(
              roomCode,
              requestFresh: true,
              reqId: reqId,
            );
            if (lanOffer != null && lanOffer['sdp'] != null && (lanOffer['sdp'] as String).isNotEmpty) {
              offerData = lanOffer;
              _isLanConnection = true;
              debugPrint("🎯 [Parent] Discovered Child via Direct Wi-Fi LAN!");
              break;
            }
          } catch (_) {}
        }

        // 2. Send Cloud request only if LAN didn't immediately connect (avoids race/teardown!)
        if (!sentCloudRequest || attempt % 10 == 0) {
          sentCloudRequest = true;
          _signaling.requestFreshOffer(
            roomCode,
            reqTimestamp,
            reqId: reqId,
            turnServers: customTurnOnly,
          );
        }

        // 3. Cloud Relay search (ntfy.sh) - wait up to ~6 attempts for fresh replyToReqId offer first!
        offerData = await _signaling.getOffer(
          roomCode,
          reqId: reqId,
          requireMatchingReqId: attempt <= 6,
          excludeOfferIds: triedOfferIds,
        );
        if (offerData != null && offerData['sdp'] != null && (offerData['sdp'] as String).isNotEmpty) {
          debugPrint("🎯 [Parent] Discovered Child via Cloud Relay!");
          break;
        }

        await Future.delayed(const Duration(milliseconds: 1100));
      }

      if (offerData == null || offerData['sdp'] == null) {
        if (mounted) {
          setState(() {
            _isConnecting = false;
            _statusText = '⚠️ कोड $roomCode पर कोई एक्टिव स्क्रीन शेयर नहीं मिला।\nजांचें कि बच्चे के फोन में वही कोड ($roomCode) है और स्क्रीन शेयर चालू है।';
          });
        }
        return;
      }

      _activeOfferId = offerData['offerId']?.toString();

      List<Map<String, dynamic>>? childTurnServers;
      if (offerData['turnServers'] is List) {
        childTurnServers = (offerData['turnServers'] as List)
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
      }

      if (mounted) {
        setState(() {
          _statusText = _isLanConnection
              ? '⚡ वाई-फाई डायरेक्ट सिग्नल मिल गया! स्क्रीन लोड हो रही है...'
              : '✅ बच्चे का क्लाउड सिग्नल मिल गया! लाइव स्क्रीन कनेक्ट हो रही है...';
        });
      }

      final iceConfig = await IceConfigService.buildIceConfig(extraTurnServers: childTurnServers);
      _peerConnection = await createPeerConnection(iceConfig);

      // DataChannel listener on Parent
      _peerConnection!.onDataChannel = (RTCDataChannel channel) {
        _parentDataChannel = channel;
        _parentDataChannel!.onMessage = (RTCDataChannelMessage msg) {
          debugPrint("Parent received DataChannel message: ${msg.text}");
        };
      };

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
            } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
              _statusText = '🔄 नेटवर्क अस्थायी रूप से धीमा है — पुनः जुड़ने की प्रतीक्षा...';
            } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
              _isConnecting = false;
              _statusText = '❌ कनेक्शन असफल! मोबाइल डेटा (CGNAT) होने पर ऊपर 📡 TURN सेटिंग में फ्री Relay जोड़ें।';
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
        } else if (event.track.kind == 'audio') {
          _remoteAudioTrack = event.track;
          _remoteAudioTrack!.enabled = _isLiveAudioOn;
          if (_isLiveAudioOn) {
            try {
              await Helper.setSpeakerphoneOn(true);
            } catch (_) {}
          }
          debugPrint("🎙️ [Parent] Audio track registered: enabled=$_isLiveAudioOn");
        }
      };

      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate.candidate != null) {
          if (_isLanConnection) {
            _localLan.sendCandidateToLan(candidate);
          }
          _outgoingCandidateBuffer.add({
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
          _scheduleParentCandidateBatchFlush(roomCode, _activeOfferId);
        }
      };

      RTCSessionDescription offer = RTCSessionDescription(
        offerData['sdp'],
        offerData['type'] ?? 'offer',
      );
      await _peerConnection!.setRemoteDescription(offer);
      _isRemoteDescSet = true;

      RTCSessionDescription answer = await _peerConnection!.createAnswer({
        'offerToReceiveVideo': 1,
        'offerToReceiveAudio': 1,
      });
      await _peerConnection!.setLocalDescription(answer);

      // Send Answer to both LAN (if connected) and Cloud Relay
      if (_isLanConnection) {
        await _localLan.sendAnswerToLan(answer.sdp!, answer.type!);
      }
      await _signaling.sendAnswer(
        roomCode,
        answer.sdp!,
        answer.type!,
        offerId: _activeOfferId,
      );

      _startListeningToKidIceCandidates(roomCode, _activeOfferId);

      if (mounted) {
        setState(() {
          _statusText = 'उत्तर भेजा गया! वीडियो लोड हो रहा है...';
        });
      }
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

  void _startListeningToKidIceCandidates(String roomCode, String? expectedOfferId) {
    _candidatePollTimer?.cancel();
    _candidatePollTimer = Timer.periodic(const Duration(milliseconds: 1400), (timer) async {
      if (_peerConnection == null) {
        timer.cancel();
        return;
      }

      final List<Map<String, dynamic>> combined = [];
      if (_isLanConnection) {
        final lanCands = await _localLan.fetchCandidatesFromLan();
        combined.addAll(lanCands);
      }
      final cloudCands = await _signaling.getCandidates(
        roomCode,
        'parent',
        expectedOfferId: expectedOfferId,
      );
      combined.addAll(cloudCands);

      for (final item in combined) {
        final cStr = item['candidate'] as String?;
        final sdpMid = item['sdpMid'] as String?;
        final sdpMLineIndex = item['sdpMLineIndex'] as int?;

        if (cStr != null && !_addedRemoteCandidateKeys.contains(cStr)) {
          _addedRemoteCandidateKeys.add(cStr);
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

  void _cleanupConnectionOnly({bool emitDisconnect = false}) {
    final roomCode = _codeController.text.trim().toUpperCase();
    _candidatePollTimer?.cancel();
    _candidatePollTimer = null;
    _candidateFlushTimer?.cancel();
    _candidateFlushTimer = null;
    _touchFeedbackTimer?.cancel();
    _touchFeedbackTimer = null;
    _outgoingCandidateBuffer.clear();
    _addedRemoteCandidateKeys.clear();
    final activeOfferId = _activeOfferId;
    _activeOfferId = null;

    if (emitDisconnect) {
      _localLan.sendDisconnectToLan();
      if (roomCode.isNotEmpty) {
        _signaling.sendDisconnect(roomCode, offerId: activeOfferId);
      }
    }
    _localLan.stop();

    try {
      Helper.setSpeakerphoneOn(false);
    } catch (_) {}
    try {
      _parentDataChannel?.close();
    } catch (_) {}
    _parentDataChannel = null;
    _remoteAudioTrack?.stop();
    _remoteAudioTrack = null;
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
        _isLiveAudioOn = false;
        _isRemoteTouchOn = false;
        _touchFeedbackPos = null;
        _iceState = 'None';
        _videoResolution = '0x0';
        _statusText = 'डिस्कनेक्ट हो गया।';
      });
    }
  }

  void _disconnect() {
    _cleanupConnectionOnly(emitDisconnect: true);
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
    final bool isSessionConnected = (_isConnected || _hasRemoteVideo) && _remoteRenderer.srcObject != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('माता-पिता का लाइव मॉनिटर'),
        backgroundColor: const Color(0xFF1E293B),
        actions: [
          IconButton(
            icon: const Icon(Icons.cell_tower, color: Colors.cyanAccent),
            tooltip: 'मोबाइल डेटा TURN सेटिंग',
            onPressed: () => showTurnSettingsDialog(context),
          ),
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

            const SizedBox(height: 10),

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

            // ONLY WHEN CONNECTED: Render Remote Touch & Live Audio Controls
            if (isSessionConnected) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.cyanAccent.withOpacity(0.4)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        // 1. REMOTE TOUCH BUTTON
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: Icon(
                              _isRemoteTouchOn ? Icons.touch_app : Icons.touch_app_outlined,
                              size: 18,
                              color: Colors.white,
                            ),
                            label: Text(
                              _isRemoteTouchOn ? '👆 रिमोट टच: चालू' : '👆 रिमोट टच: बंद',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isRemoteTouchOn ? Colors.green.shade600 : Colors.blueGrey.shade800,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: _toggleRemoteTouch,
                          ),
                        ),
                        const SizedBox(width: 8),

                        // 2. LIVE AUDIO ON/OFF BUTTON
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: Icon(
                              _isLiveAudioOn ? Icons.volume_up : Icons.volume_off,
                              size: 18,
                              color: Colors.white,
                            ),
                            label: Text(
                              _isLiveAudioOn ? '🔊 ऑडियो: चालू' : '🔇 ऑडियो: बंद',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isLiveAudioOn ? Colors.teal.shade600 : Colors.blueGrey.shade800,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: _toggleLiveAudio,
                          ),
                        ),
                      ],
                    ),

                    if (_isLiveAudioOn) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.teal.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.tealAccent.withOpacity(0.5)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.graphic_eq, color: Colors.tealAccent, size: 16),
                            SizedBox(width: 6),
                            Text(
                              '🎙️ लाइव ऑडियो सक्रिय — बच्चे के आसपास की आवाज सुनाई दे रही है',
                              style: TextStyle(fontSize: 11, color: Colors.tealAccent, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],

                    if (_isRemoteTouchOn) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.greenAccent.withOpacity(0.5)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.ads_click, color: Colors.greenAccent, size: 16),
                            SizedBox(width: 6),
                            Text(
                              'स्क्रीन पर जहां टैप करेंगे, वही कमांड बच्चे के फोन पर जाएगी',
                              style: TextStyle(fontSize: 11, color: Colors.greenAccent, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            const SizedBox(height: 10),

            // Video Feed Container with Remote Touch Interaction
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _hasRemoteVideo
                        ? (_isRemoteTouchOn ? Colors.greenAccent : Colors.cyanAccent.withOpacity(0.5))
                        : Colors.white24,
                    width: _isRemoteTouchOn ? 2 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: isSessionConnected
                      ? LayoutBuilder(
                          builder: (context, constraints) {
                            return Stack(
                              children: [
                                SizedBox.expand(
                                  child: RTCVideoView(
                                    _remoteRenderer,
                                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                                  ),
                                ),

                                // Interactive Gesture Detector for Remote Touch
                                if (_isRemoteTouchOn)
                                  Positioned.fill(
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTapDown: (details) => _handleRemoteScreenTap(details.localPosition, constraints),
                                      child: Container(
                                        color: Colors.transparent,
                                      ),
                                    ),
                                  ),

                                // Animated Touch Feedback Ripple under finger
                                if (_touchFeedbackPos != null)
                                  Positioned(
                                    left: _touchFeedbackPos!.dx - 24,
                                    top: _touchFeedbackPos!.dy - 24,
                                    child: Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.cyanAccent.withOpacity(0.4),
                                        border: Border.all(color: Colors.white, width: 2),
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Colors.cyanAccent,
                                            blurRadius: 16,
                                            spreadRadius: 4,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
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

            // Remote Navigation Control Bar (ONLY when connected & Remote Touch is ON)
            if (isSessionConnected && _isRemoteTouchOn) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.greenAccent.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      tooltip: 'पीछे जाएं (Back)',
                      onPressed: () => _sendRemoteNavAction('BACK', 'पीछे जाएं (Back)'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.circle_outlined, color: Colors.white),
                      tooltip: 'होम स्क्रीन (Home)',
                      onPressed: () => _sendRemoteNavAction('HOME', 'होम स्क्रीन (Home)'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.crop_square, color: Colors.white),
                      tooltip: 'हाल के ऐप्स (Recents)',
                      onPressed: () => _sendRemoteNavAction('RECENTS', 'हाल के ऐप्स (Recents)'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_upward, color: Colors.white),
                      tooltip: 'ऊपर स्क्रॉल (Scroll Up)',
                      onPressed: () => _sendRemoteNavAction('SCROLL_UP', 'ऊपर स्क्रॉल (Scroll Up)'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_downward, color: Colors.white),
                      tooltip: 'नीचे स्क्रॉल (Scroll Down)',
                      onPressed: () => _sendRemoteNavAction('SCROLL_DOWN', 'नीचे स्क्रॉल (Scroll Down)'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.notifications_active, color: Colors.amberAccent),
                      tooltip: 'अलर्ट घंटी (Buzzer)',
                      onPressed: () => _sendRemoteNavAction('BUZZER', 'अलर्ट बज़र बज गया'),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 10),

            if (isSessionConnected)
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
