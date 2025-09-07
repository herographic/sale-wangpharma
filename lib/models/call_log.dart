// lib/models/call_log.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class CallLog {
  final String id;
  final String salespersonId;
  final String salespersonName;
  final String customerId;
  final String customerName;
  final String phoneNumber;
  final Timestamp callTimestamp;
  final int durationInSeconds; // Reserved for future implementation

  CallLog({
    required this.id,
    required this.salespersonId,
    required this.salespersonName,
    required this.customerId,
    required this.customerName,
    required this.phoneNumber,
    required this.callTimestamp,
    this.durationInSeconds = 0,
  });

  factory CallLog.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return CallLog(
      id: doc.id,
      salespersonId: data['salespersonId'] ?? '',
      salespersonName: data['salespersonName'] ?? '',
      customerId: data['customerId'] ?? '',
      customerName: data['customerName'] ?? '',
      phoneNumber: data['phoneNumber'] ?? '',
      callTimestamp: data['callTimestamp'] ?? Timestamp.now(),
      durationInSeconds: data['durationInSeconds'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'salespersonId': salespersonId,
      'salespersonName': salespersonName,
      'customerId': customerId,
      'customerName': customerName,
      'phoneNumber': phoneNumber,
      'callTimestamp': callTimestamp,
      'durationInSeconds': durationInSeconds,
    };
  }
}
