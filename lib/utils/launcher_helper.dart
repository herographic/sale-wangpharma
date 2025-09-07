// lib/utils/launcher_helper.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:salewang/models/customer.dart';
import 'package:salewang/models/member.dart'; // Import Member model
import 'package:url_launcher/url_launcher.dart';

class LauncherHelper {
  // --- NEW FUNCTION for API Member data ---
  static Future<void> makeAndLogApiCall({
    required BuildContext context,
    required String phoneNumber,
    required Member member,
  }) async {
    // Convert Member to a temporary Customer object for logging
    final tempCustomer = Customer(
      id: member.memCode ?? '',
      customerId: member.memCode ?? '',
      name: member.memName ?? 'N/A',
      contacts: [{'name': 'เบอร์หลัก', 'phone': member.memTel ?? ''}],
      address1: member.addressLine1 ?? '',
      address2: member.addressLine2 ?? '',
      phone: member.memTel ?? '',
      contactPerson: '',
      email: '',
      customerType: '',
      taxId: '',
      branch: '',
      paymentTerms: '',
      creditLimit: '',
      salesperson: member.empCode ?? '',
      p: '', b1: '', b2: '', b3: '',
      startDate: '', lastSaleDate: '', lastPaymentDate: '',
    );
    // Call the original function with the converted data
    await makeAndLogPhoneCall(context: context, phoneNumber: phoneNumber, customer: tempCustomer);
  }


  // Original function for Firestore Customer data
  static Future<void> makeAndLogPhoneCall({
    required BuildContext context,
    required String phoneNumber,
    required Customer customer,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่พบข้อมูลผู้ใช้ กรุณาล็อกอินใหม่')),
      );
      return;
    }

    if (phoneNumber.trim().isEmpty) {
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เบอร์โทรศัพท์ไม่ถูกต้อง')),
      );
      return;
    }

    final sanitizedPhoneNumber = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    final Uri launchUri = Uri(scheme: 'tel', path: sanitizedPhoneNumber);

    try {
      final now = Timestamp.now();
      final threeMinutesAgo = Timestamp.fromMillisecondsSinceEpoch(
          now.millisecondsSinceEpoch - (3 * 60 * 1000));

      final recentCallSnapshot = await FirebaseFirestore.instance
          .collection('call_logs')
          .where('salespersonId', isEqualTo: user.uid)
          .where('customerId', isEqualTo: customer.customerId)
          .where('callTimestamp', isGreaterThanOrEqualTo: threeMinutesAgo)
          .limit(1)
          .get();

      if (recentCallSnapshot.docs.isNotEmpty) {
        if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('เพิ่งโทรหาลูกค้ารายนี้เมื่อเร็วๆ นี้ (จะไม่นับซ้ำ)'),
              backgroundColor: Colors.orangeAccent,
              ),
          );
        }
        if (await canLaunchUrl(launchUri)) {
          await launchUrl(launchUri);
        } else {
          throw 'Could not launch $launchUri';
        }
        return;
      }

      await user.reload();
      final freshUser = FirebaseAuth.instance.currentUser;

      final callLogData = {
        'salespersonId': freshUser!.uid,
        'salespersonName': freshUser.displayName ?? freshUser.email ?? 'N/A',
        'customerId': customer.customerId,
        'customerName': customer.name,
        'phoneNumber': phoneNumber,
        'callTimestamp': Timestamp.now(),
        'durationInSeconds': 1,
      };
      await FirebaseFirestore.instance.collection('call_logs').add(callLogData);

      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri);
      } else {
        throw 'Could not launch $launchUri';
      }

    } catch (e) {
       if(context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการโทรหรือบันทึก: $e')),
        );
       }
    }
  }
}
