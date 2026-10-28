class ProductModel {
  final String id;
  final String productID;
  final String listingTitle;
  final String description;
  final double sellingPrice;
  final String imageUrl;
  final List<String> images;
  final String brand;
  final String model;
  final String storage;
  final String ram;
  final String color;
  final String condition;
  final String listingStatus;
  final String deviceID;
  final String modelCode;
  final double rentalPrice;
  final double collectedPrice;

  ProductModel({
    required this.id,
    required this.productID,
    this.listingTitle = '',
    required this.description,
    required this.sellingPrice,
    required this.imageUrl,
    this.images = const [],
    required this.brand,
    required this.model,
    required this.storage,
    required this.ram,
    required this.color,
    required this.condition,
    required this.listingStatus,
    this.deviceID = '',
    this.modelCode = '',
    this.rentalPrice = 0.0,
    this.collectedPrice = 0.0,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    final sp = (json['sellingPrice'] is num) ? (json['sellingPrice'] as num).toDouble() : 0.0;
    final cp = (json['collectedPrice'] is num) ? (json['collectedPrice'] as num).toDouble() : 0.0;
    final ep = (json['estPrice'] is num) ? (json['estPrice'] as num).toDouble() : 0.0;
    final dynamic rawRent = json['rentalPrice'] ?? json['monthlyRentalPrice'] ?? json['rentPricePerMonth'];
    final rp = (rawRent is num && rawRent > 0)
        ? rawRent.toDouble()
        : (sp > 0 ? (sp * 0.08) : (cp > 0 ? (cp * 0.08) : (ep > 0 ? (ep * 0.08) : 50.0)));
    return ProductModel(
      id: json['id']?.toString() ?? '',
      productID: json['productID']?.toString() ?? json['id']?.toString() ?? '',
      listingTitle: json['listingTitle']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      sellingPrice: sp,
      rentalPrice: rp,
      collectedPrice: cp,
      imageUrl: json['imageUrl']?.toString() ?? 'https://res.cloudinary.com/spyhcckw/image/upload/v1792084768/product/sample_iphone14.jpg',
      images: (json['images'] is List)
          ? (json['images'] as List).map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
          : (json['imageUrl'] != null && json['imageUrl'].toString().isNotEmpty
              ? [json['imageUrl'].toString()]
              : []),
      brand: json['brand']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      storage: json['storage']?.toString() ?? '',
      ram: json['ram']?.toString() ?? '',
      color: json['color']?.toString() ?? '',
      condition: json['condition']?.toString() ?? 'Good',
      listingStatus: json['listingStatus']?.toString() ?? 'listed',
      deviceID: json['deviceID']?.toString() ?? '',
      modelCode: json['modelCode']?.toString() ?? '',
    );
  }

  /// Formatted title e.g. "iPhone 15 Pro"
  String get displayTitle {
    if (listingTitle.trim().isNotEmpty) {
      return listingTitle.trim();
    }
    final List<String> parts = [];
    if (model.isNotEmpty) {
      if (brand.isNotEmpty && !model.toLowerCase().startsWith(brand.toLowerCase())) {
        parts.add('$brand $model');
      } else {
        parts.add(model);
      }
    }
    if (storage.isNotEmpty) parts.add(storage);
    if (color.isNotEmpty && color.toLowerCase() != 'standard') parts.add(color);
    if (parts.isNotEmpty) return parts.join(' - ');

    if (description.isNotEmpty) {
      final dashIndex = description.indexOf(' - ');
      final titlePart = (dashIndex != -1 ? description.substring(0, dashIndex) : description).trim();
      final cleanTitle = titlePart.replaceAll(RegExp(r'\s*\([^)]*\)$'), '').trim();
      if (cleanTitle.isNotEmpty) {
        return cleanTitle;
      }
    }
    return 'Item';
  }

  /// Formatted subtitle specs e.g. "256GB • 8GB RAM • Natural Titanium"
  String get displaySpecs {
    final List<String> parts = [];
    if (storage.isNotEmpty) parts.add(storage);
    if (ram.isNotEmpty) parts.add('${ram.replaceAll(RegExp(r'ram', caseSensitive: false), '').trim()} RAM');
    if (color.isNotEmpty) parts.add(color);
    if (parts.isEmpty && description.isNotEmpty) return description;
    return parts.join(' • ');
  }
}
