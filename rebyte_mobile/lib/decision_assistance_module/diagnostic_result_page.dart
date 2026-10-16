import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../device_tradein_module/models/device_model.dart';
import '../widgets/rebyte_app_bar.dart';
import '../widgets/rebyte_bottom_nav_bar.dart';
import 'services/diagnostic_report_pdf_service.dart';

class DiagnosticResultPage extends StatefulWidget {
  final DeviceModel? device;
  final String? tradeInRequestID;
  final bool isLoggedIn;
  final String? email;
  final String? name;

  // 8 Tests scores (0 - 100)
  final int touchScore;
  final int displayScore;
  final int cameraScore;
  final int micScore;
  final int speakerScore;
  final int sensorScore;
  final int networkScore;
  final int gpsScore;

  // Skip statuses
  final bool isTouchSkipped;
  final bool isDisplaySkipped;
  final bool isCameraSkipped;
  final bool isMicSkipped;
  final bool isSpeakerSkipped;
  final bool isSensorSkipped;
  final bool isNetworkSkipped;
  final bool isGpsSkipped;

  const DiagnosticResultPage({
    super.key,
    this.device,
    this.tradeInRequestID,
    this.isLoggedIn = false,
    this.email,
    this.name,
    required this.touchScore,
    required this.displayScore,
    this.cameraScore = 100,
    this.micScore = 100,
    this.speakerScore = 100,
    this.sensorScore = 100,
    this.networkScore = 100,
    this.gpsScore = 100,
    this.isTouchSkipped = false,
    this.isDisplaySkipped = false,
    this.isCameraSkipped = false,
    this.isMicSkipped = false,
    this.isSpeakerSkipped = false,
    this.isSensorSkipped = false,
    this.isNetworkSkipped = false,
    this.isGpsSkipped = false,
  });

  @override
  State<DiagnosticResultPage> createState() => _DiagnosticResultPageState();
}

class _DiagnosticResultPageState extends State<DiagnosticResultPage> {
  String? _toastMessage;
  bool _isToastError = false;
  bool _isDownloading = false;

