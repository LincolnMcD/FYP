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
      final response = await http
          .post(
            Uri.parse('${AuthService.baseUrl}/api/rental/register-phone'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'productID': productID.trim(),
              'fcmToken': fcmToken.trim(),
            }),
          )
          .timeout(const Duration(seconds: 10));

      final body = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'message':
              body['message'] ??
              'Product successfully registered as rental phone.',
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
        'error':
            'Connection failed. Please ensure backend server is reachable.',
      };
    }
  }

  static Future<Map<String, dynamic>> createRentalSession({
    required String email,
    required double amount,
    required String description,
    required String productID,
    required int durationMonths,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(
              '${AuthService.baseUrl}/api/rental/create-rental-session',
            ),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email.trim(),
              'amount': amount,
              'description': description,
              'productID': productID.trim(),
              'durationMonths': durationMonths,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final body = jsonDecode(response.body);
      return body is Map<String, dynamic>
          ? body
          : {'success': false, 'error': 'Invalid server response'};
    } catch (e) {
      return {'success': false, 'error': 'Connection failed: $e'};
    }
  }

  static Future<Map<String, dynamic>> createRentalRecord({
    required String productID,
    required String email,
    required int durationMonths,
    double? monthlyRentalFee,
    double? depositAmount,
    String? addressID,
    String? paymentAccountID,
    String? paymentTokenID,
    String? xenditCustomerID,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AuthService.baseUrl}/api/rental/create-rental'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'productID': productID.trim(),
              'email': email.trim(),
              'durationMonths': durationMonths,
              if (monthlyRentalFee != null)
                'monthlyRentalFee': monthlyRentalFee,
              if (depositAmount != null) 'depositAmount': depositAmount,
              if (addressID != null && addressID.isNotEmpty)
                'addressID': addressID.trim(),
              if (paymentAccountID != null && paymentAccountID.isNotEmpty)
                'paymentAccountID': paymentAccountID.trim(),
              if (paymentTokenID != null && paymentTokenID.isNotEmpty)
                'paymentTokenID': paymentTokenID.trim(),
              if (xenditCustomerID != null && xenditCustomerID.isNotEmpty)
                'xenditCustomerID': xenditCustomerID.trim(),
            }),
          )
          .timeout(const Duration(seconds: 15));

      final body = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'success': true,
          'message': body['message'] ?? 'Rental record created successfully.',
          'rental': body['rental'],
          'recurringAuthUrl': body['recurringAuthUrl'],
          'recurringAuthSessionID': body['recurringAuthSessionID'],
          'recurringStatus': body['recurringStatus'],
        };
      } else {
        return {
          'success': false,
          'error': body['error'] ?? 'Failed to create rental record.',
        };
      }
    } catch (e) {
      return {'success': false, 'error': 'Connection failed: $e'};
    }
  }

  static Future<List<Map<String, dynamic>>> getCustomerRentals(
    String emailOrId,
  ) async {
    try {
      final encoded = Uri.encodeComponent(emailOrId.trim());
      final response = await http
          .get(
            Uri.parse('${AuthService.baseUrl}/api/rental/customer/$encoded'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['success'] == true && body['rentals'] is List) {
          return List<Map<String, dynamic>>.from(body['rentals']);
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<bool> syncRentalPlanStatus(String rentalID) async {
    try {
      final res = await http
          .post(
            Uri.parse('${AuthService.baseUrl}/api/rental/sync-plan-status'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'rentalID': rentalID}),
          )
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(res.body);
      return body['success'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> completeRecurringAuthorization({
    required String rentalID,
    required String sessionID,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(
              '${AuthService.baseUrl}/api/rental/complete-recurring-auth',
            ),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'rentalID': rentalID, 'sessionID': sessionID}),
          )
          .timeout(const Duration(seconds: 15));
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) {
        return {
          ...body,
          'success':
              response.statusCode >= 200 &&
              response.statusCode < 300 &&
              body['success'] == true,
        };
      }
      return {'success': false, 'error': 'Invalid server response.'};
    } catch (e) {
      return {
        'success': false,
        'error': 'Unable to verify e-wallet authorization: $e',
      };
    }
  }

  static Future<Map<String, dynamic>> testRecurringCharge({
    required String rentalID,
    required bool forceFailure,
    String? failureReason,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse(
              '${AuthService.baseUrl}/api/rental/test-recurring-charge',
            ),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'rentalID': rentalID,
              'forceFailure': forceFailure,
              if (failureReason != null) 'failureReason': failureReason,
            }),
          )
          .timeout(const Duration(seconds: 10));
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Network error testing charge: $e'};
    }
  }

  static Future<bool> cancelRental(String rentalID) async {
    try {
      final res = await http
          .post(
            Uri.parse('${AuthService.baseUrl}/api/rental/cancel-rental'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'rentalID': rentalID}),
          )
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(res.body);
      return body['success'] == true;
    } catch (_) {
      return false;
    }
  }
}
