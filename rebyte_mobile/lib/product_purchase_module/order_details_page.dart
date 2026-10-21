import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'customer_delivery_tracking_page.dart';
import 'models/cart_item_model.dart';
import 'select_address_page.dart';
import 'services/shop_service.dart';
import '../account_management_module/models/address_model.dart';
import '../account_management_module/home_page.dart';
import '../../widgets/rebyte_app_bar.dart';

class OrderDetailsPage extends StatefulWidget {
  final String orderNumber;
  final double amountPaid;
  final String email;
  final String? name;
  final DateTime paidAt;
  final List<CartItemModel> items;
  final AddressModel? deliveryAddress;
  final String paymentTitle;
  final String paymentType;
  final String paymentAccountID;
  final String taskStatus;
  final String orderStatus;
  final String failReason;
  final String? estimatedEndTime;
  final String? scheduleDate;
  final int? estimatedDuration;

  const OrderDetailsPage({
    super.key,
    required this.orderNumber,
    required this.amountPaid,
    required this.email,
    this.name,
    required this.paidAt,
    required this.items,
    this.deliveryAddress,
    required this.paymentTitle,
    this.paymentType = 'card',
    this.paymentAccountID = '',
    this.taskStatus = 'Packaging',
    this.orderStatus = 'Packaging',
    this.failReason = '',
    this.estimatedEndTime,
    this.scheduleDate,
    this.estimatedDuration,
  });

  @override
  State<OrderDetailsPage> createState() => _OrderDetailsPageState();
}

