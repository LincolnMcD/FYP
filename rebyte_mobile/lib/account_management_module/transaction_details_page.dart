import 'package:flutter/material.dart';
import '../widgets/rebyte_app_bar.dart';
import '../widgets/rebyte_bottom_nav_bar.dart';
import 'models/customer_transaction_model.dart';
import 'services/session_service.dart';

class TransactionDetailsPage extends StatefulWidget {
  final CustomerTransactionModel transaction;

  const TransactionDetailsPage({
    super.key,
    required this.transaction,
  });

  @override
  State<TransactionDetailsPage> createState() => _TransactionDetailsPageState();
}

class _TransactionDetailsPageState extends State<TransactionDetailsPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String? _userName;
  String? _userEmail;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    try {
      final session = await SessionService.getSession();
      if (mounted && session.isNotEmpty) {
        setState(() {
          _userName = session['name'];
          _userEmail = session['email'];
        });
      }
    } catch (_) {}
  }

  String _formatCurrency(double amount) {
    final parts = amount.toStringAsFixed(2).split('.');
    final intPart = parts[0];
    final decPart = parts[1];
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final formattedInt = intPart.replaceAllMapped(reg, (Match m) => '${m[1]},');
    return '$formattedInt.$decPart';
  }

  String _formatDateTimeString(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr);
      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      final month = months[dt.month - 1];
      final day = dt.day;
      final year = dt.year;
      final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      return '$month $day, $year at $hour:$minute $period';
    } catch (_) {
      return widget.transaction.formattedDate.isNotEmpty
          ? widget.transaction.formattedDate
          : 'Recent';
    }
  }

  @override
  Widget build(BuildContext context) {
    final tx = widget.transaction;
    final isCompleted = tx.status == 'completed';
    final isFailed = tx.status == 'failed';
    final sign = tx.isCredit ? '+' : '';

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: ReByteAppBar(
        scaffoldKey: _scaffoldKey,
      ),
      drawer: ReByteDrawer(
        isLoggedIn: true,
        email: _userEmail,
        name: _userName,
        selectedIndex: -1,
      ),
      bottomNavigationBar: const ReByteBottomNavBar(
        selectedIndex: -1,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
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

              // Page Title
              const Text(
                'Transactions Details',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F254B),
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 24),

              // Status Icon & Main Header
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isFailed
                            ? const Color(0xFFFEE2E2)
                            : const Color(0xFFDCFCE7),
                        border: Border.all(
                          color: isFailed
                              ? const Color(0xFFFCA5A5)
                              : const Color(0xFF86EFAC),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        isFailed ? Icons.close_rounded : Icons.check_rounded,
                        color: isFailed
                            ? const Color(0xFFEF4444)
                            : const Color(0xFF10B981),
                        size: 38,
                      ),
                    ),
                    const SizedBox(height: 14),

                    Text(
                      isFailed
                          ? 'Payment Failed'
                          : (tx.isCredit ? 'Payout Successful' : 'Payment Successful'),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 6),

                    Text(
                      _formatDateTimeString(tx.date),
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Big Amount
                    Text(
                      '$sign${tx.amount == 0 ? "RM0.00" : "RM" + _formatCurrency(tx.amount)}',
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0043CE),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Status Pill Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: isFailed
                            ? const Color(0xFFFEE2E2)
                            : const Color(0xFFE6F7F0),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isFailed
                              ? const Color(0xFFFECACA)
                              : const Color(0xFFA7F3D0),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isFailed
                                  ? const Color(0xFFEF4444)
                                  : const Color(0xFF10B981),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            tx.status.toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: isFailed
                                  ? const Color(0xFFDC2626)
                                  : const Color(0xFF059669),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Card 1: Transaction Info
              _buildSectionCard(
                icon: Icons.info_outline_rounded,
                title: 'Transaction Info',
                child: Column(
                  children: [
                    _buildInfoRow(
                      tx.type == 'trade-in'
                          ? 'Trade-In Request ID'
                          : (tx.type == 'rental' ? 'Rental ID' : 'Order ID'),
                      tx.transactionId,
                    ),
                    if (tx.rawTransactionId != null &&
                        tx.rawTransactionId!.isNotEmpty &&
                        tx.rawTransactionId != tx.transactionId) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10.0),
                        child: Divider(color: Color(0xFFF1F5F9), height: 1),
                      ),
                      _buildInfoRow('Transaction ID', tx.rawTransactionId!),
                    ],
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10.0),
                      child: Divider(color: Color(0xFFF1F5F9), height: 1),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Payment Method',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Row(
                          children: [
                            const Icon(
                              Icons.credit_card,
                              size: 16,
                              color: Color(0xFF475569),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              tx.paymentMethod,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
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

              // Card 2: Related Items (displays all items in multi-item orders)
              _buildSectionCard(
                icon: Icons.devices_other_rounded,
                title: (tx.relatedItems.length > 1)
                    ? 'Related Items (${tx.relatedItems.length})'
                    : 'Related Item',
                child: Column(
                  children: [
                    for (int i = 0; i < (tx.relatedItems.isNotEmpty ? tx.relatedItems.length : 1); i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      _buildRelatedItemCard(
                        tx.relatedItems.isNotEmpty ? tx.relatedItems[i] : tx.relatedItem,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Card 3: Payment Breakdown (only base amount and total)
              _buildSectionCard(
                icon: Icons.receipt_long_outlined,
                title: 'Payment Breakdown',
                child: Column(
                  children: [
                    _buildInfoRow(
                      'Base Amount',
                      'RM${_formatCurrency(tx.breakdown.baseAmount > 0 ? tx.breakdown.baseAmount : tx.amount)}',
                    ),
                    const SizedBox(height: 12),
                    // Dashed divider line
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final boxWidth = constraints.constrainWidth();
                        const dashWidth = 5.0;
                        const dashSpace = 4.0;
                        final dashCount = (boxWidth / (dashWidth + dashSpace)).floor();
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(dashCount, (_) {
                            return const SizedBox(
                              width: dashWidth,
                              height: 1,
                              child: DecoratedBox(
                                decoration: BoxDecoration(color: Color(0xFFCBD5E1)),
                              ),
                            );
                          }),
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          tx.isCredit ? 'Total Received' : 'Total Paid',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          'RM${_formatCurrency(tx.breakdown.totalPaid > 0 ? tx.breakdown.totalPaid : tx.amount)}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0043CE),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFF0F5FC2)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  Widget _buildRelatedItemCard(TransactionRelatedItem item) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Thumbnail
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            clipBehavior: Clip.antiAlias,
            child: item.imageUrl.isNotEmpty
                ? Image.network(
                    item.imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (ctx, err, stack) => const Icon(
                      Icons.phone_iphone_rounded,
                      color: Color(0xFF94A3B8),
                      size: 30,
                    ),
                  )
                : const Icon(
                    Icons.phone_iphone_rounded,
                    color: Color(0xFF94A3B8),
                    size: 30,
                  ),
          ),
          const SizedBox(width: 14),

          // Item Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Builder(
                  builder: (context) {
                    final List<String> details = [];
                    // Real IMEI (only when it is not a DEV ID)
                    if (item.imei.isNotEmpty && item.imei != 'N/A' && !item.imei.startsWith('DEV')) {
                      details.add('IMEI: ${item.imei}');
                    }
                    // Device ID (DEV-XXXX)
                    if (item.deviceID.isNotEmpty && item.deviceID != 'N/A') {
                      details.add('ID: ${item.deviceID}');
                    } else if (item.imei.startsWith('DEV')) {
                      details.add('ID: ${item.imei}');
                    }
                    // Storage and color specs
                    final specs = [item.storage, item.color].where((s) => s.isNotEmpty).join(' • ');
                    if (specs.isNotEmpty) {
                      details.add(specs);
                    }

                    return Text(
                      details.isNotEmpty ? details.join(' • ') : 'Certified Pre-Owned',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
