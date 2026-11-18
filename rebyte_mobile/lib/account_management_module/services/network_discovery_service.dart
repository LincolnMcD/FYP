import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NetworkDiscoveryService {
  static const int discoveryPort = 38888;
  static const String _prefKeyDiscoveredUrl = 'rebyte_discovered_backend_url';
  static String fallbackUrl = 'http://10.108.7.21:3000';
  static String? _cachedUrl;
  static Future<String>? _pendingDiscovery;

  static String get currentUrl => _cachedUrl ?? fallbackUrl;

  /// Coalesce startup/retry callers so they cannot race to save different hosts.
  static Future<String> discoverBackendUrl({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    if (_pendingDiscovery != null) return _pendingDiscovery!;
    final pending = _discover(timeout);
    _pendingDiscovery = pending;
    try {
      return await pending;
    } finally {
      _pendingDiscovery = null;
    }
  }

  static bool _isPrivateAddress(String address) {
    final octets = address.split('.').map(int.tryParse).toList();
    if (octets.length != 4 ||
        octets.any((n) => n == null || n < 0 || n > 255)) {
      return false;
    }
    return octets[0] == 10 ||
        (octets[0] == 172 && octets[1]! >= 16 && octets[1]! <= 31) ||
        (octets[0] == 192 && octets[1] == 168);
  }

  /// Android exposes tethering interfaces separately from its mobile-data route.
  /// Only probe private LAN interfaces, never cellular, VPN, or public subnets.
  static Future<Set<String>> _localAddresses() async {
    final addresses = <String>{};
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        if (RegExp(
          r'^(rmnet|ccmni|pdp|wwan|tun|tap|utun|dummy)',
          caseSensitive: false,
        ).hasMatch(interface.name)) {
          continue;
        }
        for (final address in interface.addresses) {
          if (_isPrivateAddress(address.address)) {
            addresses.add(address.address);
          }
        }
      }
    } catch (error) {
      debugPrint('[Discovery] Could not enumerate LAN interfaces: $error');
    }
    return addresses;
  }

  static Future<String> _discover(Duration timeout) async {
    if (kIsWeb) return currentUrl;
    final client = HttpClient()
      ..findProxy = ((_) => 'DIRECT')
      ..connectionTimeout = const Duration(milliseconds: 450);
    RawDatagramSocket? socket;
    Timer? repeatPing;
    var active = true;
    final found = Completer<String>();
    final checks = <String, Future<bool>>{};
    final localAddresses = await _localAddresses();
    final subnets = localAddresses
        .map((ip) => ip.substring(0, ip.lastIndexOf('.')))
        .toSet()
        .take(2)
        .toList();

    Future<bool> verify(String url) async {
      try {
        final uri = Uri.parse(url);
        if (uri.scheme != 'http' || !_isPrivateAddress(uri.host)) return false;
        final request = await client
            .getUrl(uri.resolve('/api/health/rebyte'))
            .timeout(const Duration(milliseconds: 650));
        request.followRedirects = false;
        final response = await request.close().timeout(
          const Duration(milliseconds: 650),
        );
        if (response.statusCode != HttpStatus.ok) {
          await response.drain<void>();
          return false;
        }
        final body = await response
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(milliseconds: 650));
        final data = jsonDecode(body);
        return data is Map &&
            data['app'] == 'ReByte' &&
            data['service'] == 'backend';
      } catch (_) {
        return false;
      }
    }

    Future<void> consider(String url) async {
      if (!active || found.isCompleted) return;
      final valid = await checks.putIfAbsent(url, () => verify(url));
      if (active && valid && !found.isCompleted) found.complete(url);
    }

    Future<void> scanHttp() async {
      final candidates = <String>[];
      for (final subnet in subnets) {
        for (var host = 1; host < 255; host++) {
          final ip = '$subnet.$host';
          if (!localAddresses.contains(ip)) candidates.add('http://$ip:3000');
        }
      }
      var next = 0;
      // Bounded concurrency; no scan outside the phone's private local /24s.
      Future<void> worker() async {
        while (active && !found.isCompleted && next < candidates.length) {
          await consider(candidates[next++]);
        }
      }

      await Future.wait(List.generate(32, (_) => worker()));
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKeyDiscoveredUrl);
      _cachedUrl = null;
      // A saved address is a candidate, not a trusted result on a new network.
      if (saved != null && saved.isNotEmpty) unawaited(consider(saved));
      unawaited(consider(fallbackUrl));
      try {
        socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        socket.broadcastEnabled = true;
        socket.listen(
          (event) {
            if (!active || event != RawSocketEvent.read) return;
            Datagram? datagram;
            while ((datagram = socket?.receive()) != null) {
              try {
                final data = jsonDecode(utf8.decode(datagram!.data));
                if (data is! Map || data['app'] != 'ReByte') continue;
                final port = int.tryParse('${data['port']}');
                if (port == null || port < 1 || port > 65535) continue;
                // Use the reply's source IP, not an advertised IP from another adapter.
                unawaited(consider('http://${datagram.address.address}:$port'));
              } catch (_) {}
            }
          },
          onError: (Object error) {
            debugPrint('[Discovery] UDP receive failed: $error');
          },
        );
        final ping = utf8.encode('REBYTE_DISCOVERY_PING');
        void sendPings() {
          if (!active || found.isCompleted) return;
          final targets = <String>{'255.255.255.255'};
          for (final subnet in subnets) {
            targets.add('$subnet.255');
            // Hotspot hosts may send global broadcasts over mobile data instead
            // of tethering. Direct LAN packets still reach the backend computer.
            for (var host = 1; host < 255; host++) {
              final ip = '$subnet.$host';
              if (!localAddresses.contains(ip)) targets.add(ip);
            }
          }
          for (final target in targets) {
            try {
              socket?.send(ping, InternetAddress(target), discoveryPort);
            } catch (_) {}
          }
        }

        sendPings();
        repeatPing = Timer(const Duration(milliseconds: 600), sendPings);
      } catch (error) {
        debugPrint('[Discovery] UDP unavailable, trying direct HTTP: $error');
      }
      // Allow normal discovery first. TCP probing also works when UDP is blocked.
      var result = await found.future.timeout(timeout, onTimeout: () => '');
      if (result.isEmpty) {
        unawaited(scanHttp());
        result = await found.future.timeout(
          const Duration(seconds: 6),
          onTimeout: () => '',
        );
      }
      if (result.isNotEmpty) {
        _cachedUrl = result;
        await prefs.setString(_prefKeyDiscoveredUrl, result);
        debugPrint('[Discovery] Verified backend: $result');
        return result;
      }
      await prefs.remove(_prefKeyDiscoveredUrl);
      debugPrint(
        '[Discovery] No verified backend reachable. Offline fallback: $fallbackUrl',
      );
      // Keep the app usable offline; never persist this unverified fallback.
      return fallbackUrl;
    } catch (error) {
      debugPrint('[Discovery] Discovery failed: $error');
      return fallbackUrl;
    } finally {
      active = false;
      repeatPing?.cancel();
      socket?.close();
      client.close(force: true);
    }
  }
}
