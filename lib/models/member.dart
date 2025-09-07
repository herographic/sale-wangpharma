// lib/models/member.dart

import 'dart:convert';

// Helper function to parse JSON string into a Member object or a list of Members
List<Member> memberFromJson(String str) {
  try {
    final jsonData = json.decode(str);
    if (jsonData is List) {
      return List<Member>.from(jsonData.map((x) => Member.fromJson(x)));
    } else if (jsonData is Map<String, dynamic>) {
      // Handle case where a single object is returned, if it's a valid member
      if (jsonData.containsKey('mem_code')) {
        return [Member.fromJson(jsonData)];
      }
    }
    return []; // Return empty list if format is unexpected or no valid data
  } catch (e) {
    return [];
  }
}

// Member class representing the data structure from the new API response
class Member {
    final String? memCode;
    final String? memName;
    final String? province;
    final String? empCode;
    final String? addressLine1;
    final String? addressLine2;
    final String? subDistrict;
    final String? district;
    final String? postalCode;
    final String? memNote;
    final String? memShippingNote;
    final String? routeCode;
    final String? memTel;

    Member({
        this.memCode,
        this.memName,
        this.province,
        this.empCode,
        this.addressLine1,
        this.addressLine2,
        this.subDistrict,
        this.district,
        this.postalCode,
        this.memNote,
        this.memShippingNote,
        this.routeCode,
        this.memTel,
    });

    // Factory constructor to create a Member instance from a JSON map
    factory Member.fromJson(Map<String, dynamic> json) => Member(
        memCode: json["mem_code"],
        memName: json["mem_name"],
        province: json["province"],
        empCode: json["emp_code"],
        addressLine1: json["address_line1"],
        addressLine2: json["address_line2"],
        subDistrict: json["sub_district"],
        district: json["district"],
        postalCode: json["postal_code"],
        memNote: json["mem_note"],
        memShippingNote: json["mem_shipping_note"],
        routeCode: json["route_code"],
        memTel: json["mem_tel"],
    );
}
