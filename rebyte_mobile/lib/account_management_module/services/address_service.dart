import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import '../models/address_model.dart';
import 'auth_service.dart';

class AddressService {
  /// Fetch all active addresses for the user from Firebase Address collection via backend API
  static Future<List<AddressModel>> getAddresses(String email) async {
    try {
      final res = await http.get(
        Uri.parse('${AuthService.baseUrl}/api/address?email=$email'),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['addresses'] is List) {
          return (data['addresses'] as List)
              .map((item) => AddressModel.fromJson(item as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (e) {
      // Backend error or offline
    }
    return [];
  }

  /// Create a new address in Firebase Address collection
  static Future<Map<String, dynamic>> addAddress(String email, AddressModel address) async {
    try {
      final res = await http.post(
        Uri.parse('${AuthService.baseUrl}/api/address'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'addressLine': address.addressLine,
          'postcode': address.postcode,
          'city': address.city,
          'state': address.state,
          'recipentName': address.recipientName,
          'phoneNumber': address.phoneNumber,
          'addressType': address.addressType,
          'isDefault': address.isDefault,
          'lat': address.latitude,
          'lng': address.longitude,
        }),
      ).timeout(const Duration(seconds: 8));

      final data = jsonDecode(res.body);
      if (res.statusCode == 201 || res.statusCode == 200) {
        return {'success': true, 'data': data['address']};
      }
      return {'success': false, 'error': data['error'] ?? 'Failed to save address'};
    } catch (e) {
      return {'success': false, 'error': 'Connection failed. Please try again.'};
    }
  }

  /// Update an existing address in Firebase Address collection
  static Future<Map<String, dynamic>> updateAddress(String email, AddressModel address) async {
    try {
      final res = await http.put(
        Uri.parse('${AuthService.baseUrl}/api/address/${address.addressID}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'addressLine': address.addressLine,
          'postcode': address.postcode,
          'city': address.city,
          'state': address.state,
          'recipentName': address.recipientName,
          'phoneNumber': address.phoneNumber,
          'addressType': address.addressType,
          'isDefault': address.isDefault,
          'lat': address.latitude,
          'lng': address.longitude,
        }),
      ).timeout(const Duration(seconds: 8));

      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        return {'success': true, 'data': data['address']};
      }
      return {'success': false, 'error': data['error'] ?? 'Failed to update address'};
    } catch (e) {
      return {'success': false, 'error': 'Connection failed. Please try again.'};
    }
  }

  /// Set an address as default in Firebase Address collection
  static Future<bool> setDefaultAddress(String email, String addressId) async {
    try {
      final res = await http.post(
        Uri.parse('${AuthService.baseUrl}/api/address/$addressId/default'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['success'] == true;
      }
    } catch (_) {}
    return false;
  }

  /// Soft delete an address record (status: 'delete')
  static Future<bool> deleteAddress(String email, String addressId) async {
    try {
      final res = await http.delete(
        Uri.parse('${AuthService.baseUrl}/api/address/$addressId?email=$email'),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['success'] == true;
      }
    } catch (_) {}
    return false;
  }

  /// Search coordinates for an inputted address query via /api/address/search with progressive fallbacks
  static Future<Map<String, dynamic>?> searchAddress(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return null;

    // Helper to query backend Nominatim proxy
    Future<Map<String, dynamic>?> fetchSearch(String q) async {
      try {
        final encoded = Uri.encodeComponent(q);
        final res = await http.get(
          Uri.parse('${AuthService.baseUrl}/api/address/search?q=$encoded'),
        ).timeout(const Duration(seconds: 8));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data['success'] == true && data['results'] is List && (data['results'] as List).isNotEmpty) {
            final first = (data['results'] as List).first as Map<String, dynamic>;
            final lat = (first['lat'] as num?)?.toDouble();
            final lng = (first['lng'] as num?)?.toDouble();
            if (lat != null && lng != null) {
              return {
                'lat': lat,
                'lng': lng,
                'displayName': first['displayName'] ?? '',
                'address': first['address'] ?? {},
              };
            }
          }
        }
      } catch (_) {}
      return null;
    }

    // 1. Try full exact query
    final exact = await fetchSearch(cleanQuery);
    if (exact != null) return exact;

    // 2. Try stripping common unit/level/block prefixes (e.g. "Unit 15-02, Block A, No. 12")
    final stripped = cleanQuery
        .replaceAll(RegExp(r'(?:unit|block|lot|level|tingkat|floor|apt|apartment|no\.?)\s*[\w\-\/]+[\s,]*', caseSensitive: false), '')
        .replaceAll(RegExp(r'^[,\s]+|[,\s]+$'), '')
        .trim();
    if (stripped.isNotEmpty && stripped != cleanQuery) {
      final strippedResult = await fetchSearch(stripped);
      if (strippedResult != null) return strippedResult;
    }

    // 3. Try splitting comma parts and searching progressively broader (e.g. street + city + state)
    final commaParts = cleanQuery.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    if (commaParts.length > 2) {
      for (int i = 1; i < commaParts.length; i++) {
        final subQuery = commaParts.sublist(i).join(', ');
        if (subQuery.length >= 5) {
          final subResult = await fetchSearch(subQuery);
          if (subResult != null) return subResult;
        }
      }
    }

    return null;
  }

