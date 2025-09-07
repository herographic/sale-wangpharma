// lib/models/salesperson_performance.dart

// This model holds the aggregated performance data for a single salesperson.
class SalespersonPerformance {
  final String salespersonName;
  final String? photoUrl;
  final String? employeeCode;

  int totalCustomers;
  int customersWithPendingSO;
  int totalCallsToday; // Total number of calls made today
  int uniqueCustomersCalledToday; // Number of unique customers called today
  DateTime? lastCallTime; // Timestamp of the last call made today
  bool isActivelyCalling; // True if the last call was within the last 7 minutes
  double todaySales; // Total sales from bill_history for today

  SalespersonPerformance({
    required this.salespersonName,
    this.photoUrl,
    this.employeeCode,
    this.totalCustomers = 0,
    this.customersWithPendingSO = 0,
    this.totalCallsToday = 0,
    this.uniqueCustomersCalledToday = 0,
    this.lastCallTime,
    this.isActivelyCalling = false,
    this.todaySales = 0.0,
  });
}