class _OrderDetailsPageState extends State<OrderDetailsPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late String _taskStatus;
  late String _orderStatus;
  AddressModel? _deliveryAddress;
  String? _estimatedEndTime;
  String? _scheduleDate;
  bool _isCancelling = false;
  bool _isUpdatingAddress = false;
  String? _toastMessage;
  bool _isToastError = false;

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

  @override
  void initState() {
    super.initState();
    _taskStatus = widget.taskStatus;
    _orderStatus = widget.orderStatus;
    _deliveryAddress = widget.deliveryAddress;
    _estimatedEndTime = widget.estimatedEndTime;
    _scheduleDate = widget.scheduleDate;
  }

  Future<void> _refreshOrderDetails() async {
    final cleanOrderID = widget.orderNumber.replaceAll('#', '').trim();
    final orders = await ShopService.fetchOrders(email: widget.email);
    final match = orders.firstWhere(
      (o) => (o['orderID']?.toString().replaceAll('#', '').trim() == cleanOrderID ||
              o['orderNumber']?.toString().replaceAll('#', '').trim() == cleanOrderID),
      orElse: () => {},
    );
    if (match.isNotEmpty && mounted) {
      setState(() {
        if (match['deliveryAddress'] != null && match['deliveryAddress'] is Map) {
          _deliveryAddress = AddressModel.fromJson(Map<String, dynamic>.from(match['deliveryAddress'] as Map));
        }
        if (match['taskStatus'] != null) {
          _taskStatus = match['taskStatus'].toString();
        }
        if (match['orderStatus'] != null) {
          _orderStatus = match['orderStatus'].toString();
        }
        _estimatedEndTime = match['estimatedEndTime']?.toString();
        _scheduleDate = match['scheduleDate']?.toString();
      });
    }
  }

  /// Cancellation & address edit are allowed ONLY when order is at Packaging status.
  /// If beyond Packaging (Delivering, Shipping, In Transit, Completed, Delivered) or Cancelled, NOT allowed.
  bool get _canModifyOrder {
    final ts = _taskStatus.trim().toLowerCase();
    final os = _orderStatus.trim().toLowerCase();

    // Disallow if cancelled, terminated, refunded, or failed
    if (ts.contains('cancel') || os.contains('cancel') ||
        ts.contains('terminate') || os.contains('terminate') ||
        ts.contains('refund') || os.contains('refund') ||
        ts.contains('fail') || os.contains('fail')) {
      return false;
    }

    // Over packaging status: shipping, delivering, in transit, delivered, completed
    const overPackaging = ['shipping', 'in transit', 'delivered', 'completed'];
    if (overPackaging.contains(ts) || os == 'delivered' || os == 'completed') {
      return false;
    }

    // Allowed when at packaging (or initial pending/confirmed before dispatch)
    const allowed = ['packaging', 'packaged', 'packing', 'confirmed', 'pending', 'unassigned', 'assigned'];
    if (allowed.contains(ts) || os == 'packaging' || os == 'pending' || os == 'confirmed') {
      return true;
    }

    return _getStepIndex(_taskStatus) <= 2;
  }

  Future<void> _handleCancelOrder() async {
    final double refundAmount = widget.amountPaid * 0.5;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 24),
            SizedBox(width: 8),
            Text(
              'Cancel Order',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you sure you want to cancel this order?',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Refund Policy Notice:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Only 50% of the total amount (RM ${refundAmount.toStringAsFixed(2)}) will be refunded to your original payment account. The remaining 50% is non-refundable.',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF991B1B), height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'This action cannot be undone. Products will be relisted back into the store.',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Order', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Confirm Cancel'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() => _isCancelling = true);
      final cleanOrderID = widget.orderNumber.replaceAll('#', '').trim();
      final res = await ShopService.cancelOrder(orderID: cleanOrderID);
      if (!mounted) return;
      setState(() => _isCancelling = false);

      if (res['success'] == true) {
        setState(() {
          _orderStatus = 'Cancelled';
          _taskStatus = 'Cancelled';
        });
        _showTopToast('Refund successful! 50% refund (RM ${refundAmount.toStringAsFixed(2)}) has been refunded.');
      } else {
        _showTopToast(res['error'] ?? 'Failed to cancel order.', isError: true);
      }
    }
  }

  Future<void> _handleChangeAddress() async {
    final selected = await Navigator.push<AddressModel>(
      context,
      MaterialPageRoute(
        builder: (context) => SelectAddressPage(
          email: widget.email,
          currentlySelected: _deliveryAddress,
        ),
      ),
    );

    if (selected != null && mounted) {
      if (_deliveryAddress?.addressID == selected.addressID) {
        return;
      }
      setState(() => _isUpdatingAddress = true);
      final cleanOrderID = widget.orderNumber.replaceAll('#', '').trim();
      final res = await ShopService.updateOrderAddress(
        orderID: cleanOrderID,
        addressID: selected.addressID,
      );
      if (!mounted) return;
      setState(() => _isUpdatingAddress = false);

      if (res['success'] == true) {
        setState(() {
          _deliveryAddress = selected;
          if (res['taskStatus'] != null && res['taskStatus'].toString().isNotEmpty) {
            _taskStatus = res['taskStatus'].toString();
          }
          if (res['orderStatus'] != null && res['orderStatus'].toString().isNotEmpty) {
            _orderStatus = res['orderStatus'].toString();
          }
          if (res.containsKey('estimatedEndTime')) {
            _estimatedEndTime = res['estimatedEndTime']?.toString();
          }
          if (res.containsKey('scheduleDate')) {
            _scheduleDate = res['scheduleDate']?.toString();
          }
        });
        _showTopToast(res['message'] ?? 'Delivery address is changed.');
        // Fully refresh order details from database
        await _refreshOrderDetails();
      } else {
        _showTopToast(res['error'] ?? 'Failed to update address.', isError: true);
      }
    }
  }

  int _getStepIndex(String taskStatus) {
    final s = taskStatus.toLowerCase().trim();
    if (s == 'delivered' || s == 'completed' || s == 'delivery') return 4;
    if (s == 'shipping' || s == 'in transit' || s == 'delivering') return 3;
    if (s == 'packaging' || s == 'packaged' || s == 'packing') return 2;
    return 1; // Confirmed
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM dd, yyyy');
    final currentStep = _getStepIndex(_taskStatus);

    final isShipping = _taskStatus.trim().toLowerCase() == 'shipping' || _orderStatus.trim().toLowerCase() == 'shipping';
    final isDelivering = _taskStatus.trim().toLowerCase() == 'shipping' ||
        _taskStatus.trim().toLowerCase() == 'in transit' ||
        _taskStatus.trim().toLowerCase() == 'delivering' ||
        _orderStatus.trim().toLowerCase() == 'shipping' ||
        currentStep == 3;
    String? estimatedArrivalText;
    if (isShipping && _estimatedEndTime != null && _estimatedEndTime!.isNotEmpty) {
      final rawEndTime = _estimatedEndTime!;
      final cleanTime = rawEndTime.contains('T')
          ? rawEndTime.split('T').last.split('.').first
          : (rawEndTime.length == 5 ? '$rawEndTime:00' : rawEndTime);
      final datePart = _scheduleDate ?? DateFormat('yyyy-MM-dd').format(DateTime.now());
      final parsedDt = DateTime.tryParse('${datePart}T$cleanTime');
      if (parsedDt != null) {
        final formattedDateStr = DateFormat('MMM dd, yyyy').format(parsedDt);
        final formattedTimeStr = DateFormat('h:mm a').format(parsedDt);
        estimatedArrivalText = '$formattedDateStr by $formattedTimeStr';
      } else {
        estimatedArrivalText = '${_scheduleDate ?? ''} $_estimatedEndTime'.trim();
      }
    }

    // Resolve Payment Method display
    IconData paymentIcon;
    String displayPaymentText;
    String paymentSubtitle;

    final payAccId = widget.paymentAccountID.toLowerCase();
    final payType = widget.paymentType.toLowerCase();

    if (payAccId == 'ewallet_all' || payType == 'ewallet') {
      paymentIcon = Icons.account_balance_wallet_outlined;
      displayPaymentText = 'E-Wallet';
      paymentSubtitle = 'Touch \'n Go / GrabPay / Boost';
    } else if (payAccId == 'fpx_online_banking' || payAccId == 'fpx' || payType == 'fpx') {
      paymentIcon = Icons.account_balance_outlined;
      displayPaymentText = 'FPX transfer';
      paymentSubtitle = 'Online Banking';
    } else {
      paymentIcon = Icons.credit_card;
      displayPaymentText = widget.paymentTitle;
      paymentSubtitle = 'Secured Card Payment';
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: ReByteAppBar(
        scaffoldKey: _scaffoldKey,
      ),
      drawer: ReByteDrawer(
        isLoggedIn: true,
        email: widget.email,
        name: widget.name,
        isMyOrdersSelected: true,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: 1, // Shop Tab selected
          onTap: (index) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (context) => HomePage(
                  isLoggedIn: true,
                  email: widget.email,
                  name: widget.name,
                  initialIndex: index,
                ),
              ),
              (route) => false,
            );
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: const Color(0xFF0C5AD2),
          unselectedItemColor: Colors.grey.shade500,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
          unselectedLabelStyle: const TextStyle(fontSize: 10),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.shopping_bag_outlined), label: 'Shop'),
            BottomNavigationBarItem(icon: Icon(Icons.autorenew), label: 'Trade-In'),
            BottomNavigationBarItem(icon: Icon(Icons.calendar_month_outlined), label: 'Rentals'),
            BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Account'),
          ],
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            RefreshIndicator(
              onRefresh: _refreshOrderDetails,
              color: const Color(0xFF0C5AD2),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Page Header with back button & title
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B), size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Order Details',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 1. Order Number & Status Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Order Number',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.orderNumber,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0C5AD2),
                              ),
                            ),
                          ],
                        ),
                        // Status Badge using same live pill design
                        _buildTaskStatusPill(
                          () {
                            final os = _orderStatus.trim().toLowerCase();
                            final ts = _taskStatus.trim().toLowerCase();
                            if (os == 'cancelled' || os == 'canceled') return 'Cancelled';
                            if (os == 'fail' || os == 'failed') return 'Failed';
                            if (os == 'delivered' || os == 'completed') return 'Delivered';
                            if (ts == 'rejected' || os == 'rejected') return 'Unassigned';
                            return _taskStatus.isNotEmpty ? _taskStatus : _orderStatus;
                          }(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Placed on ${dateFormat.format(widget.paidAt)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    // Estimated Arrival Banner (when Shipping)
                    if (isShipping && estimatedArrivalText != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.local_shipping_rounded, size: 18, color: Color(0xFF1D4ED8)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    const TextSpan(
                                      text: 'Estimated Arrival: ',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E3A8A)),
                                    ),
                                    TextSpan(
                                      text: estimatedArrivalText,
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF0C5AD2)),
                                    ),
                                  ],
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
              const SizedBox(height: 16),

              // 2. Delivery Status Stepper Card OR Failure Reason Card
              Builder(
                builder: (context) {
                  final oStatus = _orderStatus.trim().toLowerCase();
                  final tStatus = _taskStatus.trim().toLowerCase();
                  final isFailed = oStatus == 'fail' || oStatus == 'failed' || tStatus == 'failed';
                  final isCancelled = oStatus == 'cancelled' || oStatus == 'canceled' || tStatus == 'cancelled';
                  final isCompleted = oStatus == 'completed' || oStatus == 'delivered' || tStatus == 'completed' || tStatus == 'delivered';

                  // If failed: replace delivery block with reason card
                  if (isFailed) {
                    final reasonText = widget.failReason.isNotEmpty
                        ? widget.failReason
                        : 'Payment was declined by your bank or payment gateway. Please try again or use another payment method.';
                    return Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFFECACA)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: const [
                                  Icon(Icons.error_outline, size: 18, color: Color(0xFFDC2626)),
                                  SizedBox(width: 8),
                                  Text(
                                    'Reason of Failure',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF991B1B),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                reasonText,
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.4,
                                  color: Color(0xFF7F1D1D),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    );
                  }

                  // If cancelled or completed: no delivery status block
                  if (isCancelled || isCompleted) {
                    return const SizedBox.shrink();
                  }

                  // Active / in-progress order: show Delivery Status Stepper
                  return Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Delivery Status',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Stepper row based on taskStatus
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildStepItem(
                                  icon: Icons.check,
                                  label: 'Confirmed',
                                  isActive: currentStep >= 1,
                                  isCompleted: currentStep >= 1,
                                ),
                                _buildStepConnector(isCompleted: currentStep >= 2),
                                _buildStepItem(
                                  icon: (currentStep > 2 || currentStep == 4) ? Icons.check : Icons.inventory_2,
                                  label: 'Packaging',
                                  isActive: currentStep >= 2,
                                  isCompleted: currentStep > 2 || currentStep == 4,
                                ),
                                _buildStepConnector(isCompleted: currentStep >= 3),
                                _buildStepItem(
                                  icon: (currentStep > 3 || currentStep == 4) ? Icons.check : Icons.local_shipping,
                                  label: 'Shipping',
                                  isActive: currentStep >= 3,
                                  isCompleted: currentStep > 3 || currentStep == 4,
                                ),
                                _buildStepConnector(isCompleted: currentStep >= 4),
                                _buildStepItem(
                                  icon: currentStep == 4 ? Icons.check : Icons.home_outlined,
                                  label: 'Delivered',
                                  isActive: currentStep >= 4,
                                  isCompleted: currentStep == 4,
                                ),
                              ],
                            ),
                            // Track on Map button - ONLY shown when order is delivering
                            if (isDelivering) ...[
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    final cleanOrderID = widget.orderNumber.replaceAll('#', '').trim();
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => CustomerDeliveryTrackingPage(
                                          orderID: cleanOrderID,
                                          taskStatus: _taskStatus,
                                          orderStatus: _orderStatus,
                                          scheduleDate: _scheduleDate,
                                          estimatedEndTime: _estimatedEndTime,
                                          deliveryAddress: _deliveryAddress,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.map_outlined, size: 18, color: Color(0xFF0C5AD2)),
                                  label: const Text(
                                    'Track on Map',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0C5AD2),
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    side: const BorderSide(color: Color(0xFFBFDBFE)),
                                    backgroundColor: const Color(0xFFF1F5FD),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),

              // 3. Order Summary Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.shopping_cart_outlined, size: 18, color: Color(0xFF0C5AD2)),
                        SizedBox(width: 8),
                        Text(
                          'Order Summary',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Product item cards
                    ...widget.items.map((item) => _buildOrderItemCard(item)),

                    const SizedBox(height: 16),
                    const Divider(color: Color(0xFFF1F5F9), height: 1),
                    const SizedBox(height: 12),

                    // Subtotal
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Subtotal',
                          style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                        ),
                        Text(
                          'RM${widget.amountPaid.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Shipping
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text(
                          'Shipping',
                          style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                        ),
                        Text(
                          'Free',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: Color(0xFFE2E8F0), height: 1),
                    const SizedBox(height: 12),
                    // Total
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        ),
                        Text(
                          'RM${widget.amountPaid.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0C5AD2)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 4. Delivery Address Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.local_shipping_outlined, size: 18, color: Color(0xFF0C5AD2)),
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
                        if (_canModifyOrder)
                          InkWell(
                            onTap: _isUpdatingAddress ? null : _handleChangeAddress,
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: _isUpdatingAddress
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFF0C5AD2),
                                      ),
                                    )
                                  : const Text(
                                      'Edit',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF0C5AD2),
                                      ),
                                    ),
                            ),
                          ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10.0),
                      child: Divider(color: Color(0xFFF1F5F9), height: 1),
                    ),
                    Text(
                      _deliveryAddress?.recipientName ?? widget.name ?? 'Customer',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _deliveryAddress != null
                          ? '${_deliveryAddress!.addressLine}, ${_deliveryAddress!.postcode} ${_deliveryAddress!.city}, ${_deliveryAddress!.state}, Malaysia'
                          : '12, Jalan SS 15/4, SS 15, 47500 Subang Jaya, Selangor, Malaysia',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 5. Payment Method Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.payment, size: 18, color: Color(0xFF0C5AD2)),
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
                      padding: EdgeInsets.symmetric(vertical: 10.0),
                      child: Divider(color: Color(0xFFF1F5F9), height: 1),
                    ),
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: Icon(
                            paymentIcon,
                            size: 20,
                            color: const Color(0xFF0C5AD2),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayPaymentText,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              paymentSubtitle,
                              style: const TextStyle(
                                fontSize: 11,
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
              if (_canModifyOrder) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _isCancelling ? null : _handleCancelOrder,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Color(0xFFFCA5A5)),
                      backgroundColor: const Color(0xFFFEF2F2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isCancelling
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFFDC2626),
                            ),
                          )
                        : const Text(
                            'Cancel Order',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFDC2626),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 24),
              ] else ...[
                const SizedBox(height: 24),
              ],
            ],
          ),
        ),
      ),
        // Floating Top Toast Banner
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
                  color: _isToastError ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
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
                        textAlign: TextAlign.justify,
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

  Widget _buildStepItem({
    required IconData icon,
    required String label,
    required bool isActive,
    required bool isCompleted,
  }) {
    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF0C5AD2) : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: isActive ? const Color(0xFF0C5AD2) : const Color(0xFFCBD5E1),
              width: 1.5,
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: isActive ? Colors.white : const Color(0xFF94A3B8),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
            color: isActive ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }

  Widget _buildStepConnector({required bool isCompleted}) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(top: 18),
        color: isCompleted ? const Color(0xFF0C5AD2) : const Color(0xFFE2E8F0),
      ),
    );
  }

  Widget _buildOrderItemCard(CartItemModel item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Image
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(4),
            child: Image.network(
              item.imageUrl,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  Icon(Icons.smartphone, size: 28, color: Colors.grey.shade400),
            ),
          ),
          const SizedBox(width: 12),
          // Title & Specs
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.displayTitle,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
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
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskStatusPill(String taskStatus) {
    var s = taskStatus.toLowerCase().trim();
    if (s == 'rejected') s = 'unassigned';
    Color bgColor = const Color(0xFFF1F5F9);
    Color textColor = const Color(0xFF475569);
    IconData icon = Icons.inventory_2_outlined;

    if (s == 'delivered' || s == 'completed') {
      bgColor = const Color(0xFFDCFCE7);
      textColor = const Color(0xFF16A34A);
      icon = Icons.check_circle_outline;
    } else if (s == 'shipping' || s == 'delivering' || s == 'ongoing') {
      bgColor = const Color(0xFFE0E7FF);
      textColor = const Color(0xFF4338CA);
      icon = Icons.directions_car_outlined;
    } else if (s == 'packaging' || s == 'packaged' || s == 'packing' || s == 'processing' || s == 'confirmed') {
      bgColor = const Color(0xFFFEF3C7);
      textColor = const Color(0xFFD97706);
      icon = Icons.inventory_2_outlined;
    } else if (s == 'unassigned' || s == 'pending') {
      bgColor = const Color(0xFFEFF6FF);
      textColor = const Color(0xFF2563EB);
      icon = Icons.schedule_outlined;
    } else if (s == 'cancelled' || s == 'canceled' || s == 'failed' || s == 'fail') {
      bgColor = const Color(0xFFFEE2E2);
      textColor = const Color(0xFFDC2626);
      icon = Icons.error_outline;
    }

    final displayText = (s == 'unassigned')
        ? 'Unassigned'
        : (taskStatus.isNotEmpty
            ? (taskStatus[0].toUpperCase() + taskStatus.substring(1))
            : 'Packaging');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: textColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(
            displayText,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
