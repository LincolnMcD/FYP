import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'widgets/staff_app_bar_and_drawer.dart';
import 'staff_device_inspection_specs_page.dart';
import '../device_tradein_module/services/trade_in_service.dart';

class PerformDeviceInspectionPage extends StatefulWidget {
  final Map<String, dynamic> task;
  final VoidCallback? onTaskUpdated;

  const PerformDeviceInspectionPage({
    super.key,
    required this.task,
    this.onTaskUpdated,
  });

  @override
  State<PerformDeviceInspectionPage> createState() =>
      _PerformDeviceInspectionPageState();
}

class _PerformDeviceInspectionPageState
    extends State<PerformDeviceInspectionPage> {
  String? _imageUrl;

  @override
  void initState() {
    super.initState();
    final items = widget.task['items'] as List? ?? [];
    _imageUrl = widget.task['imageUrl']?.toString() ??
        widget.task['deviceImageUrl']?.toString() ??
        (items.isNotEmpty && items[0] is Map ? items[0]['imageUrl']?.toString() : null);

    if (_imageUrl == null || _imageUrl!.isEmpty) {
      _fetchCloudImage();
    }
  }

  Future<void> _fetchCloudImage() async {
    final trId = widget.task['tradeInRequestID']?.toString() ??
        widget.task['tradeInID']?.toString() ??
        widget.task['orderID']?.toString() ??
        '';
    if (trId.isEmpty) return;

    final details = await TradeInService.getTradeInRequestDetails(trId);
    if (details != null && mounted) {
      final img = details['deviceImage']?.toString() ??
          (details['deviceImages'] is List && (details['deviceImages'] as List).isNotEmpty
              ? details['deviceImages'][0].toString()
              : null);
      if (img != null && img.isNotEmpty) {
        setState(() {
          _imageUrl = img;
          widget.task['imageUrl'] = img;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final onTaskUpdated = widget.onTaskUpdated;
    final rawDeviceModel = task['deviceModel']?.toString() ??
        task['model']?.toString() ??
        'iPhone 13 Pro';
    final storage = task['storage']?.toString() ?? '256GB';
    final color = task['color']?.toString() ?? task['colour']?.toString() ?? 'Graphite';
    final reportedCondition = task['reportedCondition']?.toString() ?? 'Good (Minor Scratches)';

    // Strip storage capacity from model name if already present (e.g. "(128GB)" or "(256GB)")
    // because specsLabel already renders a dedicated small label for storage & color.
    String deviceModel = rawDeviceModel;
    if (storage.isNotEmpty && deviceModel.toLowerCase().contains('(${storage.toLowerCase()})')) {
      deviceModel = deviceModel.replaceAll(RegExp('\\(${RegExp.escape(storage)}\\)', caseSensitive: false), '').trim();
    } else {
      deviceModel = deviceModel.replaceAll(RegExp(r'\s*\(\d+\s*(?:GB|TB)\)', caseSensitive: false), '').trim();
    }

    final rawEstimate = task['estimatedValue'] ??
        task['estimatedValueRange'] ??
        task['tradeInEstimate'] ??
        task['totalAmount'] ??
        task['price'] ??
        task['offeredPrice'] ??
        (task['items'] is List && (task['items'] as List).isNotEmpty
            ? (task['items'][0]['estimatedValue'] ?? task['items'][0]['tradeInEstimate'] ?? task['items'][0]['price'])
            : null);
    final estimateRange = NumberFormatUtils.formatEstimateRange(rawEstimate);
    final imei = task['imei']?.toString() ??
        task['imeiNum']?.toString() ??
        '3548 9201 8847 112';
    final customerName = task['customerName']?.toString() ?? 'Alex Mercer';
    final customerEmail = task['customerEmail']?.toString() ?? 'alex.mercer@email.com';
    final customerPhone = task['customerPhone']?.toString() ?? '(555) 019-2834';
    final imageUrl = _imageUrl ?? task['imageUrl']?.toString() ?? '';

    final specsLabel = [storage, color].where((s) => s.isNotEmpty).join(' • ');

    final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();

    return Scaffold(
      key: scaffoldKey,
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: StaffAppBar(scaffoldKey: scaffoldKey),
      drawer: const StaffDrawer(selectedIndex: 2),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back Button & Page Title
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B)),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Perform Device Inspection',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),

              // Device Inspection Card
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Device Photo Preview
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      child: Container(
                        height: 200,
                        width: double.infinity,
                        color: const Color(0xFFF1F5F9),
                        child: imageUrl.isNotEmpty
                            ? Image.network(
                                imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => _buildPlaceholderPhoto(),
                              )
                            : _buildPlaceholderPhoto(),
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title & Status Badge
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Text(
                                  deviceModel,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFFDE68A)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(Icons.assignment_outlined, size: 14, color: Color(0xFFD97706)),
                                    SizedBox(width: 4),
                                    Text(
                                      'Pending Inspection',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFFD97706),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            specsLabel,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(height: 18),

                          // Two Highlight Boxes (Reported Condition & Trade-in Estimate)
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Reported Condition',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        reportedCondition,
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF1E293B),
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Trade-in Estimate',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        estimateRange[0],
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w900,
                                          color: Color(0xFF0C5AD2),
                                          height: 1.25,
                                        ),
                                      ),
                                      Text(
                                        estimateRange[1],
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w900,
                                          color: Color(0xFF0C5AD2),
                                          height: 1.25,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),

                          const Divider(color: Color(0xFFE2E8F0), thickness: 1, height: 1),
                          const SizedBox(height: 14),

                          // IMEI Row
                          Row(
                            children: [
                              const Icon(
                                Icons.qr_code_scanner_rounded,
                                size: 18,
                                color: Color(0xFF0F172A),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'IMEI: $imei',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F172A),
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Customer Card
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.person_outline_rounded, color: Color(0xFF0C5AD2), size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Customer',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0C5AD2),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      customerName,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.email_outlined, size: 16, color: Color(0xFF64748B)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            customerEmail,
                            style: const TextStyle(
                              fontSize: 13.5,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.phone_outlined, size: 16, color: Color(0xFF64748B)),
                        const SizedBox(width: 8),
                        Text(
                          customerPhone,
                          style: const TextStyle(
                            fontSize: 13.5,
                            color: Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Start Inspection Button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () async {
                      final res = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          settings: const RouteSettings(name: 'StaffDeviceInspectionSpecsPage'),
                          builder: (_) => StaffDeviceInspectionSpecsPage(
                            task: task,
                            onTaskUpdated: onTaskUpdated,
                          ),
                        ),
                      );
                      if (res != null && context.mounted) {
                        onTaskUpdated?.call();
                        Navigator.pop(context, res);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0043CE),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Text(
                          'Start inspection',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward, color: Colors.white, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const StaffBottomNavBar(currentIndex: 2),
    );
  }

  Widget _buildPlaceholderPhoto() {
    return Container(
      color: const Color(0xFF0F172A),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.phone_iphone_rounded, size: 56, color: Colors.white70),
            SizedBox(height: 8),
            Text(
              'Inspection Device Preview',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NumberFormatUtils {
  static List<String> formatEstimateRange(dynamic value) {
    final fmt = NumberFormat('#,##0.00');
    double? minD;
    double? maxD;

    if (value is Map) {
      final min = value['min'] ?? value['minEstimatedValue'];
      final max = value['max'] ?? value['maxEstimatedValue'];
      if (min != null) minD = (min is num) ? min.toDouble() : double.tryParse(min.toString());
      if (max != null) maxD = (max is num) ? max.toDouble() : double.tryParse(max.toString());
    } else if (value is List && value.length >= 2) {
      minD = (value[0] is num) ? value[0].toDouble() : double.tryParse(value[0].toString());
      maxD = (value[1] is num) ? value[1].toDouble() : double.tryParse(value[1].toString());
    } else if (value != null) {
      final str = value.toString();
      final matches = RegExp(r'[\d,]+(?:\.\d+)?').allMatches(str).map((m) {
        return double.tryParse(m.group(0)!.replaceAll(',', ''));
      }).whereType<double>().toList();

      if (matches.length >= 2) {
        minD = matches[0];
        maxD = matches[1];
      } else if (matches.length == 1 && matches[0] > 0) {
        minD = matches[0];
        maxD = matches[0];
      }
    }

    minD ??= 2340.50;
    maxD ??= 2355.30;

    if (minD == maxD && minD > 0) {
      minD = (minD - 14.80 > 0) ? minD - 14.80 : minD;
    }

    if (minD > maxD) {
      final t = minD;
      minD = maxD;
      maxD = t;
    }

    return [
      'RM  ${fmt.format(minD)} -',
      'RM  ${fmt.format(maxD)}',
    ];
  }

  static String formatSingleCurrency(dynamic value) {
    if (value == null) return '1,425.00';
    double numVal = 0.0;
    if (value is num) {
      numVal = value.toDouble();
    } else if (value is Map) {
      final maxVal = value['max'] ?? value['maxEstimatedValue'];
      final minVal = value['min'] ?? value['minEstimatedValue'];
      final picked = maxVal ?? minVal ?? 0;
      numVal = double.tryParse(picked.toString()) ?? 0.0;
    } else {
      final str = value.toString().replaceAll('RM', '').replaceAll(',', '').trim();
      final parts = str.split(RegExp(r'\s*-\s*'));
      if (parts.length >= 2) {
        numVal = double.tryParse(parts[1].trim()) ?? double.tryParse(parts[0].trim()) ?? 0.0;
      } else {
        numVal = double.tryParse(str) ?? 0.0;
      }
    }
    if (numVal <= 0) {
      return '1,425.00';
    }
    return NumberFormat('#,##0.00').format(numVal);
  }

  static String formatCurrency(dynamic value) => formatSingleCurrency(value);
}
