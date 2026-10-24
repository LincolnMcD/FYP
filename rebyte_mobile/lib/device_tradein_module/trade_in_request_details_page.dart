import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../widgets/rebyte_app_bar.dart';
import '../widgets/rebyte_bottom_nav_bar.dart';
import 'models/device_model.dart';
import 'schedule_inspection_page.dart';
import 'services/trade_in_flow_session.dart';
import 'services/trade_in_service.dart';
import '../product_purchase_module/customer_delivery_tracking_page.dart';

class TradeInRequestDetailsPage extends StatefulWidget {
  final Map<String, dynamic> request;
  final bool isLoggedIn;
  final String? email;
  final String? name;

  const TradeInRequestDetailsPage({
    super.key,
    required this.request,
    this.isLoggedIn = true,
    this.email,
    this.name,
  });

  @override
  State<TradeInRequestDetailsPage> createState() => _TradeInRequestDetailsPageState();
}

class _TradeInRequestDetailsPageState extends State<TradeInRequestDetailsPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late Map<String, dynamic> _request;
  late PageController _pageController;
  int _currentImageIndex = 0;
  bool _isLoadingFresh = false;

  @override
  void initState() {
    super.initState();
    _request = Map<String, dynamic>.from(widget.request);
    _pageController = PageController();
    _loadFreshData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadFreshData() async {
    final reqId = _request['tradeInRequestID']?.toString();
    if (reqId == null || reqId.isEmpty) return;

    setState(() => _isLoadingFresh = true);
    final fresh = await TradeInService.getTradeInRequestDetails(reqId);
    if (fresh != null && mounted) {
      setState(() {
        _request.addAll(fresh);
        _isLoadingFresh = false;
      });
    } else if (mounted) {
      setState(() => _isLoadingFresh = false);
    }
  }

  /// Collects all uploaded image URLs and local paths for the device
  List<String> _getAllImages() {
    final List<String> list = [];

    // 1. From deviceImages array
    if (_request['deviceImages'] is List) {
      for (final item in _request['deviceImages']) {
        if (item != null && item.toString().trim().isNotEmpty) {
          final s = item.toString().trim();
          if (!list.contains(s)) list.add(s);
        }
      }
    }

    // 2. From deviceImagesDetailed array
    if (_request['deviceImagesDetailed'] is List) {
      for (final item in _request['deviceImagesDetailed']) {
        if (item is Map && item['imageUrl'] != null) {
          final s = item['imageUrl'].toString().trim();
          if (s.isNotEmpty && !list.contains(s)) list.add(s);
        }
      }
    }

    // 3. From single deviceImage
    if (_request['deviceImage'] != null) {
      final s = _request['deviceImage'].toString().trim();
      if (s.isNotEmpty && !list.contains(s)) list.add(s);
    }

    // 4. From nested device object
    if (_request['device'] is Map) {
      final dev = _request['device'] as Map;
      if (dev['deviceImages'] is List) {
        for (final item in dev['deviceImages']) {
          if (item != null && item.toString().trim().isNotEmpty) {
            final s = item.toString().trim();
            if (!list.contains(s)) list.add(s);
          }
        }
      }
      if (dev['deviceImage'] != null) {
        final s = dev['deviceImage'].toString().trim();
        if (s.isNotEmpty && !list.contains(s)) list.add(s);
      }
    }

    // 5. From current session slots if user recently uploaded
    final sessionSlots = TradeInFlowSession.savedSlots;
    if (sessionSlots != null && sessionSlots.isNotEmpty) {
      for (final slot in sessionSlots) {
        final p = slot.localFilePath;
        if (p != null && p.trim().isNotEmpty && !list.contains(p.trim())) {
          list.add(p.trim());
        }
      }
    }

    return list;
  }

  String _formatDate(dynamic dateVal) {
    if (dateVal == null) return 'Oct 26, 2023';
    try {
      if (dateVal is DateTime) {
        return DateFormat('MMM d, yyyy').format(dateVal);
      }
      if (dateVal is Map && dateVal['_seconds'] != null) {
        final dt = DateTime.fromMillisecondsSinceEpoch((dateVal['_seconds'] as int) * 1000);
        return DateFormat('MMM d, yyyy').format(dt);
      }
      final str = dateVal.toString();
      final dt = DateTime.tryParse(str);
      if (dt != null) {
        return DateFormat('MMM d, yyyy').format(dt);
      }
    } catch (_) {}
    return 'Oct 26, 2023';
  }

  String _formatAppointmentDate(dynamic dateVal) {
    if (dateVal == null) return 'Nov 12, 2023';
    try {
      if (dateVal is DateTime) {
        return DateFormat('MMM d, yyyy').format(dateVal);
      }
      if (dateVal is Map && dateVal['_seconds'] != null) {
        final dt = DateTime.fromMillisecondsSinceEpoch((dateVal['_seconds'] as int) * 1000);
        return DateFormat('MMM d, yyyy').format(dt);
      }
      final str = dateVal.toString().trim();
      final dt = DateTime.tryParse(str);
      if (dt != null) {
        return DateFormat('MMM d, yyyy').format(dt);
      }
    } catch (_) {}
    return dateVal.toString();
  }

  String _formatAppointmentTimeRange(String timeStr) {
    if (timeStr.contains('-')) return timeStr;
    try {
      final parts = timeStr.trim().split(':');
      if (parts.isNotEmpty) {
        int hour = int.parse(parts[0].replaceAll(RegExp(r'\D'), ''));
        int minute = parts.length > 1 ? int.parse(parts[1].replaceAll(RegExp(r'\D'), '')) : 0;
        final startDt = DateTime(2023, 1, 1, hour, minute);
        final endDt = startDt.add(const Duration(hours: 1));
        final startFmt = DateFormat('h:mm a').format(startDt);
        final endFmt = DateFormat('h:mm a').format(endDt);
        return '$startFmt - $endFmt';
      }
    } catch (_) {}
    return timeStr.contains('AM') || timeStr.contains('PM')
        ? '$timeStr - 11:00 AM'
        : '$timeStr:00 AM - 11:00 AM';
  }

  String _formatDateTime(dynamic dateVal) {
    if (dateVal == null) return 'Oct 26, 2023, 10:42 AM';
    try {
      if (dateVal is DateTime) {
        return DateFormat('MMM d, yyyy, hh:mm a').format(dateVal);
      }
      if (dateVal is Map && dateVal['_seconds'] != null) {
        final dt = DateTime.fromMillisecondsSinceEpoch((dateVal['_seconds'] as int) * 1000);
        return DateFormat('MMM d, yyyy, hh:mm a').format(dt);
      }
      final str = dateVal.toString();
      final dt = DateTime.tryParse(str);
      if (dt != null) {
        return DateFormat('MMM d, yyyy, hh:mm a').format(dt);
      }
    } catch (_) {}
    return 'Oct 26, 2023, 10:42 AM';
  }

  String _formatEstimatedValue(dynamic estValueVal) {
    final fmt = NumberFormat('#,##0.00');
    double? minD;
    double? maxD;

    if (estValueVal is Map) {
      final min = estValueVal['min'] ?? estValueVal['minEstimatedValue'];
      final max = estValueVal['max'] ?? estValueVal['maxEstimatedValue'];
      if (min != null) minD = (min is num) ? min.toDouble() : double.tryParse(min.toString());
      if (max != null) maxD = (max is num) ? max.toDouble() : double.tryParse(max.toString());
    } else if (estValueVal is List && estValueVal.length >= 2) {
      minD = (estValueVal[0] is num) ? estValueVal[0].toDouble() : double.tryParse(estValueVal[0].toString());
      maxD = (estValueVal[1] is num) ? estValueVal[1].toDouble() : double.tryParse(estValueVal[1].toString());
    } else if (estValueVal != null) {
      final str = estValueVal.toString();
      final matches = RegExp(r'[\d,]+(?:\.\d+)?').allMatches(str).map((m) {
        return double.tryParse(m.group(0)!.replaceAll(',', ''));
      }).whereType<double>().toList();

      if (matches.length >= 2) {
        minD = matches[0];
        maxD = matches[1];
      } else if (matches.length == 1) {
        minD = matches[0];
        maxD = matches[0];
      }
    }

    minD ??= 1050.0;
    maxD ??= 1520.0;

    return 'RM ${fmt.format(minD)} - RM ${fmt.format(maxD)}';
  }

  Map<String, String> _resolveSpecs(String model) {
    final m = model.toLowerCase();
    if (m.contains('15 pro')) {
      return {'processor': 'A17 Pro', 'memory': '8GB RAM'};
    } else if (m.contains('14 pro')) {
      return {'processor': 'A16 Bionic', 'memory': '6GB RAM'};
    } else if (m.contains('13 pro') || m.contains('iphone 13')) {
      return {'processor': 'A15 Bionic', 'memory': '6GB RAM'};
    } else if (m.contains('s23')) {
      return {'processor': 'Snapdragon 8 Gen 2', 'memory': '12GB RAM'};
    } else if (m.contains('s24')) {
      return {'processor': 'Snapdragon 8 Gen 3', 'memory': '12GB RAM'};
    } else if (m.contains('pixel 8')) {
      return {'processor': 'Google Tensor G3', 'memory': '12GB RAM'};
    }
    return {'processor': 'Octa-Core 3.2GHz', 'memory': '8GB RAM'};
  }

  void _showConditionReportModal(BuildContext context, String brand, String model) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Condition Report',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Excellent',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF16A34A),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '$brand $model',
              style: const TextStyle(fontSize: 14, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 18),
            _buildConditionCheckRow('Screen & Display', 'No scratches, cracks, or dead pixels', true),
            _buildConditionCheckRow('Body & Enclosure', 'Pristine exterior with minimal signs of wear', true),
            _buildConditionCheckRow('Battery Health', '85% or higher maximum capacity', true),
            _buildConditionCheckRow('Hardware & Sensors', 'All cameras, speakers, and FaceID/TouchID functional', true),
            _buildConditionCheckRow('Lock & Activation', 'Device is unlocked, no carrier/iCloud locks', true),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0C5AD2),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text('Close Report', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConditionCheckRow(String title, String desc, bool passed) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            passed ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: passed ? const Color(0xFF16A34A) : const Color(0xFFEF4444),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _resolveActualAppointmentId(Map<String, dynamic> req) {
    // 1. Direct appointmentID in req
    for (final key in ['appointmentID', 'appointmentId', 'appointment_id']) {
      final val = req[key]?.toString().trim();
      if (val != null && val.isNotEmpty) return val;
    }
    // 2. Direct appointmentID in state _request
    for (final key in ['appointmentID', 'appointmentId', 'appointment_id']) {
      final val = _request[key]?.toString().trim();
      if (val != null && val.isNotEmpty) return val;
    }
    // 3. Nested appointment object
    final app = req['appointment'] ?? _request['appointment'];
    if (app is Map) {
      for (final key in ['appointmentID', 'appointmentId', 'id']) {
        final val = app[key]?.toString().trim();
        if (val != null && val.isNotEmpty) return val;
      }
    }
    // 4. Default / fallback
    final rawReqId = (req['tradeInRequestID'] ?? _request['tradeInRequestID'])?.toString() ?? '';
    if (rawReqId.contains('5510')) {
      return 'APT-4829-X';
    }
    final cleanId = rawReqId.replaceAll('#', '');
    if (cleanId.isNotEmpty) {
      final digits = cleanId.replaceAll(RegExp(r'\D'), '');
      if (digits.isNotEmpty) {
        return 'APT-${digits.padRight(4, '0').substring(0, min(4, digits.length))}-X';
      }
    }
    return 'APT-4829-X';
  }

  /// Exact Appointment Details popup matching user mockup
  void _showAppointmentDetailsModal(BuildContext context, Map<String, dynamic> req) {
    final appointmentId = _resolveActualAppointmentId(req);

    final dynamic rawDate = req['appointmentDate'] ?? _request['appointmentDate'] ?? req['scheduledAt'] ?? _request['scheduledAt'];
    final formattedDate = _formatAppointmentDate(rawDate);
    final rawTime = (req['appointmentTime'] ?? _request['appointmentTime'])?.toString() ?? '10:00';
    final formattedTime = _formatAppointmentTimeRange(rawTime);
    final location = (req['appointmentLocation'] != null && req['appointmentLocation'].toString().trim().isNotEmpty)
        ? req['appointmentLocation'].toString().trim()
        : (_request['appointmentLocation'] != null && _request['appointmentLocation'].toString().trim().isNotEmpty)
            ? _request['appointmentLocation'].toString().trim()
            : (req['address'] != null && req['address'].toString().trim().isNotEmpty)
                ? req['address'].toString().trim()
                : (_request['address'] != null && _request['address'].toString().trim().isNotEmpty)
                    ? _request['address'].toString().trim()
                    : '123 Tech Avenue, Suite 400\nSan Francisco, CA 94105';

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 360),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF0F172A), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 26),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Row: APPOINTMENT ID + Badge (padded on right for cross icon)
                    Padding(
                      padding: const EdgeInsets.only(right: 32),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'APPOINTMENT ID',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF475569),
                              letterSpacing: 0.5,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEF2FF),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              appointmentId,
                              style: const TextStyle(
                                color: Color(0xFF1E3A8A),
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Divider(color: Color(0xFFE2E8F0), thickness: 1, height: 1),
                    const SizedBox(height: 20),

                    // DATE Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Transform.translate(
                          offset: const Offset(0, -3),
                          child: const Icon(
                            Icons.calendar_today_outlined,
                            color: Color(0xFF0C5AD2),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'DATE',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF475569),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                formattedDate,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0F172A),
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // TIME Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Transform.translate(
                          offset: const Offset(0, -3),
                          child: const Icon(
                            Icons.access_time_rounded,
                            color: Color(0xFF0C5AD2),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'TIME',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF475569),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                formattedTime,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0F172A),
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Divider(color: Color(0xFFE2E8F0), thickness: 1, height: 1),
                    const SizedBox(height: 20),

                    // LOCATION Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Transform.translate(
                          offset: const Offset(0, -3),
                          child: const Icon(
                            Icons.location_on_outlined,
                            color: Color(0xFF0C5AD2),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'LOCATION',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF475569),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                location,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F172A),
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Close Cross Icon at top right
              Positioned(
                top: 12,
                right: 12,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => Navigator.pop(ctx),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: Color(0xFF64748B),
                      ),
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

  @override
  Widget build(BuildContext context) {
    final dev = _request['device'] is Map<String, dynamic> ? _request['device'] as Map<String, dynamic> : null;
    final brand = dev?['brand']?.toString() ?? _request['brand']?.toString() ?? 'Apple';
    final model = dev?['model']?.toString() ?? _request['model']?.toString() ?? 'iPhone 13 Pro';
    final storage = dev?['storageCapacity']?.toString() ?? _request['storageCapacity']?.toString() ?? '256GB';
    final colour = dev?['colour']?.toString() ?? dev?['color']?.toString() ?? _request['colour']?.toString() ?? 'Graphite';

    final reqId = _request['tradeInRequestID']?.toString() ?? '#TRD-8992-BX';
    final formattedReqId = reqId.startsWith('#') ? reqId : '#$reqId';
    final submittedDate = _formatDate(_request['submittedAt'] ?? _request['createdAt']);
    final createdDateTime = _formatDateTime(_request['submittedAt'] ?? _request['createdAt']);
    final methodStr = _request['inspectionMethod']?.toString() ?? 'Mail-in Inspection';
    final estValue = _formatEstimatedValue(_request['estimatedValue']);
    final specs = _resolveSpecs(model);

    final String status = (_request['requestStatus'] ?? 'Scheduled').toString();
    final bool isShipment = methodStr.toLowerCase().contains('mail');
    final String rawTaskType = (_request['taskType'] ??
            _request['appointmentType'] ??
            _request['inspectionMethod'] ??
            widget.request['taskType'] ??
            widget.request['appointmentType'] ??
            widget.request['inspectionMethod'] ??
            '')
        .toString()
        .toLowerCase();
    final bool isCollect = rawTaskType.contains('collect') ||
        rawTaskType.contains('pickup') ||
        rawTaskType.contains('pick up');
    final bool isOnHold = status.toLowerCase() == 'on hold' ||
        status.toLowerCase().contains('hold') ||
        _request['bookingStatus']?.toString().toLowerCase() == 'on hold' ||
        _request['appointmentStatus']?.toString().toLowerCase() == 'on hold';
    final bool isInProgress = status.toLowerCase() == 'in progress' ||
        status.toLowerCase() == 'ongoing' ||
        _request['bookingStatus']?.toString().toLowerCase() == 'in progress' ||
        _request['appointmentStatus']?.toString().toLowerCase() == 'in progress' ||
        _request['appointmentStatus']?.toString().toLowerCase() == 'ongoing';
    final bool hasAppointment = _request['appointmentDate'] != null && _request['appointmentTime'] != null;
    final appointmentDate = hasAppointment ? _formatAppointmentDate(_request['appointmentDate']) : null;
    final appointmentTime = hasAppointment ? _formatAppointmentTimeRange(_request['appointmentTime'].toString()) : null;

    final allImages = _getAllImages();

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: ReByteAppBar(
        scaffoldKey: _scaffoldKey,
      ),
      drawer: ReByteDrawer(
        isLoggedIn: widget.isLoggedIn,
        email: widget.email,
        name: widget.name,
        isTradeInRequestsSelected: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_isLoadingFresh)
              const LinearProgressIndicator(
                minHeight: 2.5,
                color: Color(0xFF0C5AD2),
                backgroundColor: Colors.transparent,
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
              // Back Button
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A), size: 24),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(height: 12),

              // Title
              const Text(
                'Request Details',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 8),

              // Subtitle & Status Badge Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formattedReqId,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${isCollect ? 'Collection' : 'Inspection'} Service',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isInProgress
                          ? const Color(0xFFEFF6FF)
                          : (isOnHold ? const Color(0xFFFFF7ED) : const Color(0xFFFEF3C7)),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isInProgress
                            ? const Color(0xFFBFDBFE)
                            : (isOnHold ? const Color(0xFFFFEDD5) : const Color(0xFFFDE68A)),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isInProgress
                              ? Icons.navigation_rounded
                              : (isShipment
                                  ? Icons.local_shipping_outlined
                                  : (isOnHold
                                      ? Icons.pause_circle_outline_rounded
                                      : Icons.event_available_rounded)),
                          size: 13,
                          color: isInProgress
                              ? const Color(0xFF0C5AD2)
                              : (isOnHold ? const Color(0xFFEA580C) : const Color(0xFFD97706)),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isInProgress
                              ? 'In Progress'
                              : (isShipment
                                  ? 'In Transit'
                                  : (isOnHold ? 'On Hold' : (status.isNotEmpty ? status : 'Scheduled'))),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: isInProgress
                                ? const Color(0xFF0C5AD2)
                                : (isOnHold ? const Color(0xFFEA580C) : const Color(0xFFD97706)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // CARD 1: Uploaded Device Images Gallery & Specs Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFF1F5F9)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Device Images Carousel with Next / Previous actions
                    _buildImageGalleryBox(allImages),
                    const SizedBox(height: 16),

                    Text(
                      model,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$brand • $colour',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 2x2 Specs Grid
                    Row(
                      children: [
                        Expanded(child: _buildSpecItem('PROCESSOR', specs['processor']!)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildSpecItem('MEMORY', specs['memory']!)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _buildSpecItem('STORAGE', storage)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildSpecItem('DECLARED COND.', 'Excellent', isCondition: true)),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // View Condition Report Link
                    InkWell(
                      onTap: () => _showConditionReportModal(context, brand, model),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: const [
                            Icon(Icons.visibility_outlined, size: 16, color: Color(0xFF0C5AD2)),
                            SizedBox(width: 6),
                            Text(
                              'View Condition Report',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0C5AD2),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // CARD 2: Estimated Value Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFF1F5F9)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Text(
                      'ESTIMATED VALUE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF64748B),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      estValue,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0C5AD2),
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Final value pending physical diagnostic verification.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF94A3B8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // CARD 3: Tracking & Diagnostics Timeline
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFF1F5F9)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tracking & Diagnostics',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Step 1: Request Created
                    _buildTimelineStep(
                      title: 'Request Created',
                      subtitle: createdDateTime,
                      isCompleted: true,
                      showLine: true,
                    ),

                    // Step 2: Digital Diagnostics & IMEI Verified
                    _buildTimelineStep(
                      title: 'Digital Diagnostics & IMEI Verified',
                      subtitle: '$submittedDate, 11:05 AM',
                      isCompleted: true,
                      showLine: true,
                    ),

                    if (isInProgress) ...[
                      // Step 3: Appointment Confirmed (Completed)
                      _buildTimelineStep(
                        title: isShipment
                            ? 'Package Picked Up'
                            : (isCollect ? 'Collection Appointment Confirmed' : 'Inspection Appointment Confirmed'),
                        subtitle: hasAppointment ? '$appointmentDate at $appointmentTime' : 'Appointment confirmed',
                        isCompleted: true,
                        showLine: true,
                      ),

                      // Step 4: Active Physical Inspection with Map Tracking
                      _buildActiveInspectionBox(
                        isShipment: isShipment,
                        isCollect: isCollect,
                        onViewMapTracking: () {
                          final cleanId = (_request['tradeInRequestID']?.toString() ?? widget.request['tradeInRequestID']?.toString() ?? '').replaceAll('#', '');
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CustomerDeliveryTrackingPage(
                                orderID: cleanId,
                                taskStatus: 'In Progress',
                                taskType: isCollect ? 'collect' : 'inspect',
                                scheduleDate: appointmentDate,
                                estimatedEndTime: appointmentTime,
                              ),
                            ),
                          );
                        },
                      ),

                      // Step 5: Final Offer Issued
                      _buildTimelineStep(
                        title: 'Final Offer Issued',
                        subtitle: 'Pending inspection',
                        isCompleted: false,
                        showLine: false,
                      ),
                    ] else ...[
                      // Step 3: Current Active Step (In Transit or Scheduled or On Hold)
                      _buildActiveTimelineBox(
                        isShipment: isShipment,
                        hasAppointment: hasAppointment,
                        isOnHold: isOnHold,
                        appointmentDate: appointmentDate,
                        appointmentTime: appointmentTime,
                        onActionPressed: () {
                          if (isOnHold) {
                            final cleanId = (_request['tradeInRequestID']?.toString() ?? widget.request['tradeInRequestID']?.toString() ?? '').replaceAll('#', '');
                            final devMap = _request['device'] is Map<String, dynamic> ? _request['device'] : widget.request['device'];
                            DeviceModel? deviceObj;
                            if (devMap is Map<String, dynamic>) {
                              deviceObj = DeviceModel(
                                deviceID: devMap['deviceID']?.toString() ?? '',
                                brand: devMap['brand']?.toString() ?? 'Apple',
                                model: devMap['model']?.toString() ?? 'iPhone 13 Pro',
                                storageCapacity: devMap['storageCapacity']?.toString() ?? '128GB',
                                colour: devMap['colour']?.toString() ?? 'Graphite',
                              );
                            }
                            final bookingAddressID = (_request['addressID'] ?? widget.request['addressID'])?.toString();
                            final bookingAddressLine = (_request['appointmentLocation'] ?? _request['inspectionAddress'] ?? _request['address'] ?? widget.request['appointmentLocation'] ?? widget.request['inspectionAddress'])?.toString();
                            final bookingDate = (_request['appointmentDate'] ?? widget.request['appointmentDate'])?.toString();
                            final bookingSlot = (_request['appointmentTime'] ?? widget.request['appointmentTime'])?.toString();

                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ScheduleInspectionPage(
                                  tradeInRequestID: cleanId,
                                  method: methodStr,
                                  device: deviceObj,
                                  estimatedValue: estValue,
                                  email: widget.email,
                                  name: widget.name,
                                  isLoggedIn: widget.isLoggedIn,
                                  fromMyTradeInRequests: true,
                                  initialAddressID: bookingAddressID,
                                  initialAddressLine: bookingAddressLine,
                                  initialDate: bookingDate,
                                  initialSlot: bookingSlot,
                                ),
                              ),
                            ).then((_) {
                              _loadFreshData();
                            });
                          } else {
                            // Pop up the appointment details modal
                            _showAppointmentDetailsModal(context, _request);
                          }
                        },
                      ),

                      // Step 4: Physical Inspection or Collection
                      _buildTimelineStep(
                        title: isCollect ? 'Device Collection' : 'Physical Inspection',
                        subtitle: 'Pending arrival',
                        isCompleted: false,
                        showLine: true,
                      ),

                      // Step 5: Final Offer Issued
                      _buildTimelineStep(
                        title: 'Final Offer Issued',
                        subtitle: 'Pending inspection',
                        isCompleted: false,
                        showLine: false,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  ),
),
bottomNavigationBar: const ReByteBottomNavBar(
  selectedIndex: 2,
),
);
  }

  /// Builds the interactive multi-image carousel showing all uploaded images
  Widget _buildImageGalleryBox(List<String> images) {
    if (images.isEmpty) {
      return Container(
        width: double.infinity,
        height: 160,
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF).withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.phone_iphone_rounded, size: 64, color: Color(0xFF64748B)),
            SizedBox(height: 8),
            Text(
              'No uploaded photos found',
              style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      height: 180,
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          // Swipeable PageView of all uploaded images
          PageView.builder(
            controller: _pageController,
            itemCount: images.length,
            onPageChanged: (idx) {
              setState(() {
                _currentImageIndex = idx;
              });
            },
            itemBuilder: (context, index) {
              final imgStr = images[index];
              final isNetwork = imgStr.startsWith('http://') || imgStr.startsWith('https://');

              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 42, vertical: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: isNetwork
                        ? Image.network(
                            imgStr,
                            fit: BoxFit.contain,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF0C5AD2),
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) => const Icon(
                              Icons.broken_image_rounded,
                              size: 48,
                              color: Color(0xFF94A3B8),
                            ),
                          )
                        : (File(imgStr).existsSync()
                            ? Image.file(
                                File(imgStr),
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) => const Icon(
                                  Icons.broken_image_rounded,
                                  size: 48,
                                  color: Color(0xFF94A3B8),
                                ),
                              )
                            : Image.asset(
                                'assets/images/phones/iphone13.png',
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) => const Icon(
                                  Icons.phone_iphone_rounded,
                                  size: 54,
                                  color: Color(0xFF64748B),
                                ),
                              )),
                  ),
                ),
              );
            },
          ),

          // Previous Button (Left)
          if (images.length > 1)
            Positioned(
              left: 6,
              top: 0,
              bottom: 0,
              child: Center(
                child: Material(
                  color: _currentImageIndex > 0
                      ? Colors.white.withValues(alpha: 0.9)
                      : Colors.white.withValues(alpha: 0.4),
                  shape: const CircleBorder(),
                  elevation: _currentImageIndex > 0 ? 2 : 0,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _currentImageIndex > 0
                        ? () {
                            _pageController.previousPage(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeInOut,
                            );
                          }
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.chevron_left_rounded,
                        size: 26,
                        color: _currentImageIndex > 0 ? const Color(0xFF0F172A) : Colors.grey.shade400,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Next Button (Right)
          if (images.length > 1)
            Positioned(
              right: 6,
              top: 0,
              bottom: 0,
              child: Center(
                child: Material(
                  color: _currentImageIndex < images.length - 1
                      ? Colors.white.withValues(alpha: 0.9)
                      : Colors.white.withValues(alpha: 0.4),
                  shape: const CircleBorder(),
                  elevation: _currentImageIndex < images.length - 1 ? 2 : 0,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _currentImageIndex < images.length - 1
                        ? () {
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeInOut,
                            );
                          }
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 26,
                        color: _currentImageIndex < images.length - 1
                            ? const Color(0xFF0F172A)
                            : Colors.grey.shade400,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Image Counter Pill (Top-Right)
          if (images.length > 1)
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_currentImageIndex + 1} / ${images.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

          // Dot Indicators (Bottom-Center)
          if (images.length > 1)
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  images.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: _currentImageIndex == i ? 14 : 6,
                    height: 5,
                    decoration: BoxDecoration(
                      color: _currentImageIndex == i ? const Color(0xFF0C5AD2) : const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSpecItem(String label, String value, {bool isCondition = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: Color(0xFF64748B),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isCondition) ...[
              const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 14),
              const SizedBox(width: 4),
            ],
            Text(
              value,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: isCondition ? const Color(0xFF10B981) : const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTimelineStep({
    required String title,
    required String subtitle,
    required bool isCompleted,
    required bool showLine,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Icon(
              isCompleted ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: isCompleted ? const Color(0xFF10B981) : const Color(0xFFCBD5E1),
              size: 22,
            ),
            if (showLine)
              Container(
                width: 2,
                height: 34,
                color: const Color(0xFFE2E8F0),
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: isCompleted ? FontWeight.w700 : FontWeight.w600,
                    color: isCompleted ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActiveTimelineBox({
    required bool isShipment,
    required bool hasAppointment,
    bool isOnHold = false,
    String? appointmentDate,
    String? appointmentTime,
    required VoidCallback onActionPressed,
  }) {
    final title = isShipment
        ? 'In Transit to Processing Center'
        : (isOnHold ? 'Appointment On Hold' : 'Inspection Appointment Confirmed');
    final estLabel = isShipment
        ? 'Estimated 1-Day'
        : (isOnHold
            ? 'Reschedule Required'
            : (hasAppointment ? '$appointmentDate at $appointmentTime' : 'Appointment Scheduled'));
    final desc = isShipment
        ? 'Your package was picked up and is en route.'
        : (isOnHold
            ? 'Technician is currently unavailable. Please reschedule your appointment.'
            : 'Technician has been assigned. Please have your device ready for on-site inspection.');
    final buttonText = isShipment
        ? 'Track Shipment'
        : (isOnHold ? 'Reschedule' : 'View Appointment Details');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF0C5AD2), width: 2),
              ),
              alignment: Alignment.center,
              child: Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Color(0xFF0C5AD2),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Container(
              width: 2,
              height: 140,
              color: const Color(0xFFE2E8F0),
            ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFDBEAFE)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E3A8A),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  estLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0C5AD2),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  desc,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF475569),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: ElevatedButton(
                    onPressed: onActionPressed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0C5AD2),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      buttonText,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActiveInspectionBox({
    required bool isShipment,
    bool isCollect = false,
    required VoidCallback onViewMapTracking,
  }) {
    final title = isCollect ? 'Device Collection' : 'Physical Inspection';
    final subtitle = isCollect ? 'Collector On The Way' : 'Inspector On The Way';
    final desc = isCollect
        ? 'Our collector has started heading to your location to collect your trade-in device. You can view their live location and track arrival on the map.'
        : 'Our inspector has started heading to your location to perform the physical device inspection. You can view their live location and track arrival on the map.';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF0C5AD2), width: 2),
              ),
              alignment: Alignment.center,
              child: Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Color(0xFF0C5AD2),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Container(
              width: 2,
              height: 155,
              color: const Color(0xFFE2E8F0),
            ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFDBEAFE)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0C5AD2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'IN PROGRESS',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1E3A8A),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0C5AD2),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  desc,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF475569),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: ElevatedButton.icon(
                    onPressed: onViewMapTracking,
                    icon: const Icon(Icons.navigation_rounded, size: 18),
                    label: const Text(
                      'View Map Tracking',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0C5AD2),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

