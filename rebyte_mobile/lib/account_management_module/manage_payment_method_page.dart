import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/rebyte_app_bar.dart';
import '../widgets/rebyte_bottom_nav_bar.dart';
import 'models/payment_account_model.dart';
import 'services/xendit_service.dart';
import 'services/session_service.dart';

class ManagePaymentMethodPage extends StatefulWidget {
  final String email;

  const ManagePaymentMethodPage({super.key, required this.email});

  @override
  State<ManagePaymentMethodPage> createState() => _ManagePaymentMethodPageState();
}

class _ManagePaymentMethodPageState extends State<ManagePaymentMethodPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  List<PaymentAccountModel> _payments = [];
  bool _isLoading = true;
  String? _toastMessage;
  bool _isToastError = false;
  String? _userName;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _loadPayments();
  }

  Future<void> _loadUserInfo() async {
    try {
      final session = await SessionService.getSession();
      if (mounted && session.isNotEmpty) {
        setState(() {
          _userName = session['name'];
        });
      }
    } catch (_) {}
  }

  Future<void> _loadPayments() async {
    setState(() => _isLoading = true);
    
    // Fetch directly from backend paymentAccount table
    List<PaymentAccountModel> list = [];
    try {
      final backendMethods = await XenditService.fetchSavedCards(widget.email);
      if (backendMethods.isNotEmpty) {
        list = backendMethods.map((m) => PaymentAccountModel.fromJson(m)).toList();
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _payments = list;
        _isLoading = false;
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

  Future<void> _handleSetDefault(PaymentAccountModel payment) async {
    final success = await XenditService.setDefaultCard(widget.email, payment.id);
    if (success) {
      _showTopToast('Default payment account updated.');
    } else {
      _showTopToast('Failed to update default card.', isError: true);
    }
    await _loadPayments();
  }

  Future<void> _handleDelete(PaymentAccountModel payment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Payment Account',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF0F254B)),
        ),
        content: Text(
          'Are you sure you want to remove card ending in ${payment.cardNumber.length >= 4 ? payment.cardNumber.substring(payment.cardNumber.length - 4) : payment.cardNumber}?',
          style: const TextStyle(fontSize: 13.5, color: Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE11D48),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await XenditService.deleteCard(widget.email, payment.id);
      if (success) {
        _showTopToast('Payment account removed.');
      } else {
        _showTopToast('Failed to delete payment account.', isError: true);
      }
      await _loadPayments();
    }
  }

  void _openAddPaymentDialog() {
    final cardController = TextEditingController();
    final expiryController = TextEditingController();
    final cvnController = TextEditingController();
    bool isDefault = _payments.isEmpty;
    bool isSubmitting = false;

    String? cardError;
    String? expiryError;
    String? cvnError;

    // Helper: Identify Card Provider / Brand (Only Visa and Mastercard supported in Malaysia)
    // Returns 'Visa', 'Mastercard', 'UNSUPPORTED' if unsupported, or null if too short
    String? identifyBrand(String cardNumber) {
      final clean = cardNumber.replaceAll(' ', '').trim();
      if (clean.isEmpty) return null;
      if (clean.startsWith('4')) {
        return 'Visa';
      }
      final int2 = clean.length >= 2 ? int.tryParse(clean.substring(0, 2)) ?? 0 : 0;
      final int4 = clean.length >= 4 ? int.tryParse(clean.substring(0, 4)) ?? 0 : 0;
      if ((int2 >= 51 && int2 <= 55) || (int4 >= 2221 && int4 <= 2720)) {
        return 'Mastercard';
      }
      // If starts with any other prefix (Amex 34/37, JCB 35, Discover, UnionPay, etc.)
      return 'UNSUPPORTED';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            final currentBrand = identifyBrand(cardController.text);

            void validateCard(String value) {
              final clean = value.replaceAll(' ', '').trim();
              if (clean.isEmpty) {
                cardError = 'Card number is required';
              } else if (clean.length < 16) {
                cardError = 'Card number must be 16 digits';
              } else if (clean.length > 16) {
                cardError = 'Card number cannot exceed 16 digits';
              } else if (int.tryParse(clean) == null) {
                cardError = 'Must contain digits only';
              } else if (identifyBrand(clean) == 'UNSUPPORTED') {
                cardError = 'Only Visa and Mastercard are supported';
              } else {
                cardError = null;
              }
            }

            void validateExpiry(String value) {
              final exp = value.trim();
              if (exp.isEmpty) {
                expiryError = 'Required';
              } else if (exp.length < 5 || !exp.contains('/') || exp.split('/').length != 2) {
                expiryError = 'Use MM/YY';
              } else {
                final parts = exp.split('/');
                final m = int.tryParse(parts[0].trim());
                final yRaw = int.tryParse(parts[1].trim());

                if (m == null || m < 1 || m > 12) {
                  expiryError = 'MM: 01 to 12';
                } else if (yRaw == null || parts[1].trim().length != 2) {
                  expiryError = 'YY must be 2 digits';
                } else {
                  final fullYear = 2000 + yRaw;
                  final now = DateTime.now();
                  if (fullYear < now.year) {
                    expiryError = 'Expired year';
                  } else if (fullYear == now.year && m < now.month) {
                    expiryError = 'Expired month';
                  } else {
                    expiryError = null;
                  }
                }
              }
            }

            void validateCvv(String value) {
              final clean = value.trim();
              if (clean.isEmpty) {
                cvnError = 'Required';
              } else if (clean.length != 3 || int.tryParse(clean) == null) {
                cvnError = 'Must be 3 digits';
              } else {
                cvnError = null;
              }
            }

            return SafeArea(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => FocusScope.of(context).unfocus(),
                child: Container(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                    left: 20,
                    right: 20,
                    top: 20,
                  ),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Add Payment Account',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F254B),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Color(0xFF64748B)),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Card Number (with Auto-detected Brand icon/badge)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Card Number', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                            if (currentBrand != null && currentBrand != 'UNSUPPORTED')
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEEF2FF),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  currentBrand,
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF0C5AD2)),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: cardController,
                          keyboardType: TextInputType.number,
                          maxLength: 16,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(16),
                          ],
                          onChanged: (val) {
                            setModalState(() {
                              validateCard(val);
                            });
                          },
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: '1234 5678 9012 3456',
                            hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 14),
                            errorText: cardError,
                            errorStyle: const TextStyle(fontSize: 11, color: Color(0xFFEF4444)),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            prefixIcon: const Icon(Icons.credit_card, color: Color(0xFF0C5AD2)),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                            errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFEF4444))),
                            focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Row 1: Expiry + CVV (50/50 clean split)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Expires (MM/YY)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: expiryController,
                                    keyboardType: TextInputType.number,
                                    maxLength: 5,
                                    inputFormatters: [
                                      _ExpiryDateInputFormatter(),
                                    ],
                                    onChanged: (val) {
                                      setModalState(() {
                                        validateExpiry(val);
                                      });
                                    },
                                    decoration: InputDecoration(
                                      counterText: '',
                                      hintText: 'MM/YY',
                                      hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 14),
                                      errorText: expiryError,
                                      errorStyle: const TextStyle(fontSize: 11, color: Color(0xFFEF4444)),
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFEF4444))),
                                      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('CVV', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: cvnController,
                                    keyboardType: TextInputType.number,
                                    obscureText: false,
                                    maxLength: 3,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(3),
                                    ],
                                    onChanged: (val) {
                                      setModalState(() {
                                        validateCvv(val);
                                      });
                                    },
                                    decoration: InputDecoration(
                                      counterText: '',
                                      hintText: '123',
                                      hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 14),
                                      errorText: cvnError,
                                      errorStyle: const TextStyle(fontSize: 11, color: Color(0xFFEF4444)),
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFEF4444))),
                                      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                    // Set default checkbox
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: isDefault,
                      onChanged: _payments.isEmpty
                          ? null // First card cannot be unticked
                          : (val) => setModalState(() => isDefault = val ?? false),
                      title: const Text(
                        'Set as default payment account',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                      ),
                      subtitle: _payments.isEmpty
                          ? const Text(
                              'The first payment account is automatically set as default.',
                              style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                            )
                          : null,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    const SizedBox(height: 16),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: isSubmitting ? null : () async {
                          setModalState(() {
                            validateCard(cardController.text);
                            validateExpiry(expiryController.text);
                            validateCvv(cvnController.text);
                          });

                          // If any field is invalid, STOP and keep modal open showing errors under inputs
                          if (cardError != null || expiryError != null || cvnError != null) {
                            return;
                          }

                          final num = cardController.text.replaceAll(' ', '').trim();
                          final exp = expiryController.text.trim();
                          final cvn = cvnController.text.trim();

                          // Client-side Duplicate Check against existing loaded payments
                          final isDuplicateLocally = _payments.any((p) {
                            final last4 = num.length >= 4 ? num.substring(num.length - 4) : num;
                            return p.cardNumber.endsWith(last4);
                          });

                          if (isDuplicateLocally) {
                            setModalState(() {
                              cardError = 'This card is already added to your account.';
                            });
                            return;
                          }

                          setModalState(() => isSubmitting = true);

                          // Pre-check duplicate against backend database before triggering 3DS OTP modal
                          final isDuplicateOnServer = await XenditService.checkCardDuplicate(widget.email, num);
                          if (isDuplicateOnServer) {
                            setModalState(() {
                              isSubmitting = false;
                              cardError = 'This card is already added to your account.';
                            });
                            return;
                          }

                          final expParts = exp.split('/');
                          final expMonth = expParts[0].trim();
                          final expYear = expParts[1].trim();
                          final int? yearRaw = int.tryParse(expYear);
                          final int fullYear = expYear.length == 2 ? 2000 + (yearRaw ?? 0) : (yearRaw ?? 0);
                          if (!context.mounted) return;

                          // Pass to Xendit to perform gateway-side validation (Luhn check, Brand support, etc.)
                          final tokenResult = await XenditService.tokenizeCard(
                            context: context,
                            cardNumber: num,
                            expMonth: expMonth.padLeft(2, '0'),
                            expYear: fullYear.toString(),
                            cvn: cvn,
                            cardholderName: '',
                            email: widget.email,
                          );

                          // If Xendit detects an error (invalid checksum or unsupported brand), keep popup open and show error under input
                          if (!tokenResult.success || tokenResult.tokenId == null) {
                            setModalState(() {
                              isSubmitting = false;
                              final err = tokenResult.errorMessage ?? 'Authentication failed';
                              cardError = err;
                            });
                            return;
                          }

                          // Ask Xendit for the card brand first.
                          // Fall back to local prefix identification only if Xendit didn't return one.
                          final xenditBrand = tokenResult.cardBrand;
                          final localBrand = identifyBrand(num);
                          final brand = (xenditBrand != null && xenditBrand.isNotEmpty)
                              ? xenditBrand
                              : ((localBrand != null && localBrand != 'UNSUPPORTED') ? localBrand : 'Visa');

                          // Step 2: Save to Firestore table: paymentAccount
                          final saveRes = await XenditService.saveCardToBackend(
                            email: widget.email,
                            tokenId: tokenResult.tokenId!,
                            paymentAccountNo: num,
                            cardNumber: num,
                            expiryDate: '${expMonth.padLeft(2, '0')}/${expYear.length == 4 ? expYear.substring(2) : expYear}',
                            cvv: cvn,
                            providerName: brand,
                            isDefault: isDefault,
                          );

                          if (saveRes['success'] != true) {
                            setModalState(() {
                              isSubmitting = false;
                              final err = saveRes['error']?.toString() ?? 'Failed to save account';
                              cardError = err;
                            });
                            return;
                          }

                          // Success! Now close popup and refresh list
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext);
                          }

                          _showTopToast('Card linked to account successfully!');
                          await _loadPayments();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0C5AD2),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: isSubmitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Text('Save & Verify with Xendit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        },
      );
    },
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: ReByteAppBar(
        scaffoldKey: _scaffoldKey,
      ),
      drawer: ReByteDrawer(
        isLoggedIn: true,
        email: widget.email,
        name: _userName,
        selectedIndex: -1,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Back Arrow
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A), size: 22),
                          onPressed: () => Navigator.pop(context),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(height: 14),

                        // Title Bar with + Button
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Manage Payment Account',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F254B),
                                letterSpacing: -0.3,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add, size: 26, color: Color(0xFF0F254B)),
                              onPressed: _openAddPaymentDialog,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Payment Cards List
                        if (_isLoading)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(40.0),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else ...[
                          ..._payments.map((pay) => _buildPaymentCard(pay)),
                          const SizedBox(height: 6),
                          _buildAddPaymentCard(),
                          const SizedBox(height: 28),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Top Floating Toast Banner
            if (_toastMessage != null)
              Positioned(
                top: 12,
                left: 16,
                right: 16,
                child: Dismissible(
                  key: UniqueKey(),
                  direction: DismissDirection.horizontal,
                  onDismissed: (_) => setState(() => _toastMessage = null),
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                            size: 24,
                          ),
                          const SizedBox(width: 12),
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
              ),
          ],
        ),
      ),
      bottomNavigationBar: const ReByteBottomNavBar(
        selectedIndex: -1,
      ),
    );
  }

  Widget _buildCardBrandLogo(String brand) {
    final b = brand.toLowerCase();
    if (b.contains('visa')) {
      return Container(
        width: 52,
        height: 34,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1F71), // Visa navy blue
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: const Text(
          'VISA',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 14,
            letterSpacing: 1.2,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    } else if (b.contains('master') || b.contains('mc')) {
      return Container(
        width: 52,
        height: 34,
        decoration: BoxDecoration(
          color: const Color(0xFF222222),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: SizedBox(
          width: 32,
          height: 20,
          child: Stack(
            children: [
              Positioned(
                left: 2,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 20,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEB001B), // Mastercard red
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Positioned(
                right: 2,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 20,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF79E1B).withValues(alpha: 0.92), // Mastercard orange
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Fallback card icon
    return Container(
      width: 52,
      height: 34,
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(
        Icons.credit_card_rounded,
        size: 22,
        color: Color(0xFF0C5AD2),
      ),
    );
  }

  Widget _buildPaymentCard(PaymentAccountModel pay) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF0C5AD2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row with Card Brand Logo + Number + Expiry + Default badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Card Brand Logo Container
              _buildCardBrandLogo(pay.cardType),
              const SizedBox(width: 14),

              // Card details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pay.cardNumber.contains('*')
                          ? pay.cardNumber
                          : (pay.cardNumber.length >= 4
                              ? '**** **** **** ${pay.cardNumber.substring(pay.cardNumber.length - 4)}'
                              : pay.cardNumber),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Expires ${pay.expiryDate}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // Default Badge
              if (pay.isDefault)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0C5AD2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline, size: 13, color: Colors.white),
                      SizedBox(width: 4),
                      Text(
                        'Default',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),

          // Bottom Action: Trash / Set Default
          if (pay.isDefault)
            // Full width trash button when default
            SizedBox(
              width: double.infinity,
              height: 40,
              child: OutlinedButton(
                onPressed: () => _handleDelete(pay),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFE11D48),
                  size: 20,
                ),
              ),
            )
          else
            // Split buttons: Set Default (Light blue) + Trash
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: ElevatedButton(
                      onPressed: () => _handleSetDefault(pay),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEEF2FF),
                        foregroundColor: const Color(0xFF0C5AD2),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text(
                        'Set Default',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0C5AD2),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 54,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFE11D48), size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _handleDelete(pay),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildAddPaymentCard() {
    return InkWell(
      onTap: _openAddPaymentDialog,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFCBD5E1),
            width: 1.2,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: Color(0xFFEEF2FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.credit_card_rounded,
                size: 28,
                color: Color(0xFF0C5AD2),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Add New Payment Account',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F254B),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Save another payment account to your account.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: Color(0xFF64748B),
                height: 1.3,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Automatically inserts '/' after the 2-digit month without breaking backspace or cursor position
class _ExpiryDateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final oldText = oldValue.text;
    final newText = newValue.text;

    // If user is deleting and just hit the slash, delete the character before the slash too
    if (oldText.length > newText.length && oldText.endsWith('/') && !newText.contains('/')) {
      final stripped = newText.replaceAll(RegExp(r'\D'), '');
      if (stripped.isNotEmpty) {
        final cut = stripped.substring(0, stripped.length - 1);
        return TextEditingValue(
          text: cut,
          selection: TextSelection.collapsed(offset: cut.length),
        );
      }
    }

    final digits = newText.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(text: '');
    }

    final buffer = StringBuffer();
    int selectionIndex = newValue.selection.end;
    int digitsBeforeCursor = 0;

    for (int i = 0; i < selectionIndex && i < newText.length; i++) {
      if (RegExp(r'\d').hasMatch(newText[i])) {
        digitsBeforeCursor++;
      }
    }

    for (int i = 0; i < digits.length && i < 4; i++) {
      if (i == 2) {
        buffer.write('/');
      }
      buffer.write(digits[i]);
    }

    final formatted = buffer.toString();
    int newCursorPos = 0;
    int count = 0;

    for (int i = 0; i < formatted.length; i++) {
      if (count == digitsBeforeCursor) {
        newCursorPos = i;
        break;
      }
      if (RegExp(r'\d').hasMatch(formatted[i])) {
        count++;
      }
      newCursorPos = i + 1;
    }

    // Auto-advance cursor past slash if user just typed the 2nd month digit
    if (formatted.length == 3 && formatted.endsWith('/') && newCursorPos == 2) {
      newCursorPos = 3;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newCursorPos.clamp(0, formatted.length)),
    );
  }
}

