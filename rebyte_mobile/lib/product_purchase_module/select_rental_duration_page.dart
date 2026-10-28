import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/product_model.dart';
import 'rental_checkout_page.dart';
import '../account_management_module/welcome_page.dart';

class SelectRentalDurationPage extends StatefulWidget {
  final ProductModel product;
  final bool isLoggedIn;
  final String? email;
  final String? name;
  final VoidCallback? onRentalCompleted;

  const SelectRentalDurationPage({
    super.key,
    required this.product,
    required this.isLoggedIn,
    this.email,
    this.name,
    this.onRentalCompleted,
  });

  @override
  State<SelectRentalDurationPage> createState() => _SelectRentalDurationPageState();
}

class _SelectRentalDurationPageState extends State<SelectRentalDurationPage> {
  // Preset months: 3, 12, 24
  int _selectedPresetMonths = 3;
  int _customMonths = 3;
  final TextEditingController _customMonthsController = TextEditingController(text: '3');
  String? _durationValidationError;
  bool _isCreatingRental = false;

  @override
  void initState() {
    super.initState();
    _customMonthsController.text = '3';
  }

  @override
  void dispose() {
    _customMonthsController.dispose();
    super.dispose();
  }

  void _onPresetSelected(int months) {
    setState(() {
      _selectedPresetMonths = months;
      _customMonths = months;
      _customMonthsController.text = months.toString();
      _durationValidationError = null;
    });
  }

