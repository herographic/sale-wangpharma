// lib/models/member_route.dart

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';

// Helper function remains for the sync service
List<MemberRoute> memberRouteFromJson(String str) {
  try {
    final jsonData = json.decode(str);
    if (jsonData is List) {
      return List<MemberRoute>.from(jsonData.map((x) => MemberRoute.fromJson(x)));
    }
    return [];
  } catch (e) {
    print('Error decoding MemberRoute JSON: $e');
    return [];
  }
}

class MemberRoute {
    final String? memCode;
    final String? routeCode;

    MemberRoute({
        this.memCode,
        this.routeCode,
    });

    factory MemberRoute.fromJson(Map<String, dynamic> json) => MemberRoute(
        memCode: json["mem_code"],
        routeCode: json["route_code"],
    );

    // NEW: Factory to create instance from a Firestore document
    factory MemberRoute.fromFirestore(DocumentSnapshot doc) {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      return MemberRoute.fromJson(data);
    }

    // NEW: Method to convert instance to a map for Firestore
    Map<String, dynamic> toMap() => {
      "mem_code": memCode,
      "route_code": routeCode,
    };
}
