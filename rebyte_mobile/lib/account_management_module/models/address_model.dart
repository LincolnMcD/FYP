class AddressModel {
  final String id;
  final String addressID;
  final String addressLine;
  final String postcode;
  final String city;
  final String state;
  final String recipientName;
  final String phoneNumber;
  final String addressType; // 'Home', 'Office', or custom string (limit <= 20 char)
  final bool isDefault;
  final String customerID;

  AddressModel({
    required this.id,
    required this.addressID,
    required this.addressLine,
    required this.postcode,
    required this.city,
    required this.state,
    required this.recipientName,
    required this.phoneNumber,
    this.addressType = 'Home',
    this.isDefault = false,
    this.customerID = '',
  });

  // Backward compatibility alias for label
  String get label => addressType;

  // Formatted full address line
  String get fullAddress {
    final parts = [addressLine, postcode, city, state].where((p) => p.trim().isNotEmpty).toList();
    return parts.join(', ');
  }

  AddressModel copyWith({
    String? id,
    String? addressID,
    String? addressLine,
    String? postcode,
    String? city,
    String? state,
    String? recipientName,
    String? phoneNumber,
    String? addressType,
    bool? isDefault,
    String? customerID,
  }) {
    return AddressModel(
      id: id ?? this.id,
      addressID: addressID ?? this.addressID,
      addressLine: addressLine ?? this.addressLine,
      postcode: postcode ?? this.postcode,
      city: city ?? this.city,
      state: state ?? this.state,
      recipientName: recipientName ?? this.recipientName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      addressType: addressType ?? this.addressType,
      isDefault: isDefault ?? this.isDefault,
      customerID: customerID ?? this.customerID,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'addressID': addressID,
      'addressLine': addressLine,
      'postcode': postcode,
      'city': city,
      'state': state,
      'recipentName': recipientName,
      'phoneNumber': phoneNumber,
      'addressType': addressType,
      'isDefault': isDefault,
      'customerID': customerID,
    };
  }

  factory AddressModel.fromJson(Map<String, dynamic> json) {
    return AddressModel(
      id: json['addressID']?.toString() ?? json['id']?.toString() ?? '',
      addressID: json['addressID']?.toString() ?? json['id']?.toString() ?? '',
      addressLine: json['addressLine']?.toString() ?? json['addressLIne']?.toString() ?? '',
      postcode: json['postcode']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      state: json['state']?.toString() ?? '',
      recipientName: json['recipentName']?.toString() ?? json['recipientName']?.toString() ?? '',
      phoneNumber: json['phoneNumber']?.toString() ?? '',
      addressType: json['addressType']?.toString() ?? json['label']?.toString() ?? 'Home',
      isDefault: json['isDefault'] == true,
      customerID: json['customerID']?.toString() ?? '',
    );
  }
}
