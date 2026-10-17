class NotificationModel {
  final String id;
  final String title;
  final String body;
  final String type;
  final bool read;
  final String createdAt;

  NotificationModel({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.read,
    required this.createdAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? json['message']?.toString() ?? '',
      type: json['type']?.toString() ?? 'system',
      read: json['read'] == true,
      createdAt: json['createdAt']?.toString() ?? '',
    );
  }

  /// Format timestamp into clean "YYYY-MM-DD HH:mm" without 'T', 'Z', or microseconds
  String get formattedTime {
    if (createdAt.isEmpty) return '';
    try {
      final parsed = DateTime.tryParse(createdAt);
      if (parsed != null) {
        final local = parsed.toLocal();
        final year = local.year.toString().padLeft(4, '0');
        final month = local.month.toString().padLeft(2, '0');
        final day = local.day.toString().padLeft(2, '0');
        final hour = local.hour.toString().padLeft(2, '0');
        final min = local.minute.toString().padLeft(2, '0');
        return '$year-$month-$day $hour:$min';
      }
    } catch (_) {}
    // If string already has T (e.g. 2026-10-17T01:54:02.123Z)
    if (createdAt.contains('T')) {
      final parts = createdAt.split('T');
      final date = parts[0];
      final timePart = parts.length > 1 ? parts[1].split('.')[0].replaceAll('Z', '') : '';
      final timeShort = timePart.length >= 5 ? timePart.substring(0, 5) : timePart;
      return '$date $timeShort'.trim();
    }
    return createdAt;
  }
}
