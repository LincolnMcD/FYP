import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../account_management_module/services/session_service.dart';
import '../task_assignment_module/services/task_assignment_service.dart';

class StaffLeaveApplicationPage extends StatefulWidget {
  final String? email;
  final String? staffID;

  const StaffLeaveApplicationPage({
    super.key,
    this.email,
    this.staffID,
  });

  @override
  State<StaffLeaveApplicationPage> createState() => _StaffLeaveApplicationPageState();
}

class _StaffLeaveApplicationPageState extends State<StaffLeaveApplicationPage> {
  int _activeTopTab = 0; // 0: My Applications, 1: Apply Leave
  int _activeFilterIndex = 0; // 0: All, 1: Pending, 2: Approved, 3: Rejected

  String? _effectiveEmail;
  String? _effectiveStaffID;

  // Leave balances
  int _annualRemaining = 12;
  int _medicalRemaining = 14;
  bool _isLoadingData = true;
  bool _isSubmitting = false;

  // Toast state
  String? _toastMessage;
  bool _isToastError = false;

  void _showToast(String message, [bool isError = false]) {
    if (!mounted) return;
    setState(() {
      _toastMessage = message;
      _isToastError = isError;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _toastMessage == message) {
        setState(() => _toastMessage = null);
      }
    });
  }

  // Form Fields
  // Allowed types: only Annual Leave, Medical Leave, and Unpaid Leave
  String _selectedLeaveType = 'Annual Leave';
  DateTime? _startDate;
  DateTime? _endDate;
  final TextEditingController _reasonController = TextEditingController();

  File? _supportingDocFile;
  String? _supportingDocFileName;
  final ImagePicker _picker = ImagePicker();

  List<Map<String, dynamic>> _applications = [];

  @override
  void initState() {
    super.initState();
    _effectiveEmail = widget.email;
    _effectiveStaffID = widget.staffID;
    _reasonController.addListener(() {
      if (mounted) setState(() {});
    });
    _initializeData();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    if ((_effectiveEmail == null || _effectiveEmail!.isEmpty) ||
        (_effectiveStaffID == null || _effectiveStaffID!.isEmpty)) {
      final session = await SessionService.getSession();
      if (session.isNotEmpty) {
        _effectiveEmail ??= session['email'];
      }
    }
    await _loadBalancesAndApplications();
  }

  Future<void> _loadBalancesAndApplications() async {
    setState(() => _isLoadingData = true);
    try {
      final balanceFuture = TaskAssignmentService.fetchLeaveBalance(
        staffID: _effectiveStaffID,
        email: _effectiveEmail,
      );
      final appsFuture = TaskAssignmentService.fetchLeaveApplications(
        staffID: _effectiveStaffID,
        email: _effectiveEmail,
      );

      final results = await Future.wait([balanceFuture, appsFuture]);
      final balanceData = results[0] as Map<String, dynamic>;
      final appsData = results[1] as List<Map<String, dynamic>>;

      if (mounted) {
        setState(() {
          _annualRemaining = balanceData['annualRemaining'] ?? 12;
          _medicalRemaining = balanceData['medicalRemaining'] ?? 14;
          if (balanceData['staffID'] != null) {
            _effectiveStaffID = balanceData['staffID'].toString();
          }
          _applications = appsData;
          _isLoadingData = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading leave data: $e');
      if (mounted) {
        setState(() => _isLoadingData = false);
      }
    }
  }

  int get _calculatedDuration {
    if (_startDate == null || _endDate == null) return 0;
    final diff = _endDate!.difference(_startDate!).inDays + 1;
    return diff > 0 ? diff : 0;
  }

  /// Parse DD/MM/YYYY into DateTime
  DateTime? _parseDisplayDate(String? dStr) {
    if (dStr == null || dStr.trim().isEmpty) return null;
    try {
      final parts = dStr.trim().split('/');
      if (parts.length == 3) {
        final d = int.parse(parts[0]);
        final m = int.parse(parts[1]);
        final y = int.parse(parts[2]);
        return DateTime(y, m, d);
      }
      return DateTime.tryParse(dStr);
    } catch (_) {
      return null;
    }
  }

  /// Check whether a selected date range overlaps with any active (Pending / Approved) application
  Map<String, dynamic>? _findDateOverlap(DateTime start, DateTime end) {
    final normStart = DateTime(start.year, start.month, start.day);
    final normEnd = DateTime(end.year, end.month, end.day);

    for (final app in _applications) {
      final status = (app['leaveStatus'] ?? '').toString().toUpperCase();
      if (status == 'PENDING' || status == 'APPROVED' || status == 'IN REQUEST' || status == 'REQUESTED') {
        final exStart = _parseDisplayDate(app['startDate']?.toString());
        final exEnd = _parseDisplayDate(app['endDate']?.toString());
        if (exStart != null && exEnd != null) {
          final normExStart = DateTime(exStart.year, exStart.month, exStart.day);
          final normExEnd = DateTime(exEnd.year, exEnd.month, exEnd.day);

          // Overlap condition: startA <= endB && endA >= startB
          if (!normStart.isAfter(normExEnd) && !normEnd.isBefore(normExStart)) {
            return app;
          }
        }
      }
    }
    return null;
  }

  /// Total days currently pending approval for Annual Leave
  int get _pendingAnnualDays {
    return _applications
        .where((a) =>
            a['leaveType'] == 'Annual Leave' &&
            (a['leaveStatus'] ?? '').toString().toUpperCase() == 'PENDING')
        .fold(0, (sum, a) => sum + (int.tryParse(a['daysCount']?.toString() ?? a['duration']?.toString() ?? '1') ?? 1));
  }

  /// Total days currently pending approval for Medical Leave
  int get _pendingMedicalDays {
    return _applications
        .where((a) =>
            a['leaveType'] == 'Medical Leave' &&
            (a['leaveStatus'] ?? '').toString().toUpperCase() == 'PENDING')
        .fold(0, (sum, a) => sum + (int.tryParse(a['daysCount']?.toString() ?? a['duration']?.toString() ?? '1') ?? 1));
  }

  /// Validate whether requested duration + pending requests exceed remaining balance
  bool _checkRequestedVsRemaining(DateTime start, DateTime end, String leaveType, {bool showDialogIfExceeded = false}) {
    final duration = end.difference(start).inDays + 1;
    if (duration <= 0) return true;

    if (leaveType == 'Annual Leave') {
      final totalRequested = _pendingAnnualDays + duration;
      if (totalRequested > _annualRemaining) {
        if (showDialogIfExceeded) {
          final available = (_annualRemaining - _pendingAnnualDays).clamp(0, _annualRemaining);
          _showErrorDialog(
            'Requested Days Exceed Remaining',
            'Requested Annual Leave cannot exceed your remaining balance ($totalRequested days requested vs $_annualRemaining days remaining).\n\nYou currently have $_pendingAnnualDays day(s) pending approval and can only request up to $available more day(s).',
          );
        }
        return false;
      }
    } else if (leaveType == 'Medical Leave') {
      final totalRequested = _pendingMedicalDays + duration;
      if (totalRequested > _medicalRemaining) {
        if (showDialogIfExceeded) {
          final available = (_medicalRemaining - _pendingMedicalDays).clamp(0, _medicalRemaining);
          _showErrorDialog(
            'Requested Days Exceed Remaining',
            'Requested Medical Leave cannot exceed your remaining balance ($totalRequested days requested vs $_medicalRemaining days remaining).\n\nYou currently have $_pendingMedicalDays day(s) pending approval and can only request up to $available more day(s).',
          );
        }
        return false;
      }
    }
    return true;
  }

  /// Check whether all required inputs are filled according to leave type
  bool get _isFormValid {
    // Both start and end dates are required
    if (_startDate == null || _endDate == null) return false;
    if (_endDate!.isBefore(_startDate!)) return false;

    // Reason & Attachment requirements per leave type
    if (_selectedLeaveType == 'Medical Leave') {
      // Reason and attachment are mandatory
      if (_reasonController.text.trim().isEmpty) return false;
      if (_supportingDocFile == null) return false;
    } else if (_selectedLeaveType == 'Unpaid Leave') {
      // Reason is mandatory, attachment is optional
      if (_reasonController.text.trim().isEmpty) return false;
    }
    // Annual Leave: reason & attachment are optional

    return true;
  }

  List<Map<String, dynamic>> get _filteredApplications {
    if (_activeFilterIndex == 1) {
      return _applications.where((a) => (a['leaveStatus'] ?? '').toString().toUpperCase() == 'PENDING').toList();
    } else if (_activeFilterIndex == 2) {
      return _applications.where((a) => (a['leaveStatus'] ?? '').toString().toUpperCase() == 'APPROVED').toList();
    } else if (_activeFilterIndex == 3) {
      return _applications.where((a) => (a['leaveStatus'] ?? '').toString().toUpperCase() == 'REJECTED').toList();
    } else if (_activeFilterIndex == 4) {
      return _applications.where((a) => (a['leaveStatus'] ?? '').toString().toUpperCase() == 'CANCELLED').toList();
    }
    return _applications;
  }

  Future<void> _pickAttachment() async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1600,
        maxHeight: 1600,
      );

      if (picked != null) {
        setState(() {
          _supportingDocFile = File(picked.path);
          _supportingDocFileName = picked.name;
        });
      }
    } catch (e) {
      debugPrint('Error picking attachment: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick document: $e')),
      );
    }
  }

  Future<void> _submitApplication() async {
    // 1. Validate dates selected
    if (_startDate == null || _endDate == null) {
      _showErrorDialog('Missing Dates', 'Please select both start and end dates.');
      return;
    }

    // 2. Start date limit until tomorrow (leave needs to be 1 day before)
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final selectedStartDay = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);

    if (selectedStartDay.isBefore(tomorrow)) {
      _showErrorDialog(
        'Invalid Start Date',
        'Leave application must be submitted at least 1 day in advance. The earliest start date allowed is tomorrow (${DateFormat("dd/MM/yyyy").format(tomorrow)}).',
      );
      return;
    }

    if (_endDate!.isBefore(_startDate!)) {
      _showErrorDialog('Invalid Date Range', 'End date cannot be earlier than start date.');
      return;
    }

    // Check if there is an overlapping application that is Pending or Approved
    final conflictApp = _findDateOverlap(_startDate!, _endDate!);
    if (conflictApp != null) {
      final conflictId = conflictApp['leaveID'] ?? '';
      final conflictDates = '${conflictApp['startDate']} - ${conflictApp['endDate']}';
      final conflictStatus = conflictApp['leaveStatus'] ?? 'Pending';
      _showErrorDialog(
        'Application Rejected',
        'You already have an active leave application ($conflictId: $conflictDates, Status: $conflictStatus) covering the selected date(s). Applications with the same date cannot be submitted.',
      );
      return;
    }

    final duration = _calculatedDuration;
    if (duration <= 0) {
      _showErrorDialog('Invalid Duration', 'Please select a valid date range.');
      return;
    }

    // 3. Validate leave rules per leave type:
    // Medical: reason and attachment are necessary
    if (_selectedLeaveType == 'Medical Leave') {
      if (_reasonController.text.trim().isEmpty) {
        _showErrorDialog('Reason Required', 'Please provide a reason for Medical Leave.');
        return;
      }
      if (_supportingDocFile == null) {
        _showErrorDialog(
          'Attachment Required',
          'A supporting document (e.g. Medical Certificate / MC) is mandatory for Medical Leave.',
        );
        return;
      }
    }

    // Unpaid: reason is necessary, attachment is optional
    if (_selectedLeaveType == 'Unpaid Leave') {
      if (_reasonController.text.trim().isEmpty) {
        _showErrorDialog('Reason Required', 'Please provide a reason for Unpaid Leave.');
        return;
      }
    }

    // Annual: reason and notes are optional

    // 4. Balance check: total requested (pending + current) cannot exceed remaining leave
    if (_selectedLeaveType == 'Annual Leave') {
      final totalRequested = _pendingAnnualDays + duration;
      if (totalRequested > _annualRemaining) {
        final available = (_annualRemaining - _pendingAnnualDays).clamp(0, _annualRemaining);
        _showErrorDialog(
          'Insufficient Annual Leave',
          'Total requested Annual Leave ($totalRequested days: $_pendingAnnualDays pending + $duration applied) cannot exceed your remaining balance of $_annualRemaining day(s).\n\nYou can only request up to $available more day(s).',
        );
        return;
      }
    } else if (_selectedLeaveType == 'Medical Leave') {
      final totalRequested = _pendingMedicalDays + duration;
      if (totalRequested > _medicalRemaining) {
        final available = (_medicalRemaining - _pendingMedicalDays).clamp(0, _medicalRemaining);
        _showErrorDialog(
          'Insufficient Medical Leave',
          'Total requested Medical Leave ($totalRequested days: $_pendingMedicalDays pending + $duration applied) cannot exceed your remaining balance of $_medicalRemaining day(s).\n\nYou can only request up to $available more day(s).',
        );
        return;
      }
    }

    // Submit to Firebase via backend
    setState(() => _isSubmitting = true);

    final startDisplayStr = DateFormat('dd/MM/yyyy').format(_startDate!);
    final endDisplayStr = DateFormat('dd/MM/yyyy').format(_endDate!);

    final result = await TaskAssignmentService.submitLeaveApplication(
      applicantStaffID: _effectiveStaffID ?? '',
      email: _effectiveEmail,
      leaveType: _selectedLeaveType,
      startDate: startDisplayStr,
      endDate: endDisplayStr,
      days: duration,
      reason: _reasonController.text.trim(),
      supportingDocFilePath: _supportingDocFile?.path,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result['success'] == true) {
      // Pop up success and wait for approve and review
      _showSuccessDialog();

      // Reset form fields
      setState(() {
        _startDate = null;
        _endDate = null;
        _reasonController.clear();
        _supportingDocFile = null;
        _supportingDocFileName = null;
        _activeTopTab = 0; // Switch to My Applications tab
      });

      // Refresh applications and updated balances
      _loadBalancesAndApplications();
    } else {
      _showErrorDialog(
        'Submission Failed',
        result['error']?.toString() ?? 'Unable to submit leave application. Please try again.',
      );
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 6,
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Red Alert Warning Icon Container
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFE4E6),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFBE123C),
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF64748B),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0C5AD2),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text(
                    'OK',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 6,
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Green Checkmark Circular Container
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: Color(0xFFECFDF5),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF10B981),
                    size: 32,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Application Submitted',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your leave application has been submitted successfully.\n\nPlease wait for manager approval and review.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF64748B),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0C5AD2),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text(
                    'Got It',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _cancelApplication(String leaveID) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 6,
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Rose/Red Circular Warning Container
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFE4E6),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.delete_outline_rounded,
                    color: Color(0xFFBE123C),
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Cancel Leave Request',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 8),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                    height: 1.4,
                  ),
                  children: [
                    const TextSpan(text: 'Are you sure you want to cancel request '),
                    TextSpan(
                      text: '#$leaveID',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const TextSpan(text: '? The status of this request will be changed to Cancelled.'),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text(
                        'Keep Request',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE11D48),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text(
                        'Yes, Cancel',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true) {
      final res = await TaskAssignmentService.cancelLeaveApplication(leaveID);
      if (!mounted) return;
      if (res['success'] == true) {
        _showToast('Leave request #$leaveID has been cancelled successfully.');
        _loadBalancesAndApplications();
      } else {
        _showToast(res['message'] ?? 'Failed to cancel application.', true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A), size: 24),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/rebyte_logo.png', height: 28),
            const SizedBox(width: 8),
            const Text(
              'ReByte',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w900,
                fontSize: 22,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: Colors.grey.shade200,
              child: Icon(Icons.person, color: Colors.grey.shade600, size: 20),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            color: const Color(0xFF0C5AD2),
            onRefresh: _loadBalancesAndApplications,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Balance Cards: Annual (Initial 12) | Medical (Initial 14) stored in staff 'leave' field
                  _buildBalanceCards(),
                  const SizedBox(height: 18),

                  // Top Tab Switcher: My Applications | Apply Leave
                  _buildTopTabs(),
                  const SizedBox(height: 20),

                  if (_activeTopTab == 0) ...[
                    // Filters: All | Pending | Approved | Rejected
                    _buildFilterChips(),
                    const SizedBox(height: 20),
                    // Applications List
                    _buildApplicationsList(),
                  ] else ...[
                    // Apply Leave Form
                    _buildApplyLeaveForm(),
                  ],
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),

          // Top Floating Toast Banner
          if (_toastMessage != null)
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _isToastError ? const Color(0xFFE11D48) : const Color(0xFF10B981),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isToastError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _toastMessage!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _toastMessage = null),
                        child: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopTabs() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _activeTopTab = 0),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _activeTopTab == 0 ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: _activeTopTab == 0
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                child: Center(
                  child: Text(
                    'My Applications',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: _activeTopTab == 0 ? const Color(0xFF0C5AD2) : const Color(0xFF475569),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _activeTopTab = 1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _activeTopTab == 1 ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: _activeTopTab == 1
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                child: Center(
                  child: Text(
                    'Apply Leave',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: _activeTopTab == 1 ? const Color(0xFF0C5AD2) : const Color(0xFF475569),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    final filters = ['All', 'Pending', 'Approved', 'Rejected', 'Cancelled'];

    return Row(
      children: List.generate(filters.length, (index) {
        final isSelected = _activeFilterIndex == index;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _activeFilterIndex = index),
            child: Container(
              margin: EdgeInsets.only(right: index < filters.length - 1 ? 6 : 0),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF0C5AD2) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? const Color(0xFF0C5AD2) : const Color(0xFFE2E8F0),
                ),
              ),
              child: Center(
                child: Text(
                  filters[index],
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.white : const Color(0xFF475569),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildApplicationsList() {
    if (_isLoadingData) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 60),
        alignment: Alignment.center,
        child: const CircularProgressIndicator(color: Color(0xFF0C5AD2)),
      );
    }

    final list = _filteredApplications;

    if (list.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 60),
        alignment: Alignment.center,
        child: Column(
          children: [
            Icon(Icons.event_busy_outlined, size: 50, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'No applications found',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return Column(
      children: list.map((item) {
        final leaveId = (item['leaveID'] ?? item['id'] ?? '').toString();
        final status = (item['leaveStatus'] ?? item['status'] ?? 'Pending').toString().toUpperCase();
        final leaveType = (item['leaveType'] ?? item['title'] ?? 'Leave').toString();
        final startDisplay = (item['startDate'] ?? '').toString();
        final endDisplay = (item['endDate'] ?? '').toString();
        final days = item['duration'] ?? item['daysCount'] ?? item['days'] ?? 1;
        final reason = (item['reason'] ?? '').toString();
        final docUrl = (item['suportingDocUrl'] ?? item['supportingDocUrl'] ?? '').toString();

        Color badgeBg = const Color(0xFFEFF6FF);
        Color badgeColor = const Color(0xFF2563EB);
        IconData badgeIcon = Icons.hourglass_top_rounded;

        if (status == 'APPROVED') {
          badgeBg = const Color(0xFFECFDF5);
          badgeColor = const Color(0xFF10B981);
          badgeIcon = Icons.check_circle_outline;
        } else if (status == 'REJECTED') {
          badgeBg = const Color(0xFFFEF2F2);
          badgeColor = const Color(0xFFEF4444);
          badgeIcon = Icons.cancel_outlined;
        } else if (status == 'CANCELLED') {
          badgeBg = const Color(0xFFF1F5F9);
          badgeColor = const Color(0xFF64748B);
          badgeIcon = Icons.block_rounded;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        leaveType,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      if (leaveId.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          '($leaveId)',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(badgeIcon, size: 12, color: badgeColor),
                        const SizedBox(width: 4),
                        Text(
                          status,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: badgeColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.calendar_today_outlined, size: 14, color: Color(0xFF64748B)),
                  const SizedBox(width: 6),
                  Text(
                    startDisplay == endDisplay
                        ? '$startDisplay ($days ${days == 1 ? "day" : "days"})'
                        : '$startDisplay - $endDisplay ($days days)',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF475569),
                    ),
                  ),
                ],
              ),
              if (reason.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Reason: $reason',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                ),
              ],
              if (docUrl.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.attachment_rounded, size: 14, color: Color(0xFF0C5AD2)),
                    const SizedBox(width: 4),
                    const Text(
                      'Supporting document attached',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0C5AD2),
                      ),
                    ),
                  ],
                ),
              ],
              if (status == 'PENDING') ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => _cancelApplication(leaveId),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Cancel Request',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBalanceCards() {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.beach_access_rounded, size: 14, color: Color(0xFF0C5AD2)),
                    SizedBox(width: 4),
                    Text(
                      'ANNUAL LEAVE',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B), letterSpacing: 0.5),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('$_annualRemaining', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                    const SizedBox(width: 4),
                    const Text('/ 12 days', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                  ],
                ),
                if (_pendingAnnualDays > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '$_pendingAnnualDays day(s) requested',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFD97706)),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.local_hospital_rounded, size: 14, color: Color(0xFF10B981)),
                    SizedBox(width: 4),
                    Text(
                      'MEDICAL LEAVE',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B), letterSpacing: 0.5),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('$_medicalRemaining', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                    const SizedBox(width: 4),
                    const Text('/ 14 days', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                  ],
                ),
                if (_pendingMedicalDays > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '$_pendingMedicalDays day(s) requested',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFD97706)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildApplyLeaveForm() {
    // Tomorrow minimum limit for start date
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Form Card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Leave Type Dropdown: Annual Leave | Medical Leave | Unpaid Leave
              const Text(
                'Leave Type *',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedLeaveType,
                    isExpanded: true,
                    icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF64748B)),
                    items: ['Annual Leave', 'Medical Leave', 'Unpaid Leave']
                        .map((type) => DropdownMenuItem(
                              value: type,
                              child: Text(type, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedLeaveType = val);
                        if (_startDate != null && _endDate != null) {
                          _checkRequestedVsRemaining(_startDate!, _endDate!, val, showDialogIfExceeded: true);
                        }
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Start Date Picker (Limit until tomorrow)
              Row(
                children: const [
                  Text(
                    'Start Date *',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                  ),
                  SizedBox(width: 6),
                  Text(
                    '(Min. 1 day in advance)',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _startDate != null && !_startDate!.isBefore(tomorrow) ? _startDate! : tomorrow,
                    firstDate: tomorrow,
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    setState(() {
                      _startDate = picked;
                      if (_endDate == null || _endDate!.isBefore(picked)) {
                        _endDate = picked;
                      }
                    });
                    if (_endDate != null) {
                      final conflict = _findDateOverlap(picked, _endDate!);
                      if (conflict != null) {
                        final conflictId = conflict['leaveID'] ?? '';
                        final conflictDates = '${conflict['startDate']} - ${conflict['endDate']}';
                        final conflictStatus = conflict['leaveStatus'] ?? 'Pending';
                        _showErrorDialog(
                          'Date Overlap Detected',
                          'You already have an active leave application ($conflictId: $conflictDates, Status: $conflictStatus) covering this date. Overlapping leaves will be rejected.',
                        );
                      } else {
                        _checkRequestedVsRemaining(picked, _endDate!, _selectedLeaveType, showDialogIfExceeded: true);
                      }
                    }
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined, size: 18, color: Color(0xFF64748B)),
                      const SizedBox(width: 10),
                      Text(
                        _startDate != null ? DateFormat('dd/MM/yyyy').format(_startDate!) : 'DD/MM/YYYY',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _startDate != null ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // End Date Picker
              const Text(
                'End Date *',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () async {
                  final minDate = _startDate ?? tomorrow;
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _endDate != null && !_endDate!.isBefore(minDate) ? _endDate! : minDate,
                    firstDate: minDate,
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    setState(() => _endDate = picked);
                    if (_startDate != null) {
                      final conflict = _findDateOverlap(_startDate!, picked);
                      if (conflict != null) {
                        final conflictId = conflict['leaveID'] ?? '';
                        final conflictDates = '${conflict['startDate']} - ${conflict['endDate']}';
                        final conflictStatus = conflict['leaveStatus'] ?? 'Pending';
                        _showErrorDialog(
                          'Date Overlap Detected',
                          'You already have an active leave application ($conflictId: $conflictDates, Status: $conflictStatus) covering this date. Overlapping leaves will be rejected.',
                        );
                      } else {
                        _checkRequestedVsRemaining(_startDate!, picked, _selectedLeaveType, showDialogIfExceeded: true);
                      }
                    }
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined, size: 18, color: Color(0xFF64748B)),
                      const SizedBox(width: 10),
                      Text(
                        _endDate != null ? DateFormat('dd/MM/yyyy').format(_endDate!) : 'DD/MM/YYYY',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _endDate != null ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Total Duration Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.access_time_filled, color: Color(0xFF0C5AD2), size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      'Total Duration',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0C5AD2)),
                    ),
                    const Spacer(),
                    Text(
                      _calculatedDuration > 0 ? '$_calculatedDuration days' : '-- days',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF0C5AD2)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Reason / Notes
              Row(
                children: [
                  Text(
                    _selectedLeaveType == 'Annual Leave'
                        ? 'Reason / Notes (Optional)'
                        : 'Reason *',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                  ),
                  if (_selectedLeaveType != 'Annual Leave') ...[
                    const SizedBox(width: 4),
                    const Text(
                      '(Required)',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFEF4444)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _reasonController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: _selectedLeaveType == 'Medical Leave'
                      ? 'Please describe reason for medical leave...'
                      : (_selectedLeaveType == 'Unpaid Leave'
                          ? 'Please provide reason for unpaid leave...'
                          : 'Add any relevant details...'),
                  hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  contentPadding: const EdgeInsets.all(14),
                ),
              ),
              const SizedBox(height: 16),

              // Attachment Uploader
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 4,
                children: [
                  Text(
                    _selectedLeaveType == 'Medical Leave'
                        ? 'Supporting Document / MC *'
                        : 'Attachment (Optional)',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                  ),
                  if (_selectedLeaveType == 'Medical Leave')
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Required',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFEF4444)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _pickAttachment,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _supportingDocFile != null ? const Color(0xFF0C5AD2) : const Color(0xFFCBD5E1),
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _supportingDocFile != null ? Icons.check_circle : Icons.file_upload_outlined,
                        color: _supportingDocFile != null ? const Color(0xFF10B981) : const Color(0xFF64748B),
                        size: 28,
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          _supportingDocFileName ?? 'Click to attach image / document',
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: _supportingDocFile != null ? const Color(0xFF0C5AD2) : const Color(0xFF64748B),
                          ),
                        ),
                      ),
                      if (_supportingDocFile != null) ...[
                        const SizedBox(height: 4),
                        const Text(
                          'Tap to change file',
                          style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Submit Button with gray overlay when required inputs are not filled
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _submitApplication,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Icon(
                          Icons.send_rounded,
                          size: 16,
                          color: _isFormValid ? Colors.white : const Color(0xFF94A3B8),
                        ),
                  label: Text(
                    _isSubmitting ? 'Submitting...' : 'Submit Application',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: _isFormValid ? Colors.white : const Color(0xFF94A3B8),
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isFormValid ? const Color(0xFF0C5AD2) : const Color(0xFFE2E8F0),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
