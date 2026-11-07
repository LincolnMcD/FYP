import 'dart:io';
import 'package:flutter/material.dart';
import 'models/product_model.dart';
import 'models/cart_item_model.dart';
import 'services/shop_service.dart';
import 'checkout_page.dart';
import 'cart_page.dart';
import 'select_rental_duration_page.dart';
import 'payment_required_page.dart';
import '../../account_management_module/welcome_page.dart';
import '../../account_management_module/services/xendit_service.dart';
import '../../device_tradein_module/services/trade_in_service.dart';
import '../rental_managment_module/services/rental_service.dart';

class ProductDetailPage extends StatefulWidget {
  final ProductModel product;
  final bool isLoggedIn;
  final String? email;
  final String? name;
  final VoidCallback? onCartUpdated;
  final bool isRentalMode;

  const ProductDetailPage({
    super.key,
    required this.product,
    required this.isLoggedIn,
    this.email,
    this.name,
    this.onCartUpdated,
    this.isRentalMode = false,
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
  Map<String, dynamic>? _evaluationData;
  Map<String, dynamic>? _diagnosticData;
  Map<String, dynamic>? _deviceRecordData;
  double _depositPercentage = 10;

  bool get _isRentalDevice {
    final st = _product.listingStatus.toLowerCase();
    return widget.isRentalMode || st == 'rent' || st == 'renting';
  }

  double get _rentalAmount {
    if (_product.rentalPrice > 0) return _product.rentalPrice;
    if (_product.sellingPrice > 0) return _product.sellingPrice * 0.08;
    return 50.0;
  }

  @override
  void initState() {
    super.initState();
    _product = widget.product;
    if (_isRentalDevice) _loadRentalDepositPolicy();
    _modelCode = widget.product.modelCode;
    _deviceID = widget.product.deviceID;
    _checkCartStatus();
    _fetchFullProductAndSpecs();
  }


  Future<void> _loadRentalDepositPolicy() async {
    final result = await RentalService.getRentalPolicies();
    if (!mounted || result['success'] != true) return;
    final raw = result['baseDepositPercentage'];
    final percentage = raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 10;
    setState(() => _depositPercentage = percentage.clamp(1, 100).toDouble());
  }

  Future<void> _fetchFullProductAndSpecs() async {
    // 1. Fetch live product with full images list
    try {
      final liveProduct = await ShopService.fetchProductById(_product.productID);
      if (mounted && liveProduct != null) {
        setState(() {
          _product = liveProduct;
          if (liveProduct.modelCode.isNotEmpty) _modelCode = liveProduct.modelCode;
          if (liveProduct.deviceID.isNotEmpty) _deviceID = liveProduct.deviceID;
        });
      }
    } catch (_) {}

    // 2. Fetch full specifications
    await _fetchSpecifications();

    // 3. Fetch device inspection evaluation & diagnostic data
    await _loadDeviceEvaluationAndDiagnostic();
  }

  Future<void> _loadDeviceEvaluationAndDiagnostic() async {
    final devId = _deviceID.isNotEmpty ? _deviceID : _product.deviceID;
    final trId = _product.tradeInRequestID;

    if (devId.isEmpty && trId.isEmpty) return;

    try {
      // 1. Fetch device record by deviceID to resolve storage, color, and IMEI
      if (devId.isNotEmpty) {
        final devRec = await TradeInService.getDeviceById(devId);
        if (mounted && devRec != null) {
          setState(() {
            _deviceRecordData = devRec;
          });
        }
      }

      // 2. Fetch diagnostic data by deviceID
      if (devId.isNotEmpty) {
        final diag = await TradeInService.getDeviceDiagnostic(devId);
        if (mounted && diag != null) {
          setState(() {
            _diagnosticData = diag;
          });
        }
      }

      // 3. Fetch evaluation data by tradeInRequestID (prefer staffEvaluation)
      if (trId.isNotEmpty) {
        var eval = await TradeInService.getEvaluation(trId, source: 'staffEvaluation');
        eval ??= await TradeInService.getEvaluation(trId);
        if (mounted && eval != null) {
          setState(() {
            _evaluationData = eval;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading evaluation or diagnostic: $e');
    }
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
      listingTitle: _product.listingTitle.isNotEmpty ? _product.listingTitle : _product.displayTitle,
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

  Future<void> _handleStartRental() async {
    if (!widget.isLoggedIn || widget.email == null || widget.email!.isEmpty) {
      final loggedIn = await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const WelcomePage()),
      );
      if (loggedIn != true) return;
    }

    // Check if customer has linked payment accounts (cards)
    try {
      final savedCards = await XenditService.fetchSavedCards(widget.email!);
      if (savedCards.isEmpty) {
        if (!mounted) return;
        final linked = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => PaymentRequiredPage(
              email: widget.email!,
              onPaymentAccountLinked: () {},
            ),
          ),
        );
        if (linked != true) return;
      }
    } catch (_) {}

    if (!mounted) return;
    final rented = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => SelectRentalDurationPage(
          product: _product,
          isLoggedIn: widget.isLoggedIn,
          email: widget.email,
          name: widget.name,
          onRentalCompleted: widget.onCartUpdated,
        ),
      ),
    );

    if (rented == true && mounted) {
      widget.onCartUpdated?.call();
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Generate image list from product.images or fallback to product.imageUrl
    final images = _product.images.isNotEmpty
        ? _product.images
        : (_product.imageUrl.isNotEmpty ? [_product.imageUrl] : <String>[]);

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
          if (!_isRentalDevice) ...[
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
    final displayImages = images.where((u) => u.trim().isNotEmpty && !u.contains('sample_')).toList();
    if (displayImages.isEmpty && _product.imageUrl.isNotEmpty && !_product.imageUrl.contains('sample_')) {
      displayImages.add(_product.imageUrl);
    }
    final int safeIndex = (displayImages.isNotEmpty && _selectedImageIndex >= 0 && _selectedImageIndex < displayImages.length)
        ? _selectedImageIndex
        : 0;
    final bool hasMultiple = displayImages.length > 1;

    // Resolve Grade and Condition badge for image gallery
    String galleryGrade = 'A';
    final eval = _evaluationData;
    if (eval != null && eval['grade'] != null && eval['grade'].toString().isNotEmpty) {
      galleryGrade = eval['grade'].toString().toUpperCase();
    } else if (_product.condition.isNotEmpty) {
      final cLower = _product.condition.toLowerCase();
      if (cLower.contains('grade b') || cLower == 'good') {
        galleryGrade = 'B';
      } else if (cLower.contains('grade c') || cLower == 'fair') {
        galleryGrade = 'C';
      } else {
        galleryGrade = 'A';
      }
    }
    final String galleryConditionLabel = _resolveConditionLabel(eval?['condition']?.toString() ?? _product.condition, galleryGrade);
    final Color galleryConditionColor = _resolveConditionColor(galleryConditionLabel);
    final Color galleryConditionBg = _resolveConditionBg(galleryConditionLabel);

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
                  color: galleryConditionBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified, size: 14, color: galleryConditionColor),
                    const SizedBox(width: 5),
                    Text(
                      galleryConditionLabel,
                      style: TextStyle(
                        color: galleryConditionColor,
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

          // Main image (with left/right arrows only if more than 1 image)
          SizedBox(
            height: 190,
            child: Row(
              children: [
                if (hasMultiple)
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios, size: 18, color: Color(0xFF0F172A)),
                    onPressed: () {
                      setState(() {
                        _selectedImageIndex = (safeIndex - 1 + displayImages.length) % displayImages.length;
                      });
                    },
                  ),
                Expanded(
                  child: Center(
                    child: displayImages.isNotEmpty
                        ? Image.network(
                            displayImages[safeIndex],
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) => Icon(
                              Icons.smartphone,
                              size: 110,
                              color: Colors.grey.shade300,
                            ),
                          )
                        : Icon(
                            Icons.smartphone,
                            size: 110,
                            color: Colors.grey.shade300,
                          ),
                  ),
                ),
                if (hasMultiple)
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, size: 18, color: Color(0xFF0F172A)),
                    onPressed: () {
                      setState(() {
                        _selectedImageIndex = (safeIndex + 1) % displayImages.length;
                      });
                    },
                  ),
              ],
            ),
          ),

