import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../account_management_module/login_page.dart';
import '../account_management_module/services/session_service.dart';
import 'services/rental_service.dart';

class RentalManagementPage extends StatefulWidget {
  final String? toastMessage;

  const RentalManagementPage({super.key, this.toastMessage});

  @override
  State<RentalManagementPage> createState() => _RentalManagementPageState();
}

class _RentalManagementPageState extends State<RentalManagementPage> {
  final TextEditingController _productIdController = TextEditingController();
  bool _isLoading = false;

  String? _toastMessage;
  bool _isToastError = false;

  @override
  void initState() {
    super.initState();
    if (widget.toastMessage != null) {
      _showTopToast(widget.toastMessage!, false);
    }
  }

  @override
  void dispose() {
    _productIdController.dispose();
    super.dispose();
  }

  void _showTopToast(String message, bool isError) {
    setState(() {
      _toastMessage = message;
      _isToastError = isError;
    });

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _toastMessage = null;
        });
      }
    });
  }

  Future<void> _handleLogout() async {
    await SessionService.clearSession();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
      (route) => false,
    );
  }

  Future<void> _handleRegisterRentalPhone() async {
    final productID = _productIdController.text.trim();

    // 1. Toast error when empty input
    if (productID.isEmpty) {
      _showTopToast('Product ID cannot be empty.', true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 2. Retrieve the using phone's fcmToken
      String fcmToken = '';
      try {
        final messaging = FirebaseMessaging.instance;
        await messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        final token = await messaging.getToken().timeout(const Duration(seconds: 5));
        if (token != null && token.isNotEmpty) {
          fcmToken = token;
        }
      } catch (fcmError) {
        // Fallback: If device doesn't have Google Play Services or token fails, continue with fallback token
        debugPrint('Could not retrieve device FCM token: $fcmError');
      }

      // 3. Call backend rental endpoint
      final result = await RentalService.registerRentalPhone(
        productID: productID,
        fcmToken: fcmToken,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (result['success']) {
        _showTopToast(result['message'] ?? 'Product registered as rental phone!', false);
        _productIdController.clear();
      } else {
        _showTopToast(result['error'] ?? 'Registration failed.', true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showTopToast('An error occurred during registration.', true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: Row(
          children: [
            Image.asset(
              'assets/images/rebyte_logo.png',
              height: 32,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.memory,
                color: Color(0xFF0C5AD2),
                size: 28,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'ReByte Rental',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout, color: Color(0xFF64748B)),
            onPressed: _handleLogout,
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  children: [
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0C5AD2).withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.phone_android_rounded,
                                  size: 44,
                                  color: Color(0xFF0C5AD2),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            const Center(
                              child: Text(
                                "Im RENTAL",
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Center(
                              child: Text(
                                "Rental Management Module",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ),
                            const SizedBox(height: 28),
                            const Text(
                              "Product ID",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _productIdController,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _handleRegisterRentalPhone(),
                              decoration: InputDecoration(
                                hintText: "Enter Product ID (e.g. 2610PRD008)",
                                hintStyle: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontSize: 14,
                                ),
                                prefixIcon: const Icon(
                                  Icons.qr_code_rounded,
                                  color: Color(0xFF64748B),
                                  size: 20,
                                ),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: Colors.grey.shade300),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: Colors.grey.shade300),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF0C5AD2),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              height: 48,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _handleRegisterRentalPhone,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0C5AD2),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  elevation: 0,
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        "Register as Rental Phone",
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              height: 44,
                              child: OutlinedButton.icon(
                                onPressed: _handleLogout,
                                icon: const Icon(Icons.logout, size: 18),
                                label: const Text('Sign Out'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFFDC2626),
                                  side: const BorderSide(color: Color(0xFFFCA5A5)),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_toastMessage != null)
            Positioned(
              top: 16,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: _isToastError ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      _isToastError ? Icons.error_outline : Icons.check_circle_outline,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _toastMessage!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
