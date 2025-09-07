// lib/models/daily_report.dart

import 'package:cloud_firestore/cloud_firestore.dart';

// Represents the performance of a single employee for a given day.
class EmployeeDailyPerformance {
  final String empCode;
  final String? empNickname;
  final String empImg;
  final double price;
  final int shop;
  final int bill;
  final int list;
  final int totalCalls;
  final int totalCustomers;
  final int calledCustomers;

  EmployeeDailyPerformance({
    required this.empCode,
    this.empNickname,
    required this.empImg,
    required this.price,
    required this.shop,
    required this.bill,
    required this.list,
    required this.totalCalls,
    required this.totalCustomers,
    required this.calledCustomers,
  });

  // Factory constructor to create an instance from a map (e.g., from Firestore)
  factory EmployeeDailyPerformance.fromMap(Map<String, dynamic> map) {
    return EmployeeDailyPerformance(
      empCode: map['empCode'] ?? '',
      empNickname: map['empNickname'],
      empImg: map['empImg'] ?? '',
      price: (map['price'] ?? 0.0).toDouble(),
      shop: map['shop'] ?? 0,
      bill: map['bill'] ?? 0,
      list: map['list'] ?? 0,
      totalCalls: map['totalCalls'] ?? 0,
      totalCustomers: map['totalCustomers'] ?? 0,
      calledCustomers: map['calledCustomers'] ?? 0,
    );
  }

  // Method to convert instance to a map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'empCode': empCode,
      'empNickname': empNickname,
      'empImg': empImg,
      'price': price,
      'shop': shop,
      'bill': bill,
      'list': list,
      'totalCalls': totalCalls,
      'totalCustomers': totalCustomers,
      'calledCustomers': calledCustomers,
    };
  }
}

// Represents the entire daily report summary.
class DailyReport {
  final String date; // YYYY-MM-DD
  final Timestamp timestamp;
  final double grandTotalSales;
  final int totalItemsAllTeams;
  final List<EmployeeDailyPerformance> salesTeam;
  final List<EmployeeDailyPerformance> dataEntryTeam;

  DailyReport({
    required this.date,
    required this.timestamp,
    required this.grandTotalSales,
    required this.totalItemsAllTeams,
    required this.salesTeam,
    required this.dataEntryTeam,
  });

  factory DailyReport.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return DailyReport(
      date: doc.id,
      timestamp: data['timestamp'] ?? Timestamp.now(),
      grandTotalSales: (data['grandTotalSales'] ?? 0.0).toDouble(),
      totalItemsAllTeams: data['totalItemsAllTeams'] ?? 0,
      salesTeam: (data['salesTeam'] as List<dynamic>?)
              ?.map((e) => EmployeeDailyPerformance.fromMap(e))
              .toList() ??
          [],
      dataEntryTeam: (data['dataEntryTeam'] as List<dynamic>?)
              ?.map((e) => EmployeeDailyPerformance.fromMap(e))
              .toList() ??
          [],
    );
  }
}
