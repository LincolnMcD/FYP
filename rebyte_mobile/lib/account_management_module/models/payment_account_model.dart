class PaymentAccountModel {
  final String id;
  final String cardNumber; // masked e.g. "**** **** **** 4242"
  final String rawCardNumber; // unmasked digits e.g. "4000000000001000"
  final String expiryDate; // e.g. "12/25"
  final String cardHolderName;
  final String cardType; // "Visa", "Mastercard", etc.
  final String cvv;
  final bool isDefault;

  PaymentAccountModel({
    required this.id,
    required this.cardNumber,
    this.rawCardNumber = '',
    required this.expiryDate,
    this.cardHolderName = '',
    this.cardType = 'Visa',
    this.cvv = '',
    this.isDefault = false,
  });

  PaymentAccountModel copyWith({
    String? id,
    String? cardNumber,
    String? rawCardNumber,
    String? expiryDate,
    String? cardHolderName,
    String? cardType,
    String? cvv,
    bool? isDefault,
  }) {
    return PaymentAccountModel(
      id: id ?? this.id,
      cardNumber: cardNumber ?? this.cardNumber,
      rawCardNumber: rawCardNumber ?? this.rawCardNumber,
      expiryDate: expiryDate ?? this.expiryDate,
      cardHolderName: cardHolderName ?? this.cardHolderName,
      cardType: cardType ?? this.cardType,
      cvv: cvv ?? this.cvv,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cardNumber': cardNumber,
      'rawCardNumber': rawCardNumber,
      'expiryDate': expiryDate,
      'cardHolderName': cardHolderName,
      'cardType': cardType,
      'cvv': cvv,
      'isDefault': isDefault,
    };
  }

  static String formatMaskedCard(String raw) {
    final clean = raw.replaceAll(' ', '').trim();
    if (clean.length < 4) return raw;
    final last4 = clean.substring(clean.length - 4);
    return '**** **** **** $last4';
  }

  factory PaymentAccountModel.fromJson(Map<String, dynamic> json) {
    final rawNumber = (json['rawCardNumber'] ?? json['cardNumber'] ?? json['maskedCardNumber'] ?? '').toString();
    final cleanRaw = rawNumber.replaceAll(' ', '').trim();
    final isAlreadyMasked = cleanRaw.contains('*');
    final masked = isAlreadyMasked ? cleanRaw : (cleanRaw.isNotEmpty ? formatMaskedCard(cleanRaw) : '**** **** **** 4242');

    return PaymentAccountModel(
      id: json['id'] ?? '',
      cardNumber: masked,
      rawCardNumber: !isAlreadyMasked ? cleanRaw : (json['rawCardNumber']?.toString() ?? ''),
      expiryDate: json['expiryDate'] ?? json['expiredDate'] ?? '12/25',
      cardHolderName: json['cardHolderName'] ?? '',
      cardType: json['cardType'] ?? json['providerName'] ?? 'Visa',
      cvv: (json['cvv'] ?? json['CVV'] ?? '').toString(),
      isDefault: json['isDefault'] ?? false,
    );
  }
}
