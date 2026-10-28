import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'models/cart_item_model.dart';
import '../account_management_module/models/address_model.dart';
import '../account_management_module/models/payment_account_model.dart';
import '../account_management_module/home_page.dart';
import 'order_details_page.dart';
import '../rental_managment_module/my_rentals_page.dart';

class PaymentSuccessPage extends StatelessWidget {
  final String orderNumber;
  final double amountPaid;
  final String email;
  final String? name;
  final String paymentTitle; // e.g. '**** **** **** 4242' or 'TNG eWallet'
  final DateTime paidAt;
  final List<CartItemModel> items;
  final AddressModel? deliveryAddress;
  final PaymentAccountModel? paymentAccount;
  final bool isRental;

  const PaymentSuccessPage({
    super.key,
    required this.orderNumber,
    required this.amountPaid,
    required this.email,
    this.name,
    required this.paymentTitle,
    required this.paidAt,
    required this.items,
    this.deliveryAddress,
    this.paymentAccount,
    this.isRental = false,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy,\nhh:mm a');
    final bool effectiveIsRental = isRental || orderNumber.toUpperCase().contains('REN');

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B)),
          onPressed: () {
            if (effectiveIsRental) {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (context) => MyRentalsPage(
                    email: email,
                    name: name,
                  ),
                ),
                (route) => false,
              );
            } else {
              // Back to product page (Shop tab)
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (context) => HomePage(
                    isLoggedIn: true,
                    email: email,
                    name: name,
                    initialIndex: 1, // Shop tab
                  ),
                ),
                (route) => false,
              );
            }
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
          child: Column(
            children: [
              const SizedBox(height: 10),
              // Success Card
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    // Green check circle
                    Container(
                      width: 80,
                      height: 80,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE6F4EA),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.check_circle,
                          color: Color(0xFF10B981),
                          size: 48,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      effectiveIsRental ? 'Rental Payment Successful' : 'Payment Successful',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Your transaction has been\nsecurely processed.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF64748B),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Order Number & Amount Paid box (Separated onto different levels)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5FD),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Level 1: ORDER NUMBER
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'ORDER NUMBER',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF64748B),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  orderNumber,
                                  textAlign: TextAlign.end,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0C5AD2),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12.0),
                            child: Divider(color: Color(0xFFE2E8F0), height: 1),
                          ),
                          // Level 2: AMOUNT PAID
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'AMOUNT PAID',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF64748B),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              Text(
                                'RM${amountPaid.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Card/Payment & Receipt Sent To box (Receipt email in next line)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.credit_card, size: 20, color: Color(0xFF475569)),
                                  const SizedBox(width: 8),
                                  Text(
                                    paymentTitle,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                dateFormat.format(paidAt),
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF64748B),
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                          if (!effectiveIsRental) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12.0),
                              child: Divider(color: Color(0xFFF1F5F9), height: 1),
                            ),
                            // Receipt sent to with email on next line
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Receipt sent to',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  email,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Action buttons: Track Delivery / View My Rentals & Continue Shopping
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              if (effectiveIsRental) {
                                Navigator.pushAndRemoveUntil(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => MyRentalsPage(
                                      email: email,
                                      name: name,
                                    ),
                                  ),
                                  (route) => false,
                                );
                              } else {
                                // Open Order Details Page
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => OrderDetailsPage(
                                      orderNumber: orderNumber,
                                      amountPaid: amountPaid,
                                      email: email,
                                      name: name,
                                      paidAt: paidAt,
                                      items: items,
                                      deliveryAddress: deliveryAddress,
                                      paymentTitle: paymentTitle,
                                    ),
                                  ),
                                );
                              }
                            },
                            icon: Icon(
                              effectiveIsRental ? Icons.calendar_month_outlined : Icons.local_shipping_outlined,
                              size: 18,
                              color: Colors.white,
                            ),
                            label: Text(
                              effectiveIsRental ? 'View My Rentals' : 'Track Delivery',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0C5AD2),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              // Continue Shopping -> Back to Product Page (Shop Tab or Home)
                              Navigator.pushAndRemoveUntil(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => HomePage(
                                    isLoggedIn: true,
                                    email: email,
                                    name: name,
                                    initialIndex: effectiveIsRental ? 3 : 1, // Rental tab or Shop tab
                                  ),
                                ),
                                (route) => false,
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: const BorderSide(color: Color(0xFFCBD5E1)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              effectiveIsRental ? 'Back to Shop' : 'Continue Shopping',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
