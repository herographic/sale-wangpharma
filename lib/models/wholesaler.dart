// lib/models/wholesaler.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class Wholesaler {
  final String id;
  final String name;
  final String? nickname;
  final String? logoUrl;
  final String? address;
  final GeoPoint? location;
  final String? openingHours;
  final List<String>? deliveryRoutes;
  final String? promotions;
  final String? transportInfo;
  final String? pros;
  final String? cons;
  final String? customerFeedback;
  final String? repFeedback;
  final Timestamp lastUpdated;
  final String type; // 'wholesaler' or 'competitor'

  Wholesaler({
    required this.id,
    required this.name,
    this.nickname,
    this.logoUrl,
    this.address,
    this.location,
    this.openingHours,
    this.deliveryRoutes,
    this.promotions,
    this.transportInfo,
    this.pros,
    this.cons,
    this.customerFeedback,
    this.repFeedback,
    required this.lastUpdated,
    required this.type,
  });

  factory Wholesaler.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Wholesaler(
      id: doc.id,
      name: data['name'] ?? '',
      nickname: data['nickname'],
      logoUrl: data['logoUrl'],
      address: data['address'],
      location: data['location'],
      openingHours: data['openingHours'],
      deliveryRoutes: List<String>.from(data['deliveryRoutes'] ?? []),
      promotions: data['promotions'],
      transportInfo: data['transportInfo'],
      pros: data['pros'],
      cons: data['cons'],
      customerFeedback: data['customerFeedback'],
      repFeedback: data['repFeedback'],
      lastUpdated: data['lastUpdated'] ?? Timestamp.now(),
      type: data['type'] ?? 'wholesaler',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'nickname': nickname,
      'logoUrl': logoUrl,
      'address': address,
      'location': location,
      'openingHours': openingHours,
      'deliveryRoutes': deliveryRoutes,
      'promotions': promotions,
      'transportInfo': transportInfo,
      'pros': pros,
      'cons': cons,
      'customerFeedback': customerFeedback,
      'repFeedback': repFeedback,
      'lastUpdated': lastUpdated,
      'type': type,
    };
  }
}
