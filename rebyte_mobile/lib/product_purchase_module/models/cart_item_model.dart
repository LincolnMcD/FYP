class CartItemModel {
  final String productID;
  final String description;
  final double sellingPrice;
  final String imageUrl;
  final bool isSold;
  final String listingStatus;
  final String brand;
  final String model;
  final String storage;
  final String ram;
  final String color;
  final String condition;
  bool isSelected;

  CartItemModel({
    required this.productID,
    required this.description,
    required this.sellingPrice,
    required this.imageUrl,
    this.isSold = false,
    this.listingStatus = 'listed',
    this.brand = '',
    this.model = '',
    this.storage = '',
    this.ram = '',
    this.color = '',
    this.condition = 'Good',
    this.isSelected = false,
  });

  factory CartItemModel.fromJson(Map<String, dynamic> json) {
    return CartItemModel(
      productID: json['productID']?.toString() ?? json['id']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      sellingPrice: (json['sellingPrice'] is num) ? (json['sellingPrice'] as num).toDouble() : 0.0,
      imageUrl: json['imageUrl']?.toString() ?? 'https://res.cloudinary.com/spyhcckw/image/upload/v1792084768/product/sample_iphone14.jpg',
      isSold: json['isSold'] == true || json['listingStatus'] == 'sold',
      listingStatus: json['listingStatus']?.toString() ?? 'listed',
      brand: json['brand']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      storage: json['storage']?.toString() ?? '',
      ram: json['ram']?.toString() ?? '',
      color: json['color']?.toString() ?? '',
      condition: json['condition']?.toString() ?? 'Good',
      isSelected: false,
    );
  }

  String get displayTitle {
    if (model.isNotEmpty) {
      if (brand.isNotEmpty && !model.toLowerCase().startsWith(brand.toLowerCase())) {
        return '$brand $model';
      }
      return model;
    }
    if (description.isNotEmpty) {
      // If description contains dash separator e.g. "Apple iPhone 15 Pro Max (256 GB) - Pristine..."
      final dashIndex = description.indexOf(' - ');
      final titlePart = (dashIndex != -1 ? description.substring(0, dashIndex) : description).trim();
      // Remove trailing storage like (256 GB) or (128GB) for a clean model title
      final cleanTitle = titlePart.replaceAll(RegExp(r'\s*\([^)]*\)$'), '').trim();
      if (cleanTitle.isNotEmpty) {
        return cleanTitle;
      }
    }
    return 'Item';
  }

  String get displaySpecs {
    final List<String> parts = [];
    if (storage.isNotEmpty) parts.add(storage);
    if (color.isNotEmpty) parts.add(color);
    if (parts.isEmpty && description.isNotEmpty) return description;
    return parts.join(' • ');
  }
}