  /// Reverse geocode coordinates to fill address, postcode, city, and state
  static Future<Map<String, dynamic>> reverseGeocode(double lat, double lng) async {
    try {
      final res = await http.get(
        Uri.parse('${AuthService.baseUrl}/api/address/reverse-geocode?lat=$lat&lng=$lng'),
      ).timeout(const Duration(seconds: 12));

      final data = jsonDecode(res.body);
      return data;
    } catch (e) {
      return {
        'success': false,
        'error': 'Network timeout contacting map geocoding service.',
      };
    }
  }

  /// Get accurate device GPS coordinates natively via Flutter Geolocator
  static Future<Map<String, dynamic>> getDeviceGpsCoordinates() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return {'success': false, 'error': 'Location services disabled'};
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return {'success': false, 'error': 'Location permissions denied'};
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return {'success': false, 'error': 'Location permissions permanently denied'};
      }

      // First check last known position for near-instant retrieval
      Position? lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        return {
          'success': true,
          'lat': lastKnown.latitude,
          'lng': lastKnown.longitude,
          'source': 'flutter_gps_last_known',
        };
      }

      // Query current high-accuracy GPS position directly from the hardware
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 6),
        ),
      );

      return {
        'success': true,
        'lat': position.latitude,
        'lng': position.longitude,
        'source': 'flutter_gps',
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Get best available location: attempts native Flutter GPS first, falls back to network IP
  static Future<Map<String, dynamic>> getCurrentLocation() async {
    // 1. Primary: Obtain GPS coordinates directly from Flutter
    try {
      final gpsRes = await getDeviceGpsCoordinates();
      if (gpsRes['success'] == true && gpsRes['lat'] != null && gpsRes['lng'] != null) {
        return {
          'success': true,
          'lat': (gpsRes['lat'] as num).toDouble(),
          'lng': (gpsRes['lng'] as num).toDouble(),
          'source': gpsRes['source'] ?? 'flutter_gps',
          'isMalaysia': true,
        };
      }
    } catch (_) {}

    // 2. Secondary fallback: Query network IP-based location from backend
    try {
      final res = await http.get(
        Uri.parse('${AuthService.baseUrl}/api/address/current-location'),
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['lat'] != null && data['lng'] != null) {
          return data;
        }
      }
    } catch (_) {}

    // 3. Ultimate fallback: Kuala Lumpur default
    return {
      'success': true,
      'lat': 3.1390,
      'lng': 101.6869,
      'isMalaysia': true,
      'fallback': true,
    };
  }
}
