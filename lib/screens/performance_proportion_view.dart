// lib/screens/performance_proportion_view.dart

import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:salewang/models/bill_history.dart';
import 'package:salewang/models/customer.dart';
import 'package:salewang/models/saleperson_performance.dart';
import 'package:salewang/screens/pending_so_report_screen.dart';

class PerformanceProportionView extends StatefulWidget {
  final String? salespersonFilter;

  const PerformanceProportionView({super.key, this.salespersonFilter});

  @override
  State<PerformanceProportionView> createState() =>
      _PerformanceProportionViewState();
}

class _PerformanceProportionViewState extends State<PerformanceProportionView> {
  late Future<List<SalespersonPerformance>> _performanceFuture;
  Timer? _refreshTimer;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _performanceFuture = _fetchPerformanceData(_selectedDate);
    // Refresh data every 5 minutes to update the "actively calling" status
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      _refreshData();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel(); // Cancel the timer when the widget is disposed
    super.dispose();
  }

  void _refreshData() {
    if (mounted) {
      setState(() {
        _performanceFuture = _fetchPerformanceData(_selectedDate);
      });
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2022), // Or any other reasonable start date
      lastDate: DateTime.now(), // Cannot select future dates
      locale: const Locale('th', 'TH'),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _performanceFuture = _fetchPerformanceData(_selectedDate);
      });
    }
  }

  Future<List<SalespersonPerformance>> _fetchPerformanceData(
      DateTime selectedDate) async {
    final firestore = FirebaseFirestore.instance;

    // 1. Fetch salesperson data to create the base map
    final salespeopleSnapshot = await firestore.collection('salespeople').get();
    if (salespeopleSnapshot.docs.isEmpty) return [];

    final Map<String, SalespersonPerformance> performanceMap = {};
    final Map<String, String> uidToEmployeeIdMap = {};
    for (var doc in salespeopleSnapshot.docs) {
      final data = doc.data();
      final employeeId = data['employeeId'] as String?;
      final displayName = data['displayName'] as String?;
      final uid = doc.id;
      if (employeeId != null && displayName != null) {
        performanceMap[employeeId] = SalespersonPerformance(
            salespersonName: displayName, employeeCode: employeeId);
        uidToEmployeeIdMap[uid] = employeeId;
      }
    }

    // 2. Aggregate customer counts and pending SOs
    final customersSnapshot = await firestore.collection('customers').get();
    final Map<String, List<Customer>> salespersonCustomersMap = {};
    for (var doc in customersSnapshot.docs) {
      final customer = Customer.fromFirestore(doc);
      final salespersonId = customer.salesperson;
      if (performanceMap.containsKey(salespersonId)) {
        performanceMap[salespersonId]!.totalCustomers++;
        salespersonCustomersMap
            .putIfAbsent(salespersonId, () => [])
            .add(customer);
      }
    }

    final allOrdersSnapshot = await firestore.collection('sales_orders').get();
    final pendingOrdersCustomerIds =
        allOrdersSnapshot.docs.map((doc) => doc.data()['รหัสลูกหนี้'] as String).toSet();

    salespersonCustomersMap.forEach((salespersonId, customers) {
      int pendingCount = 0;
      for (var customer in customers) {
        if (pendingOrdersCustomerIds.contains(customer.customerId)) {
          pendingCount++;
        }
      }
      if (performanceMap.containsKey(salespersonId)) {
        performanceMap[salespersonId]!.customersWithPendingSO = pendingCount;
      }
    });

    // 3. Process call logs for the selected date
    final startOfDay = Timestamp.fromDate(
        DateTime(selectedDate.year, selectedDate.month, selectedDate.day));
    final endOfDay = Timestamp.fromDate(DateTime(
        selectedDate.year, selectedDate.month, selectedDate.day, 23, 59, 59));

    final callsTodaySnapshot = await firestore
        .collection('call_logs')
        .where('callTimestamp', isGreaterThanOrEqualTo: startOfDay)
        .where('callTimestamp', isLessThanOrEqualTo: endOfDay)
        .get();

    final Map<String, List<DateTime>> salespersonCallTimestamps = {};
    final Map<String, Set<String>> salespersonUniqueCustomers = {};

    for (var doc in callsTodaySnapshot.docs) {
      final callSalespersonUid = doc.data()['salespersonId'] as String?;
      final customerId = doc.data()['customerId'] as String?;
      final timestamp = (doc.data()['callTimestamp'] as Timestamp?)?.toDate();

      if (callSalespersonUid != null && customerId != null && timestamp != null) {
        final employeeId = uidToEmployeeIdMap[callSalespersonUid];
        if (employeeId != null) {
          salespersonCallTimestamps
              .putIfAbsent(employeeId, () => [])
              .add(timestamp);
          salespersonUniqueCustomers
              .putIfAbsent(employeeId, () => {})
              .add(customerId);
        }
      }
    }

    final now = DateTime.now();
    final isToday = DateUtils.isSameDay(selectedDate, now);

    salespersonCallTimestamps.forEach((employeeId, timestamps) {
      if (performanceMap.containsKey(employeeId)) {
        timestamps.sort((a, b) => b.compareTo(a)); // Sort descending
        final lastCall = timestamps.first;
        final difference = now.difference(lastCall);

        performanceMap[employeeId]!.totalCallsToday = timestamps.length;
        performanceMap[employeeId]!.lastCallTime = lastCall;
        performanceMap[employeeId]!.isActivelyCalling =
            isToday && difference.inMinutes < 7;
        performanceMap[employeeId]!.uniqueCustomersCalledToday =
            salespersonUniqueCustomers[employeeId]?.length ?? 0;
      }
    });

    // 4. Calculate sales from bill_history for the selected date
    final selectedDatePrefix = DateFormat('yyyy-MM-dd').format(selectedDate);
    final salesTodaySnapshot = await firestore
        .collection('bill_history')
        .where('วันที่', isGreaterThanOrEqualTo: selectedDatePrefix)
        .where('วันที่', isLessThan: '$selectedDatePrefix\uf8ff')
        .get();

    final Map<String, double> salespersonSales = {};
    for (var doc in salesTodaySnapshot.docs) {
      final bill = BillHistory.fromFirestore(doc);
      if (bill.salesperson.isNotEmpty) {
        final salespersonCode = bill.salesperson.split('/').first;
        final totalBillAmount =
            bill.items.fold<double>(0.0, (sum, item) => sum + item.netAmount);
        salespersonSales[salespersonCode] =
            (salespersonSales[salespersonCode] ?? 0.0) + totalBillAmount;
      }
    }

    salespersonSales.forEach((salespersonCode, totalSales) {
      if (performanceMap.containsKey(salespersonCode)) {
        performanceMap[salespersonCode]!.todaySales = totalSales;
      }
    });

    // 5. Final processing and sorting
    final performanceList = performanceMap.values.toList();
    if (widget.salespersonFilter != null &&
        widget.salespersonFilter!.isNotEmpty) {
      performanceList
          .retainWhere((p) => p.salespersonName == widget.salespersonFilter);
    }

    performanceList.sort(
        (a, b) => b.customersWithPendingSO.compareTo(a.customersWithPendingSO));

    return performanceList;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: ElevatedButton.icon(
            icon: const Icon(Icons.calendar_today),
            label: Text(
                'วันที่: ${DateFormat('d MMMM yyyy', 'th_TH').format(_selectedDate)}'),
            onPressed: () => _selectDate(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Theme.of(context).primaryColor,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<SalespersonPerformance>>(
            future: _performanceFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: Colors.white));
              }
              if (snapshot.hasError) {
                return Center(
                    child: Text('เกิดข้อผิดพลาด: ${snapshot.error}',
                        style: const TextStyle(color: Colors.white)));
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(
                    child: Text('ไม่พบข้อมูลพนักงานขาย',
                        style: TextStyle(color: Colors.white)));
              }

              final performanceData = snapshot.data!;

              return LayoutBuilder(
                builder: (context, constraints) {
                  int crossAxisCount;
                  double childAspectRatio;

                  if (constraints.maxWidth > 1200) {
                    crossAxisCount = 3;
                    childAspectRatio = 2.9;
                  } else if (constraints.maxWidth > 700) {
                    crossAxisCount = 2;
                    childAspectRatio = 2.7;
                  } else {
                    crossAxisCount = 1;
                    childAspectRatio = 2.7; // Adjusted for mobile
                  }

                  return RefreshIndicator(
                    onRefresh: () async => _refreshData(),
                    child: GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        childAspectRatio: childAspectRatio,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: performanceData.length,
                      itemBuilder: (context, index) {
                        return _SalespersonPerformanceCard(
                          performance: performanceData[index],
                          onNavigateBack: _refreshData,
                        );
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SalespersonPerformanceCard extends StatelessWidget {
  final SalespersonPerformance performance;
  final VoidCallback onNavigateBack;

  const _SalespersonPerformanceCard({
    required this.performance,
    required this.onNavigateBack,
  });

  @override
  Widget build(BuildContext context) {
    final employeeCode = performance.employeeCode ?? 'N/A';
    final displayName = performance.salespersonName;
    final currencyFormat = NumberFormat("#,##0.00", "en_US");

    // Determine card color based on call activity
    final cardColor = performance.isActivelyCalling
        ? Colors.green.shade50
        : Colors.red.shade50;

    return Card(
      color: cardColor,
      margin: EdgeInsets.zero,
      elevation: 2,
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircleAvatar(
                          radius: 24,
                          backgroundColor: Color(0xFFEEEEEE),
                          child:
                              Icon(Icons.person, size: 28, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          displayName,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          employeeCode,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 7,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        GestureDetector(
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PendingSoReportScreen(
                                  salespersonCode: employeeCode,
                                  salespersonName: displayName,
                                ),
                              ),
                            );
                            onNavigateBack();
                          },
                          child: _ProportionCircle(
                            value: performance.customersWithPendingSO,
                            total: performance.totalCustomers,
                            label: 'SO ค้าง',
                            progressColor: Colors.red.shade600,
                            backgroundColor: Colors.green.shade300,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _ProportionCircle(
                          value: performance.uniqueCustomersCalledToday,
                          total: performance.totalCustomers,
                          label: 'โทรวันนี้',
                          progressColor: Colors.green.shade600,
                          backgroundColor: Colors.red.shade300,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, thickness: 1),
          Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 4.0, horizontal: 12.0),
            child: FittedBox( // Use FittedBox to prevent text overflow
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'จำนวน: ${performance.totalCallsToday} สาย',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                  ),
                  const Text(
                    ' | ',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    'ยอดขาย: ',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                  ),
                  Text(
                    '฿${currencyFormat.format(performance.todaySales)}',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade900),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProportionCircle extends StatelessWidget {
  final int value;
  final int total;
  final String label;
  final Color progressColor;
  final Color backgroundColor;

  const _ProportionCircle({
    required this.value,
    required this.total,
    required this.label,
    required this.progressColor,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final double percentage = (total > 0) ? (value / total) : 0.0;
    final String bottomText = label == 'SO ค้าง'
        ? 'ค้าง: $value / $total ร้าน'
        : 'โทรแล้ว: $value / $total ร้าน';

    return AspectRatio(
      aspectRatio: 1.0,
      child: CustomPaint(
        painter: _PieChartPainter(
          percentage: percentage,
          progressColor: progressColor,
          backgroundColor: backgroundColor,
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${(percentage * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 25,
                      color: Colors.white,
                      shadows: [Shadow(blurRadius: 4, color: Colors.black)]),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(blurRadius: 5, color: Colors.black)]),
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  bottomText,
                  style: const TextStyle(
                      color: Colors.black,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(blurRadius: 5, color: Colors.white)]),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

class _PieChartPainter extends CustomPainter {
  final double percentage;
  final Color progressColor;
  final Color backgroundColor;

  _PieChartPainter({
    required this.percentage,
    required this.progressColor,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width / 2, size.height / 2);

    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, backgroundPaint);

    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.fill;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * percentage,
      true,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
