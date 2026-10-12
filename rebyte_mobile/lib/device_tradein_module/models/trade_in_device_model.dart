class TradeInDeviceModel {
  final String? tradeInId;
  final String? userId;
  final String? userEmail;
  final String brand;
  final String model;
  final String storageCapacity;
  final String colour;
  final String deviceAge;
  final String deviceCategory;
  final double? estimatedPrice;
  final String status;
  final DateTime? createdAt;

  TradeInDeviceModel({
    this.tradeInId,
    this.userId,
    this.userEmail,
    required this.brand,
    required this.model,
    required this.storageCapacity,
    required this.colour,
    required this.deviceAge,
    this.deviceCategory = 'Smartphone',
    this.estimatedPrice,
    this.status = 'Draft',
    this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'tradeInId': tradeInId,
      'userId': userId,
      'userEmail': userEmail,
      'brand': brand,
      'model': model,
      'storageCapacity': storageCapacity,
      'colour': colour,
      'color': colour,
      'deviceAge': deviceAge,
      'deviceCategory': deviceCategory,
      'estimatedPrice': estimatedPrice,
      'status': status,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  factory TradeInDeviceModel.fromJson(Map<String, dynamic> json) {
    return TradeInDeviceModel(
      tradeInId: json['tradeInId'],
      userId: json['userId'],
      userEmail: json['userEmail'],
      brand: json['brand'] ?? '',
      model: json['model'] ?? '',
      storageCapacity: json['storageCapacity'] ?? '',
      colour: json['colour'] ?? json['color'] ?? '',
      deviceAge: json['deviceAge'] ?? '',
      deviceCategory: json['deviceCategory'] ?? 'Smartphone',
      estimatedPrice: json['estimatedPrice'] != null ? (json['estimatedPrice'] as num).toDouble() : null,
      status: json['status'] ?? 'Draft',
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt']) : null,
    );
  }

  TradeInDeviceModel copyWith({
    String? tradeInId,
    String? userId,
    String? userEmail,
    String? brand,
    String? model,
    String? storageCapacity,
    String? colour,
    String? deviceAge,
    String? deviceCategory,
    double? estimatedPrice,
    String? status,
    DateTime? createdAt,
  }) {
    return TradeInDeviceModel(
      tradeInId: tradeInId ?? this.tradeInId,
      userId: userId ?? this.userId,
      userEmail: userEmail ?? this.userEmail,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      storageCapacity: storageCapacity ?? this.storageCapacity,
      colour: colour ?? this.colour,
      deviceAge: deviceAge ?? this.deviceAge,
      deviceCategory: deviceCategory ?? this.deviceCategory,
      estimatedPrice: estimatedPrice ?? this.estimatedPrice,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
