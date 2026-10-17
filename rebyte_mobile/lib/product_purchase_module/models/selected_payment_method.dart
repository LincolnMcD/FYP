class SelectedPaymentMethod {
  final String id;
  final String type; // 'card', 'ewallet', 'fpx'
  final String title; // '**** **** **** 4242' or 'TNG eWallet' or 'Maybank2u'
  final String subtitle; // 'Exp: 12/25' or 'eWallet' or 'FPX Online Banking'
  final String iconType; // 'card', 'tng', 'fpx', 'grabpay', etc.
  final Map<String, dynamic>? rawData;

  const SelectedPaymentMethod({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.iconType,
    this.rawData,
  });

}

