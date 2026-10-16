import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../account_management_module/services/auth_service.dart';
import '../models/product_model.dart';
import '../models/cart_item_model.dart';
import '../models/notification_model.dart';

class ShopService {
  static String get baseUrl => AuthService.baseUrl;

  /// Fetch catalog products, excluding those already in the user's cart
  static Future<List<ProductModel>> fetchProducts({
    String? email,
    String? search,
    String? brand,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (email != null && email.isNotEmpty) queryParams['email'] = email;
      if (search != null && search.isNotEmpty) queryParams['search'] = search;
      if (brand != null && brand.isNotEmpty && brand != 'All Devices') {
        queryParams['brand'] = brand;
      }

      final uri = Uri.parse('$baseUrl/api/shop/products').replace(queryParameters: queryParams);
      final response = await http.get(uri).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['products'] is List) {
          return (data['products'] as List)
              .map((item) => ProductModel.fromJson(item as Map<String, dynamic>))
              .toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('ShopService.fetchProducts error: $e');
      return [];
    }
  }

  /// Fetch user's cart items
  static Future<List<CartItemModel>> fetchCart({required String email}) async {
    if (email.isEmpty) return [];
    try {
      final uri = Uri.parse('$baseUrl/api/shop/cart').replace(queryParameters: {'email': email});
      final response = await http.get(uri).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['items'] is List) {
          return (data['items'] as List)
              .map((item) => CartItemModel.fromJson(item as Map<String, dynamic>))
              .toList();
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
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'productID': productID}),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
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
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'productID': productID}),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      debugPrint('ShopService.removeFromCart error: $e');
      return false;
    }
  }

  /// Purchase items in cart
  static Future<Map<String, dynamic>> purchaseItems({
    required String email,
    required List<String> productIDs,
  }) async {
    if (email.isEmpty || productIDs.isEmpty) {
      return {'success': false, 'error': 'Missing parameters'};
    }
    try {
      final uri = Uri.parse('$baseUrl/api/shop/purchase');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'productIDs': productIDs}),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
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
      final response = await http.get(uri).timeout(const Duration(seconds: 8));

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
        headers: {'Content-Type': 'application/json'},
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
