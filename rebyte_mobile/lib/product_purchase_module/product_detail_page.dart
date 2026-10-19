import 'package:flutter/material.dart';
import 'models/product_model.dart';
import 'models/cart_item_model.dart';
import 'services/shop_service.dart';
import 'checkout_page.dart';
import 'cart_page.dart';
import '../../account_management_module/welcome_page.dart';

class ProductDetailPage extends StatefulWidget {
  final ProductModel product;
  final bool isLoggedIn;
  final String? email;
  final String? name;
  final VoidCallback? onCartUpdated;

  const ProductDetailPage({
    super.key,
    required this.product,
    required this.isLoggedIn,
    this.email,
    this.name,
    this.onCartUpdated,
  });

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  late ProductModel _product;
  int _selectedImageIndex = 0;
  bool _isInCart = false;
  bool _isAddingToCart = false;
  String? _toastMessage;
  bool _isToastError = false;
  int _cartItemCount = 0;
  Map<String, dynamic>? _specData;
  bool _isLoadingSpecs = true;
  String _modelCode = '';
  String _deviceID = '';

  @override
  void initState() {
    super.initState();
    _product = widget.product;
    _modelCode = widget.product.modelCode;
    _deviceID = widget.product.deviceID;
    _checkCartStatus();
    _fetchSpecifications();
  }

