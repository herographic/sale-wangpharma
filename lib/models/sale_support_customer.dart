// lib/models/sale_support_customer.dart

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';

// Helper function remains for the sync service
List<SaleSupportCustomer> saleSupportCustomerFromJson(String str) {
  try {
    final jsonData = json.decode(str);
    if (jsonData is List) {
      return List<SaleSupportCustomer>.from(jsonData.map((x) => SaleSupportCustomer.fromJson(x)));
    }
    return [];
  } catch (e) {
    print('Error decoding SaleSupportCustomer JSON: $e');
    return [];
  }
}

class SaleSupportCustomer {
    final String? memImg;
    final String? memCode;
    final String? memName;
    final String? memAddress;
    final String? memPhone;
    final String? memPrice;
    final List<OrderHistory> order;
    final String? memSale;
    final String? memSalesupport;
    final String? memLastsale;
    final String? memLastpayments;
    final String? memBalance;
    final String? boxs;
    final String? routeCode;
    final List<StatusOrder> statusOrder;

    SaleSupportCustomer({
        this.memImg,
        this.memCode,
        this.memName,
        this.memAddress,
        this.memPhone,
        this.memPrice,
        required this.order,
        this.memSale,
        this.memSalesupport,
        this.memLastsale,
        this.memLastpayments,
        this.memBalance,
    this.boxs,
    this.routeCode,
        required this.statusOrder,
    });

    // Factory from JSON map (used by sync service and fromFirestore)
    factory SaleSupportCustomer.fromJson(Map<String, dynamic> json) => SaleSupportCustomer(
        memImg: json["mem_img"],
        memCode: json["mem_code"],
        memName: json["mem_name"],
        memAddress: json["mem_address"],
        memPhone: json["mem_phone"],
        memPrice: json["mem_price"],
        order: json["order"] == null ? [] : List<OrderHistory>.from(json["order"]!.map((x) => OrderHistory.fromJson(x))),
        memSale: json["mem_sale"],
        memSalesupport: json["mem_salesupport"],
        memLastsale: json["mem_lastsale"],
        memLastpayments: json["mem_lastpayments"],
        memBalance: json["mem_balance"],
        boxs: json["boxs"],
    statusOrder: json["Status_order"] == null ? [] : List<StatusOrder>.from(json["Status_order"]!.map((x) => StatusOrder.fromJson(x))),
    routeCode: json["route_code"],
    );

    // NEW: Factory to create instance from a Firestore document
    factory SaleSupportCustomer.fromFirestore(DocumentSnapshot doc) {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      return SaleSupportCustomer.fromJson(data);
    }

    // NEW: Method to convert instance to a map for Firestore
    Map<String, dynamic> toMap() => {
        "mem_img": memImg,
        "mem_code": memCode,
        "mem_name": memName,
        "mem_address": memAddress,
        "mem_phone": memPhone,
        "mem_price": memPrice,
        "order": List<dynamic>.from(order.map((x) => x.toMap())),
        "mem_sale": memSale,
        "mem_salesupport": memSalesupport,
        "mem_lastsale": memLastsale,
        "mem_lastpayments": memLastpayments,
        "mem_balance": memBalance,
        "boxs": boxs,
    "Status_order": List<dynamic>.from(statusOrder.map((x) => x.toMap())),
    "route_code": routeCode,
    };
}

class OrderHistory {
    final String? date;
    final String? bill;
    final String? price;

    OrderHistory({
        this.date,
        this.bill,
        this.price,
    });

    factory OrderHistory.fromJson(Map<String, dynamic> json) => OrderHistory(
        date: json["date"],
        bill: json["bill"],
        price: json["price"],
    );

    // NEW: toMap method
    Map<String, dynamic> toMap() => {
        "date": date,
        "bill": bill,
        "price": price,
    };
}

class StatusOrder {
    final String? sohRuning;
    final String? status;
    final String? emp;

    StatusOrder({
        this.sohRuning,
        this.status,
        this.emp,
    });

    factory StatusOrder.fromJson(Map<String, dynamic> json) => StatusOrder(
        sohRuning: json["soh_runing"],
        status: json["status"],
        emp: json["emp"],
    );

    // NEW: toMap method
    Map<String, dynamic> toMap() => {
        "soh_runing": sohRuning,
        "status": status,
        "emp": emp,
    };
}
