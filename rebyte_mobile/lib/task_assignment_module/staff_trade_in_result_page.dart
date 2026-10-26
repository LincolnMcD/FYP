import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../staff_module/staff_home_page.dart';

class StaffTradeInResultPage extends StatelessWidget {
  final bool isSuccessful;
  final double finalOfferPrice;
  final String? tradeInRequestID;
  final String? deviceModel;

  const StaffTradeInResultPage({
    super.key,
    required this.isSuccessful,
    required this.finalOfferPrice,
    this.tradeInRequestID,
    this.deviceModel,
  });

  void _navigateToAssignedTasks(BuildContext context) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => StaffHomePage(
          initialIndex: 2,
          toastMessage: isSuccessful
              ? 'Trade-in completed and payment disbursed!'
              : 'Trade-in marked as unsuccessful.',
        ),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final formattedPrice = NumberFormat('#,##0.00').format(finalOfferPrice);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _navigateToAssignedTasks(context);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Navigation: Back Arrow
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 12, bottom: 8),
              child: IconButton(
                icon: const Icon(
                  Icons.arrow_back,
                  color: Color(0xFF0F172A),
                  size: 24,
                ),
                onPressed: () => _navigateToAssignedTasks(context),
              ),
            ),

            const SizedBox(height: 16),

            // Main Card (Matching the user's design image)
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Center(
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 420),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: isSuccessful
                              ? const Color(0xFF0043CE).withValues(alpha: 0.06)
                              : const Color(0xFFDC2626).withValues(alpha: 0.06),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                      border: Border.all(
                        color: const Color(0xFFF1F5F9),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Card Header with subtle gradient tint
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(24, 36, 24, 28),
                          decoration: BoxDecoration(
                            color: isSuccessful
                                ? const Color(0xFFF0F5FF)
                                : const Color(0xFFFFF1F2),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(26),
                              topRight: Radius.circular(26),
                            ),
                          ),
                          child: Column(
                            children: [
                              // Circular Status Icon
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: isSuccessful
                                      ? const Color(0xFFD1FAE5)
                                      : const Color(0xFFFEE2E2),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: isSuccessful
                                          ? const Color(0xFF10B981)
                                          : const Color(0xFFEF4444),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      isSuccessful
                                          ? Icons.check
                                          : Icons.close_rounded,
                                      color: Colors.white,
                                      size: 26,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),

                              // Title
                              Text(
                                isSuccessful
                                    ? 'Trade-In Successful!'
                                    : 'Trade-In Rejected',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0F172A),
                                  letterSpacing: -0.5,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),

                              // Subtitle
                              Text(
                                isSuccessful
                                    ? 'Device valuation has been confirmed.'
                                    : 'Device valuation was declined or unsuccessful.',
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),

                        // Card Body
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
                          child: Column(
                            children: [
                              // Confirmed Valuation Box
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 22),
                                decoration: BoxDecoration(
                                  color: isSuccessful
                                      ? const Color(0xFFEEF2FF)
                                      : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      isSuccessful
                                          ? 'CONFIRMED VALUATION'
                                          : 'FINAL VALUATION',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.2,
                                        color: isSuccessful
                                            ? const Color(0xFF6366F1)
                                            : const Color(0xFF64748B),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.baseline,
                                      textBaseline: TextBaseline.alphabetic,
                                      children: [
                                        Text(
                                          'RM ',
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w900,
                                            color: isSuccessful
                                                ? const Color(0xFF0043CE)
                                                : const Color(0xFFDC2626),
                                          ),
                                        ),
                                        Text(
                                          formattedPrice,
                                          style: TextStyle(
                                            fontSize: 34,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: -0.8,
                                            color: isSuccessful
                                                ? const Color(0xFF0043CE)
                                                : const Color(0xFFDC2626),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 18),

                              // Payment / Trade-in Status Pill Row
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFFE2E8F0),
                                    width: 1.2,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isSuccessful
                                          ? Icons.account_balance_wallet_outlined
                                          : Icons.info_outline,
                                      size: 20,
                                      color: const Color(0xFF475569),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      isSuccessful ? 'Payment Status' : 'Trade-In Status',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF1E293B),
                                      ),
                                    ),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSuccessful
                                            ? const Color(0xFFDCFCE7)
                                            : const Color(0xFFFEE2E2),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            isSuccessful
                                                ? Icons.check_circle
                                                : Icons.cancel,
                                            size: 14,
                                            color: isSuccessful
                                                ? const Color(0xFF16A34A)
                                                : const Color(0xFFDC2626),
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            isSuccessful ? 'Success' : 'Rejected',
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w800,
                                              color: isSuccessful
                                                  ? const Color(0xFF16A34A)
                                                  : const Color(0xFFDC2626),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 22),

                              // Complete Inspection Button
                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: OutlinedButton.icon(
                                  onPressed: () => _navigateToAssignedTasks(context),
                                  icon: const Icon(
                                    Icons.fact_check_outlined,
                                    size: 19,
                                    color: Color(0xFF0F172A),
                                  ),
                                  label: const Text(
                                    'Complete Inspection',
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(
                                      color: Color(0xFFCBD5E1),
                                      width: 1.5,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    backgroundColor: Colors.white,
                                  ),
                                ),
                              ),
                            ],
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
    ),
  );
}
}
