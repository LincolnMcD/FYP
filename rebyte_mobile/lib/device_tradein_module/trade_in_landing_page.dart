import 'package:flutter/material.dart';
import 'device_info_step_page.dart';
import 'models/device_model.dart';
import 'services/trade_in_service.dart';
import 'services/trade_in_flow_session.dart';
import '../widgets/rebyte_bottom_nav_bar.dart';
import '../widgets/rebyte_app_bar.dart';
import '../account_management_module/home_page.dart';
import '../account_management_module/welcome_page.dart';
import 'my_trade_in_requests_page.dart';

class TradeInLandingPage extends StatelessWidget {
  final bool isLoggedIn;
  final String? email;
  final String? name;
  final bool isEmbedded;
  final VoidCallback? onBackToHome;

  const TradeInLandingPage({
    super.key,
    this.isLoggedIn = false,
    this.email,
    this.name,
    this.isEmbedded = false,
    this.onBackToHome,
  });

  void _handleBack(BuildContext context) {
    if (isEmbedded) {
      if (onBackToHome != null) {
        onBackToHome!();
      }
      return;
    }
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => HomePage(
            isLoggedIn: isLoggedIn,
            email: email,
            name: name,
          ),
        ),
      );
    }
  }

  void _startFreshFlow(BuildContext context) {
    if (isLoggedIn && email != null && email!.isNotEmpty) {
      TradeInService.cancelTradeInRequests(email!).catchError((_) => {'success': false});
    }
    TradeInFlowSession.clear();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DeviceInfoStepPage(
          isLoggedIn: isLoggedIn,
          email: email,
          name: name,
        ),
      ),
    );
  }

  void _resumePendingFlow(
    BuildContext context,
    String tradeInRequestId,
    Map<String, dynamic>? devData,
  ) {
    DeviceModel? dev;
    if (devData != null) {
      dev = DeviceModel.fromJson(devData);
    }
    TradeInFlowSession.startOrResume(
      tradeInRequestId: tradeInRequestId,
      device: dev,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DeviceInfoStepPage(
          isLoggedIn: isLoggedIn,
          email: email,
          name: name,
        ),
      ),
    );
  }

  void _showTradeInRequestsModal(BuildContext context) async {
    if (!isLoggedIn) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const WelcomePage()),
      );
      return;
    }

    // Show loading dialog while fetching pending request
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF0C5AD2)),
      ),
    );

    Map<String, dynamic>? pendingReq;
    Map<String, dynamic>? devData;

    try {
      final res = await TradeInService.getActivePendingTradeIn(email ?? '');
      if (res['success'] == true && res['pendingRequest'] != null) {
        pendingReq = res['pendingRequest'];
        devData = res['device'];
      }
    } catch (_) {}

    if (context.mounted) {
      Navigator.pop(context); // close loader
    }

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Icon(
                pendingReq != null ? Icons.pending_actions_rounded : Icons.inventory_2_outlined,
                size: 52,
                color: const Color(0xFF0C5AD2),
              ),
              const SizedBox(height: 12),
              Text(
                pendingReq != null ? 'Pending Trade-In Evaluation' : 'Trade-In Requests',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 8),
              if (pendingReq != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Request ID: ${pendingReq['tradeInRequestID'] ?? ''}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0C5AD2),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  devData != null
                      ? 'You have an ongoing evaluation for ${devData['brand']} ${devData['model']}. You can resume your session or start a new trade-in.'
                      : 'You have an active pending trade-in request. Would you like to resume your session?',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _resumePendingFlow(
                      context,
                      pendingReq!['tradeInRequestID'],
                      devData,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0C5AD2),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Resume Trade-In', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _startFreshFlow(context);
                  },
                  style: ElevatedButton.styleFrom(
                    foregroundColor: const Color(0xFF64748B),
                    minimumSize: const Size(double.infinity, 44),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Start New Trade-In', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ] else ...[
                const Text(
                  'You do not have any active trade-in evaluations at the moment. Start a new evaluation to trade in your device!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _startFreshFlow(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0C5AD2),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Start Trade-In Now', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Top back button row
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A), size: 22),
              onPressed: () => _handleBack(context),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
          const SizedBox(height: 12),

          // Header Title
          const Text(
            'Trade-In Your\nTech',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
              height: 1.15,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),

          // Subtitle
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.0),
            child: Text(
              'Upgrade your gear or get cash back. Our transparent 7-step process ensures you get the best value for your professional equipment.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF475569),
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Ready to Upgrade Card
          _buildReadyToUpgradeCard(context),
          const SizedBox(height: 24),

          // How It Works Card
          _buildHowItWorksCard(),
          const SizedBox(height: 20),

          // Why Trade-In with ReByte Card
          _buildWhyTradeInCard(),
          const SizedBox(height: 32),
        ],
      ),
    );

    if (isEmbedded) {
      return content;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: const ReByteAppBar(),
      drawer: ReByteDrawer(
        isLoggedIn: isLoggedIn,
        email: email,
        name: name,
        selectedIndex: 2,
      ),
      body: content,
      bottomNavigationBar: const ReByteBottomNavBar(
        selectedIndex: 2,
      ),
    );
  }

  Widget _buildReadyToUpgradeCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Icon badge
          Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(
              color: Color(0xFFEFF6FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.recycling_rounded,
              color: Color(0xFF0C5AD2),
              size: 32,
            ),
          ),
          const SizedBox(height: 16),

          // Title
          const Text(
            'Ready to Upgrade?',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),

          // Subtitle
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              'Start your trade-in evaluation now to lock in your offer for 14 days.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: Color(0xFF64748B),
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Start Trade-In -> Button
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: () {
                if (!isLoggedIn) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const WelcomePage()),
                  );
                  return;
                }
                _startFreshFlow(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0C5AD2),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Start Trade-In',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, size: 16),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // View Trade-In Requests Button
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton(
              onPressed: () {
                if (!isLoggedIn) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const WelcomePage()),
                  );
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MyTradeInRequestsPage(
                      email: email ?? '',
                      name: name,
                      isLoggedIn: isLoggedIn,
                    ),
                  ),
                );
              },
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0F172A),
                side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              child: const Text(
                'View Trade-In Requests',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorksCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'How It Works',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 12),
          Divider(color: Colors.grey.shade200, height: 1),
          const SizedBox(height: 16),

          // Steps 1 to 7 timeline
          _buildStepItem(
            stepNumber: 1,
            title: 'Device Info',
            description: 'Select your device category, brand, and model to start the valuation.',
            icon: Icons.devices_rounded,
            isLast: false,
          ),
          _buildStepItem(
            stepNumber: 2,
            title: 'Upload Images',
            description: 'Provide clear photos of the front, back, and any visible wear.',
            icon: Icons.camera_alt_outlined,
            isLast: false,
          ),
          _buildStepItem(
            stepNumber: 3,
            title: 'IMEI/Serial Validation',
            description: 'Enter your serial number to confirm authenticity and eligibility.',
            icon: Icons.badge_outlined,
            isLast: false,
          ),
          _buildStepItem(
            stepNumber: 4,
            title: 'Optional Self-Test',
            description: 'Run our diagnostic tool to boost your initial offer accuracy.',
            icon: Icons.verified_user_outlined,
            isLast: false,
          ),
          _buildStepItem(
            stepNumber: 5,
            title: 'Condition Assessment',
            description: 'Answer a few questions about physical and functional condition.',
            icon: Icons.format_list_bulleted_rounded,
            isLast: false,
          ),
          _buildStepItem(
            stepNumber: 6,
            title: 'Preliminary Quotation',
            description: 'Receive an instant estimate based on the provided details.',
            icon: Icons.request_quote_outlined,
            isLast: false,
          ),
          _buildStepItem(
            stepNumber: 7,
            title: 'Accept Offer',
            description: 'Confirm the trade-in and receive your shipping label.',
            icon: Icons.local_shipping_outlined,
            isLast: true,
            isDarkHighlight: true,
          ),
        ],
      ),
    );
  }

  Widget _buildStepItem({
    required int stepNumber,
    required String title,
    required String description,
    required IconData icon,
    required bool isLast,
    bool isDarkHighlight = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left column: Icon circle + vertical connecting line
        Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isDarkHighlight ? const Color(0xFF0C5AD2) : const Color(0xFFEFF6FF),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isDarkHighlight ? Colors.white : const Color(0xFF0C5AD2),
                size: 20,
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 44,
                color: const Color(0xFFE2E8F0),
              ),
          ],
        ),
        const SizedBox(width: 14),

        // Right column: Step info
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'STEP $stepNumber',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWhyTradeInCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDBEAFE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, color: Color(0xFF0C5AD2), size: 18),
              SizedBox(width: 8),
              Text(
                'Why Trade-In with ReByte?',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildBenefitRow('Guaranteed highest value for professional gear.'),
          const SizedBox(height: 8),
          _buildBenefitRow('Secure data wipe certification included.'),
          const SizedBox(height: 8),
          _buildBenefitRow('Free insured shipping on all accepted trades.'),
        ],
      ),
    );
  }

  Widget _buildBenefitRow(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF10B981), size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF334155),
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}
