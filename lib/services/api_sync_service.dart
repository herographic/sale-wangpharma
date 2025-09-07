// lib/services/api_sync_service.dart

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:salewang/models/sale_support_customer.dart';

/// A service class to handle synchronization of data from external APIs to Firestore.
/// This version fetches customer data route by route to ensure all data is captured
/// and correctly associated with its route code. It uses an update-merge strategy
/// instead of deleting the entire collection.
class ApiSyncService {
  static const String _saleSupportBaseUrl = 'http://www.wangpharma.com/API/appV3/sale-support.php';
  static const String _bearerToken = 'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJtZW1fY29kZSI6Ii4wNjM1In0.5U_Yle8l5bZqOVTxqlvQo36XyQaW2bf3Q-h91bw3UL8';
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static final Map<String, String> _allRoutes = {
    'L1-1': 'อ.หาดใหญ่1', 'L1-2': 'เมืองสงขลา', 'L1-3': 'สะเดา', 'L2': 'ปัตตานี', 'L3': 'สตูล',
    'L4': 'พัทลุง', 'L5-1': 'นราธิวาส', 'L5-2': 'สุไหงโกลก', 'L6': 'ยะลา', 'L7': 'เบตง',
    'L9': 'ตรัง', 'L10': 'นครศรีฯ', 'Office': 'วังเภสัช', 'R-00': 'อื่นๆ', 'L1-5': 'สทิงพระ',
    'Logistic': 'ฝากขนส่ง', 'L11': 'กระบี่', 'L12': 'ภูเก็ต', 'L13': 'สุราษฎร์ฯ', 'L17': 'พังงา',
    'L16': 'ยาแห้ง', 'L4-1': 'พัทลุง VIP', 'L18': 'เกาะสมุย', 'L19': 'พัทลุง-นคร', 'L20': 'ชุมพร',
    'L9-11': 'กระบี่-ตรัง', 'L21': 'เกาะลันตา', 'L22': 'เกาะพะงัน', 'L23': 'อ.หาดใหญ่2',
  };

  /// Fetches customer data from the 'sale-support' API for all routes and caches it in Firestore.
  /// This method now intelligently updates existing data instead of deleting and re-creating.
  static Future<void> syncAllCustomerData({
    required ValueNotifier<String> statusNotifier,
    required ValueNotifier<double> progressNotifier,
  }) async {
    statusNotifier.value = 'กำลังเริ่มซิงค์ข้อมูลลูกค้าทั้งหมด...';
    progressNotifier.value = 0.0;

    final Map<String, Map<String, dynamic>> allCustomersDataMap = {};
    final totalRoutes = _allRoutes.length;
    int routesProcessed = 0;

    // 1. Fetch data from the API for each route
    for (var routeEntry in _allRoutes.entries) {
      final routeCode = routeEntry.key;
      final routeName = routeEntry.value;
      routesProcessed++;
      statusNotifier.value = 'กำลังดึงข้อมูลเส้นทาง: $routeName ($routesProcessed/$totalRoutes)';
      
      // Add limit=9999 to ensure all customers from the route are fetched
      final url = Uri.parse('$_saleSupportBaseUrl?r_search=$routeCode&limit=9999');
      final response = await http.get(url, headers: {'Authorization': 'Bearer $_bearerToken'});

      if (response.statusCode == 200) {
        final List<SaleSupportCustomer> customersInRoute = saleSupportCustomerFromJson(response.body);
        for (var customer in customersInRoute) {
          if (customer.memCode != null && customer.memCode!.isNotEmpty) {
            // Convert customer to map and add the route code
            final customerMap = customer.toMap();
            customerMap['route_code'] = routeCode; // Add route code directly to the customer data
            allCustomersDataMap[customer.memCode!] = customerMap;
          }
        }
      } else {
        // Log error but continue with other routes
        print('Warning: API Error for route $routeCode: ${response.statusCode}');
      }
      progressNotifier.value = routesProcessed / totalRoutes;
    }

    if (allCustomersDataMap.isEmpty) {
      throw Exception('ไม่สามารถดึงข้อมูลลูกค้าจาก API ได้เลย');
    }

    // 2. Sync All Customer Data using an update/merge strategy
    statusNotifier.value = 'กำลังเตรียมข้อมูลลูกค้าเพื่ออัปเดต...';
    final saleSupportCollection = _firestore.collection('api_sale_support_cache');
    await _batchUpdate(
      collection: saleSupportCollection,
      dataMap: allCustomersDataMap,
      statusNotifier: statusNotifier,
      progressNotifier: progressNotifier,
      processName: 'ลูกค้า',
    );

    // 3. Update metadata
    await _firestore.collection('api_data_cache').doc('metadata').set({
      'allCustomerDataLastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    statusNotifier.value = 'ซิงค์ข้อมูลลูกค้าและเส้นทางทั้งหมดสำเร็จ!';
  }

  /// Generic helper to update a Firestore collection in batches using Set with merge.
  static Future<void> _batchUpdate({
    required CollectionReference collection,
    required Map<String, Map<String, dynamic>> dataMap,
    required ValueNotifier<String> statusNotifier,
    required ValueNotifier<double> progressNotifier,
    required String processName,
  }) async {
    const batchSize = 400;
    final allKeys = dataMap.keys.toList();
    final totalItems = allKeys.length;

    for (int i = 0; i < totalItems; i += batchSize) {
      final batch = _firestore.batch();
      final end = (i + batchSize > totalItems) ? totalItems : i + batchSize;

      for (int j = i; j < end; j++) {
        final key = allKeys[j];
        final data = dataMap[key]!;
        final docId = key.replaceAll('/', '-');
        final docRef = collection.doc(docId);
        // Use set with merge: true to update existing fields or create new documents
        batch.set(docRef, data, SetOptions(merge: true));
      }

      statusNotifier.value = 'กำลังอัปเดต $processName... (${((end / totalItems) * 100).toStringAsFixed(0)}%)';
      await batch.commit();
      progressNotifier.value = end / totalItems;
    }
  }
}
