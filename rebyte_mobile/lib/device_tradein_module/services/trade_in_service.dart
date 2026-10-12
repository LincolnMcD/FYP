import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../account_management_module/services/auth_service.dart';
import '../data/phone_brands_data.dart';

class TradeInService {
  static String get baseUrl => '${AuthService.baseUrl}/api/tradein';

  // Cache to avoid refetching large library lists repeatedly
  static List<String>? _cachedBrands;
  static final Map<String, List<String>> _cachedModels = {};

  /// Fetch all brands from backend (powered by android-device-list + Apple DB)
  static Future<List<String>> getBrands({bool forceRefresh = false}) async {
    // If cache contains the old 2627 uncurated list, discard it immediately
    if (_cachedBrands != null && _cachedBrands!.length > 30) {
      _cachedBrands = null;
    }

    if (!forceRefresh && _cachedBrands != null && _cachedBrands!.isNotEmpty) {
      return _cachedBrands!;
    }

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/brands'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['brands'] is List) {
          final List<String> brands = List<String>.from(data['brands']);
          _cachedBrands = brands;
          return brands;
        }
      }
    } catch (e) {
      // Log or handle network error
    }

    return _cachedBrands ?? PhoneBrandsData.wellKnownPhoneBrands;
  }

  /// Fetch all models for a specific brand from backend (android-device-list library)
  static Future<List<String>> getModelsForBrand(String brand, {bool forceRefresh = false}) async {
    final cacheKey = brand.trim().toLowerCase();
    if (!forceRefresh && _cachedModels.containsKey(cacheKey)) {
      return _cachedModels[cacheKey]!;
    }

    try {
      final uri = Uri.parse('$baseUrl/models').replace(queryParameters: {'brand': brand});
      final response = await http.get(
        uri,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['models'] is List) {
          final List<String> models = List<String>.from(data['models']);
          _cachedModels[cacheKey] = models;
          return models;
        }
      }
    } catch (e) {
      // Log error
    }

    return _cachedModels[cacheKey] ?? ['Other $brand Model'];
  }

  /// Create a new device record with status pending
  static Future<Map<String, dynamic>> createDeviceRecord({
    required String brand,
    required String model,
    required String storageCapacity,
    required String colour,
    required String deviceAge,
    String? imeiNum,
    String deviceCategory = 'smartphone',
    String? userEmail,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/device'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'deviceCategory': deviceCategory,
          'brand': brand,
          'model': model,
          'storageCapacity': storageCapacity,
          'colour': colour,
          'imeiNum': imeiNum,
          'status': 'pending',
          'deviceAge': deviceAge,
          'userEmail': userEmail,
        }),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      return data;
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Check record for device by deviceID
  static Future<Map<String, dynamic>> checkDeviceRecord(String deviceID) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/device/$deviceID'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }
}
