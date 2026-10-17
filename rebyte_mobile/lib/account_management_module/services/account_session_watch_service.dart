import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Shares one backend Firestore snapshot stream per signed-in app instance.
class AccountSessionWatchService {
  static String? _uid;
  static http.Client? _client;
  static StreamSubscription<User?>? _authSubscription;
  static bool _running = false;
  static bool _suspendedForPublicFlow = false;
  static void Function(Map<String, dynamic>)? _onState;
  static int _generation = 0;
  static String? _baseUrl;

  static bool get isSuspendedForPublicFlow => _suspendedForPublicFlow;

  static void start({required String baseUrl, required void Function(Map<String, dynamic>) onState}) {
    if (_suspendedForPublicFlow) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      onState({'expired': true, 'error': 'Session expired. Please log in again.'});
      return;
    }
    if (_running && _uid == user.uid) {
      _onState = onState;
      _baseUrl = baseUrl;
      return;
    }
    stop();
    _onState = onState;
    _baseUrl = baseUrl;
    _uid = user.uid;
    _running = true;
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((authUser) {
      if (_running && (authUser == null || authUser.uid != _uid)) {
        _onState?.call({'expired': true, 'error': 'Session expired. Please log in again.'});
      }
    });
    final generation = _generation;
    unawaited(_connectLoop(user.uid, generation));
  }

  static Future<void> _connectLoop(String uid, int generation) async {
    var failures = 0;
    while (_running && _uid == uid && _generation == generation) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.uid != uid) break;
      final client = http.Client();
      _client = client;
      try {
        final token = await user.getIdToken();
        final request = http.Request('GET', Uri.parse('${_baseUrl!}/account-session/stream'));
        request.headers['Authorization'] = 'Bearer $token';
        final response = await client.send(request).timeout(const Duration(seconds: 15));
        if (response.statusCode == 401) {
          final body = await response.stream.bytesToString();
          final decoded = jsonDecode(body);
          if (decoded is Map<String, dynamic>) _onState?.call(decoded);
          break;
        }
        if (response.statusCode != 200) throw StateError('Session stream returned ${response.statusCode}');
        failures = 0;
        var eventData = <String>[];
        await for (final line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
          if (!_running || _uid != uid || _generation != generation) break;
          if (line.isEmpty) {
            if (eventData.isNotEmpty) {
              try {
                final decoded = jsonDecode(eventData.join('\n'));
                if (decoded is Map<String, dynamic>) _onState?.call(decoded);
              } catch (error) {
                debugPrint('Account session stream event parse failed: $error');
              }
              eventData = <String>[];
            }
          } else if (line.startsWith('data:')) {
            eventData.add(line.substring(5).trimLeft());
          }
        }
      } catch (error) {
        if (_running && _uid == uid && _generation == generation) debugPrint('Account session stream disconnected: $error');
      } finally {
        client.close();
        if (identical(_client, client)) _client = null;
      }
      if (!_running || _uid != uid || _generation != generation) break;
      failures = (failures + 1).clamp(1, 6).toInt();
      final seconds = (2 * (1 << (failures - 1))).clamp(2, 120).toInt();
      await Future<void>.delayed(Duration(seconds: seconds));
    }
    if (_uid == uid && _generation == generation) {
      _running = false;
      _uid = null;
    }
  }

  static void stop() {
    _generation++;
    _running = false;
    _uid = null;
    _onState = null;
    _authSubscription?.cancel();
    _authSubscription = null;
    _client?.close();
    _client = null;
  }

  /// A public account recovery flow must not be interrupted by a stale signed-in
  /// page underneath it. Monitoring resumes when that page becomes visible again.
  static void suspendForPublicFlow() {
    _suspendedForPublicFlow = true;
    stop();
  }

  static void resumeAfterPublicFlow() {
    _suspendedForPublicFlow = false;
  }

  static void restart({required String baseUrl, required void Function(Map<String, dynamic>) onState}) {
    stop();
    start(baseUrl: baseUrl, onState: onState);
  }

  static void restartCurrent() {
    final callback = _onState;
    final baseUrl = _baseUrl;
    if (callback != null && baseUrl != null) restart(baseUrl: baseUrl, onState: callback);
  }
}
