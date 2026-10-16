import 'package:flutter/material.dart';
import 'models/notification_model.dart';
import 'services/shop_service.dart';

class NotificationPage extends StatefulWidget {
  final bool isLoggedIn;
  final String? email;
  final String? name;

  const NotificationPage({
    super.key,
    required this.isLoggedIn,
    this.email,
    this.name,
  });

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  List<NotificationModel> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    if (widget.email == null || widget.email!.isEmpty) {
      setState(() {
        _notifications = _getMockNotifications();
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);
    final fetched = await ShopService.fetchNotifications(email: widget.email!);

    if (mounted) {
      setState(() {
        if (fetched.isNotEmpty) {
          _notifications = fetched;
        } else {
          // Provide standard initial mock notifications matching Screenshot 3 if user has none yet
          _notifications = _getMockNotifications();
        }
        _isLoading = false;
      });
    }
  }

  List<NotificationModel> _getMockNotifications() {
    return [
      NotificationModel(
        id: 'mock_1',
        title: 'Trade-In Update',
        body: 'Your iPhone 13 Pro assessment is complete. Review your preliminary...',
        type: 'tradein',
        read: false,
        createdAt: '2 mins ago',
      ),
      NotificationModel(
        id: 'mock_2',
        title: 'Rental Reminder',
        body: 'Rental due soon: Your Galaxy S23 Ultra is due for return in 2 days.',
        type: 'rental',
        read: false,
        createdAt: '3 hours ago',
      ),
      NotificationModel(
        id: 'mock_3',
        title: 'Order Status',
        body: 'Package Delivered: Your order #RB-8821 has been delivered to your saved...',
        type: 'order',
        read: true,
        createdAt: 'Yesterday',
      ),
      NotificationModel(
        id: 'mock_4',
        title: 'Booking Confirmation',
        body: 'Appointment Confirmed: On-site inspection scheduled for Oct 12, 10:00...',
        type: 'booking',
        read: false,
        createdAt: 'Oct 10',
      ),
      NotificationModel(
        id: 'mock_5',
        title: 'Account Security',
        body: 'Password Changed: Your account password was updated successfully.',
        type: 'security',
        read: true,
        createdAt: 'Oct 08',
      ),
    ];
  }

  Future<void> _markAsRead(NotificationModel notif) async {
    if (!notif.read && !notif.id.startsWith('mock_')) {
      await ShopService.markNotificationRead(notificationId: notif.id);
      _loadNotifications();
    }
  }

  IconData _getIconForType(String type) {
    switch (type.toLowerCase()) {
      case 'tradein':
        return Icons.compare_arrows;
      case 'rental':
        return Icons.access_time;
      case 'order':
      case 'cart':
        return Icons.local_shipping_outlined;
      case 'booking':
        return Icons.calendar_today_outlined;
      case 'security':
        return Icons.security_outlined;
      default:
        return Icons.notifications_none;
    }
  }

  Color _getIconBgColor(String type) {
    switch (type.toLowerCase()) {
      case 'tradein':
        return const Color(0xFFE0F2FE);
      case 'rental':
        return const Color(0xFFFEF3C7);
      case 'order':
      case 'cart':
        return const Color(0xFFD1FAE5);
      case 'booking':
        return const Color(0xFFE0E7FF);
      case 'security':
        return const Color(0xFFE2E8F0);
      default:
        return const Color(0xFFF1F5F9);
    }
  }

  Color _getIconColor(String type) {
    switch (type.toLowerCase()) {
      case 'tradein':
        return const Color(0xFF0284C7);
      case 'rental':
        return const Color(0xFFD97706);
      case 'order':
      case 'cart':
        return const Color(0xFF059669);
      case 'booking':
        return const Color(0xFF4F46E5);
      case 'security':
        return const Color(0xFF475569);
      default:
        return const Color(0xFF64748B);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/rebyte_logo.png', height: 36),
            const SizedBox(width: 8),
            const Text(
              'ReByte',
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ],
        ),
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_none, color: Colors.black87),
                onPressed: () {},
              ),
              Positioned(
                right: 12,
                top: 12,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF97316),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF0C5AD2)),
            )
          : RefreshIndicator(
              onRefresh: _loadNotifications,
              color: const Color(0xFF0C5AD2),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Notification',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _notifications.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final item = _notifications[index];
                        return _buildNotificationCard(item);
                      },
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildNotificationCard(NotificationModel notif) {
    return InkWell(
      onTap: () => _markAsRead(notif),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _getIconBgColor(notif.type),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(
                _getIconForType(notif.type),
                color: _getIconColor(notif.type),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notif.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notif.body,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF475569),
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    notif.formattedTime,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
            if (!notif.read)
              Container(
                margin: const EdgeInsets.only(top: 4, left: 8),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF0C5AD2),
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
