import 'package:flutter/material.dart';
import 'package:rebyte_mobile/account_management_module/services/auth_service.dart';
import 'package:rebyte_mobile/account_management_module/forgot_password_otp_page.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final TextEditingController _emailController = TextEditingController();
  String? _emailError;
  bool _isLoading = false;

  void _validateEmail(String value) {
    if (value.isEmpty || value.trim().isEmpty) setState(() => _emailError = 'Email cannot be empty');
    else if (value.contains(' ')) setState(() => _emailError = 'Email cannot contain spaces');
    else if (value.contains(RegExp(r'[A-Z]'))) setState(() => _emailError = 'Email cannot contain capital letters');
    else if (!value.contains('@')) setState(() => _emailError = 'Email must contain @');
    else if (value.split('@').length > 2) setState(() => _emailError = 'Email cannot contain multiple @');
    else if (value.split('@')[0].isEmpty) setState(() => _emailError = 'Email must have at least 1 character before @');
    else if (!value.split('@')[1].contains('.')) setState(() => _emailError = 'Email must have a dot after @');
    else if (value.split('@')[1].split('.').length != 2) setState(() => _emailError = 'Email must have exactly one dot after @');
    else if (value.split('@')[1].split('.')[0].isEmpty) setState(() => _emailError = 'Email must have at least 1 character between @ and .');
    else if (value.split('@')[1].split('.')[1].isEmpty) setState(() => _emailError = 'Email must have at least 1 character after .');
    else setState(() => _emailError = null);
  }

  void _handleSendOTP() async {
    _validateEmail(_emailController.text);
    if (_emailError != null || _emailController.text.isEmpty) return;

    setState(() => _isLoading = true);
    final result = await AuthService.requestForgotPasswordOtp(_emailController.text);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success']) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ForgotPasswordOtpPage(email: _emailController.text),
        ),
      );
    } else {
      _showTopToast(result['error'] ?? 'Request failed', true);
    }
  }

  

  String? _toastMessage;
  bool _isToastError = false;

  void _showTopToast(String message, bool isError) {
    setState(() {
      _toastMessage = message;
      _isToastError = isError;
    });
    
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toastMessage = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/rebyte_logo.png', height: 45),
            const SizedBox(width: 8),
            const Text('ReByte', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 32, letterSpacing: -0.5)),
          ],
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Forgot Password?', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                const SizedBox(height: 12),
                const Text('Enter your registered email address to receive a one-time password (OTP) to reset your account access.', style: TextStyle(fontSize: 14, color: Color(0xFF475569))),
                const SizedBox(height: 24),
                const Text('Email Address', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                const SizedBox(height: 8),
                TextField(
                  controller: _emailController,
                  onChanged: _validateEmail,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: 'you@example.com',
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 15),
                    prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFF64748B)),
                    errorText: _emailError,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF0C5AD2), width: 1.5)),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleSendOTP,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0C5AD2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Send OTP', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF0C5AD2), width: 1.2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Return to Login', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0C5AD2))),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),

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
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
                    ),
                    child: Row(
                      children: [
                        Icon(_isToastError ? Icons.error_outline : Icons.check_circle_outline, color: Colors.white, size: 24),
                        const SizedBox(width: 12),
                        Expanded(child: Text(_toastMessage!, textAlign: TextAlign.justify, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13))),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),

    );
  }
}
