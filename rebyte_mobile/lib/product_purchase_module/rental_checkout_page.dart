import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'models/product_model.dart';
import 'models/cart_item_model.dart';
import 'models/selected_payment_method.dart';
import 'services/shop_service.dart';
import '../rental_managment_module/services/rental_service.dart';
import '../account_management_module/models/address_model.dart';
import '../account_management_module/models/payment_account_model.dart';
import '../account_management_module/services/address_service.dart';
import '../account_management_module/services/xendit_service.dart';
import 'select_address_page.dart';
import 'select_payment_method_page.dart';
import 'payment_success_page.dart';
import 'payment_failure_page.dart';
import 'rental_terms_and_conditions_page.dart';

class RentalCheckoutPage extends StatefulWidget {
  final ProductModel product;
  final String email;
  final String? name;
  final int durationMonths;
  final double monthlyRentalFee;
  final double depositAmount;
  final VoidCallback? onRentalCompleted;

  const RentalCheckoutPage({
    super.key,
    required this.product,
    required this.email,
    this.name,
    required this.durationMonths,
    required this.monthlyRentalFee,
    required this.depositAmount,
    this.onRentalCompleted,
  });

  @override
  State<RentalCheckoutPage> createState() => _RentalCheckoutPageState();
}

class _RentalCheckoutPageState extends State<RentalCheckoutPage> {
  AddressModel? _selectedAddress;
  SelectedPaymentMethod? _selectedPayment;
  bool _isLoading = true;
  bool _isProcessingPayment = false;
  bool _agreedToTerms = false;
  String? _toastMessage;
  bool _isToastError = false;

  late final DateTime _startDate;
  late final DateTime _endDate;

  @override
  void initState() {
    super.initState();
    _startDate = DateTime.now();
    _endDate = DateTime(
      _startDate.year,
      _startDate.month + widget.durationMonths,
      _startDate.day,
    );
    _loadInitialDefaults();
  }

  Future<void> _loadInitialDefaults() async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch addresses and select default
      final addresses = await AddressService.getAddresses(widget.email);
      if (addresses.isNotEmpty) {
        _selectedAddress = addresses.firstWhere(
          (a) => a.isDefault,
          orElse: () => addresses.first,
        );
      }

