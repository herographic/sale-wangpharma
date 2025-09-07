// lib/models/customer_ranking.dart

import 'package:salewang/models/sale_support_customer.dart';
import 'package:salewang/models/customer.dart'; // Import Firestore Customer model
import 'package:salewang/models/rebate.dart'; // Import Rebate model

// This model is a processed entity, not a direct API model.
// It combines data from multiple sources for the ranking screen.
class CustomerRanking {
  final int rank;
  final SaleSupportCustomer apiCustomer;
  final Customer? firestoreCustomer; // Added to hold Firestore data for navigation
  final RebateData? rebateData; // NEW: To hold rebate data
  final String? route;
  final double totalSalesCurrentMonth;
  final double totalSalesPreviousMonth;

  CustomerRanking({
    required this.rank,
    required this.apiCustomer,
    this.firestoreCustomer,
    this.rebateData, // NEW: Added to constructor
    this.route,
    required this.totalSalesCurrentMonth,
    required this.totalSalesPreviousMonth,
  });

  // Getters for easy access in the UI
  String get customerCode => apiCustomer.memCode ?? '-';
  String get customerName => apiCustomer.memName ?? 'N/A';
  String? get customerImg => apiCustomer.memImg;
}
