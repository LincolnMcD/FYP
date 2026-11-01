import 'dart:io';
import 'package:flutter/material.dart';
import 'models/device_model.dart';
import 'services/trade_in_flow_session.dart';
import 'services/trade_in_service.dart';
import 'preliminary_quotation_page.dart';
import '../widgets/rebyte_app_bar.dart';
import '../widgets/rebyte_bottom_nav_bar.dart';
import '../account_management_module/home_page.dart';
import 'my_trade_in_requests_page.dart';

class AssessmentResultPage extends StatefulWidget {
  final DeviceModel device;
  final String tradeInRequestID;
  final bool isLoggedIn;
  final String? email;
  final String? name;
  final bool fromMyTradeInRequests;

  const AssessmentResultPage({
    super.key,
    required this.device,
    required this.tradeInRequestID,
    this.isLoggedIn = false,
    this.email,
    this.name,
    this.fromMyTradeInRequests = false,
  });

  @override
  State<AssessmentResultPage> createState() => _AssessmentResultPageState();
}

class _AssessmentResultPageState extends State<AssessmentResultPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  bool _isLoading = true;
  bool _isPreparingQuotation = false;
  Map<String, dynamic>? _evaluationData;
  Map<String, dynamic>? _diagnosticData;
  Map<String, dynamic>? _deviceRecord;

  @override
  void initState() {
    super.initState();
    // Mark session as having reached Page 7 (Evaluated / Quotation Pending)
    TradeInFlowSession.currentUserEmail = widget.email;
    TradeInFlowSession.currentStep = 7;
    TradeInFlowSession.setTradeInRequestId(widget.tradeInRequestID);
    TradeInFlowSession.setCurrentDevice(widget.device);

    // Update tradeInRequest status in database to 'Evaluated'
    if (widget.tradeInRequestID.isNotEmpty) {
      TradeInService.updateTradeInStatus(
        tradeInRequestID: widget.tradeInRequestID,
        status: 'Evaluated',
      );
    }

    _loadAssessmentData();
  }

  Future<void> _loadAssessmentData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final results = await Future.wait([
        TradeInService.getEvaluation(widget.tradeInRequestID),
        if (widget.device.deviceID.isNotEmpty)
          TradeInService.getDeviceDiagnostic(widget.device.deviceID)
        else
          Future.value(null),
        if (widget.device.deviceID.isNotEmpty)
          TradeInService.getDeviceById(widget.device.deviceID)
        else
          Future.value(null),
      ]);

      if (!mounted) return;
      setState(() {
        _evaluationData = results[0];
        _diagnosticData = results.length > 1 ? results[1] : null;
        _deviceRecord = results.length > 2 ? results[2] : null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _onBack() {
    if (widget.fromMyTradeInRequests) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => MyTradeInRequestsPage(
            email: widget.email ?? 'customer@rebyte.com',
            name: widget.name,
            isLoggedIn: widget.isLoggedIn,
          ),
        ),
        (route) => false,
      );
      return;
    }
    // Navigate back to HomePage at Active Activity section
    // Keep TradeInFlowSession intact so the active block is visible with Quotation Pending
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => HomePage(
          isLoggedIn: widget.isLoggedIn,
          email: widget.email,
          name: widget.name,
          initialIndex: 0,
          scrollToActiveActivity: true,
        ),
      ),
      (route) => false,
    );
  }

  Future<void> _onContinueToQuotation() async {
    if (_isPreparingQuotation) return;
    setState(() => _isPreparingQuotation = true);
    final prediction = await TradeInService.predictQuotation(widget.tradeInRequestID);
    if (!mounted) return;
    final range = prediction['estimatedValue'];
    final min = range is Map ? double.tryParse(range['min']?.toString() ?? '') : null;
    final max = range is Map ? double.tryParse(range['max']?.toString() ?? '') : null;
    if (prediction['success'] != true || min == null || max == null) {
      setState(() => _isPreparingQuotation = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(prediction['message']?.toString() ?? 'Could not calculate the quotation. Please try again.')),
      );
      return;
    }
    final priceRange = 'RM ${min.toStringAsFixed(2)} - RM ${max.toStringAsFixed(2)}';
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => PreliminaryQuotationPage(
          device: widget.device,
          tradeInRequestID: widget.tradeInRequestID,
          isLoggedIn: widget.isLoggedIn,
          email: widget.email,
          name: widget.name,
          estimatedValue: priceRange,
          estimateFromModel: true,
          fromMyTradeInRequests: widget.fromMyTradeInRequests,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Retrieve any uploaded inspection photos from TradeInFlowSession if available
    final savedSlots = TradeInFlowSession.savedSlots;
    final List<String> localPhotos = [];
    if (savedSlots != null) {
      for (final s in savedSlots) {
        if (s.localFilePath != null &&
            s.localFilePath!.isNotEmpty &&
            File(s.localFilePath!).existsSync()) {
          localPhotos.add(s.localFilePath!);
        }
      }
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _onBack();
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: ReByteAppBar(scaffoldKey: _scaffoldKey),
        drawer: ReByteDrawer(
          isLoggedIn: widget.isLoggedIn,
          email: widget.email,
          name: widget.name,
          selectedIndex: 2,
        ),
        body: SafeArea(
          child: _isLoading
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: Color(0xFF0C5AD2)),
                      SizedBox(height: 16),
                      Text(
                        'Loading assessment details...',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top back button
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B), size: 24),
                        onPressed: _onBack,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(height: 16),

                      // Evaluating Device Information Card
                      _buildEvaluatingDeviceCard(),
                      const SizedBox(height: 16),

                      // 1. Overall Condition Card
                      _buildOverallConditionCard(),
                      const SizedBox(height: 16),

                      // 2. External Score Card (3 Part Summary)
                      _buildExternalScoreCard(),
                      const SizedBox(height: 16),

                      // 3. Component Breakdown Card (Internal Diagnostic Result)
                      _buildComponentBreakdownCard(),
                      const SizedBox(height: 16),

                      // 5. Inspection Photos Card
                      _buildInspectionPhotosCard(localPhotos),
                      const SizedBox(height: 16),

                      // 6. Eligibility Result Card
                      _buildEligibilityResultCard(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
        ),
        bottomNavigationBar: const ReByteBottomNavBar(
          selectedIndex: 2,
        ),
      ),
    );
  }

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return const Color(0xFFDC2626); // Red
      case 'major':
        return const Color(0xFFEA580C); // Orange-Red
      case 'minor':
        return const Color(0xFFD97706); // Amber / Orange
      case 'low':
        return const Color(0xFF0284C7); // Sky Blue
      case 'none':
      default:
        return const Color(0xFF10B981); // Emerald Green
    }
  }

  Color _getSeverityBgColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return const Color(0xFFFEF2F2);
      case 'major':
        return const Color(0xFFFFF7ED);
      case 'minor':
        return const Color(0xFFFFFBEB);
      case 'low':
        return const Color(0xFFF0F9FF);
      case 'none':
      default:
        return const Color(0xFFF0FDF4);
    }
  }

  Widget _buildEvaluatingDeviceCard() {
    final device = widget.device;
    final devRec = _deviceRecord;

    final String brand = (devRec?['brand']?.toString().isNotEmpty ?? false)
        ? devRec!['brand'].toString()
        : device.brand;
    final String model = (devRec?['model']?.toString().isNotEmpty ?? false)
        ? devRec!['model'].toString()
        : device.model;
    final String fullDeviceName = (brand.isNotEmpty || model.isNotEmpty)
        ? '$brand $model'.trim()
        : device.displayTitle;

    final String storage = (devRec?['storageCapacity']?.toString().isNotEmpty ?? false)
        ? devRec!['storageCapacity'].toString()
        : (device.storageCapacity.isNotEmpty ? device.storageCapacity : 'N/A');

    final String colour = (devRec?['colour']?.toString().isNotEmpty ?? false)
        ? devRec!['colour'].toString()
        : (devRec?['color']?.toString().isNotEmpty ?? false)
            ? devRec!['color'].toString()
            : (device.colour.isNotEmpty ? device.colour : 'N/A');

    final String? imei = devRec?['imeiNum']?.toString() ??
        devRec?['imei']?.toString() ??
        device.imeiNum ??
        TradeInFlowSession.lastEnteredImei;

    final String rawAge = devRec?['deviceAge']?.toString() ??
        device.deviceAge ??
        '';
    final String age = rawAge.trim().isNotEmpty ? rawAge.trim() : 'N/A';

    final String? modelCode = devRec?['modelCode']?.toString() ?? device.modelCode;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.smartphone_rounded,
                  color: Color(0xFF0C5AD2),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'EVALUATED DEVICE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFA7F3D0)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_rounded, size: 12, color: Color(0xFF10B981)),
                              SizedBox(width: 4),
                              Text(
                                'Evaluated',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      fullDeviceName.isNotEmpty ? fullDeviceName : 'Smartphone',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 12),

          // Specs Badges & Details
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildSpecBadge(Icons.sd_storage_outlined, storage),
              _buildSpecBadge(Icons.palette_outlined, colour),
              _buildSpecBadge(Icons.calendar_today_outlined, 'Age: $age'),
            ],
          ),

          if (imei != null && imei.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.fingerprint_rounded, size: 14, color: Color(0xFF64748B)),
                const SizedBox(width: 6),
                Text(
                  'IMEI: $imei',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF475569),
                  ),
                ),
                const Spacer(),
                Text(
                  '#${widget.tradeInRequestID}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSpecBadge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFF64748B)),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverallConditionCard() {
    final grade = _evaluationData?['grade']?.toString().toUpperCase() ?? 'A';

    Color gradeBgColor;
    Color gradeTextColor;
    String statusLabel;
    Color statusColor;
    String description;

    switch (grade) {
      case 'A':
        gradeBgColor = const Color(0xFFDBEAFE);
        gradeTextColor = const Color(0xFF0C5AD2);
        statusLabel = 'Excellent';
        statusColor = const Color(0xFF10B981);
        description =
            'Device is in near-perfect cosmetic condition with minimal signs of wear. All hardware components passed diagnostics.';
        break;
      case 'B':
        gradeBgColor = const Color(0xFFE0F2FE);
        gradeTextColor = const Color(0xFF0284C7);
        statusLabel = 'Good';
        statusColor = const Color(0xFF0284C7);
        description =
            'Device is in good cosmetic condition with light cosmetic wear or minor scratches. Core functions are working properly.';
        break;
      case 'C':
        gradeBgColor = const Color(0xFFFEF3C7);
        gradeTextColor = const Color(0xFFD97706);
        statusLabel = 'Fair';
        statusColor = const Color(0xFFD97706);
        description =
            'Device shows moderate signs of wear, visible scratches or minor cosmetic blemishes. All primary functions operate normally.';
        break;
      default:
        gradeBgColor = const Color(0xFFFEE2E2);
        gradeTextColor = const Color(0xFFDC2626);
        statusLabel = 'Needs Attention';
        statusColor = const Color(0xFFDC2626);
        description =
            'Device has noticeable cosmetic damage or hardware performance degradation requiring further refurbishment.';
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'Overall Condition',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 20),

          // Grade Badge circle
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: gradeBgColor,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                grade,
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  color: gradeTextColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Status tag
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_rounded, size: 18, color: statusColor),
              const SizedBox(width: 6),
              Text(
                statusLabel,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Subtitle text
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                color: Color(0xFF64748B),
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExternalScoreCard() {
    // 3 Part Summary Mark: Screen, Back, Frame damage coverage % in 2 decimals
    final Map<String, dynamic>? parts = _evaluationData?['parts'] is Map<String, dynamic>
        ? _evaluationData!['parts'] as Map<String, dynamic>
        : null;

    final screenData = parts?['screen'] ?? _evaluationData?['screen'];
    final backData = parts?['back'] ?? _evaluationData?['back'];
    final frameData = parts?['frame'] ?? _evaluationData?['frame'];

    double getDmgCoverage(dynamic part) {
      if (part is Map) {
        final cov = part['dmgCoverage'] ?? part['coverage'];
        if (cov is num) return cov.toDouble();
        if (cov != null) return double.tryParse(cov.toString()) ?? 0.0;
      }
      return 0.0;
    }

    final double screenCov = getDmgCoverage(screenData);
    final double backCov = getDmgCoverage(backData);
    final double frameCov = getDmgCoverage(frameData);

    // Overall cosmetic health score: 100 - avg(coverage * 100)
    final double avgDmgPct = ((screenCov + backCov + frameCov) / 3.0) * 100.0;
    final int overallExternalScore = (100 - avgDmgPct).clamp(0, 100).round();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.tune_rounded, size: 18, color: Color(0xFF64748B)),
              SizedBox(width: 8),
              Text(
                'External Condition Score',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF334155),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Overall External Mark /100
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$overallExternalScore',
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                '/100',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF94A3B8),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '3-Part Summary',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0C5AD2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 3 Part Summary cards
          Row(
            children: [
              Expanded(
                child: _buildPartSummaryItem(
                  partKey: 'screen',
                  title: 'Screen',
                  icon: Icons.phone_android_rounded,
                  dmgCoverage: screenCov,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildPartSummaryItem(
                  partKey: 'back',
                  title: 'Back',
                  icon: Icons.flip_to_back_rounded,
                  dmgCoverage: backCov,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildPartSummaryItem(
                  partKey: 'frame',
                  title: 'Frame',
                  icon: Icons.crop_portrait_rounded,
                  dmgCoverage: frameCov,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPartSummaryItem({
    required String partKey,
    required String title,
    required IconData icon,
    required double dmgCoverage,
  }) {
    final double dmgPct = (dmgCoverage * 100.0).clamp(0.0, 100.0);
    final String pctText = '${dmgPct.toStringAsFixed(2)}%';
    final bool hasDamage = dmgPct > 0.05;

    final Color statusColor = hasDamage ? (dmgPct > 5.0 ? const Color(0xFFDC2626) : const Color(0xFFD97706)) : const Color(0xFF10B981);
    final Color bgColor = hasDamage ? (dmgPct > 5.0 ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB)) : const Color(0xFFF0FDF4);

    return InkWell(
      onTap: () => _showPartDefectsDialog(partKey: partKey, partTitle: title),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: statusColor.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: statusColor),
            const SizedBox(height: 6),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              pctText,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: statusColor,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  hasDamage ? 'Damage Cov.' : 'Intact',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w500,
                    color: statusColor.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 8,
                  color: statusColor.withValues(alpha: 0.6),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showPartDefectsDialog({
    required String partKey,
    required String partTitle,
  }) {
    // Collect defect types for this specific part
    final List<Map<String, dynamic>> defectConfig;
    if (partKey == 'screen') {
      defectConfig = [
        {'key': 'screenCrack', 'title': 'Crack', 'icon': Icons.bolt_rounded},
        {'key': 'screenDiscolouration', 'title': 'Discolouration', 'icon': Icons.palette_outlined},
        {'key': 'screenScratch', 'title': 'Scratch', 'icon': Icons.show_chart_rounded},
      ];
    } else if (partKey == 'back') {
      defectConfig = [
        {'key': 'backCrack', 'title': 'Crack', 'icon': Icons.bolt_rounded},
        {'key': 'backScratch', 'title': 'Scratch', 'icon': Icons.show_chart_rounded},
      ];
    } else {
      // frame
      defectConfig = [
        {'key': 'frameScratch', 'title': 'Scratch', 'icon': Icons.show_chart_rounded},
        {'key': 'frameDent', 'title': 'Dent', 'icon': Icons.radio_button_checked_rounded},
      ];
    }

    // Extract real data for each defect type from classes or root
    final Map<String, dynamic>? classes = _evaluationData?['classes'] is Map<String, dynamic>
        ? _evaluationData!['classes'] as Map<String, dynamic>
        : null;

    final List<Map<String, dynamic>> pages = defectConfig.map((cfg) {
      final key = cfg['key'] as String;
      final dynamic raw = classes?[key] ?? _evaluationData?[key];

      int count = 0;
      double? area;
      double? coverage;
      String severity = 'None';

      if (raw is Map) {
        if (raw['count'] is num) count = (raw['count'] as num).toInt();
        if (raw['area'] is num) area = (raw['area'] as num).toDouble();
        if (raw['coverage'] is num) coverage = (raw['coverage'] as num).toDouble();
        if (raw['severity'] != null && raw['severity'].toString().isNotEmpty) {
          severity = raw['severity'].toString();
        }
      }

      final bool isCrack = (cfg['title'] == 'Crack') || key.toLowerCase().contains('crack');

      return {
        'title': '$partTitle ${cfg['title']}',
        'defectType': cfg['title'] as String,
        'icon': cfg['icon'] as IconData,
        'isCrack': isCrack,
        'count': count,
        'area': area,
        'coverage': coverage,
        'severity': count > 0 ? severity : 'None',
      };
    }).toList();

    showDialog(
      context: context,
      builder: (ctx) {
        final PageController pageController = PageController();
        int activePage = 0;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 520, maxWidth: 420),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Dialog Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 14, 12),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.analytics_outlined,
                              color: Color(0xFF0C5AD2),
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$partTitle Defect Breakdown',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Swipe left / right to view each defect',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                GestureDetector(
                                  onTap: _showSeverityRankingDialog,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEFF6FF),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFFBFDBFE)),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.help_outline_rounded, color: Color(0xFF0C5AD2), size: 13),
                                        SizedBox(width: 4),
                                        Text(
                                          'Severity Ranking',
                                          style: TextStyle(
                                            fontSize: 11,
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
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B), size: 22),
                            onPressed: () => Navigator.of(ctx).pop(),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),

                    // Page Indicator Dots
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(pages.length, (i) {
                          final isCurrent = i == activePage;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            height: 6,
                            width: isCurrent ? 22 : 6,
                            decoration: BoxDecoration(
                              color: isCurrent ? const Color(0xFF0C5AD2) : const Color(0xFFCBD5E1),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          );
                        }),
                      ),
                    ),

                    // Swipeable PageView with defect details
                    Flexible(
                      child: SizedBox(
                        height: 380,
                        child: PageView.builder(
                          controller: pageController,
                          itemCount: pages.length,
                          onPageChanged: (i) {
                            setDialogState(() {
                              activePage = i;
                            });
                          },
                          itemBuilder: (context, idx) {
                            final page = pages[idx];
                            final int count = page['count'] as int;
                            final double? area = page['area'] as double?;
                            final double? coverage = page['coverage'] as double?;
                            final String severity = page['severity'] as String;
                            final bool hasDefect = count > 0;

                            final Color statusColor = hasDefect
                                ? _getSeverityColor(severity)
                                : const Color(0xFF10B981);

                            return SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Defect Category Badge & Icon
                                  Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: (page['isCrack'] == true)
                                          ? CustomPaint(
                                              size: const Size(28, 28),
                                              painter: _CrackIconPainter(color: statusColor),
                                            )
                                          : Icon(
                                              page['icon'] as IconData,
                                              size: 28,
                                              color: statusColor,
                                            ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    page['title'] as String,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      hasDefect ? '$count Detected' : 'No Defects Detected',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: statusColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 18),

                                  // 4 Detail Grid Blocks: Count, Area, Severity, Coverage
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildDefectMetricCard(
                                          label: 'Count',
                                          value: '$count',
                                          icon: Icons.tag_rounded,
                                          valueColor: statusColor,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _buildDefectMetricCard(
                                          label: 'Severity',
                                          value: severity,
                                          icon: Icons.shield_outlined,
                                          valueColor: statusColor,
                                          onHelpTap: _showSeverityRankingDialog,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildDefectMetricCard(
                                          label: 'Damage Area',
                                          value: area != null ? '${area.toStringAsFixed(2)} cm²' : '0.00 cm²',
                                          icon: Icons.aspect_ratio_rounded,
                                          valueColor: const Color(0xFF1E293B),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _buildDefectMetricCard(
                                          label: 'Coverage',
                                          value: coverage != null
                                              ? '${(coverage * 100).toStringAsFixed(2)}%'
                                              : '0.00%',
                                          icon: Icons.pie_chart_outline_rounded,
                                          valueColor: const Color(0xFF1E293B),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),

                                  // Bottom helper status text
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          hasDefect ? Icons.info_outline_rounded : Icons.check_circle_outline_rounded,
                                          size: 16,
                                          color: statusColor,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            hasDefect
                                                ? 'Detected during AI surface assessment. Severity level evaluated as $severity.'
                                                : 'Zero $partTitle ${page['defectType']} defects found during evaluation.',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFF64748B),
                                              height: 1.35,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                    // Swipe Navigation controls
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton.icon(
                            onPressed: activePage > 0
                                ? () {
                                    pageController.previousPage(
                                      duration: const Duration(milliseconds: 250),
                                      curve: Curves.easeInOut,
                                    );
                                  }
                                : null,
                            icon: const Icon(Icons.chevron_left_rounded, size: 20),
                            label: const Text('Previous', style: TextStyle(fontSize: 12.5)),
                          ),
                          Text(
                            '${activePage + 1} of ${pages.length}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: activePage < pages.length - 1
                                ? () {
                                    pageController.nextPage(
                                      duration: const Duration(milliseconds: 250),
                                      curve: Curves.easeInOut,
                                    );
                                  }
                                : null,
                            icon: const Text('Next', style: TextStyle(fontSize: 12.5)),
                            label: const Icon(Icons.chevron_right_rounded, size: 20),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDefectMetricCard({
    required String label,
    required String value,
    required IconData icon,
    required Color valueColor,
    VoidCallback? onHelpTap,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: const Color(0xFF64748B)),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
              if (onHelpTap != null)
                GestureDetector(
                  onTap: onHelpTap,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.help_outline_rounded,
                      size: 13,
                      color: Color(0xFF0C5AD2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  void _showSeverityRankingDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        final rankings = [
          {
            'level': 'Critical',
            'color': const Color(0xFFDC2626),
            'bgColor': const Color(0xFFFEF2F2),
            'icon': Icons.dangerous_rounded,
            'desc': 'Deep cracks, extensive shattered areas, or damage that impairs device function or touch response.',
          },
          {
            'level': 'Major',
            'color': const Color(0xFFEA580C),
            'bgColor': const Color(0xFFFFF7ED),
            'icon': Icons.warning_rounded,
            'desc': 'Noticeable cracks, deep scratches, or distinct discolouration patches clearly visible at arm’s length.',
          },
          {
            'level': 'Minor',
            'color': const Color(0xFFD97706),
            'bgColor': const Color(0xFFFFFBEB),
            'icon': Icons.error_outline_rounded,
            'desc': 'Light surface scratches, hairline marks, or slight cosmetic wear that does not affect functionality.',
          },
          {
            'level': 'Low',
            'color': const Color(0xFF0284C7),
            'bgColor': const Color(0xFFF0F9FF),
            'icon': Icons.info_outline_rounded,
            'desc': 'Micro-scratches or faint signs of handling visible only under direct angled light inspection.',
          },
          {
            'level': 'None',
            'color': const Color(0xFF10B981),
            'bgColor': const Color(0xFFF0FDF4),
            'icon': Icons.check_circle_outline_rounded,
            'desc': 'Pristine surface with zero detected cosmetic blemishes or structural anomalies.',
          },
        ];

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 14, 14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.help_outline_rounded,
                          color: Color(0xFF0C5AD2),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Severity Ranking Guide',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              'Defect severity classifications explained',
                              style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B), size: 22),
                        onPressed: () => Navigator.of(ctx).pop(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),

                // Ranking list
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: rankings.map((r) {
                      final Color col = r['color'] as Color;
                      final Color bg = r['bgColor'] as Color;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: col.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(r['icon'] as IconData, size: 20, color: col),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r['level'] as String,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: col,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    r['desc'] as String,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: Color(0xFF475569),
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),

                // Close Button
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0C5AD2),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildComponentBreakdownCard() {
    final String? diagnosticId = _evaluationData?['diagnosticID']?.toString();
    final bool hasDiagnostic = diagnosticId != null &&
        diagnosticId.trim().isNotEmpty &&
        diagnosticId.trim().toUpperCase() != 'NULL' &&
        _diagnosticData != null;

    final diag = hasDiagnostic ? _diagnosticData : null;

    // Component rows from deviceDiagnostic
    final List<Map<String, dynamic>> components = [
      {
        'title': 'Touchscreen',
        'icon': Icons.touch_app_rounded,
        'mark': diag?['touchScreenMark'],
      },
      {
        'title': 'Display Panel',
        'icon': Icons.smartphone_rounded,
        'mark': diag?['displayMark'],
      },
      {
        'title': 'Camera System',
        'icon': Icons.camera_alt_outlined,
        'mark': diag?['cameraMark'],
      },
      {
        'title': 'Microphone',
        'icon': Icons.mic_none_rounded,
        'mark': diag?['microphoneMark'],
      },
      {
        'title': 'Speaker & Audio',
        'icon': Icons.volume_up_outlined,
        'mark': diag?['speakerMark'],
      },
      {
        'title': 'Sensors',
        'icon': Icons.sensors_rounded,
        'mark': diag?['sensorMark'],
      },
      {
        'title': 'Network & Connectivity',
        'icon': Icons.wifi_rounded,
        'mark': diag?['connectivityMark'],
      },
      {
        'title': 'GPS Location',
        'icon': Icons.location_on_outlined,
        'mark': diag?['gpsMark'],
      },
    ];

    final int? diagScore = diag?['diagnosticScore'] is num
        ? (diag!['diagnosticScore'] as num).toInt()
        : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Component Breakdown',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: hasDiagnostic ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: hasDiagnostic ? const Color(0xFFBFDBFE) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Text(
                  hasDiagnostic && diagScore != null ? 'Score: $diagScore/100' : 'Score: N/A',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: hasDiagnostic ? const Color(0xFF0C5AD2) : const Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          ...components.asMap().entries.map((entry) {
            final int index = entry.key;
            final item = entry.value;

            String scoreText;
            String statusText;
            Color statusColor;
            Color statusBgColor;
            IconData statusIcon;

            if (!hasDiagnostic) {
              scoreText = 'N/A';
              statusText = 'N/A';
              statusColor = const Color(0xFF64748B);
              statusBgColor = const Color(0xFFF1F5F9);
              statusIcon = Icons.remove_circle_outline_rounded;
            } else {
              final dynamic markVal = item['mark'];
              final int score = (markVal is num)
                  ? markVal.toInt()
                  : (markVal != null ? int.tryParse(markVal.toString()) ?? 100 : 100);
              scoreText = '$score%';

              if (score >= 80) {
                statusText = 'Pass';
                statusColor = const Color(0xFF10B981);
                statusBgColor = const Color(0xFFECFDF5);
                statusIcon = Icons.check_circle_outline_rounded;
              } else if (score >= 50) {
                statusText = 'Degraded';
                statusColor = const Color(0xFFD97706);
                statusBgColor = const Color(0xFFFFFBEB);
                statusIcon = Icons.error_outline_rounded;
              } else {
                statusText = 'Fail';
                statusColor = const Color(0xFFDC2626);
                statusBgColor = const Color(0xFFFEF2F2);
                statusIcon = Icons.cancel_outlined;
              }
            }

            return Column(
              children: [
                _buildComponentRow(
                  icon: item['icon'] as IconData,
                  title: item['title'] as String,
                  scoreText: scoreText,
                  statusText: statusText,
                  statusColor: statusColor,
                  statusBgColor: statusBgColor,
                  statusIcon: statusIcon,
                ),
                if (index < components.length - 1)
                  const Divider(height: 20, color: Color(0xFFF1F5F9)),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildComponentRow({
    required IconData icon,
    required String title,
    required String scoreText,
    required String statusText,
    required Color statusColor,
    required Color statusBgColor,
    required IconData statusIcon,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF475569)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
        ),
        Text(
          scoreText,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: statusBgColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: statusColor.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(statusIcon, size: 12, color: statusColor),
              const SizedBox(width: 4),
              Text(
                statusText,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInspectionPhotosCard(List<String> localPhotos) {
    // Extract real images from _evaluationData['images'] subcollection / list
    final List<Map<String, dynamic>> evalImages = [];
    if (_evaluationData?['images'] is List) {
      for (final img in _evaluationData!['images']) {
        if (img is Map) {
          evalImages.add(Map<String, dynamic>.from(img));
        }
      }
    }

    // Determine items to display: prefer remote inspection images, fallback to localPhotos
    final bool hasEvalImages = evalImages.isNotEmpty;
    final int itemCount = hasEvalImages ? evalImages.length : localPhotos.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Inspection Photos',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const Spacer(),
              if (itemCount > 0)
                Text(
                  '$itemCount photo${itemCount > 1 ? 's' : ''} (tap to enlarge)',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF64748B),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          if (itemCount == 0)
            Container(
              height: 110,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Center(
                child: Text(
                  'No inspection photos available',
                  style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                ),
              ),
            )
          else
            // Horizontal scrollable list showing initial 2 photos in view
            LayoutBuilder(
              builder: (context, constraints) {
                // Showing 2 initial items in view with gap of 12
                final double itemWidth = (constraints.maxWidth - 12) / 2;
                return SizedBox(
                  height: 130,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: itemCount,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      String? url;
                      String? filePath;
                      String caption = 'Photo ${index + 1}';

                      if (hasEvalImages) {
                        final imgObj = evalImages[index];
                        url = imgObj['imageUrl']?.toString() ?? imgObj['originalImageUrl']?.toString();
                        final view = imgObj['imageView']?.toString();
                        if (view != null && view.isNotEmpty) {
                          caption = view.replaceAll('_', ' ').toUpperCase();
                        }
                      } else {
                        filePath = localPhotos[index];
                      }

                      return SizedBox(
                        width: itemWidth,
                        child: GestureDetector(
                          onTap: () {
                            _showImagePreviewDialog(
                              imageUrl: url,
                              filePath: filePath,
                              title: caption,
                            );
                          },
                          child: _buildPhotoThumbCard(
                            imageUrl: url,
                            filePath: filePath,
                            caption: caption,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildPhotoThumbCard({
    String? imageUrl,
    String? filePath,
    required String caption,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl != null && imageUrl.isNotEmpty)
            Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image_rounded, color: Color(0xFF94A3B8)),
              ),
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              },
            )
          else if (filePath != null && filePath.isNotEmpty && File(filePath).existsSync())
            Image.file(
              File(filePath),
              fit: BoxFit.cover,
            )
          else
            Container(
              color: const Color(0xFFE2E8F0),
              child: const Center(
                child: Icon(Icons.smartphone_rounded, size: 36, color: Color(0xFF94A3B8)),
              ),
            ),

          // Caption overlay banner
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
              color: Colors.black.withValues(alpha: 0.55),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(Icons.zoom_in, color: Colors.white, size: 14),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showImagePreviewDialog({
    String? imageUrl,
    String? filePath,
    required String title,
  }) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 600),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
                        onPressed: () => Navigator.of(ctx).pop(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFF334155)),

                // Interactive zoomable image
                Flexible(
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4.0,
                    child: Center(
                      child: imageUrl != null && imageUrl.isNotEmpty
                          ? Image.network(
                              imageUrl,
                              fit: BoxFit.contain,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return const Center(
                                  child: CircularProgressIndicator(color: Colors.white),
                                );
                              },
                              errorBuilder: (_, __, ___) => const Center(
                                child: Text('Failed to load image', style: TextStyle(color: Colors.white70)),
                              ),
                            )
                          : (filePath != null && File(filePath).existsSync()
                              ? Image.file(File(filePath), fit: BoxFit.contain)
                              : const Center(
                                  child: Icon(Icons.broken_image_rounded, color: Colors.white54, size: 60),
                                )),
                    ),
                  ),
                ),

                // Footer hint
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'Pinch or double tap to zoom',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEligibilityResultCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: const Color(0xFFE0EAFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFDBFE), width: 1.2),
      ),
      child: Column(
        children: [
          const Text(
            'Eligibility Result',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Based on the assessment, this device\nmeets our trade-in requirements.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF475569),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),

          // Continue to Quotation button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isPreparingQuotation ? null : _onContinueToQuotation,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0C5AD2),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isPreparingQuotation) ...[
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    const Text('Calculating quotation...'),
                  ] else ...[
                    const Text(
                      'Continue to Quotation',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_rounded, size: 18),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter rendering a multi-branched surface glass crack pattern
class _CrackIconPainter extends CustomPainter {
  final Color color;

  const _CrackIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final double w = size.width;
    final double h = size.height;

    // Main jagged fracture spine down the center
    final mainPath = Path();
    mainPath.moveTo(w * 0.28, h * 0.14);
    mainPath.lineTo(w * 0.40, h * 0.16);
    mainPath.lineTo(w * 0.48, h * 0.28);
    mainPath.lineTo(w * 0.42, h * 0.36);
    mainPath.lineTo(w * 0.46, h * 0.48);
    mainPath.lineTo(w * 0.38, h * 0.58);
    mainPath.lineTo(w * 0.44, h * 0.68);
    mainPath.lineTo(w * 0.40, h * 0.74);
    mainPath.lineTo(w * 0.50, h * 0.82);
    mainPath.lineTo(w * 0.64, h * 0.94);
    canvas.drawPath(mainPath, paint);

    // Left branch 1 (top left fissure)
    final bLeft1 = Path();
    bLeft1.moveTo(w * 0.38, h * 0.16);
    bLeft1.lineTo(w * 0.32, h * 0.26);
    bLeft1.lineTo(w * 0.18, h * 0.32);
    canvas.drawPath(bLeft1, paint);

    // Left branch 2 (mid left horizontal fork)
    final bLeft2 = Path();
    bLeft2.moveTo(w * 0.46, h * 0.48);
    bLeft2.lineTo(w * 0.34, h * 0.46);
    bLeft2.lineTo(w * 0.24, h * 0.40);
    canvas.drawPath(bLeft2, paint);

    // Left branch 3 (bottom left fork)
    final bLeft3 = Path();
    bLeft3.moveTo(w * 0.40, h * 0.74);
    bLeft3.lineTo(w * 0.30, h * 0.78);
    bLeft3.lineTo(w * 0.34, h * 0.88);
    canvas.drawPath(bLeft3, paint);

    // Right branch 1 (top right sharp shoot)
    final bRight1 = Path();
    bRight1.moveTo(w * 0.48, h * 0.28);
    bRight1.lineTo(w * 0.64, h * 0.20);
    canvas.drawPath(bRight1, paint);

    // Right branch 2 (upper-mid right meandering crack)
    final bRight2 = Path();
    bRight2.moveTo(w * 0.42, h * 0.36);
    bRight2.lineTo(w * 0.56, h * 0.32);
    bRight2.lineTo(w * 0.74, h * 0.34);
    bRight2.lineTo(w * 0.76, h * 0.44);
    bRight2.lineTo(w * 0.66, h * 0.52);
    bRight2.lineTo(w * 0.64, h * 0.60);
    canvas.drawPath(bRight2, paint);

    // Right branch 3 (bottom right fork)
    final bRight3 = Path();
    bRight3.moveTo(w * 0.64, h * 0.60);
    bRight3.lineTo(w * 0.58, h * 0.68);
    canvas.drawPath(bRight3, paint);

    final bRight4 = Path();
    bRight4.moveTo(w * 0.64, h * 0.60);
    bRight4.lineTo(w * 0.70, h * 0.70);
    canvas.drawPath(bRight4, paint);
  }

  @override
  bool shouldRepaint(covariant _CrackIconPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
