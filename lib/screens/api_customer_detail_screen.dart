// lib/screens/api_customer_detail_screen.dart

import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http; // REMOVED
import 'package:cloud_firestore/cloud_firestore.dart'; // ADDED
import 'package:intl/intl.dart';
import 'package:salewang/models/sale_support_customer.dart';
import 'package:salewang/widgets/info_card.dart';

class CustomerSalesSummary {
  final double currentMonthSales;
  final double previousMonthSales;
  final SaleSupportCustomer customer;

  CustomerSalesSummary({
    required this.currentMonthSales,
    required this.previousMonthSales,
    required this.customer,
  });
}

class ApiCustomerDetailScreen extends StatefulWidget {
  final String customerCode;
  final String customerName;

  const ApiCustomerDetailScreen({
    super.key,
    required this.customerCode,
    required this.customerName,
  });

  @override
  State<ApiCustomerDetailScreen> createState() => _ApiCustomerDetailScreenState();
}

class _ApiCustomerDetailScreenState extends State<ApiCustomerDetailScreen> {
  late Future<CustomerSalesSummary> _customerDataFuture;

  @override
  void initState() {
    super.initState();
    _customerDataFuture = _fetchAndCalculateSales();
  }

  // --- MODIFIED: Fetches data from Firestore cache ---
  Future<CustomerSalesSummary> _fetchAndCalculateSales() async {
    final sanitizedId = widget.customerCode.replaceAll('/', '-');
    final doc = await FirebaseFirestore.instance
        .collection('api_sale_support_cache')
        .doc(sanitizedId)
        .get();

    if (doc.exists) {
      final customer = SaleSupportCustomer.fromFirestore(doc);
      final now = DateTime.now();
      final previousMonthDate = DateTime(now.year, now.month - 1, 1);
      
      double currentMonthSales = 0.0;
      double previousMonthSales = 0.0;

      for (var order in customer.order) {
        final orderDate = DateTime.tryParse(order.date ?? '');
        if (orderDate != null) {
          double price = double.tryParse(order.price?.replaceAll(',', '') ?? '0') ?? 0.0;
          if (orderDate.year == now.year && orderDate.month == now.month) {
            currentMonthSales += price;
          }
          if (orderDate.year == previousMonthDate.year && orderDate.month == previousMonthDate.month) {
            previousMonthSales += price;
          }
        }
      }
      
      return CustomerSalesSummary(
        customer: customer,
        currentMonthSales: currentMonthSales,
        previousMonthSales: previousMonthSales,
      );
    } else {
      throw Exception('ไม่พบข้อมูลลูกค้าใน Cache');
    }
  }

  @override
  Widget build(BuildContext context) {
    // The build method remains unchanged
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
          title: Text(widget.customerName, style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
        body: FutureBuilder<CustomerSalesSummary>(
          future: _customerDataFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: Colors.white));
            }
            if (snapshot.hasError) {
              return Center(child: Text('เกิดข้อผิดพลาด: ${snapshot.error}', style: const TextStyle(color: Colors.white)));
            }
            if (!snapshot.hasData) {
              return const Center(child: Text('ไม่พบข้อมูล', style: TextStyle(color: Colors.white)));
            }

            final summary = snapshot.data!;
            final customer = summary.customer;
            final currencyFormat = NumberFormat("#,##0.00", "en_US");

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  InfoCard(
                    title: 'สรุปยอดขาย (ไม่รวม VAT)',
                    details: {
                      'ยอดเดือนปัจจุบัน:': '฿${currencyFormat.format(summary.currentMonthSales)}',
                      'ยอดเดือนก่อน:': '฿${currencyFormat.format(summary.previousMonthSales)}',
                    },
                  ),
                  const SizedBox(height: 16),
                  InfoCard(
                    title: 'ข้อมูลหลัก',
                    details: {
                      'รหัสลูกค้า': customer.memCode ?? '-',
                      'ระดับราคา': customer.memPrice ?? '-',
                      'พนักงานขาย': customer.memSale ?? '-',
                      'ที่อยู่': customer.memAddress ?? '-',
                      'เบอร์โทร': customer.memPhone ?? '-',
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
