// lib/widgets/salesperson_header.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:salewang/models/daily_sales_status.dart';

// --- UPDATED: Model now includes the image URL ---
class IndividualSales {
  final double price;
  final String? imageUrl;

  IndividualSales({required this.price, this.imageUrl});
}

class SalespersonHeader extends StatefulWidget {
  const SalespersonHeader({super.key});

  @override
  State<SalespersonHeader> createState() => _SalespersonHeaderState();
}

class _SalespersonHeaderState extends State<SalespersonHeader> {
  User? _user;
  Stream<int>? _todayCallsStream;
  Future<IndividualSales>? _todaySalesFuture;
  String? _employeeId;

  @override
  void initState() {
    super.initState();
    _user = FirebaseAuth.instance.currentUser;
    if (_user != null) {
      _initializeData();
    }
  }

  Future<void> _initializeData() async {
    final userDoc = await FirebaseFirestore.instance
        .collection('salespeople')
        .doc(_user!.uid)
        .get();

    if (userDoc.exists) {
      _employeeId = userDoc.data()?['employeeId'];
    }

    if (!mounted) return;

    final now = DateTime.now();
    final startOfToday =
        Timestamp.fromDate(DateTime(now.year, now.month, now.day));

    final callsQuery = FirebaseFirestore.instance
        .collection('call_logs')
        .where('salespersonId', isEqualTo: _user!.uid)
        .where('callTimestamp', isGreaterThanOrEqualTo: startOfToday);

    setState(() {
      _todayCallsStream =
          callsQuery.snapshots().map((snapshot) => snapshot.size);
      _todaySalesFuture = _fetchIndividualTodaySales();
    });
  }

  Future<IndividualSales> _fetchIndividualTodaySales() async {
    if (_employeeId == null) {
      return IndividualSales(price: 0.0, imageUrl: null);
    }

    const String apiUrl = 'https://www.wangpharma.com/API/sale/day-status.php';
    const String token =
        'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJtZW1fY29kZSI6IjAzNTAifQ.9xQokBCn6ED-xwHQFXsa5Bah57dNc8vWJ_4Iin8E3m0';

    try {
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final List<DailySalesStatus> data =
            dailySalesStatusFromJson(response.body);
        if (data.isNotEmpty) {
          final employeePayload = data.first.payload.firstWhere(
            (emp) => emp.empCode == _employeeId,
            orElse: () => EmployeePayload(
                empCode: '',
                empImg: '',
                empMobileS: '',
                lineLink: '',
                lineQrcode: '',
                shop: '0',
                bill: '0',
                list: '0',
                price: '0.0'),
          );

          final price = double.tryParse(employeePayload.price) ?? 0.0;
          // --- NEW: Return the image URL ---
          return IndividualSales(price: price, imageUrl: employeePayload.empImg);
        } else {
          return IndividualSales(price: 0.0, imageUrl: null);
        }
      } else {
        throw Exception('API Error: ${response.statusCode}');
      }
    } catch (e) {
      print('Failed to fetch daily sales: $e');
      throw Exception('Failed to load sales data');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat("#,##0.00", "en_US");
    final displayName = _user?.displayName ?? _user?.email ?? 'พนักงานขาย';
    final displayId = _employeeId ??
        _user?.email?.split('@').first ??
        (_user != null ? _user!.uid.substring(0, 6) : 'N/A');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      margin: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(15.0),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          // --- UPDATED: CircleAvatar now uses FutureBuilder to get the image ---
          FutureBuilder<IndividualSales>(
            future: _todaySalesFuture,
            builder: (context, snapshot) {
              ImageProvider? backgroundImage;
              if (snapshot.hasData &&
                  snapshot.data?.imageUrl != null &&
                  snapshot.data!.imageUrl!.isNotEmpty) {
                backgroundImage = NetworkImage(snapshot.data!.imageUrl!);
              }
              return CircleAvatar(
                radius: 28,
                backgroundColor: Colors.white,
                backgroundImage: backgroundImage,
                onBackgroundImageError: backgroundImage != null ? (e, s) {
                  // You can log the error here if needed
                } : null,
                child: (backgroundImage == null)
                    ? const Icon(Icons.person, size: 40, color: Colors.indigo)
                    : null,
              );
            },
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
              Text(
                'รหัส: $displayId',
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FutureBuilder<IndividualSales>(
                future: _todaySalesFuture,
                builder: (context, salesSnapshot) {
                  Widget salesWidget;

                  if (salesSnapshot.connectionState ==
                      ConnectionState.waiting) {
                    salesWidget = const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    );
                  } else if (salesSnapshot.hasError) {
                    salesWidget = const Icon(Icons.error_outline,
                        color: Colors.yellow, size: 24);
                  } else if (salesSnapshot.hasData) {
                    salesWidget = Text(
                      '฿ ${currencyFormat.format(salesSnapshot.data!.price)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    );
                  } else {
                    salesWidget = const Text('N/A');
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'ยอดขายวันนี้',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      salesWidget,
                    ],
                  );
                },
              ),
              const SizedBox(height: 4),
              StreamBuilder<int>(
                stream: _todayCallsStream,
                initialData: 0,
                builder: (context, callSnapshot) {
                  final callCount = callSnapshot.data ?? 0;
                  return Text(
                    'จำนวนที่โทร $callCount สาย',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
