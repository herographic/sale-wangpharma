// lib/models/rebate_customer.dart

import 'dart:convert';

// Helper function to parse a JSON array string into a List of RebateCustomer objects
List<RebateCustomer> rebateCustomerFromJson(String str) => List<RebateCustomer>.from(json.decode(str).map((x) => RebateCustomer.fromJson(x)));

// Helper function to safely parse string values to double
double _parseDouble(dynamic value) {
  if (value == null) return 0.0;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0.0;
}

// Model for the monthly target data
class Target {
    final String? month;
    final double target;
    final double sumprice;
    final double miss;

    Target({
        this.month,
        required this.target,
        required this.sumprice,
        required this.miss,
    });

    factory Target.fromJson(Map<String, dynamic> json) => Target(
        month: json["month"],
        target: _parseDouble(json["target"]),
        sumprice: _parseDouble(json["sumprice"]),
        miss: _parseDouble(json["miss"]),
    );
}

// Model class representing the complete customer data from the member_list.php API
class RebateCustomer {
    final String? memCode;
    final String? memName;
    final String? memAddress;
    final String memPhone;
    final String? memProvince;
    final String? memPrice;
    final dynamic memSale; // Can be null
    final double memBalance;
    final String? memLastpayments;
    final String? memLastsale;
    final List<dynamic>? order;
    final List<Target> target;

    RebateCustomer({
        this.memCode,
        this.memName,
        this.memAddress,
        required this.memPhone,
        this.memProvince,
        this.memPrice,
        this.memSale,
        required this.memBalance,
        this.memLastpayments,
        this.memLastsale,
        this.order,
        required this.target,
    });

    // Factory constructor to create a RebateCustomer instance from a JSON map
    factory RebateCustomer.fromJson(Map<String, dynamic> json) => RebateCustomer(
        memCode: json["mem_code"],
        memName: json["mem_name"],
        memAddress: json["mem_address"],
        memPhone: json["mem_phone"],
        memProvince: json["mem_province"],
        memPrice: json["mem_price"],
        memSale: json["mem_sale"],
        memBalance: _parseDouble(json["mem_balance"]),
        memLastpayments: json["mem_lastpayments"],
        memLastsale: json["mem_lastsale"],
        order: json["order"] == null ? [] : List<dynamic>.from(json["order"]!.map((x) => x)),
        target: json["target"] == null ? [] : List<Target>.from(json["target"]!.map((x) => Target.fromJson(x))),
    );
}
