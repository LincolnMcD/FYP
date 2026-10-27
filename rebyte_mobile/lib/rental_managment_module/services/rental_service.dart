import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../account_management_module/services/auth_service.dart';

class RentalService {
  static Future<Map<String, dynamic>> registerRentalPhone({
    required String productID,
    required String fcmToken,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${AuthService.baseUrl}/api/rental/register-phone'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'productID': productID.trim(),
          'fcmToken': fcmToken.trim(),
        }),
      ).timeout(const Duration(seconds: 10));

      final body = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': body['message'] ?? 'Product successfully registered as rental phone.',
          'data': body,
        };
      } else {
        return {
          'success': false,
          'error': body['error'] ?? 'Failed to register rental phone.',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Connection failed. Please ensure backend server is reachable.',
      };
    }
  }
}
