import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../../account_management_module/models/payment_account_model.dart';
import '../../account_management_module/services/auth_service.dart';
import '../../account_management_module/services/xendit_service.dart';
import '../../product_purchase_module/models/cart_item_model.dart';
import '../../product_purchase_module/models/selected_payment_method.dart';
import '../../product_purchase_module/payment_success_page.dart';
import '../../product_purchase_module/select_payment_method_page.dart';
import '../../widgets/rebyte_app_bar.dart';
import '../../widgets/rebyte_bottom_nav_bar.dart';

class RentalOverdueLockedPage extends StatefulWidget {
  final Map<String, dynamic> rental;
  final String email;
  final String? name;
  final bool returnAfterPayment;

  const RentalOverdueLockedPage({
    super.key,
    required this.rental,
    required this.email,
    this.name,
    this.returnAfterPayment = false,
  });

  @override
  State<RentalOverdueLockedPage> createState() => _RentalOverdueLockedPageState();
}

class _RentalOverdueLockedPageState extends State<RentalOverdueLockedPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  SelectedPaymentMethod? _selectedPayment;
  bool _loadingPaymentMethod = true;
  bool _processingPayment = false;
  bool _loadingBalance = true;
  int? _serverMonthsDue;
  double? _serverAmountDue;
  String? _balanceError;
  String? _toastMessage;

  void _showToast(String message) {
    if (!mounted) return;
    setState(() => _toastMessage = message);
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _toastMessage == message) setState(() => _toastMessage = null);
    });
  }

  Widget _buildToastBanner() {
    final message = _toastMessage!;
    return Positioned(
      top: 12,
      left: 16,
      right: 16,
      child: Dismissible(
        key: ValueKey('overdue-payment-toast-$message'),
        direction: DismissDirection.horizontal,
        onDismissed: (_) => setState(() => _toastMessage = null),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFE11D48),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
            ),
            child: Row(children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13))),
              IconButton(
                onPressed: () => setState(() => _toastMessage = null),
                icon: const Icon(Icons.close, color: Colors.white, size: 18),
                visualDensity: VisualDensity.compact,
                tooltip: 'Dismiss',
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadDefaultPaymentMethod();
    _loadOverdueBalance();
  }

  Future<void> _loadOverdueBalance() async {
    final rentalID = widget.rental['rentalID']?.toString() ?? '';
    try {
      final response = await http.get(Uri.parse(
        '${AuthService.baseUrl}/api/rental/overdue-balance/${Uri.encodeComponent(rentalID)}',
      )).timeout(const Duration(seconds: 15));
      final decoded = jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300 ||
          decoded is! Map<String, dynamic> || decoded['success'] != true) {
        throw Exception(decoded is Map
            ? (decoded['error']?.toString() ?? 'Unable to load the latest rental payment.')
            : 'Invalid balance response');
      }
      if (!mounted) return;
      setState(() {
        _serverMonthsDue = (decoded['monthsDue'] as num).toInt();
        _serverAmountDue = (decoded['amountDue'] as num).toDouble();
        _balanceError = null;
        _loadingBalance = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _balanceError = error.toString().replaceFirst('Exception: ', '');
        _loadingBalance = false;
      });
    }
  }

  Future<void> _loadDefaultPaymentMethod() async {
    try {
      final cards = await XenditService.fetchSavedCards(widget.email);
      if (cards.isNotEmpty) {
        final accounts = cards.map((item) => PaymentAccountModel.fromJson(item)).toList();
        final selected = accounts.firstWhere((account) => account.isDefault, orElse: () => accounts.first);
        _selectedPayment = SelectedPaymentMethod(
          id: selected.id,
          type: 'card',
          title: selected.cardNumber,
          subtitle: 'Exp: ${selected.expiryDate}',
          iconType: 'card',
          rawData: selected.toJson(),
        );
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingPaymentMethod = false);
  }

  Future<void> _selectPaymentMethod() async {
    final selected = await Navigator.push<SelectedPaymentMethod>(context, MaterialPageRoute(
      builder: (_) => SelectPaymentMethodPage(email: widget.email, currentlySelected: _selectedPayment),
    ));
    if (selected != null && mounted) setState(() => _selectedPayment = selected);
  }

  Future<void> _payOverdueBalance({
    required String rentalID,
    required String productName,
    required String imageUrl,
    required String storage,
    required String color,
    required int months,
    required double totalDue,
  }) async {
    if (_processingPayment) return;
    if (_selectedPayment == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a payment method.')));
      return;
    }
    setState(() => _processingPayment = true);
    try {
      final paymentType = _selectedPayment!.type;
      final invoice = await XenditService.createInvoice(
        email: widget.email,
        amount: totalDue,
        description: 'Overdue rental balance for $rentalID: $productName ($months month${months == 1 ? '' : 's'} + lock fee${widget.returnAfterPayment ? ', pay and return' : ''})',
        paymentMethodType: paymentType,
        productIDs: [widget.rental['productID']?.toString() ?? rentalID],
      );
      if (invoice['success'] != true || invoice['invoiceUrl'] == null) {
        throw Exception(invoice['error']?.toString() ?? 'Unable to start Xendit payment.');
      }
      final invoiceID = invoice['invoiceId']?.toString() ?? '';
      final paymentResult = await XenditService.launchPaymentWebView(
        context: context,
        invoiceUrl: invoice['invoiceUrl'].toString(),
        title: 'Xendit Secure Pay',
        invoiceId: invoiceID,
        cardData: {'email': widget.email, ...?_selectedPayment!.rawData},
      );
      var status = paymentResult['status']?.toString() ?? 'cancelled';
      if (status == 'cancelled' && invoiceID.isNotEmpty) {
        try {
          final check = await XenditService.getInvoiceStatus(invoiceID);
          if (['PAID', 'SETTLED', 'COMPLETED'].contains(check['status']?.toString().toUpperCase())) status = 'success';
        } catch (_) {}
      }
      if (status != 'success') {
        if (mounted) {
          setState(() => _processingPayment = false);
          _showToast(status == 'failed'
              ? (paymentResult['errorMessage']?.toString() ?? 'Payment failed.')
              : 'Payment cancelled.');
        }
        return;
      }

      final response = await http.post(
        Uri.parse('${AuthService.baseUrl}/api/rental/pay-overdue-balance'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'rentalID': rentalID,
          'invoiceID': invoiceID,
          'monthsToPay': months,
          'amountPaid': totalDue,
          'paymentAccountID': _selectedPayment!.id,
          'returnAfterPayment': widget.returnAfterPayment,
        }),
      ).timeout(const Duration(seconds: 30));
      Map<String, dynamic> data;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) throw const FormatException('Response is not a JSON object');
        data = decoded;
      } catch (_) {
        final preview = response.body.trim().replaceAll(RegExp(r'\s+'), ' ');
        throw Exception(
          'Xendit may have completed the payment, but the rental server returned HTTP ${response.statusCode} instead of JSON. '
          'Do not pay again. Restart the Node backend and provide invoice $invoiceID to the administrator to sync the payment. '
          'Server response: ${preview.substring(0, preview.length > 120 ? 120 : preview.length)}',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300 || data['success'] != true) {
        throw Exception(data['message']?.toString() ?? data['error']?.toString() ?? 'Could not update the rental after payment.');
      }
      if (!mounted) return;
      final transactionID = data['transactionID']?.toString() ?? invoiceID;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PaymentSuccessPage(
        orderNumber: transactionID,
        amountPaid: totalDue,
        email: widget.email,
        name: widget.name,
        paymentTitle: _selectedPayment!.title,
        paidAt: DateTime.now(),
        isRental: true,
        items: [CartItemModel(
          productID: widget.rental['productID']?.toString() ?? rentalID,
          listingTitle: productName,
          description: 'Overdue rental payment ($months month${months == 1 ? '' : 's'} + lock fee)',
          sellingPrice: totalDue,
          imageUrl: imageUrl,
          storage: storage,
          color: color,
        )],
      )));
    } catch (error) {
      if (mounted) {
        setState(() => _processingPayment = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rental = widget.rental;
    final rentalID = rental['rentalID']?.toString() ?? 'RB-8924-VL';

    // Product info
    final product = (rental['product'] is Map)
        ? Map<String, dynamic>.from(rental['product'] as Map)
        : <String, dynamic>{};
    String productName = product['title']?.toString() ??
        rental['productName']?.toString() ??
        rental['title']?.toString() ??
        'iPhone 12';

    // Image URL
    String imageUrl = product['imageUrl']?.toString() ?? rental['imageUrl']?.toString() ?? '';
    if (imageUrl.isEmpty && product['images'] is List && (product['images'] as List).isNotEmpty) {
      imageUrl = product['images'][0].toString();
    }

    // Specs
    String specsText = '';
    final storage = product['storage'] ?? rental['storage'] ?? '';
    final color = product['color'] ?? rental['color'] ?? '';
    if (storage.toString().isNotEmpty && color.toString().isNotEmpty) {
      specsText = '${storage} • ${color}';
    } else if (storage.toString().isNotEmpty) {
      specsText = storage.toString();
    } else if (color.toString().isNotEmpty) {
      specsText = color.toString();
    } else {
      specsText = '256GB • Graphite';
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 1. Get startDate and monthly billing day
    DateTime startDate;
    try {
      final startStr = rental['startDate']?.toString();
      startDate = startStr != null && startStr.isNotEmpty
          ? DateTime.parse(startStr)
          : today.subtract(const Duration(days: 30));
    } catch (_) {
      startDate = today.subtract(const Duration(days: 30));
    }
    // Calculate overdue billing cycles from the saved rental coverage expiry.
    DateTime billingAnchorDate;
    try {
      final expiryValue = rental['rentalExpiryDate'];
      if (expiryValue != null && expiryValue.toString().isNotEmpty) {
        billingAnchorDate = DateTime.parse(expiryValue.toString()).toLocal();
      } else {
        billingAnchorDate = startDate;
      }
    } catch (_) {
      billingAnchorDate = startDate;
    }
    final DateTime paidD = DateTime(billingAnchorDate.year, billingAnchorDate.month, billingAnchorDate.day);

    DateTime expiryDate;
    try {
      expiryDate = DateTime.parse(rental['rentalExpiryDate']?.toString() ?? '');
    } catch (_) {
      expiryDate = paidD;
    }
    final DateTime expD = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);

    DateTime? endDate;
    try {
      final endValue = rental['endDate']?.toString();
      if (endValue != null && endValue.isNotEmpty) {
        final parsedEnd = DateTime.parse(endValue);
        endDate = DateTime(parsedEnd.year, parsedEnd.month, parsedEnd.day);
      }
    } catch (_) {}
    final bool contractEnded = endDate != null && endDate.isBefore(today);

    final int monthDifference = (today.year - paidD.year) * 12 + today.month - paidD.month;
    int unpaidMonths = monthDifference + 1;
    if (!today.isAfter(paidD)) unpaidMonths = 1;
    if (unpaidMonths < 1) unpaidMonths = 1;

    // Overdue calculation in days
    int overdueDays = today.difference(expD).inDays;
    if (overdueDays <= 0) {
      overdueDays = 14;
    }

    // Timeline dates
    final String startDateStr = DateFormat('MMM dd, yyyy').format(startDate);
    final String dueDateStr = DateFormat('MMM dd, yyyy').format(expD);
    final String currentDateStr = DateFormat('MMM dd, yyyy').format(today);

    // 4. Financial calculation (no late fee):
    // Standard Monthly Rate = unpaidMonths * monthlyRate
    // Total Due = (unpaidMonths * monthlyRate) + lock fee 50
    final rawFee = rental['monthlyRentalFee'] ?? rental['monthlyFee'];
    final feeNum = (rawFee is num) ? rawFee.toDouble() : double.tryParse(rawFee?.toString() ?? '');
    final double monthlyRate = feeNum ?? 149.00;
    const double adminLockFee = 50.00;
    final double unpaidMonthlyTotal = (unpaidMonths * monthlyRate * 100).round() / 100;
    final double totalDue = ((unpaidMonthlyTotal + adminLockFee) * 100).round() / 100;
    final displayMonths = _serverMonthsDue;
    final displayTotalDue = _serverAmountDue;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: ReByteAppBar(scaffoldKey: _scaffoldKey),
      drawer: ReByteDrawer(isLoggedIn: true, email: widget.email, name: widget.name, isRentalsSelected: true),
      bottomNavigationBar: const ReByteBottomNavBar(
        selectedIndex: 3, // Rentals tab active
      ),
      body: SafeArea(
        child: Stack(children: [
          SingleChildScrollView(
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Back Arrow Button
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B), size: 24),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.pop(context),
                ),
              ),

              // 1. Alert Banner: Device Locked: Overdue Rental
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE4E6),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.warning_rounded, color: Color(0xFFB91C1C), size: 22),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Device Locked: Overdue Rental',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF991B1B),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'This rental device has been administratively locked due to severe overdue status. Please resolve the outstanding balance or return the device immediately to restore access or avoid further penalties.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFFB91C1C),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 2. Device Info Card
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Orange top border accent
                      Container(
                        height: 3.5,
                        width: double.infinity,
                        color: const Color(0xFFFF5722),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Device Image container
                            Container(
                              width: double.infinity,
                              height: 140,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEEF2FF),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: imageUrl.isNotEmpty
                                    ? (imageUrl.startsWith('http')
                                        ? Image.network(
                                            imageUrl,
                                            fit: BoxFit.contain,
                                            height: 120,
                                            errorBuilder: (_, __, ___) => const Icon(
                                              Icons.phone_iphone,
                                              size: 64,
                                              color: Color(0xFF94A3B8),
                                            ),
                                          )
                                        : Image.asset(
                                            imageUrl,
                                            fit: BoxFit.contain,
                                            height: 120,
                                            errorBuilder: (_, __, ___) => const Icon(
                                              Icons.phone_iphone,
                                              size: 64,
                                              color: Color(0xFF94A3B8),
                                            ),
                                          ))
                                    : const Icon(
                                        Icons.phone_iphone,
                                        size: 64,
                                        color: Color(0xFF94A3B8),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Rental ID
                            Text(
                              'RENTAL ID: #${rentalID.replaceAll('#', '')}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF64748B),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 4),

                            // Product Name
                            Text(
                              productName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 2),

                            // Specs
                            Text(
                              specsText,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Tags row
                            Row(
                              children: [
                                // Overdue Tag
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFEDD5),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.access_time_rounded,
                                          size: 13, color: Color(0xFFEA580C)),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$overdueDays Days Overdue',
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFFEA580C),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // Remote Lock Active Tag
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDBEAFE),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.lock_outline, size: 13, color: Color(0xFF1E40AF)),
                                      SizedBox(width: 4),
                                      Text(
                                        'Remote Lock Active',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF1E40AF),
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
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 3. Rental Timeline Card
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.calendar_today_outlined, size: 18, color: Color(0xFF0F172A)),
                        SizedBox(width: 8),
                        Text(
                          'Rental Timeline',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _buildTimelineRow(
                      dotColor: const Color(0xFFCBD5E1),
                      label: 'Start Date',
                      labelColor: const Color(0xFF64748B),
                      dateStr: startDateStr,
                      dateColor: const Color(0xFF0F172A),
                      showBottomLine: true,
                    ),
                    _buildTimelineRow(
                      dotColor: const Color(0xFFF97316),
                      isRing: true,
                      label: 'Due Date',
                      labelColor: const Color(0xFFEA580C),
                      dateStr: dueDateStr,
                      dateColor: const Color(0xFF0F172A),
                      showBottomLine: true,
                    ),
                    _buildTimelineRow(
                      dotColor: const Color(0xFFDC2626),
                      label: 'Current Date',
                      labelColor: const Color(0xFFDC2626),
                      dateStr: currentDateStr,
                      dateColor: const Color(0xFFDC2626),
                      showBottomLine: false,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 4. Payment method selection
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.account_balance_wallet_outlined, size: 20, color: Color(0xFF0F172A)),
                      SizedBox(width: 8),
                      Text('Payment Method', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                    ]),
                    const SizedBox(height: 12),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _loadingPaymentMethod || _processingPayment ? null : _selectPaymentMethod,
                      child: Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(border: Border.all(color: const Color(0xFFCBD5E1)), borderRadius: BorderRadius.circular(12)),
                        child: Row(children: [
                          const Icon(Icons.payment, color: Color(0xFF0C5AD2)),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(_loadingPaymentMethod ? 'Loading payment methods…' : (_selectedPayment?.title ?? 'Select a payment method'), style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                            const SizedBox(height: 3),
                            Text(_loadingPaymentMethod ? ' ' : (_selectedPayment?.subtitle ?? 'Card, FPX, or e-wallet'), style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                          ])),
                          Text(_selectedPayment == null ? 'Select' : 'Change', style: const TextStyle(color: Color(0xFF0C5AD2), fontWeight: FontWeight.bold)),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right, color: Color(0xFF64748B)),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 5. Outstanding Balance Card
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.payments_outlined, size: 20, color: Color(0xFF0F172A)),
                        SizedBox(width: 8),
                        Text(
                          'Outstanding Balance',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildBalanceRow(
                      _loadingBalance
                          ? 'Checking latest payment…'
                          : _balanceError != null
                              ? 'Unable to calculate balance'
                              : 'Standard Monthly Rate ($displayMonths month${displayMonths == 1 ? "" : "s"})',
                      _loadingBalance || displayTotalDue == null
                          ? '—'
                          : 'RM${(displayTotalDue - adminLockFee).toStringAsFixed(2)}',
                      const Color(0xFF0F172A),
                    ),
                    const SizedBox(height: 12),
                    _buildBalanceRow(
                      'Administrative Lock Fee',
                      _loadingBalance || displayTotalDue == null
                          ? '—'
                          : 'RM${adminLockFee.toStringAsFixed(2)}',
                      const Color(0xFF0F172A),
                    ),
                    const SizedBox(height: 16),
                    const Divider(
                      color: Color(0xFF0F172A),
                      thickness: 1.5,
                      height: 1,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text(
                          'Total Due',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          _loadingBalance || displayTotalDue == null
                              ? '—'
                              : 'RM${displayTotalDue.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFB91C1C),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: (_processingPayment || _loadingPaymentMethod || _loadingBalance || _balanceError != null || _selectedPayment == null || (contractEnded && !widget.returnAfterPayment))
                            ? null
                            : () => _payOverdueBalance(
                                  rentalID: rentalID,
                                  productName: productName,
                                  imageUrl: imageUrl,
                                  storage: storage.toString(),
                                  color: color.toString(),
                                  months: displayMonths ?? unpaidMonths,
                                  totalDue: displayTotalDue ?? totalDue,
                                ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0C5AD2),
                          disabledBackgroundColor: const Color(0xFFCBD5E1),
                          disabledForegroundColor: const Color(0xFF94A3B8),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _processingPayment
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Text(
                          _loadingBalance
                              ? 'Checking balance…'
                              : _balanceError != null
                                  ? 'Unable to load balance'
                                  : 'Pay RM${displayTotalDue!.toStringAsFixed(2)} ${widget.returnAfterPayment ? "& Return" : "& Continue"}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
            ],
            ),
          ),
          if (_toastMessage != null) _buildToastBanner(),
        ]),
      ),
    );
  }

  Widget _buildTimelineRow({
    required Color dotColor,
    required String label,
    required Color labelColor,
    required String dateStr,
    required Color dateColor,
    bool isRing = false,
    bool showBottomLine = false,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isRing ? Colors.white : dotColor,
                    border: Border.all(
                      color: dotColor,
                      width: isRing ? 3 : 0,
                    ),
                  ),
                ),
                if (showBottomLine)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: const Color(0xFFE2E8F0),
                      margin: const EdgeInsets.symmetric(vertical: 2),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: EdgeInsets.only(bottom: showBottomLine ? 16 : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: labelColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateStr,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: dateColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceRow(
    String label,
    String amount,
    Color amountColor, {
    Color labelColor = const Color(0xFF475569),
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: labelColor,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          amount,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: amountColor,
          ),
        ),
      ],
    );
  }
}

