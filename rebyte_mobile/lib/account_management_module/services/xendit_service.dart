import 'dart:collection';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class XenditTokenResult {
  final bool success;
  final String? tokenId;
  final String? maskedCard;
  final String? cardBrand;
  final String? expiry;
  final String? status;
  final String? errorMessage;

  XenditTokenResult({
    required this.success,
    this.tokenId,
    this.maskedCard,
    this.cardBrand,
    this.expiry,
    this.status,
    this.errorMessage,
  });
}

class XenditService {
  // Public Key for client-side card tokenization
  static const String publicKey =
      'xnd_public_development_OEcRYatDYbvtgO9T1OhKvGW1oXOH61WLqPzHDCk9SXHMP50Vvzm4QYIwlrBRF6Uo';

  static String get _tokenEndpoint =>
      'https://api.xendit.co/v2/credit_card_tokens';

  static Map<String, String> get _authHeaders {
    final authBase64 = base64Encode(utf8.encode('$publicKey:'));
    return {
      'Authorization': 'Basic $authBase64',
      'Content-Type': 'application/json',
    };
  }

  /// Tokenizes credit card directly with Xendit PCI-compliant API
  static Future<XenditTokenResult> tokenizeCard({
    required BuildContext context,
    required String cardNumber,
    required String expMonth,
    required String expYear,
    required String cvn,
    required String cardholderName,
    String? email,
  }) async {
    try {
      final cleanCard = cardNumber.replaceAll(' ', '').trim();
      final cleanMonth = expMonth.padLeft(2, '0').trim();
      var cleanYear = expYear.trim();
      if (cleanYear.length == 2) {
        cleanYear = '20$cleanYear';
      }

      // Xendit requires is_single_use: false for multi-use tokens
      // and requires card_holder_first_name, card_holder_last_name, and email/phone
      final holder = cardholderName.trim();
      final firstName = holder.isNotEmpty ? holder.split(' ').first : 'ReByte';
      final lastName = holder.isNotEmpty && holder.contains(' ')
          ? holder.split(' ').sublist(1).join(' ')
          : 'Customer';
      final customerEmail = (email != null && email.contains('@'))
          ? email.trim()
          : 'customer@rebyte.com';

      final payload = {
        'is_single_use': true,
        'should_authenticate': true,
        'amount': 0,
        'currency': 'MYR',
        'card_data': {
          'account_number': cleanCard,
          'exp_month': cleanMonth,
          'exp_year': cleanYear,
          'cvn': cvn.trim(),
          'card_holder_first_name': firstName,
          'card_holder_last_name': lastName,
          'card_holder_email': customerEmail,
        },
      };

      final response = await http.post(
        Uri.parse(_tokenEndpoint),
        headers: _authHeaders,
        body: jsonEncode(payload),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode != 200 && response.statusCode != 201) {
        String errorMsg =
            data['message'] ?? data['error_code'] ?? 'Tokenization failed';
        final errCode = data['error_code']?.toString() ?? '';

        if (errCode == 'BRAND_NOT_SUPPORTED_ERROR' ||
            errorMsg.toLowerCase().contains('brand is not supported') ||
            errorMsg.toLowerCase().contains('card brand')) {
          errorMsg = 'the card is not support by ReByte payment';
        } else if (data['errors'] is List &&
            (data['errors'] as List).isNotEmpty) {
          final firstErr = data['errors'][0];
          if (firstErr is Map && firstErr['message'] != null) {
            final detail = firstErr['message'].toString();
            if (detail.contains('must be a credit card') ||
                detail.toLowerCase().contains('credit card') ||
                detail.toLowerCase().contains('checksum')) {
              errorMsg = 'invalid card number';
            } else {
              errorMsg = detail;
            }
          }
        }
        return XenditTokenResult(success: false, errorMessage: errorMsg);
      }

      final tokenId = data['id']?.toString();
      final status = data['status']?.toString();
      final authUrl = data['payer_authentication_url']?.toString();
      final masked =
          data['masked_card_number']?.toString() ??
          '**** **** **** ${cleanCard.substring(cleanCard.length - 4)}';
      final cardInfo = data['card_info'] as Map<String, dynamic>?;
      final metadata = data['metadata'] as Map<String, dynamic>?;
      final rawBrand =
          cardInfo?['brand']?.toString() ??
          data['card_brand']?.toString() ??
          metadata?['brand']?.toString();

      String? cardBrand;
      if (rawBrand != null &&
          rawBrand.isNotEmpty &&
          rawBrand.toUpperCase() != 'UNKNOWN') {
        final up = rawBrand.toUpperCase();
        if (up == 'MASTERCARD' || up == 'MASTER') {
          cardBrand = 'Mastercard';
        } else if (up == 'VISA') {
          cardBrand = 'Visa';
        } else {
          // Cards from brands other than Visa or Mastercard (e.g. JCB, Amex, Discover) are not supported in Malaysia
          return XenditTokenResult(
            success: false,
            errorMessage: 'Only Visa and Mastercard are supported',
          );
        }
      }
      final expiry = '$cleanMonth/${cleanYear.substring(cleanYear.length - 2)}';

      // If bank 3D-Secure authentication is needed
      if (status == 'IN_REVIEW' || (authUrl != null && authUrl.isNotEmpty)) {
        if (!context.mounted) {
          return XenditTokenResult(
            success: false,
            errorMessage: 'Context not mounted for 3DS verification',
          );
        }

        final bool authPassed = await _show3DSModal(context, authUrl!);
        if (!authPassed) {
          return XenditTokenResult(
            success: false,
            errorMessage: 'Card 3DS verification was cancelled or failed',
          );
        }
      }

      return XenditTokenResult(
        success: true,
        tokenId: tokenId,
        maskedCard: masked,
        cardBrand: cardBrand,
        expiry: expiry,
        status: status,
      );
    } catch (e) {
      return XenditTokenResult(success: false, errorMessage: e.toString());
    }
  }

