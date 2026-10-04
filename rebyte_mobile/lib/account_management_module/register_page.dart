import 'package:flutter/material.dart';
import 'package:rebyte_mobile/account_management_module/services/auth_service.dart';
import 'package:rebyte_mobile/account_management_module/otp_verification_page.dart';
import 'package:rebyte_mobile/account_management_module/complete_profile_page.dart';
import 'package:rebyte_mobile/account_management_module/home_page.dart';
import 'login_page.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  
  String? _emailError;
  String? _passwordError;
  String? _confirmPasswordError;
  bool _isLoading = false;

  bool get _isFormValid => _emailController.text.isNotEmpty && _passwordController.text.isNotEmpty && _confirmPasswordController.text.isNotEmpty && _emailError == null && _passwordError == null && _confirmPasswordError == null;

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

  void _validatePassword(String value) {
    if (value.isEmpty) setState(() => _passwordError = 'Please enter a password');
    else if (value.length < 8) setState(() => _passwordError = 'Password must be at least 8 characters');
    else if (!value.contains(RegExp(r'[A-Z]'))) setState(() => _passwordError = 'Password must contain at least 1 uppercase letter');
    else if (!value.contains(RegExp(r'[a-z]'))) setState(() => _passwordError = 'Password must contain at least 1 lowercase letter');
    else if (!value.contains(RegExp(r'[0-9]'))) setState(() => _passwordError = 'Password must contain at least 1 number');
    else if (!value.contains(RegExp(r'[!@#\$%\^&\*(),.?":{}|<>]'))) setState(() => _passwordError = 'Password must contain at least 1 special character');
    else setState(() => _passwordError = null);
    
    // Always re-validate confirm password when the main password changes!
    if (_confirmPasswordController.text.isNotEmpty) {
      _validateConfirmPassword(_confirmPasswordController.text);
    }
  }

  void _validateConfirmPassword(String value) {
    if (value.isEmpty) setState(() => _confirmPasswordError = 'Please confirm your password');
    else if (value != _passwordController.text) setState(() => _confirmPasswordError = 'Passwords do not match');
    else setState(() => _confirmPasswordError = null);
  }

  void _handleRegister() async {
    _validateEmail(_emailController.text);
    _validatePassword(_passwordController.text);
    _validateConfirmPassword(_confirmPasswordController.text);
    
    if (!_isFormValid) return;
    
    setState(() => _isLoading = true);
    final result = await AuthService.requestOTP(_emailController.text);
    if (!mounted) return;
    setState(() => _isLoading = false);
    
    if (result['success']) {
      _showTopToast(result['message'], false);
      Future.delayed(const Duration(milliseconds: 500), () {
        Navigator.push(context, MaterialPageRoute(
          builder: (context) => OTPVerificationPage(
            email: _emailController.text,
            password: _passwordController.text,
          ),
        ));
      });
    } else {
      _showTopToast(result['error'] ?? 'Registration failed', true);
    }
  }

  void _showTopToast(String message, bool isError) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;
    final double exactTopPosition = MediaQuery.of(context).padding.top + kToolbarHeight + 12;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: exactTopPosition, left: 16, right: 16,
        child: Dismissible(
          key: UniqueKey(),
          direction: DismissDirection.horizontal,
          onDismissed: (_) => overlayEntry.remove(),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(color: isError ? Colors.red.shade600 : Colors.green.shade600, borderRadius: BorderRadius.circular(12)),
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
    overlay.insert(overlayEntry);
    Future.delayed(const Duration(seconds: 4), () { if (overlayEntry.mounted) overlayEntry.remove(); });
  }

  void _handleSocialLoginState(Future<Map<String, dynamic>> Function() loginMethod) async {
    setState(() { _isLoading = true; });
    final response = await loginMethod();
    setState(() { _isLoading = false; });
    
    if (mounted) {
      if (response['success']) {
        if (response['requireProfileComplete'] == true) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => CompleteProfilePage(email: response['email'], initialName: response['name'], initialPhone: response['phone'])),
          );
        } else {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (context) => HomePage(isLoggedIn: true, email: response['email'], name: response['name'], toastMessage: response['message'] ?? 'Registration completed via OAuth!'),
            ),
            (route) => false,
          );
        }
      } else {
        _showTopToast(response['error'] ?? 'Sign up failed', true);
      }
    }
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
            Image.asset('assets/images/rebyte_logo.png', height: 36),
            const SizedBox(width: 8),
            const Text(
              'ReByte',
              style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 24),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const SizedBox(height: 16),
              _buildRegisterForm(context),
              const SizedBox(height: 24),
              _buildFooter(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRegisterForm(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Create an Account', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
          const SizedBox(height: 8),
          const Text('Join ReByte to start trading certified pre-owned tech.', style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
          const SizedBox(height: 24),
          const Text('Email Address', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
          const SizedBox(height: 8),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            onChanged: _validateEmail,
            decoration: InputDecoration(
              hintText: 'you@example.com',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              errorText: _emailError,
              errorMaxLines: 2,

              prefixIcon: Icon(Icons.email_outlined, color: Colors.grey.shade500, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF0C5AD2))),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Password', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
          const SizedBox(height: 8),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            onChanged: _validatePassword,
            decoration: InputDecoration(
              hintText: 'Create a strong password',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              errorText: _passwordError,
              errorMaxLines: 2,


              prefixIcon: Icon(Icons.lock_outline, color: Colors.grey.shade500, size: 20),
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.grey.shade500, size: 20),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF0C5AD2))),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 16),
          _buildPasswordRequirements(),
          const SizedBox(height: 16),
          const Text('Confirm Password', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
          const SizedBox(height: 8),
          TextField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirmPassword,
            onChanged: _validateConfirmPassword,
            decoration: InputDecoration(
              hintText: 'Repeat your password',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              errorText: _confirmPasswordError,
              prefixIcon: Icon(Icons.verified_user_outlined, color: Colors.grey.shade500, size: 20),
              suffixIcon: IconButton(
                icon: Icon(_obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.grey.shade500, size: 20),
                onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF0C5AD2))),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_isLoading || !_isFormValid) ? null : _handleRegister,
              icon: _isLoading 
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                : const Text('Register Account', style: TextStyle(fontWeight: FontWeight.bold)),
              label: _isLoading ? const SizedBox.shrink() : const Icon(Icons.arrow_forward, size: 18),
              style: ElevatedButton.styleFrom(
                backgroundColor: (!_isFormValid) ? Colors.grey.shade400 : const Color(0xFF0C5AD2),
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade400,
                disabledForegroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(child: Divider(color: Colors.grey.shade300)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('OR', style: TextStyle(color: Colors.grey.shade500, fontSize: 10, fontWeight: FontWeight.w600)),
              ),
              Expanded(child: Divider(color: Colors.grey.shade300)),
            ],
          ),
          const SizedBox(height: 24),
          _buildSocialButton('Continue with Google', Image.asset('assets/images/google_logo.png', height: 24, width: 24), () => _handleSocialLoginState(AuthService.signInWithGoogle)),
          const SizedBox(height: 12),
          _buildSocialButton('Continue with Facebook', const Icon(Icons.facebook, color: Colors.blue, size:30), () => _handleSocialLoginState(AuthService.signInWithFacebook)),
        ],
      ),
    );
  }

  Widget _buildPasswordRequirements() {
    bool hasMinLength = _passwordController.text.length >= 8;
    bool hasUppercase = _passwordController.text.contains(RegExp(r'[A-Z]'));
    bool hasLowercase = _passwordController.text.contains(RegExp(r'[a-z]'));
    bool hasNumber = _passwordController.text.contains(RegExp(r'[0-9]'));
    bool hasSpecial = _passwordController.text.contains(RegExp(r'[!@#\$%\^&\*]'));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFF3F5F9), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('PASSWORD REQUIREMENTS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
          const SizedBox(height: 12),
          _buildRequirementRow(hasMinLength ? Icons.check_circle : Icons.circle_outlined, 'At least 8 characters', hasMinLength),
          const SizedBox(height: 8),
          _buildRequirementRow(hasUppercase ? Icons.check_circle : Icons.circle_outlined, 'One uppercase letter', hasUppercase),
          const SizedBox(height: 8),
          _buildRequirementRow(hasLowercase ? Icons.check_circle : Icons.circle_outlined, 'One lowercase letter', hasLowercase),
          const SizedBox(height: 8),
          _buildRequirementRow(hasNumber ? Icons.check_circle : Icons.circle_outlined, 'One number (0-9)', hasNumber),
          const SizedBox(height: 8),
          _buildRequirementRow(hasSpecial ? Icons.check_circle : Icons.circle_outlined, 'One special character (!@#\$%^&*)', hasSpecial),
        ],
      ),
    );
  }

  Widget _buildRequirementRow(IconData icon, String text, bool isMet) {
    return Row(
      children: [
        Icon(icon, size: 16, color: isMet ? Colors.green : const Color(0xFF475569)),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(fontSize: 13, color: isMet ? const Color(0xFF1E293B) : const Color(0xFF475569))),
      ],
    );
  }

  Widget _buildSocialButton(String label, Widget iconWidget, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        onPressed: _isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.grey.shade300),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 32, // Fixed width to accommodate the icons (e.g. size 30)
              height: 32,
              child: Center(child: iconWidget),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 140, // Fixed width for text so they align perfectly
              child: Text(
                label,
                style: const TextStyle(color: Color(0xFF1E293B), fontSize: 12, fontWeight: FontWeight.w600),
                textAlign: TextAlign.left,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Already have an account? ', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
        GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const LoginPage())),
          child: const Text('Sign in', style: TextStyle(color: Color(0xFF0C5AD2), fontWeight: FontWeight.bold, fontSize: 13)),
        ),
      ],
    );
  }
}

