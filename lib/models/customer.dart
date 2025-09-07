// lib/models/customer.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class Customer {
  final String id; // Document ID จาก Firestore
  final String customerId;
  final String name;
  final String address1;
  final String address2;
  final String phone; // Kept for backward compatibility
  final String contactPerson; // Kept for backward compatibility
  final String email;
  final String customerType;
  final String taxId;
  final String branch;
  final String paymentTerms;
  final String creditLimit;
  final String salesperson;
  final String p;
  final String b1;
  final String b2;
  final String b3;
  final String startDate;
  final String lastSaleDate;
  final String lastPaymentDate;
  final List<Map<String, String>> contacts; // NEW: To hold multiple contacts

  Customer({
    required this.id,
    required this.customerId,
    required this.name,
    required this.address1,
    required this.address2,
    required this.phone,
    required this.contactPerson,
    required this.email,
    required this.customerType,
    required this.taxId,
    required this.branch,
    required this.paymentTerms,
    required this.creditLimit,
    required this.salesperson,
    required this.p,
    required this.b1,
    required this.b2,
    required this.b3,
    required this.startDate,
    required this.lastSaleDate,
    required this.lastPaymentDate,
    required this.contacts, // NEW
  });

  factory Customer.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    // --- NEW LOGIC to handle contacts ---
    List<Map<String, String>> parsedContacts = [];
    if (data['contacts'] != null && data['contacts'] is List) {
      // If 'contacts' field exists and is a list, use it
      for (var contact in data['contacts']) {
        if (contact is Map) {
          parsedContacts.add({
            'name': contact['name']?.toString() ?? '',
            'phone': contact['phone']?.toString() ?? '',
          });
        }
      }
    } else if ((data['โทรศัพท์'] as String? ?? '').isNotEmpty) {
      // Fallback for old data: convert the old single contact person and phone into the new list structure.
      parsedContacts.add({
        'name': data['ติดต่อกับ']?.toString() ?? 'เบอร์หลัก',
        'phone': data['โทรศัพท์']?.toString() ?? '',
      });
    }
    // --- END NEW LOGIC ---

    return Customer(
      id: doc.id,
      customerId: data['รหัสลูกค้า'] ?? '',
      name: data['ชื่อลูกค้า'] ?? '',
      address1: data['ที่อยู่ (1)'] ?? '',
      address2: data['ที่อยู่ (2)'] ?? '',
      phone: data['โทรศัพท์'] ?? '', // Still parse for backward compatibility
      contactPerson: data['ติดต่อกับ'] ?? '', // Still parse for backward compatibility
      email: data['อีเมล'] ?? '',
      customerType: data['ประเภทลูกหนี้'] ?? '',
      taxId: data['เลขประจำตัวผู้เสียภาษี'] ?? '',
      branch: data['สำนักงานใหญ่/สาขา'] ?? '',
      paymentTerms: (data['การชำระเงิน (วัน)'] ?? '0').toString(),
      creditLimit: (data['วงเงินอนุมัติ'] ?? '0').toString(),
      salesperson: data['พนักงานขาย'] ?? '',
      p: data['P'] ?? '',
      b1: (data['B1'] ?? '0').toString(),
      b2: (data['B2'] ?? '0').toString(),
      b3: (data['B3'] ?? '0').toString(),
      startDate: (data['วันที่เริ่มติดต่อ'] ?? '').toString(),
      lastSaleDate: (data['วันทีขายล่าสุด'] ?? '').toString(),
      lastPaymentDate: (data['วันที่รับเงินล่าสุด'] ?? '').toString(),
      contacts: parsedContacts, // Use the newly parsed list
    );
  }
}
