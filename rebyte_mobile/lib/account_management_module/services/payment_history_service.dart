import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import '../models/customer_transaction_model.dart';

class PaymentHistoryResult {
  final bool success;
  final List<CustomerTransactionModel> transactions;
  final int totalCount;
  final bool hasMore;
  final String? error;

  PaymentHistoryResult({
    required this.success,
    required this.transactions,
    required this.totalCount,
    required this.hasMore,
    this.error,
  });
}

class PaymentHistoryService {
  static Future<PaymentHistoryResult> fetchTransactions({
    required String email,
    String type = 'all',
    int limit = 5,
    int offset = 0,
    String searchId = '',
  }) async {
    try {
      final queryParams = {
        'email': email,
        'type': type,
        'limit': limit.toString(),
        'offset': offset.toString(),
        if (searchId.trim().isNotEmpty) 'searchId': searchId.trim(),
      };

      final uri = Uri.parse('${AuthService.baseUrl}/api/payment/transactions')
          .replace(queryParameters: queryParams);

      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final rawList = data['transactions'] as List? ?? [];
          final items = rawList
              .map((e) => CustomerTransactionModel.fromJson(e as Map<String, dynamic>))
              .toList();

          return PaymentHistoryResult(
            success: true,
            transactions: items,
            totalCount: (data['totalCount'] as num?)?.toInt() ?? items.length,
            hasMore: data['hasMore'] == true,
          );
        } else {
          return PaymentHistoryResult(
            success: false,
            transactions: [],
            totalCount: 0,
            hasMore: false,
            error: data['error']?.toString() ?? 'Failed to load transactions',
          );
        }
      } else {
        return PaymentHistoryResult(
          success: false,
          transactions: [],
          totalCount: 0,
          hasMore: false,
          error: 'Server returned error ${response.statusCode}',
        );
      }
    } catch (e) {
      return PaymentHistoryResult(
        success: false,
        transactions: [],
        totalCount: 0,
        hasMore: false,
        error: e.toString(),
      );
    }
  }
}
