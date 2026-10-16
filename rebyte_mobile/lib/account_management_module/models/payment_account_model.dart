class PaymentAccountModel {
  final String id;
  final String cardNumber; // e.g. "**** **** **** 4242"
  final String expiryDate; // e.g. "12/25"
  final String cardHolderName;
  final String cardType; // "Visa", "Mastercard", etc.
  final bool isDefault;

  PaymentAccountModel({
    required this.id,
    required this.cardNumber,
    required this.expiryDate,
    this.cardHolderName = '',
    this.cardType = 'Visa',
    this.isDefault = false,
  });

  PaymentAccountModel copyWith({
    String? id,
    String? cardNumber,
    String? expiryDate,
    String? cardHolderName,
    String? cardType,
    bool? isDefault,
  }) {
    return PaymentAccountModel(
      id: id ?? this.id,
      cardNumber: cardNumber ?? this.cardNumber,
      expiryDate: expiryDate ?? this.expiryDate,
      cardHolderName: cardHolderName ?? this.cardHolderName,
      cardType: cardType ?? this.cardType,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cardNumber': cardNumber,
      'expiryDate': expiryDate,
      'cardHolderName': cardHolderName,
      'cardType': cardType,
      'isDefault': isDefault,
    };
  }

  factory PaymentAccountModel.fromJson(Map<String, dynamic> json) {
    return PaymentAccountModel(
      id: json['id'] ?? '',
      cardNumber: json['cardNumber'] ?? '**** **** **** 4242',
      expiryDate: json['expiryDate'] ?? '12/25',
      cardHolderName: json['cardHolderName'] ?? '',
      cardType: json['cardType'] ?? 'Visa',
      isDefault: json['isDefault'] ?? false,
    );
  }
}
