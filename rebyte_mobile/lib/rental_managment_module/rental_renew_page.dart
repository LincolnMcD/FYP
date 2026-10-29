import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'services/rental_service.dart';
import '../../widgets/rebyte_app_bar.dart';
import '../../widgets/rebyte_bottom_nav_bar.dart';

class RentalRenewPage extends StatefulWidget {
  final Map<String, dynamic> rental;
  final String email;
  final String? name;

  const RentalRenewPage({
    super.key,
    required this.rental,
    required this.email,
    this.name,
  });

  @override
  State<RentalRenewPage> createState() => _RentalRenewPageState();
}

class _RentalRenewPageState extends State<RentalRenewPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  DateTime? _currentEndDate;
  DateTime? _rentalExpiryDate;
  DateTime? _selectedNewEndDate;
  DateTime? _maxAllowedEndDate;

  int _additionalMonths = 0;
  bool _isSubmitting = false;

  String? _toastMessage;
  bool _isToastError = false;

  @override
  void initState() {
    super.initState();
    _initDates();
  }

  void _initDates() {
    // Current endDate
    final endStr = widget.rental['endDate']?.toString();
    if (endStr != null && endStr.isNotEmpty) {
      _currentEndDate = DateTime.tryParse(endStr);
    }
    _currentEndDate ??= DateTime.now().add(const Duration(days: 30));

    // rentalExpiryDate (lastExpired)
    final expStr = widget.rental['rentalExpiryDate']?.toString();
    if (expStr != null && expStr.isNotEmpty) {
      _rentalExpiryDate = DateTime.tryParse(expStr);
    }
    _rentalExpiryDate ??= _currentEndDate;

    // Maximum allowed newEndDate: lastExpired (rentalExpiryDate) + 5 years
    _maxAllowedEndDate = DateTime(
      _rentalExpiryDate!.year + 5,
      _rentalExpiryDate!.month,
      _rentalExpiryDate!.day,
    );

    // Default selected newEndDate = currentEndDate + 1 month (with safe day clamping)
    final targetYear = _currentEndDate!.month == 12 ? _currentEndDate!.year + 1 : _currentEndDate!.year;
    final targetMonth = _currentEndDate!.month == 12 ? 1 : _currentEndDate!.month + 1;
    final daysInTargetMonth = DateTime(targetYear, targetMonth + 1, 0).day;
    final targetDay = _currentEndDate!.day > daysInTargetMonth ? daysInTargetMonth : _currentEndDate!.day;
    final defaultNew = DateTime(targetYear, targetMonth, targetDay);

    if (defaultNew.isBefore(_maxAllowedEndDate!) ||
        defaultNew.isAtSameMomentAs(_maxAllowedEndDate!)) {
      _selectedNewEndDate = defaultNew;
      _additionalMonths = 1;
    } else {
      _selectedNewEndDate = _maxAllowedEndDate;
      _calculateAdditionalMonths();
    }
  }

  void _calculateAdditionalMonths() {
    if (_selectedNewEndDate == null || _currentEndDate == null) {
      _additionalMonths = 0;
      return;
    }

    int months = (_selectedNewEndDate!.year - _currentEndDate!.year) * 12 +
        (_selectedNewEndDate!.month - _currentEndDate!.month);

    _additionalMonths = months > 0 ? months : 0;
  }

  void _showToast(String message, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _toastMessage = message;
      _isToastError = isError;
    });
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _toastMessage == message) {
        setState(() => _toastMessage = null);
      }
    });
  }

  Future<void> _pickNewEndDate() async {
    // Earliest selectable month is the month immediately after currentEndDate's month
    final minYear = _currentEndDate!.month == 12 ? _currentEndDate!.year + 1 : _currentEndDate!.year;
    final minMonth = _currentEndDate!.month == 12 ? 1 : _currentEndDate!.month + 1;

    final maxYear = _maxAllowedEndDate!.year;
    final maxMonth = _maxAllowedEndDate!.month;

    // Check if max allowed is already reached
    if (minYear > maxYear || (minYear == maxYear && minMonth > maxMonth)) {
      _showToast(
        'Maximum rental duration (5 years) has already been reached.',
        isError: true,
      );
      return;
    }

    int selectedYear = _selectedNewEndDate?.year ?? minYear;
    int selectedMonth = _selectedNewEndDate?.month ?? minMonth;

    if (selectedYear < minYear || (selectedYear == minYear && selectedMonth < minMonth)) {
      selectedYear = minYear;
      selectedMonth = minMonth;
    } else if (selectedYear > maxYear || (selectedYear == maxYear && selectedMonth > maxMonth)) {
      selectedYear = maxYear;
      selectedMonth = maxMonth;
    }

    final picked = await showDialog<DateTime>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setPickerState) {
            final monthNames = [
              'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
              'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
            ];

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Select Month & Year',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Day ${_currentEndDate!.day}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF003F9E),
                      ),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Year selector row with arrows
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left),
                            color: selectedYear > minYear ? const Color(0xFF003F9E) : const Color(0xFFCBD5E1),
                            onPressed: selectedYear > minYear
                                ? () {
                                    setPickerState(() {
                                      selectedYear--;
                                      if (selectedYear == minYear && selectedMonth < minMonth) {
                                        selectedMonth = minMonth;
                                      }
                                    });
                                  }
                                : null,
                          ),
                          Text(
                            '$selectedYear',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.chevron_right),
                            color: selectedYear < maxYear ? const Color(0xFF003F9E) : const Color(0xFFCBD5E1),
                            onPressed: selectedYear < maxYear
                                ? () {
                                    setPickerState(() {
                                      selectedYear++;
                                      if (selectedYear == maxYear && selectedMonth > maxMonth) {
                                        selectedMonth = maxMonth;
                                      }
                                    });
                                  }
                                : null,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 12 Months Grid
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 2.1,
                      ),
                      itemCount: 12,
                      itemBuilder: (context, idx) {
                        final mNum = idx + 1;
                        final isBeforeMin = selectedYear == minYear && mNum < minMonth;
                        final isAfterMax = selectedYear == maxYear && mNum > maxMonth;
                        final isBlocked = isBeforeMin || isAfterMax;
                        final isSelected = selectedMonth == mNum;

                        return InkWell(
                          onTap: isBlocked
                              ? null
                              : () {
                                  setPickerState(() {
                                    selectedMonth = mNum;
                                  });
                                },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF003F9E)
                                  : isBlocked
                                      ? const Color(0xFFF1F5F9)
                                      : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF003F9E)
                                    : isBlocked
                                        ? const Color(0xFFE2E8F0)
                                        : const Color(0xFFCBD5E1),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              monthNames[idx],
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                color: isSelected
                                    ? Colors.white
                                    : isBlocked
                                        ? const Color(0xFFCBD5E1)
                                        : const Color(0xFF1E293B),
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 12),
                    Text(
                      'Select between ${monthNames[minMonth - 1]} $minYear and ${monthNames[maxMonth - 1]} $maxYear',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx, null),
                  child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
                ),
                ElevatedButton(
                  onPressed: () {
                    // Safe day clamping for the target month
                    final daysInTargetMonth = DateTime(selectedYear, selectedMonth + 1, 0).day;
                    final targetDay = _currentEndDate!.day > daysInTargetMonth
                        ? daysInTargetMonth
                        : _currentEndDate!.day;

                    final result = DateTime(selectedYear, selectedMonth, targetDay);
                    Navigator.pop(dialogCtx, result);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF003F9E),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Confirm', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedNewEndDate = picked;
        _calculateAdditionalMonths();
      });
    }
  }

  Future<void> _handleConfirmRenewal() async {
    if (_selectedNewEndDate == null || _additionalMonths <= 0) {
      _showToast('Please select a valid new end date.', isError: true);
      return;
    }

    final newEndStr = DateFormat('yyyy-MM-dd').format(_selectedNewEndDate!);
    final currentEndFormatted = DateFormat('dd MMM yyyy').format(_currentEndDate!);
    final newEndFormatted = DateFormat('dd MMM yyyy').format(_selectedNewEndDate!);

    // Show Confirmation Dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        title: const Row(
          children: [
            Icon(Icons.sync_rounded, color: Color(0xFF003F9E), size: 24),
            SizedBox(width: 10),
            Text(
              'Confirm Renewal',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Color(0xFF0F172A),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to renew your rental agreement for this device?',
              style: TextStyle(
                fontSize: 13.5,
                color: Colors.grey.shade700,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  _dialogRow('Current End Date:', currentEndFormatted),
                  const Divider(height: 16, color: Color(0xFFE2E8F0)),
                  _dialogRow('New End Date:', newEndFormatted, isHighlight: true),
                  const Divider(height: 16, color: Color(0xFFE2E8F0)),
                  _dialogRow(
                    'Extended Duration:',
                    '+$_additionalMonths ${_additionalMonths == 1 ? 'month' : 'months'}',
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF003F9E),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text(
              'Confirm Renew',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSubmitting = true);

    final rentalID = widget.rental['rentalID']?.toString() ?? '';
    final res = await RentalService.renewRental(
      rentalID: rentalID,
      newEndDate: newEndStr,
      additionalMonths: _additionalMonths,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (res['success'] == true) {
      _showToast(
        'Rental agreement successfully renewed until $newEndFormatted! (+$_additionalMonths mth)',
        isError: false,
      );

      // Return true after short delay so parent can refresh
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) {
          Navigator.pop(context, true);
        }
      });
    } else {
      _showToast(res['error']?.toString() ?? 'Failed to renew rental.', isError: true);
    }
  }

  Widget _dialogRow(String label, String value, {bool isHighlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: isHighlight ? const Color(0xFF003F9E) : const Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Device & Product Data
    final product = widget.rental['product'] as Map<String, dynamic>? ?? {};
    final device = widget.rental['device'] as Map<String, dynamic>? ?? {};

    final brand = (device['brand'] ?? product['brand'] ?? '').toString();
    final model = (device['model'] ?? product['model'] ?? 'Rented Phone').toString();
    final title = brand.isNotEmpty ? '$brand $model' : model;
    final serial = (device['serialNumber'] ??
            product['serialNumber'] ??
            widget.rental['productID'] ??
            'N/A')
        .toString();
    final imageUrl = (product['imageUrl'] ?? product['productImage'] ?? '').toString();

    final currentEndFormatted = DateFormat('dd MMM yyyy').format(_currentEndDate!);
    final expiryFormatted = DateFormat('dd MMM yyyy').format(_rentalExpiryDate!);
    final maxEndFormatted = DateFormat('dd MMM yyyy').format(_maxAllowedEndDate!);
    final selectedNewFormatted = _selectedNewEndDate != null
        ? DateFormat('dd MMM yyyy').format(_selectedNewEndDate!)
        : 'Select Date';

    final monthlyFee = widget.rental['monthlyRentalFee'] != null
        ? 'RM ${widget.rental['monthlyRentalFee']}'
        : '-';

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: ReByteAppBar(
        scaffoldKey: _scaffoldKey,
      ),
      drawer: ReByteDrawer(
        isLoggedIn: true,
        email: widget.email,
        name: widget.name,
        isRentalsSelected: true,
      ),
      bottomNavigationBar: const ReByteBottomNavBar(
        selectedIndex: 3,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Navigation Row
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B), size: 22),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),

                // Main Title (Left aligned)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                  child: Text(
                    'Renew Rental Agreement',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),

                const SizedBox(height: 6),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Section 1: Brief of Rented Device (Identical to Pay Rental)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                            border: Border.all(color: const Color(0xFFF1F5F9)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Image
                              Container(
                                width: 70,
                                height: 70,
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: imageUrl.isNotEmpty
                                    ? Image.network(
                                        imageUrl,
                                        fit: BoxFit.contain,
                                        errorBuilder: (context, error, stackTrace) => const Icon(
                                          Icons.phone_android,
                                          color: Color(0xFF64748B),
                                          size: 36,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.phone_android,
                                        color: Color(0xFF64748B),
                                        size: 36,
                                      ),
                              ),
                              const SizedBox(width: 14),

                              // Info
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Serial:\n$serial',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF64748B),
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Active Rental Pill
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDBEAFE),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.check_circle_outline,
                                      size: 13,
                                      color: Color(0xFF2563EB),
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'Active Rental',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF2563EB),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Section 2: Select New End Date
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                            border: Border.all(color: const Color(0xFFF1F5F9)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.edit_calendar_outlined,
                                    size: 20,
                                    color: Color(0xFF003F9E),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Rental Extension Schedule',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 16),

                              // Timeline Info Box
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Column(
                                  children: [
                                    _infoRow('Current End Date', currentEndFormatted),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 8),
                                      child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                                    ),
                                    _infoRow('Rental Paid Until', expiryFormatted),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 8),
                                      child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                                    ),
                                    _infoRow('Max Allowed End Date (5 yrs)', maxEndFormatted),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 8),
                                      child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                                    ),
                                    _infoRow('Monthly Fee', monthlyFee),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 18),

                              const Text(
                                'Select New End Date',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF334155),
                                ),
                              ),
                              const SizedBox(height: 8),

                              // Date Picker Tap Target
                              InkWell(
                                onTap: _pickNewEndDate,
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFF003F9E), width: 1.5),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.calendar_today_outlined,
                                            size: 18,
                                            color: Color(0xFF003F9E),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            selectedNewFormatted,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF0F172A),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Icon(
                                        Icons.arrow_drop_down,
                                        color: Color(0xFF64748B),
                                        size: 24,
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(height: 10),

                              // Extension Summary Pill
                              if (_additionalMonths > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFECFDF5),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFA7F3D0)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.add_circle_outline,
                                        size: 16,
                                        color: Color(0xFF059669),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Extends agreement by $_additionalMonths ${_additionalMonths == 1 ? 'month' : 'months'}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF065F46),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                              const SizedBox(height: 8),
                              const Text(
                                'Note: The new end date must be after your current end date and cannot exceed 5 years from your rental expiry date.',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF94A3B8),
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Action Button: Renew Rental
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isSubmitting || _additionalMonths <= 0
                                ? null
                                : _handleConfirmRenewal,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF003F9E),
                              disabledBackgroundColor: const Color(0xFFE2E8F0),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                            child: _isSubmitting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.sync, color: Colors.white, size: 20),
                                      const SizedBox(width: 8),
                                      Text(
                                        _additionalMonths > 0
                                            ? 'Renew Rental (+$_additionalMonths ${_additionalMonths == 1 ? 'mth' : 'mths'})'
                                            : 'Select Date to Renew',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: _additionalMonths > 0
                                              ? Colors.white
                                              : const Color(0xFF94A3B8),
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),

                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Top Floating Toast Banner (Dismissible / Slideable to remove)
            if (_toastMessage != null)
              Positioned(
                top: 12,
                left: 16,
                right: 16,
                child: Dismissible(
                  key: ValueKey(_toastMessage),
                  direction: DismissDirection.horizontal,
                  onDismissed: (_) {
                    setState(() => _toastMessage = null);
                  },
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: _isToastError ? const Color(0xFFE11D48) : Colors.green.shade600,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4)),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isToastError ? Icons.error_outline : Icons.check_circle_outline,
                            color: Colors.white,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _toastMessage!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => setState(() => _toastMessage = null),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white70,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }
}
