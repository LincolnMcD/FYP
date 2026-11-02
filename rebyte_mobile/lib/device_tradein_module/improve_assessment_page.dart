import 'package:flutter/material.dart';
import 'models/device_model.dart';
import 'services/trade_in_flow_session.dart';
import 'services/trade_in_service.dart';
import 'device_assessment_loading_page.dart';
import '../widgets/rebyte_app_bar.dart';
import '../widgets/rebyte_bottom_nav_bar.dart';
import '../account_management_module/home_page.dart';
import '../decision_assistance_module/diagnostic_suite_page.dart';
import 'my_trade_in_requests_page.dart';

class ImproveAssessmentPage extends StatefulWidget {
  final DeviceModel device;
  final String tradeInRequestID;
  final bool isLoggedIn;
  final String? email;
  final String? name;
  final bool fromMyTradeInRequests;

  const ImproveAssessmentPage({
    super.key,
    required this.device,
    required this.tradeInRequestID,
    this.isLoggedIn = false,
    this.email,
    this.name,
    this.fromMyTradeInRequests = false,
  });

  @override
  State<ImproveAssessmentPage> createState() => _ImproveAssessmentPageState();
}

class _ImproveAssessmentPageState extends State<ImproveAssessmentPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _hasDiagnosticRecord = false;

  @override
  void initState() {
    super.initState();
    // Mark session as having reached Page 5
    TradeInFlowSession.currentUserEmail = widget.email;
    TradeInFlowSession.currentStep = 5;
    TradeInFlowSession.setTradeInRequestId(widget.tradeInRequestID);
    TradeInFlowSession.setCurrentDevice(widget.device);
    _checkDiagnosticRecord();
  }

  Future<void> _checkDiagnosticRecord() async {
    final devId = widget.device.deviceID;
    if (devId.isNotEmpty) {
      final exists = await TradeInService.checkDeviceDiagnosticExists(devId);
      if (mounted) {
        setState(() {
          _hasDiagnosticRecord = exists;
        });
      }
    }
  }

  void _onBackToHome() {
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
    // Keep TradeInFlowSession intact so the active block is visible under Active Activity
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

  void _onPerformSelfTest() {
    if (_hasDiagnosticRecord) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DiagnosticSuitePage(
          device: widget.device,
          tradeInRequestID: widget.tradeInRequestID,
          isLoggedIn: widget.isLoggedIn,
          email: widget.email,
          name: widget.name,
          fromImproveAssessment: true,
        ),
      ),
    ).then((_) {
      // Recheck when returning from diagnostic
      _checkDiagnosticRecord();
    });
  }

  void _onProceedAssessment() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DeviceAssessmentLoadingPage(
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _onBackToHome();
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
        child: Column(
          children: [
            // Top back button row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B), size: 24),
                  onPressed: _onBackToHome,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ),
            ),

            // Main center content
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Circular blue badge with shield cross
                      Container(
                        width: 84,
                        height: 84,
                        decoration: const BoxDecoration(
                          color: Color(0xFF0C5AD2),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.shield_outlined,
                            size: 44,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Title
                      const Text(
                        'Improve Your Assessment',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Description
                      const Text(
                        'Running a quick diagnostic self-test provides detailed internal health results (like battery capacity and sensor status), which can increase the accuracy of your trade-in offer.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF475569),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 36),

                      // Primary Button: Proceed Device Assessment
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _onProceedAssessment,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0C5AD2),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Proceed Device Assessment',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Secondary Button: Perform Device Self-Test
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: OutlinedButton(
                                onPressed: _hasDiagnosticRecord ? null : _onPerformSelfTest,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _hasDiagnosticRecord
                                      ? const Color(0xFF94A3B8)
                                      : const Color(0xFF0F172A),
                                  disabledForegroundColor: const Color(0xFF94A3B8),
                                  side: BorderSide(
                                    color: _hasDiagnosticRecord
                                        ? const Color(0xFFE2E8F0)
                                        : const Color(0xFFCBD5E1),
                                    width: 1.2,
                                  ),
                                  backgroundColor: _hasDiagnosticRecord
                                      ? const Color(0xFFF1F5F9)
                                      : Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _hasDiagnosticRecord
                                          ? Icons.check_circle_outline_rounded
                                          : Icons.monitor_heart_outlined,
                                      size: 20,
                                      color: _hasDiagnosticRecord
                                          ? const Color(0xFF94A3B8)
                                          : const Color(0xFF0F172A),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      _hasDiagnosticRecord
                                          ? 'Self-Test Completed'
                                          : 'Perform Device Self-Test',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: _hasDiagnosticRecord
                                            ? const Color(0xFF94A3B8)
                                            : const Color(0xFF0F172A),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // Gray overlay when self-test has already been completed
                            if (_hasDiagnosticRecord)
                              Positioned.fill(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF64748B).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Footer Subtext
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'You can always run the test later from your device settings if you change your mind.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF64748B),
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const ReByteBottomNavBar(
        selectedIndex: 2,
      ),
    ),
  );
  }
}
