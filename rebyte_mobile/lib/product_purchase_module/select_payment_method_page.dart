import 'package:flutter/material.dart';
import '../account_management_module/models/payment_account_model.dart';
import '../account_management_module/services/xendit_service.dart';
import '../account_management_module/widgets/add_payment_account_dialog.dart';
import 'models/selected_payment_method.dart';

class SelectPaymentMethodPage extends StatefulWidget {
  final String email;
  final SelectedPaymentMethod? currentlySelected;
  final bool cardsOnlyMode;

  const SelectPaymentMethodPage({
    super.key,
    required this.email,
    this.currentlySelected,
    this.cardsOnlyMode = false,
  });

  @override
  State<SelectPaymentMethodPage> createState() => _SelectPaymentMethodPageState();
}

class _SelectPaymentMethodPageState extends State<SelectPaymentMethodPage> {
  List<PaymentAccountModel> _savedCards = [];
  bool _isLoading = true;
  String? _selectedMethodId;
  String? _toastMessage;
  bool _isToastError = false;

  // Single E-Wallet option - Xendit handles provider selection (Touch 'n Go, GrabPay, ShopeePay)
  final Map<String, String> _ewalletMethod = {
    'id': 'ewallet_all',
    'title': 'E-Wallet',
    'type': 'ewallet',
    'icon': 'ewallet',
    'subtitle': 'Touch \'n Go, GrabPay, ShopeePay via Xendit',
  };

  // Single FPX payment method - Xendit handles bank selection and amount transfer
  final Map<String, String> _fpxMethod = {
    'id': 'fpx_online_banking',
    'title': 'Online Banking (FPX)',
    'type': 'fpx',
    'icon': 'fpx',
    'subtitle': 'Direct bank transfer via Xendit',
    'code': 'FPX',
  };

  @override
  void initState() {
    super.initState();
    _selectedMethodId = widget.currentlySelected?.id;
    _loadSavedCards();
  }

  Future<void> _loadSavedCards() async {
    setState(() => _isLoading = true);
    List<PaymentAccountModel> cards = [];
    try {
      final backendMethods = await XenditService.fetchSavedCards(widget.email);
      if (backendMethods.isNotEmpty) {
        cards = backendMethods.map((m) => PaymentAccountModel.fromJson(m)).toList();
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _savedCards = cards;
        _isLoading = false;
        // If nothing selected initially, default to default card or first saved card
        if (_selectedMethodId == null && _savedCards.isNotEmpty) {
          final defaultCard = _savedCards.firstWhere((c) => c.isDefault, orElse: () => _savedCards.first);
          _selectedMethodId = defaultCard.id;
        }
      });
    }
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

  void _selectMethod(SelectedPaymentMethod method) {
    setState(() {
      _selectedMethodId = method.id;
    });
    // Return back to checkout page with selected payment method
    Navigator.pop(context, method);
  }

