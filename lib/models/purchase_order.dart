// lib/models/purchase_order.dart

class PurchaseOrder {
  final String date;
  final String cd;
  final String poNumber; // เลขที่ใบกำกับ is the PO Number
  final String supplierId;
  final String accountId;
  final String dueDate;
  final String productId;
  final String description;
  final double quantity;
  final String unit;
  final double unitPrice;
  final String discount;
  final double amount;
  final double vat;
  final double netAmount;
  final String note;

  PurchaseOrder({
    required this.date,
    required this.cd,
    required this.poNumber,
    required this.supplierId,
    required this.accountId,
    required this.dueDate,
    required this.productId,
    required this.description,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.discount,
    required this.amount,
    required this.vat,
    required this.netAmount,
    required this.note,
  });

  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value.toString().trim().isEmpty) return 0.0;
    return double.tryParse(value.toString().replaceAll(',', '')) ?? 0.0;
  }

  factory PurchaseOrder.fromMap(Map<String, dynamic> map) {
    return PurchaseOrder(
      date: map['วันที่']?.toString() ?? '',
      cd: map['CD']?.toString() ?? '',
      poNumber: map['เลขที่ใบกำกับ']?.toString() ?? '',
      supplierId: map['รหัสเจ้าหนี้']?.toString() ?? '',
      accountId: map['รหัสบัญชี']?.toString() ?? '',
      dueDate: map['ครบกำหนด']?.toString() ?? '',
      productId: map['รหัสสินค้า']?.toString() ?? '',
      description: map['รายละเอียด']?.toString() ?? '',
      quantity: _parseDouble(map['จำนวน']),
      unit: map['หน่วย']?.toString() ?? '',
      unitPrice: _parseDouble(map['ราคา/หน่วย']),
      discount: map['ส่วนลด']?.toString() ?? '',
      amount: _parseDouble(map['จำนวนเงิน']),
      vat: _parseDouble(map['ภาษีมูลค่าเพิ่ม']),
      netAmount: _parseDouble(map['ยอดเงินสุทธิ']),
      note: map['หมายเหตุ']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'วันที่': date,
      'CD': cd,
      'เลขที่ใบกำกับ': poNumber,
      'รหัสเจ้าหนี้': supplierId,
      'รหัสบัญชี': accountId,
      'ครบกำหนด': dueDate,
      'รหัสสินค้า': productId,
      'รายละเอียด': description,
      'จำนวน': quantity,
      'หน่วย': unit,
      'ราคา/หน่วย': unitPrice,
      'ส่วนลด': discount,
      'จำนวนเงิน': amount,
      'ภาษีมูลค่าเพิ่ม': vat,
      'ยอดเงินสุทธิ': netAmount,
      'หมายเหตุ': note,
    };
  }
}
