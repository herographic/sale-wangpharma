// lib/screens/customer_ranking_screen.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:salewang/models/rebate.dart';
import 'package:salewang/models/sale_support_customer.dart';
import 'package:salewang/models/customer_ranking.dart';
import 'package:salewang/models/customer.dart';
import 'package:salewang/screens/customer_detail_screen.dart';

class CustomerRankingScreen extends StatefulWidget {
  const CustomerRankingScreen({super.key});

  @override
  State<CustomerRankingScreen> createState() => _CustomerRankingScreenState();
}

class _CustomerRankingScreenState extends State<CustomerRankingScreen> {
  Future<List<CustomerRanking>>? _rankingFuture;
  String? _selectedRouteCode;

  // Map for converting route codes to display names
  final Map<String, String> _routeCodeToNameMap = {
    'L1-1': 'อ.หาดใหญ่1', 'L1-2': 'เมืองสงขลา', 'L1-3': 'สะเดา', 'L2': 'ปัตตานี', 'L3': 'สตูล',
    'L4': 'พัทลุง', 'L5-1': 'นราธิวาส', 'L5-2': 'สุไหงโกลก', 'L6': 'ยะลา', 'L7': 'เบตง',
    'L9': 'ตรัง', 'L10': 'นครศรีฯ', 'Office': 'วังเภสัช', 'R-00': 'อื่นๆ', 'L1-5': 'สทิงพระ',
    'Logistic': 'ฝากขนส่ง', 'L11': 'กระบี่', 'L12': 'ภูเก็ต', 'L13': 'สุราษฎร์ฯ', 'L17': 'พังงา',
    'L16': 'ยาแห้ง', 'L4-1': 'พัทลุง VIP', 'L18': 'เกาะสมุย', 'L19': 'พัทลุง-นคร', 'L20': 'ชุมพร',
    'L9-11': 'กระบี่-ตรัง', 'L21': 'เกาะลันตา', 'L22': 'เกาะพะงัน', 'L23': 'อ.หาดใหญ่2',
  };

  @override
  void initState() {
    super.initState();
    _rankingFuture = _fetchAndProcessRankingData();
  }

  /// --- MODIFIED: Fetches route data from Firestore cache ---
  Future<Map<String, String>> _fetchRouteDataFromCache() async {
    final snapshot = await FirebaseFirestore.instance.collection('api_member_route_cache').get();
    if (snapshot.docs.isEmpty) return {};
    return {
      for (var doc in snapshot.docs)
        if (doc.data()['mem_code'] != null && doc.data()['route_code'] != null)
          doc.data()['mem_code']: doc.data()['route_code']
    };
  }

