// lib/models/app_order.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class AppOrderItem {
  final String productId;
  final String productDescription;
  final double quantity;
  final String unit;
  final double unitPrice;

  AppOrderItem({
    required this.productId,
    required this.productDescription,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
  });

  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'productDescription': productDescription,
      'quantity': quantity,
      'unit': unit,
      'unitPrice': unitPrice,
    };
  }

  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', '')) ?? 0.0;
  }

  factory AppOrderItem.fromMap(Map<String, dynamic> map) {
    return AppOrderItem(
      productId: map['productId'] ?? '',
      productDescription: map['productDescription'] ?? '',
      quantity: _parseDouble(map['quantity']),
      unit: map['unit'] ?? '',
      unitPrice: _parseDouble(map['unitPrice']),
    );
  }
}

class AppOrder {
  final String id;
  final String soNumber;
  final String customerId;
  final String customerName;
  final String salespersonId;
  final String salespersonName;
  final Timestamp orderDate;
  final double totalAmount;
  final List<AppOrderItem> items;
  final String status;
  final String note; // ADDED

  AppOrder({
    required this.id,
    required this.soNumber,
    required this.customerId,
    required this.customerName,
    required this.salespersonId,
    required this.salespersonName,
    required this.orderDate,
    required this.totalAmount,
    required this.items,
    this.status = 'pending',
    this.note = '', // ADDED with default value
  });

  factory AppOrder.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    var itemsData = data['items'] as List<dynamic>? ?? [];
    List<AppOrderItem> orderItems =
        itemsData.map((itemMap) => AppOrderItem.fromMap(itemMap)).toList();

    return AppOrder(
      id: doc.id,
      soNumber: data['soNumber'] ?? '',
      customerId: data['customerId'] ?? '',
      customerName: data['customerName'] ?? '',
      salespersonId: data['salespersonId'] ?? '',
      salespersonName: data['salespersonName'] ?? 'N/A',
      orderDate: data['orderDate'] ?? Timestamp.now(),
      totalAmount: (data['totalAmount'] ?? 0.0).toDouble(),
      items: orderItems,
      status: data['status'] ?? 'pending',
      note: data['note'] ?? '', // ADDED
    );
  }
}
