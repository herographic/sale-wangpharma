// lib/models/sale_order_time.dart

import 'dart:convert';

/// Represents one employee's sales/time stats from
/// https://www.wangpharma.com/API/appV3/sale-order-time.php?date=YYYY-MM-DD
class SaleOrderTimeEntry {
  final String empCode;
  final String empNickname;
  final String empFullname;
  final String empMobile;
  final String empImg;
  final int careCus;
  final int careRoute;
  final String? firstBill; // 'YYYY-MM-DD HH:mm:ss'
  final String? lastBill;  // 'YYYY-MM-DD HH:mm:ss'
  final String? periodMinutes; // e.g., '651 นาที'
  final String? periodHours;   // e.g., '10 ชั่วโมง'
  final String? priceTime;     // e.g., '421.36 บาท.สต./นาที'
  final int saleCus;
  final int saleBill;
  final int saleList;
  final String salePrice; // e.g., '274,303.00' (string with commas)
  final List<Map<String, String>> saleTimeRaw; // [{"00:00":"0.00"}, ...]

  SaleOrderTimeEntry({
    required this.empCode,
    required this.empNickname,
    required this.empFullname,
    required this.empMobile,
    required this.empImg,
    required this.careCus,
    required this.careRoute,
    required this.firstBill,
    required this.lastBill,
    required this.periodMinutes,
    required this.periodHours,
    required this.priceTime,
    required this.saleCus,
    required this.saleBill,
    required this.saleList,
    required this.salePrice,
    required this.saleTimeRaw,
  });

  factory SaleOrderTimeEntry.fromJson(Map<String, dynamic> json) {
    return SaleOrderTimeEntry(
      empCode: (json['emp_code'] ?? '').toString(),
      empNickname: (json['emp_nickname'] ?? '').toString(),
      empFullname: (json['emp_fullname'] ?? '').toString(),
      empMobile: (json['emp_mobile'] ?? '').toString(),
      empImg: (json['emp_img'] ?? '').toString(),
      careCus: _toInt(json['care_cus']),
      careRoute: _toInt(json['care_route']),
      firstBill: json['first_bill']?.toString(),
      lastBill: json['last_bill']?.toString(),
      periodMinutes: json['period_minutes']?.toString(),
      periodHours: json['period_hours']?.toString(),
      priceTime: json['price_time']?.toString(),
      saleCus: _toInt(json['sale_cus']),
      saleBill: _toInt(json['sale_bill']),
      saleList: _toInt(json['sale_list']),
      salePrice: (json['sale_price'] ?? '0').toString(),
      saleTimeRaw: _parseSaleTime(json['sale_time']),
    );
  }

  static List<Map<String, String>> _parseSaleTime(dynamic v) {
    if (v is List) {
      return v
          .map((e) => Map<String, String>.from((e as Map).map((k, val) => MapEntry(k.toString(), val.toString()))))
          .toList();
    }
    return <Map<String, String>>[];
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    final s = v.toString().replaceAll(',', '').trim();
    return int.tryParse(s) ?? 0;
  }

  double get salePriceValue {
    final s = salePrice.replaceAll(',', '').trim();
    return double.tryParse(s) ?? 0.0;
  }

  /// Returns a map hour (e.g., '00:00') -> amount as double
  Map<String, double> get saleTimeByHour {
    final m = <String, double>{};
    for (final item in saleTimeRaw) {
      if (item.isEmpty) continue;
      final hour = item.keys.first;
      final val = item.values.first.replaceAll(',', '').trim();
      m[hour] = double.tryParse(val) ?? 0.0;
    }
    return m;
  }

  DateTime? get firstBillAt => _parseDate(firstBill);
  DateTime? get lastBillAt => _parseDate(lastBill);

  static DateTime? _parseDate(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    return DateTime.tryParse(iso.replaceAll('/', '-'));
  }
}

List<SaleOrderTimeEntry> saleOrderTimeListFromJson(String body) {
  try {
    final data = json.decode(body);
    if (data is List) {
      return data.map((e) => SaleOrderTimeEntry.fromJson(e)).toList();
    }
    return <SaleOrderTimeEntry>[];
  } catch (_) {
    return <SaleOrderTimeEntry>[];
  }
}

/// Aggregates multiple lists (e.g., multiple days) into monthly totals by employee.
List<SaleOrderTimeEntry> aggregateMonthly(List<List<SaleOrderTimeEntry>> lists) {
  final map = <String, _Agg>{};
  for (final dayList in lists) {
    for (final e in dayList) {
      final a = map.putIfAbsent(e.empCode, () => _Agg.fromEntry(e));
      a.add(e);
    }
  }
  return map.values.map((a) => a.toEntry()).toList();
}

