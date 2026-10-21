import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../account_management_module/services/auth_service.dart';

class TaskAssignmentService {
  static String get baseUrl => AuthService.baseUrl;

  /// Fetch tasks assigned to the logged-in staff member
  static Future<List<Map<String, dynamic>>> fetchStaffTasks({
    String? staffID,
    String? email,
  }) async {
    try {
      final query = <String, String>{};
      if (staffID != null && staffID.isNotEmpty) query['staffID'] = staffID;
      if (email != null && email.isNotEmpty) query['email'] = email;

      final uri = Uri.parse(
        '$baseUrl/api/task-assignment/staff-tasks',
      ).replace(queryParameters: query);
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['tasks'] is List) {
          return List<Map<String, dynamic>>.from(data['tasks'] as List);
        }
      }
      return [];
    } catch (e) {
      debugPrint('TaskAssignmentService.fetchStaffTasks error: $e');
      return [];
    }
  }

  /// Update task, schedule, and delivery status
  static Future<bool> updateTaskStatus({
    required String taskID,
    required String orderID,
    String? scheduleID,
    required String status,
    String? rejectionReason,
    String? rejectionNotes,
    String? proofOfDeliveryUrl,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/task-assignment/update-status');
      final response = await http
          .patch(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'taskID': taskID,
              'orderID': orderID,
              ...?scheduleID != null ? {'scheduleID': scheduleID} : null,
              'status': status,
              ...?rejectionReason != null
                  ? {'rejectionReason': rejectionReason}
                  : null,
              ...?rejectionNotes != null
                  ? {'rejectionNotes': rejectionNotes}
                  : null,
              ...?proofOfDeliveryUrl != null
                  ? {'proofOfDeliveryUrl': proofOfDeliveryUrl}
                  : null,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      debugPrint('TaskAssignmentService.updateTaskStatus error: $e');
      return false;
    }
  }

  /// Complete delivery with proof of delivery image uploaded to Cloudinary
  static Future<Map<String, dynamic>> completeDeliveryWithProof({
    required String taskID,
    required String orderID,
    String? scheduleID,
    required String imageFilePath,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/task-assignment/complete-delivery');
      final request = http.MultipartRequest('POST', uri);

      request.fields['taskID'] = taskID;
      request.fields['orderID'] = orderID;
      if (scheduleID != null && scheduleID.isNotEmpty) {
        request.fields['scheduleID'] = scheduleID;
      }

      if (imageFilePath.isNotEmpty) {
        request.files.add(
          await http.MultipartFile.fromPath('proofImage', imageFilePath),
        );
      }

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 40),
      );
      final response = await http.Response.fromStream(streamedResponse);
      final Object? decoded;
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        debugPrint(
          'TaskAssignmentService.completeDeliveryWithProof received a non-JSON '
          'response (HTTP ${response.statusCode}, '
          'content type ${response.headers['content-type'] ?? 'unknown'}).',
        );
        return {
          'success': false,
          'message': response.statusCode >= 500
              ? 'The server could not complete the delivery. Please try again.'
              : 'The server returned an unexpected response. Please try again.',
        };
      }

      if (decoded is! Map<String, dynamic>) {
        return {
          'success': false,
          'message':
              'The server returned an unexpected response. Please try again.',
        };
      }
      final data = decoded;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return {
          'success': false,
          'message':
              data['message']?.toString() ??
              data['error']?.toString() ??
              'Failed to upload proof of delivery. Please try again.',
        };
      }
      return {
        'success': data['success'] == true,
        'proofOfDeliveryUrl': data['proofOfDeliveryUrl']?.toString() ?? '',
        'message': data['message']?.toString() ?? '',
      };
    } catch (e) {
      debugPrint('TaskAssignmentService.completeDeliveryWithProof error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Broadcast live staff GPS location to backend
  static Future<bool> updateStaffLiveLocation({
    required String orderID,
    required String taskID,
    String? staffID,
    required double lat,
    required double lng,
    double heading = 0.0,
    double? estimatedDistanceKm,
    int? estimatedDurationMinutes,
  }) async {
    try {
      final cleanOrderID = orderID.replaceAll('#', '').trim();
      final uri = Uri.parse('$baseUrl/api/task-assignment/update-staff-location');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'orderID': cleanOrderID,
          'taskID': taskID,
          if (staffID != null) 'staffID': staffID,
          'lat': lat,
          'lng': lng,
          'heading': heading,
          if (estimatedDistanceKm != null) 'estimatedDistanceKm': estimatedDistanceKm,
          if (estimatedDurationMinutes != null) 'estimatedDurationMinutes': estimatedDurationMinutes,
        }),
      ).timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Fetch real-time delivery and staff tracking info for customer tracking map
  static Future<Map<String, dynamic>?> trackDelivery({
    required String orderID,
  }) async {
    try {
      final cleanOrderID = orderID.replaceAll('#', '').trim();
      final uri = Uri.parse('$baseUrl/api/task-assignment/track-delivery/$cleanOrderID');
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map<String, dynamic> && data['success'] == true) {
          return data;
        }
      }
      return null;
    } catch (e) {
      debugPrint('TaskAssignmentService.trackDelivery error: $e');
      return null;
    }
  }
}

