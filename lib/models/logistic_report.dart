// lib/models/logistic_report.dart

import 'dart:convert';

/// Parses the JSON string into a [LogisticReport] object.
///
/// This function is now updated to handle three different response structures from the API:
/// 1. A direct JSON array (List) of logistic items (from employee search).
/// 2. A JSON array containing a single object, which in turn contains the 'data' list (from route search).
/// 3. A single JSON object (Map) as a fallback.
LogisticReport logisticReportFromJson(String str) {
  final jsonData = json.decode(str);

  if (jsonData is List) {
    // UPDATED: Handle the specific structure for route-based searches.
    // This checks if the list contains a single map with the 'data' key inside.
    if (jsonData.isNotEmpty &&
        jsonData.first is Map<String, dynamic> &&
        jsonData.first.containsKey('data')) {
      return LogisticReport.fromJson(jsonData.first);
    }

    // This handles the original case for employee-based searches (a direct list of items).
    List<LogisticItem> items = List<LogisticItem>.from(jsonData
        .map((x) => LogisticItem.fromJson(x))
        .where((item) => item.memCode != null && item.memCode!.isNotEmpty));
    return LogisticReport(data: items);
  } else if (jsonData is Map<String, dynamic>) {
    // Handles cases where the API might return a single wrapper object.
    return LogisticReport.fromJson(jsonData);
  } else {
    // Returns an empty report for any other unexpected format.
    return LogisticReport(data: []);
  }
}

/// Represents the overall logistic report, which may include an employee code
/// and a list of delivery items.
class LogisticReport {
  final String? emp; // Employee code, typically present for route-based searches.
  final List<LogisticItem> data;

  LogisticReport({
    this.emp,
    required this.data,
  });

  factory LogisticReport.fromJson(Map<String, dynamic> json) {
    List<LogisticItem> items = [];
    if (json["data"] != null && json["data"] is List) {
      items = List<LogisticItem>.from(json["data"]!
          .map((x) => LogisticItem.fromJson(x))
          // Filter out items without a valid customer code to prevent displaying empty cards.
          .where((item) => item.memCode != null && item.memCode!.isNotEmpty));
    }
    return LogisticReport(
      emp: json["emp"],
      data: items,
    );
  }
}

/// Represents a single delivery item with all fields from the API.
/// This model is a 1-to-1 match with the JSON object structure.
class LogisticItem {
  final String? memCode;
  final String? memName;
  final String? memPhone;
  final String? memPrice;
  final String? empSale;
  final String? memRoute;
  final String? billAmount;
  final String? boxAmount;
  final String? sumprice;
  final String? status;
  final String? timeOut;
  final String? timeFinish;
  final String? timeOutFinish;
  final String? timePointToPoint;
  final String? weight;
  final String? capacity;

  LogisticItem({
    this.memCode,
    this.memName,
    this.memPhone,
    this.memPrice,
    this.empSale,
    this.memRoute,
    this.billAmount,
    this.boxAmount,
    this.sumprice,
    this.status,
    this.timeOut,
    this.timeFinish,
    this.timeOutFinish,
    this.timePointToPoint,
    this.weight,
    this.capacity,
  });

  factory LogisticItem.fromJson(Map<String, dynamic> json) => LogisticItem(
        memCode: json["mem_code"],
        memName: json["mem_name"],
        memPhone: json["mem_phone"],
        memPrice: json["mem_price"],
        empSale: json["emp_sale"],
        memRoute: json["mem_route"],
        billAmount: json["bill_amount"],
        boxAmount: json["box_amount"],
        sumprice: json["sumprice"],
        status: json["status"],
        timeOut: json["time_out"],
        timeFinish: json["time_finish"],
        timeOutFinish: json["time_out_finish"],
        timePointToPoint: json["time_point_to_point"],
        weight: json["weight"],
        capacity: json["capacity"],
      );
}
