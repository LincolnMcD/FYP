import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../widgets/rebyte_app_bar.dart';
import '../../widgets/rebyte_bottom_nav_bar.dart';
import 'rental_payment_confirmation_page.dart';
import 'rental_renew_page.dart';

class RentalDeviceDetailPage extends StatefulWidget {
  final Map<String, dynamic> rental;
  final String email;
  final String? name;

  const RentalDeviceDetailPage({
    super.key,
    required this.rental,
    required this.email,
    this.name,
  });

  @override
  State<RentalDeviceDetailPage> createState() => _RentalDeviceDetailPageState();
}

class _RentalDeviceDetailPageState extends State<RentalDeviceDetailPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String _formatDate(dynamic dateVal) {
    if (dateVal == null) return '';
    try {
      final dt = DateTime.parse(dateVal.toString());
      return DateFormat('MMM dd, yyyy').format(dt);
    } catch (_) {
      return dateVal.toString();
    }
  }

  int _calculateDaysRemaining(dynamic expiryVal) {
    if (expiryVal != null && expiryVal.toString().isNotEmpty) {
      try {
        final expiry = DateTime.parse(expiryVal.toString());
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final expDate = DateTime(expiry.year, expiry.month, expiry.day);
        return expDate.difference(today).inDays;
      } catch (_) {}
    }
    return 0;
  }

  void _navigateToPaymentConfirmation() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RentalPaymentConfirmationPage(
          rental: widget.rental,
          email: widget.email,
          name: widget.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rental = widget.rental;
    final product = rental['product'] as Map<String, dynamic>? ?? {};
    final device = rental['device'] as Map<String, dynamic>? ?? {};

    // Product Title
    String title = product['listingTitle']?.toString() ?? '';
    if (title.isEmpty) {
      final brand = device['brand']?.toString() ?? '';
      final model = device['model']?.toString() ?? '';
      title = '$brand $model'.trim();
    }
    if (title.isEmpty) title = 'iPhone 12';

    // Subtitle (Storage • Color)
    final storage = device['storage']?.toString() ?? product['storage']?.toString() ?? '256GB';
    final color = device['color']?.toString() ?? product['color']?.toString() ?? 'Graphite';
    final specsSubtitle = '$storage • $color';

    // Image URL
    String imageUrl = product['imageUrl']?.toString() ?? '';
    if (imageUrl.isEmpty && product['images'] is List && (product['images'] as List).isNotEmpty) {
      imageUrl = product['images'][0].toString();
    }

    // Days remaining
    final daysRemaining = _calculateDaysRemaining(rental['rentalExpiryDate'] ?? rental['endDate']);
    final isOverdue = daysRemaining < 0;
    final statusText = isOverdue
        ? 'OVERDUE - ${daysRemaining.abs()} DAYS LATE'
        : 'ACTIVE - $daysRemaining DAYS REMAINING';

    // Agreement Details
    final agreementId = rental['rentalID']?.toString() ?? 'RNT-8492-LNS';
    final imei = device['imei']?.toString() ??
        device['serialNumber']?.toString() ??
        rental['productID']?.toString() ??
        '35 123456 789012 3';
    // Fully Paid check: endDate <= rentalExpiryDate
    bool isFullyPaid = false;
    final endStr = rental['endDate']?.toString();
    final expiryStr = rental['rentalExpiryDate']?.toString();
    if (endStr != null && endStr.isNotEmpty && expiryStr != null && expiryStr.isNotEmpty) {
      try {
        final end = DateTime.parse(endStr);
        final expiry = DateTime.parse(expiryStr);
        final endD = DateTime(end.year, end.month, end.day);
        final expD = DateTime(expiry.year, expiry.month, expiry.day);
        if (expD.isAtSameMomentAs(endD) || expD.isAfter(endD)) {
          isFullyPaid = true;
        }
      } catch (_) {}
    }

    final startDate = _formatDate(rental['startDate']);
    final endDate = _formatDate(rental['endDate']);

    final monthlyFee = rental['monthlyRentalFee'] != null
        ? 'RM ${rental['monthlyRentalFee']}/mth'
        : '';

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: ReByteAppBar(
        scaffoldKey: _scaffoldKey,
      ),
      drawer: ReByteDrawer(
        isLoggedIn: true,
        email: widget.email,
        name: widget.name,
        isRentalsSelected: true,
      ),
      bottomNavigationBar: const ReByteBottomNavBar(
        selectedIndex: 3,
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Navigation Row (Back Button)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B), size: 22),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => Navigator.pop(context),
              ),
            ),

            // Header Title
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
              child: Text(
                'Rental Details',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),

            const SizedBox(height: 6),

            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Main White Image Card with Status Pill
                    Container(
                      width: double.infinity,
                      height: 250,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                        border: Border.all(color: const Color(0xFFF1F5F9)),
                      ),
                      child: Stack(
                        children: [
                          // Device Image Centered
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(28.0),
                              child: imageUrl.isNotEmpty
                                  ? Image.network(
                                      imageUrl,
                                      fit: BoxFit.contain,
                                      errorBuilder: (context, error, stackTrace) => const Icon(
                                        Icons.phone_android,
                                        size: 100,
                                        color: Color(0xFF94A3B8),
                                      ),
                                    )
                                  : const Icon(
                                      Icons.phone_android,
                                      size: 100,
                                      color: Color(0xFF94A3B8),
                                    ),
                            ),
                          ),

                          // Top-Left Status Pill
                          Positioned(
                            top: 14,
                            left: 14,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: isOverdue ? const Color(0xFFFFECE6) : const Color(0xFF5CE3D9),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isOverdue ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                                    size: 13,
                                    color: isOverdue ? const Color(0xFFEA580C) : const Color(0xFF0F766E),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    statusText,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      color: isOverdue ? const Color(0xFFEA580C) : const Color(0xFF0F766E),
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Device Title & Subtitle + Monthly Fee
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                specsSubtitle,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (monthlyFee.isNotEmpty) ...[
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFBFDBFE)),
                            ),
                            child: Text(
                              monthlyFee,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF003F9E),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 22),

                    // Full-width Pay Rental Button (Disabled with gray overlay when endDate == rentalExpiryDate)
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: isFullyPaid ? null : _navigateToPaymentConfirmation,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0C5AD2),
                          disabledBackgroundColor: const Color(0xFFCBD5E1),
                          disabledForegroundColor: const Color(0xFF94A3B8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        icon: Icon(
                          Icons.payments_outlined,
                          color: isFullyPaid ? const Color(0xFF94A3B8) : Colors.white,
                          size: 20,
                        ),
                        label: Text(
                          isFullyPaid ? 'Rental Fully Paid' : 'Pay Rental',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isFullyPaid ? const Color(0xFF94A3B8) : Colors.white,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // 2x2 Action Grid:
                    // Row 1: Renew Rental | Buyout Device
                    Row(
                      children: [
                        // Renew Rental
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final nav = Navigator.of(context);
                              final updated = await nav.push(
                                MaterialPageRoute(
                                  builder: (context) => RentalRenewPage(
                                    rental: widget.rental,
                                    email: widget.email,
                                    name: widget.name,
                                  ),
                                ),
                              );
                              if (updated == true && mounted) {
                                nav.pop(true);
                              }
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              height: 80,
                              decoration: BoxDecoration(
                                color: const Color(0xFF003F9E),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.sync, color: Colors.white, size: 20),
                                  SizedBox(height: 6),
                                  Text(
                                    'Renew Rental',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),

                        // Buyout Device
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Buyout device for $agreementId coming soon.')),
                              );
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              height: 80,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.shopping_cart_outlined, color: Color(0xFF0C5AD2), size: 20),
                                  SizedBox(height: 6),
                                  Text(
                                    'Buyout Device',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0C5AD2),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // Row 2: Return Device | Report Missing
                    Row(
                      children: [
                        // Return Device
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Return request initiated for $agreementId.')),
                              );
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              height: 80,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.keyboard_return, color: Color(0xFF0F172A), size: 20),
                                  SizedBox(height: 6),
                                  Text(
                                    'Return Device',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),

                        // Report Missing (Light red container)
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Report missing for $agreementId initiated.')),
                              );
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              height: 80,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFE4E6),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.error_outline, color: Color(0xFFBE123C), size: 20),
                                  SizedBox(height: 6),
                                  Text(
                                    'Report Missing',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF9F1239),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Card 3: Agreement Details Box
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header
                          const Row(
                            children: [
                              Icon(Icons.description_outlined, color: Color(0xFF0C5AD2), size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Agreement Details',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),

                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                          ),

                          // Row 1: Agreement ID & Device IMEI
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Agreement ID',
                                      style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      agreementId,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Device IMEI',
                                      style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      imei,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // Row 2: Start Date & End Date
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Start Date',
                                      style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      startDate.isNotEmpty ? startDate : 'Oct 15, 2023',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'End Date',
                                      style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      endDate.isNotEmpty ? endDate : 'Oct 15, 2024',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