      // 2. Fetch saved cards and select default
      final cardsRaw = await XenditService.fetchSavedCards(widget.email);
      if (cardsRaw.isNotEmpty) {
        final cards = cardsRaw
            .map((m) => PaymentAccountModel.fromJson(m))
            .toList();
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
      } else {
        _selectedPayment = null;
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  /// Total payable today = 1st month rental fee + refundable security deposit
  double get _totalDueToday => widget.monthlyRentalFee + widget.depositAmount;

  void _showTopToast(String message, {bool isError = false}) {
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

  Future<void> _changeAddress() async {
    final result = await Navigator.push<AddressModel>(
      context,
      MaterialPageRoute(
        builder: (context) => SelectAddressPage(
          email: widget.email,
          currentlySelected: _selectedAddress,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _selectedAddress = result;
      });
    }
  }

  Future<void> _changePaymentMethod() async {
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

  Future<void> _handleConfirmRentalAndPay() async {
    if (_selectedAddress == null) {
      _showTopToast('Please select a delivery address', isError: true);
      return;
    }

    if (_selectedPayment == null) {
      _showTopToast('Please select a payment method', isError: true);
      return;
    }

    if (!_agreedToTerms) {
      _showTopToast(
        'Please agree to the ReByte Rental Terms & Conditions',
        isError: true,
      );
      return;
    }

    setState(() => _isProcessingPayment = true);

    final totalAmount = _totalDueToday;

    // 1. Create Xendit Invoice for rental checkout (same as purchase payment)
    // Allows user to choose any payment method: FPX, E-Wallet, Card, etc.
    final invoiceRes = await XenditService.createInvoice(
      email: widget.email,
      amount: totalAmount,
      description:
          'ReByte Rental: ${widget.product.displayTitle} (${widget.durationMonths} Mths)',
      paymentMethodType: _selectedPayment!.type,
      productIDs: [widget.product.productID],
    );

    if (invoiceRes['success'] != true || invoiceRes['invoiceUrl'] == null) {
      if (mounted) {
        setState(() => _isProcessingPayment = false);
        _showTopToast(
          invoiceRes['error']?.toString() ??
              'Failed to initialize payment gateway',
          isError: true,
        );
      }
      return;
    }

    final String invoiceUrl = invoiceRes['invoiceUrl'].toString();
    final String? invoiceId = invoiceRes['invoiceId']?.toString();

    if (!mounted) return;

    // 2. Launch in-app secure payment webview with Xendit
    String paymentTypeLabel = 'Card';
    if (_selectedPayment!.type == 'fpx') {
      paymentTypeLabel = 'FPX';
    } else if (_selectedPayment!.type == 'ewallet') {
      paymentTypeLabel = 'E-Wallet';
    }

    final Map<String, dynamic> prefillData = {'email': widget.email};
    if (_selectedAddress != null && _selectedAddress!.phoneNumber.isNotEmpty) {
      prefillData['phone'] = _selectedAddress!.phoneNumber;
    }
    if (_selectedPayment!.type == 'card' && _selectedPayment!.rawData != null) {
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
        if (invStatus == 'PAID' ||
            invStatus == 'SETTLED' ||
            invStatus == 'COMPLETED') {
          payStatus = 'success';
        }
      } catch (_) {}
    }

    // User cancelled
    if (payStatus == 'cancelled') {
      if (invoiceId != null && invoiceId.isNotEmpty) {
        // Expire the pending invoice in Xendit immediately
        XenditService.refundInvoice(
          invoiceId: invoiceId,
          reason: 'CANCELLATION',
          amount: totalAmount,
        );
      }
      if (mounted) {
        setState(() => _isProcessingPayment = false);
        _showTopToast('Payment cancelled', isError: true);
      }
      return;
    }

    // Payment failed
    if (payStatus == 'failed') {
      final failMsg =
          payResult['errorMessage']?.toString() ??
          'Payment was declined by your bank or card issuer.';

      // Create a failed transaction record
      ShopService.createTransaction(
        transactionType: 'Deposit',
        transactionStatus: 'Fail',
        transactionAmount: totalAmount,
        gatewayTransactionID: invoiceId,
        paymentAccountID: _selectedPayment?.id,
      );

      if (mounted) {
        setState(() => _isProcessingPayment = false);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PaymentFailurePage(
              orderTotal: totalAmount,
              errorCode: failMsg.contains('insufficient')
                  ? 'INSUFFICIENT FUNDS'
                  : 'PAYMENT DECLINED',
              errorMessage: failMsg,
              email: widget.email,
              name: widget.name,
              isReturnToRentals: true,
            ),
          ),
        );
      }
      return;
    }

    // 3. Payment succeeded -> NOW create rental record and update product status!
    final rentalRes = await RentalService.createRentalRecord(
      productID: widget.product.productID,
      email: widget.email,
      durationMonths: widget.durationMonths,
      monthlyRentalFee: widget.monthlyRentalFee,
      depositAmount: widget.depositAmount,
      addressID: _selectedAddress?.id ?? _selectedAddress?.addressID,
      paymentAccountID: _selectedPayment?.id,
    );

    if (mounted) {
      setState(() => _isProcessingPayment = false);

      if (rentalRes['success'] == true) {
        final rental = rentalRes['rental'] as Map<String, dynamic>?;
        final finalRentalID =
            rental?['rentalID']?.toString() ??
            '${DateFormat('yyMM').format(DateTime.now())}REN00001';

        // If recurring plan requires customer authorization, prompt to authorize via Xendit WebView
        final authUrl = rentalRes['recurringAuthUrl']?.toString();
        final planId = rental?['recurringPlanID']?.toString();
        final authSessionID = rentalRes['recurringAuthSessionID']?.toString();
        bool isRecurringAuthSuccess = true;

        if (authUrl != null && authUrl.isNotEmpty) {
          final authResult = await XenditService.launchPaymentWebView(
            context: context,
            invoiceUrl: authUrl,
            title: 'Authorize Recurring Rental Payment',
            invoiceId: planId,
            cardData: {
              'email': widget.email,
              if (_selectedAddress != null &&
                  _selectedAddress!.phoneNumber.isNotEmpty)
                'phone': _selectedAddress!.phoneNumber,
            },
          );

          final authStatus =
              authResult['status']?.toString().toLowerCase() ?? 'cancelled';

          // Verify the provider-side e-wallet SAVE session and create the recurring plan
          // only after Xendit returns a Touch 'n Go token. This also handles closing the
          // WebView immediately after approving the wallet.
          if (authSessionID != null && authSessionID.isNotEmpty) {
            isRecurringAuthSuccess = false;
            for (var attempt = 0; attempt < 3; attempt++) {
              final completion =
                  await RentalService.completeRecurringAuthorization(
                    rentalID: finalRentalID,
                    sessionID: authSessionID,
                  );
              isRecurringAuthSuccess = completion['success'] == true;
              if (isRecurringAuthSuccess) break;

              // Xendit may need a short moment to publish the linked payment token.
              if (attempt < 2) {
                await Future<void>.delayed(
                  Duration(milliseconds: 500 * (attempt + 1)),
                );
              }
            }
          } else if (planId != null && planId.isNotEmpty) {
            // Backward compatibility for rentals created with the previous plan-link flow.
            isRecurringAuthSuccess = false;
            for (var attempt = 0; attempt < 3; attempt++) {
              isRecurringAuthSuccess = await RentalService.syncRentalPlanStatus(
                finalRentalID,
              );
              if (isRecurringAuthSuccess) break;
              if (attempt < 2) {
                await Future<void>.delayed(
                  Duration(milliseconds: 500 * (attempt + 1)),
                );
              }
            }
          } else {
            isRecurringAuthSuccess = authStatus == 'success';
          }
        }

        // If customer cancelled or failed recurring authorization:
        // Do NOT proceed to PaymentSuccessPage! Cancel transaction & authorization in Xendit, and show 'Payment cancelled' toast.
        if (!isRecurringAuthSuccess) {
          if (invoiceId != null && invoiceId.isNotEmpty) {
            final refundRes = await XenditService.refundInvoice(
              invoiceId: invoiceId,
              reason: 'CANCELLATION',
              amount: totalAmount,
            );

            ShopService.createTransaction(
              transactionType: 'Refund',
              transactionStatus: 'Success',
              transactionAmount: totalAmount,
              gatewayTransactionID:
                  refundRes['data']?['id']?.toString() ?? invoiceId,
              paymentAccountID: _selectedPayment?.id,
              rentalID: finalRentalID,
            );
          }

          // Cancel incomplete rental and deactivate recurring plan in Xendit
          await RentalService.cancelRental(finalRentalID);

          if (mounted) {
            _showTopToast('Payment cancelled', isError: true);
          }
          return;
        }

        // ONLY GO TO payment success page when payment successful AND authorization success!
        // Create Transaction record linked with rentalID (Success with 'Deposit' type)
        ShopService.createTransaction(
          transactionType: 'Deposit',
          transactionStatus: 'Success',
          transactionAmount: totalAmount,
          gatewayTransactionID: invoiceId,
          paymentAccountID: _selectedPayment?.id,
          rentalID: finalRentalID,
        );

        // Invalidate product caches so shop updates
        ShopService.invalidateUserCache(widget.email);
        widget.onRentalCompleted?.call();

        // Convert ProductModel to CartItemModel for PaymentSuccessPage
        final rentalCartItem = CartItemModel(
          productID: widget.product.productID,
          listingTitle: widget.product.displayTitle,
          description: widget.product.description,
          sellingPrice: totalAmount,
          imageUrl: widget.product.imageUrl,
          brand: widget.product.brand,
          model: widget.product.model,
          storage: widget.product.storage,
          ram: widget.product.ram,
          color: widget.product.color,
          condition: widget.product.condition,
          deviceID: widget.product.deviceID,
        );

        // Navigate to PaymentSuccessPage with rentalID
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => PaymentSuccessPage(
                orderNumber: finalRentalID,
                amountPaid: totalAmount,
                email: widget.email,
                name: widget.name,
                paymentTitle: _selectedPayment?.title ?? 'Card',
                paidAt: DateTime.now(),
                items: [rentalCartItem],
                deliveryAddress: _selectedAddress,
                isRental: true,
              ),
            ),
          );
        }
      } else {
        // Failed to write rental record despite payment success: trigger refund
        if (invoiceId != null && invoiceId.isNotEmpty) {
          final refundRes = await XenditService.refundInvoice(
            invoiceId: invoiceId,
            reason: 'CANCELLATION',
            amount: totalAmount,
          );

          ShopService.createTransaction(
            transactionType: 'Refund',
            transactionStatus: 'Success',
            transactionAmount: totalAmount,
            gatewayTransactionID:
                refundRes['data']?['id']?.toString() ?? invoiceId,
            paymentAccountID: _selectedPayment?.id,
          );
        }

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PaymentFailurePage(
                orderTotal: totalAmount,
                errorCode: 'RENTAL ERROR',
                errorMessage:
                    rentalRes['error']?.toString() ??
                    'Equipment became unavailable. Automatic refund initiated.',
                email: widget.email,
                name: widget.name,
                isReturnToRentals: true,
              ),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM dd, yyyy');
    final startDateStr = dateFormat.format(_startDate);
    final endDateStr = dateFormat.format(_endDate);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Checkout',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF0C5AD2)),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18.0,
                      vertical: 12.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1. PRODUCT SUMMARY CARD
                        _buildProductSummaryCard(),
                        const SizedBox(height: 16),

                        // 2. DELIVERY ADDRESS CARD
                        _buildDeliveryAddressCard(),
                        const SizedBox(height: 16),

                        // 3. PAYMENT METHOD CARD
                        _buildPaymentMethodCard(),
                        const SizedBox(height: 16),

                        // 4. RENTAL PERIOD CARD
                        _buildRentalPeriodCard(startDateStr, endDateStr),
                        const SizedBox(height: 16),

                        // 5. PAYMENT SUMMARY CARD
                        _buildPaymentSummaryCard(),
                        const SizedBox(height: 20),

                        // 6. TERMS & CONDITIONS CHECKBOX
                        _buildTermsAndConditionsCheckbox(),
                        const SizedBox(height: 20),

                        // 7. CONFIRM RENTAL & PAY BUTTON
                        _buildConfirmRentalButton(),
                        const SizedBox(height: 36),
                      ],
                    ),
                  ),

            // Top Floating Toast Banner
            if (_toastMessage != null)
              Positioned(
                top: 12,
                left: 16,
                right: 16,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: _isToastError
                          ? const Color(0xFFE11D48)
                          : Colors.green.shade600,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isToastError
                              ? Icons.error_outline
                              : Icons.check_circle_outline,
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

  Widget _buildProductSummaryCard() {
    final specs = [
      if (widget.product.storage.isNotEmpty) widget.product.storage,
      if (widget.product.ram.isNotEmpty) '${widget.product.ram} RAM',
      if (widget.product.color.isNotEmpty) widget.product.color,
    ].join(', ');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product Image
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                padding: const EdgeInsets.all(6),
                child: Image.network(
                  widget.product.imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.smartphone,
                    size: 36,
                    color: Colors.grey.shade400,
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Title and Specs
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Certified refurbished badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.verified,
                            size: 12,
                            color: Color(0xFF0C5AD2),
                          ),
                          SizedBox(width: 4),
                          Text(
                            'CERTIFIED REFURBISHED',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0C5AD2),
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.product.displayTitle,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      specs.isNotEmpty ? specs : 'Standard Configuration',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 12),

          // Condition & Device ID Row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CONDITION',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(
                          Icons.check_circle_outline,
                          size: 14,
                          color: Color(0xFF10B981),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.product.condition.isNotEmpty
                              ? widget.product.condition
                              : 'Excellent',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'DEVICE ID',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.product.deviceID.isNotEmpty
                          ? widget.product.deviceID
                          : widget.product.productID,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
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
    );
  }

  Widget _buildDeliveryAddressCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _changeAddress,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: const [
                        Icon(
                          Icons.local_shipping_outlined,
                          color: Color(0xFF0C5AD2),
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Delivery Address',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text(
                        'Change',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0C5AD2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                const SizedBox(height: 12),

                if (_selectedAddress != null) ...[
                  Text(
                    _selectedAddress!.recipientName.isNotEmpty
                        ? _selectedAddress!.recipientName
                        : 'Recipient',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _selectedAddress!.fullAddress,
                    textAlign: TextAlign.justify,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF64748B),
                      height: 1.4,
                    ),
                  ),
                  if (_selectedAddress!.phoneNumber.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _selectedAddress!.phoneNumber,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ] else ...[
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: const [
                        Icon(
                          Icons.add_location_alt_outlined,
                          size: 20,
                          color: Color(0xFF0C5AD2),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'No address selected. Tap to add or select a delivery address.',
                            maxLines: 2,
                            textAlign: TextAlign.justify,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFF0C5AD2),
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentMethodCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _changePaymentMethod,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: const [
                        Icon(
                          Icons.payment_outlined,
                          color: Color(0xFF0C5AD2),
                          size: 20,
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
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text(
                        'Change',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0C5AD2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                const SizedBox(height: 12),

                if (_selectedPayment != null)
                  Row(
                    children: [
                      _buildPaymentIconBox(_selectedPayment!),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedPayment!.title,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _selectedPayment!.subtitle,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: const [
                        Icon(
                          Icons.payment_outlined,
                          size: 20,
                          color: Color(0xFF0C5AD2),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'No payment method selected. Please select a payment method.',
                            maxLines: 2,
                            textAlign: TextAlign.justify,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFF0C5AD2),
                              fontWeight: FontWeight.w600,
                              height: 1.35,
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
    );
  }

  Widget _buildPaymentIconBox(SelectedPaymentMethod payment) {
    if (payment.iconType == 'ewallet') {
      return Container(
        width: 48,
        height: 34,
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFDCFCE7)),
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.account_balance_wallet,
          size: 20,
          color: Color(0xFF16A34A),
        ),
      );
    } else if (payment.iconType == 'tng') {
      return Container(
        width: 48,
        height: 34,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        padding: const EdgeInsets.all(3),
        alignment: Alignment.center,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.asset(
            'assets/images/tng_logo.png',
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const Icon(
              Icons.account_balance_wallet,
              size: 18,
              color: Color(0xFF0C5AD2),
            ),
          ),
        ),
      );
    } else if (payment.iconType == 'grabpay') {
      return Container(
        width: 48,
        height: 34,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        padding: const EdgeInsets.all(3),
        alignment: Alignment.center,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.asset(
            'assets/images/grabpay_logo.png',
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const Icon(
              Icons.account_balance_wallet,
              size: 18,
              color: Color(0xFF0C5AD2),
            ),
          ),
        ),
      );
    } else if (payment.iconType == 'shopeepay') {
      return Container(
        width: 48,
        height: 34,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        padding: const EdgeInsets.all(3),
        alignment: Alignment.center,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.asset(
            'assets/images/shopeepay_logo.png',
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const Icon(
              Icons.account_balance_wallet,
              size: 18,
              color: Color(0xFF0C5AD2),
            ),
          ),
        ),
      );
    } else if (payment.iconType == 'bank' || payment.iconType == 'fpx') {
      return Container(
        width: 48,
        height: 34,
        decoration: BoxDecoration(
          color: const Color(0xFFEEF2FF),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFE0E7FF)),
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.account_balance,
          size: 20,
          color: Color(0xFF0C5AD2),
        ),
      );
    } else {
      return Container(
        width: 48,
        height: 34,
        decoration: BoxDecoration(
          color: const Color(0xFFEEF2FF),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFE0E7FF)),
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.credit_card,
          size: 20,
          color: Color(0xFF0C5AD2),
        ),
      );
    }
  }

  Widget _buildRentalPeriodCard(String startDateStr, String endDateStr) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(
                Icons.calendar_today_outlined,
                color: Color(0xFF0C5AD2),
                size: 18,
              ),
              SizedBox(width: 8),
              Text(
                'Rental Period',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Date Range Container with Divider
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'START DATE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        startDateStr,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(width: 24, height: 1.5, color: Colors.grey.shade300),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'END DATE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        endDateStr,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Duration summary row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Duration',
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
              Text(
                '${widget.durationMonths} Month${widget.durationMonths > 1 ? "s" : ""}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentSummaryCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(
                Icons.receipt_long_outlined,
                color: Color(0xFF0C5AD2),
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Payment Summary',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 1. Monthly Rental Fee (1st Month)
          _buildSummaryRow(
            'Monthly Rental Fee (RM${widget.monthlyRentalFee.toStringAsFixed(0)})',
            'RM${widget.monthlyRentalFee.toStringAsFixed(2)}',
          ),
          const SizedBox(height: 10),

          // 2. Refundable Security Deposit
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Text(
                    'Security Deposit',
                    style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.info_outline, size: 14, color: Color(0xFF94A3B8)),
                ],
              ),
              Text(
                'RM${widget.depositAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 3. Estimated Taxes (RM0.00 / Free)
          _buildSummaryRow('Estimated Taxes', 'RM0.00'),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 14),

          // 4. Total Amount Due Today
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              Text(
                'RM${_totalDueToday.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0C5AD2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Deposit is fully refundable upon safe return.',
              style: TextStyle(
                fontSize: 11,
                color: Color(0xFF64748B),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  Widget _buildTermsAndConditionsCheckbox() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: _agreedToTerms,
            onChanged: (val) {
              setState(() {
                _agreedToTerms = val ?? false;
              });
            },
            activeColor: const Color(0xFF0C5AD2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(
              text: 'I have read and agree to the ',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF475569),
                height: 1.4,
              ),
              children: [
                WidgetSpan(
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              const RentalTermsAndConditionsPage(),
                        ),
                      );
                    },
                    child: const Text(
                      'ReByte Rental Terms & Conditions',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0C5AD2),
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
                const TextSpan(
                  text:
                      ', including the equipment liability and return policies.',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConfirmRentalButton() {
    final canProceed =
        _selectedAddress != null &&
        _selectedPayment != null &&
        _agreedToTerms &&
        !_isProcessingPayment;

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: canProceed ? _handleConfirmRentalAndPay : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0C5AD2),
          disabledBackgroundColor: const Color(0xFF94A3B8),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isProcessingPayment
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : const Text(
                'Confirm Rental & Pay',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}
