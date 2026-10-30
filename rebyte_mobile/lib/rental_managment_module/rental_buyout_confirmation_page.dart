import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../account_management_module/models/address_model.dart';
import '../../account_management_module/models/payment_account_model.dart';
import '../../account_management_module/services/address_service.dart';
import '../../account_management_module/services/auth_service.dart';
import '../../account_management_module/services/xendit_service.dart';
import '../../product_purchase_module/models/cart_item_model.dart';
import '../../product_purchase_module/models/selected_payment_method.dart';
import '../../product_purchase_module/payment_success_page.dart';
import '../../product_purchase_module/select_address_page.dart';
import '../../product_purchase_module/select_payment_method_page.dart';
import '../../widgets/rebyte_app_bar.dart';
import '../../widgets/rebyte_bottom_nav_bar.dart';

class RentalBuyoutConfirmationPage extends StatefulWidget {
  final Map<String, dynamic> rental;
  final String email;
  final String? name;

  const RentalBuyoutConfirmationPage({
    super.key,
    required this.rental,
    required this.email,
    this.name,
  });

  @override
  State<RentalBuyoutConfirmationPage> createState() => _RentalBuyoutConfirmationPageState();
}

class _RentalBuyoutConfirmationPageState extends State<RentalBuyoutConfirmationPage> {
  static const Color _blue = Color(0xFF0C5AD2);
  static const Color _ink = Color(0xFF10233F);
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final NumberFormat _money = NumberFormat('#,##0.00');
  Map<String, dynamic> _quote = {};
  String _productID = '';
  String _title = 'Rental Device';
  String _imageUrl = '';
  String _serial = '';
  String _storage = '';
  String _color = '';
  String _rentalID = '';
  String? _error;
  AddressModel? _address;
  SelectedPaymentMethod? _selectedPayment;
  bool _loading = true;
  bool _loadingPayment = true;
  bool _processing = false;

  double _number(dynamic value) => value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0;

  @override
  void initState() {
    super.initState();
    _rentalID = widget.rental['rentalID']?.toString() ?? '';
    _load();
  }

  Future<void> _load() async {
    await Future.wait([_loadQuote(), _loadPaymentMethod(), _loadAddress()]);
  }

