import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'models/cart_item_model.dart';
import 'order_details_page.dart';
import 'services/shop_service.dart';
import '../account_management_module/models/address_model.dart';
import '../../widgets/rebyte_app_bar.dart';
import '../widgets/rebyte_bottom_nav_bar.dart';

class MyOrdersPage extends StatefulWidget {
  final String email;
  final String? name;

  const MyOrdersPage({
    super.key,
    required this.email,
    this.name,
  });

  @override
  State<MyOrdersPage> createState() => _MyOrdersPageState();
}

class _MyOrdersPageState extends State<MyOrdersPage> with SingleTickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late TabController _tabController;
  bool _isLoading = true;
  List<Map<String, dynamic>> _orders = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedActiveFilter = 'All'; // 'All', 'Self Pickup', 'Shipping', 'Packaging', 'Unassigned'

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadOrders();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    setState(() => _isLoading = true);
    final list = await ShopService.fetchOrders(email: widget.email);
    if (mounted) {
      setState(() {
        _orders = list;
        _isLoading = false;
      });
    }
  }

  String _getEffectiveStatus(Map<String, dynamic> order) {
    final status = order['orderStatus']?.toString().trim() ?? '';
    final taskStatus = order['taskStatus']?.toString().trim() ?? '';
    final os = status.toLowerCase();
    final ts = taskStatus.toLowerCase();

    // Past terminal statuses
    if (os == 'cancelled' || os == 'canceled') return 'Cancelled';
    if (os == 'fail' || os == 'failed') return 'Failed';
    if (os == 'delivered' || os == 'completed') return 'Completed';

    // 1. Self Pickup = order.status is self pickup (or terminated which means self pickup)
    if (os == 'self pickup' || os == 'self-pickup' || os == 'terminated') {
      return 'Self Pickup';
    }

    // 2. Shipping = order.status delivering and task.status is shipping
    if ((os == 'delivering' || os == 'shipping') && (ts == 'shipping' || ts == 'delivering' || ts == 'ongoing')) {
      return 'Shipping';
    }

    // 3. Packaging = order.status delivering and task.status is packaging
    if ((os == 'delivering' || os == 'packaging' || os == 'processing') &&
        (ts == 'packaging' || ts == 'packaged' || ts == 'packing' || ts == 'processing')) {
      return 'Packaging';
    }

    // 4. Unassigned = order.status = unassigned
    if (os == 'unassigned' || ts == 'unassigned' || os == 'rejected' || ts == 'rejected') {
      return 'Unassigned';
    }

    // Fallback: if order.status is delivering but taskStatus is shipping/delivering
    if (ts == 'shipping' || ts == 'delivering') return 'Shipping';
    if (ts == 'packaging') return 'Packaging';
    if (os == 'delivering') return 'Packaging';

    return status.isNotEmpty ? status : 'Packaging';
  }

  bool _isActiveOrder(Map<String, dynamic> order) {
    final status = order['orderStatus']?.toString().trim() ?? '';
    final taskStatus = order['taskStatus']?.toString().trim() ?? '';
    final os = status.toLowerCase();
    final ts = taskStatus.toLowerCase();

    // Terminal / Completed / Inactive statuses
    const pastStatuses = {
      'delivered',
      'completed',
      'cancelled',
      'canceled',
      'fail',
      'failed',
      'refunded',
      'returned',
    };

    if (pastStatuses.contains(os) || (ts.isNotEmpty && pastStatuses.contains(ts))) {
      return false;
    }

    return true;
  }

  DateTime _getOrderDate(Map<String, dynamic> order) {
    final paidAtStr = order['paidAt']?.toString() ?? order['orderDate']?.toString() ?? order['createdAt']?.toString();
    if (paidAtStr != null) {
      final parsed = DateTime.tryParse(paidAtStr);
      if (parsed != null) return parsed;
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  int _getStatusRank(String effectiveStatus) {
    // Required priority: Self pickup -> shipping -> packaging -> unassigned
    final s = effectiveStatus.toLowerCase().trim();
    if (s == 'self pickup' || s == 'self-pickup') return 1;
    if (s == 'shipping' || s == 'delivering' || s == 'ongoing') return 2;
    if (s == 'packaging' || s == 'packaged' || s == 'processing') return 3;
    if (s == 'unassigned' || s == 'pending' || s == 'rejected') return 4;
    return 5;
  }

  @override
  Widget build(BuildContext context) {
    // 1. Separate Active & Past Orders
    final rawActive = _orders.where((o) => _isActiveOrder(o)).toList();
    final rawPast = _orders.where((o) => !_isActiveOrder(o)).toList();

    // 2. Filter Active Orders by selected chip
    List<Map<String, dynamic>> filteredActive = rawActive;
    if (_selectedActiveFilter != 'All') {
      filteredActive = filteredActive.where((o) {
        final eff = _getEffectiveStatus(o).toLowerCase();
        final target = _selectedActiveFilter.toLowerCase();
        return eff == target;
      }).toList();
    }

    // 3. Search filter by ID only for both tabs
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase().replaceAll('#', '').trim();
      filteredActive = filteredActive.where((o) {
        final idStr = (o['orderNumber']?.toString() ?? o['orderID']?.toString() ?? '').toLowerCase().replaceAll('#', '').trim();
        return idStr.contains(q);
      }).toList();
    }

    List<Map<String, dynamic>> filteredPast = rawPast;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase().replaceAll('#', '').trim();
      filteredPast = filteredPast.where((o) {
        final idStr = (o['orderNumber']?.toString() ?? o['orderID']?.toString() ?? '').toLowerCase().replaceAll('#', '').trim();
        return idStr.contains(q);
      }).toList();
    }

    // 4. Sort Active orders:
    // First by status priority: Self pickup -> shipping -> packaging -> unassigned
    // In each status: sort by date (newest first)
    filteredActive.sort((a, b) {
      final rankA = _getStatusRank(_getEffectiveStatus(a));
      final rankB = _getStatusRank(_getEffectiveStatus(b));
      if (rankA != rankB) {
        return rankA.compareTo(rankB);
      }
      final dateA = _getOrderDate(a);
      final dateB = _getOrderDate(b);
      return dateB.compareTo(dateA); // newest date first within same status
    });

    // 5. Sort Past orders:
    // Just sort by date (newest first)
    filteredPast.sort((a, b) {
      final dateA = _getOrderDate(a);
      final dateB = _getOrderDate(b);
      return dateB.compareTo(dateA);
    });

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: ReByteAppBar(
        scaffoldKey: _scaffoldKey,
      ),
      drawer: ReByteDrawer(
        isLoggedIn: true,
        email: widget.email,
        name: widget.name,
        isMyOrdersSelected: true,
      ),
      bottomNavigationBar: const ReByteBottomNavBar(
        selectedIndex: -1,
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Navigation Row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B), size: 22),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => Navigator.pop(context),
              ),
            ),

            // Page Title
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'My Orders',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),

            // Search by ID only Box
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: TextField(
                  controller: _searchController,
                  textAlignVertical: TextAlignVertical.center,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search by Order ID only (e.g. 261022ORD00010)...',
                    hintStyle: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
                    prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF64748B)),
                    prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 42),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18, color: Color(0xFF64748B)),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 36, minHeight: 42),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 0),
                  ),
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val.trim();
                    });
                  },
                ),
              ),
            ),

            // Tabs: Active & Past Orders
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: const Color(0xFF0C5AD2),
                unselectedLabelColor: const Color(0xFF475569),
                indicatorColor: const Color(0xFF0C5AD2),
                indicatorWeight: 3,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                tabs: [
                  Tab(text: 'Active (${filteredActive.length})'),
                  Tab(text: 'Past Orders (${filteredPast.length})'),
                ],
              ),
            ),

            // Filter Chips for Active Tab
            if (_tabController.index == 0) ...[
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _buildFilterChip('All'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Self Pickup'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Shipping'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Packaging'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Unassigned'),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 8),

            // Tab Views
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF0C5AD2)))
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildOrdersList(filteredActive, isActive: true),
                        _buildOrdersList(filteredPast, isActive: false),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _selectedActiveFilter == label;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedActiveFilter = label;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0C5AD2) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF0C5AD2) : const Color(0xFFCBD5E1),
            width: 1.2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF0C5AD2).withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }

  Widget _buildOrdersList(List<Map<String, dynamic>> orderList, {required bool isActive}) {
    if (orderList.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight,
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 52, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text(
                        _searchQuery.isNotEmpty
                            ? 'No matching orders found'
                            : (isActive ? 'No active orders' : 'No past orders'),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: 280,
                        child: Text(
                          _searchQuery.isNotEmpty
                              ? 'No orders match ID "$_searchQuery"'
                              : (isActive
                                  ? 'Orders currently being processed, packaged,\nor self-pickup will appear here.'
                                  : 'Past and completed orders will appear here.'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B), height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    return RefreshIndicator(
      onRefresh: _loadOrders,
      color: const Color(0xFF0C5AD2),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: orderList.length,
        separatorBuilder: (_, _) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final order = orderList[index];
          return _buildOrderCard(order);
        },
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final orderNumber = order['orderNumber']?.toString() ?? '#RB-9921';
    final status = order['orderStatus']?.toString() ?? 'Packaging';
    final paidAtStr = order['paidAt']?.toString();
    DateTime paidAt = DateTime.now();
    if (paidAtStr != null) {
      paidAt = DateTime.tryParse(paidAtStr) ?? DateTime.now();
    }
    final formattedDate = DateFormat('MMM dd, yyyy').format(paidAt);

    final rawItems = order['items'] as List? ?? [];
    final List<CartItemModel> items = rawItems.map((item) {
      if (item is CartItemModel) return item;
      return CartItemModel.fromJson(Map<String, dynamic>.from(item as Map));
    }).toList();

    final totalAmount = (order['totalAmount'] as num?)?.toDouble() ?? 0.0;
    final paymentTitle = order['paymentTitle']?.toString() ?? 'Online Payment';
    final paymentType = order['paymentType']?.toString() ?? 'card';
    final paymentAccountID = order['paymentAccountID']?.toString() ?? '';
    final taskStatus = order['taskStatus']?.toString() ?? 'Packaging';
    final estimatedEndTime = order['estimatedEndTime']?.toString();
    final scheduleDate = order['scheduleDate']?.toString();
    final estimatedDuration = order['estimatedDuration'] != null ? NumberFormat().tryParse(order['estimatedDuration'].toString())?.toInt() : null;

    AddressModel? address;
    if (order['deliveryAddress'] != null && order['deliveryAddress'] is Map) {
      address = AddressModel.fromJson(Map<String, dynamic>.from(order['deliveryAddress'] as Map));
    }

    final failReason = order['failReason']?.toString() ?? '';
    final isPast = !_isActiveOrder(order);
    final isShipping = taskStatus.trim().toLowerCase() == 'shipping' || status.trim().toLowerCase() == 'shipping';
    final effectiveStatus = _getEffectiveStatus(order);

    // Format estimated arrival display
    String? estimatedArrivalText;
    if (isShipping && estimatedEndTime != null && estimatedEndTime.isNotEmpty) {
      final cleanTime = estimatedEndTime.contains('T')
          ? estimatedEndTime.split('T').last.split('.').first
          : (estimatedEndTime.length == 5 ? '$estimatedEndTime:00' : estimatedEndTime);
      final datePart = scheduleDate ?? DateFormat('yyyy-MM-dd').format(DateTime.now());
      final parsedDt = DateTime.tryParse('${datePart}T$cleanTime');
      if (parsedDt != null) {
        final formattedDateStr = DateFormat('MMM dd, yyyy').format(parsedDt);
        final formattedTimeStr = DateFormat('h:mm a').format(parsedDt);
        estimatedArrivalText = '$formattedDateStr by $formattedTimeStr';
      } else {
        estimatedArrivalText = '${scheduleDate ?? ''} $estimatedEndTime'.trim();
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Order Number & Live Status Pill
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text: 'Order ',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                    ),
                    TextSpan(
                      text: orderNumber,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                    ),
                  ],
                ),
              ),
              _buildTaskStatusPill(effectiveStatus),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Placed on $formattedDate',
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
          ),

          // Estimated Arrival Banner (when Shipping)
          if (isShipping && estimatedArrivalText != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.local_shipping_rounded, size: 16, color: Color(0xFF1D4ED8)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(
                            text: 'Estimated Arrival: ',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E3A8A)),
                          ),
                          TextSpan(
                            text: estimatedArrivalText,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF0C5AD2)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),

          // Items List inside Order Card
          for (final item in items) ...[
            _buildItemRow(item),
            const SizedBox(height: 10),
          ],

          const Divider(height: 20, color: Color(0xFFF1F5F9)),

          // Track Order / View Order Button
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              height: 38,
              child: ElevatedButton(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => OrderDetailsPage(
                        orderNumber: orderNumber,
                        amountPaid: totalAmount,
                        email: widget.email,
                        name: widget.name,
                        paidAt: paidAt,
                        items: items,
                        deliveryAddress: address,
                        paymentTitle: paymentTitle,
                        paymentType: paymentType,
                        paymentAccountID: paymentAccountID,
                        taskStatus: taskStatus,
                        orderStatus: status,
                        failReason: failReason,
                        estimatedEndTime: estimatedEndTime,
                        scheduleDate: scheduleDate,
                        estimatedDuration: estimatedDuration,
                      ),
                    ),
                  );
                  if (mounted) {
                    _loadOrders();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0C5AD2),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                ),
                child: Text(
                  isPast ? 'View Order' : 'Track Order',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildTaskStatusPill(String taskStatus) {
    var s = taskStatus.toLowerCase().trim();
    if (s == 'rejected') s = 'unassigned';
    Color bgColor = const Color(0xFFF1F5F9);
    Color textColor = const Color(0xFF475569);
    IconData icon = Icons.inventory_2_outlined;

    if (s == 'delivered' || s == 'completed') {
      bgColor = const Color(0xFFDCFCE7);
      textColor = const Color(0xFF16A34A);
      icon = Icons.check_circle_outline;
    } else if (s == 'self pickup' || s == 'self-pickup' || s == 'terminated') {
      bgColor = const Color(0xFFFEF3C7);
      textColor = const Color(0xFFB45309);
      icon = Icons.storefront_outlined;
    } else if (s == 'shipping' || s == 'delivering' || s == 'ongoing') {
      bgColor = const Color(0xFFE0E7FF);
      textColor = const Color(0xFF4338CA);
      icon = Icons.directions_car_outlined;
    } else if (s == 'packaging' || s == 'packaged' || s == 'packing' || s == 'processing' || s == 'confirmed') {
      bgColor = const Color(0xFFFEF3C7);
      textColor = const Color(0xFFD97706);
      icon = Icons.inventory_2_outlined;
    } else if (s == 'unassigned' || s == 'pending') {
      bgColor = const Color(0xFFEFF6FF);
      textColor = const Color(0xFF2563EB);
      icon = Icons.schedule_outlined;
    } else if (s == 'cancelled' || s == 'canceled' || s == 'failed' || s == 'fail') {
      bgColor = const Color(0xFFFEE2E2);
      textColor = const Color(0xFFDC2626);
      icon = Icons.error_outline;
    }

    final displayText = (s == 'unassigned')
        ? 'Unassigned'
        : (taskStatus.isNotEmpty
            ? (taskStatus[0].toUpperCase() + taskStatus.substring(1))
            : 'Packaging');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: textColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(
            displayText,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemRow(CartItemModel item) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Product Thumbnail
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            padding: const EdgeInsets.all(4),
            child: Image.network(
              item.imageUrl,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  Icon(Icons.smartphone, size: 28, color: Colors.grey.shade400),
            ),
          ),
          const SizedBox(width: 12),
          // Title & Spec details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.displayTitle,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  item.displaySpecs.isNotEmpty
                      ? '${item.displaySpecs} • ${item.condition} Condition'
                      : '${item.condition} Condition',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Price
          Text(
            'RM${item.sellingPrice.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }
}
