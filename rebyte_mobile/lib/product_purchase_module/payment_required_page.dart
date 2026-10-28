import 'package:flutter/material.dart';
import '../account_management_module/services/xendit_service.dart';
import '../account_management_module/widgets/add_payment_account_dialog.dart';

class PaymentRequiredPage extends StatefulWidget {
  final String email;
  final VoidCallback onPaymentAccountLinked;

  const PaymentRequiredPage({
    super.key,
    required this.email,
    required this.onPaymentAccountLinked,
  });

  @override
  State<PaymentRequiredPage> createState() => _PaymentRequiredPageState();
}

class _PaymentRequiredPageState extends State<PaymentRequiredPage> {
  bool _isChecking = false;

  void _openAddPaymentAccount() {
    AddPaymentAccountDialog.show(
      context: context,
      email: widget.email,
      hasExistingCards: false,
      onCardAdded: () async {
        setState(() => _isChecking = true);
        try {
          final cards = await XenditService.fetchSavedCards(widget.email);
          if (mounted) {
            setState(() => _isChecking = false);
            if (cards.isNotEmpty) {
              Navigator.pop(context, true);
              widget.onPaymentAccountLinked();
            }
          }
        } catch (_) {
          if (mounted) {
            setState(() => _isChecking = false);
            Navigator.pop(context, true);
            widget.onPaymentAccountLinked();
          }
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9), // Light grey background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Top Circle Icon
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      color: Color(0xFF0C5AD2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Title
                  const Text(
                    'Payment Required',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F254B),
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Subtitle
                  const Text(
                    'To continue with your rental, please\nlink a verified payment account.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: Color(0xFF64748B),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Feature 1: Security & Trust
                  _buildFeatureItem(
                    icon: Icons.shield_outlined,
                    iconColor: const Color(0xFF10B981),
                    title: 'Security & Trust',
                    description: 'We verify your identity to ensure a safe rental community for high-end tech.',
                  ),
                  const SizedBox(height: 20),

                  // Feature 2: Seamless Recurring Payments
                  _buildFeatureItem(
                    icon: Icons.credit_card_outlined,
                    iconColor: const Color(0xFF0C5AD2),
                    title: 'Seamless Recurring Payments',
                    description: 'Your monthly rental fees will be automatically processed.',
                  ),
                  const SizedBox(height: 20),

                  // Feature 3: Deposit Hold
                  _buildFeatureItem(
                    icon: Icons.lock_outline,
                    iconColor: const Color(0xFFF59E0B),
                    title: 'Deposit Hold',
                    description: 'A temporary hold may be placed on your account as a security deposit.',
                  ),
                  const SizedBox(height: 32),

                  // Add Payment Account Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _isChecking ? null : _openAddPaymentAccount,
                      icon: _isChecking
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.add, size: 20, color: Colors.white),
                      label: Text(
                        _isChecking ? 'Checking...' : 'Add Payment Account',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0C5AD2),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Encrypted footer note
                  const Text(
                    'Your data is encrypted and securely processed.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: iconColor),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 3),
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
      ],
    );
  }
}
