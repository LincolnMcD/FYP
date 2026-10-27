import 'dart:async';
import 'package:flutter/material.dart';
import 'models/product_model.dart';
import 'services/shop_service.dart';
import 'product_detail_page.dart';
import 'select_rental_duration_page.dart';
import '../../account_management_module/welcome_page.dart';
import '../device_tradein_module/data/phone_brands_data.dart';

enum PriceSortOption {
  none,
  lowToHigh,
  highToLow,
}

class ShopPage extends StatefulWidget {
  final bool isLoggedIn;
  final String? email;
  final String? name;
  final VoidCallback? onCartUpdated;
  final VoidCallback? onOpenCart;
  final String targetStatus;
  final bool isRentalMode;

  const ShopPage({
    super.key,
    required this.isLoggedIn,
    this.email,
    this.name,
    this.onCartUpdated,
    this.onOpenCart,
    this.targetStatus = 'listed',
    this.isRentalMode = false,
  });

  @override
  State<ShopPage> createState() => ShopPageState();
}

class ShopPageState extends State<ShopPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;
  String _selectedBrand = 'All Brands';
  PriceSortOption _priceSort = PriceSortOption.none;
  List<ProductModel> _products = [];
  bool _isLoading = true;
  String? _productLoadError;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  String? _nextCursor;
  int _productRequestGeneration = 0;
  final Set<String> _addingProductIds = {};
  String? _toastMessage;
  bool _isToastError = false;

  // Complete list of brands from trade-in options + 'All Brands'
  late final List<String> _allBrands;

  @override
  void initState() {
    super.initState();
    // Build brand list from trade-in module PhoneBrandsData
    _allBrands = ['All Brands', ...PhoneBrandsData.wellKnownPhoneBrands];
    _scrollController.addListener(_handleScroll);

    loadProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchDebounce?.cancel();
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
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

  String get _sortKey => switch (_priceSort) {
    PriceSortOption.lowToHigh => 'low',
    PriceSortOption.highToLow => 'high',
    PriceSortOption.none => 'none',
  };

  void _handleScroll() {
    if (_scrollController.hasClients && _scrollController.position.extentAfter < 500) {
      _loadMoreProducts();
    }
  }

  Future<void> loadProducts({bool forceRefresh = false}) async {
    if (!mounted) return;
    final generation = ++_productRequestGeneration;
    setState(() {
      _isLoading = true;
      _productLoadError = null;
      _isLoadingMore = false;
      _hasMore = false;
      _nextCursor = null;
      _products = [];
    });
    final result = await ShopService.fetchProductPage(
      email: widget.email,
      search: _searchController.text.trim(),
      brand: _selectedBrand == 'All Brands' ? null : _selectedBrand,
      status: widget.targetStatus,
      sort: _sortKey,
      forceRefresh: forceRefresh,
    );
    if (mounted && generation == _productRequestGeneration) {
      setState(() {
        final rawList = List<ProductModel>.from(result['products'] as List<ProductModel>);
        final expectedStatus = widget.targetStatus.toLowerCase();
        final list = rawList.where((p) {
          final s = p.listingStatus.toLowerCase();
          return expectedStatus == 'rent' ? (s == 'rent' || s == 'renting') : s == expectedStatus;
        }).toList();
        if (widget.isRentalMode && _priceSort != PriceSortOption.none) {
          list.sort((a, b) {
            final priceA = a.rentalPrice > 0 ? a.rentalPrice : (a.sellingPrice * 0.08);
            final priceB = b.rentalPrice > 0 ? b.rentalPrice : (b.sellingPrice * 0.08);
            return _priceSort == PriceSortOption.lowToHigh
                ? priceA.compareTo(priceB)
                : priceB.compareTo(priceA);
          });
        }
        _products = list;
        _nextCursor = result['nextCursor'] as String?;
        _hasMore = result['hasMore'] == true;
        _productLoadError = result['error']?.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreProducts() async {
    if (!mounted || _isLoading || _isLoadingMore || !_hasMore || _nextCursor == null) return;
    final generation = _productRequestGeneration;
    setState(() => _isLoadingMore = true);
    final result = await ShopService.fetchProductPage(
      email: widget.email,
      search: _searchController.text.trim(),
      brand: _selectedBrand == 'All Brands' ? null : _selectedBrand,
      status: widget.targetStatus,
      sort: _sortKey,
      cursor: _nextCursor,
    );
    if (!mounted || generation != _productRequestGeneration) return;
    setState(() {
      final existing = _products.map((product) => product.productID).toSet();
      final expectedStatus = widget.targetStatus.toLowerCase();
      final newItems = (result['products'] as List<ProductModel>)
          .where((item) {
            final s = item.listingStatus.toLowerCase();
            final matches = expectedStatus == 'rent' ? (s == 'rent' || s == 'renting') : s == expectedStatus;
            return matches && !existing.contains(item.productID);
          });
      _products.addAll(newItems);
      if (widget.isRentalMode && _priceSort != PriceSortOption.none) {
        _products.sort((a, b) {
          final priceA = a.rentalPrice > 0 ? a.rentalPrice : (a.sellingPrice * 0.08);
          final priceB = b.rentalPrice > 0 ? b.rentalPrice : (b.sellingPrice * 0.08);
          return _priceSort == PriceSortOption.lowToHigh
              ? priceA.compareTo(priceB)
              : priceB.compareTo(priceA);
        });
      }
      _nextCursor = result['nextCursor'] as String?;
      _hasMore = result['hasMore'] == true;
      _isLoadingMore = false;
    });
  }

  void _scheduleSearch() {
    _searchDebounce?.cancel();
    if (mounted) setState(() {});
    _searchDebounce = Timer(const Duration(milliseconds: 350), () => loadProducts());
  }

  Future<void> _handleAddToCart(ProductModel product) async {
    if (!widget.isLoggedIn || widget.email == null || widget.email!.isEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const WelcomePage()),
      );
      return;
    }

    final pid = product.productID;
    if (_addingProductIds.contains(pid)) return;

    setState(() {
      _addingProductIds.add(pid);
      // Immediately hide item from this user's product page for instant feedback
      _products.removeWhere((p) => p.productID == pid);
    });

    final success = await ShopService.addToCart(
      email: widget.email!,
      productID: pid,
    );

    if (mounted) {
      setState(() {
        _addingProductIds.remove(pid);
      });

      if (success) {
        _showTopToast('${product.displayTitle} added to cart');
        widget.onCartUpdated?.call();
      } else {
        // Rollback if add failed
        loadProducts();
        _showTopToast('Failed to add item to cart', isError: true);
      }
    }
  }

  void _showBrandPickerModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.3,
              maxChildSize: 0.85,
              expand: false,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Filter by Brand',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              setState(() => _selectedBrand = 'All Brands');
                              loadProducts();
                            },
                            child: const Text('Reset', style: TextStyle(color: Color(0xFF0C5AD2))),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: _allBrands.length,
                        itemBuilder: (context, index) {
                          final brand = _allBrands[index];
                          final isSelected = _selectedBrand == brand;
                          return ListTile(
                            dense: true,
                            title: Text(
                              brand,
                              style: TextStyle(
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected ? const Color(0xFF0C5AD2) : const Color(0xFF1E293B),
                              ),
                            ),
                            trailing: isSelected
                                ? const Icon(Icons.check, color: Color(0xFF0C5AD2), size: 18)
                                : null,
                            onTap: () {
                              Navigator.pop(context);
                              setState(() => _selectedBrand = brand);
                              loadProducts();
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _showSortPickerModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                    'Sort by Price',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.clear, color: Colors.grey),
                  title: const Text('Default (Newest first)'),
                  trailing: _priceSort == PriceSortOption.none
                      ? const Icon(Icons.check, color: Color(0xFF0C5AD2))
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    setState(() => _priceSort = PriceSortOption.none);
                    loadProducts();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.arrow_upward, color: Color(0xFF0C5AD2)),
                  title: const Text('Price: Low to High'),
                  trailing: _priceSort == PriceSortOption.lowToHigh
                      ? const Icon(Icons.check, color: Color(0xFF0C5AD2))
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    setState(() => _priceSort = PriceSortOption.lowToHigh);
                    loadProducts();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.arrow_downward, color: Color(0xFF0C5AD2)),
                  title: const Text('Price: High to Low'),
                  trailing: _priceSort == PriceSortOption.highToLow
                      ? const Icon(Icons.check, color: Color(0xFF0C5AD2))
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    setState(() => _priceSort = PriceSortOption.highToLow);
                    loadProducts();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (_searchFocusNode.hasFocus) {
          _searchFocusNode.unfocus();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FB),
        body: Stack(
          children: [
            RefreshIndicator(
        onRefresh: () => loadProducts(forceRefresh: true),
              color: const Color(0xFF0C5AD2),
                child: SingleChildScrollView(
                  controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSearchBar(),
                    const SizedBox(height: 12),
                    _buildControlsRow(),
                    const SizedBox(height: 16),
                    if (_isLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 60.0),
                        child: Center(
                          child: CircularProgressIndicator(color: Color(0xFF0C5AD2)),
                        ),
                      )
                    else if (_products.isEmpty)
                      _buildEmptyState(_productLoadError)
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _products.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 16),
                        itemBuilder: (context, index) {
                          final product = _products[index];
                          return _buildProductCard(product);
                        },
                      ),
                    if (_isLoadingMore)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(child: CircularProgressIndicator(color: Color(0xFF0C5AD2))),
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
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

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade300),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Icon(Icons.search, color: Colors.grey.shade500, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onTapOutside: (_) {
                if (_searchFocusNode.hasFocus) {
                  _searchFocusNode.unfocus();
                }
              },
              decoration: InputDecoration(
                hintText: widget.isRentalMode
                    ? 'Search rental phones (e.g. iPhone, Samsung)...'
                    : 'Search devices, brands, or models...',
                hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
              onChanged: (_) => _scheduleSearch(),
              onSubmitted: (_) {
                _searchFocusNode.unfocus();
                loadProducts();
              },
            ),
          ),
          if (_searchController.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchController.clear();
                loadProducts();
              },
              child: Icon(Icons.close, color: Colors.grey.shade400, size: 18),
            ),
        ],
      ),
    );
  }

  Widget _buildControlsRow() {
    return Row(
      children: [
        // Expandable Brand Filter Dropdown Button
        Expanded(
          child: InkWell(
            onTap: _showBrandPickerModal,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _selectedBrand != 'All Brands' ? const Color(0xFF0C5AD2) : Colors.grey.shade300,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.phone_android,
                    size: 16,
                    color: _selectedBrand != 'All Brands' ? const Color(0xFF0C5AD2) : Colors.grey.shade600,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _selectedBrand,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: _selectedBrand != 'All Brands' ? FontWeight.bold : FontWeight.w500,
                        color: _selectedBrand != 'All Brands' ? const Color(0xFF0C5AD2) : const Color(0xFF334155),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Sort by Price Button
        InkWell(
          onTap: _showSortPickerModal,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _priceSort != PriceSortOption.none ? const Color(0xFF0C5AD2) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _priceSort != PriceSortOption.none ? const Color(0xFF0C5AD2) : Colors.grey.shade300,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.swap_vert,
                  size: 16,
                  color: _priceSort != PriceSortOption.none ? Colors.white : Colors.grey.shade600,
                ),
                const SizedBox(width: 4),
                Text(
                  _priceSort == PriceSortOption.lowToHigh
                      ? 'Price: Low'
                      : _priceSort == PriceSortOption.highToLow
                          ? 'Price: High'
                          : 'Sort',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _priceSort != PriceSortOption.none ? Colors.white : const Color(0xFF334155),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProductCard(ProductModel product) {
    Color badgeBgColor = const Color(0xFFDEF7EC);
    Color badgeTextColor = const Color(0xFF03543F);
    IconData badgeIcon = Icons.verified_outlined;

    final cond = product.condition.toLowerCase();
    if (cond.contains('new')) {
      badgeBgColor = const Color(0xFFE8F5E9);
      badgeTextColor = const Color(0xFF2E7D32);
      badgeIcon = Icons.verified_outlined;
    } else if (cond.contains('good')) {
      badgeBgColor = const Color(0xFFE0F2FE);
      badgeTextColor = const Color(0xFF0284C7);
      badgeIcon = Icons.thumb_up_alt_outlined;
    } else if (cond.contains('fair')) {
      badgeBgColor = const Color(0xFFF3F4F6);
      badgeTextColor = const Color(0xFF4B5563);
      badgeIcon = Icons.tune;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ProductDetailPage(
                  product: product,
                  isLoggedIn: widget.isLoggedIn,
                  email: widget.email,
                  name: widget.name,
                  isRentalMode: widget.isRentalMode,
                  onCartUpdated: () {
                    widget.onCartUpdated?.call();
                    loadProducts(forceRefresh: true);
                  },
                ),
              ),
            );
            loadProducts(forceRefresh: true);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image container with condition badge
              Stack(
                children: [
                  Container(
                    height: 180,
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF1F4F9),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                      child: (product.imageUrl.isNotEmpty && !product.imageUrl.contains('sample_'))
                          ? Image.network(
                              product.imageUrl,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) => Center(
                                child: Icon(Icons.smartphone, size: 64, color: Colors.grey.shade300),
                              ),
                            )
                          : Center(
                              child: Icon(Icons.smartphone, size: 64, color: Colors.grey.shade300),
                            ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: badgeBgColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(badgeIcon, size: 12, color: badgeTextColor),
                          const SizedBox(width: 4),
                          Text(
                            product.condition,
                            style: TextStyle(
                              color: badgeTextColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              // Info padding
              Padding(
                padding: const EdgeInsets.all(14.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.displayTitle,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      product.displaySpecs,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.isRentalMode
                                  ? 'RM ${(product.rentalPrice > 0 ? product.rentalPrice : (product.sellingPrice * 0.08)).toStringAsFixed(2)} / mo'
                                  : 'RM ${product.sellingPrice.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0C5AD2),
                              ),
                            ),
                            if (widget.isRentalMode && product.sellingPrice > 0)
                              Text(
                                'Deposit: RM ${(product.sellingPrice * 0.2).toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                              ),
                          ],
                        ),
                        InkWell(
                          onTap: () {
                            if (widget.isRentalMode) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => SelectRentalDurationPage(
                                    product: product,
                                    isLoggedIn: widget.isLoggedIn,
                                    email: widget.email,
                                    name: widget.name,
                                    onRentalCompleted: () {
                                      widget.onCartUpdated?.call();
                                      loadProducts(forceRefresh: true);
                                    },
                                  ),
                                ),
                              );
                            } else {
                              _handleAddToCart(product);
                            }
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: const BoxDecoration(
                              color: Color(0xFF0C5AD2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              widget.isRentalMode ? Icons.calendar_month_outlined : Icons.shopping_cart_outlined,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState([String? error]) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(error == null ? Icons.inventory_2_outlined : Icons.cloud_off_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            error ?? (widget.isRentalMode ? 'No rental smartphones available at the moment.' : 'No products found.'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF334155),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => loadProducts(forceRefresh: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ],
      ),
    );
  }
}
