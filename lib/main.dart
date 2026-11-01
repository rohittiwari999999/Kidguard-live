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
const String kDefaultSignalingServer = 'https://ais-pre-6snjgczxe5mnz34fbgzs4p-751137797858.asia-east1.run.app';

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
      // 1. Send to Cloud Run server
      try {
        final uri = Uri.parse('$baseUrl/api/signal/room/$c/offer');
        final request = await _client.postUrl(uri);
        request.headers.contentType = ContentType.json;
        request.write(payload);
        final response = await request.close().timeout(const Duration(seconds: 2));
        if (response.statusCode == 200) ok = true;
      } catch (_) {}

      // 2. JSON publish to ntfy
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

      // 3. Direct topic path publish with raw text
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

  Future<Map<String, dynamic>?> getOffer(String roomCode, {int minTimestamp = 0}) async {
    final codes = _possibleCodes(roomCode);
    for (final c in codes) {
      // 1. Try Cloud Run server first
      try {
        final uri = Uri.parse('$baseUrl/api/signal/room/$c/offer');
        final request = await _client.getUrl(uri);
        final response = await request.close().timeout(const Duration(seconds: 2));
        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join();
          final json = jsonDecode(body);
          if (json is Map && json['sdp'] != null) {
            final ts = json['timestamp'] as int? ?? 0;
            if (ts >= minTimestamp) {
              return Map<String, dynamic>.from(json);
            }
          }
        }
      } catch (_) {}

      // 2. Fallback to ntfy.sh
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
                  final ts = payload['timestamp'] as int? ?? 0;
                  if (ts >= minTimestamp) {
                    return Map<String, dynamic>.from(payload);
                  }
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

  Future<void> requestFreshOffer(String roomCode, int reqTimestamp) async {
    final codes = _possibleCodes(roomCode);
    final payload = jsonEncode({'request': 'offer', 'timestamp': reqTimestamp});
    for (final c in codes) {
      try {
        final uri = Uri.parse('https://ntfy.sh');
        final request = await _client.postUrl(uri);
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode({
          'topic': 'kg_signal_${c}_req',
          'message': payload,
        }));
        await request.close().timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
  }

  Future<int?> getLatestRequestTimestamp(String roomCode) async {
    final codes = _possibleCodes(roomCode);
    for (final c in codes) {
      try {
        final uri = Uri.parse('https://ntfy.sh/kg_signal_${c}_req/json?poll=1');
        final request = await _client.getUrl(uri);
        final response = await request.close().timeout(const Duration(seconds: 2));
        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 2));
          final lines = body.trim().split('\n');
          for (final line in lines.reversed) {
            if (line.trim().isEmpty) continue;
            try {
              final json = jsonDecode(line);
              if (json is Map && json['message'] != null) {
                final payload = jsonDecode(json['message']);
                if (payload is Map && payload['timestamp'] != null) {
                  return payload['timestamp'] as int;
                }
              }
            } catch (_) {}
          }
        }
      } catch (_) {}
    }
    return null;
  }

  Future<void> sendDisconnect(String roomCode) async {
    final codes = _possibleCodes(roomCode);
    final payload = jsonEncode({'event': 'disconnect', 'timestamp': DateTime.now().millisecondsSinceEpoch});
    for (final c in codes) {
      try {
        final uri = Uri.parse('https://ntfy.sh');
        final request = await _client.postUrl(uri);
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode({
          'topic': 'kg_signal_${c}_disconnect',
          'message': payload,
        }));
        await request.close().timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
  }

  Future<int?> getLatestDisconnectTimestamp(String roomCode) async {
    final codes = _possibleCodes(roomCode);
    for (final c in codes) {
      try {
        final uri = Uri.parse('https://ntfy.sh/kg_signal_${c}_disconnect/json?poll=1');
        final request = await _client.getUrl(uri);
        final response = await request.close().timeout(const Duration(seconds: 2));
        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 2));
          final lines = body.trim().split('\n');
          for (final line in lines.reversed) {
            if (line.trim().isEmpty) continue;
            try {
              final json = jsonDecode(line);
              if (json is Map && json['message'] != null) {
                final payload = jsonDecode(json['message']);
                if (payload is Map && payload['timestamp'] != null) {
                  return payload['timestamp'] as int;
                }
              }
            } catch (_) {}
          }
        }
      } catch (_) {}
    }
    return null;
  }

  Future<bool> sendAnswer(String roomCode, String sdp, String type) async {
    final codes = _possibleCodes(roomCode);
    bool ok = false;
    final payloadMap = {'sdp': sdp, 'type': type, 'timestamp': DateTime.now().millisecondsSinceEpoch};
    final payload = jsonEncode(payloadMap);

    for (final c in codes) {
      // 1. Send to Cloud Run server
      try {
        final uri = Uri.parse('$baseUrl/api/signal/room/$c/answer');
        final request = await _client.postUrl(uri);
        request.headers.contentType = ContentType.json;
        request.write(payload);
        final response = await request.close().timeout(const Duration(seconds: 2));
        if (response.statusCode == 200) ok = true;
      } catch (_) {}

      // 2. Publish to ntfy
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

  Future<Map<String, dynamic>?> getAnswer(String roomCode, {int minTimestamp = 0}) async {
    final codes = _possibleCodes(roomCode);
    for (final c in codes) {
      // 1. Try Cloud Run server first
      try {
        final uri = Uri.parse('$baseUrl/api/signal/room/$c/answer?since=$minTimestamp');
        final request = await _client.getUrl(uri);
        final response = await request.close().timeout(const Duration(seconds: 2));
        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join();
          final json = jsonDecode(body);
          if (json is Map && json['sdp'] != null) {
            final ts = json['timestamp'] as int? ?? 0;
            if (ts >= minTimestamp) {
              return Map<String, dynamic>.from(json);
            }
          }
        }
      } catch (_) {}

      // 2. Fallback to ntfy.sh
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
                  final ts = payload['timestamp'] as int? ?? 0;
                  if (ts >= minTimestamp) {
                    return Map<String, dynamic>.from(payload);
                  }
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

  Future<void> resetRoom(String roomCode) async {
    final codes = _possibleCodes(roomCode);
    for (final c in codes) {
      try {
        final uri = Uri.parse('$baseUrl/api/signal/room/$c/reset');
        final request = await _client.postUrl(uri);
        await request.close().timeout(const Duration(seconds: 2));
      } catch (_) {}
      try {
        final uri = Uri.parse('$baseUrl/api/signal/room/$c/stop');
        final request = await _client.postUrl(uri);
        await request.close().timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
  }

  Future<bool> sendCandidate(
    String roomCode,
    String candidate,
    String? sdpMid,
    int? sdpMLineIndex,
    String sender,
  ) async {
    final codes = _possibleCodes(roomCode);
    final payloadMap = {
      'candidate': candidate,
      'sdpMid': sdpMid,
      'sdpMLineIndex': sdpMLineIndex,
      'sender': sender,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    final payload = jsonEncode(payloadMap);

    for (final c in codes) {
      // 1. Send to server
      try {
        final uri = Uri.parse('$baseUrl/api/signal/room/$c/candidate');
        final request = await _client.postUrl(uri);
        request.headers.contentType = ContentType.json;
        request.write(payload);
        await request.close().timeout(const Duration(seconds: 2));
      } catch (_) {}

      // 2. Publish to ntfy
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
      // 1. Try server first
      try {
        final uri = Uri.parse('$baseUrl/api/signal/room/$c/candidates?for=$forRole&since=$sinceTimestamp');
        final request = await _client.getUrl(uri);
        final response = await request.close().timeout(const Duration(seconds: 2));
        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join();
          final json = jsonDecode(body);
          if (json is Map && json['candidates'] is List) {
            for (final cand in json['candidates']) {
              if (cand is Map && cand['candidate'] != null) {
                results.add(Map<String, dynamic>.from(cand));
              }
            }
          }
        }
      } catch (_) {}

      if (results.isNotEmpty) return results;

      // 2. Fallback to ntfy
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

  Future<bool> sendAction(String roomCode, Map<String, dynamic> actionData) async {
    final codes = _possibleCodes(roomCode);
    final payload = jsonEncode({
      ...actionData,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    bool ok = false;
    for (final c in codes) {
      try {
        final uri = Uri.parse('https://ntfy.sh');
        final request = await _client.postUrl(uri);
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode({
          'topic': 'kg_signal_${c}_action',
          'message': payload,
        }));
        await request.close().timeout(const Duration(seconds: 2));
        ok = true;
      } catch (_) {}

      try {
        final uri = Uri.parse('$baseUrl/api/signal/room/$c/action');
        final request = await _client.postUrl(uri);
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode({
          'action': actionData['type'] ?? 'REMOTE_ACTION',
          'payload': actionData,
        }));
        await request.close().timeout(const Duration(seconds: 2));
        ok = true;
      } catch (_) {}
    }
    return ok;
  }

  Future<List<Map<String, dynamic>>> getActions(String roomCode, int sinceTimestamp) async {
    final List<Map<String, dynamic>> actions = [];
    final codes = _possibleCodes(roomCode);
    for (final c in codes) {
      // 1. Try local server endpoint first if reachable
      try {
        final uri = Uri.parse('$baseUrl/api/signal/room/$c/actions?since=$sinceTimestamp');
        final request = await _client.getUrl(uri);
        final response = await request.close().timeout(const Duration(seconds: 2));
        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join();
          final json = jsonDecode(body);
          if (json is Map && json['actions'] is List) {
            for (final a in json['actions']) {
              if (a is Map && a['payload'] is Map) {
                actions.add(Map<String, dynamic>.from(a['payload']));
              }
            }
          }
        }
      } catch (_) {}

      if (actions.isNotEmpty) return actions;

      // 2. Poll ntfy action topic
      try {
        final uri = Uri.parse('https://ntfy.sh/kg_signal_${c}_action/json?poll=1');
        final request = await _client.getUrl(uri);
        final response = await request.close().timeout(const Duration(seconds: 2));
        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 2));
          final lines = body.trim().split('\n');
          for (final line in lines) {
            if (line.trim().isEmpty) continue;
            try {
              final json = jsonDecode(line);
              if (json is Map && json['message'] != null) {
                final payload = jsonDecode(json['message']);
                if (payload is Map) {
                  final ts = payload['timestamp'] as int? ?? 0;
                  if (ts > sinceTimestamp) {
                    actions.add(Map<String, dynamic>.from(payload));
                  }
                }
              }
            } catch (_) {}
          }
        }
      } catch (_) {}

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
    required Future<Map<String, dynamic>> Function() onRequestFreshOffer,
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
            String sdp;
            String type;
            if (isRefresh) {
              final freshData = await onRequestFreshOffer();
              sdp = freshData['sdp'] ?? '';
              type = freshData['type'] ?? 'offer';
            } else {
              sdp = getOfferSdp();
              type = getOfferType();
            }
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode({
              'sdp': sdp,
              'type': type,
              'code': clean,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            }));
          } else if (path == '/request-offer') {
            final freshData = await onRequestFreshOffer();
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode({
              'sdp': freshData['sdp'] ?? '',
              'type': freshData['type'] ?? 'offer',
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
  Future<Map<String, dynamic>?> discoverOnLan(String roomCode, {bool requestFresh = false}) async {
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

                  if (requestFresh) {
                    requestFreshOfferFromLan().then((fresh) {
                      if (fresh != null && !completer.isCompleted) {
                        completer.complete(fresh);
                      }
                    });
                  } else if (json['sdp'] != null && !completer.isCompleted) {
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
    _probeSubnetForChild(clean, requestFresh: requestFresh).then((res) {
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

  Future<Map<String, dynamic>?> _probeSubnetForChild(String cleanCode, {bool requestFresh = false}) async {
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
            final path = requestFresh ? '/offer?refresh=1' : '/offer';
            final uri = Uri.parse('http://$targetIp:8998$path');
            final req = await client.getUrl(uri).timeout(const Duration(milliseconds: 300));
            final resp = await req.close().timeout(const Duration(milliseconds: 300));
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

  Future<Map<String, dynamic>?> requestFreshOfferFromLan() async {
    if (_lanPeerIp == null) return null;
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final uri = Uri.parse('http://$_lanPeerIp:$_lanPeerPort/offer?refresh=1');
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
            'lanIp': _lanPeerIp,
            'lanPort': _lanPeerPort,
          };
        }
      }
      client.close();
    } catch (_) {}
    return null;
  }

  Future<void> sendDisconnectToLan() async {
    if (_lanPeerIp == null) return;
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
      final uri = Uri.parse('http://$_lanPeerIp:$_lanPeerPort/disconnect');
      final req = await client.postUrl(uri);
      await req.close().timeout(const Duration(seconds: 1));
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

  Future<bool> sendActionToLan(Map<String, dynamic> actionData) async {
    if (_lanPeerIp == null) return false;
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
      final uri = Uri.parse('http://$_lanPeerIp:$_lanPeerPort/action');
      final req = await client.postUrl(uri);
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(actionData));
      final resp = await req.close().timeout(const Duration(seconds: 1));
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

  Timer? _answerPollTimer;
  Timer? _candidatePollTimer;
  Timer? _offerHeartbeatTimer;
  Timer? _reconnectListenTimer;
  int _lastCandidateTimestamp = 0;
  int _lastHandledReqTimestamp = 0;
  int _lastHandledDisconnectTimestamp = 0;
  bool _isRemoteDescSet = false;
  final List<RTCIceCandidate> _queuedCandidates = [];
  final List<Map<String, dynamic>> _collectedChildCandidates = [];
  String? _latestOfferSdp;
  String? _latestOfferType;
  int _offerTimestamp = 0;

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

  void _handleIncomingRemoteAction(String rawJson) {
    try {
      final map = jsonDecode(rawJson);
      if (map is! Map) return;
      final type = map['type'] as String? ?? map['action'] as String? ?? '';

      if (type == 'TOGGLE_AUDIO') {
        final enabled = map['enabled'] as bool? ?? true;
        setState(() {
          _isMicActive = enabled;
          _remoteActionFeedback = enabled ? '🎙️ माता-पिता ने ऑडियो चालू किया (माइक लाइव)' : '🔇 माता-पिता ने ऑडियो म्यूट किया';
        });
        _micAudioTrack?.enabled = enabled;
        _resetFeedbackTimer();
      } else if (type == 'REMOTE_TOUCH') {
        final x = (map['x'] as num?)?.toDouble() ?? 0.5;
        final y = (map['y'] as num?)?.toDouble() ?? 0.5;
        HapticFeedback.lightImpact();
        setState(() {
          _lastRemoteTouchPoint = Offset(x, y);
          _remoteActionFeedback = '👆 माता-पिता का रिमोट टच: ${(x * 100).toStringAsFixed(0)}%, ${(y * 100).toStringAsFixed(0)}%';
        });
        _resetFeedbackTimer();
      } else if (type == 'REMOTE_NAV') {
        final key = map['key'] as String? ?? map['action'] as String? ?? '';
        HapticFeedback.mediumImpact();
        setState(() {
          _remoteActionFeedback = '👆 रिमोट नेविगेशन: $key';
        });
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

  void _startPollingForActions(String roomCode) {
    _actionPollTimer?.cancel();
    _lastActionTimestamp = DateTime.now().millisecondsSinceEpoch;
    _actionPollTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) async {
      if (!_isSharing) return;
      final actions = await _signaling.getActions(roomCode, _lastActionTimestamp);
      for (final a in actions) {
        final ts = a['timestamp'] as int? ?? 0;
        if (ts > _lastActionTimestamp) {
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

  void _setupChildPeerConnectionListeners(String roomCode) {
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
            _statusMessage = 'माता-पिता डिस्कनेक्ट हो गए। पुनः जुड़ने की प्रतीक्षा...';
          });
        }
        // Auto-recycle peer connection with active screen stream so parent can reconnect immediately!
        _prepareFreshPeerConnection(roomCode);
      }
    };

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
  }

  // Generates a brand new PeerConnection from the EXISTING running screen stream
  // ZERO PERMISSION PROMPT REQUIRED! Screen continues streaming continuously!
  Future<Map<String, dynamic>> _prepareFreshPeerConnection(String roomCode) async {
    if (!_isSharing || _screenStream == null) {
      return {'sdp': _latestOfferSdp ?? '', 'type': _latestOfferType ?? 'offer'};
    }
    debugPrint("🔄 [Kid] Generating fresh WebRTC offer for Parent reconnection (screen stream kept alive)...");

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
    _lastCandidateTimestamp = DateTime.now().millisecondsSinceEpoch;

    try {
      _peerConnection = await createPeerConnection(_iceServers);
      _setupChildPeerConnectionListeners(roomCode);

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
      _offerTimestamp = DateTime.now().millisecondsSinceEpoch;

      _startPollingForAnswer(roomCode, _offerTimestamp);
      _signaling.sendOffer(roomCode, offer.sdp!, offer.type!);

      if (mounted) {
        setState(() {
          _isParentConnected = false;
          _statusMessage = '🔴 ब्रॉडकास्ट सक्रिय है! कोड: $roomCode\nमाता-पिता के जुड़ने की प्रतीक्षा...';
        });
      }

      return {'sdp': offer.sdp ?? '', 'type': offer.type ?? 'offer'};
    } catch (e) {
      debugPrint("Error preparing fresh peer connection: $e");
      return {'sdp': _latestOfferSdp ?? '', 'type': _latestOfferType ?? 'offer'};
    }
  }

  void _startListeningForReconnectRequests(String roomCode) {
    _reconnectListenTimer?.cancel();
    _reconnectListenTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) async {
      if (!_isSharing || _screenStream == null) return;

      // 1. Check parent connect request
      final reqTs = await _signaling.getLatestRequestTimestamp(roomCode);
      if (reqTs != null && reqTs > _lastHandledReqTimestamp) {
        _lastHandledReqTimestamp = reqTs;
        debugPrint("⚡ [Kid] Received fresh connection request from Parent ($reqTs)");
        await _prepareFreshPeerConnection(roomCode);
        return;
      }

      // 2. Check parent disconnect event
      final disTs = await _signaling.getLatestDisconnectTimestamp(roomCode);
      if (disTs != null && disTs > _lastHandledDisconnectTimestamp) {
        _lastHandledDisconnectTimestamp = disTs;
        debugPrint("⚡ [Kid] Received disconnect notification from Parent ($disTs)");
        await _prepareFreshPeerConnection(roomCode);
      }
    });
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

      // Reset stale session signaling
      _latestOfferSdp = null;
      _latestOfferType = null;
      _lastHandledReqTimestamp = 0;
      _lastHandledDisconnectTimestamp = 0;
      _isRemoteDescSet = false;
      _isParentConnected = false;
      await _signaling.resetRoom(roomCode);

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
      _setupChildPeerConnectionListeners(roomCode);

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
          debugPrint('Screen capture track ended (system notification stop)');
          if (mounted) {
            _stopScreenShare();
          }
        };
      });

      // Capture Microphone Audio for Parent Live Listening
      try {
        _micStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
        if (_micStream != null && _micStream!.getAudioTracks().isNotEmpty) {
          _micAudioTrack = _micStream!.getAudioTracks().first;
          _micAudioTrack!.enabled = _isMicActive;
          debugPrint('🎙️ [Kid] Mic capture initialized');
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
      _offerTimestamp = DateTime.now().millisecondsSinceEpoch;

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
        onRequestFreshOffer: () => _prepareFreshPeerConnection(roomCode),
        onParentDisconnected: () => _prepareFreshPeerConnection(roomCode),
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

      // 2. Poll for Parent's Answer on Cloud Relay (Strictly only accept fresh answer created for this offer!)
      _startPollingForAnswer(roomCode, _offerTimestamp);

      // 3. Listen for reconnection/offer requests from Parent
      _startListeningForReconnectRequests(roomCode);

      // 4. Send initial Offer asynchronously
      _signaling.sendOffer(roomCode, offer.sdp!, offer.type!).then((ok) {
        if (mounted && _isSharing) {
          setState(() {
            _statusMessage = '🔴 ब्रॉडकास्ट सक्रिय है! कोड: $roomCode\nमाता-पिता के जुड़ने की प्रतीक्षा...';
          });
        }
      });

      // 5. Offer Heartbeat: keep refreshing Offer so parent can connect anytime!
      _offerHeartbeatTimer?.cancel();
      _offerHeartbeatTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
        if (_isSharing && !_isParentConnected && _peerConnection != null && _latestOfferSdp != null) {
          _signaling.sendOffer(roomCode, _latestOfferSdp!, _latestOfferType ?? 'offer');
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

  // Listen / Poll for Parent's Answer (Strictly validates freshness with forOfferTimestamp)
  void _startPollingForAnswer(String roomCode, int forOfferTimestamp) {
    _answerPollTimer?.cancel();
    _answerPollTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!_isSharing || _isRemoteDescSet || _peerConnection == null) return;

      final answerData = await _signaling.getAnswer(roomCode, minTimestamp: forOfferTimestamp - 1000);
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
    _answerPollTimer = null;
    _candidatePollTimer?.cancel();
    _candidatePollTimer = null;
    _offerHeartbeatTimer?.cancel();
    _offerHeartbeatTimer = null;
    _reconnectListenTimer?.cancel();
    _reconnectListenTimer = null;
    _actionPollTimer?.cancel();
    _actionPollTimer = null;
    _actionFeedbackTimer?.cancel();
    _actionFeedbackTimer = null;
    _localLan.stop();
    _collectedChildCandidates.clear();

    final roomCode = _codeController.text.trim().toUpperCase();
    if (roomCode.isNotEmpty) {
      _signaling.sendDisconnect(roomCode);
      _signaling.resetRoom(roomCode);
    }

    _latestOfferSdp = null;
    _latestOfferType = null;
    _offerTimestamp = 0;
    _lastHandledReqTimestamp = 0;
    _lastHandledDisconnectTimestamp = 0;
    _lastCandidateTimestamp = 0;
    _isRemoteDescSet = false;
    _isParentConnected = false;

    try {
      await _platformChannel.invokeMethod('stopScreenCapture');
    } catch (_) {}
    _screenStream?.getTracks().forEach((track) => track.stop());
    _screenStream = null;
    _micAudioTrack?.stop();
    _micStream?.dispose();
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
        _statusMessage = 'स्क्रीन शेयरिंग बंद है।\n(नोटिफिकेशन या सिस्टम से बंद की गई - दोबारा कनेक्ट करने के लिए नीचे बटन दबाएं)';
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

    // 3. Cloud Relay (ntfy + server)
    _signaling.sendAction(roomCode, fullData);
  }

  void _toggleLiveAudio() {
    setState(() {
      _isLiveAudioOn = !_isLiveAudioOn;
    });

    if (_remoteAudioTrack != null) {
      _remoteAudioTrack!.enabled = _isLiveAudioOn;
    }

    _sendRemoteAction({
      'type': 'TOGGLE_AUDIO',
      'enabled': _isLiveAudioOn,
    });

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
      final reqTimestamp = DateTime.now().millisecondsSinceEpoch;
      _isLanConnection = false;

      // Request fresh offer via LAN and Cloud Relay
      _localLan.sendDisconnectToLan();
      _signaling.requestFreshOffer(roomCode, reqTimestamp);

      Map<String, dynamic>? offerData;

      for (int attempt = 1; attempt <= 40; attempt++) {
        if (!mounted || !_isConnecting) return;
        setState(() {
          _statusText = 'बच्चे के फोन से सिग्नल खोज रहे हैं... ($attempt/40)';
        });

        // Re-request fresh offer every 3 attempts to wake up backgrounded child
        if (attempt % 3 == 0) {
          _signaling.requestFreshOffer(roomCode, DateTime.now().millisecondsSinceEpoch);
        }

        // 1. Direct Wi-Fi LAN search (Instant <200ms when both phones are on same Wi-Fi)
        try {
          final lanOffer = await _localLan.discoverOnLan(roomCode, requestFresh: attempt == 1 || attempt % 3 == 0);
          if (lanOffer != null && lanOffer['sdp'] != null && (lanOffer['sdp'] as String).isNotEmpty) {
            offerData = lanOffer;
            _isLanConnection = true;
            debugPrint("🎯 [Parent] Discovered Child via Direct Wi-Fi LAN!");
            break;
          }
        } catch (_) {}

        // 2. Cloud Relay search (server.ts + ntfy.sh)
        // First 3 attempts: check for fresh offer generated around or after this connection attempt
        offerData = await _signaling.getOffer(roomCode, minTimestamp: reqTimestamp - 5000);
        if (offerData != null && offerData['sdp'] != null && (offerData['sdp'] as String).isNotEmpty) {
          debugPrint("🎯 [Parent] Discovered Child via Cloud Relay (Fresh Offer)!");
          break;
        }

        // From attempt 4+: Also accept running offer from past 60s if child is already broadcasting
        if (attempt >= 4) {
          offerData = await _signaling.getOffer(roomCode, minTimestamp: reqTimestamp - 60000);
          if (offerData != null && offerData['sdp'] != null && (offerData['sdp'] as String).isNotEmpty) {
            debugPrint("🎯 [Parent] Discovered Child via Cloud Relay (Active Running Offer)!");
            break;
          }
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
        } else if (event.track.kind == 'audio') {
          _remoteAudioTrack = event.track;
          _remoteAudioTrack!.enabled = _isLiveAudioOn;
          debugPrint("🎙️ [Parent] Audio track registered: enabled=$_isLiveAudioOn");
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

      RTCSessionDescription answer = await _peerConnection!.createAnswer({
        'offerToReceiveVideo': 1,
        'offerToReceiveAudio': 1,
      });
      await _peerConnection!.setLocalDescription(answer);

      // Send Answer to both LAN (if connected) and Cloud Relay
      if (_isLanConnection) {
        _localLan.sendAnswerToLan(answer.sdp!, answer.type!);
      }
      await _signaling.sendAnswer(roomCode, answer.sdp!, answer.type!);

      _lastCandidateTimestamp = reqTimestamp - 1000;
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
    final roomCode = _codeController.text.trim().toUpperCase();
    _candidatePollTimer?.cancel();
    _touchFeedbackTimer?.cancel();
    _localLan.sendDisconnectToLan();
    _localLan.stop();
    if (roomCode.isNotEmpty) {
      _signaling.sendDisconnect(roomCode);
    }
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
    _lastCandidateTimestamp = DateTime.now().millisecondsSinceEpoch;
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
