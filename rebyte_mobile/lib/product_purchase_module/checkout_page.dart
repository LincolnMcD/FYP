import 'package:flutter/material.dart';
import 'models/cart_item_model.dart';
import 'models/selected_payment_method.dart';
import 'services/shop_service.dart';
import '../account_management_module/models/address_model.dart';
import '../account_management_module/models/payment_account_model.dart';
import '../account_management_module/services/address_service.dart';
import '../account_management_module/services/xendit_service.dart';
import 'select_address_page.dart';
import 'select_payment_method_page.dart';
import 'payment_success_page.dart';
import 'payment_failure_page.dart';

class CheckoutPage extends StatefulWidget {
  final String email;
  final String? name;
  final List<CartItemModel> items;
  final VoidCallback? onCartUpdated;

  const CheckoutPage({
    super.key,
    required this.email,
    this.name,
    required this.items,
    this.onCartUpdated,
  });

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  AddressModel? _selectedAddress;
  SelectedPaymentMethod? _selectedPayment;
  bool _isLoading = true;
  bool _isProcessingPayment = false;
  String? _toastMessage;
  bool _isToastError = false;

  String? _currentOrderID;
  bool _isOrderPaid = false;

  @override
  void initState() {
    super.initState();
    _loadInitialDefaults();
    _createInitialOrder();
  }

  /// Create pending order record in Firebase as soon as user opens Checkout
  Future<void> _createInitialOrder() async {
    try {
      final subtotal = _calculateSubtotal();
      final total = _calculateTotal();
      final pids = widget.items.map((i) => i.productID).toList();
      final res = await ShopService.createOrder(
        email: widget.email,
        subtotal: subtotal,
        shippingFee: 0.0,
        totalAmount: total,
        addressID: _selectedAddress?.addressID ?? _selectedAddress?.id ?? '',
        productIDs: pids,
      );
      if (res['success'] == true && res['orderID'] != null) {
        _currentOrderID = res['orderID'].toString();
      }
    } catch (e) {
      debugPrint('Error creating initial order: $e');
    }
  }