  Future<void> _loadQuote() async {
    try {
      final uri = Uri.parse('${AuthService.baseUrl}/api/rental/buyout-quote/${Uri.encodeComponent(_rentalID)}')
          .replace(queryParameters: {'email': widget.email});
      final response = await http.get(uri).timeout(const Duration(seconds: 20));
      final data = jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300 || data is! Map || data['success'] != true) {
        throw Exception(data is Map ? data['error']?.toString() ?? 'Unable to load the buyout amount.' : 'Invalid server response.');
      }
      if (!mounted) return;
      final quoteData = data['quote'];
      setState(() {
        _quote = quoteData is Map ? Map<String, dynamic>.from(quoteData) : <String, dynamic>{};
        _productID = data['productID']?.toString() ?? '';
        _title = data['productTitle']?.toString() ?? _title;
        _imageUrl = data['imageUrl']?.toString() ?? '';
        _serial = data['serialNumber']?.toString() ?? '';
        _storage = data['storage']?.toString() ?? '';
        _color = data['color']?.toString() ?? '';
        _loading = false;
      });
    } catch (error) {
      if (mounted) setState(() { _error = error.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _loadPaymentMethod() async {
    try {
      final rawCards = await XenditService.fetchSavedCards(widget.email);
      if (rawCards.isNotEmpty) {
        final cards = rawCards.map((entry) => PaymentAccountModel.fromJson(entry)).toList();
        final card = cards.firstWhere((item) => item.isDefault, orElse: () => cards.first);
        _selectedPayment = SelectedPaymentMethod(
          id: card.id,
          type: 'card',
          title: card.cardNumber,
          subtitle: 'Exp: ${card.expiryDate}',
          iconType: 'card',
          rawData: card.toJson(),
        );
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingPayment = false);
  }

  Future<void> _loadAddress() async {
    final addresses = await AddressService.getAddresses(widget.email);
    if (!mounted || addresses.isEmpty) return;
    final rentalAddressID = widget.rental['addressID']?.toString();
    setState(() => _address = addresses.firstWhere(
      (address) => address.addressID == rentalAddressID,
      orElse: () => addresses.firstWhere((address) => address.isDefault, orElse: () => addresses.first),
    ));
  }

  Future<void> _changeAddress() async {
    final selected = await Navigator.push<AddressModel>(context, MaterialPageRoute(
      builder: (_) => SelectAddressPage(email: widget.email, currentlySelected: _address),
    ));
    if (selected != null && mounted) setState(() => _address = selected);
  }

  Future<void> _changePaymentMethod() async {
    final selected = await Navigator.push<SelectedPaymentMethod>(context, MaterialPageRoute(
      builder: (_) => SelectPaymentMethodPage(email: widget.email, currentlySelected: _selectedPayment),
    ));
    if (selected != null && mounted) setState(() => _selectedPayment = selected);
  }

  Future<void> _confirmBuyout() async {
    if (_processing || _loading || _selectedPayment == null) return;
    final total = _number(_quote['totalDue']);
    setState(() => _processing = true);
    try {
      var invoiceID = '';
      if (total > 0) {
        final invoice = await XenditService.createInvoice(
          email: widget.email,
          amount: total,
          description: 'Rental buyout for $_rentalID: $_title',
          paymentMethodType: _selectedPayment!.type,
          productIDs: [_productID.isNotEmpty ? _productID : _rentalID],
        );
        if (invoice['success'] != true || invoice['invoiceUrl'] == null) {
          throw Exception(invoice['error']?.toString() ?? 'Could not start Xendit payment.');
        }
        invoiceID = invoice['invoiceId']?.toString() ?? '';
        final result = await XenditService.launchPaymentWebView(
          context: context,
          invoiceUrl: invoice['invoiceUrl'].toString(),
          title: 'Xendit Secure Pay',
          invoiceId: invoiceID,
          cardData: {'email': widget.email, ...?_selectedPayment!.rawData},
        );
        var status = result['status']?.toString() ?? 'cancelled';
        if (status == 'cancelled' && invoiceID.isNotEmpty) {
          try {
            final invoiceStatus = await XenditService.getInvoiceStatus(invoiceID);
            if (['PAID', 'SETTLED', 'COMPLETED'].contains(invoiceStatus['status']?.toString().toUpperCase())) status = 'success';
          } catch (_) {}
        }
        if (status != 'success') {
          if (mounted) setState(() => _processing = false);
          _showToast(status == 'failed' ? result['errorMessage']?.toString() ?? 'Payment failed.' : 'Payment cancelled.');
          return;
        }
      }

      final response = await http.post(
        Uri.parse('${AuthService.baseUrl}/api/rental/complete-buyout'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'rentalID': _rentalID,
          'invoiceID': invoiceID,
          'email': widget.email,
          'paymentAccountID': _selectedPayment!.id,
          'addressID': _address?.addressID ?? '',
        }),
      ).timeout(const Duration(seconds: 30));
      final data = jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300 || data is! Map || data['success'] != true) {
        throw Exception(data is Map ? data['error']?.toString() ?? 'Could not complete the buyout.' : 'Invalid server response.');
      }
      if (!mounted) return;
      setState(() => _processing = false);
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PaymentSuccessPage(
        orderNumber: data['transactionID']?.toString() ?? invoiceID,
        amountPaid: total,
        email: widget.email,
        name: widget.name,
        paymentTitle: _selectedPayment!.title,
        paidAt: DateTime.now(),
        isRental: true,
        deliveryAddress: _address,
        items: [CartItemModel(
          productID: _productID.isNotEmpty ? _productID : _rentalID,
          listingTitle: _title,
          description: 'Rental device buyout',
          sellingPrice: total,
          imageUrl: _imageUrl,
          storage: _storage,
          color: _color,
        )],
      )));
    } catch (error) {
      if (mounted) setState(() => _processing = false);
      _showToast(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  String _rm(dynamic value) => 'RM ${_money.format(_number(value))}';

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
  }

  Widget _card({required String title, required IconData icon, required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: [
      BoxShadow(color: Colors.black.withValues(alpha: .045), blurRadius: 16, offset: const Offset(0, 5)),
    ]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon, color: _blue), const SizedBox(width: 9), Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: _ink))]),
      const SizedBox(height: 14), child,
    ]),
  );

  Widget _summaryRow(String title, String value, {Color? valueColor, bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Text(title, style: TextStyle(color: bold ? _ink : const Color(0xFF475569), fontWeight: bold ? FontWeight.bold : FontWeight.w500))),
      const SizedBox(width: 12),
      Text(value, style: TextStyle(color: valueColor ?? _ink, fontWeight: FontWeight.bold)),
    ]),
  );

  Widget _deviceCard() => _card(title: 'Device', icon: Icons.phone_iphone, child: Row(children: [
    Container(width: 78, height: 78, padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12)),
      child: _imageUrl.isEmpty ? const Icon(Icons.phone_iphone, size: 38, color: Color(0xFF94A3B8)) : Image.network(_imageUrl, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.phone_iphone, size: 38, color: Color(0xFF94A3B8)))),
    const SizedBox(width: 14),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(_title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _ink)),
      if (_serial.isNotEmpty) Text('Serial: $_serial', style: const TextStyle(color: Color(0xFF475569))),
      if (_storage.isNotEmpty || _color.isNotEmpty) Text([_storage, _color].where((item) => item.isNotEmpty).join(' • '), style: const TextStyle(color: Color(0xFF64748B))),
      const SizedBox(height: 4), Text('Rental ID: $_rentalID', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
    ])),
  ]));

  @override
  Widget build(BuildContext context) {
    final total = _number(_quote['totalDue']);
    final discountRate = _number(_quote['discountRate']);
    final discountPercent = (discountRate * 100).round();
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF3F5F9),
      appBar: ReByteAppBar(scaffoldKey: _scaffoldKey),
      drawer: ReByteDrawer(isLoggedIn: true, email: widget.email, name: widget.name, isRentalsSelected: true),
      bottomNavigationBar: const ReByteBottomNavBar(selectedIndex: 3),
      body: SafeArea(child: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 38), const SizedBox(height: 12), Text(_error!, textAlign: TextAlign.center),
              TextButton(onPressed: () { setState(() { _loading = true; _error = null; }); _loadQuote(); }, child: const Text('Try again')),
            ])))
          : Column(children: [
              Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: Row(children: [
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back, color: _ink)),
                const Expanded(child: Text('Buyout Confirmation', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: _ink))),
              ])),
              Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(18, 2, 18, 20), children: [
                const Text('Review your final buyout price to own this device.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF596273), fontSize: 14)),
                const SizedBox(height: 16),
                _deviceCard(),
                const SizedBox(height: 14),
                _card(title: 'Delivery Address', icon: Icons.local_shipping_outlined, child: InkWell(onTap: _processing ? null : _changeAddress, child: Row(children: [
                  Expanded(child: _address == null
                    ? const Text('Select a delivery address', style: TextStyle(color: Color(0xFF64748B)))
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_address!.recipientName, style: const TextStyle(fontWeight: FontWeight.bold, color: _ink)),
                        Text('${_address!.addressLine}, ${_address!.postcode} ${_address!.city}, ${_address!.state}', style: const TextStyle(color: Color(0xFF596273))),
                      ])),
                  Text(_address == null ? 'Select' : 'Change', style: const TextStyle(color: _blue, fontWeight: FontWeight.bold)),
                ]))),
                const SizedBox(height: 14),
                _card(title: 'Payment Method', icon: Icons.credit_card_outlined, child: InkWell(onTap: _loadingPayment || _processing ? null : _changePaymentMethod, child: Row(children: [
                  const Icon(Icons.payment, color: _blue), const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_loadingPayment
                        ? 'Loading payment methods…'
                        : (_selectedPayment?.title ?? 'Select a payment method'),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: _ink)),
                    if (_selectedPayment != null) Text(_selectedPayment!.subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                  ])),
                  Text(_selectedPayment == null ? 'Select' : 'Change', style: const TextStyle(color: _blue, fontWeight: FontWeight.bold)),
                ]))),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF8F0),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFB9E6CC)),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFF167A45).withValues(alpha: 0.10), blurRadius: 12, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Row(children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: const BoxDecoration(color: Color(0xFFD3F1DF), shape: BoxShape.circle),
                      child: const Icon(Icons.payments_outlined, color: Color(0xFF16834A), size: 21),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(child: Text('Total rental spend', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF276345)))),
                    Text(_rm(_quote['rentalFeePaid']), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF16834A))),
                  ]),
                ),
                const SizedBox(height: 14),
                _card(title: 'Payment Summary', icon: Icons.receipt_long_outlined, child: Column(children: [
                  _summaryRow('Current value', _rm(_quote['currentValue'])),
                  _summaryRow('Rental payment discount ($discountPercent%)', '-${_rm(_quote['rentalDiscount'])}', valueColor: const Color(0xFF16A765)),
                  _summaryRow('Deposit deduction', '-${_rm(_quote['depositDeduction'])}', valueColor: const Color(0xFF16A765)),
                  const Divider(height: 22),
                  _summaryRow('Total', _rm(total), valueColor: _blue, bold: true),
                ])),
                const SizedBox(height: 16),
                Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(14)), child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.info_outline, color: _blue), SizedBox(width: 10), Expanded(child: Text('After successful payment, recurring rental billing will stop and ownership of this device will transfer to you.', style: TextStyle(color: Color(0xFF475569), height: 1.35))),
                ])),
                const SizedBox(height: 16),
                SizedBox(height: 52, child: ElevatedButton.icon(
                  onPressed: _processing || _loadingPayment || _selectedPayment == null ? null : _confirmBuyout,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0645A0), disabledBackgroundColor: const Color(0xFFCBD5E1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))),
                  icon: _processing ? const SizedBox(width: 19, height: 19, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.lock_outline, color: Colors.white),
                  label: Text(_processing ? 'Processing…' : total <= 0 ? 'Confirm Buyout' : 'Confirm & Pay ${_rm(total)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                )),
              ])),
            ])),
    );
  }
}
