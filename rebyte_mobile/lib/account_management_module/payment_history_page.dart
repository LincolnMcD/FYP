import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/rebyte_app_bar.dart';
import '../widgets/rebyte_bottom_nav_bar.dart';
import 'models/customer_transaction_model.dart';
import 'services/payment_history_service.dart';
import 'services/session_service.dart';
import 'transaction_details_page.dart';

class PaymentHistoryPage extends StatefulWidget {
  final String email;
  final String? name;

  const PaymentHistoryPage({
    super.key,
    required this.email,
    this.name,
  });

  @override
  State<PaymentHistoryPage> createState() => _PaymentHistoryPageState();
}

class _PaymentHistoryPageState extends State<PaymentHistoryPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _searchController = TextEditingController();

  List<CustomerTransactionModel> _transactions = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  String _selectedFilter = 'All'; // 'All', 'Purchases', 'Trade-Ins', 'Rentals'
  Timer? _searchDebounce;
  String? _userName;

  final List<String> _filterTabs = ['All', 'Purchases', 'Trade-Ins', 'Rentals'];

  @override
  void initState() {
    super.initState();
    _userName = widget.name;
    _loadUserInfo();
    _fetchInitialTransactions();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUserInfo() async {
    try {
      final session = await SessionService.getSession();
      if (mounted && session.isNotEmpty) {
        setState(() {
          _userName = session['name'] ?? widget.name;
        });
      }
    } catch (_) {}
  }

  String _mapFilterToType(String filter) {
    switch (filter) {
      case 'Purchases':
        return 'purchase';
      case 'Trade-Ins':
        return 'trade-in';
      case 'Rentals':
        return 'rental';
      default:
        return 'all';
    }
  }

  Future<void> _fetchInitialTransactions() async {
    setState(() => _isLoading = true);

    final res = await PaymentHistoryService.fetchTransactions(
      email: widget.email,
      type: _mapFilterToType(_selectedFilter),
      limit: 5,
      offset: 0,
      searchId: _searchController.text.trim(),
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (res.success) {
          _transactions = res.transactions;
          _hasMore = res.hasMore;
        } else {
          _transactions = [];
          _hasMore = false;
        }
      });
    }
  }

  Future<void> _loadMoreTransactions() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);

    final res = await PaymentHistoryService.fetchTransactions(
      email: widget.email,
      type: _mapFilterToType(_selectedFilter),
      limit: 10,
      offset: _transactions.length,
      searchId: _searchController.text.trim(),
    );

    if (mounted) {
      setState(() {
        _isLoadingMore = false;
        if (res.success) {
          _transactions.addAll(res.transactions);
          _hasMore = res.hasMore;
        }
      });
    }
  }

  void _onSearchChanged(String val) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _fetchInitialTransactions();
    });
  }

  void _onFilterSelected(String filter) {
    if (_selectedFilter == filter) return;
    setState(() {
      _selectedFilter = filter;
    });
    _fetchInitialTransactions();
  }

  String _formatCurrency(double amount) {
    final parts = amount.toStringAsFixed(2).split('.');
    final intPart = parts[0];
    final decPart = parts[1];
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final formattedInt = intPart.replaceAllMapped(reg, (Match m) => '${m[1]},');
    return '$formattedInt.$decPart';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: ReByteAppBar(
        scaffoldKey: _scaffoldKey,
      ),
      drawer: ReByteDrawer(
        isLoggedIn: true,
        email: widget.email,
        name: _userName,
        selectedIndex: -1,
      ),
      bottomNavigationBar: const ReByteBottomNavBar(
        selectedIndex: -1,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchInitialTransactions,
          color: const Color(0xFF0C5AD2),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Back Button
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A), size: 22),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(height: 14),

                // Title
                const Text(
                  'Transactions',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F254B),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 18),

                // Search Bar (Strictly Search by ID)
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _fetchInitialTransactions(),
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF0F172A),
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search by ID...',
                      hintStyle: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF94A3B8),
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: Color(0xFF94A3B8),
                        size: 20,
                      ),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close, size: 18, color: Color(0xFF94A3B8)),
                              onPressed: () {
                                _searchController.clear();
                                _fetchInitialTransactions();
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Filter Tabs (Pill Buttons)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _filterTabs.map((tab) {
                      final isSelected = _selectedFilter == tab;
                      return Padding(
                        padding: const EdgeInsets.only(right: 10.0),
                        child: GestureDetector(
                          onTap: () => _onFilterSelected(tab),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF0C5AD2)
                                  : const Color(0xFFE6EEFA),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isSelected) ...[
                                  const Icon(Icons.check, size: 15, color: Colors.white),
                                  const SizedBox(width: 4),
                                ],
                                Text(
                                  tab,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected
                                        ? Colors.white
                                        : const Color(0xFF475569),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 20),

                // Transactions List
                if (_isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 60.0),
                      child: CircularProgressIndicator(color: Color(0xFF0C5AD2)),
                    ),
                  )
                else if (_transactions.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 60.0),
                      child: Column(
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 60,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'No transactions found',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _searchController.text.isNotEmpty
                                ? 'No transaction matching "${_searchController.text.trim()}"'
                                : 'You currently do not have any transactions under this category.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  ..._transactions.map((tx) => _buildTransactionCard(tx)),
                  const SizedBox(height: 16),

                  // Load More Transactions Button
                  if (_hasMore)
                    Center(
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton(
                          onPressed: _isLoadingMore ? null : _loadMoreTransactions,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                              color: Color(0xFF0C5AD2),
                              width: 1.2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            backgroundColor: Colors.white,
                          ),
                          child: _isLoadingMore
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF0C5AD2),
                                  ),
                                )
                              : const Text(
                                  'Load More Transactions',
                                  style: TextStyle(
                                    color: Color(0xFF0C5AD2),
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionCard(CustomerTransactionModel tx) {
    final isFailed = tx.status == 'failed';

    // Icon background and colors
    Color iconBg;
    Color iconColor;
    IconData iconData;

    if (isFailed) {
      iconBg = const Color(0xFFFEE2E2);
      iconColor = const Color(0xFFEF4444);
      iconData = Icons.credit_card_off_outlined;
    } else if (tx.type == 'trade-in') {
      iconBg = const Color(0xFFFFEDD5);
      iconColor = const Color(0xFFEA580C);
      iconData = Icons.autorenew_rounded;
    } else if (tx.type == 'rental') {
      iconBg = const Color(0xFFEEF2FF);
      iconColor = const Color(0xFF4F46E5);
      iconData = Icons.devices_other;
    } else {
      // Purchase
      iconBg = const Color(0xFFE0F7FA);
      iconColor = const Color(0xFF00838F);
      iconData = Icons.shopping_cart_outlined;
    }

    final sign = tx.isCredit ? '+' : '-';
    final categoryLabel = tx.type == 'trade-in'
        ? 'Trade-In'
        : (tx.type == 'rental' ? 'Rental' : 'Purchase');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => TransactionDetailsPage(transaction: tx),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
            child: Row(
              children: [
                // Icon Avatar
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: iconBg,
                  ),
                  child: Icon(
                    iconData,
                    color: iconColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),

                // Title & Subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tx.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${tx.formattedDate} • $categoryLabel',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),

                // ID, Amount & Status Badge
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '#${tx.transactionId.replaceAll('#', '')}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$sign${tx.amount == 0 ? "RM0.00" : "RM${_formatCurrency(tx.amount)}"}',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: tx.isCredit
                            ? const Color(0xFF0F172A)
                            : (isFailed ? const Color(0xFF64748B) : const Color(0xFF0F172A)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Status Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: isFailed
                            ? const Color(0xFFFEE2E2)
                            : const Color(0xFFE6F7F0),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isFailed ? Icons.error : Icons.check_circle,
                            size: 11,
                            color: isFailed
                                ? const Color(0xFFEF4444)
                                : const Color(0xFF10B981),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            tx.status.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: isFailed
                                  ? const Color(0xFFDC2626)
                                  : const Color(0xFF059669),
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