          // Thumbnail Row only if more than 1 image
          if (hasMultiple) ...[
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(displayImages.length, (index) {
                  final isSelected = index == safeIndex;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedImageIndex = index),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: 50,
                      height: 50,
                      padding: const EdgeInsets.all(3),
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
                          displayImages[index],
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => Icon(
                            Icons.phone_android,
                            size: 24,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _resolveConditionLabel(String? condition, String grade) {
    switch (grade.toUpperCase().trim()) {
      case 'A':
        return 'EXCELLENT CONDITION';
      case 'B':
        return 'GOOD CONDITION';
      case 'C':
        return 'FAIR CONDITION';
      default:
        if (condition != null && condition.trim().isNotEmpty) {
          final c = condition.trim().toUpperCase();
          if (c.contains('GRADE B') || c == 'GOOD') return 'GOOD CONDITION';
          if (c.contains('GRADE A') || c == 'EXCELLENT' || c == 'PRISTINE') return 'EXCELLENT CONDITION';
          if (c.contains('GRADE C') || c == 'FAIR') return 'FAIR CONDITION';
          return c.endsWith('CONDITION') ? c : '$c CONDITION';
        }
        return 'GRADE $grade CONDITION';
    }
  }

  Color _resolveConditionColor(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('excellent') || lower.contains('pristine') || lower.startsWith('grade a')) {
      return const Color(0xFF16A34A);
    }
    if (lower.contains('good') || lower.startsWith('grade b')) {
      return const Color(0xFF0284C7);
    }
    if (lower.contains('fair') || lower.startsWith('grade c')) {
      return const Color(0xFFD97706);
    }
    return const Color(0xFFDC2626);
  }

  Color _resolveConditionBg(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('excellent') || lower.contains('pristine') || lower.startsWith('grade a')) {
      return const Color(0xFFDCFCE7);
    }
    if (lower.contains('good') || lower.startsWith('grade b')) {
      return const Color(0xFFE0F2FE);
    }
    if (lower.contains('fair') || lower.startsWith('grade c')) {
      return const Color(0xFFFEF3C7);
    }
    return const Color(0xFFFEE2E2);
  }

  double _parsePartCoverage(dynamic part) {
    if (part is Map) {
      final cov = part['dmgCoverage'] ?? part['coverage'];
      if (cov is num) return cov.toDouble();
      if (cov != null) return double.tryParse(cov.toString()) ?? 0.0;
    }
    return 0.0;
  }

  Widget _buildOverallConditionCard() {
    final eval = _evaluationData;
    final diag = _diagnosticData;

    // Resolve Grade
    String grade = 'A';
    if (eval != null && eval['grade'] != null && eval['grade'].toString().isNotEmpty) {
      grade = eval['grade'].toString().toUpperCase();
    } else if (_product.condition.isNotEmpty) {
      final cLower = _product.condition.toLowerCase();
      if (cLower.contains('grade b') || cLower == 'good') {
        grade = 'B';
      } else if (cLower.contains('grade c') || cLower == 'fair') {
        grade = 'C';
      } else {
        grade = 'A';
      }
    }

    final String conditionLabel = _resolveConditionLabel(eval?['condition']?.toString() ?? _product.condition, grade);
    final Color conditionColor = _resolveConditionColor(conditionLabel);
    final Color conditionBg = _resolveConditionBg(conditionLabel);

    // 3-Part overall condition coverage
    final Map<String, dynamic>? parts = eval?['parts'] is Map<String, dynamic>
        ? eval!['parts'] as Map<String, dynamic>
        : null;

    final double screenCov = _parsePartCoverage(parts?['screen'] ?? eval?['screen']);
    final double backCov = _parsePartCoverage(parts?['back'] ?? eval?['back']);
    final double frameCov = _parsePartCoverage(parts?['frame'] ?? eval?['frame']);

    // Overall internalDeviceMark check
    dynamic internalMarkRaw;
    if (diag != null) {
      internalMarkRaw = diag['diagnosticScore'] ?? diag['internalDeviceMark'] ?? diag['hardwareScore'];
    }
    int? internalMark;
    if (internalMarkRaw is num) {
      internalMark = internalMarkRaw.toInt();
    } else if (internalMarkRaw != null) {
      internalMark = int.tryParse(internalMarkRaw.toString());
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
          // Header with shield icon and title
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
              const Spacer(),
              GestureDetector(
                onTap: _showInspectionReportBottomSheet,
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
            ],
          ),
          const SizedBox(height: 14),

          // Grade Section
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF0C5AD2).withValues(alpha: 0.3)),
                ),
                child: Text(
                  'Grade $grade',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0C5AD2),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: conditionBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  conditionLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: conditionColor,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 3-Part Overall Condition (Screen, Back Panel, Frame)
          const Text(
            '3-Part Cosmetic Assessment',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildPartConditionCard(
                  partKey: 'screen',
                  title: 'Screen',
                  coverage: screenCov,
                  icon: Icons.smartphone_rounded,
                  onTap: () => _showPartDefectsDialog(
                    partKey: 'screen',
                    partTitle: 'Screen',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildPartConditionCard(
                  partKey: 'back',
                  title: 'Back Panel',
                  coverage: backCov,
                  icon: Icons.flip_to_back_rounded,
                  onTap: () => _showPartDefectsDialog(
                    partKey: 'back',
                    partTitle: 'Back Panel',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildPartConditionCard(
                  partKey: 'frame',
                  title: 'Frame',
                  coverage: frameCov,
                  icon: Icons.crop_portrait_rounded,
                  onTap: () => _showPartDefectsDialog(
                    partKey: 'frame',
                    partTitle: 'Frame',
                  ),
                ),
              ),
            ],
          ),

          // Overall internalDeviceMark section ONLY if available
          if (internalMark != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: internalMark >= 80 ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      internalMark >= 80 ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
                      size: 20,
                      color: internalMark >= 80 ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Internal Hardware Mark',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          internalMark >= 80
                              ? 'Fully functional & passed all diagnostics'
                              : 'Minor component wear detected',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: internalMark >= 80 ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$internalMark/100',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPartConditionCard({
    required String partKey,
    required String title,
    required double coverage,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    final double dmgPct = (coverage * 100.0).clamp(0.0, 100.0);
    final bool hasDmg = dmgPct > 0.05;
    final Color col = hasDmg ? const Color(0xFFD97706) : const Color(0xFF16A34A);
    final Color bg = hasDmg ? const Color(0xFFFFFBEB) : const Color(0xFFF0FDF4);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: col.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Icon(icon, size: 18, color: col),
              const SizedBox(height: 4),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${dmgPct.toStringAsFixed(2)}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: col,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    hasDmg ? 'Dmg Cov.' : 'Intact',
                    style: TextStyle(
                      fontSize: 9,
                      color: col.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 7,
                    color: col.withValues(alpha: 0.6),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase().trim()) {
      case 'critical':
        return const Color(0xFFDC2626);
      case 'major':
        return const Color(0xFFEA580C);
      case 'minor':
        return const Color(0xFFD97706);
      case 'low':
        return const Color(0xFF0284C7);
      case 'none':
      default:
        return const Color(0xFF10B981);
    }
  }

  void _showSeverityRankingDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        final rankings = [
          {
            'level': 'Critical',
            'color': const Color(0xFFDC2626),
            'bgColor': const Color(0xFFFEF2F2),
            'icon': Icons.dangerous_rounded,
            'desc': 'Deep cracks, extensive shattered areas, or damage that impairs device function or touch response.',
          },
          {
            'level': 'Major',
            'color': const Color(0xFFEA580C),
            'bgColor': const Color(0xFFFFF7ED),
            'icon': Icons.warning_rounded,
            'desc': 'Noticeable cracks, deep scratches, or distinct discolouration patches clearly visible at arm’s length.',
          },
          {
            'level': 'Minor',
            'color': const Color(0xFFD97706),
            'bgColor': const Color(0xFFFFFBEB),
            'icon': Icons.error_outline_rounded,
            'desc': 'Light surface scratches, hairline marks, or slight cosmetic wear that does not affect functionality.',
          },
          {
            'level': 'Low',
            'color': const Color(0xFF0284C7),
            'bgColor': const Color(0xFFF0F9FF),
            'icon': Icons.info_outline_rounded,
            'desc': 'Micro-scratches or faint signs of handling visible only under direct angled light inspection.',
          },
          {
            'level': 'None',
            'color': const Color(0xFF10B981),
            'bgColor': const Color(0xFFF0FDF4),
            'icon': Icons.check_circle_outline_rounded,
            'desc': 'Pristine surface with zero detected cosmetic blemishes or structural anomalies.',
          },
        ];

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 14, 14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.help_outline_rounded,
                          color: Color(0xFF0C5AD2),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Severity Ranking Guide',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              'Defect severity classifications explained',
                              style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B), size: 22),
                        onPressed: () => Navigator.of(ctx).pop(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),

                // Ranking list
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: rankings.map((r) {
                      final Color col = r['color'] as Color;
                      final Color bg = r['bgColor'] as Color;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: col.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(r['icon'] as IconData, size: 20, color: col),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r['level'] as String,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: col,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    r['desc'] as String,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: Color(0xFF475569),
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),

                // Close Button
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0C5AD2),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPartDefectsDialog({
    required String partKey,
    required String partTitle,
  }) {
    final List<Map<String, dynamic>> defectConfig;
    if (partKey == 'screen') {
      defectConfig = [
        {'key': 'screenCrack', 'title': 'Crack', 'icon': Icons.bolt_rounded},
        {'key': 'screenDiscolouration', 'title': 'Discolouration', 'icon': Icons.palette_outlined},
        {'key': 'screenScratch', 'title': 'Scratch', 'icon': Icons.show_chart_rounded},
      ];
    } else if (partKey == 'back') {
      defectConfig = [
        {'key': 'backCrack', 'title': 'Crack', 'icon': Icons.bolt_rounded},
        {'key': 'backScratch', 'title': 'Scratch', 'icon': Icons.show_chart_rounded},
      ];
    } else {
      defectConfig = [
        {'key': 'frameScratch', 'title': 'Scratch', 'icon': Icons.show_chart_rounded},
        {'key': 'frameDent', 'title': 'Dent', 'icon': Icons.radio_button_checked_rounded},
      ];
    }

    final eval = _evaluationData;
    final Map<String, dynamic>? classes = eval?['classes'] is Map<String, dynamic>
        ? eval!['classes'] as Map<String, dynamic>
        : null;

    final List<Map<String, dynamic>> pages = defectConfig.map((cfg) {
      final key = cfg['key'] as String;
      final dynamic raw = classes?[key] ?? eval?[key];

      int count = 0;
      double? area;
      double? coverage;
      String severity = 'None';

      if (raw is Map) {
        if (raw['count'] is num) count = (raw['count'] as num).toInt();
        if (raw['area'] is num) area = (raw['area'] as num).toDouble();
        if (raw['coverage'] is num) coverage = (raw['coverage'] as num).toDouble();
        if (raw['severity'] != null && raw['severity'].toString().isNotEmpty) {
          severity = raw['severity'].toString();
        }
      }

      final bool isCrack = (cfg['title'] == 'Crack') || key.toLowerCase().contains('crack');

      return {
        'title': '$partTitle ${cfg['title']}',
        'defectType': cfg['title'] as String,
        'icon': cfg['icon'] as IconData,
        'isCrack': isCrack,
        'count': count,
        'area': area,
        'coverage': coverage,
        'severity': count > 0 ? severity : 'None',
      };
    }).toList();

    showDialog(
      context: context,
      builder: (ctx) {
        final PageController pageController = PageController();
        int activePage = 0;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 520, maxWidth: 420),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Dialog Header
                    Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 14, 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.analytics_outlined,
                          color: Color(0xFF0C5AD2),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$partTitle Defect Breakdown',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Swipe left / right to view each defect',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 5),
                            GestureDetector(
                              onTap: _showSeverityRankingDialog,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFBFDBFE)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.help_outline_rounded, color: Color(0xFF0C5AD2), size: 13),
                                    SizedBox(width: 4),
                                    Text(
                                      'Severity Ranking',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF0C5AD2),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B), size: 22),
                        onPressed: () => Navigator.of(ctx).pop(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),

                // Page Indicator Dots
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(pages.length, (i) {
                      final isCurrent = i == activePage;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        height: 6,
                        width: isCurrent ? 22 : 6,
                        decoration: BoxDecoration(
                          color: isCurrent ? const Color(0xFF0C5AD2) : const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    }),
                  ),
                ),

                // Swipeable PageView with defect details
                Flexible(
                  child: SizedBox(
                    height: 380,
                    child: PageView.builder(
                      controller: pageController,
                      itemCount: pages.length,
                      onPageChanged: (i) {
                        setDialogState(() {
                          activePage = i;
                        });
                      },
                      itemBuilder: (context, idx) {
                        final page = pages[idx];
                        final int count = page['count'] as int;
                        final double? area = page['area'] as double?;
                        final double? coverage = page['coverage'] as double?;
                        final String severity = page['severity'] as String;
                        final bool hasDefect = count > 0;

                        final Color statusColor = hasDefect
                            ? _getSeverityColor(severity)
                            : const Color(0xFF10B981);

                        return SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Defect Category Badge & Icon
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: (page['isCrack'] == true)
                                      ? CustomPaint(
                                          size: const Size(28, 28),
                                          painter: _CrackPainter(color: statusColor),
                                        )
                                      : Icon(
                                          page['icon'] as IconData,
                                          size: 28,
                                          color: statusColor,
                                        ),
                                ),
                              ),
                              const SizedBox(height: 10),

                              // Defect Title
                              Text(
                                page['title'] as String,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  hasDefect ? '$count Detected' : 'No Defects Detected',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: statusColor,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),

                              // 4 Detail Grid Blocks: Count, Area, Severity, Coverage
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildDefectMetricCard(
                                      label: 'Count',
                                      value: '$count',
                                      icon: Icons.tag_rounded,
                                      valueColor: statusColor,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildDefectMetricCard(
                                      label: 'Severity',
                                      value: severity,
                                      icon: Icons.shield_outlined,
                                      valueColor: statusColor,
                                      onHelpTap: _showSeverityRankingDialog,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildDefectMetricCard(
                                      label: 'Damage Area',
                                      value: area != null ? '${area.toStringAsFixed(2)} cm²' : '0.00 cm²',
                                      icon: Icons.aspect_ratio_rounded,
                                      valueColor: const Color(0xFF1E293B),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildDefectMetricCard(
                                      label: 'Coverage',
                                      value: coverage != null
                                          ? '${(coverage * 100).toStringAsFixed(2)}%'
                                          : '0.00%',
                                      icon: Icons.pie_chart_outline_rounded,
                                      valueColor: const Color(0xFF1E293B),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // Bottom helper status text
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      hasDefect ? Icons.info_outline_rounded : Icons.check_circle_outline_rounded,
                                      size: 16,
                                      color: statusColor,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        hasDefect
                                            ? 'Detected during AI surface assessment. Severity level evaluated as $severity.'
                                            : 'Zero $partTitle ${page['defectType']} defects found during evaluation.',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF64748B),
                                          height: 1.35,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),

                // Swipe Navigation controls
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: activePage > 0
                            ? () {
                                pageController.previousPage(
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeInOut,
                                );
                              }
                            : null,
                        icon: const Icon(Icons.chevron_left_rounded, size: 20),
                        label: const Text('Previous', style: TextStyle(fontSize: 12.5)),
                      ),
                      Text(
                        '${activePage + 1} of ${pages.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: activePage < pages.length - 1
                            ? () {
                                pageController.nextPage(
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeInOut,
                                );
                              }
                            : null,
                        icon: const Text('Next', style: TextStyle(fontSize: 12.5)),
                        label: const Icon(Icons.chevron_right_rounded, size: 20),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  },
);
  }

  Widget _buildDefectMetricCard({
    required String label,
    required String value,
    required IconData icon,
    required Color valueColor,
    VoidCallback? onHelpTap,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: const Color(0xFF64748B)),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
              if (onHelpTap != null)
                GestureDetector(
                  onTap: onHelpTap,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Color(0xFFEFF6FF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.help_outline_rounded,
                      size: 13,
                      color: Color(0xFF0C5AD2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  void _showInspectionReportBottomSheet() {
    final eval = _evaluationData;
    final diag = _diagnosticData;

    // Grade
    String grade = 'A';
    if (eval != null && eval['grade'] != null && eval['grade'].toString().isNotEmpty) {
      grade = eval['grade'].toString().toUpperCase();
    } else if (_product.condition.isNotEmpty) {
      final cLower = _product.condition.toLowerCase();
      if (cLower.contains('grade b') || cLower == 'good') {
        grade = 'B';
      } else if (cLower.contains('grade c') || cLower == 'fair') {
        grade = 'C';
      } else {
        grade = 'A';
      }
    }

    final String conditionLabel = _resolveConditionLabel(eval?['condition']?.toString() ?? _product.condition, grade);
    final Color conditionColor = _resolveConditionColor(conditionLabel);
    final Color conditionBg = _resolveConditionBg(conditionLabel);

    // Parts data for external condition summary
    final Map<String, dynamic>? parts = eval?['parts'] is Map<String, dynamic>
        ? eval!['parts'] as Map<String, dynamic>
        : null;

    final double screenCov = _parsePartCoverage(parts?['screen'] ?? eval?['screen']);
    final double backCov = _parsePartCoverage(parts?['back'] ?? eval?['back']);
    final double frameCov = _parsePartCoverage(parts?['frame'] ?? eval?['frame']);

    final String summaryDescription =
        'Device is fully functional and evaluated according to ReByte inspection standards. '
        'Screen damage coverage is ${(screenCov * 100).toStringAsFixed(2)}%, '
        'Back panel ${(backCov * 100).toStringAsFixed(2)}%, '
        'and Frame ${(frameCov * 100).toStringAsFixed(2)}%.';

    final bool hasDiagnostic = diag != null && diag.isNotEmpty;
    final List<Map<String, dynamic>> diagItems = [
      {
        'title': 'Touchscreen',
        'icon': Icons.touch_app_rounded,
        'mark': diag?['touchScreenMark'],
      },
      {
        'title': 'Display Panel',
        'icon': Icons.smartphone_rounded,
        'mark': diag?['displayMark'],
      },
      {
        'title': 'Camera System',
        'icon': Icons.camera_alt_outlined,
        'mark': diag?['cameraMark'],
      },
      {
        'title': 'Microphone',
        'icon': Icons.mic_none_rounded,
        'mark': diag?['microphoneMark'],
      },
      {
        'title': 'Speaker & Audio',
        'icon': Icons.volume_up_outlined,
        'mark': diag?['speakerMark'],
      },
      {
        'title': 'Sensors',
        'icon': Icons.sensors_rounded,
        'mark': diag?['sensorMark'],
      },
      {
        'title': 'Network & Connectivity',
        'icon': Icons.wifi_rounded,
        'mark': diag?['connectivityMark'],
      },
      {
        'title': 'GPS Location',
        'icon': Icons.location_on_outlined,
        'mark': diag?['gpsMark'],
      },
    ];

    final String? thumbUrl = _product.imageUrl.isNotEmpty
        ? _product.imageUrl
        : (_product.images.isNotEmpty ? _product.images[0] : null);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.90,
        minChildSize: 0.50,
        maxChildSize: 0.95,
        builder: (_, scrollController) => SafeArea(
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Stack(
              children: [
                Column(
                  children: [
                    // Pull Handle
                    const SizedBox(height: 12),
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Scrollable Body
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                        children: [
                          // Report Header
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Text(
                                    'ReByte',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF0C5AD2),
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  Text(
                                    'Inspection Report',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF475569),
                                    ),
                                  ),
                                ],
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 24),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      _formatDate(DateTime.now()),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF0C5AD2),
                                      ),
                                    ),
                                    const Text(
                                      'CONFIDENTIAL',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.8,
                                        color: Color(0xFF94A3B8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          const Divider(height: 1, color: Color(0xFFE2E8F0)),
                          const SizedBox(height: 18),

                          // SECTION 1: Device Information Box
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Device Information',
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Device Image Thumbnail
                                    Container(
                                      width: 85,
                                      height: 85,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: const Color(0xFFE2E8F0)),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: thumbUrl != null
                                          ? (thumbUrl.startsWith('http')
                                              ? Image.network(
                                                  thumbUrl,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) => const Icon(
                                                    Icons.smartphone_rounded,
                                                    size: 34,
                                                    color: Color(0xFF94A3B8),
                                                  ),
                                                )
                                              : Image.file(
                                                  File(thumbUrl),
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) => const Icon(
                                                    Icons.smartphone_rounded,
                                                    size: 34,
                                                    color: Color(0xFF94A3B8),
                                                  ),
                                                ))
                                          : const Icon(
                                              Icons.smartphone_rounded,
                                              size: 34,
                                              color: Color(0xFF94A3B8),
                                            ),
                                    ),
                                    const SizedBox(width: 14),

                                    // Specs 2x2 Grid
                                    Expanded(
                                      child: Column(
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: _buildReportMetaField(
                                                  'MODEL',
                                                  (() {
                                                    final b = _deviceRecordData?['brand']?.toString().isNotEmpty == true
                                                        ? _deviceRecordData!['brand'].toString()
                                                        : _product.brand;
                                                    final m = _deviceRecordData?['model']?.toString().isNotEmpty == true
                                                        ? _deviceRecordData!['model'].toString()
                                                        : _product.model;
                                                    if (m.isNotEmpty) {
                                                      return b.isNotEmpty && !m.toLowerCase().startsWith(b.toLowerCase())
                                                          ? '$b $m'
                                                          : m;
                                                    }
                                                    return _product.listingTitle.isNotEmpty
                                                        ? _product.listingTitle
                                                        : 'Smartphone';
                                                  })(),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: _buildReportMetaField(
                                                  'STORAGE',
                                                  (() {
                                                    final s = _deviceRecordData?['storageCapacity']?.toString() ??
                                                        _deviceRecordData?['storage']?.toString() ??
                                                        _product.storage;
                                                    return s.trim().isNotEmpty ? s.trim() : 'N/A';
                                                  })(),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: _buildReportMetaField(
                                                  'COLOR',
                                                  (() {
                                                    final c = _deviceRecordData?['colour']?.toString() ??
                                                        _deviceRecordData?['color']?.toString() ??
                                                        _product.color;
                                                    return c.trim().isNotEmpty ? c.trim() : 'Standard';
                                                  })(),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: _buildReportMetaField(
                                                  'IMEI / ID',
                                                  (() {
                                                    final imei = _deviceRecordData?['imeiNum']?.toString() ??
                                                        _deviceRecordData?['imei']?.toString() ??
                                                        _product.imei;
                                                    if (imei.trim().isNotEmpty) return imei.trim();
                                                    return _deviceID.isNotEmpty ? _deviceID : (_product.deviceID.isNotEmpty ? _product.deviceID : 'N/A');
                                                  })(),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // SECTION 2: Inspection Summary Card (Grading Only, no mark)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Circular Grade Badge
                                Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                    border: Border.all(color: const Color(0xFF0C5AD2), width: 3),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.04),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Grade $grade',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF0C5AD2),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),

                                // Summary text
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Inspection Summary',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: conditionBg,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          conditionLabel,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            color: conditionColor,
                                            letterSpacing: 0.4,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        summaryDescription,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF64748B),
                                          height: 1.35,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          // SECTION 3: External Condition Summary
                          Row(
                            children: [
                              const Text(
                                'External Condition Summary',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'Tap part for details',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: Colors.grey.shade500,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _buildPartConditionCard(
                                  partKey: 'screen',
                                  title: 'Screen',
                                  coverage: screenCov,
                                  icon: Icons.smartphone_rounded,
                                  onTap: () => _showPartDefectsDialog(
                                    partKey: 'screen',
                                    partTitle: 'Screen',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildPartConditionCard(
                                  partKey: 'back',
                                  title: 'Back Panel',
                                  coverage: backCov,
                                  icon: Icons.flip_to_back_rounded,
                                  onTap: () => _showPartDefectsDialog(
                                    partKey: 'back',
                                    partTitle: 'Back Panel',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildPartConditionCard(
                                  partKey: 'frame',
                                  title: 'Frame',
                                  coverage: frameCov,
                                  icon: Icons.crop_portrait_rounded,
                                  onTap: () => _showPartDefectsDialog(
                                    partKey: 'frame',
                                    partTitle: 'Frame',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),

                          // SECTION 4: Internal Condition Summary (Diagnostics)
                          Row(
                            children: [
                              const Text(
                                'Internal Condition Summary',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const Spacer(),
                              if (!hasDiagnostic)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'N/A',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          if (!hasDiagnostic)
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF64748B)),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'No internal diagnostic test record associated with this evaluation (N/A).',
                                      style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: diagItems.length,
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childAspectRatio: 2.1,
                              ),
                              itemBuilder: (context, i) {
                                final item = diagItems[i];
                                final dynamic m = item['mark'];
                                final int score = (m is num)
                                    ? m.toInt()
                                    : (m != null ? int.tryParse(m.toString()) ?? 100 : 100);
                                final int scoreOutOf10 = (score / 10).round().clamp(1, 10);
                                final bool isGood = score >= 80;

                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: isGood ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Icon(
                                          item['icon'] as IconData,
                                          size: 15,
                                          color: isGood ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              item['title'] as String,
                                              maxLines: 2,
                                              softWrap: true,
                                              style: const TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF0F172A),
                                                height: 1.15,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              isGood ? 'Pass' : 'Degraded',
                                              style: TextStyle(
                                                fontSize: 9.5,
                                                color: isGood ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isGood ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          '$scoreOutOf10/10',
                                          style: const TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          const SizedBox(height: 24),

                          // Close Button
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(ctx),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0C5AD2),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              child: const Text('Close Report', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Top Right Close Cross Icon
                Positioned(
                  top: 8,
                  right: 12,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => Navigator.pop(ctx),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF1F5F9),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReportMetaField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: Color(0xFF94A3B8),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
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
          if (_product.description.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              _product.description.trim(),
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF475569),
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 10),

          // Price
          if (_isRentalDevice) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  'RM${_rentalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0C5AD2),
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  '/ mth',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _product.sellingPrice > 0
                  ? 'Security Deposit: RM${(_product.sellingPrice * _depositPercentage / 100).toStringAsFixed(2)} (Refundable upon return)'
                  : 'Professional verified • Free delivery & pickup',
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF64748B),
              ),
            ),
          ] else ...[
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
          ],
          const SizedBox(height: 18),

          // Action Buttons: If rental device, only show "Make a Rental" button
          if (_isRentalDevice) ...[
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _handleStartRental,
                icon: const Icon(Icons.calendar_month_outlined, size: 20, color: Colors.white),
                label: const Text(
                  'Make a Rental',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0C5AD2),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ] else ...[
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
          ],
          const SizedBox(height: 14),

          // Compare device row (only for regular purchase products)
          if (!_isRentalDevice) ...[
            InkWell(
              onTap: () {
                _showTopToast('Device comparison feature coming soon.');
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
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
          ],
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

class _CrackPainter extends CustomPainter {
  final Color color;

  const _CrackPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.miter
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;

    // Main crack trunk - erratic zigzag line from top to bottom
    final mainPath = Path();
    mainPath.moveTo(w * 0.32, h * 0.08);
    mainPath.lineTo(w * 0.44, h * 0.18);
    mainPath.lineTo(w * 0.38, h * 0.28);
    mainPath.lineTo(w * 0.50, h * 0.38);
    mainPath.lineTo(w * 0.46, h * 0.48);
    mainPath.lineTo(w * 0.38, h * 0.58);
    mainPath.lineTo(w * 0.44, h * 0.68);
    mainPath.lineTo(w * 0.40, h * 0.74);
    mainPath.lineTo(w * 0.50, h * 0.82);
    mainPath.lineTo(w * 0.64, h * 0.94);
    canvas.drawPath(mainPath, paint);

    // Left branch 1 (top left fissure)
    final bLeft1 = Path();
    bLeft1.moveTo(w * 0.38, h * 0.16);
    bLeft1.lineTo(w * 0.32, h * 0.26);
    bLeft1.lineTo(w * 0.18, h * 0.32);
    canvas.drawPath(bLeft1, paint);

    // Left branch 2 (mid left horizontal fork)
    final bLeft2 = Path();
    bLeft2.moveTo(w * 0.46, h * 0.48);
    bLeft2.lineTo(w * 0.34, h * 0.46);
    bLeft2.lineTo(w * 0.24, h * 0.40);
    canvas.drawPath(bLeft2, paint);

    // Left branch 3 (bottom left fork)
    final bLeft3 = Path();
    bLeft3.moveTo(w * 0.40, h * 0.74);
    bLeft3.lineTo(w * 0.30, h * 0.78);
    bLeft3.lineTo(w * 0.34, h * 0.88);
    canvas.drawPath(bLeft3, paint);

    // Right branch 1 (top right sharp shoot)
    final bRight1 = Path();
    bRight1.moveTo(w * 0.48, h * 0.28);
    bRight1.lineTo(w * 0.64, h * 0.20);
    canvas.drawPath(bRight1, paint);

    // Right branch 2 (upper-mid right meandering crack)
    final bRight2 = Path();
    bRight2.moveTo(w * 0.42, h * 0.36);
    bRight2.lineTo(w * 0.56, h * 0.32);
    bRight2.lineTo(w * 0.74, h * 0.34);
    bRight2.lineTo(w * 0.76, h * 0.44);
    bRight2.lineTo(w * 0.66, h * 0.52);
    bRight2.lineTo(w * 0.64, h * 0.60);
    canvas.drawPath(bRight2, paint);

    // Right branch 3 (bottom right fork)
    final bRight3 = Path();
    bRight3.moveTo(w * 0.64, h * 0.60);
    bRight3.lineTo(w * 0.58, h * 0.68);
    canvas.drawPath(bRight3, paint);

    final bRight4 = Path();
    bRight4.moveTo(w * 0.64, h * 0.60);
    bRight4.lineTo(w * 0.70, h * 0.70);
    canvas.drawPath(bRight4, paint);
  }

  @override
  bool shouldRepaint(covariant _CrackPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
