import 'dart:convert';
import 'package:http/http.dart' as http;

class AuthService {
  static String get baseUrl {
    return 'http://localhost:3000';
  }

  static Future<Map<String, dynamic>> requestOTP(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/request-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      ).timeout(const Duration(seconds: 5));
      final body = jsonDecode(response.body);
      if (response.statusCode == 200) return {'success': true, 'message': body['message']};
      return {'success': false, 'error': body['error'] ?? 'Request failed'};
    } catch (e) {
      return {'success': false, 'error': 'Connection failed. Ensure backend is running.'};
    }
  }

  static Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String otp,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'otp': otp,
        }),
      ).timeout(const Duration(seconds: 10));
      
      final body = jsonDecode(response.body);
      
      if (response.statusCode == 200) {
        return {'success': true, 'message': body['message']};
      } else {
        return {'success': false, 'error': body['error'] ?? 'Registration failed'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Connection failed. Ensure backend is running.'};
    }
  }

  static Future<Map<String, dynamic>> updateProfile({
    required String email,
    required String fullName,
    required String phoneNumber,
    required String birthDate,
    required String gender,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/update-profile'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'fullName': fullName,
          'phoneNumber': phoneNumber,
          'birthDate': birthDate,
          'gender': gender,
        }),
      ).timeout(const Duration(seconds: 5));
      
      final body = jsonDecode(response.body);
      
      if (response.statusCode == 200) {
        return {'success': true, 'message': body['message']};
      } else {
        return {'success': false, 'error': body['error'] ?? 'Update failed'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Connection failed.'};
    }
  }

  static Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      ).timeout(const Duration(seconds: 5));
      
      final body = jsonDecode(response.body);
      
      if (response.statusCode == 200) {
        return {'success': true, 'message': body['message'], 'name': body['name'] ?? 'ReByte User'};
      } else {
        return {'success': false, 'error': body['error'] ?? 'Login failed'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Connection failed. Ensure backend is running.'};
    }
  }
}
