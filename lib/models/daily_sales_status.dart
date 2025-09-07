// lib/models/daily_sales_status.dart

import 'dart:convert';

// Helper function to parse the main JSON structure
List<DailySalesStatus> dailySalesStatusFromJson(String str) =>
    List<DailySalesStatus>.from(
        json.decode(str).map((x) => DailySalesStatus.fromJson(x)));

// Main model for the entire API response object
class DailySalesStatus {
  final String day;
  final String date;
  final String allTarget;
  final List<EmployeePayload> payload;
  final String allSale;
  final String allShop;
  final String allBill;
  final String allList;
  final String allPrice;

  DailySalesStatus({
    required this.day,
    required this.date,
    required this.allTarget,
    required this.payload,
    required this.allSale,
    required this.allShop,
    required this.allBill,
    required this.allList,
    required this.allPrice,
  });

  factory DailySalesStatus.fromJson(Map<String, dynamic> json) =>
      DailySalesStatus(
        day: json["day"],
        date: json["date"],
        allTarget: json["all_target"],
        payload: List<EmployeePayload>.from(
            json["payload"].map((x) => EmployeePayload.fromJson(x))),
        allSale: json["all_sale"],
        allShop: json["all_shop"],
        allBill: json["all_bill"],
        allList: json["all_list"],
        allPrice: json["all_price"],
      );
}

// Model for the employee data inside the 'payload' array
class EmployeePayload {
  final String empCode;
  final String? empNickname;
  final String empImg;
  final String empMobileS;
  final String? empIdLine;
  final String lineLink;
  final String lineQrcode;
  final String shop;
  final String bill;
  final String list;
  final String price;

  EmployeePayload({
    required this.empCode,
    this.empNickname,
    required this.empImg,
    required this.empMobileS,
    this.empIdLine,
    required this.lineLink,
    required this.lineQrcode,
    required this.shop,
    required this.bill,
    required this.list,
    required this.price,
  });

  factory EmployeePayload.fromJson(Map<String, dynamic> json) =>
      EmployeePayload(
        empCode: json["emp_code"],
        empNickname: json["emp_nickname"],
        empImg: json["emp_img"],
        empMobileS: json["emp_mobileS"],
        empIdLine: json["emp_IDLine"],
        lineLink: json["line_link"],
        lineQrcode: json["line_qrcode"],
        shop: json["Shop"],
        bill: json["Bill"],
        list: json["List"],
        price: json["Price"],
      );
}
