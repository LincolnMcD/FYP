import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../account_management_module/services/auth_service.dart';
import '../account_management_module/services/session_service.dart';

class StaffEditProfilePage extends StatefulWidget {
  final String email;
  const StaffEditProfilePage({super.key, required this.email});

  @override
  State<StaffEditProfilePage> createState() => _StaffEditProfilePageState();
}

class _StaffEditProfilePageState extends State<StaffEditProfilePage> {
  static const _blue = Color(0xFF0C5AD2);
  static const _brands = ['Apple', 'Samsung', 'Xiaomi', 'Huawei', 'Oppo', 'Vivo', 'Google Pixel', 'OnePlus'];
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _staffId = '';
  String _position = 'Inspector';
  String _loginMethod = 'Email';
  List<String> _specializations = [];
  Map<String, dynamic> _profile = {};
  Map<String, dynamic> _initial = {};
  String? _nameError;
  String? _phoneError;
  String? _specializationError;
  String? _toast;
  bool _toastError = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final response = await AuthService.getStaffProfile();
    if (!mounted) return;
    if (response['success'] != true) {
      setState(() { _loading = false; _error = response['error'] ?? 'Could not load staff profile.'; });
      return;
    }
    final data = Map<String, dynamic>.from(response['data'] as Map);
    final position = ['Inspector', 'Deliverer', 'Both'].contains(data['position']) ? data['position'] as String : 'Inspector';
    final phone = (data['phoneNumber'] ?? '').toString().replaceFirst(RegExp(r'^\+60'), '').replaceAll(RegExp(r'\D'), '');
    setState(() {
      _profile = data;
      _staffId = (data['staffNo'] ?? data['staffId'] ?? '').toString();
      _loginMethod = (data['loginMethod'] ?? 'Email').toString();
      _position = position;
      final savedSpecializations = data['specialization'] is List
          ? List<String>.from(data['specialization'])
          : data['specialization'] is String && (data['specialization'] as String).isNotEmpty
              ? [data['specialization'] as String]
              : <String>[];
      _specializations = savedSpecializations.where(_brands.contains).take(3).toList();
      _nameController.text = (data['fullName'] ?? '').toString();
      _phoneController.text = phone;
      _initial = _currentValues();
      _loading = false;
    });
  }

  Map<String, dynamic> _currentValues() => {
    'fullName': _nameController.text.trim(),
    'phone': _phoneController.text.trim(),
    'position': _position,
    'specialization': List<String>.from(_specializations),
  };

  bool _validate({bool reveal = true}) {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    String? nameError;
    String? phoneError;
    String? specializationError;
    if (name.isEmpty) nameError = 'Full name is required';
    else if (!RegExp(r'^[A-Za-z]+(?:\s+[A-Za-z]+)*$').hasMatch(name)) nameError = 'Only alphabetic characters and spaces allowed';
    if (phone.isEmpty) phoneError = 'Phone number is required';
    else if (!phone.startsWith('1')) phoneError = 'Must start with 1';
    else if (phone.startsWith('11') && phone.length != 10) phoneError = 'Must be exactly 10 digits';
    else if (!phone.startsWith('11') && phone.length != 9) phoneError = 'Must be exactly 9 digits';
    if (_position != 'Deliverer' && (_specializations.length < 1 || _specializations.length > 3)) {
      specializationError = 'Select 1 to 3 specializations for Inspector.';
    }
    if (reveal) setState(() { _nameError = nameError; _phoneError = phoneError; _specializationError = specializationError; });
    return nameError == null && phoneError == null && specializationError == null;
  }

  bool get _hasChanges {
    final now = _currentValues();
    return now['fullName'] != _initial['fullName'] || now['phone'] != _initial['phone'] || now['position'] != _initial['position'] ||
      !_sameList(now['specialization'] as List<String>, _initial['specialization'] as List<String>);
  }

  bool _sameList(List<String> a, List<String> b) => a.length == b.length && a.toSet().containsAll(b);

  Future<void> _save() async {
    if (!_validate()) return;
    if (!_hasChanges) return;
    setState(() => _saving = true);
    final response = await AuthService.updateStaffProfile(
      fullName: _nameController.text.trim(),
      phoneNumber: '+60${_phoneController.text.trim()}',
      position: _position,
      specialization: _position == 'Deliverer' ? [] : _specializations,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (response['success'] == true) {
      await SessionService.saveSession(email: widget.email, name: _nameController.text.trim(), role: 'Staff');
      setState(() { _profile = {..._profile, ...(response['data'] as Map? ?? {})}; _initial = _currentValues(); });
      _showToast('Profile updated successfully!', false);
    } else {
      _showToast(response['error'] ?? 'Could not update staff profile.', true);
    }
  }

  void _showToast(String message, bool isError) {
    setState(() { _toast = message; _toastError = isError; });
    Future.delayed(const Duration(seconds: 3), () { if (mounted) setState(() => _toast = null); });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0, foregroundColor: const Color(0xFF0F172A),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        title: Row(mainAxisSize: MainAxisSize.min, children: [Image.asset('assets/images/rebyte_logo.png', height: 32), const SizedBox(width: 8), const Text('ReByte', style: TextStyle(fontWeight: FontWeight.bold))]),
        centerTitle: true,
      ),
      body: Stack(children: [
        _loading ? const Center(child: CircularProgressIndicator()) : _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: Colors.red))) )
          : SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 32), child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: _buildForm())))),
        if (_toast != null) Positioned(top: 12, left: 16, right: 16, child: Material(color: Colors.transparent, child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: _toastError ? Colors.red.shade600 : Colors.green.shade600, borderRadius: BorderRadius.circular(12)), child: Row(children: [Icon(_toastError ? Icons.error_outline : Icons.check_circle_outline, color: Colors.white), const SizedBox(width: 12), Expanded(child: Text(_toast!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)))]))))
      ]),
    );
  }

  Widget _buildForm() {
    final canSave = _hasChanges && _validate(reveal: false) && !_saving;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200), boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 12, offset: Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Edit Account Details', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
        const SizedBox(height: 18),
        _label('Staff ID'), _lockedField(_staffId.isEmpty ? '—' : _staffId, 'Staff ID cannot be changed.'),
        const SizedBox(height: 20), _label('Email Address'), _lockedField(widget.email, 'Email address cannot be changed.'),
        const SizedBox(height: 20), _label('Full Name'),
        TextField(controller: _nameController, inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z ]'))], onChanged: (_) { _validate(); setState(() {}); }, decoration: _inputDecoration(error: _nameError)),
        const SizedBox(height: 20), _label('Phone Number'),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(height: 52, padding: const EdgeInsets.symmetric(horizontal: 16), alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFFF1F5F9), border: Border.all(color: Colors.grey.shade300), borderRadius: const BorderRadius.horizontal(left: Radius.circular(8))), child: const Text('+60', style: TextStyle(color: Color(0xFF475569)))), Expanded(child: TextField(controller: _phoneController, keyboardType: TextInputType.phone, inputFormatters: [FilteringTextInputFormatter.digitsOnly], onChanged: (_) { _validate(); setState(() {}); }, decoration: _inputDecoration(error: _phoneError, joined: true)))]),
        const SizedBox(height: 20), _label('Position'),
        DropdownButtonFormField<String>(value: _position, decoration: _inputDecoration(), items: const [DropdownMenuItem(value: 'Inspector', child: Text('Inspector')), DropdownMenuItem(value: 'Deliverer', child: Text('Deliverer')), DropdownMenuItem(value: 'Both', child: Text('Inspector & Deliverer'))], onChanged: (value) { if (value == null) return; setState(() { _position = value; if (value == 'Deliverer') { _specializations = []; _specializationError = null; } }); _validate(); }),
        const SizedBox(height: 20), _label('Device Specialization', helper: _position == 'Deliverer' ? 'Not required' : '${_specializations.length} selected'),
        Opacity(opacity: _position == 'Deliverer' ? .55 : 1, child: IgnorePointer(ignoring: _position == 'Deliverer', child: Wrap(spacing: 8, runSpacing: 8, children: _brands.map((brand) => FilterChip(label: Text(brand), selected: _specializations.contains(brand), onSelected: (selected) { setState(() { if (selected && _specializations.length < 3) _specializations.add(brand); else if (!selected) _specializations.remove(brand); }); _validate(); }, selectedColor: const Color(0xFFE0EAFF), checkmarkColor: _blue)).toList()))),
        if (_position == 'Deliverer') Padding(padding: const EdgeInsets.only(top: 6), child: Text('Device specialization is not available for Deliverers.', style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500)))
        else Padding(padding: const EdgeInsets.only(top: 6), child: Text(_specializationError ?? 'Select 1 to 3 specializations for Inspector.', style: TextStyle(color: _specializationError == null ? Colors.grey.shade600 : Colors.red, fontSize: 11))),
        const SizedBox(height: 30),
        ElevatedButton.icon(onPressed: canSave ? _save : null, icon: _saving ? const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white)) : const Icon(Icons.save_outlined,size:18), label: Text(_saving ? 'SAVING...' : 'SAVE CHANGES', style: const TextStyle(fontWeight: FontWeight.bold,fontSize:13)), style: ElevatedButton.styleFrom(backgroundColor:_blue,foregroundColor:Colors.white,disabledBackgroundColor:Colors.grey.shade300,disabledForegroundColor:Colors.grey.shade500,minimumSize:const Size(double.infinity,50),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(8)),elevation:0)),
        const SizedBox(height: 14),
        ElevatedButton.icon(onPressed: _loginMethod == 'Email' ? _showChangePasswordDialog : () => _showToast('Password changes are unavailable for $_loginMethod accounts.', true), icon: const Icon(Icons.lock_reset,size:18), label: const Text('CHANGE PASSWORD',style:TextStyle(fontWeight:FontWeight.bold,fontSize:13)), style: ElevatedButton.styleFrom(backgroundColor:_loginMethod == 'Email' ? const Color(0xFFD6E4FA) : Colors.grey.shade300,foregroundColor:_loginMethod == 'Email' ? const Color(0xFF0C5AD2) : Colors.grey.shade500,minimumSize:const Size(double.infinity,50),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(8)),elevation:0)),
      ]),
    );
  }

  Widget _label(String value, {String? helper}) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [Expanded(child: Text(value, style: const TextStyle(fontSize: 12,fontWeight:FontWeight.bold,color:Color(0xFF475569)))), if (helper != null) Text(helper, style: const TextStyle(fontSize: 11,color:Color(0xFF64748B)))]));
  Widget _lockedField(String value, String help) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [TextFormField(initialValue:value, enabled:false, style:TextStyle(color:Colors.grey.shade600,fontSize:14), decoration:_inputDecoration(disabled:true)), const SizedBox(height:6), Text(help,style:TextStyle(fontSize:11,color:Colors.grey.shade600,fontWeight:FontWeight.w500))]);
  InputDecoration _inputDecoration({String? error, bool disabled = false, bool joined = false}) => InputDecoration(errorText:error,filled:disabled,fillColor:const Color(0xFFF1F5F9),contentPadding:const EdgeInsets.symmetric(horizontal:16,vertical:14),border:OutlineInputBorder(borderRadius:BorderRadius.circular(8),borderSide:BorderSide(color:Colors.grey.shade300)),enabledBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(8),borderSide:BorderSide(color:Colors.grey.shade300)),focusedBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(8),borderSide:const BorderSide(color:_blue)),disabledBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(8),borderSide:BorderSide(color:Colors.grey.shade300)),errorBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(8),borderSide:const BorderSide(color:Colors.red)),suffixIcon: disabled ? const Icon(Icons.lock_outline,size:16,color:Color(0xFF94A3B8)) : null);

  void _showChangePasswordDialog() {
    // Keep the controllers alive with this page. The dialog route can still be
    // animating out after showDialog completes, so disposing them there can
    // invalidate TextFields while Flutter is deactivating their inherited
    // dependencies.
    final current = _currentPasswordController..clear();
    final next = _newPasswordController..clear();
    final confirm = _confirmPasswordController..clear();
    String? currentError, nextError, confirmError;
    bool obscureCurrent = true, obscureNext = true, obscureConfirm = true, submitting = false;
    showDialog<void>(context: context, barrierDismissible: false, builder: (dialogContext) => StatefulBuilder(builder: (context, setDialogState) {
      String? validatePassword(String value) {
        if (value.isEmpty) return 'Please enter a password';
        if (value.length < 8) return 'Password must be at least 8 characters';
        if (!value.contains(RegExp(r'[A-Z]'))) return 'Password must contain an uppercase letter';
        if (!value.contains(RegExp(r'[a-z]'))) return 'Password must contain a lowercase letter';
        if (!value.contains(RegExp(r'[0-9]'))) return 'Password must contain a number';
        if (!value.contains(RegExp(r'[!@#\$%\^&\*(),.?":{}|<>]'))) return 'Password must contain a special character';
        return null;
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
                _passwordInput('Current Password', current, obscureCurrent, currentError, 'Enter current password', () => setDialogState(() => obscureCurrent = !obscureCurrent), (value) => setDialogState(() => currentError = null)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('New Password', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                    GestureDetector(
                      onTap: () => showDialog(
                        context: context,
                        builder: (requirementsContext) => Dialog(
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
                                    GestureDetector(onTap: () => Navigator.pop(requirementsContext), child: const Icon(Icons.close, size: 20, color: Color(0xFF64748B))),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _buildRequirementRow('At least 8 characters'),
                                const SizedBox(height: 8),
                                _buildRequirementRow('One uppercase letter'),
                                const SizedBox(height: 8),
                                _buildRequirementRow('One lowercase letter'),
                                const SizedBox(height: 8),
                                _buildRequirementRow('One number (0-9)'),
                                const SizedBox(height: 8),
                                _buildRequirementRow('One special character (!@#\$%^&*)'),
                              ],
                            ),
                          ),
                        ),
                      ),
                      child: const Icon(Icons.help_outline, size: 16, color: Color(0xFF0C5AD2)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _passwordInput('', next, obscureNext, nextError, 'Create a strong password', () => setDialogState(() => obscureNext = !obscureNext), (value) => setDialogState(() {
                  nextError = validatePassword(value);
                  if (confirm.text.isNotEmpty) confirmError = confirm.text != value ? 'Passwords do not match' : null;
                }), errorMaxLines: 2, showLabel: false),
                const SizedBox(height: 16),
                _passwordInput('Confirm New Password', confirm, obscureConfirm, confirmError, 'Re-enter new password', () => setDialogState(() => obscureConfirm = !obscureConfirm), (value) => setDialogState(() => confirmError = value.isEmpty ? 'Please confirm your password' : value != next.text ? 'Passwords do not match' : null)),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: submitting ? null : () => Navigator.pop(dialogContext),
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
                        onPressed: submitting ? null : () async {
                          currentError = current.text.isEmpty ? 'Please enter current password' : null;
                          nextError = validatePassword(next.text);
                          confirmError = confirm.text.isEmpty ? 'Please confirm your password' : confirm.text != next.text ? 'Passwords do not match' : null;
                          setDialogState(() {});
                          if (currentError != null || nextError != null || confirmError != null) return;

                          setDialogState(() { submitting = true; });
                          final response = await AuthService.changePassword(email: widget.email, currentPassword: current.text, newPassword: next.text);
                          if (!mounted) return;
                          if (response['success'] == true) {
                            Navigator.pop(dialogContext);
                            _showToast('Password successfully changed!', false);
                          } else {
                            setDialogState(() {
                              final error = response['error'] ?? 'Could not change password';
                              if (error.toLowerCase().contains('same as current')) {
                                nextError = error;
                              } else {
                                currentError = error;
                              }
                              submitting = false;
                            });
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0C5AD2),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                        child: submitting
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
    }));
  }

  Widget _passwordInput(
    String label,
    TextEditingController controller,
    bool obscure,
    String? error,
    String hint,
    VoidCallback toggle,
    ValueChanged<String> changed, {
    int? errorMaxLines,
    bool showLabel = true,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (showLabel) Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
      if (showLabel) const SizedBox(height: 8),
      TextField(
        controller: controller,
        obscureText: obscure,
        onChanged: changed,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          errorText: error,
          errorMaxLines: errorMaxLines,
          prefixIcon: Icon(Icons.lock_outline, color: Colors.grey.shade500, size: 20),
          suffixIcon: IconButton(
            icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.grey.shade500, size: 20),
            onPressed: toggle,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    ],
  );

  Widget _buildRequirementRow(String text) => Row(
    children: [
      const Icon(Icons.circle, size: 6, color: Color(0xFF475569)),
      const SizedBox(width: 8),
      Text(text, style: const TextStyle(fontSize: 13, color: Color(0xFF475569))),
    ],
  );
}
