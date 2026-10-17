class ProductModel {
  final String id;
  final String productID;
  final String description;
  final double sellingPrice;
  final String imageUrl;
  final String brand;
  final String model;
  final String storage;
  final String ram;
  final String color;
  final String condition;
  final String listingStatus;

  ProductModel({
    required this.id,
    required this.productID,
    required this.description,
    required this.sellingPrice,
    required this.imageUrl,
    required this.brand,
    required this.model,
    required this.storage,
    required this.ram,
    required this.color,
    required this.condition,
    required this.listingStatus,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      id: json['id']?.toString() ?? '',
      productID: json['productID']?.toString() ?? json['id']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      sellingPrice: (json['sellingPrice'] is num) ? (json['sellingPrice'] as num).toDouble() : 0.0,
      imageUrl: json['imageUrl']?.toString() ?? 'https://res.cloudinary.com/spyhcckw/image/upload/v1792084768/product/sample_iphone14.jpg',
      brand: json['brand']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      storage: json['storage']?.toString() ?? '',
      ram: json['ram']?.toString() ?? '',
      color: json['color']?.toString() ?? '',
      condition: json['condition']?.toString() ?? 'Good',
      listingStatus: json['listingStatus']?.toString() ?? 'listed',
    );
  }

  /// Formatted title e.g. "iPhone 15 Pro"
  String get displayTitle {
    if (model.isNotEmpty) {
      if (brand.isNotEmpty && !model.toLowerCase().startsWith(brand.toLowerCase())) {
        return '$brand $model';
      }
      return model;
    }
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
