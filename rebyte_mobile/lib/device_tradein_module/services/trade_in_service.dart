import 'dart:convert';
import 'dart:io';
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
          if (data['modelCodes'] is Map) {
            final Map<String, dynamic> rawMap = Map<String, dynamic>.from(data['modelCodes']);
            final Map<String, String> strMap = {};
            rawMap.forEach((k, v) {
              if (v != null) strMap[k] = v.toString();
            });
            _cachedModelCodes[cacheKey] = strMap;
          }
          return models;
        }
      }
    } catch (e) {
      // Log error
    }

    return _cachedModels[cacheKey] ?? ['Other $brand Model'];
  }

  static final Map<String, Map<String, String>> _cachedModelCodes = {};

  /// Get resolved model code (or comma-separated codes) for brand and model
  static String? getModelCode(String brand, String model) {
    final bKey = brand.trim().toLowerCase();
    return _cachedModelCodes[bKey]?[model];
  }

  /// Fetch a single device record by deviceID from backend
  static Future<Map<String, dynamic>?> getDeviceById(String deviceId) async {
    try {
      final cleanId = deviceId.trim();
      final response = await http.get(
        Uri.parse('$baseUrl/device/$cleanId'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['device'] is Map) {
          return Map<String, dynamic>.from(data['device']);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Create a new device record with status pending
  static Future<Map<String, dynamic>> createDeviceRecord({
    required String brand,
    required String model,
    String? modelCode,
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
          'modelCode': modelCode,
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

  /// Submit or update trade in request with images (uploads to Cloudinary & creates/updates Device, TradeInRequest, TradeInRequestImage)
  static Future<Map<String, dynamic>> submitTradeInRequestWithImages({
    String? tradeInRequestID,
    required String deviceID,
    required String brand,
    required String model,
    String? modelCode,
    required String storageCapacity,
    required String colour,
    required String deviceAge,
    String? imeiNum,
    String deviceCategory = 'smartphone',
    String? userEmail,
    required Map<String, String> imageFilePaths, // key: imageView (e.g. front), value: local file path
    List<String>? removedImageViews, // list of imageViews to delete from cloud if user removed them
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/submit-request');
      final request = http.MultipartRequest('POST', uri);

      // Add text fields
      if (tradeInRequestID != null && tradeInRequestID.isNotEmpty) {
        request.fields['tradeInRequestID'] = tradeInRequestID;
      }
      request.fields['deviceID'] = deviceID;
      request.fields['brand'] = brand;
      request.fields['model'] = model;
      if (modelCode != null) request.fields['modelCode'] = modelCode;
      request.fields['storageCapacity'] = storageCapacity;
      request.fields['colour'] = colour;
      request.fields['deviceAge'] = deviceAge;
      request.fields['deviceCategory'] = deviceCategory;
      if (imeiNum != null) request.fields['imeiNum'] = imeiNum;
      if (userEmail != null) request.fields['userEmail'] = userEmail;
      if (removedImageViews != null && removedImageViews.isNotEmpty) {
        request.fields['removedImageViews'] = jsonEncode(removedImageViews);
      }

      // Add image files
      for (final entry in imageFilePaths.entries) {
        final imageView = entry.key;
        final filePath = entry.value;
        if (filePath.isNotEmpty) {
          request.files.add(await http.MultipartFile.fromPath(imageView, filePath));
        }
      }

      final streamedResponse = await request.send().timeout(const Duration(seconds: 40));
      final response = await http.Response.fromStream(streamedResponse);
      final data = jsonDecode(response.body);
      return data;
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Finalize the trade-in request: updates requestStatus to 'Submitted' and stores imeiNum
  static Future<Map<String, dynamic>> finalizeTradeInRequest(String tradeInRequestID, {String? imeiNum}) async {
    try {
      final Map<String, dynamic> body = {'tradeInRequestID': tradeInRequestID};
      if (imeiNum != null && imeiNum.trim().isNotEmpty) {
        body['imeiNum'] = imeiNum.trim();
      }

      final response = await http.post(
        Uri.parse('$baseUrl/finalize-request'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Check if the user has an existing submitted trade-in request for Active Activity
  static Future<Map<String, dynamic>> getActiveSubmittedTradeIn(String userEmail) async {
    try {
      final uri = Uri.parse('$baseUrl/active-submitted').replace(
        queryParameters: {'userEmail': userEmail},
      );
      final response = await http.get(
        uri,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return {'success': false, 'submittedRequest': null};
    } catch (e) {
      return {'success': false, 'submittedRequest': null, 'message': e.toString()};
    }
  }

  /// Fetch all trade-in requests for a user (unpaginated backward-compatible)
  static Future<List<Map<String, dynamic>>> fetchUserTradeInRequests(String userEmail) async {
    final result = await fetchUserTradeInRequestsPaginated(
      userEmail: userEmail,
      tab: 'all',
      page: 1,
      limit: 100,
    );
    return List<Map<String, dynamic>>.from(result['requests'] ?? []);
  }

  /// Fetch paginated trade-in requests for a user with tab and status filtering
  static Future<Map<String, dynamic>> fetchUserTradeInRequestsPaginated({
    required String userEmail,
    String tab = 'all',
    String? status,
    int page = 1,
    int limit = 10,
  }) async {
    try {
      final queryParams = <String, String>{
        'userEmail': userEmail,
        'tab': tab,
        'page': page.toString(),
        'limit': limit.toString(),
      };
      if (status != null && status.isNotEmpty && status.toLowerCase() != 'all') {
        queryParams['status'] = status;
      }

      final uri = Uri.parse('$baseUrl/user-requests').replace(
        queryParameters: queryParams,
      );
      final response = await http.get(
        uri,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final List<Map<String, dynamic>> requests = (data['requests'] as List?)
                  ?.map((item) => Map<String, dynamic>.from(item as Map))
                  .toList() ??
              [];
          final pagination = data['pagination'] as Map<String, dynamic>? ?? {};
          final counts = data['counts'] as Map<String, dynamic>? ?? {};
          return {
            'success': true,
            'requests': requests,
            'hasMore': pagination['hasMore'] == true,
            'total': pagination['total'] ?? requests.length,
            'page': pagination['page'] ?? page,
            'counts': counts,
          };
        }
      }
      return {
        'success': false,
        'requests': <Map<String, dynamic>>[],
        'hasMore': false,
        'total': 0,
        'page': page,
        'counts': <String, dynamic>{},
      };
    } catch (e) {
      return {
        'success': false,
        'requests': <Map<String, dynamic>>[],
        'hasMore': false,
        'total': 0,
        'page': page,
        'counts': <String, dynamic>{},
      };
    }
  }

  /// Fetch full trade-in request details (including all uploaded images and appointment info)
  static Future<Map<String, dynamic>?> getTradeInRequestDetails(String tradeInRequestID) async {
    try {
      final cleanId = tradeInRequestID.replaceAll('#', '').trim();
      final uri = Uri.parse('$baseUrl/request-details').replace(
        queryParameters: {'tradeInRequestID': cleanId},
      );
      final response = await http.get(
        uri,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['request'] is Map) {
          return Map<String, dynamic>.from(data['request']);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Cancel existing active trade-in requests for a user when starting a new flow
  static Future<Map<String, dynamic>> cancelTradeInRequests(String userEmail) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/cancel-requests'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userEmail': userEmail}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return {'success': false};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Update the status of a trade-in request (e.g. 'Evaluated', 'Quoted')
  static Future<Map<String, dynamic>> updateTradeInStatus({
    required String tradeInRequestID,
    required String status,
    Map<String, dynamic>? estimatedValue,
  }) async {
    try {
      final payload = <String, dynamic>{
        'tradeInRequestID': tradeInRequestID,
        'status': status,
      };
      if (estimatedValue != null) {
        payload['estimatedValue'] = estimatedValue;
      }
      final response = await http.post(
        Uri.parse('$baseUrl/update-status'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return {'success': false};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Alias for updateTradeInStatus
  static Future<Map<String, dynamic>> updateStatus({
    required String tradeInRequestID,
    required String status,
    Map<String, dynamic>? estimatedValue,
  }) => updateTradeInStatus(
    tradeInRequestID: tradeInRequestID,
    status: status,
    estimatedValue: estimatedValue,
  );

  /// Check if the user has an existing pending trade-in request to resume
  static Future<Map<String, dynamic>> getActivePendingTradeIn(String userEmail) async {
    try {
      final uri = Uri.parse('$baseUrl/active-pending').replace(
        queryParameters: {'userEmail': userEmail},
      );
      final response = await http.get(
        uri,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return {'success': false, 'pendingRequest': null};
    } catch (e) {
      return {'success': false, 'pendingRequest': null, 'message': e.toString()};
    }
  }

  /// Send image to model1_phone_detection to verify if image contains a smartphone.
  /// Automatically retries up to 5 times before failing to handle PyTorch model cold-start or busy GPU/CPU.
  static Future<Map<String, dynamic>> detectPhone(String imagePath, {int maxRetries = 5}) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('$baseUrl/detect-phone'),
        );
        request.files.add(await http.MultipartFile.fromPath('image', imagePath));

        final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          return data;
        } else {
          // If server error and retries remaining, wait briefly and retry
          if (attempt < maxRetries) {
            await Future.delayed(Duration(milliseconds: 600 * attempt));
            continue;
          }
        }
      } catch (e) {
        // If timeout or connection hiccup, automatically retry
        if (attempt < maxRetries) {
          await Future.delayed(Duration(milliseconds: 600 * attempt));
          continue;
        }
      }
    }

    // User-friendly error message after 5 retry attempts
    return {
      'success': false,
      'isPhone': false,
      'message': 'Phone verification timed out after multiple attempts. Please try again.',
    };
  }

  /// Validate IMEI number, lookup TAC specs, and detect mismatch with expected device
  static Future<Map<String, dynamic>> validateImei({
    required String imei,
    required String expectedBrand,
    required String expectedModel,
    String? expectedModelCode,
    String? expectedStorage,
    String? expectedColour,
    String? expectedDeviceAge,
  }) async {
    int attempts = 0;
    while (attempts < 3) {
      attempts++;
      try {
        final response = await http.post(
          Uri.parse('$baseUrl/validate-imei'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'imei': imei,
            'expectedBrand': expectedBrand,
            'expectedModel': expectedModel,
            'expectedModelCode': expectedModelCode,
            'expectedStorage': expectedStorage,
            'expectedColour': expectedColour,
            'expectedDeviceAge': expectedDeviceAge,
          }),
        ).timeout(const Duration(seconds: 15));

        final data = jsonDecode(response.body);
        return data;
      } catch (e) {
        if (attempts >= 3) {
          final isTimeout = e.toString().toLowerCase().contains('timeout');
          return {
            'success': false,
            'message': isTimeout
                ? 'Connection timed out. Please check your network connection and try again.'
                : 'Unable to reach the server. Please verify your connection.',
          };
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    return {
      'success': false,
      'message': 'Failed to validate IMEI. Please try again.',
    };
  }

  /// Book an inspection or collection appointment slot
  static Future<Map<String, dynamic>> bookAppointment({
    required String tradeInRequestID,
    required String method,
    required String appointmentDate,
    required String appointmentTime,
    String? addressID,
    Map<String, dynamic>? address,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/book-appointment'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'tradeInRequestID': tradeInRequestID,
          'method': method,
          'appointmentDate': appointmentDate,
          'appointmentTime': appointmentTime,
          'addressID': addressID,
          'address': address,
        }),
      ).timeout(const Duration(seconds: 30));

      final data = jsonDecode(response.body);
      return data is Map<String, dynamic> ? data : {'success': true};
    } catch (e) {
      return {'success': false, 'message': 'Network error. Please try again.'};
    }
  }

  /// Check slot availability for a given date and method
  static Future<Map<String, dynamic>> getAvailableSlots({
    required String method,
    required String date,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/check-available-slots?method=${Uri.encodeComponent(method)}&date=$date'),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      return data is Map<String, dynamic> ? data : {'disabledSlots': []};
    } catch (e) {
      return {'disabledSlots': []};
    }
  }

  /// Check month date availability (returns fully booked/disabled dates and first available date)
  static Future<Map<String, dynamic>> getMonthAvailability({
    required String method,
    required String month,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/check-month-availability?method=${Uri.encodeComponent(method)}&month=$month'),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      return data is Map<String, dynamic> ? data : {'disabledDates': []};
    } catch (e) {
      return {'disabledDates': []};
    }
  }

  /// Update an existing device record (Page 2: update device data & add ram attribute)
  static Future<Map<String, dynamic>> updateDeviceRecord({
    required String deviceID,
    String? brand,
    String? model,
    dynamic modelCode,
    String? storageCapacity,
    String? colour,
    String? imeiNum,
    String? status,
    String? deviceAge,
    String? ram,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/device/update'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'deviceID': deviceID,
          if (brand != null) 'brand': brand,
          if (model != null) 'model': model,
          if (modelCode != null) 'modelCode': modelCode,
          if (storageCapacity != null) 'storageCapacity': storageCapacity,
          if (colour != null) 'colour': colour,
          if (imeiNum != null) 'imeiNum': imeiNum,
          if (status != null) 'status': status,
          if (deviceAge != null) 'deviceAge': deviceAge,
          if (ram != null) 'ram': ram,
        }),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      return data is Map<String, dynamic> ? data : {'success': response.statusCode == 200};
    } catch (e) {
      return {'success': false, 'message': 'Network error updating device: $e'};
    }
  }

  /// Page 3: Upload staff images to Cloudinary (folder `rebyte/trade_in/<id>/staff`) & Firestore subcollection staffImages
  static Future<Map<String, dynamic>> uploadStaffDeviceImages({
    required String tradeInRequestID,
    required Map<String, String> imagePaths,
  }) async {
    try {
      final cleanId = tradeInRequestID.replaceAll('#', '').trim();
      final uri = Uri.parse('$baseUrl/staff/upload-images');
      final request = http.MultipartRequest('POST', uri);

      request.fields['tradeInRequestID'] = cleanId;

      for (final entry in imagePaths.entries) {
        final slotKey = entry.key;
        final filePath = entry.value;
        if (filePath.isNotEmpty && File(filePath).existsSync()) {
          request.files.add(
            await http.MultipartFile.fromPath(slotKey, filePath),
          );
        }
      }

      final streamedResponse = await request.send().timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamedResponse);
      final data = jsonDecode(response.body);
      return data is Map<String, dynamic> ? data : {'success': response.statusCode == 200};
    } catch (e) {
      return {'success': false, 'message': 'Error uploading staff images: $e'};
    }
  }

  /// Page 4: Store ownership proof image url in trade in request and update new IMEI in same device record
  static Future<Map<String, dynamic>> verifyStaffDevice({
    required String tradeInRequestID,
    String? deviceID,
    String? imeiNum,
    String? ownershipPhotoPath,
  }) async {
    try {
      final cleanId = tradeInRequestID.replaceAll('#', '').trim();
      final uri = Uri.parse('$baseUrl/staff/verify-device');
      final request = http.MultipartRequest('POST', uri);

      request.fields['tradeInRequestID'] = cleanId;
      if (deviceID != null && deviceID.isNotEmpty) {
        request.fields['deviceID'] = deviceID;
      }
      if (imeiNum != null && imeiNum.isNotEmpty) {
        request.fields['imeiNum'] = imeiNum;
      }

      if (ownershipPhotoPath != null &&
          ownershipPhotoPath.isNotEmpty &&
          File(ownershipPhotoPath).existsSync()) {
        request.files.add(
          await http.MultipartFile.fromPath('ownershipProof', ownershipPhotoPath),
        );
      }

      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);
      final data = jsonDecode(response.body);
      return data is Map<String, dynamic> ? data : {'success': response.statusCode == 200};
    } catch (e) {
      return {'success': false, 'message': 'Error verifying device details: $e'};
    }
  }

  /// Page 5: Add finalOfferPrice attribute with random price to tradeInRequest record
  static Future<Map<String, dynamic>> setStaffFinalOfferPrice({
    required String tradeInRequestID,
    bool forceNew = false,
  }) async {
    try {
      final cleanId = tradeInRequestID.replaceAll('#', '').trim();
      final uri = Uri.parse('$baseUrl/staff/set-final-offer');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'tradeInRequestID': cleanId,
          'forceNew': forceNew,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data is Map<String, dynamic> ? data : {'success': true};
      }
      return {'success': false, 'message': 'HTTP ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'message': 'Error setting final offer price: $e'};
    }
  }
}


