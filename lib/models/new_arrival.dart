// lib/models/new_arrival.dart

import 'dart:convert';

// Helper function to parse a JSON array string into a List of NewArrival objects
List<NewArrival> newArrivalFromJson(String str) => List<NewArrival>.from(json.decode(str).map((x) => NewArrival.fromJson(x)));

class NewArrival {
    final String poiDate;
    final String poiCode;
    final String poiAp;
    final String poiPcode;
    final String poiPname;
    final String poiAmount;
    final String poiUnit;

    NewArrival({
        required this.poiDate,
        required this.poiCode,
        required this.poiAp,
        required this.poiPcode,
        required this.poiPname,
        required this.poiAmount,
        required this.poiUnit,
    });

    factory NewArrival.fromJson(Map<String, dynamic> json) => NewArrival(
        poiDate: json["poi_date"] ?? '',
        poiCode: json["poi_code"] ?? '',
        poiAp: json["poi_ap"] ?? '',
        poiPcode: json["poi_pcode"] ?? '',
        poiPname: json["poi_pname"] ?? '',
        poiAmount: json["poi_amount"] ?? '0.00',
        poiUnit: json["poi_unit"] ?? '',
    );
}
