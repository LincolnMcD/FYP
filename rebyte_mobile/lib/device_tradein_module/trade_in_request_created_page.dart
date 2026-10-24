import 'package:flutter/material.dart';
import 'inspection_method_page.dart';
import 'models/device_model.dart';
import 'my_trade_in_requests_page.dart';

import 'services/trade_in_flow_session.dart';

class TradeInRequestCreatedPage extends StatelessWidget {
  final String tradeInRequestID;
  final DeviceModel? device;
  final String estimatedValue;
  final bool isLoggedIn;
  final String? email;
  final String? name;
  final bool isRejected;
  final bool fromMyTradeInRequests;

  const TradeInRequestCreatedPage({
    super.key,
    required this.tradeInRequestID,
    this.device,
    this.estimatedValue = 'RM 2,340.50 - RM 2,355.30',
    this.isLoggedIn = true,
    this.email,
    this.name,
    this.isRejected = false,
    this.fromMyTradeInRequests = false,
  });

  void _onBackToTradeInRequests(BuildContext context) {
    final effectiveEmail = (email != null && email!.trim().isNotEmpty)
        ? email!.trim()
        : (TradeInFlowSession.currentUserEmail ?? 'customer@rebyte.com');

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => MyTradeInRequestsPage(
          email: effectiveEmail,
          name: name,
          isLoggedIn: isLoggedIn,
        ),
      ),
      (route) => route.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    final devName = device != null
        ? '${device!.brand} ${device!.model}'.replaceAll('Apple Apple', 'Apple').trim()
        : 'iPhone 13 Pro';
    final storage = device?.storageCapacity.isNotEmpty == true ? device!.storageCapacity : '128GB';
    final colour = device?.colour.isNotEmpty == true ? device!.colour : 'Graphite';
    final formattedReqId = tradeInRequestID.startsWith('#') ? tradeInRequestID : '#$tradeInRequestID';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _onBackToTradeInRequests(context);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Top Back Button
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A), size: 24),
                    onPressed: () => _onBackToTradeInRequests(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ),
                const SizedBox(height: 20),

              // Circular Success / Rejection Icon with Halo
              Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  color: isRejected ? const Color(0xFFFEE2E2) : const Color(0xFFD1FAE5),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: isRejected ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isRejected ? Icons.close_rounded : Icons.check_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Title
              Text(
                isRejected ? 'Request Declined' : 'Request Created',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),

              // Subtitle
              Text(
                isRejected
                    ? 'Your trade-in offer has been declined and this request is closed.'
                    : 'Your trade-in has been successfully registered.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14.5,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 28),

              // Card 1: Request & Device Overview
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
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
                    // REQUEST ID Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'REQUEST ID',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF64748B),
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          formattedReqId,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: isRejected ? const Color(0xFFDC2626) : const Color(0xFF0C5AD2),
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    const SizedBox(height: 16),

                    // Device row
                    Row(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: isRejected ? const Color(0xFFFEF2F2) : const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.phone_iphone_rounded,
                            size: 28,
                            color: isRejected ? const Color(0xFFDC2626) : const Color(0xFF334155),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                devName,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$storage • $colour • Good Condition',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Inner Value Box
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isRejected ? const Color(0xFFFECACA) : const Color(0xFFDBEAFE),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Estimated Value',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            estimatedValue.replaceAll('RM ', 'RM\u00A0'),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isRejected ? const Color(0xFFFEF2F2) : const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isRejected ? const Color(0xFFFECACA) : const Color(0xFFBFDBFE),
                              ),
                            ),
                            child: Text(
                              isRejected ? 'Declined' : 'Pending Inspection',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: isRejected ? const Color(0xFFDC2626) : const Color(0xFF2563EB),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Card 2: Next Steps (Only shown when accepted / not rejected)
              if (!isRejected) ...[
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
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
                        'Next Steps',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Choose how you\'d like to hand over your device for final inspection to confirm the quoted value.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => InspectionMethodPage(
                                  tradeInRequestID: tradeInRequestID,
                                  device: device,
                                  estimatedValue: estimatedValue,
                                  email: email,
                                  name: name,
                                  isLoggedIn: isLoggedIn,
                                  fromMyTradeInRequests: fromMyTradeInRequests,
                                ),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0C5AD2),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.calendar_month_outlined, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Book Inspection',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 28),

              // Return to Trade-In Requests Link
              TextButton(
                onPressed: () => _onBackToTradeInRequests(context),
                child: const Text(
                  'Back to Trade-In Requests',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF334155),
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    ),
  );
  }
}
