import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'services/auth_service.dart';
import 'services/session_service.dart';

class EditProfilePage extends StatefulWidget {
  final String email;

  const EditProfilePage({super.key, required this.email});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  bool _isLoading = true;
  String? _errorMessage;
  
  // Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _birthdayController = TextEditingController();
  
  // State 
  String _selectedGender = 'Not Specified';
  
  // Initial values for comparison
  String _initialName = '';
  String _initialPhone = '';
  String _initialBirthday = '';
  String _loginMethod = 'Email';

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }
  
  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _birthdayController.dispose();
    super.dispose();
  }

  Future<void> _fetchProfile() async {
    setState(() => _isLoading = true);
    final response = await AuthService.getProfile(widget.email);
    
    if (mounted) {
      if (response['success']) {
        final data = response['data'];
        
        setState(() {
          _initialName = data['fullName'] ?? '';
          _initialPhone = data['phoneNumber'] ?? '';
          _loginMethod = data['loginMethod'] ?? 'Email';
          if (_initialPhone.startsWith('+60')) {
             _initialPhone = _initialPhone.substring(3);
          }
          
          String rawBirthday = data['birthDate'] ?? '';
          if (rawBirthday.isNotEmpty) {
             try {
                // If it's an ISO string or contains time, parse and format it tightly.
                if (rawBirthday.contains('-') || rawBirthday.contains('T')) {
                   DateTime parsed = DateTime.parse(rawBirthday);
                   rawBirthday = DateFormat('dd/MM/yyyy').format(parsed);
                } 
             } catch (e) {
                // fallback to whatever string is there
             }
          }
          _initialBirthday = rawBirthday;
          _selectedGender = data['gender'] ?? 'Not Specified';
          
          _nameController.text = _initialName;
          _phoneController.text = _initialPhone;
          _birthdayController.text = _initialBirthday;
          
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = response['error'];
          _isLoading = false;
        });
      }
    }
  }

  bool _hasChanges() {
    return _nameController.text.trim() != _initialName.trim() ||
           _phoneController.text.trim() != _initialPhone.trim() ||
           _birthdayController.text.trim() != _initialBirthday.trim();
  }

  Future<void> _selectDate(BuildContext context) async {
    DateTime initialDate = DateTime.now().subtract(const Duration(days: 365 * 18));
    if (_birthdayController.text.isNotEmpty) {
      try {
        initialDate = DateFormat('dd/MM/yyyy').parse(_birthdayController.text);
      } catch (e) {
        // use default
      }
    }
    
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 99)),
      lastDate: DateTime.now().subtract(const Duration(days: 365 * 12)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF0C5AD2),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _birthdayController.text = DateFormat('dd/MM/yyyy').format(picked);
      });
    }
  }

  String? _nameError;
  String? _phoneError;

  void _validateForm() {
    String? newNameError;
    String? newPhoneError;
    final f = _nameController.text.trim();
    if (f.isEmpty) {
      newNameError = "Full name is required";
    } else if (!RegExp(r'^[a-zA-Z\s]+$').hasMatch(f)) {
      newNameError = "Only alphabetic characters allowed";
    }

    final p = _phoneController.text.trim();
    if (p.isEmpty) {
      newPhoneError = "Phone number is required";
    } else if (!p.startsWith('1')) {
      newPhoneError = "Must start with 1";
    } else if (p.startsWith('11') && p.length != 10) {
      newPhoneError = "Must be exactly 10 digits";
    } else if (p.startsWith('1') && !p.startsWith('11') && p.length != 9) {
      newPhoneError = "Must be exactly 9 digits";
    }

    setState(() {
      _nameError = newNameError;
      _phoneError = newPhoneError;
    });
  }

  Future<void> _saveChanges() async {
    _validateForm();
    if (_nameError != null || _phoneError != null) return;
    if (!_hasChanges()) return;

    setState(() => _isLoading = true);
    
    String formattedPhone = _phoneController.text.trim();
    if (formattedPhone.isNotEmpty && !formattedPhone.startsWith('+60')) {
       formattedPhone = '+60$formattedPhone';
    }

    final response = await AuthService.updateProfile(
      email: widget.email,
      fullName: _nameController.text.trim(),
      phoneNumber: formattedPhone,
      birthDate: _birthdayController.text,
      gender: _selectedGender,
    );

    if (mounted) {
      setState(() => _isLoading = false);
      if (response['success']) {
         await SessionService.saveSession(email: widget.email, name: _nameController.text.trim());
         _showTopToast('Profile updated successfully!', false);
         setState(() {
            _initialName = _nameController.text.trim();
            _initialPhone = _phoneController.text.trim();
            _initialBirthday = _birthdayController.text;
         });
      } else {
         _showTopToast(response['error'] ?? 'Update failed', true);
      }
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
      if (mounted) {
        setState(() => _toastMessage = null);
      }
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
      body: Stack(
        children: [
          _isLoading 
            ? const Center(child: CircularProgressIndicator()) 
            : _errorMessage != null 
              ? Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)))
              : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                     const Text(
                       'Edit Account Details',
                       style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                     ),
                     const SizedBox(height: 24),
                     _buildEditForm(),
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

  Widget _buildEditForm() {
    final bool canSave = _hasChanges() && _nameError == null && _phoneError == null;
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Email (Disabled)
          Row(
            children: [
              const Text('Email Address', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
              const SizedBox(width: 6),
              Icon(Icons.lock_outline, size: 14, color: Colors.grey.shade500),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: TextEditingController(text: widget.email),
            enabled: false,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFFF1F5F9), // Gray background
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
              disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          const SizedBox(height: 6),
          Text('Email address cannot be changed.', style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
          const SizedBox(height: 24),

          // Full Name
          const Text('Full Name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            onChanged: (val) {
               _validateForm();
               setState(() {});
            },
            style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
            decoration: InputDecoration(
              errorText: _nameError,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF0C5AD2))),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          const SizedBox(height: 24),

          // Phone Number
          const Text('Phone Number', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(8), bottomLeft: Radius.circular(8)),
                ),
                child: const Text('+60', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF0C5AD2))),
              ),
              Expanded(
                child: TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  onChanged: (val) {
                     _validateForm();
                     setState(() {});
                  },
                  style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
                  decoration: InputDecoration(
                    errorText: _phoneError,
                    border: OutlineInputBorder(borderRadius: const BorderRadius.only(topRight: Radius.circular(8), bottomRight: Radius.circular(8)), borderSide: BorderSide(color: Colors.grey.shade300)),
                    enabledBorder: OutlineInputBorder(borderRadius: const BorderRadius.only(topRight: Radius.circular(8), bottomRight: Radius.circular(8)), borderSide: BorderSide(color: Colors.grey.shade300)),
                    focusedBorder: OutlineInputBorder(borderRadius: const BorderRadius.only(topRight: Radius.circular(8), bottomRight: Radius.circular(8)), borderSide: const BorderSide(color: Color(0xFF0C5AD2))),
                    errorBorder: OutlineInputBorder(borderRadius: const BorderRadius.only(topRight: Radius.circular(8), bottomRight: Radius.circular(8)), borderSide: const BorderSide(color: Colors.red)),
                    focusedErrorBorder: OutlineInputBorder(borderRadius: const BorderRadius.only(topRight: Radius.circular(8), bottomRight: Radius.circular(8)), borderSide: const BorderSide(color: Colors.red)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Birthday
          const Text('Birthday', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _selectDate(context),
            child: AbsorbPointer(
              child: TextField(
                controller: _birthdayController,
                style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
                decoration: InputDecoration(
                  suffixIcon: Icon(Icons.calendar_today_outlined, size: 20, color: Colors.grey.shade400),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Gender (Disabled)
          const Text('Gender', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: _selectedGender == 'Male' ? Colors.grey.shade400 : const Color(0xFFF1F5F9),
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text('Male', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _selectedGender == 'Male' ? Colors.white : Colors.grey.shade500)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: _selectedGender == 'Female' ? Colors.grey.shade400 : const Color(0xFFF1F5F9),
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text('Female', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _selectedGender == 'Female' ? Colors.white : Colors.grey.shade500)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Gender cannot be changed.', style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
          const SizedBox(height: 32),

          // Save Changes
          ElevatedButton.icon(
            onPressed: canSave ? _saveChanges : null,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('SAVE CHANGES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0C5AD2),
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
              disabledForegroundColor: Colors.grey.shade500,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
          ),
          const SizedBox(height: 24),

          // Change Password
          ElevatedButton.icon(
            onPressed: () {
               if (_loginMethod != 'Email') {
                  setState(() {
                     _toastMessage = "You logged in with $_loginMethod. Password change disabled.";
                     _isToastError = true;
                  });
                  Future.delayed(const Duration(seconds: 3), () {
                     if (mounted) setState(() => _toastMessage = null);
                  });
               } else {
                  _showChangePasswordDialog();
               }
            },
            icon: const Icon(Icons.lock_reset, size: 18),
            label: const Text('CHANGE PASSWORD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _loginMethod != 'Email' ? Colors.grey.shade300 : const Color(0xFFD6E4FA),
              foregroundColor: _loginMethod != 'Email' ? Colors.grey.shade500 : const Color(0xFF0C5AD2),
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog() {
    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;

    final currentPwController = TextEditingController();
    final newPwController = TextEditingController();
    final confirmPwController = TextEditingController();

    String? currentPwError;
    String? newPwError;
    String? confirmPwError;
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void validateNewPassword(String value) {
              if (value.isEmpty) newPwError = 'Please enter a password';
              else if (value.length < 8) newPwError = 'Password must be at least 8 characters';
              else if (!value.contains(RegExp(r'[A-Z]'))) newPwError = 'Password must contain at least 1 uppercase letter';
              else if (!value.contains(RegExp(r'[a-z]'))) newPwError = 'Password must contain at least 1 lowercase letter';
              else if (!value.contains(RegExp(r'[0-9]'))) newPwError = 'Password must contain at least 1 number';
              else if (!value.contains(RegExp(r'[!@#\$%\^&\*(),.?":{}|<>]'))) newPwError = 'Password must contain at least 1 special character';
              else newPwError = null;

              if (confirmPwController.text.isNotEmpty) {
                if (confirmPwController.text != value) confirmPwError = 'Passwords do not match';
                else confirmPwError = null;
              }
              setDialogState(() {});
            }

            void validateConfirmPassword(String value) {
              if (value.isEmpty) confirmPwError = 'Please confirm your password';
              else if (value != newPwController.text) confirmPwError = 'Passwords do not match';
              else confirmPwError = null;
              setDialogState(() {});
            }

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Change Password', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                      const SizedBox(height: 8),
                      const Text('Secure your account by updating your password constraints.', style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                      const SizedBox(height: 24),

                      // Current Password
                      const Text('Current Password', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                      const SizedBox(height: 8),
                      TextField(
                        controller: currentPwController,
                        obscureText: obscureCurrent,
                        decoration: InputDecoration(
                          hintText: 'Enter current password',
                          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                          errorText: currentPwError,
                          prefixIcon: Icon(Icons.lock_outline, color: Colors.grey.shade500, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(obscureCurrent ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.grey.shade500, size: 20),
                            onPressed: () => setDialogState(() => obscureCurrent = !obscureCurrent),
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onChanged: (v) {
                          if (currentPwError != null) setDialogState(() => currentPwError = null);
                        },
                      ),
                      const SizedBox(height: 16),

                      // New Password
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('New Password', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                          GestureDetector(
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (context) => Dialog(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  child: Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text('PASSWORD REQUIREMENTS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                                            GestureDetector(
                                              onTap: () => Navigator.pop(context),
                                              child: const Icon(Icons.close, size: 20, color: Color(0xFF64748B)),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        _buildRequirementRow(Icons.circle, 'At least 8 characters', false),
                                        const SizedBox(height: 8),
                                        _buildRequirementRow(Icons.circle, 'One uppercase letter', false),
                                        const SizedBox(height: 8),
                                        _buildRequirementRow(Icons.circle, 'One lowercase letter', false),
                                        const SizedBox(height: 8),
                                        _buildRequirementRow(Icons.circle, 'One number (0-9)', false),
                                        const SizedBox(height: 8),
                                        _buildRequirementRow(Icons.circle, 'One special character (!@#\$%^&*)', false),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                            child: const Icon(Icons.help_outline, size: 16, color: Color(0xFF0C5AD2)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: newPwController,
                        obscureText: obscureNew,
                        decoration: InputDecoration(
                          hintText: 'Create a strong password',
                          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                          errorText: newPwError,
                          errorMaxLines: 2,
                          prefixIcon: Icon(Icons.lock_outline, color: Colors.grey.shade500, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.grey.shade500, size: 20),
                            onPressed: () => setDialogState(() => obscureNew = !obscureNew),
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onChanged: validateNewPassword,
                      ),
                      const SizedBox(height: 16),

                      // Confirm Password
                      const Text('Confirm New Password', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                      const SizedBox(height: 8),
                      TextField(
                        controller: confirmPwController,
                        obscureText: obscureConfirm,
                        decoration: InputDecoration(
                          hintText: 'Re-enter new password',
                          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                          errorText: confirmPwError,
                          prefixIcon: Icon(Icons.lock_outline, color: Colors.grey.shade500, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.grey.shade500, size: 20),
                            onPressed: () => setDialogState(() => obscureConfirm = !obscureConfirm),
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onChanged: validateConfirmPassword,
                      ),
                      const SizedBox(height: 32),

                      // Actions
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isSubmitting ? null : () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                side: BorderSide(color: Colors.grey.shade300),
                              ),
                              child: const Text('CANCEL', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold, fontSize: 13)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: isSubmitting ? null : () async {
                                if (currentPwController.text.isEmpty) {
                                  setDialogState(() => currentPwError = 'Please enter current password');
                                  return;
                                }
                                validateNewPassword(newPwController.text);
                                validateConfirmPassword(confirmPwController.text);

                                if (newPwController.text == currentPwController.text && newPwController.text.isNotEmpty) {
                                  setDialogState(() => newPwError = 'New password cannot be the same as current password');
                                }

                                if (currentPwError == null && newPwError == null && confirmPwError == null) {
                                  setDialogState(() => isSubmitting = true);
                                  
                                  final response = await AuthService.changePassword(
                                    email: widget.email,
                                    currentPassword: currentPwController.text,
                                    newPassword: newPwController.text,
                                  );

                                  if (!mounted) return;
                                  
                                  if (response['success']) {
                                    Navigator.pop(context);
                                    setState(() {
                                      _toastMessage = "Password successfully changed!";
                                      _isToastError = false;
                                    });
                                    Future.delayed(const Duration(seconds: 3), () {
                                      if (mounted) setState(() => _toastMessage = null);
                                    });
                                  } else {
                                    setDialogState(() {
                                      currentPwError = response['error'];
                                      isSubmitting = false;
                                    });
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0C5AD2),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                elevation: 0,
                              ),
                              child: isSubmitting 
                                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Text('SAVE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRequirementRow(IconData icon, String text, bool isMet) {
    return Row(
      children: [
        Icon(icon, size: (icon == Icons.circle) ? 6 : 16, color: isMet ? Colors.green : const Color(0xFF475569)),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(fontSize: 13, color: isMet ? const Color(0xFF1E293B) : const Color(0xFF475569))),
      ],
    );
  }
}