  /// Displays 3D-Secure webview dialog for OTP authentication
  static Future<bool> _show3DSModal(
    BuildContext context,
    String authUrl,
  ) async {
    bool passed = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.all(12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: double.infinity,
              height: 540,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    color: const Color(0xFF0C5AD2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.lock_outline,
                              color: Colors.white,
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Card Ownership Authentication',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 20,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: InAppWebView(
                      initialUrlRequest: URLRequest(url: WebUri(authUrl)),
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        javaScriptCanOpenWindowsAutomatically: true,
                        useShouldOverrideUrlLoading: true,
                        transparentBackground: false,
                        supportMultipleWindows: true,
                      ),
                      onWebViewCreated: (controller) {
                        controller.addJavaScriptHandler(
                          handlerName: 'on3DSCompleted',
                          callback: (args) {
                            passed = true;
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                            }
                          },
                        );
                      },
                      onLoadStart: (controller, url) {
                        final strUrl = url?.toString().toLowerCase() ?? '';
                        if (strUrl.contains('/return') ||
                            strUrl.contains('/verify') ||
                            strUrl.contains('status=verified') ||
                            strUrl.contains('status=captured') ||
                            strUrl.contains('approved=true') ||
                            strUrl.contains('status=success') ||
                            strUrl.contains('action=success')) {
                          passed = true;
                          Future.delayed(
                            const Duration(milliseconds: 1000),
                            () {
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                          );
                        }
                      },
                      shouldOverrideUrlLoading:
                          (controller, navigationAction) async {
                            final uri =
                                navigationAction.request.url
                                    ?.toString()
                                    .toLowerCase() ??
                                '';
                            if (uri.contains('/return') ||
                                uri.contains('/verify') ||
                                uri.contains('status=verified') ||
                                uri.contains('status=captured') ||
                                uri.contains('approved=true') ||
                                uri.contains('status=success') ||
                                uri.contains('action=success')) {
                              passed = true;
                              Future.delayed(
                                const Duration(milliseconds: 800),
                                () {
                                  if (ctx.mounted) Navigator.pop(ctx);
                                },
                              );
                              return NavigationActionPolicy.ALLOW;
                            }
                            return NavigationActionPolicy.ALLOW;
                          },
                      onLoadStop: (controller, url) async {
                        final strUrl = url?.toString().toLowerCase() ?? '';
                        if (strUrl.contains('/return') ||
                            strUrl.contains('/verify') ||
                            strUrl.contains('status=verified') ||
                            strUrl.contains('status=captured') ||
                            strUrl.contains('approved=true') ||
                            strUrl.contains('status=success') ||
                            strUrl.contains('action=success')) {
                          passed = true;
                          Future.delayed(const Duration(milliseconds: 800), () {
                            if (ctx.mounted) Navigator.pop(ctx);
                          });
                          return;
                        }

                        // Attach cross-frame postMessage listener & DOM text inspector
                        await controller.evaluateJavascript(
                          source: '''
                          (function() {
                            if (window.__3dsBridgeActive) return;
                            window.__3dsBridgeActive = true;

                            function triggerSuccess() {
                              try {
                                if (window.flutter_inappwebview) {
                                  window.flutter_inappwebview.callHandler('on3DSCompleted');
                                }
                              } catch(e) {}
                            }

                            // Capture return/verify postMessages
                            window.addEventListener('message', function(e) {
                              try {
                                var d = e.data;
                                if (d && (d.shouldVerify || d.status === 'VERIFIED' || d.status === 'SUCCESS' || d.approved)) {
                                  setTimeout(triggerSuccess, 800);
                                }
                              } catch(err) {}
                            }, false);

                            // Observe DOM changes or redirect notification text
                            var observer = new MutationObserver(function() {
                              var text = document.body ? (document.body.innerText || '') : '';
                              if (text.indexOf("redirecting you back to the merchant") !== -1 ||
                                  text.indexOf("Authentication in Progress") !== -1 ||
                                  text.indexOf("Authentication Successful") !== -1 ||
                                  text.indexOf("Verification Successful") !== -1 ||
                                  text.indexOf("SUCCESS") !== -1) {
                                setTimeout(triggerSuccess, 800);
                              }
                            });

                            if (document.body) {
                              observer.observe(document.body, { childList: true, subtree: true, characterData: true });
                            }

                            // Interval fallback
                            setInterval(function() {
                              var text = document.body ? (document.body.innerText || '') : '';
                              if (text.indexOf("redirecting you back to the merchant") !== -1 ||
                                  text.indexOf("Authentication in Progress") !== -1 ||
                                  text.indexOf("Authentication Successful") !== -1 ||
                                  text.indexOf("Verification Successful") !== -1 ||
                                  text.indexOf("SUCCESS") !== -1) {
                                triggerSuccess();
                              }
                            }, 500);
                          })();
                        ''',
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    return passed;
  }

  // --- Backend API Integration ---

  static Future<bool> checkCardDuplicate(
    String email,
    String cardNumber,
  ) async {
    try {
      final res = await http.post(
        Uri.parse('${AuthService.baseUrl}/api/payment/check-duplicate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'cardNumber': cardNumber}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['isDuplicate'] == true;
      }
    } catch (_) {}
    return false;
  }

  static Future<List<Map<String, dynamic>>> fetchSavedCards(
    String email,
  ) async {
    try {
      final res = await http.get(
        Uri.parse('${AuthService.baseUrl}/api/payment/methods?email=$email'),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['methods'] is List) {
          return List<Map<String, dynamic>>.from(data['methods']);
        }
      }
    } catch (_) {}
    return [];
  }

  static Future<Map<String, dynamic>> saveCardToBackend({
    required String email,
    required String tokenId,
    required String paymentAccountNo,
    required String cardNumber,
    required String expiryDate,
    required String cvv,
    required String providerName,
    required bool isDefault,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('${AuthService.baseUrl}/api/payment/save-card'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'tokenId': tokenId,
          'paymentAccountNo': paymentAccountNo,
          'cardNumber': cardNumber,
          'expiryDate': expiryDate,
          'cvv': cvv,
          'providerName': providerName,
          'isDefault': isDefault,
        }),
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        return {'success': true, 'data': data};
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to save payment account',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Network error while connecting to server',
      };
    }
  }

  static Future<bool> setDefaultCard(String email, String paymentId) async {
    try {
      final res = await http.put(
        Uri.parse('${AuthService.baseUrl}/api/payment/set-default'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'paymentId': paymentId}),
      );
      final data = jsonDecode(res.body);
      return res.statusCode == 200 && data['success'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> deleteCard(String email, String paymentId) async {
    try {
      final res = await http.delete(
        Uri.parse(
          '${AuthService.baseUrl}/api/payment/methods/$paymentId?email=$email',
        ),
      );
      final data = jsonDecode(res.body);
      return res.statusCode == 200 && data['success'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Creates a Xendit Invoice for checkout payments
  static Future<Map<String, dynamic>> createInvoice({
    required String email,
    required double amount,
    required String description,
    required String paymentMethodType,
    List<String>? productIDs,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('${AuthService.baseUrl}/api/payment/create-invoice'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'amount': amount,
          'description': description,
          'paymentMethodType': paymentMethodType,
          'productIDs': productIDs ?? [],
        }),
      );
      final data = jsonDecode(res.body);
      return data is Map<String, dynamic>
          ? data
          : {'success': false, 'error': 'Invalid server response'};
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  /// Requests automatic refund or expiration if inventory was lost during payment
  static Future<Map<String, dynamic>> refundInvoice({
    required String invoiceId,
    String? reason,
    double? amount,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('${AuthService.baseUrl}/api/payment/refund-invoice'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'invoiceId': invoiceId,
          'reason': reason ?? 'ITEM_UNAVAILABLE_RACE_CONDITION',
          if (amount != null && amount > 0) 'amount': amount,
        }),
      );
      final data = jsonDecode(res.body);
      return data is Map<String, dynamic> ? data : {'success': false};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Checks live invoice status directly from Xendit
  static Future<Map<String, dynamic>> getInvoiceStatus(String invoiceId) async {
    try {
      final res = await http.get(
        Uri.parse(
          '${AuthService.baseUrl}/api/payment/get-invoice?invoiceId=$invoiceId',
        ),
        headers: {'Content-Type': 'application/json'},
      );
      final data = jsonDecode(res.body);
      return data is Map<String, dynamic> ? data : {'success': false};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Opens Xendit Payment Page via InAppWebView modal and waits for completion
  /// Returns a map: {'status': 'success' | 'failed' | 'cancelled', 'errorMessage': String?}
  static Future<Map<String, dynamic>> launchPaymentWebView({
    required BuildContext context,
    required String invoiceUrl,
    required String title,
    String? invoiceId,
    Map<String, dynamic>? cardData,
  }) async {
    String paymentResult = 'cancelled';
    String? failReason;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.90,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          clipBehavior: Clip.antiAliasWithSaveLayer,
          child: Column(
            children: [
              Container(
                color: const Color(0xFF0F254B),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.lock_outline,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 20,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        // User explicitly clicked close (X), mark as cancelled
                        paymentResult = 'cancelled';
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(invoiceUrl)),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    javaScriptCanOpenWindowsAutomatically: true,
                    useShouldOverrideUrlLoading: true,
                    transparentBackground: false,
                    supportMultipleWindows: true,
                  ),
                  onLoadStart: (controller, url) {
                    final strUrl = url?.toString().toLowerCase() ?? '';
                    if (strUrl.contains('payment-success') ||
                        strUrl.contains('status=paid') ||
                        strUrl.contains('status=settled') ||
                        strUrl.contains('status=completed') ||
                        strUrl.contains('status=active') ||
                        strUrl.contains('status=linked') ||
                        strUrl.contains('status=authorized') ||
                        strUrl.contains('action=success')) {
                      paymentResult = 'success';
                      Future.delayed(const Duration(milliseconds: 600), () {
                        if (ctx.mounted) Navigator.pop(ctx);
                      });
                    } else if (strUrl.contains('payment-failure') ||
                        strUrl.contains('status=failed') ||
                        strUrl.contains('action=failed') ||
                        strUrl.contains('error=declined') ||
                        strUrl.contains('insufficient_balance')) {
                      paymentResult = 'failed';
                      if (strUrl.contains('insufficient_balance') ||
                          strUrl.contains('insufficient_funds')) {
                        failReason =
                            'Selected account has insufficient balance.';
                      } else {
                        failReason =
                            'Payment or authorization was declined by your bank or card issuer.';
                      }
                      Future.delayed(const Duration(milliseconds: 600), () {
                        if (ctx.mounted) Navigator.pop(ctx);
                      });
                    }
                  },
                  initialUserScripts: null,
                  onLoadStop: (controller, url) async {
                    if (cardData != null) {
                      // Extract raw 16-digit card number (fallback to cardNumber if unmasked)
                      String rawNumber =
                          (cardData['rawCardNumber'] ??
                                  cardData['cardNumber'] ??
                                  '')
                              .toString()
                              .replaceAll(RegExp(r'\D'), '');
                      final expiry =
                          (cardData['expiryDate'] ??
                                  cardData['expiredDate'] ??
                                  '')
                              .toString();
                      final cvv = (cardData['cvv'] ?? cardData['CVV'] ?? '')
                          .toString()
                          .trim();
                      final holderName = (cardData['cardHolderName'] ?? '')
                          .toString();
                      final email = (cardData['email'] ?? '').toString().trim();

                      // Strip +60 or 60 or leading 0 if needed for Malaysian phone input
                      String phone =
                          (cardData['phone'] ?? cardData['phoneNumber'] ?? '')
                              .toString()
                              .trim();
                      if (phone.startsWith('+60')) {
                        phone = phone.substring(3);
                      } else if (phone.startsWith('60')) {
                        phone = phone.substring(2);
                      } else if (phone.startsWith('0')) {
                        phone = phone.substring(1);
                      }

                      await controller.evaluateJavascript(
                        source:
                            '''
                        (function() {
                          function setNativeValue(element, value) {
                            if (!element || !value) return;
                            if (element.value === value) return;
                            try {
                              var valueSetter = Object.getOwnPropertyDescriptor(element, 'value')?.set;
                              var prototype = Object.getPrototypeOf(element);
                              var prototypeValueSetter = Object.getOwnPropertyDescriptor(prototype, 'value')?.set;
                              if (prototypeValueSetter && valueSetter !== prototypeValueSetter) {
                                prototypeValueSetter.call(element, value);
                              } else if (valueSetter) {
                                valueSetter.call(element, value);
                              } else {
                                element.value = value;
                              }
                              element.dispatchEvent(new Event('input', { bubbles: true }));
                              element.dispatchEvent(new Event('change', { bubbles: true }));
                            } catch(e) {
                              try {
                                element.value = value;
                                element.dispatchEvent(new Event('input', { bubbles: true }));
                                element.dispatchEvent(new Event('change', { bubbles: true }));
                              } catch(err) {}
                            }
                          }

                          function prefillDocument(doc) {
                            if (!doc) return;
                            try {
                              // 1. Card Number
                              var numInput = doc.querySelector('input[name="card_number"]') ||
                                             doc.querySelector('input[name*="card"]') ||
                                             doc.querySelector('input[autocomplete="cc-number"]') ||
                                             doc.querySelector('input[placeholder*="Card number"]') ||
                                             doc.querySelector('input[id*="card-number"]');
                              if (numInput && (!numInput.value || numInput.value.length < 10) && '$rawNumber') {
                                setNativeValue(numInput, '$rawNumber');
                              }

                              // 2. Expiry (MM/YY)
                              var expInput = doc.querySelector('input[name="expiry"]') ||
                                             doc.querySelector('input[name*="exp"]') ||
                                             doc.querySelector('input[autocomplete="cc-exp"]') ||
                                             doc.querySelector('input[placeholder*="MM/YY"]') ||
                                             doc.querySelector('input[placeholder*="MM / YY"]') ||
                                             doc.querySelector('input[id*="expiry"]');
                              if (expInput && !expInput.value && '$expiry') {
                                setNativeValue(expInput, '$expiry');
                              }

                              // 3. CVV / CVC
                              var cvvInput = doc.querySelector('input[name="cvn"]') ||
                                             doc.querySelector('input[name="cvv"]') ||
                                             doc.querySelector('input[name="cvc"]') ||
                                             doc.querySelector('input[autocomplete="cc-csc"]') ||
                                             doc.querySelector('input[placeholder*="CVV"]') ||
                                             doc.querySelector('input[placeholder*="CVC"]') ||
                                             doc.querySelector('input[id*="cvv"]') ||
                                             doc.querySelector('input[id*="cvc"]');
                              if (cvvInput && !cvvInput.value && '$cvv') {
                                setNativeValue(cvvInput, '$cvv');
                              }

                              // 4. Cardholder Name
                              var nameInput = doc.querySelector('input[name="holder_name"]') ||
                                              doc.querySelector('input[name*="holder"]') ||
                                              doc.querySelector('input[autocomplete="cc-name"]') ||
                                              doc.querySelector('input[placeholder*="Name on card"]');
                              if (nameInput && !nameInput.value && '$holderName') {
                                setNativeValue(nameInput, '$holderName');
                              }

                              // 5. Email - prefill user's email into any email input
                              var emailInput = doc.querySelector('input[name="email"]') ||
                                               doc.querySelector('input[type="email"]') ||
                                               doc.querySelector('input[name*="email"]') ||
                                               doc.querySelector('input[autocomplete="email"]') ||
                                               doc.querySelector('input[placeholder*="email" i]') ||
                                               doc.querySelector('input[id*="email" i]');
                              if (emailInput && (!emailInput.value || emailInput.value.trim() === '') && '$email') {
                                setNativeValue(emailInput, '$email');
                              }

                              // 6. Phone Number (without +60)
                              var phoneInput = doc.querySelector('input[name="phone"]') ||
                                               doc.querySelector('input[name="mobile"]') ||
                                               doc.querySelector('input[name*="phone"]') ||
                                               doc.querySelector('input[name*="mobile"]') ||
                                               doc.querySelector('input[type="tel"]') ||
                                               doc.querySelector('input[placeholder*="Phone" i]') ||
                                               doc.querySelector('input[placeholder*="Mobile" i]');
                              if (phoneInput && (!phoneInput.value || phoneInput.value.trim() === '') && '$phone') {
                                setNativeValue(phoneInput, '$phone');
                              }
                            } catch(e) {}
                          }

                          function runAll() {
                            prefillDocument(document);
                            try {
                              var iframes = document.querySelectorAll('iframe');
                              for (var i = 0; i < iframes.length; i++) {
                                try {
                                  prefillDocument(iframes[i].contentDocument || iframes[i].contentWindow.document);
                                } catch(e) {}
                              }
                            } catch(e) {}
                          }

                          setTimeout(runAll, 300);
                          setTimeout(runAll, 800);
                          setTimeout(runAll, 1600);
                          setTimeout(runAll, 2800);
                        })();
                      ''',
                      );
                    }
                  },
                  shouldOverrideUrlLoading: (controller, navigationAction) async {
                    final uri =
                        navigationAction.request.url
                            ?.toString()
                            .toLowerCase() ??
                        '';
                    if (uri.contains('payment-success') ||
                        uri.contains('status=paid') ||
                        uri.contains('status=settled') ||
                        uri.contains('status=completed') ||
                        uri.contains('status=active') ||
                        uri.contains('status=linked') ||
                        uri.contains('status=authorized') ||
                        uri.contains('action=success')) {
                      paymentResult = 'success';
                      Future.delayed(const Duration(milliseconds: 600), () {
                        if (ctx.mounted) Navigator.pop(ctx);
                      });
                      return NavigationActionPolicy.CANCEL;
                    } else if (uri.contains('payment-failure') ||
                        uri.contains('status=failed') ||
                        uri.contains('action=failed') ||
                        uri.contains('error=declined') ||
                        uri.contains('insufficient_balance')) {
                      paymentResult = 'failed';
                      if (uri.contains('insufficient_balance') ||
                          uri.contains('insufficient_funds')) {
                        failReason =
                            'Selected account has insufficient balance.';
                      } else {
                        failReason =
                            'Payment was declined by your bank or card issuer.';
                      }
                      Future.delayed(const Duration(milliseconds: 600), () {
                        if (ctx.mounted) Navigator.pop(ctx);
                      });
                      return NavigationActionPolicy.CANCEL;
                    }
                    return NavigationActionPolicy.ALLOW;
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    return {'status': paymentResult, 'errorMessage': failReason};
  }
}
