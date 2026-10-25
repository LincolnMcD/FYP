import 'package:flutter/material.dart';
import 'models/device_model.dart';
import 'services/trade_in_flow_session.dart';
import 'services/trade_in_service.dart';
import '../widgets/rebyte_app_bar.dart';
import '../widgets/rebyte_bottom_nav_bar.dart';
import '../account_management_module/home_page.dart';
import 'my_trade_in_requests_page.dart';
import 'trade_in_request_created_page.dart';

class PreliminaryQuotationPage extends StatefulWidget {
  final DeviceModel device;
  final String tradeInRequestID;
  final bool isLoggedIn;
  final String? email;
  final String? name;
  final String? estimatedValue;
  final bool fromMyTradeInRequests;

  const PreliminaryQuotationPage({
    super.key,
    required this.device,
    required this.tradeInRequestID,
    this.isLoggedIn = false,
    this.email,
    this.name,
    this.estimatedValue,
    this.fromMyTradeInRequests = false,
  });

  @override
  State<PreliminaryQuotationPage> createState() =>
      _PreliminaryQuotationPageState();
}

class _PreliminaryQuotationPageState extends State<PreliminaryQuotationPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isProcessingAction = false;

  @override
  void initState() {
    super.initState();
    // Mark session as having reached Page 8 (Preliminary Quotation / Quoted)
    TradeInFlowSession.currentUserEmail = widget.email;
    TradeInFlowSession.currentStep = 8;
    TradeInFlowSession.setTradeInRequestId(widget.tradeInRequestID);
    TradeInFlowSession.setCurrentDevice(widget.device);

    // Update tradeInRequest status in database to 'Quoted' with estimatedValue (min & max double)
    if (widget.tradeInRequestID.isNotEmpty) {
      double minD = 2340.50;
      double maxD = 2355.30;
      if (widget.estimatedValue != null && widget.estimatedValue!.isNotEmpty) {
        final clean = widget.estimatedValue!.replaceAll('RM', '').replaceAll(',', '');
        final parts = clean.split(RegExp(r'\s*-\s*'));
        if (parts.length >= 2) {
          minD = double.tryParse(parts[0].trim()) ?? 2340.50;
          maxD = double.tryParse(parts[1].trim()) ?? 2355.30;
        } else if (parts.isNotEmpty) {
          final val = double.tryParse(parts[0].trim()) ?? 2340.50;
          minD = val;
          maxD = val;
        }
      }
      TradeInService.updateTradeInStatus(
        tradeInRequestID: widget.tradeInRequestID,
        status: 'Quoted',
        estimatedValue: {
          'min': minD,
          'max': maxD,
        },
      );
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
    // Keep TradeInFlowSession intact so the active block is visible
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

  // Blue Button: Accept Offer -> Status Agreed -> Navigate to TradeInRequestCreatedPage
  Future<void> _onAcceptOffer() async {
    if (_isProcessingAction) return;
    setState(() => _isProcessingAction = true);

    try {
      if (widget.tradeInRequestID.isNotEmpty) {
        await TradeInService.updateTradeInStatus(
          tradeInRequestID: widget.tradeInRequestID,
          status: 'Agreed',
        );
      }
    } catch (_) {}

    // Clear active session memory & storage so the active activity block disappears
    TradeInFlowSession.clear();

    if (!mounted) return;
    setState(() => _isProcessingAction = false);

    final cleanId = widget.tradeInRequestID.replaceAll('#', '').trim();
    final priceStr = widget.estimatedValue ?? 'RM 2,340.50 - RM 2,355.30';

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => TradeInRequestCreatedPage(
          tradeInRequestID: cleanId.isNotEmpty ? cleanId : 'TRD-8992-BX',
          device: widget.device,
          estimatedValue: priceStr,
          isLoggedIn: widget.isLoggedIn,
          email: widget.email,
          name: widget.name,
          isRejected: false,
          fromMyTradeInRequests: widget.fromMyTradeInRequests,
        ),
      ),
    );
  }

  // Red Button: Decline Offer -> Status Rejected -> Navigate to TradeInRequestCreatedPage (Rejected state)
  Future<void> _onDeclineOffer() async {
    if (_isProcessingAction) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Decline Quotation?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        content: const Text(
          'Are you sure you want to decline this trade-in offer? This request will be closed.',
          style: TextStyle(fontSize: 14, color: Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Decline'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isProcessingAction = true);

    try {
      if (widget.tradeInRequestID.isNotEmpty) {
        await TradeInService.updateTradeInStatus(
          tradeInRequestID: widget.tradeInRequestID,
          status: 'Declined',
        );
      }
    } catch (_) {}

    // Clear active session memory & storage so active activity block is removed
    TradeInFlowSession.clear();

    if (!mounted) return;
    setState(() => _isProcessingAction = false);

    final cleanId = widget.tradeInRequestID.replaceAll('#', '').trim();
    final priceStr = widget.estimatedValue ?? 'RM 2,340.50 - RM 2,355.30';

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => TradeInRequestCreatedPage(
          tradeInRequestID: cleanId.isNotEmpty ? cleanId : 'TRD-8992-BX',
          device: widget.device,
          estimatedValue: priceStr,
          isLoggedIn: widget.isLoggedIn,
          email: widget.email,
          name: widget.name,
          isRejected: true,
          fromMyTradeInRequests: widget.fromMyTradeInRequests,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    final String brand = device.brand.trim();
    final String model = device.model.trim();
    final bool hasBrand = model.toLowerCase().startsWith(brand.toLowerCase());
    final String fullDeviceName = hasBrand ? model : '$brand $model'.trim();
    final String storage = device.storageCapacity.isNotEmpty ? device.storageCapacity : '128GB';
    final String colour = device.colour.isNotEmpty ? device.colour : 'Graphite';
    final String reqDisplayId = widget.tradeInRequestID.isNotEmpty
        ? widget.tradeInRequestID
        : 'RB-8492-TX';

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
                const SizedBox(height: 12),

                // Quotation ID
                Text(
                  'QUOTATION ID: #$reqDisplayId',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 6),

                // Title
                const Text(
                  'Preliminary Trade-In Quotation',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 10),

                // Estimated Value Badge + Valid for 14 days
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.info_outline_rounded, size: 13, color: Color(0xFF0C5AD2)),
                          SizedBox(width: 4),
                          Text(
                            'Estimated Value',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0C5AD2),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Valid for 14 days',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // 1. Estimated Trade-In Value Card
                _buildValueCard(),
                const SizedBox(height: 16),

                // 2. Device Overview Card
                _buildDeviceOverviewCard(fullDeviceName, storage, colour),
                const SizedBox(height: 16),

                // 3. Price Influencing Factors Card
                _buildFactorsCard(),
                const SizedBox(height: 24),

                // Accept Offer Button (Solid Blue)
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isProcessingAction ? null : _onAcceptOffer,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0C5AD2),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isProcessingAction
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_rounded, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Accept Offer',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 12),

                // Decline Offer Button (Red / Orange Accent)
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isProcessingAction ? null : _onDeclineOffer,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF4D26),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.close_rounded, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Decline Offer',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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

  String _formatDisplayValue(String raw) {
    if (raw.contains(' - ')) {
      final parts = raw.split(' - ');
      final minPart = parts[0].trim().replaceAll('RM ', 'RM\u00A0');
      final maxPart = parts[1].trim().replaceAll('RM ', 'RM\u00A0');
      return '$minPart -\n$maxPart';
    } else if (raw.contains('-')) {
      final parts = raw.split('-');
      final minPart = parts[0].trim().replaceAll('RM ', 'RM\u00A0');
      final maxPart = parts[1].trim().replaceAll('RM ', 'RM\u00A0');
      return '$minPart -\n$maxPart';
    }
    return raw.replaceAll('RM ', 'RM\u00A0');
  }

  Widget _buildValueCard() {
    final rawValue = widget.estimatedValue ?? 'RM 2,340.50 - RM 2,355.30';
    final displayValue = _formatDisplayValue(rawValue);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
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
            'Estimated Trade-In Value',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            displayValue,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0C5AD2),
              height: 1.2,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Based on your device description. Final value\nsubject to physical inspection.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceOverviewCard(String fullDeviceName, String storage, String colour) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
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
          // Graphic thumbnail of smartphone
          Center(
            child: Container(
              height: 90,
              width: 140,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Icon(
                  Icons.phone_iphone_rounded,
                  size: 48,
                  color: Color(0xFF64748B),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Title
          Text(
            fullDeviceName.isNotEmpty ? fullDeviceName : 'Smartphone',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),

          // Specs subtitle
          Text(
            '$storage • $colour',
            style: const TextStyle(
              fontSize: 12.5,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 10),

          // Condition: Good badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Condition: Good',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0C5AD2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFactorsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
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
            'Price Influencing Factors',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          const Divider(height: 16, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 6),

          // Factor 1: Flawless Screen
          _buildFactorItem(
            icon: Icons.check_circle_outline_rounded,
            iconColor: const Color(0xFF10B981),
            title: 'Flawless Screen',
            description: 'No scratches or cracks detected.',
          ),
          const SizedBox(height: 14),

          // Factor 2: Battery Health (82%)
          _buildFactorItem(
            icon: Icons.battery_alert_rounded,
            iconColor: const Color(0xFFF59E0B),
            title: 'Battery Health (82%)',
            description: 'Slight deduction for battery degradation.',
          ),
          const SizedBox(height: 14),

          // Factor 3: Fully Functional
          _buildFactorItem(
            icon: Icons.check_circle_outline_rounded,
            iconColor: const Color(0xFF10B981),
            title: 'Fully Functional',
            description: 'All buttons and cameras working perfectly.',
          ),
        ],
      ),
    );
  }

  Widget _buildFactorItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
