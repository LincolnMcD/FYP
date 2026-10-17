import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../../account_management_module/services/auth_service.dart';
import '../models/product_model.dart';
import '../models/cart_item_model.dart';
import '../models/notification_model.dart';

class ShopService {
  static String get baseUrl => AuthService.baseUrl;
  static final Map<String, _CachedValue> _cache = {};
  static final Map<String, Future<dynamic>> _inFlight = {};
  static Future<Map<String, String>> _headers({bool json = false}) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    return {
      if (json) 'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static void _cacheValue(String key, dynamic value, {Duration ttl = const Duration(seconds: 8)}) {
    _cache[key] = _CachedValue(value, DateTime.now().add(ttl));
  }

  static dynamic _cached(String key) {
    final item = _cache[key];
    if (item == null || item.expiresAt.isBefore(DateTime.now())) {
      _cache.remove(key);
      return null;
    }
    return item.value;
  }

  static void invalidateUserCache(String email) {
    _cache.removeWhere((key, _) => key.startsWith('${email.toLowerCase()}|'));
  }

  /// Fetch catalog products, excluding those already in the user's cart
  static Future<List<ProductModel>> fetchProducts({
    String? email,
    String? search,
    String? brand,
  }) async {
    final page = await fetchProductPage(email: email, search: search, brand: brand);
    return page['products'] as List<ProductModel>;
  }

  static Future<Map<String, dynamic>> fetchProductPage({
    String? email,
    String? search,
    String? brand,
    String? sort,
    String? cursor,
    bool forceRefresh = false,
  }) async {
    final key = '${(email ?? '').toLowerCase()}|${(search ?? '').trim().toLowerCase()}|${(brand ?? '').toLowerCase()}|${sort ?? 'none'}|${cursor ?? 'first'}';
    if (!forceRefresh) {
      final cached = _cached(key);
      if (cached is Map<String, dynamic>) return cached;
      final pending = _inFlight[key];
      if (pending != null) return await pending as Map<String, dynamic>;
    }
    final request = _fetchProductPage(key, email: email, search: search, brand: brand, sort: sort, cursor: cursor);
    _inFlight[key] = request;
    try {
      return await request;
    } finally {
      if (identical(_inFlight[key], request)) _inFlight.remove(key);
    }
  }

