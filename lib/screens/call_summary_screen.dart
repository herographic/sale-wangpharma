// lib/screens/call_summary_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:salewang/models/call_log.dart';
import 'package:collection/collection.dart';
import 'package:salewang/models/customer.dart';
import 'package:salewang/models/new_arrival.dart';
import 'package:salewang/models/product.dart';
import 'package:salewang/models/sales_order.dart';
import 'package:salewang/screens/performance_proportion_view.dart';
import 'package:salewang/utils/date_helper.dart';
import 'package:salewang/utils/launcher_helper.dart';

// --- NEW: Enum for the main display filter ---
enum SummaryDisplayMode { proportion, allCalls, myCalls }

// Enum for filtering data (remains the same)
enum CallLogFilter { all, mine }

// Model for salesperson status
class SalespersonStatus {
  final String id;
  final String name;
  final String code;
  final int callCount;
  final DateTime? lastCallTime;
  final String? lastCallCustomerId;
  final String? lastCallCustomerName;
  bool isActivelyCalling;

  SalespersonStatus({
    required this.id,
    required this.name,
    required this.code,
    required this.callCount,
    this.lastCallTime,
    this.lastCallCustomerId,
    this.lastCallCustomerName,
    this.isActivelyCalling = false,
  });
}

class CallSummaryScreen extends StatefulWidget {
  const CallSummaryScreen({super.key});

  @override
  State<CallSummaryScreen> createState() => _CallSummaryScreenState();
}