class _Agg {
  String empCode;
  String empNickname;
  String empFullname;
  String empMobile;
  String empImg;
  int careCus;
  int careRoute;
  DateTime? firstBillAt;
  DateTime? lastBillAt;
  int saleCus;
  int saleBill;
  int saleList;
  double salePrice;
  final Map<String, double> saleTimeByHour; // hour -> amount

  _Agg({
    required this.empCode,
    required this.empNickname,
    required this.empFullname,
    required this.empMobile,
    required this.empImg,
    required this.careCus,
    required this.careRoute,
    required this.firstBillAt,
    required this.lastBillAt,
    required this.saleCus,
    required this.saleBill,
    required this.saleList,
    required this.salePrice,
    required this.saleTimeByHour,
  });

  factory _Agg.fromEntry(SaleOrderTimeEntry e) => _Agg(
        empCode: e.empCode,
        empNickname: e.empNickname,
        empFullname: e.empFullname,
        empMobile: e.empMobile,
        empImg: e.empImg,
        careCus: e.careCus,
        careRoute: e.careRoute,
        firstBillAt: e.firstBillAt,
        lastBillAt: e.lastBillAt,
        saleCus: e.saleCus,
        saleBill: e.saleBill,
        saleList: e.saleList,
        salePrice: e.salePriceValue,
        saleTimeByHour: Map<String, double>.from(e.saleTimeByHour),
      );

  void add(SaleOrderTimeEntry e) {
    // Keep latest display info from the entry, but sum numeric metrics
    empNickname = e.empNickname.isNotEmpty ? e.empNickname : empNickname;
    empFullname = e.empFullname.isNotEmpty ? e.empFullname : empFullname;
    empMobile = e.empMobile.isNotEmpty ? e.empMobile : empMobile;
    empImg = e.empImg.isNotEmpty ? e.empImg : empImg;
    careCus = e.careCus > careCus ? e.careCus : careCus; // use max across days
    careRoute = e.careRoute > careRoute ? e.careRoute : careRoute;
    if (e.firstBillAt != null) {
      firstBillAt = firstBillAt == null || e.firstBillAt!.isBefore(firstBillAt!) ? e.firstBillAt : firstBillAt;
    }
    if (e.lastBillAt != null) {
      lastBillAt = lastBillAt == null || e.lastBillAt!.isAfter(lastBillAt!) ? e.lastBillAt : lastBillAt;
    }
    saleCus += e.saleCus;
    saleBill += e.saleBill;
    saleList += e.saleList;
    salePrice += e.salePriceValue;
    final m = e.saleTimeByHour;
    for (final h in m.keys) {
      saleTimeByHour[h] = (saleTimeByHour[h] ?? 0.0) + (m[h] ?? 0.0);
    }
  }

  SaleOrderTimeEntry toEntry() {
    // Build sale_time raw back from map for completeness
    final saleTimeRaw = saleTimeByHour.entries
        .toList()
        ..sort((a, b) => a.key.compareTo(b.key));
    final rawList = saleTimeRaw
        .map((e) => <String, String>{e.key: e.value.toStringAsFixed(2)})
        .toList();

    String? periodMinutes;
    String? periodHours;
    String? priceTime;
    if (firstBillAt != null && lastBillAt != null) {
      final minutes = lastBillAt!.difference(firstBillAt!).inMinutes;
      final hours = lastBillAt!.difference(firstBillAt!).inHours;
      periodMinutes = '$minutes นาที';
      periodHours = '$hours ชั่วโมง';
      if (minutes > 0) {
        priceTime = (salePrice / minutes).toStringAsFixed(2) + ' บาท.สต./นาที';
      }
    }

    return SaleOrderTimeEntry(
      empCode: empCode,
      empNickname: empNickname,
      empFullname: empFullname,
      empMobile: empMobile,
      empImg: empImg,
      careCus: careCus,
      careRoute: careRoute,
      firstBill: firstBillAt?.toIso8601String(),
      lastBill: lastBillAt?.toIso8601String(),
      periodMinutes: periodMinutes,
      periodHours: periodHours,
      priceTime: priceTime,
      saleCus: saleCus,
      saleBill: saleBill,
      saleList: saleList,
      salePrice: salePrice.toStringAsFixed(2),
      saleTimeRaw: rawList,
    );
  }
}
