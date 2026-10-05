import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:rebyte_mobile/account_management_module/services/auth_service.dart';
import 'home_page.dart';
import 'login_page.dart';

class CreateNewPasswordPage extends StatefulWidget {
  final String email;
  final String otp;

  const CreateNewPasswordPage({
    super.key,
    required this.email,
    required this.otp,
  });

  @override
  State<CreateNewPasswordPage> createState() => _CreateNewPasswordPageState();
}

class _CreateNewPasswordPageState extends State<CreateNewPasswordPage> {
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  final TextEditingController _newPwController = TextEditingController();
  final TextEditingController _confirmPwController = TextEditingController();

  String? _newPwError;
  String? _confirmPwError;
  bool _isLoading = false;

  void _validateNewPassword(String value) {
    if (value.isEmpty) _newPwError = 'Please enter a password';
    else if (value.length < 8) _newPwError = 'Password must be at least 8 characters';
    else if (!value.contains(RegExp(r'[A-Z]'))) _newPwError = 'Password must contain at least 1 uppercase letter';
    else if (!value.contains(RegExp(r'[a-z]'))) _newPwError = 'Password must contain at least 1 lowercase letter';
    else if (!value.contains(RegExp(r'[0-9]'))) _newPwError = 'Password must contain at least 1 number';
    else if (!value.contains(RegExp(r'[!@#\$%\^&\*(),.?":{}|<>]'))) _newPwError = 'Password must contain at least 1 special character';
    else _newPwError = null;

    if (_confirmPwController.text.isNotEmpty) {
      if (_confirmPwController.text != value) _confirmPwError = 'Passwords do not match';
      else _confirmPwError = null;
    }
    setState(() {});
  }

  void _validateConfirmPassword(String value) {
    if (value.isEmpty) _confirmPwError = 'Please confirm your password';
    else if (value != _newPwController.text) _confirmPwError = 'Passwords do not match';
    else _confirmPwError = null;
    setState(() {});
  }

  bool get _isFormValid => 
    _newPwController.text.isNotEmpty && 
    _confirmPwController.text.isNotEmpty && 
    _newPwError == null && 
    _confirmPwError == null;

  void _showTopToast(String message, bool isError) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    final topPos = MediaQuery.of(context).padding.top + kToolbarHeight + 12;

    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: topPos, left: 16, right: 16,
        child: Dismissible(
          key: UniqueKey(),
          direction: DismissDirection.horizontal,
          onDismissed: (_) => entry.remove(),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isError ? Colors.red.shade600 : Colors.green.shade600,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: Colors.white, size: 24),
                  const SizedBox(width: 12),
                  Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 4), () { if (entry.mounted) entry.remove(); });
  }

  void _handleResetPassword() async {
    _validateNewPassword(_newPwController.text);
    _validateConfirmPassword(_confirmPwController.text);
    if (!_isFormValid) return;

    setState(() => _isLoading = true);

    // 1. First explicitly check if their new password is secretly their old password! 
    // This perfectly captures native Firebase constraints stopping duplicate usages identically nicely.
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: widget.email,
        password: _newPwController.text,
      );
      // Wait, if it succeeded, the password matches their currently hashed password! We reject it instantly!
      await FirebaseAuth.instance.signOut();
      setState(() {
        _isLoading = false;
        _newPwError = 'New password cannot be the same as your current password.';
      });
      return;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password') {
        // Excellent! The password is new! We can securely proceed natively downstate seamlessly!
      } else if (e.code == 'too-many-requests') {
         setState(() {
           _isLoading = false;
         });
         _showTopToast('Too many requests. Please try again later.', true);
         return;
      } else {
        // If user not found or something bizarre, we pass it safely downstairs!
      }
    } catch (_) {}

    // 2. Transmit the validated OTP and the New String explicitly towards Node.js to enact the overwrite!
    final result = await AuthService.resetForgotPassword(
      widget.email,
      _newPwController.text,
      widget.otp,
    );
    
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success']) {
      _showTopToast('Password has been successfully changed!', false);
      Future.delayed(const Duration(milliseconds: 1000), () {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginPage()),
          (route) => false,
        );
      });
    } else {
      _showTopToast(result['error'] ?? 'Reset failed', true);
    }
  }

  Widget _buildRequirementRow(String text, bool isMet) {
    return Row(
      children: [
        Icon(isMet ? Icons.check_circle : Icons.circle_outlined, size: 14, color: isMet ? Colors.green : const Color(0xFF64748B)),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(fontSize: 12, color: isMet ? Colors.green : const Color(0xFF475569))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final String pw = _newPwController.text;
    final bool has8Chars = pw.length >= 8;
    final bool hasUpper = pw.contains(RegExp(r'[A-Z]'));
    final bool hasLower = pw.contains(RegExp(r'[a-z]'));
    final bool hasNum = pw.contains(RegExp(r'[0-9]'));
    final bool hasSpecial = pw.contains(RegExp(r'[!@#\$%\^&\*(),.?":{}|<>]'));

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            int count = 0;
            Navigator.popUntil(context, (route) {
              return count++ == 2;
            });
          }
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Create a Password', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                const SizedBox(height: 12),
                const Text('Your identity has been verified. Please set a new strong password for your account.', style: TextStyle(fontSize: 14, color: Color(0xFF64748B))),
                const SizedBox(height: 24),
                
                // New Password Input
                const Text('New Password', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                const SizedBox(height: 8),
                TextField(
                  controller: _newPwController,
                  obscureText: _obscureNew,
                  onChanged: _validateNewPassword,
                  decoration: InputDecoration(
                    hintText: 'Enter new password',
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                    errorText: _newPwError,
                    errorMaxLines: 2,
                    suffixIcon: IconButton(
                      icon: Icon(_obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.grey.shade500, size: 20),
                      onPressed: () => setState(() => _obscureNew = !_obscureNew),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF0C5AD2))),
                    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.red)),
                    focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.red)),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Confirm Password Input
                const Text('Confirm New Password', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                const SizedBox(height: 8),
                TextField(
                  controller: _confirmPwController,
                  obscureText: _obscureConfirm,
                  onChanged: _validateConfirmPassword,
                  decoration: InputDecoration(
                    hintText: 'Confirm new password',
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                    errorText: _confirmPwError,
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.grey.shade500, size: 20),
                      onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF0C5AD2))),
                    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.red)),
                    focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.red)),
                  ),
                ),
                const SizedBox(height: 24),
                
                // Constraints block
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('PASSWORD REQUIREMENTS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                      const SizedBox(height: 12),
                      _buildRequirementRow('At least 8 characters', has8Chars),
                      const SizedBox(height: 8),
                      _buildRequirementRow('One uppercase letter', hasUpper),
                      const SizedBox(height: 8),
                      _buildRequirementRow('One lowercase letter', hasLower),
                      const SizedBox(height: 8),
                      _buildRequirementRow('One number (0-9)', hasNum),
                      const SizedBox(height: 8),
                      _buildRequirementRow('One special character (!@#\$%^&*)', hasSpecial),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                
                // Submit Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: (_isLoading || !_isFormValid) ? null : _handleResetPassword,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0C5AD2),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    child: _isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Change Password', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
