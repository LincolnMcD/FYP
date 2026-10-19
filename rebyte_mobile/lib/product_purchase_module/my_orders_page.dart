import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'models/cart_item_model.dart';
import 'order_details_page.dart';
import 'services/shop_service.dart';
import '../account_management_module/models/address_model.dart';
import '../account_management_module/home_page.dart';
import '../../widgets/rebyte_app_bar.dart';

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadOrders();
  }

  @override
  void dispose() {
    _tabController.dispose();
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

  bool _isActiveOrder(String status) {
    final s = status.trim().toLowerCase();
    return s == 'pending' || s == 'delivering' || s == 'shipping' || s == 'confirmed' || s == 'in transit';
  }

  @override
  Widget build(BuildContext context) {
    final activeOrders = _orders.where((o) => _isActiveOrder(o['orderStatus']?.toString() ?? '')).toList();
    final pastOrders = _orders.where((o) => !_isActiveOrder(o['orderStatus']?.toString() ?? '')).toList();

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
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: 0, // Home Tab selected
          onTap: (index) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (context) => HomePage(
                  isLoggedIn: true,
                  email: widget.email,
                  name: widget.name,
                  initialIndex: index,
                ),
              ),
              (route) => false,
            );
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: const Color(0xFF0C5AD2),
          unselectedItemColor: Colors.grey.shade500,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
          unselectedLabelStyle: const TextStyle(fontSize: 10),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.shopping_bag_outlined), label: 'Shop'),
            BottomNavigationBarItem(icon: Icon(Icons.autorenew), label: 'Trade-In'),
            BottomNavigationBarItem(icon: Icon(Icons.calendar_month_outlined), label: 'Rentals'),
            BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Account'),
          ],
        ),
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
                tabs: const [
                  Tab(text: 'Active'),
                  Tab(text: 'Past Orders'),
                ],
              ),
            ),

            // Tab Views
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF0C5AD2)))
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildOrdersList(activeOrders, isActive: true),
                        _buildOrdersList(pastOrders, isActive: false),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersList(List<Map<String, dynamic>> orderList, {required bool isActive}) {
    if (orderList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              isActive ? 'No active orders' : 'No past orders',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
            ),
            const SizedBox(
              width: 280,
              child: Text(
                'Orders currently being processed or\nshipped will appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.4),
              ),
            ),
          ],
        ),
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
    final status = order['orderStatus']?.toString() ?? 'Shipping';
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
    AddressModel? address;
    if (order['deliveryAddress'] != null && order['deliveryAddress'] is Map) {
      address = AddressModel.fromJson(Map<String, dynamic>.from(order['deliveryAddress'] as Map));
    }

    final failReason = order['failReason']?.toString() ?? '';
    final isPast = !_isActiveOrder(status);

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
          // Order Number & Status Pill
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
              _buildStatusPill(status),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Placed on $formattedDate',
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
          ),
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
                onPressed: () {
                  Navigator.push(
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
                      ),
                    ),
                  );
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

  Widget _buildStatusPill(String status) {
    final s = status.toLowerCase();
    Color bgColor = const Color(0xFFDBEAFE);
    Color textColor = const Color(0xFF1D4ED8);
    IconData icon = Icons.local_shipping_outlined;

    if (s == 'delivered' || s == 'completed') {
      bgColor = const Color(0xFFDCFCE7);
      textColor = const Color(0xFF16A34A);
      icon = Icons.check_circle_outline;
    } else if (s == 'fail' || s == 'failed' || s == 'cancelled' || s == 'canceled') {
      bgColor = const Color(0xFFFEE2E2);
      textColor = const Color(0xFFDC2626);
      icon = Icons.cancel_outlined;
    } else if (s == 'delivering' || s == 'shipping') {
      bgColor = const Color(0xFFDBEAFE);
      textColor = const Color(0xFF1D4ED8);
      icon = Icons.local_shipping_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: textColor),
          const SizedBox(width: 4),
          Text(
            status[0].toUpperCase() + status.substring(1),
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
