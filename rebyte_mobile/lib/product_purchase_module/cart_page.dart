import 'package:flutter/material.dart';
import 'models/cart_item_model.dart';
import 'services/shop_service.dart';
import 'checkout_page.dart';

class CartPage extends StatefulWidget {
  final bool isLoggedIn;
  final String? email;
  final String? name;
  final VoidCallback? onCartUpdated;

  const CartPage({
    super.key,
    required this.isLoggedIn,
    this.email,
    this.name,
    this.onCartUpdated,
  });

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  List<CartItemModel> _cartItems = [];
  bool _isLoading = true;
  bool _isDeleting = false;
  String? _toastMessage;
  bool _isToastError = false;

  @override
  void initState() {
    super.initState();
    _loadCart(forceRefresh: true);
  }

  void _showTopToast(String message, {bool isError = false}) {
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

  Future<void> _loadCart({bool forceRefresh = false}) async {
    if (widget.email == null || widget.email!.isEmpty) {
      setState(() {
        _cartItems = [];
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);
    final items = await ShopService.fetchCart(email: widget.email!, forceRefresh: forceRefresh);
    if (mounted) {
      setState(() {
        _cartItems = items;
        _isLoading = false;
      });
    }
  }

  Future<void> _removeItem(CartItemModel item) async {
    if (widget.email == null || widget.email!.isEmpty) return;

    final pid = item.productID;
    setState(() {
      _cartItems.removeWhere((i) => i.productID == pid);
    });

    final success = await ShopService.removeFromCart(
      email: widget.email!,
      productID: pid,
    );

    if (mounted) {
      if (success) {
        widget.onCartUpdated?.call();
        _showTopToast('${item.displayTitle} has been removed from cart');
      } else {
        _loadCart(forceRefresh: true);
        _showTopToast('Failed to remove item', isError: true);
      }
    }
  }

  /// Batch delete all currently selected items (or sold items)
  Future<void> _handleBatchDelete() async {
    final selectedItems = _cartItems.where((i) => i.isSelected).toList();
    if (selectedItems.isEmpty) {
      _showTopToast('Please select at least one item to delete', isError: true);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Selected Items', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text(
          'Are you sure you want to remove ${selectedItems.length} selected items from your cart?',
          textAlign: TextAlign.justify,
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isDeleting = true);

    final allSuccess = await ShopService.removeManyFromCart(
      email: widget.email!,
      productIDs: selectedItems.map((item) => item.productID).toList(),
    );

    if (mounted) {
      setState(() => _isDeleting = false);
      widget.onCartUpdated?.call();
      if (allSuccess) {
        final removedIds = selectedItems.map((item) => item.productID).toSet();
        setState(() => _cartItems.removeWhere((item) => removedIds.contains(item.productID)));
      } else {
        await _loadCart(forceRefresh: true);
      }
      if (!mounted) return;

      _showTopToast(
        allSuccess ? '${selectedItems.length} items removed from cart' : 'Some items could not be removed',
        isError: !allSuccess,
      );
    }
  }

  /// Batch purchase selected non-sold items via dedicated Checkout Page
  Future<void> _handleProceedToCheckout() async {
    final selectedPurchasableItems = _cartItems
        .where((i) => i.isSelected && !i.isSold)
        .toList();

    if (selectedPurchasableItems.isEmpty) {
      _showTopToast('Please select at least one available item to checkout', isError: true);
      return;
    }

    // Navigate to CheckoutPage
    final purchased = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => CheckoutPage(
          email: widget.email!,
          name: widget.name,
          items: selectedPurchasableItems,
          onCartUpdated: widget.onCartUpdated,
        ),
      ),
    );

    if (purchased == true && mounted) {
      widget.onCartUpdated?.call();
      final purchasedIds = selectedPurchasableItems.map((i) => i.productID).toSet();
      setState(() => _cartItems.removeWhere((item) => purchasedIds.contains(item.productID)));
      await _loadCart(forceRefresh: true);
    }
  }

  void _toggleSelectAll(bool select) {
    setState(() {
      for (final item in _cartItems) {
        item.isSelected = select;
      }
    });
  }

  double _calculateSubtotal() {
    double sum = 0.0;
    for (final item in _cartItems) {
      if (item.isSelected && !item.isSold) {
        sum += item.sellingPrice;
      }
    }
    return sum;
  }

  // NO TAX CHARGED
  double _calculateTotal() {
    return _calculateSubtotal();
  }

  int get _selectedCount {
    return _cartItems.where((i) => i.isSelected && !i.isSold).length;
  }

  bool get _isAllSelected {
    return _cartItems.isNotEmpty && _cartItems.every((i) => i.isSelected);
  }

  @override
  Widget build(BuildContext context) {
    final hasSelectedItems = _cartItems.any((i) => i.isSelected);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/rebyte_logo.png', height: 36),
            const SizedBox(width: 8),
            const Text(
              'ReByte',
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ],
        ),
        actions: const [],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF0C5AD2)),
                  )
                : Column(
                    children: [
                      // Scrollable cart items area
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: () => _loadCart(forceRefresh: true),
                          color: const Color(0xFF0C5AD2),
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Header with item count & Select All / Batch Delete
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Shopping Cart',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    Text(
                                      '${_cartItems.length} Items',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF64748B),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                if (_cartItems.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: Checkbox(
                                              value: _isAllSelected,
                                              activeColor: const Color(0xFF0C5AD2),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                              onChanged: (val) => _toggleSelectAll(val ?? false),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          GestureDetector(
                                            onTap: () => _toggleSelectAll(!_isAllSelected),
                                            child: const Text(
                                              'Select All',
                                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (hasSelectedItems)
                                        TextButton.icon(
                                          onPressed: _isDeleting ? null : _handleBatchDelete,
                                          icon: const Icon(Icons.delete_outline, size: 16, color: Color(0xFFEF4444)),
                                          label: Text(
                                            'Delete Selected (${_cartItems.where((i) => i.isSelected).length})',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFFEF4444),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 12),
                                if (_cartItems.isEmpty)
                                  _buildEmptyState()
                                else
                                  ListView.separated(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: _cartItems.length,
                                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                                    itemBuilder: (context, index) {
                                      final item = _cartItems[index];
                                      return _buildCartItemCard(item);
                                    },
                                  ),
                                const SizedBox(height: 16),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Sticky Order Summary with Proceed to Checkout button at the bottom
                      if (_cartItems.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 10,
                                offset: const Offset(0, -3),
                              ),
                            ],
                          ),
                          child: _buildOrderSummary(),
                        ),
                    ],
                  ),
          // Consistent ReByte top toast
          if (_toastMessage != null)
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: Dismissible(
                key: UniqueKey(),
                direction: DismissDirection.horizontal,
                onDismissed: (_) => setState(() => _toastMessage = null),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: _isToastError ? Colors.red.shade600 : Colors.green.shade600,
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
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _toastMessage!,
                            textAlign: TextAlign.justify,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
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

  Widget _buildCartItemCard(CartItemModel item) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Checkbox
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: item.isSelected,
                      activeColor: const Color(0xFF0C5AD2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      onChanged: (val) {
                        setState(() {
                          item.isSelected = val ?? false;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Image thumbnail
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Image.network(
                      item.imageUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          Icon(Icons.smartphone, size: 36, color: Colors.grey.shade400),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                item.displayTitle,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // Red bin icon for single delete
                            InkWell(
                              onTap: () => _removeItem(item),
                              child: const Padding(
                                padding: EdgeInsets.all(4.0),
                                child: Icon(
                                  Icons.delete_outline,
                                  color: Color(0xFFEF4444), // RED BIN ICON
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE0F2FE),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.thumb_up_alt_outlined, size: 10, color: Color(0xFF0284C7)),
                                  const SizedBox(width: 3),
                                  Text(
                                    item.condition,
                                    style: const TextStyle(
                                      color: Color(0xFF0284C7),
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                item.displaySpecs,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF64748B),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'RM${item.sellingPrice.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Elegant muted translucent overlay with "Sold Out" badge and quick remove
            if (item.isSold)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.78),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFFCA5A5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.remove_circle_outline, size: 13, color: Color(0xFFDC2626)),
                            SizedBox(width: 4),
                            Text(
                              'Sold Out',
                              style: TextStyle(
                                color: Color(0xFFDC2626),
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      InkWell(
                        onTap: () => _removeItem(item),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.grey.shade300),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.delete_outline, size: 15, color: Color(0xFFEF4444)),
                              SizedBox(width: 4),
                              Text(
                                'Remove',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFEF4444),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderSummary() {
    final subtotal = _calculateSubtotal();
    final total = _calculateTotal();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
            'Order Summary',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 16),
          _buildSummaryRow(
            'Selected Items ($_selectedCount)',
            'RM${subtotal.toStringAsFixed(2)}',
          ),
          const SizedBox(height: 10),
          _buildSummaryRow('Estimated Shipping', 'Free'),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12.0),
            child: Divider(color: Color(0xFFE2E8F0), height: 1),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              Text(
                'RM${total.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0C5AD2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selectedCount == 0 ? null : _handleProceedToCheckout,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0C5AD2),
                disabledBackgroundColor: Colors.grey.shade300,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Proceed to Checkout ($_selectedCount)',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward, size: 16, color: Colors.white),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text(
            'Your cart is empty',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Explore our products in the Shop tab and add them to your cart.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
          ),
        ],
      ),
    );
  }
}