  Future<void> _fetchSpecifications() async {
    setState(() => _isLoadingSpecs = true);
    try {
      final data = await ShopService.fetchProductSpecs(_product.productID, deviceID: _deviceID);
      if (mounted && data != null) {
        setState(() {
          _specData = data['specs'] as Map<String, dynamic>?;
          if (data['modelCode'] != null && data['modelCode'].toString().isNotEmpty) {
            _modelCode = data['modelCode'].toString();
          }
          if (data['deviceID'] != null && data['deviceID'].toString().isNotEmpty) {
            _deviceID = data['deviceID'].toString();
          }
          _isLoadingSpecs = false;
        });
        return;
      }
    } catch (e) {
      debugPrint('Error loading specs: $e');
    }
    if (mounted) {
      setState(() => _isLoadingSpecs = false);
    }
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

  Future<void> _checkCartStatus() async {
    if (!widget.isLoggedIn || widget.email == null || widget.email!.isEmpty) return;
    try {
      final cartItems = await ShopService.fetchCart(email: widget.email!);
      if (mounted) {
        setState(() {
          _cartItemCount = cartItems.length;
          _isInCart = cartItems.any((item) => item.productID == _product.productID);
        });
      }
    } catch (_) {}
  }

  Future<void> _handleAddToCart() async {
    if (_isInCart || _isAddingToCart) return;

    if (!widget.isLoggedIn || widget.email == null || widget.email!.isEmpty) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const WelcomePage()),
      );
      if (result == true) {
        widget.onCartUpdated?.call();
        _checkCartStatus();
      }
      return;
    }

    setState(() => _isAddingToCart = true);

    final success = await ShopService.addToCart(
      email: widget.email!,
      productID: _product.productID,
    );

    if (mounted) {
      setState(() => _isAddingToCart = false);
      if (success) {
        setState(() {
          _isInCart = true;
          _cartItemCount += 1;
        });
        widget.onCartUpdated?.call();
        _showTopToast('${_product.displayTitle} is added to cart');
      } else {
        _showTopToast('Failed to add item to cart. Please try again.', isError: true);
      }
    }
  }

  void _handleBuyNow() async {
    if (!widget.isLoggedIn || widget.email == null || widget.email!.isEmpty) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const WelcomePage()),
      );
      if (result == true) {
        widget.onCartUpdated?.call();
        _checkCartStatus();
      }
      return;
    }

    final singleCartItem = CartItemModel(
      productID: _product.productID,
      description: _product.description,
      sellingPrice: _product.sellingPrice,
      imageUrl: _product.imageUrl,
      isSold: _product.listingStatus == 'sold',
      listingStatus: _product.listingStatus,
      brand: _product.brand,
      model: _product.model,
      storage: _product.storage,
      ram: _product.ram,
      color: _product.color,
      condition: _product.condition,
      deviceID: _deviceID.isNotEmpty ? _deviceID : _product.deviceID,
      modelCode: _modelCode.isNotEmpty ? _modelCode : _product.modelCode,
      isSelected: true,
    );

    if (!mounted) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CheckoutPage(
          email: widget.email!,
          name: widget.name,
          items: [singleCartItem],
          onCartUpdated: () {
            widget.onCartUpdated?.call();
            _checkCartStatus();
          },
        ),
      ),
    );

    if (result == 'cancelled' || result == null) {
      if (mounted) {
        _showTopToast('Order has been cancelled', isError: true);
      }
    }

    _checkCartStatus();
  }

  void _openCartPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CartPage(
          isLoggedIn: widget.isLoggedIn,
          email: widget.email,
          name: widget.name,
          onCartUpdated: () {
            widget.onCartUpdated?.call();
            _checkCartStatus();
          },
        ),
      ),
    );
    _checkCartStatus();
  }

  @override
  Widget build(BuildContext context) {
    // Generate image list (product image + angles/fallbacks)
    final images = [
      _product.imageUrl,
      _product.imageUrl,
      _product.imageUrl,
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.of(context).pop(),
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
        actions: [
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.shopping_cart_outlined, color: Colors.black87),
                if (_cartItemCount > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Color(0xFFE11D48),
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        '$_cartItemCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: _openCartPage,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top Image Carousel Section
                  _buildImageGallery(images),
                  const SizedBox(height: 16),

                  // Side-by-side Inspection Cards: Battery Health & Detected Defects
                  _buildInspectionTopCards(),
                  const SizedBox(height: 16),

                  // Device Overall Condition Card
                  _buildOverallConditionCard(),
                  const SizedBox(height: 16),

                  // Pricing, Why This Price & Action Buttons
                  _buildProductActionCard(),
                  const SizedBox(height: 16),

                  // Specifications Section
                  _buildSpecificationsCard(),
                  const SizedBox(height: 32),
                ],
              ),
            ),

            // Top Floating Toast Banner (consistent with product page)
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

  Widget _buildImageGallery(List<String> images) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Condition badge on top-left of image
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFDEF7EC),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.verified, size: 14, color: Color(0xFF03543F)),
                    const SizedBox(width: 5),
                    Text(
                      _product.condition.isNotEmpty ? _product.condition : 'Brand New',
                      style: const TextStyle(
                        color: Color(0xFF03543F),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Main image with left/right arrows
          SizedBox(
            height: 190,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios, size: 18, color: Color(0xFF0F172A)),
                  onPressed: () {
                    setState(() {
                      _selectedImageIndex = (_selectedImageIndex - 1 + images.length) % images.length;
                    });
                  },
                ),
                Expanded(
                  child: Center(
                    child: Image.network(
                      images[_selectedImageIndex],
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => Icon(
                        Icons.smartphone,
                        size: 110,
                        color: Colors.grey.shade300,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward_ios, size: 18, color: Color(0xFF0F172A)),
                  onPressed: () {
                    setState(() {
                      _selectedImageIndex = (_selectedImageIndex + 1) % images.length;
                    });
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Thumbnail Row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(images.length, (index) {
              final isSelected = index == _selectedImageIndex;
              return GestureDetector(
                onTap: () => setState(() => _selectedImageIndex = index),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  width: 56,
                  height: 56,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF0C5AD2) : Colors.grey.shade300,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      images[index],
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => Icon(
                        Icons.phone_android,
                        size: 28,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildInspectionTopCards() {
    return Row(
      children: [
        // Battery Health Card
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.battery_charging_full, size: 18, color: Color(0xFF10B981)),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Battery\nHealth',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569), height: 1.2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  '98%',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: const [
                    Icon(Icons.check_circle_outline, size: 13, color: Color(0xFF10B981)),
                    SizedBox(width: 4),
                    Text(
                      'Passed\nInspection',
                      style: TextStyle(fontSize: 11, color: Color(0xFF10B981), fontWeight: FontWeight.w600, height: 1.1),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Detected Defects Card
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.search, size: 18, color: Color(0xFF0C5AD2)),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Detected\nDefects',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569), height: 1.2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'None',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Flawless\nenclosure',
                  style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500, height: 1.2),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOverallConditionCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Color(0xFF0C5AD2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shield_outlined, size: 16, color: Colors.white),
              ),
              const SizedBox(width: 10),
              const Text(
                'Device overall condition',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF334155),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            '98% (Grade A)',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 2),
          GestureDetector(
            onTap: () {
              _showTopToast('Viewing certified device assessment report');
            },
            child: const Text(
              'View Report',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF0C5AD2),
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Display & Touch
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text(
                'Display & Touch',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
              ),
              Text(
                'PASS',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: const LinearProgressIndicator(
              value: 1.0,
              backgroundColor: Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
              minHeight: 5,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'No scratches visible, TrueTone active.',
            style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 14),

          // Housing & Frame
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text(
                'Housing & Frame',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
              ),
              Text(
                'MINOR WEAR',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFF59E0B)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: const LinearProgressIndicator(
              value: 0.85,
              backgroundColor: Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF59E0B)),
              minHeight: 5,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Micro-abrasions near charging port. Grade A-.',
            style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 14),

          // Camera System
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text(
                'Camera System',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
              ),
              Text(
                'PASS',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: const LinearProgressIndicator(
              value: 1.0,
              backgroundColor: Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
              minHeight: 5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductActionCard() {
    final title = _product.displayTitle.isNotEmpty ? _product.displayTitle : 'iPhone 15 Pro 256GB';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 10),

          // Price
          Text(
            'RM${_product.sellingPrice.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Free shipping. Professional verified.',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 14),

          // Why this price? banner
          InkWell(
            onTap: () {
              _showTopToast('Transparent pricing based on condition & battery health.');
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: const [
                  Icon(Icons.info_outline, size: 18, color: Color(0xFF0C5AD2)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Why this price?',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 18, color: Color(0xFF64748B)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Add to Cart Button (disabled with gray overlay if already added to cart)
          GestureDetector(
            onTap: _isInCart
                ? () {
                    _showTopToast('${_product.displayTitle} already added to the cart', isError: true);
                  }
                : null,
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isInCart || _isAddingToCart ? null : _handleAddToCart,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0C5AD2),
                  disabledBackgroundColor: Colors.grey.shade300,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _isAddingToCart
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.shopping_cart,
                            size: 18,
                            color: _isInCart ? Colors.grey.shade600 : Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isInCart ? 'Added to Cart' : 'Add to Cart',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: _isInCart ? Colors.grey.shade600 : Colors.white,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Buy Now button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: _handleBuyNow,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF0F172A), width: 1.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'Buy Now',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Compare & Rent this device row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: () {
                  _showTopToast('Device comparison feature coming soon.');
                },
                child: Row(
                  children: const [
                    Icon(Icons.compare_arrows, size: 16, color: Color(0xFF64748B)),
                    SizedBox(width: 6),
                    Text(
                      'Compare',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: () {
                  _showTopToast('Rentals feature available in Rentals tab.');
                },
                child: Row(
                  children: const [
                    Icon(Icons.calendar_today_outlined, size: 15, color: Color(0xFF0C5AD2)),
                    SizedBox(width: 6),
                    Text(
                      'Rent this device',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0C5AD2)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSpecificationsCard() {
    if (_isLoadingSpecs) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: const [
            SizedBox(
              height: 28,
              width: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF0C5AD2)),
            ),
            SizedBox(height: 12),
            Text(
              'Loading product specifications...',
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    final specs = _specData ?? {};
    final List<Map<String, String>> rows = [];

    // 1. Display & Screen
    final screen = specs['screen']?.toString() ?? '';
    if (screen.isNotEmpty) {
      rows.add({'label': 'Display', 'value': screen});
    }

    // 2. Processor & GPU
    final soc = specs['soc']?.toString() ?? '';
    if (soc.isNotEmpty) {
      rows.add({'label': 'Processor', 'value': soc});
    }
    final gpu = specs['gpu']?.toString() ?? '';
    if (gpu.isNotEmpty) {
      rows.add({'label': 'Graphics (GPU)', 'value': gpu});
    }

    // 3. Memory & Storage
    final ram = specs['ram']?.toString().isNotEmpty == true
        ? specs['ram'].toString()
        : _product.ram;
    if (ram.isNotEmpty) {
      rows.add({'label': 'Memory (RAM)', 'value': ram.endsWith('RAM') ? ram : '$ram RAM'});
    }
    final storage = _product.storage.isNotEmpty
        ? _product.storage
        : (specs['storage']?.toString() ?? '');
    if (storage.isNotEmpty) {
      rows.add({'label': 'Storage', 'value': storage});
    }

    // 4. Cameras
    final mainCam = specs['main_camera']?.toString() ?? '';
    if (mainCam.isNotEmpty) {
      rows.add({'label': 'Main Camera', 'value': mainCam});
    }
    final ultraCam = specs['ultra_camera']?.toString() ?? '';
    if (ultraCam.isNotEmpty && ultraCam.toLowerCase() != 'none') {
      rows.add({'label': 'Ultra-Wide', 'value': ultraCam});
    }
    final teleCam = specs['tele_camera']?.toString() ?? '';
    if (teleCam.isNotEmpty && teleCam.toLowerCase() != 'none') {
      rows.add({'label': 'Telephoto', 'value': teleCam});
    }
    final selfieCam = specs['selfie_camera']?.toString() ?? '';
    if (selfieCam.isNotEmpty) {
      rows.add({'label': 'Front Camera', 'value': selfieCam});
    }

    // 5. Battery
    final battery = specs['battery']?.toString() ?? '';
    if (battery.isNotEmpty) {
      rows.add({'label': 'Battery', 'value': battery});
    }

    // 6. Body, Dimensions & Durability
    final dimensions = specs['dimensions']?.toString() ?? '';
    if (dimensions.isNotEmpty) {
      rows.add({'label': 'Dimensions', 'value': dimensions});
    }
    final weight = specs['weight']?.toString() ?? '';
    if (weight.isNotEmpty) {
      rows.add({'label': 'Weight', 'value': weight});
    }
    final ipRating = specs['ip_rating']?.toString() ?? '';
    if (ipRating.isNotEmpty) {
      rows.add({'label': 'Durability (IP)', 'value': ipRating});
    }

    // 7. Operating System & Connectivity
    final os = specs['os']?.toString() ?? '';
    if (os.isNotEmpty) {
      rows.add({'label': 'Operating System', 'value': os});
    }
    final connectivity = specs['connectivity']?.toString() ?? '';
    if (connectivity.isNotEmpty) {
      rows.add({'label': 'Connectivity', 'value': connectivity});
    }

    // Fallbacks if list is empty
    if (rows.isEmpty) {
      rows.add({'label': 'Brand', 'value': _product.brand});
      rows.add({'label': 'Model', 'value': _product.model});
      if (_product.storage.isNotEmpty) rows.add({'label': 'Storage', 'value': _product.storage});
      if (_product.ram.isNotEmpty) rows.add({'label': 'Memory (RAM)', 'value': _product.ram});
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Specifications',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 16),
          for (int i = 0; i < rows.length; i++) ...[
            _buildSpecRow(rows[i]['label']!, rows[i]['value']!),
            if (i < rows.length - 1)
              const Divider(height: 22, color: Color(0xFFF1F5F9)),
          ],
        ],
      ),
    );
  }

  Widget _buildSpecRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.justify,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A),
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}
