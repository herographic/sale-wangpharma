// lib/models/task_note.dart

import 'package:cloud_firestore/cloud_firestore.dart';

enum TaskStatus { pending, approved, rejected }

class TaskNote {
  final String id;
  final String customerId; // Firestore document ID of the customer
  final String customerCode; // The human-readable customer code
  final String customerName;
  final String title;
  final String details;
  final Timestamp taskDateTime;
  final List<String> imageUrls;
  final String createdBy;
  final String createdById;
  final Timestamp createdAt;
  bool isDeleted; // To soft delete from the main tracker view
  String status; // 'pending', 'approved', 'rejected'
  String? approvedBy;
  Timestamp? approvedAt;
  String? priceLevel; // A / A+ / A- / B / C
  String? urgency; // urgent / asap / pending_fix -> mapped to Thai labels

  TaskNote({
    required this.id,
    required this.customerId,
    required this.customerCode,
    required this.customerName,
    required this.title,
    required this.details,
    required this.taskDateTime,
    required this.imageUrls,
    required this.createdBy,
    required this.createdById,
    required this.createdAt,
    this.isDeleted = false,
    this.status = 'pending',
    this.approvedBy,
    this.approvedAt,
  this.priceLevel,
  this.urgency,
  });

  factory TaskNote.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return TaskNote(
      id: doc.id,
      customerId: data['customerId'] ?? '',
      customerCode: data['customerCode'] ?? '',
      customerName: data['customerName'] ?? '',
      title: data['title'] ?? '',
      details: data['details'] ?? '',
      taskDateTime: data['taskDateTime'] ?? Timestamp.now(),
      imageUrls: List<String>.from(data['imageUrls'] ?? []),
      createdBy: data['createdBy'] ?? 'Unknown',
      createdById: data['createdById'] ?? '',
      createdAt: data['createdAt'] ?? Timestamp.now(),
      isDeleted: data['isDeleted'] ?? false,
      status: data['status'] ?? 'pending',
      approvedBy: data['approvedBy'],
      approvedAt: data['approvedAt'],
  priceLevel: data['priceLevel'],
  urgency: data['urgency'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'customerId': customerId,
      'customerCode': customerCode,
      'customerName': customerName,
      'title': title,
      'details': details,
      'taskDateTime': taskDateTime,
      'imageUrls': imageUrls,
      'createdBy': createdBy,
      'createdById': createdById,
      'createdAt': createdAt,
      'isDeleted': isDeleted,
      'status': status,
      'approvedBy': approvedBy,
      'approvedAt': approvedAt,
  'priceLevel': priceLevel,
  'urgency': urgency,
    };
  }
}