  void _onCustomMonthsChanged(String value) {
    setState(() {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        _durationValidationError = 'Please enter rental duration.';
        return;
      }
      final parsed = int.tryParse(trimmed);
      if (parsed == null || parsed < 1) {
        _durationValidationError = 'Duration must be at least 1 month.';
      } else if (parsed > 60) {
        _durationValidationError = 'Duration cannot exceed 5 years (60 months).';
      } else {
        _durationValidationError = null;
        _customMonths = parsed;
        // Check if matches one of presets (3, 12, 24)
        if (parsed == 3 || parsed == 12 || parsed == 24) {
          _selectedPresetMonths = parsed;
        } else {
          _selectedPresetMonths = 0; // custom value
        }
      }
    });
  }

  void _incrementMonths() {
    final current = _effectiveDurationMonths;
    if (current >= 60) return;
    final next = current + 1;
    setState(() {
      _customMonths = next;
      _customMonthsController.text = next.toString();
      _durationValidationError = null;
      if (next == 3 || next == 12 || next == 24) {
        _selectedPresetMonths = next;
      } else {
        _selectedPresetMonths = 0;
      }
    });
  }

  void _decrementMonths() {
    final current = _effectiveDurationMonths;
    if (current <= 1) return;
    final next = current - 1;
    setState(() {
      _customMonths = next;
      _customMonthsController.text = next.toString();
      _durationValidationError = null;
      if (next == 3 || next == 12 || next == 24) {
        _selectedPresetMonths = next;
      } else {
        _selectedPresetMonths = 0;
      }
    });
  }

  double get _baseMonthlyRate {
    if (widget.product.rentalPrice > 0) {
      return widget.product.rentalPrice;
    }
    if (widget.product.sellingPrice > 0) {
      return widget.product.sellingPrice * 0.08;
    }
    return 50.0;
  }

  double get _discountRate {
    if (_effectiveDurationMonths >= 24) return 0.20;
    if (_effectiveDurationMonths >= 12) return 0.10;
    return 0.0;
  }

  double get _effectiveMonthlyRate {
    return _baseMonthlyRate * (1.0 - _discountRate);
  }

  int get _effectiveDurationMonths {
    if (_selectedPresetMonths > 0) {
      return _selectedPresetMonths;
    }
    return _customMonths < 1 ? 1 : (_customMonths > 60 ? 60 : _customMonths);
  }

  double get _rentalFee {
    return _effectiveMonthlyRate * _effectiveDurationMonths;
  }

  /// Deposit amount: ceil(collectedPrice * 0.1)
  /// fallback: ceil((sellingPrice / 1.2) * 0.1), or derived from rentalPrice (where rentalPrice = collectedPrice * 0.05)
  double get _refundableDeposit {
    double baseCollected = 0.0;
    if (widget.product.collectedPrice > 0) {
      baseCollected = widget.product.collectedPrice;
    } else if (widget.product.sellingPrice > 0) {
      baseCollected = widget.product.sellingPrice / 1.2;
    } else if (widget.product.rentalPrice > 0) {
      // Since monthly rental fee is collectedPrice * 0.05, collectedPrice = rentalPrice / 0.05
      baseCollected = widget.product.rentalPrice / 0.05;
    }
    if (baseCollected > 0) {
      return (baseCollected * 0.1).ceilToDouble();
    }
    return 35.0;
  }

  /// Total estimate for the whole rental spend (All months rental fee + refundable security deposit)
  double get _totalEstimatedRentalSpend {
    return _rentalFee + _refundableDeposit;
  }

  /// Amount currently needed to pay today (First month rental fee + refundable security deposit)
  double get _currentlyDueAmount {
    return _effectiveMonthlyRate + _refundableDeposit;
  }

  Future<void> _handleContinueToRent() async {
    if (!widget.isLoggedIn || widget.email == null || widget.email!.isEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const WelcomePage()),
      );
      return;
    }

    final parsed = int.tryParse(_customMonthsController.text.trim());
    if (parsed == null || parsed < 1) {
      setState(() {
        _durationValidationError = 'Duration must be at least 1 month.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rental duration must be at least 1 month.'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    if (parsed > 60) {
      setState(() {
        _durationValidationError = 'Duration cannot exceed 5 years (60 months).';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Duration cannot exceed 5 years (60 months).'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    // Navigate to RentalCheckoutPage (Checkout)
    // Rental record & product status will be created upon successful payment
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RentalCheckoutPage(
          product: widget.product,
          email: widget.email!,
          name: widget.name,
          durationMonths: _effectiveDurationMonths,
          monthlyRentalFee: _effectiveMonthlyRate,
          depositAmount: _refundableDeposit,
          onRentalCompleted: () {
            widget.onRentalCompleted?.call();
            Navigator.pop(context, true);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/rebyte_logo.png',
              height: 36,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Container(
                height: 36,
                width: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF0C5AD2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Text('R', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'ReByte',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Page Header
              const Text(
                'Select Rental Duration',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F254B),
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Choose how long you need the equipment.\nPrices scale with duration.',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF64748B),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),

              // 1. Quick Select Presets Card
              _buildQuickSelectCard(),
              const SizedBox(height: 16),

              // 2. Custom Month Input Card
              _buildCustomMonthCard(),
              const SizedBox(height: 16),

              // 3. Rental Summary & Details Card
              _buildRentalDetailsCard(),
              const SizedBox(height: 24),

              // Estimated Total & Continue to Rent
              _buildCheckoutBottomSection(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickSelectCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
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
            children: const [
              Text(
                'Quick Select',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              Icon(Icons.flash_on_rounded, size: 20, color: Color(0xFF0C5AD2)),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Select a recommended plan or type your months below.',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildPresetOption(
                  months: 3,
                  badgeText: null,
                  isSelected: _selectedPresetMonths == 3,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildPresetOption(
                  months: 12,
                  badgeText: '10% OFF',
                  isSelected: _selectedPresetMonths == 12,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildPresetOption(
                  months: 24,
                  badgeText: '20% OFF',
                  isSelected: _selectedPresetMonths == 24,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPresetOption({
    required int months,
    required String? badgeText,
    required bool isSelected,
  }) {
    return InkWell(
      onTap: () => _onPresetSelected(months),
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 96,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? const Color(0xFF0C5AD2) : Colors.grey.shade300,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$months',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: isSelected ? const Color(0xFF0C5AD2) : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'MONTHS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: isSelected ? const Color(0xFF0C5AD2) : const Color(0xFF64748B),
                    ),
                  ),
                  if (badgeText != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      badgeText,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (isSelected)
            Positioned(
              top: -6,
              right: -6,
              child: Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  color: Color(0xFF0C5AD2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  size: 13,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCustomMonthCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _durationValidationError != null ? const Color(0xFFEF4444) : Colors.grey.shade200,
        ),
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
            children: const [
              Text(
                'Custom Month Duration',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              Icon(Icons.edit_calendar_outlined, size: 20, color: Color(0xFF64748B)),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Enter any custom number of months (min 1 month, max 60 months / 5 years).',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 14),

          // Stepper & Text Field Row
          Row(
            children: [
              // Decrement Button
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: IconButton(
                  icon: const Icon(Icons.remove, size: 20, color: Color(0xFF0F172A)),
                  onPressed: _effectiveDurationMonths > 1 ? _decrementMonths : null,
                  disabledColor: Colors.grey.shade400,
                ),
              ),
              const SizedBox(width: 12),

              // Number Input
              Expanded(
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _durationValidationError != null ? const Color(0xFFEF4444) : const Color(0xFF0C5AD2),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 60,
                        child: TextField(
                          controller: _customMonthsController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(3),
                          ],
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: _onCustomMonthsChanged,
                        ),
                      ),
                      const Text(
                        'Months',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Increment Button
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: IconButton(
                  icon: const Icon(Icons.add, size: 20, color: Color(0xFF0F172A)),
                  onPressed: _effectiveDurationMonths < 60 ? _incrementMonths : null,
                  disabledColor: Colors.grey.shade400,
                ),
              ),
            ],
          ),

          // Duration Validation Error Banner
          if (_durationValidationError != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.error_outline, size: 14, color: Color(0xFFDC2626)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _durationValidationError!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFDC2626),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRentalDetailsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
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
          // Item row
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Image.network(
                  widget.product.imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.phone_android,
                    size: 32,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'RENTAL ITEM',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: Color(0xFF0C5AD2),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.product.displayTitle,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 14),

          // Monthly Rate (showing original crossed out if discounted)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text(
                    'Monthly Rate',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  if (_discountRate > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${(_discountRate * 100).toInt()}% OFF',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF16A34A),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Row(
                children: [
                  if (_discountRate > 0) ...[
                    Text(
                      'RM${_baseMonthlyRate.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 12,
                        decoration: TextDecoration.lineThrough,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    'RM${_effectiveMonthlyRate.toStringAsFixed(2)}/mth',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: _discountRate > 0 ? const Color(0xFF16A34A) : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Duration
          _buildDetailRow(
            'Duration',
            '$_effectiveDurationMonths Month${_effectiveDurationMonths > 1 ? "s" : ""}',
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 12),

          // Total Rental Fee for the duration
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Rental Fee ($_effectiveDurationMonths mth)',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569),
                ),
              ),
              Text(
                'RM${_rentalFee.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Refundable Deposit Banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Refundable Deposit',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Returned upon passing inspection.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'RM${_refundableDeposit.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Highlight Box: Total Whole Rental Spend vs Currently Need to Pay
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total Estimate for Whole Spend',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF334155),
                      ),
                    ),
                    Text(
                      'RM${_totalEstimatedRentalSpend.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Currently Need to Pay',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0C5AD2),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '(Deposit + 1st month rental)',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'RM${_currentlyDueAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0C5AD2),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Informational Notice
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: const [
                Icon(Icons.info_outline, size: 18, color: Color(0xFF4338CA)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Rentals require a credit check that will not impact your credit score.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF4338CA),
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF64748B),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  Widget _buildCheckoutBottomSection() {
    final hasError = _durationValidationError != null || _isCreatingRental;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Total Whole Spend summary line
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Whole Rental Spend',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF64748B),
                ),
              ),
              Text(
                'RM${_totalEstimatedRentalSpend.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF475569),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Currently Need to Pay summary line
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Currently Need to Pay',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    'Deposit + 1st month',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
              Text(
                'RM${_currentlyDueAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0C5AD2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: hasError ? null : _handleContinueToRent,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0C5AD2),
                disabledBackgroundColor: const Color(0xFF94A3B8),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isCreatingRental
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Text(
                          'Continue to Rent',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward, size: 18, color: Colors.white),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
