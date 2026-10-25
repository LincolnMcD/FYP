class TransactionRelatedItem {
  final String name;
  final String imei;
  final String deviceID;
  final String imageUrl;
  final String storage;
  final String color;

  TransactionRelatedItem({
    required this.name,
    required this.imei,
    this.deviceID = '',
    required this.imageUrl,
    this.storage = '',
    this.color = '',
  });

  factory TransactionRelatedItem.fromJson(Map<String, dynamic> json) {
    return TransactionRelatedItem(
      name: json['name']?.toString() ?? 'Device',
      imei: json['imei']?.toString() ?? '',
      deviceID: json['deviceID']?.toString() ?? '',
      imageUrl: json['imageUrl']?.toString() ?? '',
      storage: json['storage']?.toString() ?? '',
      color: json['color']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'imei': imei,
      'deviceID': deviceID,
      'imageUrl': imageUrl,
      'storage': storage,
      'color': color,
    };
  }
}

class TransactionBreakdown {
  final double baseAmount;
  final double taxAmount;
  final double totalPaid;

  TransactionBreakdown({
    required this.baseAmount,
    required this.taxAmount,
    required this.totalPaid,
  });

  factory TransactionBreakdown.fromJson(Map<String, dynamic> json) {
    return TransactionBreakdown(
      baseAmount: (json['baseAmount'] as num?)?.toDouble() ?? 0.0,
      taxAmount: (json['taxAmount'] as num?)?.toDouble() ?? 0.0,
      totalPaid: (json['totalPaid'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'baseAmount': baseAmount,
      'taxAmount': taxAmount,
      'totalPaid': totalPaid,
    };
  }
}

class CustomerTransactionModel {
  final String id;
  final String transactionId;
  final String? rawTransactionId;
  final String? orderID;
  final String? tradeInRequestID;
  final String? rentalID;
  final String title;
  final String type; // 'purchase', 'trade-in', 'rental'
  final double amount;
  final bool isCredit; // true = +RM (money to customer), false = -RM (charged to customer)
  final String status; // 'completed', 'failed', 'pending'
  final String date;
  final String formattedDate;
  final String paymentMethod;
  final TransactionRelatedItem relatedItem;
  final List<TransactionRelatedItem> relatedItems;
  final TransactionBreakdown breakdown;

  CustomerTransactionModel({
    required this.id,
    required this.transactionId,
    this.rawTransactionId,
    this.orderID,
    this.tradeInRequestID,
    this.rentalID,
    required this.title,
    required this.type,
    required this.amount,
    required this.isCredit,
    required this.status,
    required this.date,
    required this.formattedDate,
    required this.paymentMethod,
    required this.relatedItem,
    required this.relatedItems,
    required this.breakdown,
  });

  factory CustomerTransactionModel.fromJson(Map<String, dynamic> json) {
    List<TransactionRelatedItem> itemsList = [];
    if (json['relatedItems'] is List) {
      itemsList = (json['relatedItems'] as List)
          .map((e) => TransactionRelatedItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } else if (json['relatedItem'] is Map<String, dynamic>) {
      itemsList.add(TransactionRelatedItem.fromJson(json['relatedItem']));
    }

    final singleItem = itemsList.isNotEmpty
        ? itemsList.first
        : TransactionRelatedItem.fromJson(
            json['relatedItem'] is Map<String, dynamic>
                ? json['relatedItem']
                : <String, dynamic>{},
          );

    return CustomerTransactionModel(
      id: json['id']?.toString() ?? '',
      transactionId: json['transactionId']?.toString() ?? '',
      rawTransactionId: json['rawTransactionId']?.toString(),
      orderID: json['orderID']?.toString(),
      tradeInRequestID: json['tradeInRequestID']?.toString(),
      rentalID: json['rentalID']?.toString(),
      title: json['title']?.toString() ?? '',
      type: json['type']?.toString().toLowerCase() ?? 'purchase',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      isCredit: json['isCredit'] == true,
      status: json['status']?.toString().toLowerCase() ?? 'completed',
      date: json['date']?.toString() ?? '',
      formattedDate: json['formattedDate']?.toString() ?? '',
      paymentMethod: json['paymentMethod']?.toString() ?? 'Visa •••• 4242',
      relatedItem: singleItem,
      relatedItems: itemsList,
      breakdown: TransactionBreakdown.fromJson(
        json['breakdown'] is Map<String, dynamic>
            ? json['breakdown']
            : <String, dynamic>{},
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'transactionId': transactionId,
      'rawTransactionId': rawTransactionId,
      'orderID': orderID,
      'tradeInRequestID': tradeInRequestID,
      'rentalID': rentalID,
      'title': title,
      'type': type,
      'amount': amount,
      'isCredit': isCredit,
      'status': status,
      'date': date,
      'formattedDate': formattedDate,
      'paymentMethod': paymentMethod,
      'relatedItem': relatedItem.toJson(),
      'relatedItems': relatedItems.map((e) => e.toJson()).toList(),
      'breakdown': breakdown.toJson(),
    };
  }
}