  void _openAddPaymentDialog() {
    AddPaymentAccountDialog.show(
      context: context,
      email: widget.email,
      hasExistingCards: _savedCards.isNotEmpty,
      onCardAdded: () async {
        _showTopToast('Card linked to account successfully!');
        await _loadSavedCards();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A), size: 22),
          onPressed: () => Navigator.pop(context),
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
            SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Payment Method',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F254B),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 20),

                // SAVED CARDS SECTION
                _buildSectionTitle('SAVED CARDS'),
                const SizedBox(height: 10),
                if (_isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: CircularProgressIndicator(color: Color(0xFF0C5AD2), strokeWidth: 2.5),
                    ),
                  )
                else if (_savedCards.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: const Text(
                      'No saved cards found. Tap below to link a card.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                    ),
                  )
                else if (_savedCards.length <= 3)
                  ..._savedCards.map((card) => _buildSavedCardItem(card))
                else
                  // Max showing 3 cards in view, scrollable to other cards
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: 255, // Height of 3 card items (including margins)
                    ),
                    child: Scrollbar(
                      thumbVisibility: true,
                      radius: const Radius.circular(8),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _savedCards.length,
                        padding: const EdgeInsets.only(right: 6),
                        itemBuilder: (context, index) {
                          return _buildSavedCardItem(_savedCards[index]);
                        },
                      ),
                    ),
                  ),

                if (!widget.cardsOnlyMode) ...[
                  const SizedBox(height: 24),

                  // E-WALLETS SECTION
                  _buildSectionTitle('E-WALLETS'),
                  const SizedBox(height: 10),
                  _buildEWalletItem(),

                  const SizedBox(height: 24),

                  // ONLINE BANKING (FPX) SECTION
                  _buildSectionTitle('ONLINE BANKING (FPX)'),
                  const SizedBox(height: 10),
                  _buildFpxMethodItem(),
                ],

                const SizedBox(height: 20),

                // ADD PAYMENT ACCOUNT BUTTON
                InkWell(
                  onTap: _openAddPaymentDialog,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9).withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFFCBD5E1),
                        width: 1.2,
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.add_circle_outline, size: 20, color: Color(0xFF334155)),
                        SizedBox(width: 8),
                        Text(
                          'Add Payment Account',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF334155),
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

          // Top Floating Toast
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
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: Color(0xFF64748B),
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _buildSavedCardItem(PaymentAccountModel card) {
    final isSelected = _selectedMethodId == card.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFF0F5FF) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? const Color(0xFF0C5AD2) : const Color(0xFFE2E8F0),
          width: isSelected ? 2.0 : 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            _selectMethod(SelectedPaymentMethod(
              id: card.id,
              type: 'card',
              title: card.cardNumber,
              subtitle: 'Exp: ${card.expiryDate}',
              iconType: 'card',
              rawData: card.toJson(),
            ));
          },
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                // Card icon box
                Container(
                  width: 50,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE0E7FF)),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.credit_card, size: 22, color: Color(0xFF0C5AD2)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.cardNumber,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Expires ${card.expiryDate}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? const Color(0xFF0C5AD2) : const Color(0xFF94A3B8),
                      width: isSelected ? 6.5 : 2.0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEWalletItem() {
    final id = _ewalletMethod['id']!;
    final isSelected = _selectedMethodId == id;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFF0F5FF) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? const Color(0xFF0C5AD2) : const Color(0xFFE2E8F0),
          width: isSelected ? 2.0 : 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            _selectMethod(SelectedPaymentMethod(
              id: id,
              type: 'ewallet',
              title: _ewalletMethod['title']!,
              subtitle: 'Touch \'n Go, GrabPay, ShopeePay',
              iconType: 'ewallet',
              rawData: _ewalletMethod,
            ));
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
            child: Row(
              children: [
                _buildCombinedWalletLogo(),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _ewalletMethod['title']!,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Touch \'n Go, GrabPay, ShopeePay via Xendit',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? const Color(0xFF0C5AD2) : const Color(0xFF94A3B8),
                      width: isSelected ? 6.5 : 2.0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCombinedWalletLogo() {
    return Container(
      width: 50,
      height: 38,
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDCFCE7)),
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.account_balance_wallet, size: 22, color: Color(0xFF16A34A)),
    );
  }

  Widget _buildFpxMethodItem() {
    final id = _fpxMethod['id']!;
    final isSelected = _selectedMethodId == id;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFF0F5FF) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? const Color(0xFF0C5AD2) : const Color(0xFFE2E8F0),
          width: isSelected ? 2.0 : 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            _selectMethod(SelectedPaymentMethod(
              id: id,
              type: 'fpx',
              title: _fpxMethod['title']!,
              subtitle: 'Online Banking (FPX)',
              iconType: 'fpx',
              rawData: _fpxMethod,
            ));
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE0E7FF)),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.account_balance, size: 22, color: Color(0xFF0C5AD2)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _fpxMethod['title']!,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Direct bank transfer via Xendit',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? const Color(0xFF0C5AD2) : const Color(0xFF94A3B8),
                      width: isSelected ? 6.5 : 2.0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
