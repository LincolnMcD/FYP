import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'services/rental_service.dart';
import '../../widgets/rebyte_app_bar.dart';
import '../../widgets/rebyte_bottom_nav_bar.dart';

class RentalReturnPage extends StatefulWidget {
  final Map<String, dynamic> rental;
  final String email;
  final String name;

  const RentalReturnPage({
    super.key,
    required this.rental,
    required this.email,
    required this.name,
  });

  @override
  State<RentalReturnPage> createState() => _RentalReturnPageState();
}

class _RentalReturnPageState extends State<RentalReturnPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isSubmitting = false;
  String? _toastMessage;
  bool _isToastError = false;

  DateTime? _currentEndDate;
  DateTime? _rentalExpiryDate;

  @override
  void initState() {
    super.initState();
    _initDates();
  }

  void _initDates() {
    final endStr = widget.rental['endDate']?.toString();
    if (endStr != null && endStr.isNotEmpty) {
      _currentEndDate = DateTime.tryParse(endStr);
    }
    _currentEndDate ??= DateTime.now().add(const Duration(days: 30));

    final expStr = widget.rental['rentalExpiryDate']?.toString();
    if (expStr != null && expStr.isNotEmpty) {
      _rentalExpiryDate = DateTime.tryParse(expStr);
    }
    _rentalExpiryDate ??= _currentEndDate;
  }

  void _showToast(String message, {bool isError = false}) {
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

  Future<void> _handleConfirmReturn() async {
    final rentalID = widget.rental['rentalID']?.toString() ?? '';
    final endFormatted = DateFormat('dd MMM yyyy').format(_currentEndDate!);
    final expiryFormatted = DateFormat('dd MMM yyyy').format(_rentalExpiryDate!);

    // Show Confirmation Dialog (styled similar to renew confirmation popup)
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        title: const Row(
          children: [
            Icon(Icons.assignment_return_outlined, color: Color(0xFF0C5AD2), size: 24),
            SizedBox(width: 10),
            Text(
              'Confirm Return',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Color(0xFF0F172A),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to return this rented device now? The remaining unpaid rental duration will be terminated.',
              style: TextStyle(
                fontSize: 13.5,
                color: Colors.grey.shade700,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  _dialogRow('Rental End Date:', endFormatted),
                  const Divider(height: 16, color: Color(0xFFE2E8F0)),
                  _dialogRow('Rental Paid Until:', expiryFormatted),
                  const Divider(height: 16, color: Color(0xFFE2E8F0)),
                  _dialogRow('Return Status:', 'Returning', isHighlight: true),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0C5AD2),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text(
              'Confirm Return',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSubmitting = true);

    final res = await RentalService.returnRental(rentalID: rentalID);

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (res['success'] == true) {
      _showToast(
        'Return request initiated successfully. Your remaining unpaid rental duration is terminated.',
        isError: false,
      );

      // Return true after short delay so parent can refresh list
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) {
          Navigator.pop(context, true);
        }
      });
    } else {
      _showToast(res['error']?.toString() ?? 'Failed to initiate return.', isError: true);
    }
  }

  Widget _dialogRow(String label, String value, {bool isHighlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: isHighlight ? const Color(0xFF0C5AD2) : const Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Device & Product Data
    final product = widget.rental['product'] as Map<String, dynamic>? ?? {};
    final device = widget.rental['device'] as Map<String, dynamic>? ?? {};

    final brand = (device['brand'] ?? product['brand'] ?? '').toString();
    final model = (device['model'] ?? product['model'] ?? 'Rented Phone').toString();
    final title = brand.isNotEmpty ? '$brand $model' : model;
    final serial = (device['serialNumber'] ??
            product['serialNumber'] ??
            widget.rental['productID'] ??
            'N/A')
        .toString();
    final imageUrl = (product['imageUrl'] ?? product['productImage'] ?? '').toString();

    final endFormatted = DateFormat('dd MMM yyyy').format(_currentEndDate!);
    final expiryFormatted = DateFormat('dd MMM yyyy').format(_rentalExpiryDate!);
    final rawFee = widget.rental['monthlyRentalFee'];
    final feeNum = (rawFee is num) ? rawFee.toDouble() : double.tryParse(rawFee?.toString() ?? '');
    final monthlyFee = feeNum != null
        ? 'RM ${feeNum.toStringAsFixed(2)}/mth'
        : (rawFee != null ? 'RM $rawFee/mth' : '-');

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
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Navigation Row
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B), size: 22),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),

                // Main Title (Left aligned)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                  child: Text(
                    'Return Rental Device',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),

                const SizedBox(height: 6),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Section 1: Brief of Rented Device (Similar to Renew & Pay Rental)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                            border: Border.all(color: const Color(0xFFF1F5F9)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Image
                              Container(
                                width: 70,
                                height: 70,
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: imageUrl.isNotEmpty
                                    ? Image.network(
                                        imageUrl,
                                        fit: BoxFit.contain,
                                        errorBuilder: (context, error, stackTrace) => const Icon(
                                          Icons.phone_android,
                                          color: Color(0xFF64748B),
                                          size: 36,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.phone_android,
                                        color: Color(0xFF64748B),
                                        size: 36,
                                      ),
                              ),
                              const SizedBox(width: 14),

                              // Info
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Serial:\n$serial',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF64748B),
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Active Rental Pill
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDBEAFE),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.check_circle_outline,
                                      size: 13,
                                      color: Color(0xFF2563EB),
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'Active Rental',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF2563EB),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Section 2: Rental Agreement & Return Details
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                            border: Border.all(color: const Color(0xFFF1F5F9)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    size: 20,
                                    color: Color(0xFF003F9E),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Rental Schedule & Return Status',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 16),

                              // Timeline Info Box showing End Date and Rental Paid Until
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Column(
                                  children: [
                                    _infoRow('Rental End Date', endFormatted),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 8),
                                      child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                                    ),
                                    _infoRow('Rental Paid Until', expiryFormatted),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 8),
                                      child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                                    ),
                                    _infoRow('Monthly Rental Fee', monthlyFee),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 18),

                              // Warning Notice Box stating remaining unpaid rental duration termination
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFBFDBFE)),
                                ),
                                child: const Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.warning_amber_rounded,
                                      color: Color(0xFF0C5AD2),
                                      size: 22,
                                    ),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'If you return the device now, the remaining unpaid rental duration will be terminated and automatic recurring charges will be stopped immediately.',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF1E40AF),
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Action Button: Return Device
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isSubmitting ? null : _handleConfirmReturn,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0C5AD2),
                              disabledBackgroundColor: const Color(0xFFE2E8F0),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                            child: _isSubmitting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.keyboard_return, color: Colors.white, size: 20),
                                      SizedBox(width: 8),
                                      Text(
                                        'Return Rental Device',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),

                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Top Floating Toast Banner (Dismissible / Slideable to remove)
            if (_toastMessage != null)
              Positioned(
                top: 12,
                left: 16,
                right: 16,
                child: Dismissible(
                  key: ValueKey(_toastMessage),
                  direction: DismissDirection.horizontal,
                  onDismissed: (_) {
                    setState(() => _toastMessage = null);
                  },
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: _isToastError ? const Color(0xFFE11D48) : Colors.green.shade600,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4)),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isToastError ? Icons.error_outline : Icons.check_circle_outline,
                            color: Colors.white,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _toastMessage!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => setState(() => _toastMessage = null),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white70,
                              size: 18,
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
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }
}

