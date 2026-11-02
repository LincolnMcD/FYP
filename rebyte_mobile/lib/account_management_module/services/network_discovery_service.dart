import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NetworkDiscoveryService {
  static const int discoveryPort = 38888;
  static const String _prefKeyDiscoveredUrl = 'rebyte_discovered_backend_url';
  
  // Safe default fallback
  static String fallbackUrl = 'http://10.108.7.21:3000';

  static String? _cachedUrl;

  /// Returns the current known URL synchronously
  static String get currentUrl => _cachedUrl ?? fallbackUrl;

  /// Discovers the backend on the current local network dynamically
  static Future<String> discoverBackendUrl({Duration timeout = const Duration(seconds: 2)}) async {
    // 1. On Android Emulator, 10.0.2.2 always points directly to the host machine
    if (!kIsWeb && Platform.isAndroid) {
      // Check if running on Android emulator
      // For physical device, UDP broadcast discovers the exact computer IP!
    }

    // 2. Load last verified URL from persistent storage
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKeyDiscoveredUrl);
      if (saved != null && saved.isNotEmpty) {
        _cachedUrl = saved;
      }
    } catch (_) {}

    // 3. UDP Broadcast to discover active backend on current Wi-Fi
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      final completer = Completer<String>();

      socket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket?.receive();
          if (datagram != null) {
            try {
              final responseStr = utf8.decode(datagram.data);
              final map = jsonDecode(responseStr);
              if (map['app'] == 'ReByte' && map['url'] != null) {
                final discovered = map['url'] as String;
                _cachedUrl = discovered;
                SharedPreferences.getInstance().then((p) {
                  p.setString(_prefKeyDiscoveredUrl, discovered);
                });
                if (!completer.isCompleted) {
                  completer.complete(discovered);
                }
              }
            } catch (_) {}
          }
        }
      });

      // Broadcast discovery ping packet to local subnet
      final pingData = utf8.encode('REBYTE_DISCOVERY_PING');
      socket.send(pingData, InternetAddress('255.255.255.255'), discoveryPort);

      // Timeout fallback
      final result = await completer.future.timeout(timeout, onTimeout: () {
        return _cachedUrl ?? fallbackUrl;
      });

      return result;
    } catch (e) {
      debugPrint('[Discovery] UDP discovery skipped: $e');
      return _cachedUrl ?? fallbackUrl;
    } finally {
      socket?.close();
    }
  }
}

