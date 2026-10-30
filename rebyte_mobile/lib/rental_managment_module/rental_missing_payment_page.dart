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

class RentalMissingPaymentPage extends StatefulWidget {
  final Map<String, dynamic> rental;
  final String email;
  final String? name;

  const RentalMissingPaymentPage({
    super.key,
    required this.rental,
    required this.email,
    this.name,
  });

  @override
  State<RentalMissingPaymentPage> createState() => _RentalMissingPaymentPageState();
}

class _RentalMissingPaymentPageState extends State<RentalMissingPaymentPage> {
  static const Color _blue = Color(0xFF0C5AD2);
  static const Color _ink = Color(0xFF0F172A);
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  SelectedPaymentMethod? _selectedPayment;
  bool _loadingMethod = true;
  bool _processing = false;
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
        key: ValueKey('missing-payment-toast-$message'),
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
  }

  Future<void> _loadDefaultPaymentMethod() async {
    try {
      final rawCards = await XenditService.fetchSavedCards(widget.email);
      if (rawCards.isNotEmpty) {
        final cards = rawCards.map((entry) => PaymentAccountModel.fromJson(entry)).toList();
        final selected = cards.firstWhere((card) => card.isDefault, orElse: () => cards.first);
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
    if (mounted) setState(() => _loadingMethod = false);
  }

  Future<void> _changePaymentMethod() async {
    final selected = await Navigator.push<SelectedPaymentMethod>(
      context,
      MaterialPageRoute(
        builder: (_) => SelectPaymentMethodPage(
          email: widget.email,
          currentlySelected: _selectedPayment,
        ),
      ),
    );
    if (selected != null && mounted) setState(() => _selectedPayment = selected);
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> _payAndReport({
    required String rentalID,
    required String title,
    required String productID,
    required String imageUrl,
    required String storage,
    required String color,
    required double total,
  }) async {
    if (_processing || _selectedPayment == null || total <= 0) return;
    setState(() => _processing = true);
    try {
      final invoice = await XenditService.createInvoice(
        email: widget.email,
        amount: total,
        description: 'Missing rental device payment for $rentalID: $title',
        paymentMethodType: _selectedPayment!.type,
        productIDs: [productID.isNotEmpty ? productID : rentalID],
      );
      if (invoice['success'] != true || invoice['invoiceUrl'] == null) {
        throw Exception(invoice['error']?.toString() ?? 'Could not start Xendit payment.');
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
          final invoiceStatus = await XenditService.getInvoiceStatus(invoiceID);
          if (['PAID', 'SETTLED', 'COMPLETED'].contains(invoiceStatus['status']?.toString().toUpperCase())) {
            status = 'success';
          }
        } catch (_) {}
      }
      if (status != 'success') {
        if (mounted) {
          setState(() => _processing = false);
          _showToast(status == 'failed'
              ? (paymentResult['errorMessage']?.toString() ?? 'Payment failed.')
              : 'Payment cancelled.');
        }
        return;
      }

      final response = await http.post(
        Uri.parse('${AuthService.baseUrl}/api/rental/report-missing-payment'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'rentalID': rentalID,
          'invoiceID': invoiceID,
          'paymentAccountID': _selectedPayment!.id,
          'email': widget.email,
        }),
      ).timeout(const Duration(seconds: 30));
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || response.statusCode < 200 || response.statusCode >= 300 || decoded['success'] != true) {
        throw Exception(decoded is Map
            ? (decoded['error']?.toString() ?? decoded['message']?.toString() ?? 'Could not record the missing-device payment.')
            : 'The rental server returned an invalid response.');
      }
      if (!mounted) return;
      setState(() => _processing = false);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentSuccessPage(
            orderNumber: decoded['transactionID']?.toString() ?? invoiceID,
            amountPaid: total,
            email: widget.email,
            name: widget.name,
            paymentTitle: _selectedPayment!.title,
            paidAt: DateTime.now(),
            isRental: true,
            items: [
              CartItemModel(
                productID: productID.isNotEmpty ? productID : rentalID,
                listingTitle: title,
                description: 'Missing rental device payment',
                sellingPrice: total,
                imageUrl: imageUrl,
                storage: storage,
                color: color,
              ),
            ],
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _processing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Widget _section({required String title, required IconData icon, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.035), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 20, color: _blue),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _ink)),
        ]),
        const SizedBox(height: 14),
        child,
      ]),
    );
  }

  Widget _summaryRow(String label, String amount, {bool total = false}) {
    return Padding(
      padding: EdgeInsets.only(top: total ? 14 : 0),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(fontSize: total ? 16 : 14, fontWeight: total ? FontWeight.bold : FontWeight.w500, color: total ? _ink : const Color(0xFF475569))),
        Text(amount, style: TextStyle(fontSize: total ? 20 : 14, fontWeight: FontWeight.bold, color: total ? _blue : _ink)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rental = widget.rental;
    final product = rental['product'] is Map ? Map<String, dynamic>.from(rental['product'] as Map) : <String, dynamic>{};
    final device = rental['device'] is Map ? Map<String, dynamic>.from(rental['device'] as Map) : <String, dynamic>{};
    final rentalID = rental['rentalID']?.toString() ?? '';
    final productID = rental['productID']?.toString() ?? product['productID']?.toString() ?? '';
    final brand = (device['brand'] ?? product['brand'] ?? '').toString();
    final model = (device['model'] ?? product['model'] ?? '').toString();
    final title = (product['listingTitle'] ?? product['title'] ??
            (brand.isNotEmpty ? '$brand $model'.trim() : 'Rental Device'))
        .toString();
    final images = product['images'];
    final imageUrl = (product['imageUrl'] ??
            product['productImage'] ??
            (images is List && images.isNotEmpty ? images.first : ''))
        .toString();
    final serial = (device['serialNumber'] ?? device['imei'] ?? product['serialNumber'] ?? '').toString().trim();
    final storage = (device['storage'] ?? product['storage'] ?? '').toString();
    final color = (device['color'] ?? product['color'] ?? '').toString();
    final collectionPrice = _asDouble(
      product['collectedPrice'] ?? product['collectionPrice'] ?? product['collection_price'] ?? rental['collectedPrice'],
    );
    final sellingPrice = _asDouble(product['sellingPrice'] ?? rental['sellingPrice']);
    final deviceTotal = ((collectionPrice > 0 ? collectionPrice * 1.2 : sellingPrice) * 100).round() / 100;
    const lossPenalty = 50.0;
    final total = ((deviceTotal + lossPenalty) * 100).round() / 100;
    final money = NumberFormat('#,##0.00');

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: ReByteAppBar(scaffoldKey: _scaffoldKey),
      drawer: ReByteDrawer(isLoggedIn: true, email: widget.email, name: widget.name, isRentalsSelected: true),
      bottomNavigationBar: const ReByteBottomNavBar(selectedIndex: 3),
      body: SafeArea(
        child: Stack(children: [
          Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(children: [
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back, color: _ink)),
              const SizedBox(width: 4),
              const Expanded(child: Text('Report Missing Device', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: _ink))),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _section(
                  title: 'Device Details',
                  icon: Icons.phone_iphone_outlined,
                  child: Row(children: [
                    Container(
                      width: 78,
                      height: 78,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
                      child: imageUrl.isNotEmpty
                          ? Image.network(imageUrl, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.phone_iphone, size: 38, color: Color(0xFF94A3B8)))
                          : const Icon(Icons.phone_iphone, size: 38, color: Color(0xFF94A3B8)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _ink)),
                      const SizedBox(height: 5),
                      Text('Rental ID: $rentalID', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                      if (serial.isNotEmpty)
                        Text('Serial number: $serial', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                      if (storage.isNotEmpty || color.isNotEmpty)
                        Text([storage, color].where((value) => value.isNotEmpty).join(' • '), style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                    ])),
                  ]),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFECDD3)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 19, color: Color(0xFFDC2626)),
                      SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'The rental deposit is not refundable when the device is reported missing.',
                          style: TextStyle(fontSize: 13, height: 1.35, fontWeight: FontWeight.w600, color: Color(0xFFB91C1C)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _section(
                  title: 'Payment Method',
                  icon: Icons.account_balance_wallet_outlined,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _loadingMethod || _processing ? null : _changePaymentMethod,
                    child: Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFCBD5E1)), borderRadius: BorderRadius.circular(12)),
                      child: Row(children: [
                        const Icon(Icons.payment, color: _blue),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_loadingMethod ? 'Loading payment methods…' : (_selectedPayment?.title ?? 'Select a payment method'), style: const TextStyle(fontWeight: FontWeight.w700, color: _ink)),
                          const SizedBox(height: 3),
                          Text(_loadingMethod ? ' ' : (_selectedPayment?.subtitle ?? 'Card, FPX, or e-wallet'), style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                        ])),
                        Text(_selectedPayment == null ? 'Select' : 'Change', style: const TextStyle(color: _blue, fontWeight: FontWeight.bold)),
                        const Icon(Icons.chevron_right, color: Color(0xFF64748B)),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _section(
                  title: 'Payment Summary',
                  icon: Icons.receipt_long_outlined,
                  child: Column(children: [
                    _summaryRow('Device total price', 'RM ${money.format(deviceTotal)}'),
                    const SizedBox(height: 12),
                    _summaryRow('Loss penalty', 'RM ${money.format(lossPenalty)}'),
                    const Divider(height: 25, color: Color(0xFFE2E8F0)),
                    _summaryRow('Total', 'RM ${money.format(total)}', total: true),
                  ]),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: (_processing || _loadingMethod || _selectedPayment == null || deviceTotal <= 0)
                        ? null
                        : () => _payAndReport(
                              rentalID: rentalID,
                              title: title,
                              productID: productID,
                              imageUrl: imageUrl,
                              storage: storage,
                              color: color,
                              total: total,
                            ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _blue,
                      disabledBackgroundColor: const Color(0xFFCBD5E1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: _processing
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text('Pay RM ${money.format(total)} & Report Missing', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
                if (deviceTotal <= 0) ...[
                  const SizedBox(height: 8),
                  const Text('Device price is unavailable. Please contact support.', style: TextStyle(fontSize: 12, color: Color(0xFFB91C1C))),
                ],
              ]),
            ),
          ),
          ]),
          if (_toastMessage != null) _buildToastBanner(),
        ]),
      ),
    );
  }
}
