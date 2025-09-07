// lib/models/new_customer_prospect.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class NewCustomerProspect {
  final String id;
  final String tempId;
  final String status; // 'ร้านใหม่' or 'ร้านเก่าลูกค้าใหม่'
  final Timestamp? openingDate;
  final String? previousSupplier;
  final String storeName;
  final String? branch;
  final String address; // A consolidated, readable address string
  final String district;
  final String province;
  final String phone; // A primary contact phone for quick access
  final String paymentTerms;
  final String details;
  final String notes;
  final List<String> imageUrls; // A consolidated list of all images for simple display
  final String salesperson;
  final String salesSupport;
  final Timestamp createdAt;
  final String createdBy;
  String approvalStatus;

  // Holds the original, unmodified data from Firestore. This is key for flexibility.
  final Map<String, dynamic> rawData;

  NewCustomerProspect({
    required this.id,
    required this.tempId,
    required this.status,
    this.openingDate,
    this.previousSupplier,
    required this.storeName,
    this.branch,
    required this.address,
    required this.district,
    required this.province,
    required this.phone,
    required this.paymentTerms,
    required this.details,
    required this.notes,
    required this.imageUrls,
    required this.salesperson,
    required this.salesSupport,
    required this.createdAt,
    required this.createdBy,
    this.approvalStatus = 'pending',
    required this.rawData,
  });

  // FIXED: Updated factory to handle both old and new data structures gracefully.
  factory NewCustomerProspect.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    // --- Smart Data Extraction ---
    // This logic checks for the new nested structure first, then falls back to the old flat structure.

    // Image URLs Consolidation
    List<String> allImageUrls = [];
    if (data['categorizedImageUrls'] != null && data['categorizedImageUrls'] is Map) {
      final categorizedUrls = Map<String, dynamic>.from(data['categorizedImageUrls']);
      categorizedUrls.forEach((key, value) {
        if (value is String && value.isNotEmpty) {
          allImageUrls.add(value);
        }
      });
    } else if (data['imageUrls'] != null && data['imageUrls'] is List) {
      // Fallback for old structure
      allImageUrls = List<String>.from(data['imageUrls']);
    }

    // Address construction for display
    String fullAddress = '';
    if (data['storeAddress'] != null && data['storeAddress'] is Map) {
        final adr = data['storeAddress'];
        fullAddress = [
            adr['houseNumber'],
            adr['moo'],
            adr['road'],
            adr['soi'],
        ].where((s) => s != null && s.isNotEmpty).join(' ');
    } else {
        fullAddress = data['address'] ?? '';
    }

    // Primary phone number extraction
    String primaryPhone = '';
    if (data['contacts'] != null && data['contacts'] is Map) {
      final contacts = data['contacts'];
      primaryPhone = contacts['owner']?['phone'] ?? 
                     contacts['pharmacist']?['phone'] ?? 
                     contacts['purchaser']?['phone'] ?? '';
    }
    if (primaryPhone.isEmpty) {
      primaryPhone = data['phone'] ?? '';
    }


    return NewCustomerProspect(
      id: doc.id,
      rawData: data, // Store the original map for detailed display
      tempId: data['tempId'] ?? '',
      status: data['status'] ?? 'ร้านใหม่',
      openingDate: data['openingDate'],
      previousSupplier: data['previousSupplier'],
      storeName: data['storeInfo']?['name'] ?? data['storeName'] ?? '',
      branch: data['storeInfo']?['branch'] ?? data['branch'],
      address: fullAddress,
      district: data['storeAddress']?['district'] ?? data['district'] ?? '',
      province: data['storeAddress']?['province'] ?? data['province'] ?? '',
      phone: primaryPhone,
      paymentTerms: data['paymentInfo']?['term'] ?? data['paymentTerms'] ?? '',
      details: data['additionalInfo']?['details'] ?? data['details'] ?? '',
      notes: data['additionalInfo']?['notes'] ?? data['notes'] ?? '',
      imageUrls: allImageUrls,
      salesperson: data['staffInfo']?['salesperson'] ?? data['salesperson'] ?? '',
      salesSupport: data['staffInfo']?['salesSupport'] ?? data['salesSupport'] ?? '',
      createdAt: data['createdAt'] ?? Timestamp.now(),
      createdBy: data['createdBy'] ?? 'Unknown',
      approvalStatus: data['approvalStatus'] ?? 'pending',
    );
  }
}
