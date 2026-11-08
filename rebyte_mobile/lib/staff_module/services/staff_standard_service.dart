import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../account_management_module/services/auth_service.dart';

class StaffStandardService {
  static dynamic _decodeResponse(http.Response response, String endpointLabel) {
    try {
      return jsonDecode(response.body);
    } on FormatException {
      throw Exception(
        '$endpointLabel returned HTML instead of JSON (HTTP ${response.statusCode}). '
        'Restart the updated backend and confirm this app is using that server.',
      );
    }
  }

  static Future<Map<String, String>> _headers() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Please sign in to view ReByte Standards.');
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) throw Exception('Your staff session has expired. Please sign in again.');
    return {'Authorization': 'Bearer $token'};
  }

  static Future<List<Map<String, dynamic>>> getStandards() async {
    final response = await http
        .get(Uri.parse('${AuthService.baseUrl}/api/staff/standards'), headers: await _headers())
        .timeout(const Duration(seconds: 15));
    final body = _decodeResponse(response, 'The staff standards endpoint');
    if (response.statusCode != 200 || body is! Map<String, dynamic> || body['success'] != true) {
      throw Exception(body is Map ? body['error']?.toString() ?? 'Could not load standards.' : 'Could not load standards.');
    }
    final records = body['standards'];
    if (records is! List) return [];
    return records.whereType<Map>().map((record) => Map<String, dynamic>.from(record)).toList();
  }

  static Future<Map<String, dynamic>> getStandard(String standardId) async {
    final response = await http
        .get(
          Uri.parse('${AuthService.baseUrl}/api/staff/standards/${Uri.encodeComponent(standardId)}'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 15));
    final body = _decodeResponse(response, 'The standard detail endpoint');
    if (response.statusCode != 200 || body is! Map<String, dynamic> || body['success'] != true || body['standard'] is! Map) {
      throw Exception(body is Map ? body['error']?.toString() ?? 'Could not load this standard.' : 'Could not load this standard.');
    }
    return Map<String, dynamic>.from(body['standard'] as Map);
  }
}