  /// If user leaves checkout without completing payment, mark order as cancelled
  Future<void> _handleLeaveCheckout() async {
    if (!_isOrderPaid && _currentOrderID != null) {
      ShopService.updateOrderStatus(
        orderID: _currentOrderID!,
        orderStatus: 'cancelled',
      );
    }
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
      } else {
        _selectedPayment = null;
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  double _calculateSubtotal() {
    double sum = 0.0;
    for (final item in widget.items) {
      sum += item.sellingPrice;
    }
    return sum;
  }

  // NO TAX CHARGED
  double _calculateTotal() {
    return _calculateSubtotal();
  }

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

  Future<void> _handleConfirmAndPay() async {
    if (_selectedAddress == null) {
      _showTopToast('Please select a delivery address', isError: true);
      return;
    }

    if (_selectedPayment == null) {
      _showTopToast('Please select a payment method', isError: true);
      return;
    }

    setState(() => _isProcessingPayment = true);

    final totalAmount = _calculateTotal();
    final productIDs = widget.items.map((i) => i.productID).toList();
    final expectedPrices = <String, double>{
      for (final item in widget.items) item.productID: item.sellingPrice,
    };

    // 1. Create Xendit Payment Session / Invoice for the exact amount and method
    final invoiceRes = await XenditService.createInvoice(
      email: widget.email,
      amount: totalAmount,
      description: 'ReByte Order (${widget.items.length} items)',
      paymentMethodType: _selectedPayment!.type, // 'ewallet', 'fpx', or 'card'
      productIDs: productIDs,
    );

    if (invoiceRes['success'] != true || invoiceRes['invoiceUrl'] == null) {
      if (mounted) {
        setState(() => _isProcessingPayment = false);
        _showTopToast(invoiceRes['error']?.toString() ?? 'Failed to initialize Xendit payment', isError: true);
      }
      return;
    }

    final invoiceUrl = invoiceRes['invoiceUrl'].toString();

    if (!mounted) return;

    // 2. Launch in-app secure payment webview with Xendit
    String paymentTypeLabel = 'Card';
    if (_selectedPayment!.type == 'fpx') {
      paymentTypeLabel = 'FPX';
    } else if (_selectedPayment!.type == 'ewallet') {
      paymentTypeLabel = 'E-Wallet';
    }

    // Prepare prefill data (email, phone, card details if card)
    final Map<String, dynamic> prefillData = {
      'email': widget.email,
    };
    if (_selectedAddress != null && _selectedAddress!.phoneNumber.isNotEmpty) {
      prefillData['phone'] = _selectedAddress!.phoneNumber;
    }
    if (_selectedPayment!.type == 'card' && _selectedPayment!.rawData != null) {
      prefillData.addAll(_selectedPayment!.rawData!);
    }

    final invoiceId = invoiceRes['invoiceId']?.toString();

    final payResult = await XenditService.launchPaymentWebView(
      context: context,
      invoiceUrl: invoiceUrl,
      title: 'Xendit Secure Pay ($paymentTypeLabel)',
      invoiceId: invoiceId,
      cardData: prefillData,
    );

    String payStatus = payResult['status']?.toString() ?? 'cancelled';

    // 2a. If status returned cancelled, double check with Xendit whether the customer actually paid
    if (payStatus == 'cancelled' && invoiceId != null && invoiceId.isNotEmpty) {
      try {
        final check = await XenditService.getInvoiceStatus(invoiceId);
        final invStatus = check['status']?.toString().toUpperCase() ?? '';
        if (invStatus == 'PAID' || invStatus == 'SETTLED' || invStatus == 'COMPLETED') {
          payStatus = 'success';
        }
      } catch (_) {}
    }

    // 2b. If user cancelled / closed without completing payment, show toast in red color (no error page)
    if (payStatus == 'cancelled') {
      if (mounted) {
        setState(() => _isProcessingPayment = false);
        _showTopToast('Payment cancelled', isError: true);
      }
      return;
    }

    // 2b. If payment failed at gateway / bank decline / insufficient funds
    if (payStatus == 'failed') {
      final failMsg = payResult['errorMessage']?.toString() ?? 'Payment was declined by your bank or card issuer.';
      
      // Update order status to 'Fail' with failReason
      if (_currentOrderID != null) {
        ShopService.updateOrderStatus(
          orderID: _currentOrderID!,
          orderStatus: 'Fail',
          addressID: _selectedAddress?.addressID ?? _selectedAddress?.id,
          failReason: failMsg,
        );
      }

      // Create a transaction record with status: 'Fail'
      ShopService.createTransaction(
        transactionType: 'Purchase',
        transactionStatus: 'Fail',
        transactionAmount: totalAmount,
        gatewayTransactionID: invoiceRes['invoiceId']?.toString(),
        paymentAccountID: _selectedPayment?.id,
        orderID: _currentOrderID,
      );

      if (mounted) {
        setState(() => _isProcessingPayment = false);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PaymentFailurePage(
              orderTotal: totalAmount,
              errorCode: failMsg.contains('insufficient') ? 'INSUFFICIENT FUNDS' : 'PAYMENT DECLINED',
              errorMessage: failMsg,
              email: widget.email,
              name: widget.name,
            ),
          ),
        );
      }
      return;
    }

    // 3. Payment succeeded in Xendit -> finalize inventory purchase in ReByte database
    final result = await ShopService.purchaseItems(
      email: widget.email,
      productIDs: productIDs,
      expectedPrices: expectedPrices,
    );