  void _showTopToast(String message, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _toastMessage = message;
      _isToastError = isError;
    });
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _toastMessage == message) {
        setState(() => _toastMessage = null);
      }
    });
  }

  int get overallScore {
    // Average across all 8 tests
    return ((widget.touchScore +
                widget.displayScore +
                widget.cameraScore +
                widget.micScore +
                widget.speakerScore +
                widget.sensorScore +
                widget.networkScore +
                widget.gpsScore) /
            8)
        .round()
        .clamp(0, 100);
  }

  String get conditionLabel {
    if (overallScore >= 90) return 'Excellent Condition';
    if (overallScore >= 75) return 'Good Condition';
    if (overallScore >= 50) return 'Fair Condition';
    return 'Needs Attention';
  }

  Color get conditionColor {
    if (overallScore >= 80) return const Color(0xFF16A34A);
    if (overallScore >= 60) return const Color(0xFFD97706);
    return const Color(0xFFE11D48);
  }

  Future<void> _handleDownloadPdf() async {
    if (_isDownloading) return;

    setState(() => _isDownloading = true);
    _showTopToast('Downloading PDF inspection report...');

    try {
      final savedPath = await DiagnosticReportPdfService.downloadOrPrintReport(
        device: widget.device,
        overallScore: overallScore,
        conditionLabel: conditionLabel,
        touchScore: widget.touchScore,
        displayScore: widget.displayScore,
        cameraScore: widget.cameraScore,
        micScore: widget.micScore,
        speakerScore: widget.speakerScore,
        sensorScore: widget.sensorScore,
        networkScore: widget.networkScore,
        gpsScore: widget.gpsScore,
        isTouchSkipped: widget.isTouchSkipped,
        isDisplaySkipped: widget.isDisplaySkipped,
        isCameraSkipped: widget.isCameraSkipped,
        isMicSkipped: widget.isMicSkipped,
        isSpeakerSkipped: widget.isSpeakerSkipped,
        isSensorSkipped: widget.isSensorSkipped,
        isNetworkSkipped: widget.isNetworkSkipped,
        isGpsSkipped: widget.isGpsSkipped,
      );

      if (mounted) {
        _showTopToast(
          savedPath != null && savedPath.contains('Download')
              ? 'PDF report downloaded successfully to Downloads folder!'
              : 'PDF report generated and ready in Downloads!',
          isError: false,
        );
      }
    } catch (e) {
      if (mounted) {
        _showTopToast('Failed to generate PDF report: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String formattedDate = DateFormat('MMM d, yyyy \'at\' h:mm a').format(DateTime.now());

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: const ReByteAppBar(),
      drawer: ReByteDrawer(
        isLoggedIn: widget.isLoggedIn,
        email: widget.email,
        name: widget.name,
        selectedIndex: 5,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Back button
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A), size: 22),
                          onPressed: () => Navigator.pop(context),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(height: 12),

                        // Title
                        const Text(
                          'Diagnostic Result',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F254B),
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Full 8/8 self-test completed on $formattedDate.',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Download Action Button (Single button)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isDownloading ? null : _handleDownloadPdf,
                            icon: _isDownloading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.download_rounded, size: 18, color: Colors.white),
                            label: Text(
                              _isDownloading ? 'Downloading PDF Report...' : 'Download Inspection Report (PDF)',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5),
                            ),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              backgroundColor: const Color(0xFF0848AA),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: const Color(0xFF0848AA).withValues(alpha: 0.6),
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                    // Overall Health Big Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0C5AD2).withValues(alpha: 0.04),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'Overall Health',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F254B),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '$overallScore',
                            style: const TextStyle(
                              fontSize: 64,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F254B),
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            '/ 100',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: conditionColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle, size: 16, color: conditionColor),
                                const SizedBox(width: 6),
                                Text(
                                  conditionLabel,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: conditionColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Component Results Header
                    const Text(
                      'Component Results',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F254B),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Component Results Card (All 8 Tests)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          // 1. Touchscreen
                          _buildComponentRow(
                            icon: Icons.touch_app_rounded,
                            title: 'Touchscreen',
                            subtitle: widget.isTouchSkipped
                                ? 'Touchscreen test skipped'
                                : (widget.touchScore >= 90
                                    ? 'Touch responsive, fully registered'
                                    : 'Partial grid response registered'),
                            score: widget.touchScore,
                            isSkipped: widget.isTouchSkipped,
                            showDivider: true,
                          ),

                          // 2. Display
                          _buildComponentRow(
                            icon: Icons.phone_android_rounded,
                            title: 'Display & Pixels',
                            subtitle: widget.isDisplaySkipped
                                ? 'Display inspection skipped'
                                : (widget.displayScore >= 85
                                    ? 'No dead pixels, uniform color'
                                    : 'Display defect issues noted'),
                            score: widget.displayScore,
                            isSkipped: widget.isDisplaySkipped,
                            showDivider: true,
                          ),

                          // 3. Camera
                          _buildComponentRow(
                            icon: Icons.camera_alt_rounded,
                            title: 'Cameras',
                            subtitle: widget.isCameraSkipped
                                ? 'Camera test skipped'
                                : (widget.cameraScore >= 85
                                    ? 'Front and rear lenses clear'
                                    : 'Camera quality defects reported'),
                            score: widget.cameraScore,
                            isSkipped: widget.isCameraSkipped,
                            showDivider: true,
                          ),

                          // 4. Microphone
                          _buildComponentRow(
                            icon: Icons.mic_rounded,
                            title: 'Microphone',
                            subtitle: widget.isMicSkipped
                                ? 'Microphone test skipped'
                                : (widget.micScore >= 85
                                    ? 'Clean voice recording, no distortion'
                                    : 'Audio clarity issues reported'),
                            score: widget.micScore,
                            isSkipped: widget.isMicSkipped,
                            showDivider: true,
                          ),

                          // 5. Speaker
                          _buildComponentRow(
                            icon: Icons.volume_up_rounded,
                            title: 'Speaker',
                            subtitle: widget.isSpeakerSkipped
                                ? 'Speaker test skipped'
                                : (widget.speakerScore >= 85
                                    ? 'Clear numeric playback confirmed'
                                    : 'Audio output mismatch / distortion'),
                            score: widget.speakerScore,
                            isSkipped: widget.isSpeakerSkipped,
                            showDivider: true,
                          ),

                          // 6. Sensors
                          _buildComponentRow(
                            icon: Icons.sensors_rounded,
                            title: 'Sensors',
                            subtitle: widget.isSensorSkipped
                                ? 'Sensors test skipped'
                                : (widget.sensorScore >= 85
                                    ? 'Accelerometer, Gyro & Proximity verified'
                                    : 'Sensor responsiveness issue detected'),
                            score: widget.sensorScore,
                            isSkipped: widget.isSensorSkipped,
                            showDivider: true,
                          ),

                          // 7. Network (Wi-Fi & Cellular)
                          _buildComponentRow(
                            icon: Icons.wifi_rounded,
                            title: 'Network & Cellular',
                            subtitle: widget.isNetworkSkipped
                                ? 'Network test skipped'
                                : (widget.networkScore >= 85
                                    ? 'Wi-Fi & Cellular HTTPS connected'
                                    : 'Network connectivity issues detected'),
                            score: widget.networkScore,
                            isSkipped: widget.isNetworkSkipped,
                            showDivider: true,
                          ),

                          // 8. GPS
                          _buildComponentRow(
                            icon: Icons.location_on_rounded,
                            title: 'GPS & Location',
                            subtitle: widget.isGpsSkipped
                                ? 'GPS test skipped'
                                : (widget.gpsScore >= 85
                                    ? 'Precision location acquired under 30s'
                                    : 'Location accuracy or stability deduction'),
                            score: widget.gpsScore,
                            isSkipped: widget.isGpsSkipped,
                            showDivider: false,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                  ],
                ),
              ),
            ),

            // Bottom CTA: Use Result in Trade-In
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    // Return or navigate to Trade-In
                    Navigator.popUntil(context, (route) => route.isFirst);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0848AA),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Use Result in Trade-In',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),

        // Floating Toast Message Overlay (matching app's standard design)
        if (_toastMessage != null)
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Dismissible(
              key: UniqueKey(),
              direction: DismissDirection.horizontal,
              onDismissed: (_) => setState(() => _toastMessage = null),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: _isToastError ? const Color(0xFFE11D48) : Colors.green.shade600,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isToastError ? Icons.error_outline : Icons.check_circle_outline,
                        color: Colors.white,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _toastMessage!,
                          textAlign: TextAlign.start,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
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
);
}

  Widget _buildComponentRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required int score,
    required bool isSkipped,
    required bool showDivider,
  }) {
    Color badgeBg;
    Color badgeText;
    if (isSkipped) {
      badgeBg = const Color(0xFFFEF3C7);
      badgeText = const Color(0xFFD97706);
    } else if (score >= 80) {
      badgeBg = const Color(0xFFDCFCE7);
      badgeText = const Color(0xFF16A34A);
    } else if (score >= 50) {
      badgeBg = const Color(0xFFFEF3C7);
      badgeText = const Color(0xFFD97706);
    } else {
      badgeBg = const Color(0xFFFFE4E6);
      badgeText = const Color(0xFFE11D48);
    }

    final String badgeLabel = isSkipped ? 'Skipped' : '$score/100';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: const Color(0xFF0C5AD2), size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isSkipped && score >= 80) ...[
                      Icon(Icons.check_circle_rounded, size: 13, color: badgeText),
                      const SizedBox(width: 4),
                    ] else if (!isSkipped && score < 50) ...[
                      Icon(Icons.cancel_rounded, size: 13, color: badgeText),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      badgeLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: badgeText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
      ],
    );
  }
}
