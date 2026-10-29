import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import '../../account_management_module/services/auth_service.dart';
import '../../account_management_module/services/xendit_service.dart';
import '../../account_management_module/models/payment_account_model.dart';
import '../../widgets/rebyte_app_bar.dart';
import '../../widgets/rebyte_bottom_nav_bar.dart';
import '../../product_purchase_module/select_payment_method_page.dart';
import '../../product_purchase_module/models/selected_payment_method.dart';
import '../../product_purchase_module/payment_success_page.dart';
import '../../product_purchase_module/models/cart_item_model.dart';

class RentalPaymentConfirmationPage extends StatefulWidget {
  final Map<String, dynamic> rental;
  final String email;
  final String? name;

  const RentalPaymentConfirmationPage({
    super.key,
    required this.rental,
    required this.email,
    this.name,
  });

  @override
  State<RentalPaymentConfirmationPage> createState() => _RentalPaymentConfirmationPageState();
}

class _RentalPaymentConfirmationPageState extends State<RentalPaymentConfirmationPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  SelectedPaymentMethod? _selectedPayment;
  bool _isLoadingPaymentMethod = true;
  bool _isProcessing = false;
  String? _toastMessage;
  bool _isToastError = false;

  int _selectedMonths = 1;
  int _maxPayableMonths = 1;
  bool _isFullyPaid = false;

  late final TextEditingController _monthsController;

  @override
  void initState() {
    super.initState();
    _calculatePayableMonths();
    _monthsController = TextEditingController(
      text: _isFullyPaid ? '0' : '$_selectedMonths',
    );
    _loadDefaultPaymentMethod();
  }

  @override
  void dispose() {
    _monthsController.dispose();
    super.dispose();
  }

  String _formatShortDate(dynamic dateVal) {
    if (dateVal == null) return 'N/A';
    try {
      final dt = DateTime.parse(dateVal.toString());
      return DateFormat('dd MMM yyyy').format(dt);
    } catch (_) {
      return dateVal.toString();
    }
  }

  void _calculatePayableMonths() {
    final rental = widget.rental;
    final endStr = rental['endDate']?.toString();
    final expiryStr = rental['rentalExpiryDate']?.toString();

    if (endStr != null && endStr.isNotEmpty && expiryStr != null && expiryStr.isNotEmpty) {
      try {
        final end = DateTime.parse(endStr);
        final expiry = DateTime.parse(expiryStr);
        final endDate = DateTime(end.year, end.month, end.day);
        final expiryDate = DateTime(expiry.year, expiry.month, expiry.day);

        if (expiryDate.isAtSameMomentAs(endDate) || expiryDate.isAfter(endDate)) {
          _isFullyPaid = true;
          _maxPayableMonths = 0;
          _selectedMonths = 0;
          return;
        }

        // Calculate months difference
        int months = (endDate.year - expiryDate.year) * 12 + (endDate.month - expiryDate.month);
        // If end day is earlier than expiry day, adjust
        if (endDate.day < expiryDate.day && months > 0) {
          // Check days remaining
          if (endDate.difference(expiryDate).inDays < 20) {
            months = 0;
          }
        }
        if (months <= 0) {
          // If endDate > expiryDate but within same month
          if (endDate.isAfter(expiryDate)) {
            months = 1;
          } else {
            _isFullyPaid = true;
            months = 0;
          }
        }
        _maxPayableMonths = months;
        _selectedMonths = _maxPayableMonths > 0 ? 1 : 0;
        _isFullyPaid = _maxPayableMonths <= 0;
        return;
      } catch (_) {}
    }

    _maxPayableMonths = 1;
    _selectedMonths = 1;
    _isFullyPaid = false;
  }

  Future<void> _loadDefaultPaymentMethod() async {
    setState(() => _isLoadingPaymentMethod = true);
    try {
      final cardsRaw = await XenditService.fetchSavedCards(widget.email);
      if (cardsRaw.isNotEmpty) {
        final cards = cardsRaw.map((m) => PaymentAccountModel.fromJson(m)).toList();
        final defaultCard = cards.firstWhere(
          (c) => c.isDefault,
          orElse: () => cards.first,
        );
        _selectedPayment = SelectedPaymentMethod(
          id: defaultCard.id,
          type: 'card',
          title: defaultCard.cardNumber,
          subtitle: 'Exp: ${defaultCard.expiryDate}',
          iconType: 'card',
          rawData: defaultCard.toJson(),
        );
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _isLoadingPaymentMethod = false);
    }
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

  Future<void> _handleChangePaymentMethod() async {
    final result = await Navigator.push<SelectedPaymentMethod>(
      context,
      MaterialPageRoute(
        builder: (context) => SelectPaymentMethodPage(
          email: widget.email,
          currentlySelected: _selectedPayment,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _selectedPayment = result;
      });
    }
  }

  Future<void> _handleConfirmAndPay() async {
    if (_isProcessing || _isFullyPaid || _selectedMonths <= 0) return;

    final rentalID = widget.rental['rentalID']?.toString() ?? '';
    if (rentalID.isEmpty) {
      _showToast('Invalid rental record ID.', isError: true);
      return;
    }

    final product = widget.rental['product'] as Map<String, dynamic>? ?? {};
    final device = widget.rental['device'] as Map<String, dynamic>? ?? {};
    final rawTitle = product['listingTitle']?.toString() ??
        '${device['brand'] ?? ''} ${device['model'] ?? ''}'.trim();
    final title = rawTitle.isNotEmpty ? rawTitle : 'Rental Device';
    final monthlyFee = (widget.rental['monthlyRentalFee'] is num)
        ? (widget.rental['monthlyRentalFee'] as num).toDouble()
        : 149.0;
    final totalPaidAmount = monthlyFee * _selectedMonths;

    setState(() => _isProcessing = true);

    try {
      // 1. Create Xendit Invoice for Rental Payment
      final paymentType = _selectedPayment?.type ?? 'card';
      final invoiceRes = await XenditService.createInvoice(
        email: widget.email,
        amount: totalPaidAmount,
        description: 'Rental Payment: $title ($_selectedMonths ${_selectedMonths == 1 ? 'mth' : 'mths'})',
        paymentMethodType: paymentType,
        productIDs: [widget.rental['productID']?.toString() ?? rentalID],
      );

      if (invoiceRes['success'] != true || invoiceRes['invoiceUrl'] == null) {
        if (mounted) {
          setState(() => _isProcessing = false);
          _showToast(invoiceRes['error']?.toString() ?? 'Failed to initialize Xendit payment', isError: true);
        }
        return;
      }

      final invoiceUrl = invoiceRes['invoiceUrl'].toString();
      final invoiceId = invoiceRes['invoiceId']?.toString();

      if (!mounted) return;

      // 2. Launch in-app secure payment webview with Xendit
      String paymentTypeLabel = 'Card';
      if (paymentType == 'fpx') {
        paymentTypeLabel = 'FPX';
      } else if (paymentType == 'ewallet') {
        paymentTypeLabel = 'E-Wallet';
      }

      final Map<String, dynamic> prefillData = {
        'email': widget.email,
      };
      if (_selectedPayment?.rawData != null) {
        prefillData.addAll(_selectedPayment!.rawData!);
      }

      final payResult = await XenditService.launchPaymentWebView(
        context: context,
        invoiceUrl: invoiceUrl,
        title: 'Xendit Secure Pay ($paymentTypeLabel)',
        invoiceId: invoiceId,
        cardData: prefillData,
      );

      String payStatus = payResult['status']?.toString() ?? 'cancelled';

      // Verify invoice status with Xendit if cancelled
      if (payStatus == 'cancelled' && invoiceId != null && invoiceId.isNotEmpty) {
        try {
          final check = await XenditService.getInvoiceStatus(invoiceId);
          final invStatus = check['status']?.toString().toUpperCase() ?? '';
          if (invStatus == 'PAID' || invStatus == 'SETTLED' || invStatus == 'COMPLETED') {
            payStatus = 'success';
          }
        } catch (_) {}
      }

      if (payStatus == 'cancelled') {
        if (mounted) {
          setState(() => _isProcessing = false);
          _showToast('Payment cancelled', isError: true);
        }
        return;
      }

      if (payStatus == 'failed') {
        if (mounted) {
          setState(() => _isProcessing = false);
          _showToast(payResult['errorMessage']?.toString() ?? 'Payment was declined by payment gateway.', isError: true);
        }
        return;
      }

      // 3. Payment Succeeded in Xendit -> Complete payment in backend
      // Creates transaction record with rentalID, updates rentalExpiryDate, and deducts Xendit recurring cycles
      final completeRes = await http.post(
        Uri.parse('${AuthService.baseUrl}/api/rental/complete-rental-payment'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'rentalID': rentalID,
          'invoiceID': invoiceId,
          'monthsToPay': _selectedMonths,
          'amountPaid': totalPaidAmount,
          'paymentAccountID': _selectedPayment?.id ?? '',
        }),
      ).timeout(const Duration(seconds: 20));

      final data = jsonDecode(completeRes.body);

      if (mounted) {
        setState(() => _isProcessing = false);
      }

      if (data['success'] == true) {
        if (!mounted) return;

        final String transactionID = data['transactionID']?.toString() ??
            invoiceId ??
            'TXN-${DateTime.now().millisecondsSinceEpoch}';

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => PaymentSuccessPage(
              orderNumber: transactionID,
              amountPaid: totalPaidAmount,
              email: widget.email,
              name: widget.name,
              paymentTitle: _selectedPayment?.title ?? 'Card',
              paidAt: DateTime.now(),
              isRental: true,
              items: [
                CartItemModel(
                  productID: widget.rental['productID']?.toString() ?? rentalID,
                  listingTitle: title,
                  description: 'Rental device renewal ($_selectedMonths ${_selectedMonths == 1 ? 'mth' : 'mths'})',
                  sellingPrice: totalPaidAmount,
                  imageUrl: product['imageUrl']?.toString() ?? '',
                  storage: device['storage']?.toString() ?? '',
                  color: device['color']?.toString() ?? '',
                ),
              ],
            ),
          ),
        );
      } else {
        final errorMsg = data['message'] ?? data['error'] ?? 'Failed to update rental record after payment.';
        _showToast(errorMsg, isError: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
      _showToast('Network error processing payment: $e', isError: true);
    }
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

    // Image URL
    String imageUrl = product['imageUrl']?.toString() ?? '';
    if (imageUrl.isEmpty && product['images'] is List && (product['images'] as List).isNotEmpty) {
      imageUrl = product['images'][0].toString();
    }

    // Serial / IMEI / RentalID
    final serial = device['serialNumber']?.toString() ??
        device['imei']?.toString() ??
        rental['rentalID']?.toString() ??
        'C02XG3QKJHG';

    // Fee
    final monthlyFee = (rental['monthlyRentalFee'] is num)
        ? (rental['monthlyRentalFee'] as num).toDouble()
        : 149.0;
    final singleFeeFormatted = 'RM${NumberFormat('#,##0.00').format(monthlyFee)}';
    final totalFee = monthlyFee * _selectedMonths;
    final totalFeeFormatted = 'RM${NumberFormat('#,##0.00').format(totalFee)}';

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
                // Top Navigation Row (Back Button)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B), size: 22),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),

                // Main Title Centered
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                    child: Text(
                      'Rental Payment Confirmation',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Card 1: Product Summary Card
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

                        // Card: Duration to Pay (Month Quantity Selector)
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
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(
                                        Icons.calendar_month_outlined,
                                        size: 20,
                                        color: Color(0xFF0C5AD2),
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Payment Duration',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_isFullyPaid)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'Fully Paid',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                    )
                                  else
                                    Text(
                                      'Max: $_maxPayableMonths ${_maxPayableMonths == 1 ? 'Month' : 'Months'}',
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                ],
                              ),

                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                              ),

                              if (_isFullyPaid)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 6.0),
                                  child: Text(
                                    'This rental agreement is fully paid through the end of its rental period. No further monthly payments required.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF64748B),
                                      height: 1.4,
                                    ),
                                  ),
                                )
                              else
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Concise explanation label
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: const Color(0xFFE2E8F0)),
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Icon(
                                            Icons.info_outline,
                                            size: 16,
                                            color: Color(0xFF0C5AD2),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Paid until ${_formatShortDate(rental['rentalExpiryDate'])} • Ends ${_formatShortDate(rental['endDate'])} (max $_maxPayableMonths ${_maxPayableMonths == 1 ? 'mth' : 'mths'})',
                                              style: const TextStyle(
                                                fontSize: 12.5,
                                                color: Color(0xFF334155),
                                                fontWeight: FontWeight.w500,
                                                height: 1.35,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    const SizedBox(height: 16),

                                    const Text(
                                      'Enter number of months to pay:',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1E293B),
                                      ),
                                    ),

                                    const SizedBox(height: 10),

                                    // Typed Input with Stepper Buttons
                                    Row(
                                      children: [
                                        // Minus Button
                                        InkWell(
                                          onTap: _selectedMonths > 1
                                              ? () {
                                                  setState(() {
                                                    _selectedMonths--;
                                                    _monthsController.text = '$_selectedMonths';
                                                  });
                                                }
                                              : null,
                                          borderRadius: BorderRadius.circular(10),
                                          child: Container(
                                            width: 44,
                                            height: 48,
                                            decoration: BoxDecoration(
                                              color: _selectedMonths > 1
                                                  ? const Color(0xFFF1F5F9)
                                                  : const Color(0xFFF8FAFC),
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(
                                                color: _selectedMonths > 1
                                                    ? const Color(0xFFCBD5E1)
                                                    : const Color(0xFFE2E8F0),
                                              ),
                                            ),
                                            child: Icon(
                                              Icons.remove,
                                              size: 20,
                                              color: _selectedMonths > 1
                                                  ? const Color(0xFF1E293B)
                                                  : const Color(0xFF94A3B8),
                                            ),
                                          ),
                                        ),

                                        const SizedBox(width: 10),

                                        // Digits-only TextField
                                        Expanded(
                                          child: TextFormField(
                                            controller: _monthsController,
                                            keyboardType: TextInputType.number,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF0F172A),
                                            ),
                                            inputFormatters: [
                                              FilteringTextInputFormatter.digitsOnly,
                                              LengthLimitingTextInputFormatter(3),
                                            ],
                                            decoration: InputDecoration(
                                              contentPadding: const EdgeInsets.symmetric(
                                                horizontal: 14,
                                                vertical: 12,
                                              ),
                                              suffixText: _selectedMonths == 1 ? 'Month' : 'Months',
                                              suffixStyle: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF64748B),
                                              ),
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(10),
                                                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                              ),
                                              enabledBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(10),
                                                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(10),
                                                borderSide: const BorderSide(
                                                  color: Color(0xFF0C5AD2),
                                                  width: 1.5,
                                                ),
                                              ),
                                              filled: true,
                                              fillColor: Colors.white,
                                            ),
                                            onChanged: (val) {
                                              if (val.isEmpty) return;
                                              int? parsed = int.tryParse(val);
                                              if (parsed == null) return;

                                              if (parsed > _maxPayableMonths) {
                                                parsed = _maxPayableMonths;
                                                _monthsController.text = '$parsed';
                                                _monthsController.selection = TextSelection.fromPosition(
                                                  TextPosition(offset: _monthsController.text.length),
                                                );
                                              } else if (parsed < 1 && _maxPayableMonths >= 1) {
                                                parsed = 1;
                                                _monthsController.text = '$parsed';
                                                _monthsController.selection = TextSelection.fromPosition(
                                                  TextPosition(offset: _monthsController.text.length),
                                                );
                                              }

                                              setState(() {
                                                _selectedMonths = parsed!;
                                              });
                                            },
                                          ),
                                        ),

                                        const SizedBox(width: 10),

                                        // Plus Button
                                        InkWell(
                                          onTap: _selectedMonths < _maxPayableMonths
                                              ? () {
                                                  setState(() {
                                                    _selectedMonths++;
                                                    _monthsController.text = '$_selectedMonths';
                                                  });
                                                }
                                              : null,
                                          borderRadius: BorderRadius.circular(10),
                                          child: Container(
                                            width: 44,
                                            height: 48,
                                            decoration: BoxDecoration(
                                              color: _selectedMonths < _maxPayableMonths
                                                  ? const Color(0xFFF1F5F9)
                                                  : const Color(0xFFF8FAFC),
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(
                                                color: _selectedMonths < _maxPayableMonths
                                                    ? const Color(0xFFCBD5E1)
                                                    : const Color(0xFFE2E8F0),
                                              ),
                                            ),
                                            child: Icon(
                                              Icons.add,
                                              size: 20,
                                              color: _selectedMonths < _maxPayableMonths
                                                  ? const Color(0xFF1E293B)
                                                  : const Color(0xFF94A3B8),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 8),

                                    // Helper text showing range
                                    Text(
                                      'Enter between 1 and $_maxPayableMonths ${_maxPayableMonths == 1 ? 'month' : 'months'}',
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: Color(0xFF94A3B8),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Card 2: Payment Method Card
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
                              // Header Row
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(
                                        Icons.credit_card,
                                        size: 20,
                                        color: Color(0xFF0C5AD2),
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Payment Method',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                    ],
                                  ),
                                  InkWell(
                                    onTap: _handleChangePaymentMethod,
                                    borderRadius: BorderRadius.circular(6),
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      child: Text(
                                        'Change',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF0C5AD2),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                              ),

                              // Payment detail
                              if (_isLoadingPaymentMethod)
                                const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(12.0),
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  ),
                                )
                              else
                                Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFFE2E8F0)),
                                      ),
                                      alignment: Alignment.center,
                                      child: const Icon(
                                        Icons.payment,
                                        color: Color(0xFF0C5AD2),
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _selectedPayment?.title ?? '**** **** **** 4242',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF0F172A),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _selectedPayment?.subtitle ?? 'Exp: 12/25',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Card 3: Fee Breakdown Card (Transaction Summary)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
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
                                    Icons.receipt_long_outlined,
                                    size: 20,
                                    color: Color(0xFF0C5AD2),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Transaction Summary',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ],
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                              ),

                              // Monthly rental fee
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Monthly rental fee',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                  Text(
                                    singleFeeFormatted,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 10),

                              // Month quantity
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Month quantity',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                  Text(
                                    '$_selectedMonths ${_selectedMonths == 1 ? 'mth' : 'mths'}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ],
                              ),

                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 14),
                                child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                              ),

                              // TOTAL
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'TOTAL',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  Text(
                                    totalFeeFormatted,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF0C5AD2),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Confirm & Pay Button
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: (_isProcessing || _isFullyPaid || _selectedMonths <= 0)
                                ? null
                                : _handleConfirmAndPay,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0C5AD2),
                              disabledBackgroundColor: const Color(0xFFCBD5E1),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: _isProcessing
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.lock_outline,
                                        size: 18,
                                        color: (_isFullyPaid || _selectedMonths <= 0)
                                            ? const Color(0xFF94A3B8)
                                            : Colors.white,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _isFullyPaid
                                            ? 'Rental Fully Paid'
                                            : 'Confirm & Pay $totalFeeFormatted',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: (_isFullyPaid || _selectedMonths <= 0)
                                              ? const Color(0xFF94A3B8)
                                              : Colors.white,
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

            // Top Floating Toast Banner (Identical to Purchase Checkout)
            if (_toastMessage != null)
              Positioned(
                top: 12,
                left: 16,
                right: 16,
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
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
