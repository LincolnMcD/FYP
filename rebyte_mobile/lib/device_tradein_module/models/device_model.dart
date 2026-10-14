class DeviceModel {
  final String deviceID;
  final String deviceCategory;
  final String brand;
  final String model;
  final String? modelCode;
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
    this.modelCode,
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
      'modelCode': modelCode,
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
      modelCode: json['modelCode'] is List
          ? (json['modelCode'] as List).join(', ')
          : json['modelCode']?.toString(),
      storageCapacity: json['storageCapacity'] ?? '',
      colour: json['colour'] ?? json['color'] ?? '',
      imeiNum: json['imeiNum'] ?? json['imei'],
      status: json['status'] ?? 'pending',
      deviceAge: json['deviceAge'],
      userEmail: json['userEmail'],
      createdAt: json['createdAt'] != null
          ? (json['createdAt'] is Map && json['createdAt']['_seconds'] != null
              ? DateTime.fromMillisecondsSinceEpoch(json['createdAt']['_seconds'] * 1000)
              : DateTime.tryParse(json['createdAt'].toString()))
          : null,
    );
  }

  DeviceModel copyWith({
    String? deviceID,
    String? deviceCategory,
    String? brand,
    String? model,
    String? modelCode,
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
      modelCode: modelCode ?? this.modelCode,
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
