import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'services/rental_service.dart';
import 'rental_device_detail_page.dart';
import 'rental_payment_confirmation_page.dart';
import 'rental_renew_page.dart';
import 'rental_return_page.dart';
import 'rental_overdue_locked_page.dart';
import 'rental_missing_payment_page.dart';
import '../../widgets/rebyte_app_bar.dart';
import '../widgets/rebyte_bottom_nav_bar.dart';
import '../account_management_module/home_page.dart';

class MyRentalsPage extends StatefulWidget {
  final String email;
  final String? name;
  final int initialTabIndex;

  const MyRentalsPage({
    super.key,
    required this.email,
    this.name,
    this.initialTabIndex = 0,
  });

  @override
  State<MyRentalsPage> createState() => _MyRentalsPageState();
}

class _MyRentalsPageState extends State<MyRentalsPage> with SingleTickerProviderStateMixin {
  static const int _rentalBufferDays = 3;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late TabController _tabController;
  bool _isLoading = true;
  List<Map<String, dynamic>> _rentals = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 3),
    );
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadRentals();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRentals() async {
    setState(() => _isLoading = true);
    final results = await RentalService.getCustomerRentals(widget.email);
    if (mounted) {
      setState(() {
        _rentals = results;
        _isLoading = false;
      });
    }
  }

  /// Overdue membership comes only from the backend rentalStatus field.
  bool _isRentalOverdue(Map<String, dynamic> rental) {
    final status = (rental['rentalStatus'] ?? '').toString().toLowerCase().trim();
    return status == 'overdue';
  }

  /// Categorizes rentals into:
  /// - 'active': rentalStatus == 'renting' (and not overdue)
  /// - 'returning': rentalStatus == 'returning'
  /// - 'overdue': rentalStatus == 'overdue'
  /// - 'completed': rentalStatus == 'completed', 'returned', 'bought_out', or 'missing'
  String _categorizeRental(Map<String, dynamic> rental) {
    final status = (rental['rentalStatus'] ?? '').toString().toLowerCase().trim();
    final depositStatus = (rental['depositStatus'] ?? '').toString().toLowerCase().trim();
    if (status == 'missing') {
      return 'completed';
    }
    if (status == 'overdue') {
      return 'overdue';
    }
    if (depositStatus == 'returned' || depositStatus == 'refunded') {
      return 'completed';
    }
    if (_isRentalOverdue(rental)) {
      return 'overdue';
    }
    if (status == 'returning') {
      return 'returning';
    }
    if (status == 'renting' || status == 'active') {
      return 'active';
    }
    return 'completed';
  }

  /// Calculates total rental contract remaining days (from today until endDate)
  int _calculateTotalRentalRemainingDays(Map<String, dynamic> rental) {
    final endStr = rental['endDate']?.toString();
    if (endStr != null && endStr.isNotEmpty) {
      try {
        final end = DateTime.parse(endStr);
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final endDate = DateTime(end.year, end.month, end.day);
        final diff = endDate.difference(today).inDays;
        return diff < 0 ? 0 : diff;
      } catch (_) {}
    }
    return 0;
  }

  /// Calculates remaining days until the rental pay until date (rentalExpiryDate)
  int _calculateDaysUntilPayDate(Map<String, dynamic> rental) {
    return _calculateDaysRemainingOrLate(rental);
  }

  int _calculateDaysRemainingOrLate(Map<String, dynamic> rental) {
    final expiryStr = rental['rentalExpiryDate']?.toString();
    if (expiryStr != null && expiryStr.isNotEmpty) {
      try {
        final expiry = DateTime.parse(expiryStr);
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final expDate = DateTime(expiry.year, expiry.month, expiry.day);
        return expDate.difference(today).inDays;
      } catch (_) {}
    }
    return 0;
  }

  int _calculateBufferDaysRemaining(Map<String, dynamic> rental) {
    final expiryStr = rental['rentalExpiryDate']?.toString();
    if (expiryStr == null || expiryStr.isEmpty) return 0;
    try {
      final expiry = DateTime.parse(expiryStr);
      final bufferEnd = DateTime(expiry.year, expiry.month, expiry.day + _rentalBufferDays);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final days = bufferEnd.difference(today).inDays;
      return days < 0 ? 0 : days;
    } catch (_) {
      return 0;
    }
  }

  String _formatDate(dynamic dateVal) {
    if (dateVal == null) return '';
    try {
      final dt = DateTime.parse(dateVal.toString());
      return DateFormat('dd MMM yy').format(dt);
    } catch (_) {
      return dateVal.toString();
    }
  }

  Future<void> _showDepositRefundBreakdown(Map<String, dynamic> rental) async {
    final assessment = rental['returnAssessment'] is Map
        ? Map<String, dynamic>.from(rental['returnAssessment'] as Map)
        : <String, dynamic>{};
    final conditions = assessment['condition'] is Map
        ? Map<String, dynamic>.from(assessment['condition'] as Map)
        : <String, dynamic>{};
    final savedDeductions = assessment['deductions'] is List
        ? List<Map<String, dynamic>>.from(
            (assessment['deductions'] as List).whereType<Map>().map(
              (item) => Map<String, dynamic>.from(item),
            ),
          )
        : <Map<String, dynamic>>[];
    final depositRaw = rental['rentalDeposit'] ?? rental['depositAmount'] ?? 0;
    final deposit = depositRaw is num ? depositRaw.toDouble() : double.tryParse('$depositRaw') ?? 0;
    final refundRaw = assessment['totalDepositRefund'] ?? 0;
    final totalRefund = refundRaw is num ? refundRaw.toDouble() : double.tryParse('$refundRaw') ?? 0;
    const partNames = <String, String>{
      'screen': 'Screen',
      'back': 'Back',
      'camera': 'Camera Area',
      'frame': 'Frame',
    };
    const rates = <String, Map<String, double>>{
      'screen': {'perfect': 0, 'minor': .10, 'major': .50},
      'back': {'perfect': 0, 'minor': .05, 'major': .25},
      'camera': {'perfect': 0, 'minor': .10, 'major': .50},
      'frame': {'perfect': 0, 'minor': .02, 'major': .05},
    };
    final parts = partNames.entries.map((entry) {
      final condition = (conditions[entry.key] ?? 'perfect').toString().toLowerCase();
      final match = savedDeductions.where((item) =>
          (item['name'] ?? '').toString().toLowerCase().startsWith(entry.value.toLowerCase())).toList();
      final rawAmount = match.isNotEmpty ? match.first['amount'] : null;
      final amount = rawAmount is num
          ? rawAmount.toDouble()
          : double.tryParse('$rawAmount') ?? deposit * (rates[entry.key]?[condition] ?? 0);
      return (name: entry.value, condition: condition, amount: amount);
    }).toList();
    final totalDeduction = (deposit - totalRefund).clamp(0, deposit).toDouble();
    String money(double value) => 'RM ${value.toStringAsFixed(2)}';
    String conditionLabel(String value) => value.isEmpty || value == 'none'
        ? 'Not recorded'
        : value[0].toUpperCase() + value.substring(1);

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Deposit Refund Breakdown', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
              const SizedBox(height: 5),
              Text('Rental ${rental['rentalID'] ?? ''}', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
              const SizedBox(height: 16),
              ...parts.map((part) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(part.name, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                      Text('Condition: ${conditionLabel(part.condition)}', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                    ])),
                    Text('- ${money(part.amount)}', style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFDC2626))),
                  ],
                ),
              )),
              const Divider(height: 22),
              _refundAmountRow('Original deposit', money(deposit)),
              const SizedBox(height: 8),
              _refundAmountRow('Total deductions', '- ${money(totalDeduction)}', valueColor: const Color(0xFFDC2626)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(12)),
                child: _refundAmountRow('Total deposit refund', money(totalRefund), valueColor: const Color(0xFF0C5AD2), bold: true),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _refundAmountRow(String label, String value, {Color valueColor = const Color(0xFF0F172A), bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.bold : FontWeight.w500, color: const Color(0xFF475569)))),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.bold : FontWeight.w600, color: valueColor)),
      ],
    );
  }

  Future<void> _handleReportMissing(BuildContext context, Map<String, dynamic> rental) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RentalMissingPaymentPage(
          rental: rental,
          email: widget.email,
          name: widget.name,
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final activeList = _rentals.where((r) => _categorizeRental(r) == 'active').toList();
    final returningList = _rentals.where((r) => _categorizeRental(r) == 'returning').toList();
    final overdueList = _rentals.where((r) => _categorizeRental(r) == 'overdue').toList();
    final completedList = _rentals.where((r) => _categorizeRental(r) == 'completed').toList();

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
        selectedIndex: -1,
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Navigation Row (Back Button)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B), size: 22),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  } else {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (context) => HomePage(
                          isLoggedIn: true,
                          email: widget.email,
                          name: widget.name,
                          initialIndex: 4, // Profile tab
                        ),
                      ),
                      (route) => false,
                    );
                  }
                },
              ),
            ),

            // Header Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'My Rentals',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Manage your active devices and rental history.',
                    style: TextStyle(
                      fontSize: 13.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Tabs Bar matching mockup
            Container(
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                onTap: (index) {
                  if (index == 2 || index == 3) _loadRentals();
                },
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: const Color(0xFF0C5AD2),
                unselectedLabelColor: const Color(0xFF64748B),
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                indicatorColor: const Color(0xFF0C5AD2),
                indicatorWeight: 3,
                tabs: [
                  _buildTab('Active', activeList.length, showBadge: false),
                  _buildTab('Returning', returningList.length, showBadge: returningList.isNotEmpty),
                  _buildTab('Overdue', overdueList.length, isDot: true, showBadge: overdueList.isNotEmpty),
                  _buildTab('Completed', completedList.length, showBadge: false),
                ],
              ),
            ),

            // Tab Views
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildRentalList(activeList, category: 'active'),
                        _buildRentalList(returningList, category: 'returning'),
                        _buildRentalList(overdueList, category: 'overdue'),
                        _buildRentalList(completedList, category: 'completed'),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(String label, int count, {bool showBadge = false, bool isDot = false}) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (showBadge && !isDot) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF4F46E5),
                ),
              ),
            ),
          ],
          if (showBadge && isDot) ...[
            const SizedBox(width: 4),
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: Color(0xFFF97316),
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRentalList(List<Map<String, dynamic>> items, {required String category}) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 54, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'No ${category.toLowerCase()} rentals found.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRentals,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final rental = items[index];
          return _buildRentalCard(rental, category: category);
        },
      ),
    );
  }

  Widget _buildRentalCard(Map<String, dynamic> rental, {required String category}) {
    final rentalID = rental['rentalID']?.toString() ?? '';
    final isMissing = (rental['rentalStatus'] ?? '').toString().toLowerCase().trim() == 'missing';
    final product = rental['product'] as Map<String, dynamic>? ?? {};
    final device = rental['device'] as Map<String, dynamic>? ?? {};

    // Product Title
    String title = product['listingTitle']?.toString() ?? '';
    if (title.isEmpty) {
      final brand = device['brand']?.toString() ?? '';
      final model = device['model']?.toString() ?? '';
      title = '$brand $model'.trim();
    }
    if (title.isEmpty) title = 'Device Rental';

    // Image URL
    String imageUrl = product['imageUrl']?.toString() ?? '';
    if (imageUrl.isEmpty && product['images'] is List && (product['images'] as List).isNotEmpty) {
      imageUrl = product['images'][0].toString();
    }

    // Period formatting
    final startFormatted = _formatDate(rental['startDate']);
    final endFormatted = _formatDate(rental['endDate']);
    final periodText = startFormatted.isNotEmpty && endFormatted.isNotEmpty
        ? '$startFormatted - $endFormatted'
        : (startFormatted.isNotEmpty ? startFormatted : '—');

    // Rental Pay Until formatting
    final payUntilFormatted = _formatDate(rental['rentalExpiryDate']);
    final payUntilText = payUntilFormatted.isNotEmpty ? payUntilFormatted : '—';

    // Monthly rental fee formatted with 2 decimal places
    final rawFee = rental['monthlyRentalFee'];
    final feeNum = (rawFee is num) ? rawFee.toDouble() : double.tryParse(rawFee?.toString() ?? '');
    final monthlyFee = feeNum != null
        ? 'RM ${feeNum.toStringAsFixed(2)}/mth'
        : (rawFee != null ? 'RM $rawFee/mth' : '');
    final refundState = (rental['depositRefundStatus'] ?? '').toString().toUpperCase();
    final depositRefundComplete = refundState == 'SUCCEEDED' || refundState == 'NOT_REQUIRED';
    final depositIsReturned = const {'returned', 'refunded'}
        .contains((rental['depositStatus'] ?? '').toString().toLowerCase().trim());

    // Days calculation
    final totalRentalDaysRemaining = _calculateTotalRentalRemainingDays(rental);
    final daysRemaining = _calculateDaysUntilPayDate(rental);
    final isOverdue = category == 'overdue';
    final isInBuffer = !isOverdue && daysRemaining <= 0 &&
        (category == 'active' || category == 'returning');
    final bufferDaysRemaining = isInBuffer ? _calculateBufferDaysRemaining(rental) : 0;

    // Check if fully paid: endDate <= rentalExpiryDate
    bool isFullyPaid = false;
    bool isContractEnded = false;
    final endStr = rental['endDate']?.toString();
    final expiryStr = rental['rentalExpiryDate']?.toString();
    if (endStr != null && endStr.isNotEmpty) {
      try {
        final parsedEnd = DateTime.parse(endStr);
        final endDay = DateTime(parsedEnd.year, parsedEnd.month, parsedEnd.day);
        final now = DateTime.now();
        isContractEnded = endDay.isBefore(DateTime(now.year, now.month, now.day));
      } catch (_) {}
    }
    if (endStr != null && endStr.isNotEmpty && expiryStr != null && expiryStr.isNotEmpty) {
      try {
        final end = DateTime.parse(endStr);
        final expiry = DateTime.parse(expiryStr);
        final endD = DateTime(end.year, end.month, end.day);
        final expD = DateTime(expiry.year, expiry.month, expiry.day);
        if (expD.isAtSameMomentAs(endD) || expD.isAfter(endD)) {
          isFullyPaid = true;
        }
      } catch (_) {}
    }

    void navigateToDetail() {
      // Returning, completed, and overdue tabs should not redirect to any detail page
      if (category == 'returning' || category == 'completed' || category == 'overdue' || isOverdue) {
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RentalDeviceDetailPage(
            rental: rental,
            email: widget.email,
            name: widget.name,
          ),
        ),
      );
    }

    void navigateToPayConfirmation() {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RentalPaymentConfirmationPage(
            rental: rental,
            email: widget.email,
            name: widget.name,
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: navigateToDetail,
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: isOverdue ? const Color(0xFFF5F3FF) : const Color(0xFFEFF4FF),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isOverdue ? const Color(0xFFDDD6FE) : const Color(0xFFDBEAFE),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top section with Status Tag and Phone Image
          Stack(
            children: [
              // Phone Image inside rounded upper area
              Container(
                height: 190,
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                alignment: Alignment.center,
                child: imageUrl.isNotEmpty
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => const Icon(Icons.phone_android, size: 70, color: Colors.grey),
                      )
                    : const Icon(Icons.phone_android, size: 70, color: Colors.grey),
              ),

              // Status Pill Tag
              Positioned(
                top: 14,
                left: 14,
                child: _buildStatusPill(
                  isOverdue,
                  category,
                  depositRefundComplete: depositRefundComplete,
                  depositIsReturned: depositIsReturned,
                  isMissing: isMissing,
                ),
              ),
            ],
          ),

          // Bottom White Details Area
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(23),
                bottomRight: Radius.circular(23),
              ),
            ),
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title & Monthly Fee Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    if (monthlyFee.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: Text(
                          monthlyFee,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF003F9E),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                // Rental ID
                Text(
                  'ID:  $rentalID',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),

                // Grey Summary Box (PERIOD & RENTAL PAY UNTIL with their remaining days)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFF1F5F9)),
                  ),
                  child: Column(
                    children: [
                      // Row 1: PERIOD & Total Remaining Rental Period (current date until endDate)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'PERIOD',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF64748B),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  periodText,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                totalRentalDaysRemaining < 0 ? 'PERIOD ENDED' : 'REMAINING',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF64748B),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                totalRentalDaysRemaining < 0
                                    ? 'Ended'
                                    : '$totalRentalDaysRemaining Days',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Divider(height: 1, color: Color(0xFFE2E8F0)),
                      ),

                      // Row 2: RENTAL PAY UNTIL & Remaining Period (current day until rental pay until date)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'RENTAL PAY UNTIL',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF64748B),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  payUntilText,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                isOverdue
                                    ? 'LATE BY'
                                    : isInBuffer
                                        ? 'BUFFER DAYS LEFT'
                                        : 'REMAINING',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: isOverdue ? const Color(0xFFEA580C) : const Color(0xFF64748B),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isOverdue
                                    ? '${daysRemaining.abs()} Days'
                                    : isInBuffer
                                        ? (bufferDaysRemaining == 0
                                            ? 'Ends today'
                                            : '$bufferDaysRemaining Days')
                                        : '$daysRemaining Days',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: isOverdue ? const Color(0xFFEA580C) : const Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Action Buttons
                if (category == 'active') ...[
                  // Pay Rental Button (Disabled with gray overlay when endDate == rentalExpiryDate)
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: isFullyPaid ? null : navigateToPayConfirmation,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0C5AD2),
                        disabledBackgroundColor: const Color(0xFFCBD5E1),
                        disabledForegroundColor: const Color(0xFF94A3B8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      icon: Icon(
                        Icons.payments_outlined,
                        color: isFullyPaid ? const Color(0xFF94A3B8) : Colors.white,
                        size: 18,
                      ),
                      label: Text(
                        isFullyPaid ? 'Rental Fully Paid' : 'Pay Rental',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isFullyPaid ? const Color(0xFF94A3B8) : Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Renew & Return Row
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final updated = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => RentalRenewPage(
                                  rental: rental,
                                  email: widget.email,
                                  name: widget.name,
                                ),
                              ),
                            );
                            if (updated == true && mounted) {
                              _loadRentals();
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Renew',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final returned = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => RentalReturnPage(
                                  rental: rental,
                                  email: widget.email,
                                  name: widget.name ?? 'Customer',
                                ),
                              ),
                            );
                            if (returned == true && mounted) {
                              _loadRentals();
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Return',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else if (isOverdue) ...[
                  // 1. Pay balance & continue (Primary action)
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: isContractEnded ? null : () async {
                        final updated = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => RentalOverdueLockedPage(
                              rental: rental,
                              email: widget.email,
                              name: widget.name,
                            ),
                          ),
                        );
                        if (updated == true && mounted) {
                          _loadRentals();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0C5AD2),
                        disabledBackgroundColor: const Color(0xFFCBD5E1),
                        disabledForegroundColor: const Color(0xFF94A3B8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      icon: Icon(Icons.sync_rounded, color: isContractEnded ? const Color(0xFF94A3B8) : Colors.white, size: 18),
                      label: Text(
                        'Pay balance & continue',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isContractEnded ? const Color(0xFF94A3B8) : Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // 2 & 3. Pay balance & return | Report missing
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final returned = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => RentalOverdueLockedPage(
                                  rental: rental,
                                  email: widget.email,
                                  name: widget.name,
                                  returnAfterPayment: true,
                                ),
                              ),
                            );
                            if (returned == true && mounted) {
                              _loadRentals();
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'Pay balance & return',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _handleReportMissing(context, rental),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFF1F2),
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                            side: const BorderSide(color: Color(0xFFFECDD3)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.error_outline, size: 16, color: Color(0xFFDC2626)),
                                SizedBox(width: 6),
                                Text(
                                  'Report missing',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFDC2626),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else if (category == 'returning') ...[
                  // Returning Banner: "Please return from [endDate] to [bufferDate (endDate + 3 days)]"
                  Builder(
                    builder: (context) {
                      String startReturnStr = endFormatted.isNotEmpty ? endFormatted : 'today';
                      String bufferReturnStr = '';
                      try {
                        DateTime? baseDt;
                        if (rental['endDate'] != null) {
                          baseDt = DateTime.tryParse(rental['endDate'].toString());
                        }
                        baseDt ??= DateTime.now();
                        final bufferDt = baseDt.add(const Duration(days: 3));
                        bufferReturnStr = DateFormat('dd MMM yyyy').format(bufferDt);
                        if (rental['endDate'] != null) {
                          startReturnStr = DateFormat('dd MMM yyyy').format(baseDt);
                        }
                      } catch (_) {
                        bufferReturnStr = 'within 3 days';
                      }

                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Icon(Icons.info_outline, color: Color(0xFF1D4ED8), size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Please return between $startReturnStr to $bufferReturnStr',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1E40AF),
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ] else if (category == 'completed' && (depositRefundComplete || depositIsReturned)) ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _showDepositRefundBreakdown(rental),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      foregroundColor: depositRefundComplete ? const Color(0xFF15803D) : const Color(0xFF1D4ED8),
                      side: BorderSide(color: depositRefundComplete ? const Color(0xFF86EFAC) : const Color(0xFFBFDBFE)),
                      backgroundColor: depositRefundComplete ? const Color(0xFFF0FDF4) : const Color(0xFFEFF6FF),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: Icon(depositRefundComplete ? Icons.receipt_long_outlined : Icons.hourglass_top_rounded, size: 18),
                      label: Text(
                        depositRefundComplete ? 'Deposit Refunded' : 'Refund Processing',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ] else ...[
                  // Completed
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isMissing ? 'Device Reported Missing' : 'Rental Completed',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
  }

  Widget _buildStatusPill(
    bool isOverdue,
    String category, {
    bool depositRefundComplete = false,
    bool depositIsReturned = false,
    bool isMissing = false,
  }) {
    if (isOverdue) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFFECE6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFFCCBD)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFEA580C)),
            SizedBox(width: 4),
            Text(
              'Overdue',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: Color(0xFFEA580C),
              ),
            ),
          ],
        ),
      );
    }

    if (category == 'returning') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFEEF2FF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFC7D2FE)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sync, size: 14, color: Color(0xFF4F46E5)),
            SizedBox(width: 4),
            Text(
              'Returning',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: Color(0xFF4F46E5),
              ),
            ),
          ],
        ),
      );
    }

    if (category == 'completed') {
      if (isMissing) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFFEE2E2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFECACA)),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.report_outlined, size: 14, color: Color(0xFFB91C1C)),
            SizedBox(width: 4),
            Text('Missing', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFFB91C1C))),
          ]),
        );
      }
      final isRefundProcessing = depositIsReturned && !depositRefundComplete;
      final label = depositRefundComplete
          ? 'Deposit Refunded'
          : isRefundProcessing
              ? 'Refund Processing'
              : 'Completed';
      final color = depositRefundComplete
          ? const Color(0xFF15803D)
          : isRefundProcessing
              ? const Color(0xFF1D4ED8)
              : const Color(0xFF64748B);
      final background = depositRefundComplete
          ? const Color(0xFFDCFCE7)
          : isRefundProcessing
              ? const Color(0xFFEFF6FF)
              : const Color(0xFFF1F5F9);
      final border = depositRefundComplete
          ? const Color(0xFFBBF7D0)
          : isRefundProcessing
              ? const Color(0xFFBFDBFE)
              : const Color(0xFFE2E8F0);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(20), border: Border.all(color: border)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            depositRefundComplete
                ? Icons.check_circle_outline
                : isRefundProcessing
                    ? Icons.hourglass_top_rounded
                    : Icons.check_circle,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: color)),
        ]),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFDBEAFE),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, size: 14, color: Color(0xFF2563EB)),
          SizedBox(width: 4),
          Text(
            'Active',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2563EB),
            ),
          ),
        ],
      ),
    );
  }
}
