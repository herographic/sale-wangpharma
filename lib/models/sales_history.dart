// lib/models/sales_history.dart
import 'dart:convert';

// ฟังก์ชันสำหรับแปลง JSON string เป็น List ของ SalesHistory
List<SalesHistory> salesHistoryFromJson(String str) => List<SalesHistory>.from(json.decode(str).map((x) => SalesHistory.fromJson(x)));

// Model สำหรับข้อมูลประวัติการขายจาก API historyday-status.php
class SalesHistory {
    final int saleShop;
    final int saleBill;
    final double salePrice;
    final String saleDay;
    final DateTime saleDate;

    SalesHistory({
        required this.saleShop,
        required this.saleBill,
        required this.salePrice,
        required this.saleDay,
        required this.saleDate,
    });

    // Factory constructor สำหรับสร้าง instance จาก JSON
    // เพิ่มการตรวจสอบค่า null และแปลงชนิดข้อมูลให้ถูกต้อง
    factory SalesHistory.fromJson(Map<String, dynamic> json) {
      return SalesHistory(
        saleShop: int.tryParse(json["sale_shop"]?.toString() ?? '0') ?? 0,
        saleBill: int.tryParse(json["sale_bill"]?.toString() ?? '0') ?? 0,
        salePrice: double.tryParse(json["sale_price"]?.toString() ?? '0.0') ?? 0.0,
        saleDay: json["sale_day"] ?? 'N/A',
        saleDate: DateTime.tryParse(json["sale_date"] ?? '') ?? DateTime.now(),
      );
    }
}
