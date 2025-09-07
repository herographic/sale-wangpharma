import 'package:cloud_firestore/cloud_firestore.dart';

class SalesOrder {
  final String id;
  final String orderDate;
  final String cd;
  final String invoiceNumber;
  final String customerId;
  final String accountId;
  final String dueDate;
  final String salesperson;
  final String productId;
  final String productDescription;
  final double quantity;
  final String unit;
  final double unitPrice;
  final String discount;
  final double totalAmount;
  final List<String> clearedBy; // NEW: To store UIDs of who cleared it

  SalesOrder({
    required this.id,
    required this.orderDate,
    required this.cd,
    required this.invoiceNumber,
    required this.customerId,
    required this.accountId,
    required this.dueDate,
    required this.salesperson,
    required this.productId,
    required this.productDescription,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.discount,
    required this.totalAmount,
    this.clearedBy = const [], // NEW
  });

  // ADDED: Helper function to safely parse any value to a double.
  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    // It can handle strings like "1", "1.5", and even "1,000.50"
    return double.tryParse(value.toString().replaceAll(',', '')) ?? 0.0;
  }

  factory SalesOrder.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    
    // Safely handle the new 'clearedBy' field
    List<String> clearedByList = [];
    if (data['clearedBy'] is List) {
      clearedByList = List<String>.from(data['clearedBy']);
    }

    return SalesOrder(
      id: doc.id,
      orderDate: (data['วันที่'] ?? '').toString(),
      cd: data['CD'] ?? '',
      invoiceNumber: data['เลขที่ใบกำกับ'] ?? '',
      customerId: data['รหัสลูกหนี้'] ?? '',
      accountId: (data['รหัสบัญชี'] ?? '').toString(),
      dueDate: (data['ครบกำหนด'] ?? '').toString(),
      salesperson: data['พนง.ขาย'] ?? '',
      productId: data['รหัสสินค้า'] ?? '',
      productDescription: data['รายละเอียด'] ?? '',
      quantity: _parseDouble(data['จำนวน']),
      unit: data['หน่วย'] ?? '',
      unitPrice: _parseDouble(data['ราคา/หน่วย']),
      discount: (data['ส่วนลด'] ?? '').toString(),
      totalAmount: _parseDouble(data['จำนวนเงิน']),
      clearedBy: clearedByList, // NEW
    );
  }
}
