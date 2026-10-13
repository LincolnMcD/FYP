import 'package:flutter/material.dart';

class PhoneColorOption {
  final String name;
  final Color color;
  final bool isOther;

  const PhoneColorOption({
    required this.name,
    required this.color,
    this.isOther = false,
  });
}

class PhoneBrandsData {
  static const List<String> storageCapacities = [
    '64 GB',
    '128 GB',
    '256 GB',
    '512 GB',
    '1 TB',
    '2 TB',
  ];

  static const List<PhoneColorOption> popularColors = [
    PhoneColorOption(name: 'Black / Midnight / Space Gray', color: Color(0xFF1E2022)),
    PhoneColorOption(name: 'White / Silver / Starlight', color: Color(0xFFE5E7EB)),
    PhoneColorOption(name: 'Natural Titanium / Titanium Gray', color: Color(0xFF9CA3AF)),
    PhoneColorOption(name: 'Blue / Sierra Blue / Deep Navy', color: Color(0xFF2563EB)),
    PhoneColorOption(name: 'Purple / Deep Purple / Lavender', color: Color(0xFF7C3AED)),
    PhoneColorOption(name: 'Green / Alpine Green / Mint', color: Color(0xFF059669)),
    PhoneColorOption(name: 'Gold / Rose Gold / Bronze', color: Color(0xFFD97706)),
    PhoneColorOption(name: 'Red / (PRODUCT)RED', color: Color(0xFFDC2626)),
    PhoneColorOption(name: 'Yellow / Amber', color: Color(0xFFEAB308)),
    PhoneColorOption(name: 'Orange / Coral / Peach', color: Color(0xFFEA580C)),
    PhoneColorOption(name: 'Other Color', color: Color(0xFF6B7280), isOther: true),
  ];
  static const List<String> wellKnownPhoneBrands = [
    'Apple',
    'Samsung',
    'Xiaomi',
    'OPPO',
    'HONOR',
    'vivo',
    'realme',
    'Huawei',
    'Redmi',
    'POCO',
    'OnePlus',
    'Nothing',
    'ASUS',
    'Google Pixel',
    'Motorola',
    'Infinix',
    'TECNO',
    'ZTE',
    'nubia',
    'Sony',
  ];
}
