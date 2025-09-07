// lib/models/daily_so.dart

import 'dart:convert';

// Helper function to parse a JSON array string into a List of DailySO objects
List<DailySO> dailySOFromJson(String str) {
  try {
    final decoded = json.decode(str);
    final dynamic data = decoded is List
        ? decoded
        : (decoded is Map<String, dynamic> && decoded['data'] is List)
            ? decoded['data']
            : null;
    if (data is List) {
      return List<DailySO>.from(data.map((x) => DailySO.fromJson(x as Map<String, dynamic>)));
    }
    return [];
  } catch (e) {
    print('Error decoding DailySO JSON: $e');
    return [];
  }
}

// Main model for the daily sales order data from the API
class DailySO {
  final String? soCode;
  final String? soDate;
  final String? soMemcode;
  final List<SOProduct> soProduct;
  final int? soList;
  final String? soSumprice;

  DailySO({
    this.soCode,
    this.soDate,
    this.soMemcode,
    required this.soProduct,
    this.soList,
    this.soSumprice,
  });

  factory DailySO.fromJson(Map<String, dynamic> json) => DailySO(
        soCode: json["so_code"]?.toString(),
        soDate: json["so_date"]?.toString(),
        soMemcode: json["so_memcode"]?.toString(),
        soProduct: () {
          final sp = json["so_product"];
          if (sp is List) {
            return List<SOProduct>.from(sp.map((x) => SOProduct.fromJson(x as Map<String, dynamic>)));
          }
          return <SOProduct>[];
        }(),
        soList: () {
          final v = json["so_list"];
          if (v == null) return null;
          if (v is int) return v;
          if (v is double) return v.toInt();
          return int.tryParse(v.toString());
        }(),
        soSumprice: json["so_sumprice"]?.toString(),
      );
}

// Model for the product data within a sales order
class SOProduct {
  final String? proCode;
  final String? proName;
  final String? proAmount;
  final String? proUnit;
  final String? proPriceUnit;
  final String? proDiscount;
  final String? proPrice;

  SOProduct({
    this.proCode,
    this.proName,
    this.proAmount,
    this.proUnit,
    this.proPriceUnit,
    this.proDiscount,
    this.proPrice,
  });

  factory SOProduct.fromJson(Map<String, dynamic> json) => SOProduct(
        proCode: json["pro_code"]?.toString(),
        proName: json["pro_name"]?.toString(),
        proAmount: json["pro_amount"]?.toString(),
        proUnit: json["pro_unit"]?.toString(),
        proPriceUnit: json["pro_priceUnit"]?.toString(),
        proDiscount: json["pro_discount"]?.toString(),
        proPrice: json["pro_price"]?.toString(),
      );
}
