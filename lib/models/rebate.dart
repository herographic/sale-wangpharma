// lib/models/rebate.dart

import 'package:cloud_firestore/cloud_firestore.dart';

// Represents the entire row of data for a single customer from the Excel file.
class RebateData {
  // Customer Info
  final String customerId;
  final String customerName;
  final String? phoneNumber;
  final String? priceLevel;
  final String? route;
  final String? salesperson;
  final double sales2024;
  final double monthlyTarget;
  final double nineMonthTarget;
  final double bonus;

  // Monthly Sales Data
  final double salesJan;
  final double salesFeb;
  final double salesMar;
  final double salesApr;
  final double salesMay;
  final double salesJun;
  final double salesJul;
  final double salesAug;
  final double salesSep;
  final double salesOct;
  final double salesNov;
  final double salesDec;

  // Monthly Percentage Data
  final double percentApr;
  final double percentMay;
  final double percentJun;
  final double percentJul;
  final double percentAug;
  final double percentSep;
  final double percentOct;
  final double percentNov;
  final double percentDec;

  RebateData({
    required this.customerId,
    required this.customerName,
    this.phoneNumber,
    this.priceLevel,
    this.route,
    this.salesperson,
    required this.sales2024,
    required this.monthlyTarget,
    required this.nineMonthTarget,
    required this.bonus,
    required this.salesJan,
    required this.salesFeb,
    required this.salesMar,
    required this.salesApr,
    required this.salesMay,
    required this.salesJun,
    required this.salesJul,
    required this.salesAug,
    required this.salesSep,
    required this.salesOct,
    required this.salesNov,
    required this.salesDec,
    required this.percentApr,
    required this.percentMay,
    required this.percentJun,
    required this.percentJul,
    required this.percentAug,
    required this.percentSep,
    required this.percentOct,
    required this.percentNov,
    required this.percentDec,
  });

  // Helper to safely parse strings to double
  static double parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    String stringValue = value.toString().replaceAll(',', '').replaceAll('%', '').trim();
    if (stringValue.isEmpty) return 0.0;
    return double.tryParse(stringValue) ?? 0.0;
  }

  // Factory to create an instance from a map (e.g., a row from Excel)
  factory RebateData.fromMap(Map<String, dynamic> map) {
    return RebateData(
      customerId: map['รหัสลูกค้า']?.toString().trim() ?? '',
      customerName: map['ชื่อลูกค้า']?.toString().trim() ?? '',
      phoneNumber: map['เบอร์']?.toString().trim(),
      priceLevel: map['ราคา']?.toString().trim(),
      route: map['เส้นทาง']?.toString().trim(),
      salesperson: map['ผู้ดูแล']?.toString().trim(),
      sales2024: parseDouble(map['2024']),
      monthlyTarget: parseDouble(map['เป้า/เดือน']),
      nineMonthTarget: parseDouble(map['เป้า 9 เดือน']),
      bonus: parseDouble(map['สมมนาคุณ']),
      salesJan: parseDouble(map['ม.ค.']),
      salesFeb: parseDouble(map['ก.พ.']),
      salesMar: parseDouble(map['มี.ค.']),
      salesApr: parseDouble(map['เม.ย.']),
      salesMay: parseDouble(map['พ.ค.']),
      salesJun: parseDouble(map['มิ.ย.']),
      salesJul: parseDouble(map['ก.ค.']),
      salesAug: parseDouble(map['ส.ค.']),
      salesSep: parseDouble(map['ก.ย.']),
      salesOct: parseDouble(map['ต.ค.']),
      salesNov: parseDouble(map['พ.ย.']),
      salesDec: parseDouble(map['ธ.ค.']),
      percentApr: parseDouble(map['%เม.ย.']),
      percentMay: parseDouble(map['%พ.ค.']),
      percentJun: parseDouble(map['%มิ.ย.']),
      percentJul: parseDouble(map['%ก.ค.']),
      percentAug: parseDouble(map['%ส.ค.']),
      percentSep: parseDouble(map['%ก.ย.']),
      percentOct: parseDouble(map['%ต.ค.']),
      percentNov: parseDouble(map['%พ.ย.']),
      percentDec: parseDouble(map['%ธ.ค.']),
    );
  }

  // --- NEW: Factory to create an instance from a Firestore document ---
  factory RebateData.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return RebateData(
      customerId: data['customerId'] ?? '',
      customerName: data['customerName'] ?? '',
      phoneNumber: data['phoneNumber'],
      priceLevel: data['priceLevel'],
      route: data['route'],
      salesperson: data['salesperson'],
      sales2024: (data['sales2024'] ?? 0.0).toDouble(),
      monthlyTarget: (data['monthlyTarget'] ?? 0.0).toDouble(),
      nineMonthTarget: (data['nineMonthTarget'] ?? 0.0).toDouble(),
      bonus: (data['bonus'] ?? 0.0).toDouble(),
      salesJan: (data['salesJan'] ?? 0.0).toDouble(),
      salesFeb: (data['salesFeb'] ?? 0.0).toDouble(),
      salesMar: (data['salesMar'] ?? 0.0).toDouble(),
      salesApr: (data['salesApr'] ?? 0.0).toDouble(),
      salesMay: (data['salesMay'] ?? 0.0).toDouble(),
      salesJun: (data['salesJun'] ?? 0.0).toDouble(),
      salesJul: (data['salesJul'] ?? 0.0).toDouble(),
      salesAug: (data['salesAug'] ?? 0.0).toDouble(),
      salesSep: (data['salesSep'] ?? 0.0).toDouble(),
      salesOct: (data['salesOct'] ?? 0.0).toDouble(),
      salesNov: (data['salesNov'] ?? 0.0).toDouble(),
      salesDec: (data['salesDec'] ?? 0.0).toDouble(),
      percentApr: (data['percentApr'] ?? 0.0).toDouble(),
      percentMay: (data['percentMay'] ?? 0.0).toDouble(),
      percentJun: (data['percentJun'] ?? 0.0).toDouble(),
      percentJul: (data['percentJul'] ?? 0.0).toDouble(),
      percentAug: (data['percentAug'] ?? 0.0).toDouble(),
      percentSep: (data['percentSep'] ?? 0.0).toDouble(),
      percentOct: (data['percentOct'] ?? 0.0).toDouble(),
      percentNov: (data['percentNov'] ?? 0.0).toDouble(),
      percentDec: (data['percentDec'] ?? 0.0).toDouble(),
    );
  }

  // Method to convert instance to a map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'customerId': customerId,
      'customerName': customerName,
      'phoneNumber': phoneNumber,
      'priceLevel': priceLevel,
      'route': route,
      'salesperson': salesperson,
      'sales2024': sales2024,
      'monthlyTarget': monthlyTarget,
      'nineMonthTarget': nineMonthTarget,
      'bonus': bonus,
      'salesJan': salesJan,
      'salesFeb': salesFeb,
      'salesMar': salesMar,
      'salesApr': salesApr,
      'salesMay': salesMay,
      'salesJun': salesJun,
      'salesJul': salesJul,
      'salesAug': salesAug,
      'salesSep': salesSep,
      'salesOct': salesOct,
      'salesNov': salesNov,
      'salesDec': salesDec,
      'percentApr': percentApr,
      'percentMay': percentMay,
      'percentJun': percentJun,
      'percentJul': percentJul,
      'percentAug': percentAug,
      'percentSep': percentSep,
      'percentOct': percentOct,
      'percentNov': percentNov,
      'percentDec': percentDec,
    };
  }
}
