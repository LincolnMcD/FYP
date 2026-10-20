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

      final uri = Uri.parse('$baseUrl/api/task-assignment/staff-tasks').replace(queryParameters: query);
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
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/task-assignment/update-status');
      final response = await http.patch(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'taskID': taskID,
          'orderID': orderID,
          ...?scheduleID != null ? {'scheduleID': scheduleID} : null,
          'status': status,
          ...?rejectionReason != null ? {'rejectionReason': rejectionReason} : null,
          ...?rejectionNotes != null ? {'rejectionNotes': rejectionNotes} : null,
        }),
      ).timeout(const Duration(seconds: 10));

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
}
