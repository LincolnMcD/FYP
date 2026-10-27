import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'models/product_model.dart';
import 'models/cart_item_model.dart';
import 'checkout_page.dart';
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

  late DateTime _startDate;
  late DateTime _endDate;

  @override
  void initState() {
    super.initState();
    _startDate = DateTime.now();
    _endDate = _addMonths(_startDate, 3);
  }

  DateTime _addMonths(DateTime date, int months) {
    var year = date.year;
    var month = date.month + months;
    while (month > 12) {
      year++;
      month -= 12;
    }
    final day = date.day;
    final daysInTargetMonth = DateUtils.getDaysInMonth(year, month);
    return DateTime(year, month, day > daysInTargetMonth ? daysInTargetMonth : day);
  }

  int _calculateMonthsDifference(DateTime start, DateTime end) {
    if (end.isBefore(start)) return 1;
    final diffDays = end.difference(start).inDays;
    final calculated = (diffDays / 30.0).round();
    return calculated < 1 ? 1 : calculated;
  }

  void _onPresetSelected(int months) {
    setState(() {
      _selectedPresetMonths = months;
      _endDate = _addMonths(_startDate, months);
    });
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF0C5AD2),
              onPrimary: Colors.white,
              onSurface: Color(0xFF0F172A),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked;
        if (_selectedPresetMonths > 0) {
          _endDate = _addMonths(_startDate, _selectedPresetMonths);
        } else if (_endDate.isBefore(_startDate)) {
          _endDate = _addMonths(_startDate, 1);
        }
      });
    }
  }

  Future<void> _pickEndDate() async {
    final firstAllowed = _startDate.add(const Duration(days: 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate.isAfter(firstAllowed) ? _endDate : firstAllowed,
      firstDate: firstAllowed,
      lastDate: DateTime(_startDate.year + 5),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF0C5AD2),
              onPrimary: Colors.white,
              onSurface: Color(0xFF0F172A),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _endDate = picked;
        _selectedPresetMonths = 0; // custom duration
      });
    }
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
    if (_selectedPresetMonths == 12) return 0.10;
    if (_selectedPresetMonths == 24) return 0.20;
    return 0.0;
  }

  double get _effectiveMonthlyRate {
    return _baseMonthlyRate * (1.0 - _discountRate);
  }

  int get _effectiveDurationMonths {
    if (_selectedPresetMonths > 0) {
      return _selectedPresetMonths;
    }
    return _calculateMonthsDifference(_startDate, _endDate);
  }

  double get _rentalFee {
    return _effectiveMonthlyRate * _effectiveDurationMonths;
  }

  double get _refundableDeposit {
    if (widget.product.sellingPrice > 0) {
      return widget.product.sellingPrice * 0.20;
    }
    return 200.0;
  }

  double get _estimatedTotalFee {
    return _rentalFee + _refundableDeposit;
  }

  void _proceedToCheckout() {
    if (!widget.isLoggedIn || widget.email == null || widget.email!.isEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const WelcomePage()),
      );
      return;
    }

    final durationText = '$_effectiveDurationMonths Month${_effectiveDurationMonths > 1 ? "s" : ""}';
    final rentalItem = CartItemModel(
      productID: widget.product.productID,
      listingTitle: '${widget.product.displayTitle} ($durationText Rental)',
      description: 'Rental Duration: $durationText | Deposit: RM ${_refundableDeposit.toStringAsFixed(2)}',
      sellingPrice: _estimatedTotalFee,
      imageUrl: widget.product.imageUrl,
      brand: widget.product.brand,
      model: widget.product.model,
      storage: widget.product.storage,
      ram: widget.product.ram,
      color: widget.product.color,
      condition: widget.product.condition,
      deviceID: widget.product.deviceID,
      modelCode: widget.product.modelCode,
      listingStatus: 'rent',
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CheckoutPage(
          email: widget.email!,
          name: widget.name,
          items: [rentalItem],
          onCartUpdated: widget.onRentalCompleted,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy');

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

              // 1. Quick Select Card
              _buildQuickSelectCard(),
              const SizedBox(height: 16),

              // 2. Custom Dates Card
              _buildCustomDatesCard(dateFormat),
              const SizedBox(height: 16),

              // 3. Rental Summary & Details Card
              _buildRentalDetailsCard(),
              const SizedBox(height: 24),

              // Estimated Total & Continue to Checkout
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
          const Text(
            'Quick Select',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
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
                  badgeText: '-10% rate',
                  isSelected: _selectedPresetMonths == 12,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildPresetOption(
                  months: 24,
                  badgeText: '-20% rate',
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

  Widget _buildCustomDatesCard(DateFormat dateFormat) {
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
                'Custom Dates',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              Icon(Icons.calendar_today_outlined, size: 20, color: Color(0xFF0F172A)),
            ],
          ),
          const SizedBox(height: 14),

          // Start Date Field
          const Text(
            'Start Date',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: _pickStartDate,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Text(
                dateFormat.format(_startDate),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // End Date Field
          const Text(
            'End Date',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: _pickEndDate,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Text(
                dateFormat.format(_endDate),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
          ),
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

          // Monthly Rate
          _buildDetailRow(
            'Monthly Rate',
            'RM${_effectiveMonthlyRate.toStringAsFixed(2)}',
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

          // Rental Fee
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Rental Fee',
                style: TextStyle(
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Estimated Total Fee',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
              Text(
                'RM${_estimatedTotalFee.toStringAsFixed(2)}',
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
              onPressed: _proceedToCheckout,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0C5AD2),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Text(
                    'Continue to Checkout',
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