    if (mounted) {
      setState(() => _isProcessingPayment = false);

      if (result['success'] == true) {
        _isOrderPaid = true;
        widget.onCartUpdated?.call();

        final finalOrderID = _currentOrderID ?? ('#RB-${1000 + (DateTime.now().millisecondsSinceEpoch % 9000)}');

        // Update Order record to 'Delivering' in Firebase
        if (_currentOrderID != null) {
          ShopService.updateOrderStatus(
            orderID: _currentOrderID!,
            orderStatus: 'Delivering',
            addressID: _selectedAddress?.addressID ?? _selectedAddress?.id,
          );
        }

        // Create Transaction record in Firebase (status: 'Success')
        ShopService.createTransaction(
          transactionType: 'Purchase',
          transactionStatus: 'Success',
          transactionAmount: totalAmount,
          gatewayTransactionID: invoiceRes['invoiceId']?.toString(),
          paymentAccountID: _selectedPayment?.id,
          orderID: _currentOrderID,
        );

        // Send official itemized receipt email with ReByte branding
        final itemsPayload = widget.items.map((i) => {
          'productID': i.productID,
          'productName': i.displayTitle,
          'sellingPrice': i.sellingPrice,
        }).toList();

        ShopService.sendReceiptEmail(
          email: widget.email,
          orderID: finalOrderID,
          items: itemsPayload,
          subtotal: _calculateSubtotal(),
          shippingFee: 0.0,
          totalAmount: totalAmount,
          paidAt: DateTime.now(),
          paymentTitle: _selectedPayment!.title,
        );

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => PaymentSuccessPage(
              orderNumber: finalOrderID,
              amountPaid: totalAmount,
              email: widget.email,
              name: widget.name,
              paymentTitle: _selectedPayment!.title,
              paidAt: DateTime.now(),
              items: widget.items,
              deliveryAddress: _selectedAddress,
            ),
          ),
        );
      } else {
        // Race condition: Item was purchased by another user while payment was completing
        // 1. Mark this customer's order as Fail in Firebase with failReason
        if (_currentOrderID != null) {
          ShopService.updateOrderStatus(
            orderID: _currentOrderID!,
            orderStatus: 'Fail',
            addressID: _selectedAddress?.addressID ?? _selectedAddress?.id,
            failReason: 'Item purchased by another customer',
          );
        }

        // 2. The payment transaction was successful at gateway -> transactionStatus: 'Success'
        ShopService.createTransaction(
          transactionType: 'Purchase',
          transactionStatus: 'Success',
          transactionAmount: totalAmount,
          gatewayTransactionID: invoiceRes['invoiceId']?.toString(),
          paymentAccountID: _selectedPayment?.id,
          orderID: _currentOrderID,
        );

        final invoiceId = invoiceRes['invoiceId']?.toString();
        if (invoiceId != null && invoiceId.isNotEmpty) {
          // 3. Trigger automatic refund with Xendit so customer is not charged
          final refundRes = await XenditService.refundInvoice(
            invoiceId: invoiceId,
            reason: 'CANCELLATION',
          );

          // 4. Create a Refund transaction record with status: 'Success'
          ShopService.createTransaction(
            transactionType: 'Refund',
            transactionStatus: 'Success',
            transactionAmount: totalAmount,
            gatewayTransactionID: refundRes['data']?['id']?.toString() ?? invoiceId,
            paymentAccountID: _selectedPayment?.id,
            orderID: _currentOrderID,
          );
        }
        widget.onCartUpdated?.call();

        if (!mounted) return;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PaymentFailurePage(
              orderTotal: totalAmount,
              errorCode: 'ITEM PURCHASED',
              errorMessage: 'Item was purchased by another customer just now. A full automatic refund has been issued.',
              email: widget.email,
              name: widget.name,
              isReturnToCart: true, // Return to Cart button
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtotal = _calculateSubtotal();
    final total = _calculateTotal();
    final bool canPay = !_isProcessingPayment &&
        _selectedAddress != null &&
        _selectedPayment != null &&
        widget.items.isNotEmpty;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _handleLeaveCheckout();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A), size: 22),
            onPressed: () {
              Navigator.pop(context, _isOrderPaid ? 'paid' : 'cancelled');
            },
          ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/rebyte_logo.png', height: 32),
            const SizedBox(width: 8),
            const Text(
              'ReByte',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF0C5AD2)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Checkout',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F254B),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 18),

                      // 1. ORDER SUMMARY CARD
                      _buildOrderSummaryCard(),
                      const SizedBox(height: 16),

                      // 2. DELIVERY ADDRESS CARD
                      _buildDeliveryAddressCard(),
                      const SizedBox(height: 16),

                      // 3. PAYMENT METHOD CARD
                      _buildPaymentMethodCard(),
                      const SizedBox(height: 16),

                      // 4. PRICE BREAKDOWN CARD (NO TAX CHARGED)
                      _buildPriceBreakdownCard(subtotal, total),
                      const SizedBox(height: 24),

                      // 5. CONFIRM & PAY BUTTON
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: canPay ? _handleConfirmAndPay : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0C5AD2),
                            disabledBackgroundColor: const Color(0xFF94A3B8),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(26),
                            ),
                          ),
                          child: _isProcessingPayment
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(Icons.lock_outline, color: Colors.white, size: 18),
                                    SizedBox(width: 8),
                                    Text(
                                      'Confirm & Pay',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
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
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
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
    ),
  );
  }

  Widget _buildOrderSummaryCard() {
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
              Icon(Icons.shopping_cart_outlined, color: Color(0xFF0C5AD2), size: 20),
              SizedBox(width: 8),
              Text(
                'Order Summary',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...widget.items.map((item) => _buildOrderItemRow(item)),
        ],
      ),
    );
  }

  Widget _buildOrderItemRow(CartItemModel item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Thumbnail image
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            padding: const EdgeInsets.all(4),
            child: Image.network(
              item.imageUrl,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Icon(Icons.smartphone, size: 28, color: Colors.grey.shade400),
            ),
          ),
          const SizedBox(width: 12),

          // Specs and Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.displayTitle,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${item.displaySpecs.isNotEmpty ? "${item.displaySpecs} • " : ""}${item.condition} Condition',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Price
          Text(
            'RM${item.sellingPrice.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
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
                        Icon(Icons.local_shipping_outlined, color: Color(0xFF0C5AD2), size: 20),
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
                    _selectedAddress!.recipientName.isNotEmpty ? _selectedAddress!.recipientName : 'Recipient',
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
                        Icon(Icons.add_location_alt_outlined, size: 20, color: Color(0xFF0C5AD2)),
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
                        Icon(Icons.payment_outlined, color: Color(0xFF0C5AD2), size: 20),
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
                        Icon(Icons.payment_outlined, size: 20, color: Color(0xFF0C5AD2)),
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
        child: const Icon(Icons.account_balance_wallet, size: 20, color: Color(0xFF16A34A)),
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
            errorBuilder: (context, error, stackTrace) => const Icon(Icons.account_balance_wallet, size: 18, color: Color(0xFF0C5AD2)),
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
            errorBuilder: (context, error, stackTrace) => const Icon(Icons.account_balance_wallet, size: 18, color: Color(0xFF0C5AD2)),
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
            errorBuilder: (context, error, stackTrace) => const Icon(Icons.account_balance_wallet, size: 18, color: Color(0xFF0C5AD2)),
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
        child: const Icon(Icons.account_balance, size: 20, color: Color(0xFF0C5AD2)),
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
        child: const Icon(Icons.credit_card, size: 20, color: Color(0xFF0C5AD2)),
      );
    }
  }

  Widget _buildPriceBreakdownCard(double subtotal, double total) {
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
        children: [
          _buildRow('Subtotal', 'RM${subtotal.toStringAsFixed(2)}'),
          const SizedBox(height: 10),
          _buildRow('Shipping (Standard)', 'Free'),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12.0),
            child: Divider(color: Color(0xFFE2E8F0), height: 1),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              Text(
                'RM${total.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0C5AD2),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13.5,
            color: Color(0xFF64748B),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }
}
