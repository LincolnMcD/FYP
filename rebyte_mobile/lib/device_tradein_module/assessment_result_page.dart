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
  }

  void _onBack() {
    if (widget.fromMyTradeInRequests) {
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
        return;
      } else {
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

  void _onContinueToQuotation() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PreliminaryQuotationPage(
          device: widget.device,
          tradeInRequestID: widget.tradeInRequestID,
          isLoggedIn: widget.isLoggedIn,
          email: widget.email,
          name: widget.name,
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
          child: SingleChildScrollView(
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

                // 2. External Score Card (94 / 100)
                _buildExternalScoreCard(),
                const SizedBox(height: 16),

                // 3. Detected Defects Card
                _buildDetectedDefectsCard(),
                const SizedBox(height: 16),

                // 4. Component Breakdown Card
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

  Widget _buildEvaluatingDeviceCard() {
    final device = widget.device;
    final String brand = device.brand.trim();
    final String model = device.model.trim();
    final bool hasBrand = model.toLowerCase().startsWith(brand.toLowerCase());
    final String fullDeviceName = hasBrand ? model : '$brand $model'.trim();
    final String storage = device.storageCapacity.isNotEmpty ? device.storageCapacity : 'N/A';
    final String colour = device.colour.isNotEmpty ? device.colour : 'N/A';
    final String? imei = device.imeiNum ?? TradeInFlowSession.lastEnteredImei;
    final String age = device.deviceAge != null && device.deviceAge!.isNotEmpty
        ? device.deviceAge!
        : 'N/A';

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
              if (device.modelCode != null && device.modelCode!.isNotEmpty)
                _buildSpecBadge(Icons.code_rounded, 'Code: ${device.modelCode!}'),
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

          // Grade Badge circle "A"
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              color: Color(0xFFDBEAFE),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text(
                'A',
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0C5AD2),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Excellent tag
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.check_circle_rounded, size: 18, color: Color(0xFF10B981)),
              SizedBox(width: 6),
              Text(
                'Excellent',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF10B981),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Subtitle text
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Device is in near-perfect cosmetic condition with minor signs of wear. All hardware components passed diagnostics.',
              textAlign: TextAlign.center,
              style: TextStyle(
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
                'External Score',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF334155),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 94 /100
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: const [
              Text(
                '94',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                  letterSpacing: -1,
                ),
              ),
              SizedBox(width: 4),
              Text(
                '/100',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: 0.94,
              minHeight: 8,
              backgroundColor: const Color(0xFFE2E8F0),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0C5AD2)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetectedDefectsCard() {
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
              Icon(Icons.search_rounded, size: 18, color: Color(0xFF64748B)),
              SizedBox(width: 8),
              Text(
                'Detected Defects',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF334155),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Defect Item 1: Micro-scratches on bezel
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFD97706)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Micro-scratches on bezel',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Bottom-right corner, length < 2mm',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Defect Item 2: Battery Health at 88%
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF0C5AD2)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Battery Health at 88%',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Normal degradation for age',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildComponentBreakdownCard() {
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
          const Text(
            'Component Breakdown',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 16),

          // Display Panel -> Pass
          _buildComponentRow(
            icon: Icons.smartphone_rounded,
            title: 'Display Panel',
            statusText: 'Pass',
            statusColor: const Color(0xFF10B981),
            statusBgColor: const Color(0xFFECFDF5),
            statusIcon: Icons.check_circle_outline_rounded,
          ),
          const Divider(height: 20, color: Color(0xFFF1F5F9)),

          // Camera Lenses -> Pass
          _buildComponentRow(
            icon: Icons.camera_alt_outlined,
            title: 'Camera Lenses',
            statusText: 'Pass',
            statusColor: const Color(0xFF10B981),
            statusBgColor: const Color(0xFFECFDF5),
            statusIcon: Icons.check_circle_outline_rounded,
          ),
          const Divider(height: 20, color: Color(0xFFF1F5F9)),

          // Middle Frame -> Degraded
          _buildComponentRow(
            icon: Icons.crop_portrait_rounded,
            title: 'Middle Frame',
            statusText: 'Degraded',
            statusColor: const Color(0xFFD97706),
            statusBgColor: const Color(0xFFFFFBEB),
            statusIcon: Icons.error_outline_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildComponentRow({
    required IconData icon,
    required String title,
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

  Widget _buildInspectionPhotosCard(List<String> photos) {
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
          const Text(
            'Inspection Photos',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 14),

          // Two photos side-by-side
          Row(
            children: [
              Expanded(
                child: _buildPhotoThumb(
                  photos.isNotEmpty ? photos[0] : null,
                  hasHighlightCircle: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildPhotoThumb(
                  photos.length > 1 ? photos[1] : null,
                  hasHighlightCircle: false,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoThumb(String? filePath, {bool hasHighlightCircle = false}) {
    return Container(
      height: 110,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (filePath != null)
            Image.file(
              File(filePath),
              fit: BoxFit.cover,
            )
          else
            Container(
              color: const Color(0xFFE2E8F0),
              child: const Center(
                child: Icon(Icons.smartphone_rounded, size: 40, color: Color(0xFF94A3B8)),
              ),
            ),
          if (hasHighlightCircle)
            Center(
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF38BDF8), width: 2),
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
              onPressed: _onContinueToQuotation,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0C5AD2),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Continue to Quotation',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
