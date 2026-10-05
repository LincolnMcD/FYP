import 'package:flutter/material.dart';
import 'home_page.dart';
import 'services/auth_service.dart';
import 'services/session_service.dart';
import 'register_page.dart';
import 'complete_profile_page.dart';
import 'forgot_password_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _obscurePassword = true;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String? _emailError;
  String? _passwordError;
  bool _isLoading = false;

  bool get _isFormValid {
    return _emailController.text.isNotEmpty &&
        _passwordController.text.isNotEmpty &&
        _emailError == null &&
        _passwordError == null;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _validateEmail(String value) {
    if (value.isEmpty) {
      setState(() => _emailError = 'Email cannot be empty');
      return;
    }
    if (value.contains(' ')) {
      setState(() => _emailError = 'Email cannot contain spaces');
      return;
    }
    if (value.contains(RegExp(r'[A-Z]'))) {
      setState(() => _emailError = 'Email cannot contain capital letters');
      return;
    }
    if (!value.contains('@')) {
      setState(() => _emailError = 'Email must contain @');
      return;
    }
    final parts = value.split('@');
    if (parts.length > 2) {
      setState(() => _emailError = 'Email cannot contain multiple @');
      return;
    }
    if (parts[0].isEmpty) {
      setState(() => _emailError = 'Email must have at least 1 character before @');
      return;
    }
    if (!parts[1].contains('.')) {
      setState(() => _emailError = 'Email must have a dot after @');
      return;
    }
    final afterParts = parts[1].split('.');
    if (afterParts.length != 2) {
      setState(() => _emailError = 'Email must have exactly one dot after @');
      return;
    }
    if (afterParts[0].isEmpty) {
      setState(() => _emailError = 'Email must have at least 1 character between @ and .');
      return;
    }
    if (afterParts[1].isEmpty) {
      setState(() => _emailError = 'Email must have at least 1 character after .');
      return;
    }
    setState(() => _emailError = null);
  }

  void _handleLogin() async {
    _validateEmail(_emailController.text);
    setState(() => _passwordError = null);
    if (_emailError != null) return;
    
    setState(() => _isLoading = true);
    final result = await AuthService.login(_emailController.text, _passwordController.text);
    
    if (!mounted) return;
    setState(() => _isLoading = false);
    
      if (result['success']) {
        await SessionService.saveSession(email: _emailController.text.trim(), name: result['name']);
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => HomePage(isLoggedIn: true, email: _emailController.text, name: result['name'], toastMessage: 'Signed in successfully!')),
          (route) => false,
        );
    } else {
      _showTopToast(context, result['error'] ?? 'Login failed', true);
    }
  }

  void _showTopToast(BuildContext context, String message, bool isError) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;
    
    // Natively extract the height of the Status Bar + the Header (AppBar)
    final double exactTopPosition = MediaQuery.of(context).padding.top + kToolbarHeight + 12;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: exactTopPosition,
        left: 16,
        right: 16,
        child: Dismissible(
          key: UniqueKey(),
          direction: DismissDirection.horizontal,
          onDismissed: (_) => overlayEntry.remove(),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isError ? Colors.red.shade600 : Colors.green.shade600,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Row(
                children: [
                   Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: Colors.white, size: 24),
                   const SizedBox(width: 12),
                   Expanded(
                     child: Text(
                       message,
                       style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                     ),
                   ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);
    Future.delayed(const Duration(seconds: 4), () {
      if (overlayEntry.mounted) overlayEntry.remove();
    });
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
          await SessionService.saveSession(email: response['email'], name: response['name']);
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (context) => HomePage(isLoggedIn: true, email: response['email'], name: response['name'], toastMessage: response['message'] ?? 'Login successful via OAuth!'),
            ),
            (route) => false,
          );
        }
      } else {
        _showTopToast(context, response['error'] ?? 'Sign in failed', true);
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
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const HomePage(isLoggedIn: false)));
            }
          }
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/rebyte_logo.png', height: 36),
            const SizedBox(width: 8),
            const Text(
              'ReByte',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.bold,
                fontSize: 24,
              ),
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
              _buildLoginForm(context),
              const SizedBox(height: 24),
              _buildFooter(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.02),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Welcome Back',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Sign in to manage your certified tech.',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Email Address',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _emailController,
            onChanged: (val) {
              _validateEmail(val);
              setState(() => _passwordError = null);
            },
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              hintText: 'you@example.com',
              errorText: _emailError,
              errorMaxLines: 2,

              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              prefixIcon: Icon(Icons.email_outlined, color: Colors.grey.shade500, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF0C5AD2)),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.red),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.red),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Password',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              ),
              GestureDetector(
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const ForgotPasswordPage()));
                },
                child: const Text(
                  'Forgot password?',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0C5AD2)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            onChanged: (val) {
              setState(() => _passwordError = null);
            },
            decoration: InputDecoration(
              hintText: '••••••••',
              errorText: _passwordError,
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              prefixIcon: Icon(Icons.lock_outline, color: Colors.grey.shade500, size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: Colors.grey.shade500,
                  size: 20,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF0C5AD2)),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.red),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.red),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_isLoading || !_isFormValid) ? null : _handleLogin,
              icon: _isLoading 
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Sign In', style: TextStyle(fontWeight: FontWeight.bold)),
              label: const Icon(Icons.arrow_forward, size: 18),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0C5AD2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
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
          _buildSocialButton('Sign in with Google', Image.asset('assets/images/google_logo.png', height: 24, width: 24), () => _handleSocialLoginState(AuthService.signInWithGoogle)),
          const SizedBox(height: 12),
          _buildSocialButton('Sign in with Facebook', const Icon(Icons.facebook, color: Colors.blue, size: 30), () => _handleSocialLoginState(AuthService.signInWithFacebook)),
        ],
      ),
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
        const Text(
          'Don\'t have an account? ',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
        ),
        GestureDetector(
          onTap: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const RegisterPage()),
            );
          },
          child: const Text(
            'Register',
            style: TextStyle(
              color: Color(0xFF0C5AD2),
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}
