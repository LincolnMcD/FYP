class DeviceModel {
  final String deviceID;
  final String deviceCategory;
  final String brand;
  final String model;
  final String storageCapacity;
  final String colour;
  final String? imeiNum;
  final String status;
  final String? deviceAge;
  final String? userEmail;
  final DateTime? createdAt;

  DeviceModel({
    required this.deviceID,
    this.deviceCategory = 'smartphone',
    required this.brand,
    required this.model,
    required this.storageCapacity,
    required this.colour,
    this.imeiNum,
    this.status = 'pending',
    this.deviceAge,
    this.userEmail,
    this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'deviceID': deviceID,
      'deviceCategory': deviceCategory,
      'brand': brand,
      'model': model,
      'storageCapacity': storageCapacity,
      'colour': colour,
      'imeiNum': imeiNum,
      'status': status,
      'deviceAge': deviceAge,
      'userEmail': userEmail,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  factory DeviceModel.fromJson(Map<String, dynamic> json) {
    return DeviceModel(
      deviceID: json['deviceID'] ?? '',
      deviceCategory: json['deviceCategory'] ?? 'smartphone',
      brand: json['brand'] ?? '',
      model: json['model'] ?? '',
      storageCapacity: json['storageCapacity'] ?? '',
      colour: json['colour'] ?? json['color'] ?? '',
      imeiNum: json['imeiNum'] ?? json['imei'],
      status: json['status'] ?? 'pending',
      deviceAge: json['deviceAge'],
      userEmail: json['userEmail'],
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt']) : null,
    );
  }

  DeviceModel copyWith({
    String? deviceID,
    String? deviceCategory,
    String? brand,
    String? model,
    String? storageCapacity,
    String? colour,
    String? imeiNum,
    String? status,
    String? deviceAge,
    String? userEmail,
    DateTime? createdAt,
  }) {
    return DeviceModel(
      deviceID: deviceID ?? this.deviceID,
      deviceCategory: deviceCategory ?? this.deviceCategory,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      storageCapacity: storageCapacity ?? this.storageCapacity,
      colour: colour ?? this.colour,
      imeiNum: imeiNum ?? this.imeiNum,
      status: status ?? this.status,
      deviceAge: deviceAge ?? this.deviceAge,
      userEmail: userEmail ?? this.userEmail,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
