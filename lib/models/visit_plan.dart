// lib/models/visit_plan.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class VisitPlan {
  final String id;
  final String customerId;
  final String customerName;
  final String? notes;
  final Timestamp plannedAt;
  final Timestamp createdAt;
  final String createdBy;
  final String salespersonId;
  // Assignment
  final String? assignedToId;
  final String? assignedToName;
  // Acceptance
  final String? acceptedById;
  final String? acceptedByName;
  final Timestamp? acceptedAt;
  // Completion summary
  final String? resultNotes;
  final Timestamp? doneAt;
  final List<String> photoUrls;
  final String? signatureUrl;
  final String? completedById;
  final String? completedByName;

  VisitPlan({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.plannedAt,
    required this.createdAt,
    required this.createdBy,
    required this.salespersonId,
    this.notes,
  this.assignedToId,
  this.assignedToName,
  this.acceptedById,
  this.acceptedByName,
  this.acceptedAt,
  this.resultNotes,
  this.doneAt,
  this.photoUrls = const [],
  this.signatureUrl,
  this.completedById,
  this.completedByName,
  });

  factory VisitPlan.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return VisitPlan(
      id: doc.id,
      customerId: (data['customerId'] ?? '').toString(),
      customerName: (data['customerName'] ?? '').toString(),
      notes: data['notes']?.toString(),
      plannedAt: data['plannedAt'] as Timestamp,
      createdAt: (data['createdAt'] as Timestamp?) ?? Timestamp.now(),
      createdBy: (data['createdBy'] ?? '').toString(),
      salespersonId: (data['salespersonId'] ?? '').toString(),
      assignedToId: (data['assignedToId'] ?? data['assigneeId'] ?? '')?.toString().isEmpty == true
          ? null
          : (data['assignedToId'] ?? data['assigneeId']).toString(),
      assignedToName: (data['assignedToName'] ?? data['assigneeName'] ?? '')?.toString().isEmpty == true
          ? null
          : (data['assignedToName'] ?? data['assigneeName']).toString(),
      acceptedById: (data['acceptedById'] ?? '')?.toString().isEmpty == true ? null : data['acceptedById'].toString(),
      acceptedByName: (data['acceptedByName'] ?? '')?.toString().isEmpty == true ? null : data['acceptedByName'].toString(),
      acceptedAt: data['acceptedAt'] as Timestamp?,
      resultNotes: (data['resultNotes'] ?? '')?.toString().isEmpty == true ? null : data['resultNotes'].toString(),
      doneAt: data['doneAt'] as Timestamp?,
      photoUrls: (data['photoUrls'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      signatureUrl: (data['signatureUrl'] ?? '')?.toString().isEmpty == true ? null : data['signatureUrl'].toString(),
      completedById: (data['completedById'] ?? '')?.toString().isEmpty == true ? null : data['completedById'].toString(),
      completedByName: (data['completedByName'] ?? '')?.toString().isEmpty == true ? null : data['completedByName'].toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'customerId': customerId,
        'customerName': customerName,
        'notes': notes,
        'plannedAt': plannedAt,
        'createdAt': createdAt,
        'createdBy': createdBy,
        'salespersonId': salespersonId,
        'assignedToId': assignedToId,
        'assignedToName': assignedToName,
        'acceptedById': acceptedById,
        'acceptedByName': acceptedByName,
        'acceptedAt': acceptedAt,
        'resultNotes': resultNotes,
        'doneAt': doneAt,
        'photoUrls': photoUrls,
        'signatureUrl': signatureUrl,
        'completedById': completedById,
        'completedByName': completedByName,
      };

  // Derived status
  String get status {
    if (doneAt != null) return 'done';
    if (acceptedById != null) return 'in_progress';
    return 'new';
  }
}
