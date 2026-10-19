import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:intl/intl.dart';
import 'services/task_assignment_service.dart';

class StaffTaskDetailsPage extends StatefulWidget {
  final Map<String, dynamic> task;
  final VoidCallback? onTaskUpdated;

  const StaffTaskDetailsPage({
    super.key,
    required this.task,
    this.onTaskUpdated,
  });

  @override
  State<StaffTaskDetailsPage> createState() => _StaffTaskDetailsPageState();
}

class _StaffTaskDetailsPageState extends State<StaffTaskDetailsPage> {
  bool _isMapLoading = true;
  bool _isActionLoading = false;
  late Map<String, dynamic> _currentTask;

  @override
  void initState() {
    super.initState();
    _currentTask = Map<String, dynamic>.from(widget.task);
  }

  @override
  Widget build(BuildContext context) {
    final task = _currentTask;
    final orderID = task['orderID']?.toString() ?? 'RB-9901';
    final taskID = task['taskID']?.toString() ?? '';
    final scheduleID = task['scheduleID']?.toString() ?? '';
    final taskStatus = task['taskStatus']?.toString() ?? 'Packaging';
    final scheduleStatus = task['scheduleStatus']?.toString() ?? 'assigned';
    final customerName = task['customerName']?.toString() ?? 'Customer';
    final customerPhone = task['customerPhone']?.toString() ?? '+60 12-345 6789';
    final customerEmail = task['customerEmail']?.toString() ?? '';
    final address = task['deliveryAddress']?.toString() ?? 'Central Hub';
    final scheduleDateStr = task['scheduleDate']?.toString();
    final startTimeStr = task['scheduleStartTime']?.toString();
    final endTimeStr = task['scheduleEndTime']?.toString();

    final destLat = (task['destinationLat'] as num?)?.toDouble() ?? 3.1390;
    final destLng = (task['destinationLng'] as num?)?.toDouble() ?? 101.6869;

    // Parse DateTime
    DateTime? scheduleDate;
    if (startTimeStr != null && startTimeStr.isNotEmpty) {
      if (startTimeStr.contains('-') || startTimeStr.contains('T')) {
        scheduleDate = DateTime.tryParse(startTimeStr);
      } else if (scheduleDateStr != null && scheduleDateStr.isNotEmpty) {
        final cleanTime = startTimeStr.length == 5 ? '$startTimeStr:00' : startTimeStr;
        scheduleDate = DateTime.tryParse('${scheduleDateStr}T$cleanTime');
      }
    }
    scheduleDate ??= (scheduleDateStr != null ? DateTime.tryParse(scheduleDateStr) : null) ?? DateTime.now();

    String formattedDate = DateFormat('MMM d, yyyy').format(scheduleDate);
    String timeFormatted = DateFormat('h:mm a').format(scheduleDate);
    if (endTimeStr != null && endTimeStr.isNotEmpty && !endTimeStr.contains('T')) {
      try {
        final cleanEndTime = endTimeStr.length == 5 ? '$endTimeStr:00' : endTimeStr;
        final endDt = DateTime.tryParse('${scheduleDateStr ?? DateFormat('yyyy-MM-dd').format(scheduleDate)}T$cleanEndTime');
        if (endDt != null) {
          timeFormatted = '${DateFormat('h:mm a').format(scheduleDate)} - ${DateFormat('h:mm a').format(endDt)}';
        }
      } catch (_) {}
    }

    // Time difference relative to now for badge
    final now = DateTime.now();
    final diff = scheduleDate.difference(now);
    String timeBadge = '';
    if (diff.isNegative) {
      final hoursAgo = diff.inHours.abs();
      if (hoursAgo == 0) {
        timeBadge = '${diff.inMinutes.abs()}m ago';
      } else {
        timeBadge = '${hoursAgo}h ago';
      }
    } else {
      final inHours = diff.inHours;
      if (inHours == 0) {
        timeBadge = 'In ${diff.inMinutes} mins';
      } else {
        timeBadge = 'In $inHours hours';
      }
    }

    // Device details
    final items = task['items'] as List? ?? [];
    String modelName = 'Electronic Device';
    String storage = 'N/A';
    String condition = 'Good';
    String? imageUrl;
    if (items.isNotEmpty && items[0] is Map) {
      final first = items[0] as Map;
      final brand = first['brand']?.toString() ?? '';
      final model = first['model']?.toString() ?? '';
      modelName = '$brand $model'.trim();
      if (modelName.isEmpty) modelName = 'Electronic Device';
      storage = first['storage']?.toString() ?? 'Standard';
      condition = first['condition']?.toString() ?? 'Good';
      imageUrl = first['imageUrl']?.toString();
    }

    // Status styling
    Color statusBgColor = const Color(0xFFFEF3C7);
    Color statusTextColor = const Color(0xFFD97706);
    IconData statusIcon = Icons.pending;

    final lowerStatus = taskStatus.toLowerCase();
    final lowerSched = scheduleStatus.toLowerCase();
    final isAssigned = lowerSched == 'assigned' || lowerStatus == 'packaging';
    final isShipping = lowerSched == 'ongoing' || lowerStatus == 'shipping' || lowerStatus == 'in progress';
    final isDelivered = lowerSched == 'completed' || lowerStatus == 'delivered';

    if (isShipping) {
      statusBgColor = const Color(0xFFDBEAFE);
      statusTextColor = const Color(0xFF1D4ED8);
      statusIcon = Icons.local_shipping;
    } else if (isDelivered) {
      statusBgColor = const Color(0xFFDCFCE7);
      statusTextColor = const Color(0xFF16A34A);
      statusIcon = Icons.check_circle;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Task Details',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status & Order ID Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: statusBgColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 14, color: statusTextColor),
                        const SizedBox(width: 5),
                        Text(
                          taskStatus,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: statusTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'ID:  #$orderID',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Customer Info Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: const Color(0xFFEFF6FF),
                    child: Text(
                      customerName.isNotEmpty ? customerName[0].toUpperCase() : 'C',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0C5AD2),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customerName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.phone, size: 14, color: Color(0xFF64748B)),
                            const SizedBox(width: 6),
                            Text(
                              customerPhone,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF475569),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        if (customerEmail.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.email, size: 14, color: Color(0xFF64748B)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  customerEmail,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF475569),
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Device Details Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.phone_android, size: 18, color: Color(0xFF0C5AD2)),
                      SizedBox(width: 8),
                      Text(
                        'Device Details',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        padding: const EdgeInsets.all(6),
                        child: imageUrl != null && imageUrl.isNotEmpty
                            ? Image.network(
                                imageUrl,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) => const Icon(Icons.devices, color: Color(0xFF94A3B8)),
                              )
                            : const Icon(Icons.devices, size: 30, color: Color(0xFF94A3B8)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'MODEL',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF94A3B8),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              modelName,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'STORAGE',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF94A3B8),
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      storage,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF334155),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 24),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'CONDITION',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF94A3B8),
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF16A34A),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          condition,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF334155),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Date, Time & Delivery Location Map Card (Matching screenshot Appointment card)
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Card Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: Row(
                      children: const [
                        Icon(Icons.calendar_month, size: 18, color: Color(0xFF0C5AD2)),
                        SizedBox(width: 8),
                        Text(
                          'Schedule & Location',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFF1F5F9)),

                  // Date & Time
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'DATE & TIME',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF94A3B8),
                                letterSpacing: 0.5,
                              ),
                            ),
                            if (timeBadge.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.access_time, size: 12, color: Color(0xFF0C5AD2)),
                                    const SizedBox(width: 4),
                                    Text(
                                      timeBadge,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF0C5AD2),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          formattedDate,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          timeFormatted,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        const SizedBox(height: 14),

                        // Location Address
                        const Text(
                          'DELIVERY LOCATION',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF94A3B8),
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          address,
                          textAlign: TextAlign.justify,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF334155),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Map Container with pinpoint
                  Container(
                    height: 180,
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        InAppWebView(
                          initialData: InAppWebViewInitialData(
                            data: _buildMapHtml(destLat, destLng),
                            mimeType: 'text/html',
                            encoding: 'utf-8',
                          ),
                          initialSettings: InAppWebViewSettings(
                            javaScriptEnabled: true,
                            supportZoom: false,
                            disableHorizontalScroll: true,
                            disableVerticalScroll: true,
                          ),
                          onLoadStop: (controller, url) {
                            setState(() => _isMapLoading = false);
                          },
                        ),
                        if (_isMapLoading)
                          const Center(
                            child: CircularProgressIndicator(color: Color(0xFF0C5AD2), strokeWidth: 2.5),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Reject / Cancel Task Button
              Expanded(
                flex: 1,
                child: OutlinedButton.icon(
                  onPressed: _isActionLoading
                      ? null
                      : () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Reject Task'),
                              content: const Text('Are you sure you want to reject this assigned delivery task?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                                  child: const Text('Reject', style: TextStyle(color: Colors.white)),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            setState(() => _isActionLoading = true);
                            await TaskAssignmentService.updateTaskStatus(
                              taskID: taskID,
                              orderID: orderID,
                              scheduleID: scheduleID,
                              status: 'Rejected',
                            );
                            widget.onTaskUpdated?.call();
                            if (!context.mounted) return;
                            Navigator.pop(context);
                          }
                        },
                  icon: const Icon(Icons.close, color: Color(0xFFDC2626), size: 18),
                  label: const Text(
                    'Reject Task',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Color(0xFFFCA5A5)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Start Navigation / Action Button
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _isActionLoading
                      ? null
                      : () async {
                          setState(() => _isActionLoading = true);
                          final nextStatus = isAssigned ? 'Shipping' : 'Delivered';
                          await TaskAssignmentService.updateTaskStatus(
                            taskID: taskID,
                            orderID: orderID,
                            scheduleID: scheduleID,
                            status: nextStatus,
                          );
                          widget.onTaskUpdated?.call();
                          if (!context.mounted) return;
                          setState(() {
                            _currentTask['taskStatus'] = nextStatus;
                            _currentTask['scheduleStatus'] = isAssigned ? 'ongoing' : 'completed';
                            _isActionLoading = false;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(isAssigned ? 'Navigation started! Task moved to Ongoing.' : 'Delivery completed successfully!'),
                              backgroundColor: const Color(0xFF0C5AD2),
                            ),
                          );
                        },
                  icon: _isActionLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.navigation, color: Colors.white, size: 18),
                  label: Text(
                    isAssigned
                        ? 'Start Navigation'
                        : isShipping
                            ? 'Complete Delivery'
                            : 'Completed',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0C5AD2),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _buildMapHtml(double lat, double lng) {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
  <style>
    body, html { margin: 0; padding: 0; width: 100%; height: 100%; background: #F8FAFC; overflow: hidden; }
    #map { width: 100%; height: 100%; }
    .custom-pin {
      width: 28px;
      height: 28px;
      background: #0C5AD2;
      border: 3px solid #FFFFFF;
      border-radius: 50% 50% 50% 0;
      transform: rotate(-45deg);
      box-shadow: 0 4px 8px rgba(0,0,0,0.25);
    }
  </style>
</head>
<body>
  <div id="map"></div>
  <script>
    var map = L.map('map', {
      center: [$lat, $lng],
      zoom: 15,
      zoomControl: false,
      attributionControl: false,
      dragging: false,
      touchZoom: false,
      scrollWheelZoom: false,
      doubleClickZoom: false
    });

    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19
    }).addTo(map);

    var pinIcon = L.divIcon({
      className: '',
      html: '<div class="custom-pin"></div>',
      iconSize: [28, 28],
      iconAnchor: [14, 28]
    });

    L.marker([$lat, $lng], { icon: pinIcon }).addTo(map);
  </script>
</body>
</html>
''';
  }
}
