import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:intl/intl.dart';
import 'services/task_assignment_service.dart';
import 'staff_navigation_page.dart';

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
      if (storage.isNotEmpty && storage != 'N/A' && storage != 'Standard' && !modelName.toLowerCase().contains(storage.toLowerCase())) {
        modelName = '$modelName ($storage)';
      }
      condition = first['condition']?.toString() ?? 'Good';
      imageUrl = first['imageUrl']?.toString();
    }
    final taskType = (task['taskType']?.toString() ?? task['type']?.toString() ?? 'deliver').toLowerCase();
    final isInspect = taskType.contains('inspect');
    final isCollect = taskType.contains('collect');

    final String itemsTitle = isInspect
        ? (items.length > 1 ? 'Inspect Items' : 'Inspect Item')
        : (isCollect ? (items.length > 1 ? 'Collect Items' : 'Collect Item') : 'Package Items');

    final proofOfDeliveryUrl = (_currentTask['proofOfDeliveryUrl'] ?? task['proofOfDeliveryUrl'])?.toString() ?? '';

    // Status styling
    Color statusBgColor = const Color(0xFFFEF3C7);
    Color statusTextColor = const Color(0xFFD97706);
    IconData statusIcon = Icons.pending;

    final lowerStatus = taskStatus.toLowerCase();
    final lowerSched = scheduleStatus.toLowerCase();
    final isAssigned = lowerSched == 'assigned' || lowerStatus == 'packaging';
    final isShipping = lowerSched == 'ongoing' || lowerStatus == 'shipping' || lowerStatus == 'in progress';
    final isDelivered = lowerSched == 'completed' || lowerStatus == 'delivered';

    final String displayStatusText = (taskStatus.toLowerCase() == 'shipping' || (isShipping && !isDelivered)) ? 'Ongoing' : taskStatus;

    if (isShipping) {
      statusBgColor = const Color(0xFFDBEAFE);
      statusTextColor = const Color(0xFF1D4ED8);
      statusIcon = Icons.navigation;
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
                          displayStatusText,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: statusTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isInspect || isCollect) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: isInspect ? const Color(0xFFF3E8FF) : const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isInspect ? const Color(0xFFDDD6FE) : const Color(0xFFA7F3D0),
                        ),
                      ),
                      child: Text(
                        isInspect ? 'INSPECTION' : 'COLLECTION',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: isInspect ? const Color(0xFF7C3AED) : const Color(0xFF059669),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ID:  #$orderID',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF64748B),
                      ),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
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

            // Device Details Card (Renders all products in the order)
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              isInspect
                                  ? Icons.search_rounded
                                  : (isCollect ? Icons.archive_outlined : Icons.inventory_2_outlined),
                              size: 18,
                              color: isInspect
                                  ? const Color(0xFF7C3AED)
                                  : (isCollect ? const Color(0xFF059669) : const Color(0xFF0C5AD2)),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                itemsTitle,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isInspect
                              ? const Color(0xFFF3E8FF)
                              : (isCollect ? const Color(0xFFECFDF5) : const Color(0xFFEFF6FF)),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isInspect
                                ? const Color(0xFFDDD6FE)
                                : (isCollect ? const Color(0xFFA7F3D0) : const Color(0xFFBFDBFE)),
                          ),
                        ),
                        child: Text(
                          isInspect || isCollect
                              ? '${items.isEmpty ? 1 : items.length} ${(items.isEmpty || items.length == 1) ? "Device" : "Devices"}'
                              : '${items.isEmpty ? 1 : items.length} ${(items.isEmpty || items.length == 1) ? "Product" : "Products"}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isInspect
                                ? const Color(0xFF7C3AED)
                                : (isCollect ? const Color(0xFF059669) : const Color(0xFF1D4ED8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (items.isEmpty)
                    _buildSingleProductRow(
                      name: modelName,
                      storage: storage,
                      condition: condition,
                      imageUrl: imageUrl,
                      index: 1,
                      showBadge: false,
                    )
                  else
                    for (int i = 0; i < items.length; i++) ...[
                      if (i > 0) const Divider(height: 24, thickness: 1, color: Color(0xFFF1F5F9)),
                      _buildItemFromMap(items[i], i + 1, items.length > 1),
                    ],
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
            if (proofOfDeliveryUrl.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.verified_rounded, color: Color(0xFF16A34A), size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Proof of Delivery',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        proofOfDeliveryUrl,
                        width: double.infinity,
                        height: 220,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          height: 120,
                          color: const Color(0xFFF1F5F9),
                          alignment: Alignment.center,
                          child: const Text('Could not load proof photo', style: TextStyle(color: Color(0xFF64748B))),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
      bottomNavigationBar: isDelivered
          ? null
          : SafeArea(
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
                          final result = await showDialog<Map<String, dynamic>>(
                            context: context,
                            builder: (ctx) => RejectTaskDialog(taskID: taskID.isNotEmpty ? taskID : orderID),
                          );
                          if (result != null && result['confirmed'] == true) {
                            setState(() => _isActionLoading = true);
                            await TaskAssignmentService.updateTaskStatus(
                              taskID: taskID,
                              orderID: orderID,
                              scheduleID: scheduleID,
                              status: 'Rejected',
                              rejectionReason: result['reason'],
                              rejectionNotes: result['notes'],
                            );
                            widget.onTaskUpdated?.call();
                            if (!context.mounted) return;
                            Navigator.pop(context, {
                              'rejected': true,
                              'message': 'Delivery task is rejected',
                            });
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
                          if (isAssigned) {
                            setState(() => _isActionLoading = true);
                            await TaskAssignmentService.updateTaskStatus(
                              taskID: taskID,
                              orderID: orderID,
                              scheduleID: scheduleID,
                              status: 'In Progress',
                            );
                            widget.onTaskUpdated?.call();
                            if (!context.mounted) return;
                            setState(() {
                              _currentTask['taskStatus'] = 'In Progress';
                              _currentTask['scheduleStatus'] = 'ongoing';
                              _isActionLoading = false;
                            });

                            // Transition directly to Navigation Page
                            final completed = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => StaffNavigationPage(
                                  task: _currentTask,
                                  onTaskUpdated: widget.onTaskUpdated,
                                ),
                              ),
                            );

                            if (completed != null && completed != false) {
                              if (!context.mounted) return;
                              Navigator.pop(context, completed);
                            }
                          } else if (isShipping) {
                            // Already ongoing -> open navigation map directly
                            final completed = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => StaffNavigationPage(
                                  task: _currentTask,
                                  onTaskUpdated: widget.onTaskUpdated,
                                ),
                              ),
                            );

                            if (completed != null && completed != false) {
                              if (!context.mounted) return;
                              Navigator.pop(context, completed);
                            }
                          }
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
                        ? (isInspect
                            ? 'Start Inspection'
                            : (isCollect
                                ? 'Start Collect'
                                : 'Start Delivery'))
                        : isShipping
                            ? 'Continue Navigation'
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

  Widget _buildItemFromMap(dynamic rawItem, int index, bool showIndex) {
    if (rawItem is! Map) return const SizedBox.shrink();
    final item = rawItem;
    final brand = item['brand']?.toString() ?? '';
    final model = item['model']?.toString() ?? '';
    var name = '$brand $model'.trim();
    if (name.isEmpty) name = 'Electronic Device';
    final storage = item['storage']?.toString() ?? 'Standard';
    if (storage.isNotEmpty && storage != 'N/A' && storage != 'Standard') {
      name = name.replaceAll(RegExp('\\s*\\(${RegExp.escape(storage)}\\)', caseSensitive: false), '').trim();
    }
    name = name.replaceAll(RegExp(r'\s*\(\d+\s*(?:GB|TB)\)', caseSensitive: false), '').trim();
    final condition = item['condition']?.toString() ?? 'Good';
    final color = item['color']?.toString() ?? '';
    final imageUrl = item['imageUrl']?.toString();
    final productId = item['productID']?.toString();

    return _buildSingleProductRow(
      name: name,
      storage: storage,
      condition: condition,
      color: color,
      imageUrl: imageUrl,
      productId: productId,
      index: index,
      showBadge: showIndex,
    );
  }

  Widget _buildSingleProductRow({
    required String name,
    required String storage,
    required String condition,
    String? color,
    String? imageUrl,
    String? productId,
    required int index,
    required bool showBadge,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
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
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.devices, color: Color(0xFF94A3B8)),
                    )
                  : const Icon(Icons.devices, size: 30, color: Color(0xFF94A3B8)),
            ),
            if (showBadge)
              Positioned(
                top: 2,
                left: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '#$index',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                  if (productId != null && productId.isNotEmpty)
                    Flexible(
                      child: Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          productId,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF475569),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                name,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'STORAGE',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF94A3B8),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        storage,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF334155),
                        ),
                      ),
                    ],
                  ),
                  if (color != null && color.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'COLOR',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF94A3B8),
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          color,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ],
                    ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'CONDITION',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF94A3B8),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Row(
                        mainAxisSize: MainAxisSize.min,
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
                              fontSize: 12.5,
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
    );
  }
}

