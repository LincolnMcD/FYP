import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'auth_service.dart';

class HelpDeskService {
  static Future<Map<String, String>> _authHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Please sign in to use ReByte Help Desk.');
    final idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) throw Exception('Your sign-in session has expired. Please sign in again.');
    return {'Content-Type': 'application/json', 'Authorization': 'Bearer $idToken'};
  }

  static Future<Map<String, dynamic>> _request(http.Response response) async {
    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(response.body);
      body = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } on FormatException {
      throw Exception('The Help Desk server returned an invalid response.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(body['error']?.toString() ?? 'Unable to complete the Help Desk request.');
    }
    return body;
  }

  static Future<SupportTicket?> getActiveTicket() async {
    final response = await http.get(Uri.parse('${AuthService.baseUrl}/api/help-desk/tickets/active'), headers: await _authHeaders()).timeout(const Duration(seconds: 15));
    final ticket = (await _request(response))['ticket'];
    return ticket is Map ? SupportTicket.fromJson(Map<String, dynamic>.from(ticket)) : null;
  }

  static Future<SupportTicket> getTicket(String ticketID) async {
    final response = await http.get(Uri.parse('${AuthService.baseUrl}/api/help-desk/tickets/${Uri.encodeComponent(ticketID)}'), headers: await _authHeaders()).timeout(const Duration(seconds: 15));
    final ticket = (await _request(response))['ticket'];
    if (ticket is! Map) throw Exception('The support ticket was not returned.');
    return SupportTicket.fromJson(Map<String, dynamic>.from(ticket));
  }

  static Future<SupportTicket> createTicket(String category) async {
    final response = await http.post(Uri.parse('${AuthService.baseUrl}/api/help-desk/tickets'), headers: await _authHeaders(), body: jsonEncode({'ticketCategory': category})).timeout(const Duration(seconds: 15));
    final ticket = (await _request(response))['ticket'];
    if (ticket is! Map) throw Exception('The support ticket was not returned.');
    return SupportTicket.fromJson(Map<String, dynamic>.from(ticket));
  }

  static Future<List<SupportMessage>> getMessages(String ticketID) async {
    final response = await http.get(Uri.parse('${AuthService.baseUrl}/api/help-desk/tickets/${Uri.encodeComponent(ticketID)}/messages'), headers: await _authHeaders()).timeout(const Duration(seconds: 15));
    final messages = (await _request(response))['messages'];
    if (messages is! List) return [];
    return messages.whereType<Map>().map((item) => SupportMessage.fromJson(Map<String, dynamic>.from(item))).toList();
  }

  static Future<SupportMessage> sendTicketMessage(String ticketID, String content) async {
    final response = await http.post(Uri.parse('${AuthService.baseUrl}/api/help-desk/tickets/${Uri.encodeComponent(ticketID)}/messages'), headers: await _authHeaders(), body: jsonEncode({'messageContent': content})).timeout(const Duration(seconds: 15));
    final message = (await _request(response))['message'];
    if (message is! Map) throw Exception('The message was not returned.');
    return SupportMessage.fromJson(Map<String, dynamic>.from(message));
  }

  static Future<HelpDeskReply> sendMessage({
    required String message,
    required List<Map<String, String>> history,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Please sign in to use ReByte Help Desk.');
    }

    final idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw Exception('Your sign-in session has expired. Please sign in again.');
    }
    final response = await http
        .post(
          Uri.parse('${AuthService.baseUrl}/api/help-desk/chat'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken',
          },
          body: jsonEncode({'message': message, 'history': history}),
        )
        .timeout(const Duration(seconds: 55));

    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(response.body);
      body = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } on FormatException {
      throw Exception('The Help Desk server returned an invalid response.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(body['error']?.toString() ?? 'Unable to get a Help Desk reply.');
    }

    final reply = body['reply']?.toString().trim() ?? '';
    if (reply.isEmpty) throw Exception('The Help Desk returned an empty reply.');
    final actions = body['actions'] is List
        ? (body['actions'] as List).map((action) => action.toString()).toList()
        : <String>[];
    final steps = body['steps'] is List
        ? (body['steps'] as List).map((step) => step.toString()).toList()
        : <String>[];
    return HelpDeskReply(
      text: reply,
      intent: body['intent']?.toString() ?? 'general',
      actions: actions,
      steps: steps,
      needsStaff: body['needsStaff'] == true,
    );
  }
}

class SupportTicket {
  final String ticketID;
  final String ticketCategory;
  final String ticketStatus;

  const SupportTicket({required this.ticketID, required this.ticketCategory, required this.ticketStatus});

  factory SupportTicket.fromJson(Map<String, dynamic> json) => SupportTicket(
        ticketID: json['ticketID']?.toString() ?? '',
        ticketCategory: json['ticketCategory']?.toString() ?? '',
        ticketStatus: json['ticketStatus']?.toString() ?? 'pending',
      );
}

class SupportMessage {
  final String messageID;
  final String messageContent;
  final String ticketID;
  final String senderRole;

  const SupportMessage({required this.messageID, required this.messageContent, required this.ticketID, required this.senderRole});

  factory SupportMessage.fromJson(Map<String, dynamic> json) => SupportMessage(
        messageID: json['messageID']?.toString() ?? '',
        messageContent: json['messageContent']?.toString() ?? '',
        ticketID: json['ticketID']?.toString() ?? '',
        senderRole: json['senderRole']?.toString() ?? 'staff',
      );
}

class HelpDeskReply {
  final String text;
  final String intent;
  final List<String> actions;
  final List<String> steps;
  final bool needsStaff;

  const HelpDeskReply({required this.text, required this.intent, required this.actions, required this.steps, this.needsStaff = false});
}