class _CallSummaryScreenState extends State<CallSummaryScreen>
    with SingleTickerProviderStateMixin {
  // --- MODIFIED: TabController for call history tabs only ---
  late TabController _tabController;
  
  // --- NEW: State for the main segmented button ---
  SummaryDisplayMode _displayMode = SummaryDisplayMode.allCalls;
  
  // This filter is now controlled by the main segmented button
  CallLogFilter _filter = CallLogFilter.all;
  
  DateTime _selectedHistoryDate = DateTime.now();
  final String _currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

  StreamSubscription? _callLogSubscription;
  Timer? _statusTimer;
  Map<String, SalespersonStatus> _salespersonStatusMap = {};

  Set<String> _customersWithMatchingSO = {};

  @override
  void initState() {
    super.initState();
    // --- MODIFIED: TabController now has 2 tabs ---
    _tabController = TabController(length: 2, vsync: this);
    _setupLiveStatusStream();
    _statusTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _updateCallingStatus();
    });
    _loadMatchingSoData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _callLogSubscription?.cancel();
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadMatchingSoData() async {
    if (!mounted) return;

    try {
      final String formattedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
      const String bearerToken = 'eyJ0eXAiOiJKV1QiLCJhbGciOiUzI1NiJ9.eyJtZW1fY29kZSI6Ii4wNjM1In0.5U_Yle8l5bZqOVTxqlvQo36XyQaW2bf3Q-h91bw3UL8';
      final url = Uri.parse('https://www.wangpharma.com/API/appV3/recive_list.php?start=$formattedDate&end=$formattedDate&limit=500&offset=0');
      
      final response = await http.get(url, headers: {'Authorization': 'Bearer $bearerToken'});
      
      Set<String> arrivalProductCodes = {};
      if (response.statusCode == 200) {
        final arrivals = newArrivalFromJson(response.body);
        arrivalProductCodes = arrivals.map((a) => a.poiPcode).toSet();
      }

      if (arrivalProductCodes.isEmpty) {
        if (mounted) {
          return;
        }
      }

      final soSnapshot = await FirebaseFirestore.instance.collection('sales_orders').get();
      final allPendingOrders = soSnapshot.docs.map((doc) => SalesOrder.fromFirestore(doc)).toList();

      final matchingCustomerIds = <String>{};
      for (final order in allPendingOrders) {
        if (arrivalProductCodes.contains(order.productId)) {
          matchingCustomerIds.add(order.customerId);
        }
      }

      if (mounted) {
        setState(() {
          _customersWithMatchingSO = matchingCustomerIds;
        });
      }
    } catch (e) {
      debugPrint("Error loading matching SO data: $e");
    } finally {
      if (mounted) {
      }
    }
  }

  void _setupLiveStatusStream() {
    final now = DateTime.now();
    final startOfToday = Timestamp.fromDate(DateTime(now.year, now.month, now.day));

    final query = FirebaseFirestore.instance
        .collection('call_logs')
        .where('callTimestamp', isGreaterThanOrEqualTo: startOfToday)
        .orderBy('callTimestamp', descending: true);

    _callLogSubscription = query.snapshots().listen((snapshot) {
      final logs = snapshot.docs.map((doc) => CallLog.fromFirestore(doc)).toList();
      _processCallLogsForStatus(logs);
    });
  }

  void _processCallLogsForStatus(List<CallLog> logs) {
    final groupedLogs = groupBy(logs, (CallLog log) => log.salespersonId);
    final newStatusMap = <String, SalespersonStatus>{};

    groupedLogs.forEach((salespersonId, userLogs) {
      final firstLog = userLogs.first; 
      
      String name = firstLog.salespersonName;
      String code = salespersonId.substring(0, 6);

      if (name.contains('@')) {
        code = name.split('@').first;
        final logWithDisplayName = userLogs.firstWhereOrNull((l) => !l.salespersonName.contains('@') && l.salespersonName.isNotEmpty);
        name = logWithDisplayName?.salespersonName ?? code;
      }

      newStatusMap[salespersonId] = SalespersonStatus(
        id: salespersonId,
        name: name,
        code: code,
        callCount: userLogs.length,
        lastCallTime: firstLog.callTimestamp.toDate(),
        lastCallCustomerId: firstLog.customerId,
        lastCallCustomerName: firstLog.customerName,
      );
    });

    if (mounted) {
      setState(() {
        _salespersonStatusMap = newStatusMap;
      });
      _updateCallingStatus();
    }
  }

  void _updateCallingStatus() {
    if (!mounted) return;
    final now = DateTime.now();
    bool changed = false;

    _salespersonStatusMap.forEach((id, status) {
      final bool wasActive = status.isActivelyCalling;
      if (status.lastCallTime != null) {
        final difference = now.difference(status.lastCallTime!);
        status.isActivelyCalling = difference.inMinutes < 7;
      } else {
        status.isActivelyCalling = false;
      }
      if (wasActive != status.isActivelyCalling) {
        changed = true;
      }
    });

    if (changed) {
      setState(() {});
    }
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
          title: const Text('DashBoard SellForce', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
        body: Column(
          children: [
            // --- NEW: Main filter control at the top ---
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
              child: SegmentedButton<SummaryDisplayMode>(
                segments: const <ButtonSegment<SummaryDisplayMode>>[
                  ButtonSegment<SummaryDisplayMode>(value: SummaryDisplayMode.proportion, label: Text('อัตราส่วน'), icon: Icon(Icons.pie_chart_outline)),
                  ButtonSegment<SummaryDisplayMode>(value: SummaryDisplayMode.allCalls, label: Text('ภาพรวม'), icon: Icon(Icons.people_outline)),
                  ButtonSegment<SummaryDisplayMode>(value: SummaryDisplayMode.myCalls, label: Text('เฉพาะฉัน'), icon: Icon(Icons.person_outline)),
                ],
                selected: <SummaryDisplayMode>{_displayMode},
                onSelectionChanged: (Set<SummaryDisplayMode> newSelection) {
                  setState(() {
                    _displayMode = newSelection.first;
                    // Update the underlying filter based on the main selection
                    if (_displayMode == SummaryDisplayMode.myCalls) {
                       _filter = CallLogFilter.mine;
                    } else {
                       _filter = CallLogFilter.all;
                    }
                  });
                },
                style: SegmentedButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.2),
                  foregroundColor: Colors.white,
                  selectedForegroundColor: Theme.of(context).primaryColor,
                  selectedBackgroundColor: Colors.white,
                ),
              ),
            ),
            // --- NEW: Conditionally display content based on the filter ---
            Expanded(
              child: _buildContentForDisplayMode(),
            ),
          ],
        ),
      ),
    );
  }

  // --- NEW: This widget decides what to show based on the main filter ---
  Widget _buildContentForDisplayMode() {
    switch (_displayMode) {
      case SummaryDisplayMode.proportion:
        // If 'สัดส่วน' is selected, show only the performance view.
        return PerformanceProportionView(
          // Pass the correct filter to the view
          salespersonFilter: _filter == CallLogFilter.mine 
              ? _salespersonStatusMap[_currentUserId]?.name // <-- FIXED HERE
              : null,
        );
      case SummaryDisplayMode.allCalls:
      case SummaryDisplayMode.myCalls:
        // If 'ภาพรวม' or 'เฉพาะฉัน' is selected, show the summary and call list tabs.
        return Column(
          children: [
            _buildSalespersonSummary(),
            _buildCallListTabs(),
          ],
        );
    }
  }

  Widget _buildSalespersonSummary() {
    List<SalespersonStatus> summaries = _salespersonStatusMap.values.toList();
    
    if (_filter == CallLogFilter.mine) {
      summaries = summaries.where((s) => s.id == _currentUserId).toList();
    }

    if (summaries.isEmpty) {
      return const SizedBox.shrink();
    }

    summaries.sort((a, b) => b.callCount.compareTo(a.callCount));
    final totalCalls = summaries.fold<int>(0, (sum, s) => sum + s.callCount);
    const double dailyTarget = 100.0;

    return Container(
      padding: const EdgeInsets.all(16.0),
      margin: const EdgeInsets.fromLTRB(8.0, 0, 8.0, 8.0),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'สรุปการโทรวันนี้',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  _buildLegendItem(Colors.red, 'ยังไม่โทร'),
                  _buildLegendItem(Colors.blue, 'เฉลี่ย'),
                  _buildLegendItem(Colors.green, 'เป้าหมาย'),
                ],
              )
            ],
          ),
          const SizedBox(height: 16),
          ListView.builder(
            itemCount: (summaries.length / 2).ceil(),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemBuilder: (context, rowIndex) {
              final int firstIndex = rowIndex * 2;
              final int secondIndex = firstIndex + 1;

              final summary1 = summaries[firstIndex];
              final teamPercentage1 = totalCalls > 0 ? (summary1.callCount / totalCalls) * 100 : 0.0;
              final targetPercentage1 = (summary1.callCount / dailyTarget) * 100;
              
              SalespersonStatus? summary2;
              double? teamPercentage2, targetPercentage2;
              if (secondIndex < summaries.length) {
                summary2 = summaries[secondIndex];
                teamPercentage2 = totalCalls > 0 ? (summary2.callCount / totalCalls) * 100 : 0.0;
                targetPercentage2 = (summary2.callCount / dailyTarget) * 100;
              }

              return Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildSalespersonProgressBars(summary1, teamPercentage1, targetPercentage1),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: summary2 != null
                            ? _buildSalespersonProgressBars(summary2, teamPercentage2!, targetPercentage2!)
                            : const SizedBox(),
                      ),
                    ],
                  ),
                  if (rowIndex < (summaries.length / 2).ceil() - 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Divider(color: Colors.white.withOpacity(0.2), height: 1),
                    )
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 8.0),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildSalespersonProgressBars(SalespersonStatus summary, double teamPercentage, double targetPercentage) {
    final bool hasCalled = summary.isActivelyCalling;
    final activeGradient = LinearGradient(colors: [Colors.greenAccent.shade400, Colors.green.shade600]);
    final teamGradient = LinearGradient(colors: [Colors.lightBlue.shade300, Colors.blue.shade600]);
    final redGradient = LinearGradient(colors: [Colors.red.shade400, Colors.red.shade700]);
    final timeFormat = DateFormat('HH:mm');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                '${summary.code} ${summary.name}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${summary.callCount} สาย',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _buildSingleProgressBar(
          percentage: teamPercentage,
          label: 'เฉลี่ยการโทร',
          gradient: hasCalled ? teamGradient : redGradient,
        ),
        const SizedBox(height: 4),
        _buildSingleProgressBar(
          percentage: targetPercentage,
          label: 'เป้าหมาย',
          gradient: hasCalled ? activeGradient : redGradient,
        ),
        if (summary.lastCallTime != null)
          Padding(
            padding: const EdgeInsets.only(top: 6.0),
            child: Row(
              children: [
                Icon(Icons.history_toggle_off, color: Colors.white70, size: 12),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${summary.lastCallCustomerId} | ${summary.lastCallCustomerName}',
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${timeFormat.format(summary.lastCallTime!)} น.',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildSingleProgressBar({required double percentage, required String label, required Gradient gradient}) {
    return SizedBox(
      height: 20,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          FractionallySizedBox(
            widthFactor: (percentage / 100).clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 2, color: Colors.black54)]),
                ),
                Text(
                  '${percentage.toStringAsFixed(0)}%',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 2, color: Colors.black54)]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  // --- MODIFIED: This widget now only contains the two call list tabs ---
  Widget _buildCallListTabs() {
    return Expanded(
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white.withOpacity(0.7),
            indicatorColor: Colors.white,
            tabs: const [
              Tab(text: 'วันปัจจุบัน'),
              Tab(text: 'ย้อนหลัง'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildCallListForDate(DateTime.now()),
                _buildHistoryView(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallListForDate(DateTime date) {
    final startOfDay = Timestamp.fromDate(DateTime(date.year, date.month, date.day));
    final endOfDay = Timestamp.fromDate(DateTime(date.year, date.month, date.day, 23, 59, 59));

    Query query = FirebaseFirestore.instance
        .collection('call_logs')
        .where('callTimestamp', isGreaterThanOrEqualTo: startOfDay)
        .where('callTimestamp', isLessThanOrEqualTo: endOfDay)
        .orderBy('callTimestamp', descending: true);
    
    // The filter is applied here based on the main segmented button's state
    if (_filter == CallLogFilter.mine) {
      query = query.where('salespersonId', isEqualTo: _currentUserId);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }
        if (snapshot.hasError) {
          return Center(child: Text('เกิดข้อผิดพลาด: ${snapshot.error}', style: const TextStyle(color: Colors.white)));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Text('ไม่มีการโทรในวันที่ ${DateFormat.yMMMd('th').format(date)}', style: const TextStyle(color: Colors.white70, fontSize: 16)),
          );
        }

        final callLogs = snapshot.data!.docs.map((doc) => CallLog.fromFirestore(doc)).toList();

        return ListView.builder(
          padding: const EdgeInsets.all(8.0),
          itemCount: callLogs.length,
          itemBuilder: (context, index) {
            return _buildCallLogRow(callLogs[index]);
          },
        );
      },
    );
  }

  Widget _buildHistoryView() {
    return Column(
      children: [
        _buildDateSelector(),
        Expanded(child: _buildCallListForDate(_selectedHistoryDate)),
      ],
    );
  }

  Widget _buildDateSelector() {
    return FutureBuilder<Map<DateTime, int>>(
      future: _getRecentCallHistoryCounts(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(height: 60, child: Center(child: CircularProgressIndicator(color: Colors.white)));
        }
        final dateCounts = snapshot.data!;
        final sortedDates = dateCounts.keys.toList()..sort((a,b) => b.compareTo(a));

        return Container(
          height: 60,
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: sortedDates.length,
            itemBuilder: (context, index) {
              final date = sortedDates[index];
              final count = dateCounts[date]!;
              final isSelected = DateUtils.isSameDay(date, _selectedHistoryDate);

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: ChoiceChip(
                  label: Text('${DateFormat.MMMd('th').format(date)} ($count สาย)'),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _selectedHistoryDate = date;
                      });
                    }
                  },
                  backgroundColor: Colors.black.withOpacity(0.1),
                  selectedColor: Colors.white,
                  labelStyle: TextStyle(color: isSelected ? Colors.indigo : Colors.white),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<Map<DateTime, int>> _getRecentCallHistoryCounts() async {
    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(const Duration(days: 7));
    final startOfPeriod = Timestamp.fromDate(DateTime(sevenDaysAgo.year, sevenDaysAgo.month, sevenDaysAgo.day));

    Query query = FirebaseFirestore.instance
        .collection('call_logs')
        .where('callTimestamp', isGreaterThanOrEqualTo: startOfPeriod);
        
    if (_filter == CallLogFilter.mine) {
      query = query.where('salespersonId', isEqualTo: _currentUserId);
    }

    final snapshot = await query.get();

    final Map<DateTime, int> dateCounts = {};
    for (var doc in snapshot.docs) {
      final log = CallLog.fromFirestore(doc);
      final date = log.callTimestamp.toDate();
      final dayOnly = DateTime(date.year, date.month, date.day);
      dateCounts[dayOnly] = (dateCounts[dayOnly] ?? 0) + 1;
    }
    return dateCounts;
  }

  Widget _buildCallLogRow(CallLog log) {
    final timeFormat = DateFormat('HH:mm');
    final bool hasMatchingSO = _customersWithMatchingSO.contains(log.customerId);
    
    final goldGradient = LinearGradient(
      colors: [Colors.amber.shade200, Colors.amber.shade500],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: hasMatchingSO ? null : Colors.white.withOpacity(0.95),
          gradient: hasMatchingSO ? goldGradient : null,
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  '(${log.customerId}) ${log.customerName}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: hasMatchingSO ? Colors.brown.shade800 : Colors.indigo,
                    fontSize: 16,
                  ),
                ),
              ),
              // Call Button
              IconButton(
                icon: Icon(Icons.phone_forwarded_outlined, color: Colors.green.shade700, size: 20),
                tooltip: 'โทรซ้ำ',
                onPressed: () {
                  final tempCustomer = Customer(
                    id: log.customerId, customerId: log.customerId, name: log.customerName,
                    contacts: [{'name': 'เบอร์หลัก', 'phone': log.phoneNumber}],
                    address1: '', address2: '', phone: '', contactPerson: '', email: '',
                    customerType: '', taxId: '', branch: '', paymentTerms: '', creditLimit: '',
                    salesperson: '', p: '', b1: '', b2: '', b3: '', startDate: '',
                    lastSaleDate: '', lastPaymentDate: '',
                  );
                  LauncherHelper.makeAndLogPhoneCall(
                    context: context, phoneNumber: log.phoneNumber, customer: tempCustomer,
                  );
                },
              ),
              Text(
                '${timeFormat.format(log.callTimestamp.toDate())} น.',
                style: TextStyle(
                  color: hasMatchingSO ? Colors.brown.shade900 : Colors.green,
                  fontSize: 16, 
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          subtitle: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: DefaultTextStyle.of(context).style.copyWith(
                      fontSize: 14, 
                      color: hasMatchingSO ? Colors.brown.shade700 : Colors.grey.shade700
                    ),
                    children: <TextSpan>[
                      const TextSpan(text: 'โดย: '),
                      TextSpan(
                        text: log.salespersonName.split(' ').first,
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                      ),
                      TextSpan(text: ' • เบอร์: ${log.phoneNumber}'),
                    ],
                  ),
                ),
              ),
              // View SO Button
              InkWell(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) => _PendingOrdersDialog(customerId: log.customerId),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Icon(Icons.receipt_long_outlined, color: hasMatchingSO ? Colors.brown.shade900 : Colors.grey, size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Helper class to combine SalesOrder with Product data
class EnrichedSalesOrder {
  final SalesOrder order;
  final Product? product;

  EnrichedSalesOrder({required this.order, this.product});
}

// --- UPDATED: Dialog to show pending Sales Orders for a customer ---
class _PendingOrdersDialog extends StatefulWidget {
  final String customerId;

  const _PendingOrdersDialog({required this.customerId});

  @override
  State<_PendingOrdersDialog> createState() => _PendingOrdersDialogState();
}

class _PendingOrdersDialogState extends State<_PendingOrdersDialog> {
  late Future<Map<String, List<EnrichedSalesOrder>>> _groupedOrdersFuture;
  final List<String> _forbiddenKeywords = const ['รีเบท', 'ฟรี', 'ส่งเสริมการขาย', '-', '@'];

  @override
  void initState() {
    super.initState();
    _groupedOrdersFuture = _fetchAndGroupPendingOrders();
  }

  Future<Map<String, List<EnrichedSalesOrder>>> _fetchAndGroupPendingOrders() async {
    // 1. Fetch all pending orders for the customer, filtering out free items
    final soSnapshot = await FirebaseFirestore.instance
        .collection('sales_orders')
        .where('รหัสลูกหนี้', isEqualTo: widget.customerId)
        .where('จำนวนเงิน', isGreaterThan: 0) // Filter items with a price
        .get();

    List<SalesOrder> orders = soSnapshot.docs
        .map((doc) => SalesOrder.fromFirestore(doc))
        .where((order) => !_forbiddenKeywords.any((keyword) => order.productDescription.startsWith(keyword)))
        .toList();

    if (orders.isEmpty) return {};

    // 2. Get unique product IDs and fetch their data
    final productIds = orders.map((o) => o.productId.replaceAll('/', '-')).toSet().toList();
    final Map<String, Product> productsMap = {};
    if (productIds.isNotEmpty) {
       for (var i = 0; i < productIds.length; i += 30) {
        final chunk = productIds.sublist(i, i + 30 > productIds.length ? productIds.length : i + 30);
         if (chunk.isNotEmpty) {
            final productSnapshot = await FirebaseFirestore.instance.collection('products').where(FieldPath.documentId, whereIn: chunk).get();
            for (final doc in productSnapshot.docs) {
              productsMap[doc.id] = Product.fromFirestore(doc);
            }
         }
       }
    }

    // 3. Fetch new arrivals data for the last 30 days
    final thirtyDaysAgo = DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 30)));
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    const String bearerToken = 'eyJ0eXAiOiJKV1QiLCJhbGciOiUzI1NiJ9.eyJtZW1fY29kZSI6Ii4wNjM1In0.5U_Yle8l5bZqOVTxqlvQo36XyQaW2bf3Q-h91bw3UL8';
    final url = Uri.parse('https://www.wangpharma.com/API/appV3/recive_list.php?start=$thirtyDaysAgo&end=$today&limit=1000&offset=0');
    final response = await http.get(url, headers: {'Authorization': 'Bearer $bearerToken'});
    
    final Map<String, String> productArrivalDateMap = {};
    if (response.statusCode == 200) {
      final arrivals = newArrivalFromJson(response.body);
      for (var arrival in arrivals) {
        // Store the latest arrival date for each product
        if (!productArrivalDateMap.containsKey(arrival.poiPcode)) {
          productArrivalDateMap[arrival.poiPcode] = arrival.poiDate;
        }
      }
    }

    // 4. Create enriched orders and group them by arrival date
    final Map<String, List<EnrichedSalesOrder>> groupedOrders = {};
    for (final order in orders) {
      final product = productsMap[order.productId.replaceAll('/', '-')];
      final arrivalDate = productArrivalDateMap[order.productId] ?? 'ยังไม่เข้า';
      
      if (groupedOrders[arrivalDate] == null) {
        groupedOrders[arrivalDate] = [];
      }
      groupedOrders[arrivalDate]!.add(EnrichedSalesOrder(order: order, product: product));
    }

    // 5. Sort items within each group by product ID
    groupedOrders.forEach((date, orders) {
      orders.sort((a, b) => a.order.productId.compareTo(b.order.productId));
    });

    return groupedOrders;
  }


  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('รายการค้างส่ง'),
      content: SizedBox(
        width: double.maxFinite,
        child: FutureBuilder<Map<String, List<EnrichedSalesOrder>>>(
          future: _groupedOrdersFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(child: Text('ไม่พบรายการค้างส่ง'));
            }

            final groupedOrders = snapshot.data!;
            
            // Sort date keys: today first, then descending, "ยังไม่เข้า" last
            final sortedKeys = groupedOrders.keys.toList()..sort((a, b) {
              if (a == 'ยังไม่เข้า') return 1;
              if (b == 'ยังไม่เข้า') return -1;
              final dateA = DateTime.tryParse(a);
              final dateB = DateTime.tryParse(b);
              if (dateA == null || dateB == null) return 0;
              return dateB.compareTo(dateA);
            });

            return ListView.builder(
              shrinkWrap: true,
              itemCount: sortedKeys.length,
              itemBuilder: (context, index) {
                final dateKey = sortedKeys[index];
                final orders = groupedOrders[dateKey]!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
                      child: Text(
                        'วันที่สินค้าเข้า: ${DateHelper.formatDateToThai(dateKey)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo),
                      ),
                    ),
                    ...orders.map((enrichedOrder) => _buildOrderItemCard(enrichedOrder)),
                  ],
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('ปิด')),
      ],
    );
  }

  // --- NEW: Order Item Card with new layout ---
  Widget _buildOrderItemCard(EnrichedSalesOrder enrichedOrder) {
    final order = enrichedOrder.order;
    final product = enrichedOrder.product;
    final currencyFormat = NumberFormat("#,##0.00", "en_US");

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Line 1: Product ID & Stock
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('รหัส: ${order.productId}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                Text(
                  'สต็อก: ${product?.stockQuantity.toStringAsFixed(0) ?? '?'}',
                  style: TextStyle(
                    fontSize: 12,
                    color: (product?.stockQuantity ?? 0) > 0 ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Line 2: Product Name
            Text(order.productDescription, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            // Line 3: Quantity & Total Amount
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('สั่ง: ${order.quantity.toStringAsFixed(0)} ${order.unit}'),
                Text(
                  '฿${currencyFormat.format(order.totalAmount)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
