// lib/models/bill_history.dart

import 'package:cloud_firestore/cloud_firestore.dart';

// Represents a single item within a bill
class BillItem {
  final String productId;
  final String description;
  final double quantity;
  final String unit;
  final double unitPrice;
  final String discount;
  final double totalAmount;
  final double vat;
  final double netAmount;
  final String note;

  BillItem({
    required this.productId,
    required this.description,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.discount,
    required this.totalAmount,
    required this.vat,
    required this.netAmount,
    required this.note,
  });

  factory BillItem.fromMap(Map<String, dynamic> map) {
    return BillItem(
      productId: (map['รหัสสินค้า'] ?? '').toString(),
      description: (map['รายละเอียด'] ?? '').toString(),
      quantity: double.tryParse((map['จำนวน'] ?? '0').toString()) ?? 0.0,
      unit: (map['หน่วย'] ?? '').toString(),
      unitPrice: double.tryParse((map['ราคา/หน่วย'] ?? '0').toString()) ?? 0.0,
      discount: (map['ส่วนลด'] ?? '').toString(),
      totalAmount: double.tryParse((map['จำนวนเงิน'] ?? '0').toString()) ?? 0.0,
      vat: double.tryParse((map['ภาษีมูลค่าเพิ่ม'] ?? '0').toString()) ?? 0.0,
      netAmount: double.tryParse((map['ยอดเงินสุทธิ'] ?? '0').toString()) ?? 0.0,
      note: (map['หมายเหตุ'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'รหัสสินค้า': productId,
      'รายละเอียด': description,
      'จำนวน': quantity,
      'หน่วย': unit,
      'ราคา/หน่วย': unitPrice,
      'ส่วนลด': discount,
      'จำนวนเงิน': totalAmount,
      'ภาษีมูลค่าเพิ่ม': vat,
      'ยอดเงินสุทธิ': netAmount,
      'หมายเหตุ': note,
    };
  }
}

// Represents the entire bill history document
class BillHistory {
  final String id;
  final String customerId;
  final String invoiceNumber;
  final String date;
  final String cd; // FIXED: Added the 'CD' field
  final String accountId;
  final String dueDate;
  final String salesperson;
  final List<BillItem> items;

  BillHistory({
    required this.id,
    required this.customerId,
    required this.invoiceNumber,
    required this.date,
    required this.cd, // FIXED: Added to constructor
    required this.accountId,
    required this.dueDate,
    required this.salesperson,
    required this.items,
  });

  factory BillHistory.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    var itemsData = data['items'] as List<dynamic>? ?? [];
    List<BillItem> billItems = itemsData.map((itemMap) => BillItem.fromMap(itemMap)).toList();

    return BillHistory(
      id: doc.id,
      customerId: data['รหัสลูกหนี้'] ?? '',
      invoiceNumber: data['เลขที่ใบกำกับ'] ?? '',
      date: data['วันที่'] ?? '',
      cd: data['CD'] ?? '', // FIXED: Read from Firestore
      accountId: data['รหัสบัญชี'] ?? '',
      dueDate: data['ครบกำหนด'] ?? '',
      salesperson: data['พนง.ขาย'] ?? '',
      items: billItems,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'รหัสลูกหนี้': customerId,
      'เลขที่ใบกำกับ': invoiceNumber,
      'วันที่': date,
      'CD': cd, // FIXED: Add to map for Firestore
      'รหัสบัญชี': accountId,
      'ครบกำหนด': dueDate,
      'พนง.ขาย': salesperson,
      'items': items.map((item) => item.toMap()).toList(),
    };
  }
}