class RejectTaskDialog extends StatefulWidget {
  final String taskID;

  const RejectTaskDialog({
    super.key,
    required this.taskID,
  });

  @override
  State<RejectTaskDialog> createState() => _RejectTaskDialogState();
}

class _RejectTaskDialogState extends State<RejectTaskDialog> {
  String? _selectedReason;
  final TextEditingController _notesController = TextEditingController();

  final List<String> _reasons = [
    'Vehicle breakdown / technical issue',
    'Emergency / personal illness',
    'Severe traffic / road blockage',
    'Customer unreachable / wrong address',
    'Exceeds working capacity today',
    'Other reason'
  ];

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      elevation: 6,
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          constraints: const BoxConstraints(maxWidth: 380),
          child: Stack(
            children: [
              // Top-right cross close button
              Positioned(
                top: -6,
                right: -6,
                child: IconButton(
                  icon: const Icon(Icons.close, size: 20, color: Color(0xFF94A3B8)),
                  splashRadius: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Red Alert Warning Icon Container
                  Container(
                    width: 50,
                    height: 50,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFE4E6),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.warning_rounded,
                        color: Color(0xFFBE123C),
                        size: 26,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

              // Title
              const Text(
                'Reject Task',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 6),

              // Description
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF475569),
                    height: 1.35,
                  ),
                  children: [
                    const TextSpan(text: 'You are about to reject the assigned task\n'),
                    TextSpan(
                      text: '#${widget.taskID}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const TextSpan(text: '. Please provide a reason. This action cannot be undone.'),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              const Divider(color: Color(0xFFF1F5F9), thickness: 1, height: 1),
              const SizedBox(height: 12),

              // REJECTION REASON label
              Align(
                alignment: Alignment.centerLeft,
                child: const Text(
                  'REJECTION REASON',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              const SizedBox(height: 6),

              // Rejection Reason Dropdown
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _selectedReason,
                    hint: const Text(
                      'Select a reason...',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF475569), size: 20),
                    items: _reasons.map((r) {
                      return DropdownMenuItem<String>(
                        value: r,
                        child: Text(
                          r,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => _selectedReason = val),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ADDITIONAL NOTES label
              Align(
                alignment: Alignment.centerLeft,
                child: const Text(
                  'ADDITIONAL NOTES',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              const SizedBox(height: 6),

              // Additional Notes Text Area (3 lines max, compact)
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: TextField(
                  controller: _notesController,
                  maxLines: 2,
                  maxLength: 250,
                  buildCounter: (ctx, {required currentLength, required isFocused, maxLength}) => null,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    hintText: 'Provide any additional details...',
                    hintStyle: TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              const SizedBox(height: 3),

              // 0 / 250 counter
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${_notesController.text.length} / 250',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Confirm Reject Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _selectedReason == null
                      ? null
                      : () {
                          Navigator.pop(context, {
                            'confirmed': true,
                            'reason': _selectedReason,
                            'notes': _notesController.text.trim(),
                          });
                        },
                  icon: Icon(
                    Icons.cancel,
                    color: _selectedReason == null ? const Color(0xFF94A3B8) : Colors.white,
                    size: 16,
                  ),
                  label: Text(
                    'Confirm Reject',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: _selectedReason == null ? const Color(0xFF94A3B8) : Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFB91C1C),
                    disabledBackgroundColor: const Color(0xFFE2E8F0),
                    disabledForegroundColor: const Color(0xFF94A3B8),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Cancel Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
              ),
            ],
          ),
            ],
          ),
        ),
      ),
    );
  }
}


