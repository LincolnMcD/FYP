import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/xendit_service.dart';

class AddPaymentAccountDialog {
  static void show({
    required BuildContext context,
    required String email,
    required bool hasExistingCards,
    required VoidCallback onCardAdded,
  }) {
    final cardController = TextEditingController();
    final expiryController = TextEditingController();
    final cvnController = TextEditingController();
    bool isDefault = !hasExistingCards;
    bool isSubmitting = false;

    String? cardError;
    String? expiryError;
    String? cvnError;

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
                              onPressed: () => Navigator.pop(sheetContext),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Card Number
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

                        // Expiry + CVV
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
                                      _CardExpiryDateInputFormatter(),
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
                          onChanged: !hasExistingCards
                              ? null
                              : (val) => setModalState(() => isDefault = val ?? false),
                          title: const Text(
                            'Set as default payment account',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                          ),
                          subtitle: !hasExistingCards
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
                            onPressed: isSubmitting
                                ? null
                                : () async {
                                    setModalState(() {
                                      validateCard(cardController.text);
                                      validateExpiry(expiryController.text);
                                      validateCvv(cvnController.text);
                                    });

                                    if (cardError != null || expiryError != null || cvnError != null) {
                                      return;
                                    }

                                    final num = cardController.text.replaceAll(' ', '').trim();
                                    final exp = expiryController.text.trim();
                                    final cvn = cvnController.text.trim();

                                    setModalState(() => isSubmitting = true);

                                    final isDuplicateOnServer = await XenditService.checkCardDuplicate(email, num);
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

                                    final tokenResult = await XenditService.tokenizeCard(
                                      context: context,
                                      cardNumber: num,
                                      expMonth: expMonth.padLeft(2, '0'),
                                      expYear: fullYear.toString(),
                                      cvn: cvn,
                                      cardholderName: '',
                                      email: email,
                                    );

                                    if (!tokenResult.success || tokenResult.tokenId == null) {
                                      setModalState(() {
                                        isSubmitting = false;
                                        cardError = tokenResult.errorMessage ?? 'Authentication failed';
                                      });
                                      return;
                                    }

                                    final xenditBrand = tokenResult.cardBrand;
                                    final localBrand = identifyBrand(num);
                                    final brand = (xenditBrand != null && xenditBrand.isNotEmpty)
                                        ? xenditBrand
                                        : ((localBrand != null && localBrand != 'UNSUPPORTED') ? localBrand : 'Visa');

                                    final saveRes = await XenditService.saveCardToBackend(
                                      email: email,
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
                                        cardError = saveRes['error']?.toString() ?? 'Failed to save account';
                                      });
                                      return;
                                    }

                                    if (sheetContext.mounted) {
                                      Navigator.pop(sheetContext);
                                    }

                                    onCardAdded();
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
}

class _CardExpiryDateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var text = newValue.text;
    if (text.isEmpty) return newValue;

    text = text.replaceAll('/', '');
    if (text.length > 4) text = text.substring(0, 4);

    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      if (i == 1 && text.length > 2) {
        buffer.write('/');
      }
    }

    final string = buffer.toString();
    return newValue.copyWith(
      text: string,
      selection: TextSelection.collapsed(offset: string.length),
    );
  }
}
