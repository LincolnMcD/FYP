import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../device_tradein_module/models/device_model.dart';
import '../widgets/rebyte_app_bar.dart';
import '../widgets/rebyte_bottom_nav_bar.dart';

class DiagnosticResultPage extends StatelessWidget {
  final DeviceModel? device;
  final String? tradeInRequestID;
  final bool isLoggedIn;
  final String? email;
  final String? name;
  final int touchScore; // 0 - 100
  final int displayScore; // 0 - 100
  final int cameraScore; // 0 - 100
  final int micScore; // 0 - 100
  final bool isTouchSkipped;
  final bool isDisplaySkipped;
  final bool isCameraSkipped;
  final bool isMicSkipped;

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
    this.isTouchSkipped = false,
    this.isDisplaySkipped = false,
    this.isCameraSkipped = false,
    this.isMicSkipped = false,
  });

  int get overallScore {
    // Average of touch, display, camera, and microphone scores
    return ((touchScore + displayScore + cameraScore + micScore) / 4).round().clamp(0, 100);
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

  @override
  Widget build(BuildContext context) {
    final String formattedDate = DateFormat('MMM d, yyyy \'at\' h:mm a').format(DateTime.now());

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: const ReByteAppBar(),
      drawer: ReByteDrawer(
        isLoggedIn: isLoggedIn,
        email: email,
        name: name,
        selectedIndex: 2,
      ),
      body: SafeArea(
        child: Column(
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
                      'Self-test completed on $formattedDate.',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Download & Export Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Diagnostic summary report downloaded.')),
                              );
                            },
                            icon: const Icon(Icons.download_rounded, size: 16, color: Color(0xFF0F172A)),
                            label: const Text(
                              'Download',
                              style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              side: const BorderSide(color: Color(0xFFCBD5E1)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              backgroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Diagnostic report link ready to share.')),
                              );
                            },
                            icon: const Icon(Icons.share_outlined, size: 16, color: Color(0xFF0F172A)),
                            label: const Text(
                              'Export',
                              style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              side: const BorderSide(color: Color(0xFFCBD5E1)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              backgroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
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

                    // Component Results Card
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          // Test 1: Touchscreen
                          _buildComponentRow(
                            icon: Icons.touch_app_rounded,
                            title: 'Display & Touch',
                            subtitle: isTouchSkipped
                                ? 'Touchscreen test skipped'
                                : (touchScore >= 90
                                    ? 'Touch responsive, fully registered'
                                    : 'Partial grid response registered'),
                            score: touchScore,
                            isSkipped: isTouchSkipped,
                            showDivider: true,
                          ),

                          // Test 2: Display
                          _buildComponentRow(
                            icon: Icons.desktop_windows_rounded,
                            title: 'Display & Pixels',
                            subtitle: isDisplaySkipped
                                ? 'Display inspection skipped'
                                : (displayScore >= 85
                                    ? 'No dead pixels, uniform color'
                                    : 'Display defect issues noted'),
                            score: displayScore,
                            isSkipped: isDisplaySkipped,
                            showDivider: true,
                          ),

                          // Connectivity (Future/Placeholder)
                          _buildComponentRow(
                            icon: Icons.wifi_rounded,
                            title: 'Connectivity',
                            subtitle: 'GPS and Wi-Fi functional',
                            score: 100,
                            isSkipped: false,
                            showDivider: true,
                          ),

                          // Test 3: Cameras
                          _buildComponentRow(
                            icon: Icons.camera_alt_rounded,
                            title: 'Cameras',
                            subtitle: isCameraSkipped
                                ? 'Camera test skipped'
                                : (cameraScore >= 85
                                    ? 'Front and rear lenses clear'
                                    : 'Camera quality defects reported'),
                            score: cameraScore,
                            isSkipped: isCameraSkipped,
                            showDivider: true,
                          ),

                          // Test 4: Microphone
                          _buildComponentRow(
                            icon: Icons.mic_rounded,
                            title: 'Microphone',
                            subtitle: isMicSkipped
                                ? 'Microphone test skipped'
                                : (micScore >= 85
                                    ? 'Clean voice recording, no distortion'
                                    : 'Audio clarity issues reported'),
                            score: micScore,
                            isSkipped: isMicSkipped,
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