  /// --- MODIFIED: Fetches sales data from Firestore cache and filters client-side ---
  Future<List<CustomerRanking>> _fetchAndProcessRankingData({String? routeCode}) async {
    final firestore = FirebaseFirestore.instance;

    // Fetch all necessary data concurrently from Firestore cache
    final salesFuture = firestore.collection('api_sale_support_cache').get();
    final routesFuture = _fetchRouteDataFromCache();

    final responses = await Future.wait([salesFuture, routesFuture]);
    final salesSnapshot = responses[0] as QuerySnapshot<Map<String, dynamic>>;
    final routeDataMap = responses[1] as Map<String, String>;

    if (salesSnapshot.docs.isEmpty) {
      throw Exception('ไม่พบข้อมูลใน Cache กรุณาซิงค์ข้อมูลก่อน');
    }

    List<SaleSupportCustomer> apiCustomers = salesSnapshot.docs.map((doc) => SaleSupportCustomer.fromFirestore(doc)).toList();

    // Client-side filtering if a route is selected
    if (routeCode != null && routeCode.isNotEmpty) {
      apiCustomers.retainWhere((customer) {
        final customerRoute = routeDataMap[customer.memCode];
        return customerRoute == routeCode;
      });
    }

    final customerCodes = apiCustomers.map((c) => c.memCode ?? '').where((c) => c.isNotEmpty).toSet().toList();
    
    // Fetch supplementary data from other Firestore collections (Customer and Rebate)
    final Map<String, Customer> firestoreCustomerMap = {};
    final Map<String, RebateData> rebateDataMap = {};

    for (var i = 0; i < customerCodes.length; i += 30) {
      final chunk = customerCodes.sublist(i, i + 30 > customerCodes.length ? customerCodes.length : i + 30);
      if (chunk.isNotEmpty) {
        // Fetch customer data
        final customerSnapshot = await firestore.collection('customers').where('รหัสลูกค้า', whereIn: chunk).get();
        for (var doc in customerSnapshot.docs) {
          final customer = Customer.fromFirestore(doc);
          firestoreCustomerMap[customer.customerId] = customer;
        }
        // Fetch rebate data (document ID is the sanitized customer code)
        final rebateChunk = chunk.map((c) => c.replaceAll('/', '-')).toList();
        final rebateSnapshot = await firestore.collection('rebate').where(FieldPath.documentId, whereIn: rebateChunk).get();
        for (var doc in rebateSnapshot.docs) {
            final rebate = RebateData.fromFirestore(doc);
            rebateDataMap[rebate.customerId] = rebate;
        }
      }
    }
    
    final now = DateTime.now();
    final previousMonthDate = DateTime(now.year, now.month - 1, 1);
    List<CustomerRanking> processedList = [];

    for (var apiCustomer in apiCustomers) {
      double totalSalesCurrentMonthVat = 0.0;
      double totalSalesPreviousMonthVat = 0.0;

      for (var order in apiCustomer.order) {
        final orderDate = DateTime.tryParse(order.date ?? '');
        if (orderDate != null) {
          double priceBeforeVat = double.tryParse(order.price?.replaceAll(',', '') ?? '0') ?? 0.0;
          if (orderDate.year == now.year && orderDate.month == now.month) {
            totalSalesCurrentMonthVat += priceBeforeVat * 1.07;
          }
          if (orderDate.year == previousMonthDate.year && orderDate.month == previousMonthDate.month) {
            totalSalesPreviousMonthVat += priceBeforeVat * 1.07;
          }
        }
      }
      
      final currentRouteCode = routeDataMap[apiCustomer.memCode] ?? '';
      final routeName = _routeCodeToNameMap[currentRouteCode] ?? currentRouteCode;
      final customerId = apiCustomer.memCode ?? '';

      processedList.add(CustomerRanking(
        rank: 0,
        apiCustomer: apiCustomer,
        firestoreCustomer: firestoreCustomerMap[customerId],
        rebateData: rebateDataMap[customerId],
        route: routeName,
        totalSalesCurrentMonth: totalSalesCurrentMonthVat,
        totalSalesPreviousMonth: totalSalesPreviousMonthVat,
      ));
    }

    final activeCustomers = processedList.where((c) => c.totalSalesCurrentMonth > 0 || c.totalSalesPreviousMonth > 0).toList();
    
    activeCustomers.sort((a, b) {
      int salesCompare = b.totalSalesCurrentMonth.compareTo(a.totalSalesCurrentMonth);
      if (salesCompare != 0) return salesCompare;
      final dateA = DateTime.tryParse(a.apiCustomer.memLastsale ?? '');
      final dateB = DateTime.tryParse(b.apiCustomer.memLastsale ?? '');
      if (dateA != null && dateB != null) return dateB.compareTo(dateA);
      return 0;
    });

    List<CustomerRanking> rankedList = [];
    for (int i = 0; i < activeCustomers.length && i < 100; i++) {
      rankedList.add(CustomerRanking(
        rank: i + 1,
        apiCustomer: activeCustomers[i].apiCustomer,
        firestoreCustomer: activeCustomers[i].firestoreCustomer,
        rebateData: activeCustomers[i].rebateData,
        route: activeCustomers[i].route,
        totalSalesCurrentMonth: activeCustomers[i].totalSalesCurrentMonth,
        totalSalesPreviousMonth: activeCustomers[i].totalSalesPreviousMonth,
      ));
    }

    return rankedList;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0052D4), Color(0xFF4364F7), Color(0xFF6FB1FC)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('อันดับยอดขายลูกค้า', style: TextStyle(color: Colors.white, fontSize: 18, fontFamily: 'Kanit')),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                setState(() {
                  _rankingFuture = _fetchAndProcessRankingData(routeCode: _selectedRouteCode);
                });
              },
              tooltip: 'โหลดข้อมูลใหม่',
            ),
          ],
        ),
        body: Column(
          children: [
            _buildFilterPanel(),
            Expanded(
              child: FutureBuilder<List<CustomerRanking>>(
                future: _rankingFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Colors.white));
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('เกิดข้อผิดพลาด: ${snapshot.error}', style: const TextStyle(color: Colors.white, fontFamily: 'Kanit')));
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(child: Text('ไม่พบข้อมูลในเส้นทางที่เลือก', style: TextStyle(color: Colors.white, fontFamily: 'Kanit')));
                  }

                  final rankedCustomers = snapshot.data!;
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    itemCount: rankedCustomers.length,
                    itemBuilder: (context, index) {
                      return _buildTableRow(rankedCustomers[index]);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedRouteCode,
              isExpanded: true,
              hint: const Text("กรองตามเส้นทาง", style: TextStyle(fontFamily: 'Kanit')),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text("แสดงทุกเส้นทาง", style: TextStyle(fontFamily: 'Kanit')),
                ),
                ..._routeCodeToNameMap.entries.map((entry) {
                  return DropdownMenuItem<String>(
                    value: entry.key,
                    child: Text(entry.value, style: const TextStyle(fontFamily: 'Kanit')),
                  );
                }),
              ],
              onChanged: (String? newValue) {
                setState(() {
                  _selectedRouteCode = newValue;
                  _rankingFuture = _fetchAndProcessRankingData(routeCode: _selectedRouteCode);
                });
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTableRow(CustomerRanking data) {
    final now = DateTime.now();
    
    final currentMonthName = DateFormat('MMMM', 'th_TH').format(now);
    final previousMonthName = DateFormat('MMMM', 'th_TH').format(DateTime(now.year, now.month - 1));

    final rebate = data.rebateData;
    final monthlyTarget = rebate?.monthlyTarget ?? 0.0;
    
    Color cardColor = Colors.white;
    if (rebate != null && monthlyTarget > 0) {
      final percentageOfTarget = data.totalSalesCurrentMonth / monthlyTarget;
      if (percentageOfTarget >= 1.0) {
        cardColor = const Color(0xFFE8F5E9); // Light Green
      } else if (percentageOfTarget >= 0.8) {
        cardColor = const Color(0xFFFFF8E1); // Light Yellow
      }
    }

    return Card(
      color: cardColor,
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: InkWell(
        onTap: data.firestoreCustomer != null
            ? () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CustomerDetailScreen(customer: data.firestoreCustomer!),
                  ),
                );
              }
            : null,
        borderRadius: BorderRadius.circular(12.0),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 30,
                    child: Text(
                      data.rank.toString(),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black54, fontFamily: 'Kanit'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      if (data.customerImg != null && data.customerImg!.isNotEmpty) {
                        showDialog(
                          context: context,
                          builder: (_) => Dialog(child: Image.network(data.customerImg!)),
                        );
                      }
                    },
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: (data.customerImg != null && data.customerImg!.isNotEmpty)
                          ? NetworkImage(data.customerImg!)
                          : null,
                      child: (data.customerImg == null || data.customerImg!.isEmpty)
                          ? const Icon(Icons.store, size: 24, color: Colors.grey)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data.customerName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'Kanit'),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'ลูกค้า: ${data.customerCode} • ผู้ดูแล: ${data.apiCustomer.memSale ?? "-"}',
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontFamily: 'Kanit'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                ],
              ),
              const SizedBox(height: 16),
              _buildSalesInfoGrid(
                previousMonthName: previousMonthName,
                previousMonthValue: data.totalSalesPreviousMonth,
                currentMonthName: currentMonthName,
                currentMonthValue: data.totalSalesCurrentMonth,
                targetValue: monthlyTarget,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSalesInfoGrid({
    required String previousMonthName,
    required double previousMonthValue,
    required String currentMonthName,
    required double currentMonthValue,
    required double targetValue,
  }) {
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildDigitalDisplayColumn(
                label: previousMonthName,
                value: previousMonthValue,
                color: Colors.grey.shade600,
              ),
              const VerticalDivider(width: 16, thickness: 1),
              _buildDigitalDisplayColumn(
                label: currentMonthName,
                value: currentMonthValue,
                color: currentMonthValue >= previousMonthValue ? Colors.green.shade800 : Colors.red.shade800,
              ),
              const VerticalDivider(width: 16, thickness: 1),
              _buildDigitalDisplayColumn(
                label: 'เป้าหมาย',
                value: targetValue,
                color: Colors.orange.shade800,
                isTarget: true,
                currentValue: currentMonthValue,
              ),
            ],
          ),
        ),
        if (targetValue > 0) ...[
          const SizedBox(height: 8),
          _buildSummaryFooter(currentMonthValue, targetValue),
        ]
      ],
    );
  }

  Widget _buildDigitalDisplayColumn({
    required String label,
    required double value,
    required Color color,
    bool isTarget = false,
    double currentValue = 0,
  }) {
    final currencyFormat = NumberFormat("#,##0", "en_US");
    
    Color targetColor = Colors.orange.shade800;
    if (isTarget && value > 0) {
        if (currentValue >= value) {
            targetColor = Colors.green.shade800;
        }
    }

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: (isTarget ? targetColor : color).withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                fontFamily: 'Kanit',
                color: isTarget ? targetColor : color,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value == 0 && isTarget ? '-' : currencyFormat.format(value),
              style: TextStyle(
                fontFamily: 'Orbitron',
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: isTarget ? targetColor : color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryFooter(double currentValue, double targetValue) {
    final currencyFormat = NumberFormat("#,##0", "en_US");
    final surplus = currentValue - targetValue;
    
    double percentageOfTarget = 0;
    if (targetValue > 0) {
      percentageOfTarget = (currentValue / targetValue) * 100;
    }

    final bool isOverTarget = surplus >= 0;
    final Color mrbColor = isOverTarget ? Colors.green.shade700 : Colors.red.shade700;
    
    final String mrbText;
    if (isOverTarget) {
      mrbText = 'เกินเป้าหมาย ${currencyFormat.format(surplus)} บาท | ${percentageOfTarget.toStringAsFixed(1)}%';
    } else {
      mrbText = 'เป้าในเดือนขาดอีก ${currencyFormat.format(surplus.abs())} บาท | ${percentageOfTarget.toStringAsFixed(1)}%';
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          mrbText,
          style: TextStyle(
            fontSize: 15,
            color: mrbColor,
            fontWeight: FontWeight.bold,
            fontFamily: 'Kanit',
          ),
        ),
      ),
    );
  }
}
