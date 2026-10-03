import 'user_model.dart';

class Customer extends User {
  final DateTime birthDate;
  final String gender;

  Customer({
    required super.userId,
    required super.fullName,
    required super.email,
    required super.phoneNumber,
    required super.loginMethod,
    required super.status,
    required super.createdAt,
    required super.updatedAt,
    required this.birthDate,
    required this.gender,
  });

  @override
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> baseJson = super.toJson();
    baseJson['birthDate'] = birthDate.toIso8601String();
    baseJson['gender'] = gender;
    
    // Explicitly note the role/type
    baseJson['role'] = 'Customer';
    return baseJson;
  }

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      userId: json['userId'] ?? '',
      fullName: json['fullName'] ?? '',
      email: json['email'] ?? '',
      phoneNumber: json['phoneNumber'] ?? '',
      loginMethod: json['loginMethod'] ?? 'Email',
      status: json['status'] ?? 'Active',
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : DateTime.now(),
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : DateTime.now(),
      birthDate: json['birthDate'] != null ? DateTime.parse(json['birthDate']) : DateTime.now(),
      gender: json['gender'] ?? 'Not Specified',
    );
  }
}
