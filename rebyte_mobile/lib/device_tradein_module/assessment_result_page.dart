import 'dart:io';
import 'package:flutter/material.dart';
import 'models/device_model.dart';
import 'services/trade_in_flow_session.dart';
import 'services/trade_in_service.dart';
import 'preliminary_quotation_page.dart';
import 'trade_in_inspection_sections.dart';
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
          TradeInService.getDeviceById(widget.device.deviceID)
        else
          Future.value(null),
      ]);

      if (!mounted) return;
      setState(() {
        _evaluationData = results[0];
        _deviceRecord = results[1];
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

                      TradeInInspectionSections(
                        evaluation: _evaluationData,
                        localPhotos: localPhotos,
                      ),
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
    final grade = _evaluationData?['grade']?.toString().trim().toUpperCase();
    final quickTradeIn = _evaluationData?['quickTradeIn'] == true;

    Color gradeBgColor;
    Color gradeTextColor;
    String statusLabel;
    Color statusColor;
    String description;

    switch (grade) {
      case null:
      case '':
        gradeBgColor = const Color(0xFFF1F5F9);
        gradeTextColor = const Color(0xFF64748B);
        statusLabel = 'Grade unavailable';
        statusColor = const Color(0xFF64748B);
        description = 'The photo assessment did not produce a condition grade.';
        break;
      case 'A':
        gradeBgColor = const Color(0xFFDBEAFE);
        gradeTextColor = const Color(0xFF0C5AD2);
        statusLabel = 'Excellent';
        statusColor = const Color(0xFF10B981);
        description =
            'Device is in near-perfect cosmetic condition with minimal signs of wear.';
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

          if (quickTradeIn && grade?.isNotEmpty == true) ...[
            const Text(
              'Provisional grade based on Quick Trade-In photos',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
          ],

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
                grade?.isNotEmpty == true ? grade! : '–',
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