  static Future<Map<String, dynamic>> _fetchProductPage(String key, {String? email, String? search, String? brand, String? sort, String? cursor}) async {
    try {
      final queryParams = <String, String>{};
      if (email != null && email.isNotEmpty) queryParams['email'] = email;
      if (search != null && search.isNotEmpty) queryParams['search'] = search;
      if (brand != null && brand.isNotEmpty && brand != 'All Devices') {
        queryParams['brand'] = brand;
      }
      if (sort != null && sort.isNotEmpty) queryParams['sort'] = sort;
      if (cursor != null && cursor.isNotEmpty) queryParams['cursor'] = cursor;

      final uri = Uri.parse('$baseUrl/api/shop/products').replace(queryParameters: queryParams);
      final response = await http.get(uri, headers: await _headers()).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['products'] is List) {
          final result = <String, dynamic>{
            'products': (data['products'] as List)
              .map((item) => ProductModel.fromJson(item as Map<String, dynamic>))
              .toList(),
            'nextCursor': data['nextCursor']?.toString(),
            'hasMore': data['hasMore'] == true,
          };
          _cacheValue(key, result, ttl: const Duration(seconds: 15));
          return result;
        }
      }
      var message = 'Could not retrieve products (HTTP ${response.statusCode}).';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['error'] != null) message = body['error'].toString();
      } catch (_) {}
      return {'products': <ProductModel>[], 'nextCursor': null, 'hasMore': false, 'error': message};
    } catch (e) {
      debugPrint('ShopService.fetchProducts error: $e');
      return {'products': <ProductModel>[], 'nextCursor': null, 'hasMore': false, 'error': 'Could not connect to ReByte. Check that the backend is running and the device is on the same network.'};
    }
  }

  /// Fetch user's cart items
  static Future<List<CartItemModel>> fetchCart({required String email, bool forceRefresh = false}) async {
    if (email.isEmpty) return [];
    final cacheKey = '${email.toLowerCase()}|cart';
    final cached = forceRefresh ? null : _cached(cacheKey);
    if (cached is List<CartItemModel>) return cached.map(_copyCartItem).toList();
    final pending = forceRefresh ? null : _inFlight[cacheKey];
    if (pending != null) return (await pending as List<CartItemModel>).map(_copyCartItem).toList();
    final request = _fetchCart(email, cacheKey);
    _inFlight[cacheKey] = request;
    try { return (await request).map(_copyCartItem).toList(); }
    finally { if (identical(_inFlight[cacheKey], request)) _inFlight.remove(cacheKey); }
  }

  static CartItemModel _copyCartItem(CartItemModel item) => CartItemModel(
    productID: item.productID, description: item.description, sellingPrice: item.sellingPrice,
    imageUrl: item.imageUrl, isSold: item.isSold, listingStatus: item.listingStatus,
    brand: item.brand, model: item.model, storage: item.storage, ram: item.ram,
    color: item.color, condition: item.condition, isSelected: item.isSelected,
  );

  static Future<List<CartItemModel>> _fetchCart(String email, String cacheKey) async {
    try {
      final uri = Uri.parse('$baseUrl/api/shop/cart').replace(queryParameters: {'email': email});
      final response = await http.get(uri, headers: await _headers()).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['items'] is List) {
          final items = (data['items'] as List)
              .map((item) => CartItemModel.fromJson(item as Map<String, dynamic>))
              .toList();
          _cacheValue(cacheKey, items, ttl: const Duration(seconds: 5));
          return items;
        }
      }
      return [];
    } catch (e) {
      debugPrint('ShopService.fetchCart error: $e');
      return [];
    }
  }

  /// Add item to cart
  static Future<bool> addToCart({required String email, required String productID}) async {
    if (email.isEmpty || productID.isEmpty) return false;
    try {
      final uri = Uri.parse('$baseUrl/api/shop/cart/add');
      final response = await http.post(
        uri,
        headers: await _headers(json: true),
        body: jsonEncode({'email': email, 'productID': productID}),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final success = data['success'] == true;
        if (success) invalidateUserCache(email);
        return success;
      }
      return false;
    } catch (e) {
      debugPrint('ShopService.addToCart error: $e');
      return false;
    }
  }

  /// Remove item from cart
  static Future<bool> removeFromCart({required String email, required String productID}) async {
    if (email.isEmpty || productID.isEmpty) return false;
    try {
      final uri = Uri.parse('$baseUrl/api/shop/cart/remove');
      final response = await http.post(
        uri,
        headers: await _headers(json: true),
        body: jsonEncode({'email': email, 'productID': productID}),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final success = data['success'] == true;
        if (success) invalidateUserCache(email);
        return success;
      }
      return false;
    } catch (e) {
      debugPrint('ShopService.removeFromCart error: $e');
      return false;
    }
  }

  static Future<bool> removeManyFromCart({required String email, required List<String> productIDs}) async {
    if (email.isEmpty || productIDs.isEmpty) return false;
    try {
      final response = await http.post(Uri.parse('$baseUrl/api/shop/cart/remove-many'),
        headers: await _headers(json: true),
        body: jsonEncode({'email': email, 'productIDs': productIDs}),
      ).timeout(const Duration(seconds: 8));
      final data = jsonDecode(response.body);
      final success = response.statusCode == 200 && data['success'] == true;
      if (success) invalidateUserCache(email);
      return success;
    } catch (e) {
      debugPrint('ShopService.removeManyFromCart error: $e');
      return false;
    }
  }

  /// Create an order record in Firebase
  static Future<Map<String, dynamic>> createOrder({
    required String email,
    required double subtotal,
    required double shippingFee,
    required double totalAmount,
    required String addressID,
    required List<String> productIDs,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/shop/order/create');
      final response = await http.post(
        uri,
        headers: await _headers(json: true),
        body: jsonEncode({
          'email': email,
          'subtotal': subtotal,
          'shippingFee': shippingFee,
          'totalAmount': totalAmount,
          'addressID': addressID,
          'productIDs': productIDs,
        }),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      return data is Map<String, dynamic> ? data : {'success': false};
    } catch (e) {
      debugPrint('ShopService.createOrder error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Update order status in Firebase (e.g. 'success' or 'cancelled')
  static Future<Map<String, dynamic>> updateOrderStatus({
    required String orderID,
    required String orderStatus,
    String? addressID,
    String? failReason,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/shop/order/update-status');
      final response = await http.post(
        uri,
        headers: await _headers(json: true),
        body: jsonEncode({
          'orderID': orderID,
          'orderStatus': orderStatus,
          ...?addressID != null ? {'addressID': addressID} : null,
          ...?failReason != null ? {'failReason': failReason} : null,
        }),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      return data is Map<String, dynamic> ? data : {'success': false};
    } catch (e) {
      debugPrint('ShopService.updateOrderStatus error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Create a transaction record in Firebase
  static Future<Map<String, dynamic>> createTransaction({
    required String transactionType,
    required String transactionStatus,
    required double transactionAmount,
    String? gatewayTransactionID,
    String? paymentAccountID,
    String? orderID,
    String? rentalID,
    String? tradeInRequestID,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/shop/transaction/create');
      final response = await http.post(
        uri,
        headers: await _headers(json: true),
        body: jsonEncode({
          'transactionType': transactionType,
          'transactionStatus': transactionStatus,
          'transactionAmount': transactionAmount,
          'gatewayTransactionID': gatewayTransactionID ?? '',
          'paymentAccountID': paymentAccountID ?? '',
          'orderID': orderID,
          'rentalID': rentalID,
          'tradeInRequestID': tradeInRequestID,
        }),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      return data is Map<String, dynamic> ? data : {'success': false};
    } catch (e) {
      debugPrint('ShopService.createTransaction error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Send official itemized receipt email via backend
  static Future<Map<String, dynamic>> sendReceiptEmail({
    required String email,
    required String orderID,
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required double shippingFee,
    required double totalAmount,
    DateTime? paidAt,
    String? paymentTitle,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/shop/send-receipt-email');
      final response = await http.post(
        uri,
        headers: await _headers(json: true),
        body: jsonEncode({
          'email': email,
          'orderID': orderID,
          'items': items,
          'subtotal': subtotal,
          'shippingFee': shippingFee,
          'totalAmount': totalAmount,
          'paidAt': paidAt?.toIso8601String(),
          'paymentTitle': paymentTitle,
        }),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      return data is Map<String, dynamic> ? data : {'success': false};
    } catch (e) {
      debugPrint('ShopService.sendReceiptEmail error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Purchase items in cart
  static Future<Map<String, dynamic>> purchaseItems({
    required String email,
    required List<String> productIDs,
    Map<String, double>? expectedPrices,
  }) async {
    if (email.isEmpty || productIDs.isEmpty) {
      return {'success': false, 'error': 'Missing parameters'};
    }
    try {
      final uri = Uri.parse('$baseUrl/api/shop/purchase');
      final response = await http.post(
        uri,
        headers: await _headers(json: true),
        body: jsonEncode({'email': email, 'productIDs': productIDs, 'expectedPrices': expectedPrices}),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic> && data['success'] == true) invalidateUserCache(email);
      return data is Map<String, dynamic> ? data : {'success': false};
    } catch (e) {
      debugPrint('ShopService.purchaseItems error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Fetch notifications for user
  static Future<List<NotificationModel>> fetchNotifications({required String email}) async {
    if (email.isEmpty) return [];
    try {
      final uri = Uri.parse('$baseUrl/api/shop/notifications').replace(queryParameters: {'email': email});
      final response = await http.get(uri, headers: await _headers()).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['notifications'] is List) {
          return (data['notifications'] as List)
              .map((n) => NotificationModel.fromJson(n as Map<String, dynamic>))
              .toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('ShopService.fetchNotifications error: $e');
      return [];
    }
  }

  /// Mark notification as read
  static Future<bool> markNotificationRead({required String notificationId}) async {
    if (notificationId.isEmpty) return false;
    try {
      final uri = Uri.parse('$baseUrl/api/shop/notifications/read');
      final response = await http.post(
        uri,
        headers: await _headers(json: true),
        body: jsonEncode({'notificationId': notificationId}),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}

class _CachedValue {
  final dynamic value;
  final DateTime expiresAt;
  const _CachedValue(this.value, this.expiresAt);
}
