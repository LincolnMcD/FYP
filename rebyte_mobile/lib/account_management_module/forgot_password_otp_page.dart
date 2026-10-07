import 'dart:async';
import 'package:flutter/material.dart';
import 'package:rebyte_mobile/account_management_module/services/auth_service.dart';
import 'package:rebyte_mobile/account_management_module/forgot_password_create_page.dart';

class ForgotPasswordOtpPage extends StatefulWidget {
  final String email;

  const ForgotPasswordOtpPage({
    super.key,
    required this.email,
  });

  @override
  State<ForgotPasswordOtpPage> createState() => _ForgotPasswordOtpPageState();
}

class _ForgotPasswordOtpPageState extends State<ForgotPasswordOtpPage> {
  final List<TextEditingController> _controllers = List.generate(6, (index) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (index) => FocusNode());
  bool _isLoading = false;
  bool _isResending = false;
  
  Timer? _timer;
  int _countdown = 600; // 10 minutes
  int _resendCooldown = 60; // 1 minute lockout

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _countdown = 600);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_countdown > 0) _countdown--;
        if (_resendCooldown > 0) _resendCooldown--;
        
        if (_countdown == 0 && _resendCooldown == 0) {
          _timer?.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (var c in _controllers) c.dispose();
    for (var f in _focusNodes) f.dispose();
    super.dispose();
  }

  

  Future<void> _verifyOTP() async {
    final code = _controllers.map((c) => c.text.trim()).join();
    if (code.length != 6) {
      _showTopToast('no 6 digit yet', true);
      return;
    }

    setState(() => _isLoading = true);
    final result = await AuthService.verifyForgotPasswordOtp(widget.email, code);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success']) {
      _showTopToast('OTP verified!', false);
      Future.delayed(const Duration(milliseconds: 500), () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CreateNewPasswordPage(email: widget.email, otp: code),
          ),
        );
      });
    } else {
      _showTopToast('fail due to wrong OTP', true);
    }
  }

  Future<void> _resendOTP() async {
    setState(() => _isResending = true);
    final result = await AuthService.requestForgotPasswordOtp(widget.email);
    if (!mounted) return;
    setState(() => _isResending = false);

    if (result['success']) {
      _showTopToast('A new code has been sent!', false);
      _startTimer();
      if (!mounted) return;
      setState(() => _resendCooldown = 60);
    } else {
      _showTopToast(result['error'] ?? 'Could not resend code', true);
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
      backgroundColor: const Color(0xFFF9FAFF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
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
      ),
      body: Stack(
        children: [
          SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),
              Center(
                child: Container(
                  height: 64,
                  width: 64,
                  decoration: BoxDecoration(color: Colors.blue.shade50, shape: BoxShape.circle),
                  child: Icon(Icons.mark_email_read, size: 28, color: Colors.blue.shade800),
                ),
              ),
              const SizedBox(height: 32),
              const Text('Verify Your Email', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
              const SizedBox(height: 12),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: const TextStyle(fontSize: 15, color: Color(0xFF475569), height: 1.5),
                  children: [
                    const TextSpan(text: 'We\'ve sent a 6-digit verification code to\n'),
                    TextSpan(text: widget.email, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (index) {
                  return SizedBox(
                    width: 48,
                    height: 56,
                    child: TextField(
                      controller: _controllers[index],
                      focusNode: _focusNodes[index],
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      maxLength: 1,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      decoration: InputDecoration(
                        counterText: '',
                        contentPadding: EdgeInsets.zero,
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.blue.shade800, width: 2)),
                      ),
                      onChanged: (value) {
                        if (value.isNotEmpty && index < 5) FocusScope.of(context).requestFocus(_focusNodes[index + 1]);
                        if (value.isEmpty && index > 0) FocusScope.of(context).requestFocus(_focusNodes[index - 1]);
                      },
                    ),
                  );
                }),
              ),
              const SizedBox(height: 32),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer_outlined, size: 16, color: Colors.orange.shade700),
                      const SizedBox(width: 8),
                      Text(
                        '${(_countdown ~/ 60).toString().padLeft(2, '0')}:${(_countdown % 60).toString().padLeft(2, '0')}',
                        style: TextStyle(color: Colors.orange.shade700, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isLoading ? () {} : _verifyOTP,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade900,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: _isLoading 
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Verify Code', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                        ],
                      ),
              ),
              const SizedBox(height: 32),
              const Text('Didn\'t receive the email?', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
              TextButton(
                onPressed: (_isResending || _resendCooldown > 0) ? null : _resendOTP,
                child: _isResending
                    ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(
                        _resendCooldown > 0 ? 'Resend Code in ${_resendCooldown}s' : 'Resend Code', 
                        style: TextStyle(
                          color: _resendCooldown > 0 ? Colors.grey : Colors.blue.shade800, 
                          fontWeight: FontWeight.bold, 
                          fontSize: 14, 
                          decoration: _resendCooldown > 0 ? TextDecoration.none : TextDecoration.underline
                        )
                      ),
              ),
              const SizedBox(height: 32),
              const Divider(color: Color(0xFFE2E8F0)),
              const SizedBox(height: 24),
              Center(
                child: TextButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back, size: 16, color: Color(0xFF475569)),
                  label: const Text('Back to Previous', style: TextStyle(color: Color(0xFF475569))),
                ),
              ),
            ],
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
