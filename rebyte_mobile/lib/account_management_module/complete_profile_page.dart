import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:rebyte_mobile/account_management_module/services/auth_service.dart';
import 'package:rebyte_mobile/account_management_module/services/session_service.dart';
import 'package:rebyte_mobile/account_management_module/home_page.dart';
import 'terms_of_service_page.dart';
import 'privacy_policy_page.dart';

class CompleteProfilePage extends StatefulWidget {
  final String email;
  final String? initialName;
  final String? initialPhone;

  const CompleteProfilePage({super.key, required this.email, this.initialName, this.initialPhone});

  @override
  State<CompleteProfilePage> createState() => _CompleteProfilePageState();
}

class _CompleteProfilePageState extends State<CompleteProfilePage> {
  late final TextEditingController _fullNameController;
  late final TextEditingController _phoneController;
  
  String? _selectedGender;
  DateTime? _selectedBirthDate;
  bool _isLoading = false;
  bool _hasInteractedWithFullName = false;
  bool _hasInteractedWithPhone = false;
  bool _isFormValid = false;
  bool _agreedToTerms = false;

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController(text: widget.initialName ?? '');
    _phoneController = TextEditingController(text: widget.initialPhone ?? '');
  }

  String? _toastMessage;
  bool _isToastError = false;

  void _showTopToast(String message, bool isError) {
    setState(() {
      _toastMessage = message;
      _isToastError = isError;
    });
    
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _toastMessage = null);
      }
    });
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime maxDate = DateTime(now.year - 12, now.month, now.day);
    final DateTime minDate = DateTime(now.year - 100, now.month, now.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: maxDate,
      firstDate: minDate,
      lastDate: maxDate,
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: ColorScheme.light(primary: Colors.blue.shade900),
          ),
          child: child!,
        );
      }
    );
    if (picked != null) {
      setState(() => _selectedBirthDate = picked);
    }
  }

  void _submitProfile() async {
    if (_fullNameController.text.trim().isEmpty) {
      _showTopToast('Full name is required', true);
      return;
    }

    final pVal = _phoneController.text.trim();
    final phonePayload = pVal.isEmpty ? '' : '+60$pVal';

    setState(() => _isLoading = true);
    final result = await AuthService.updateProfile(
      email: widget.email,
      fullName: _fullNameController.text,
      phoneNumber: phonePayload,
      birthDate: _selectedBirthDate?.toIso8601String() ?? '',
      gender: _selectedGender ?? '',
    );
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success']) {
        await SessionService.saveSession(email: widget.email, name: _fullNameController.text);
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => HomePage(isLoggedIn: true, email: widget.email, name: _fullNameController.text, toastMessage: 'Account created successfully!')), (route) => false);
    } else {
      _showTopToast(result['error'] ?? 'Update failed', true);
    }
  }


  @override
  Widget build(BuildContext context) {
    String? currentFullNameError;
    String? currentPhoneError;
    
    final f = _fullNameController.text.trim();
    bool isFullNameValid = false;
    
    if (f.isEmpty) {
       if (_hasInteractedWithFullName) {
         currentFullNameError = "Full name is required";
       }
    } else {
       isFullNameValid = true;
    }

    final p = _phoneController.text.trim();
    bool isPhoneValid = false;
    if (p.isEmpty) {
        if (_hasInteractedWithPhone) {
            currentPhoneError = 'Phone number is required';
        }
    }
    else if (!p.startsWith('1')) currentPhoneError = 'Must start with 1';
    else if (p.startsWith('11') && p.length != 10) currentPhoneError = 'Must be exactly 10 digits';
    else if (p.startsWith('1') && !p.startsWith('11') && p.length != 9) currentPhoneError = 'Must be exactly 9 digits';
    else isPhoneValid = true;

    _isFormValid = isFullNameValid && isPhoneValid && _selectedGender != null && _agreedToTerms;
    
    final birthDateText = _selectedBirthDate != null 
        ? "${_selectedBirthDate!.day.toString().padLeft(2, '0')}/${_selectedBirthDate!.month.toString().padLeft(2, '0')}/${_selectedBirthDate!.year}"
        : "Select date";

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFF),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/rebyte_logo.png', height: 36),
            const SizedBox(width: 8),
            const Text('ReByte', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 24)),
          ],
        ),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Complete Profile', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
              const SizedBox(height: 8),
              const Text('Lets get your account set up for secure transactions.', style: TextStyle(fontSize: 15, color: Color(0xFF475569))),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Personal Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                    const SizedBox(height: 4),
                    const Text('* indicates compulsory fields', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 16),
                    _buildLabel('Full Name *'),
                    _buildTextField(
                      _fullNameController, 
                      'Jane Doe',
                      maxLength: 100,
                      errorText: currentFullNameError,
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]'))],
                      onChangedCallback: () => setState(() => _hasInteractedWithFullName = true),
                    ),
                    const SizedBox(height: 16),
                    _buildLabel('Phone Number *'),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                          ),
                          child: const Text('+60', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                        ),
                        Expanded(
                          child: _buildTextField(
                            _phoneController, 
                            '12 1234567',
                            maxLength: 10,
                            keyboardType: TextInputType.phone,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            onChangedCallback: () => setState(() => _hasInteractedWithPhone = true),
                          ),
                        ),
                      ],
                    ),
                    if (currentPhoneError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0, left: 4.0),
                        child: Text(currentPhoneError, style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
                      ),
                    const SizedBox(height: 16),
                    _buildLabel('Birthday'),
                    GestureDetector(
                      onTap: _pickDate,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(birthDateText, style: TextStyle(fontSize: 15, color: _selectedBirthDate == null ? Colors.grey : Colors.black)),
                            const Icon(Icons.calendar_today_outlined, size: 20, color: Colors.grey),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildLabel('Gender *'),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => setState(() => _selectedGender = 'Male'),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: _selectedGender == 'Male' ? Colors.blue.shade900 : Colors.white,
                              side: BorderSide(color: _selectedGender == 'Male' ? Colors.blue.shade900 : const Color(0xFFE2E8F0)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text('Male', style: TextStyle(color: _selectedGender == 'Male' ? Colors.white : Colors.black)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => setState(() => _selectedGender = 'Female'),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: _selectedGender == 'Female' ? Colors.blue.shade900 : Colors.white,
                              side: BorderSide(color: _selectedGender == 'Female' ? Colors.blue.shade900 : const Color(0xFFE2E8F0)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text('Female', style: TextStyle(color: _selectedGender == 'Female' ? Colors.white : Colors.black)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    height: 24,
                    width: 24,
                    child: Checkbox(
                      value: _agreedToTerms,
                      onChanged: (val) => setState(() => _agreedToTerms = val ?? false),
                      activeColor: Colors.blue.shade900,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(fontSize: 13, color: Color(0xFF475569), height: 1.4),
                        children: [
                          const TextSpan(text: 'I agree to the '),
                          TextSpan(
                            text: 'Terms of Service',
                            style: const TextStyle(color: Color(0xFF0C5AD2), fontWeight: FontWeight.w600),
                            recognizer: TapGestureRecognizer()..onTap = () {
                              Navigator.push(context, MaterialPageRoute(builder: (context) => const TermsOfServicePage()));
                            },
                          ),
                          const TextSpan(text: ' and '),
                          TextSpan(
                            text: 'Privacy Policy',
                            style: const TextStyle(color: Color(0xFF0C5AD2), fontWeight: FontWeight.w600),
                            recognizer: TapGestureRecognizer()..onTap = () {
                              Navigator.push(context, MaterialPageRoute(builder: (context) => const PrivacyPolicyPage()));
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: (_isLoading || !_isFormValid) ? null : _submitProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: (!_isFormValid) ? Colors.grey.shade400 : Colors.blue.shade900,
                        disabledBackgroundColor: Colors.grey.shade400,
                        disabledForegroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        elevation: 0,
                      ),
                      child: _isLoading 
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Complete Registration', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
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
                    decoration: BoxDecoration(color: _isToastError ? Colors.red.shade600 : Colors.green.shade600, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        Icon(_isToastError ? Icons.error_outline : Icons.check_circle_outline, color: Colors.white, size: 24),
                        const SizedBox(width: 12),
                        Expanded(child: Text(_toastMessage!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13))),
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

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, {int? maxLength, List<TextInputFormatter>? inputFormatters, TextInputType? keyboardType, String? errorText, VoidCallback? onChangedCallback}) {
    return TextField(
      controller: controller,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      keyboardType: keyboardType,
      onChanged: (value) {
        if (onChangedCallback != null) onChangedCallback();
        setState(() {});
      },
      decoration: InputDecoration(
        errorText: errorText,
        counterText: '',
        hintText: hint,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.blue)),
      ),
    );
  }
}

