// lib/widgets/salesperson_slider.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:salewang/models/customer.dart';
import 'package:salewang/models/daily_sales_status.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SalespersonSlider extends StatefulWidget {
  const SalespersonSlider({super.key});

  @override
  State<SalespersonSlider> createState() => _SalespersonSliderState();
}

class _SalespersonSliderState extends State<SalespersonSlider> {
  Future<List<DailySalesStatus>>? _salesStatusFuture;

  final ScrollController _salesTeamScrollController = ScrollController();
  final ScrollController _dataEntryTeamScrollController = ScrollController();
  Timer? _salesScrollTimer;
  Timer? _dataEntryScrollTimer;

  List<EmployeePayload> _salesTeam = [];
  List<EmployeePayload> _dataEntryTeam = [];
  double _grandTotalSales = 0.0;

  int _salesTeamTotalShops = 0;
  int _salesTeamTotalItems = 0;
  int _dataEntryTeamTotalShops = 0;
  int _dataEntryTeamTotalItems = 0;

  // NEW: State variables for detailed stats
  Map<String, int> _salespersonTotalCustomers = {};
  final Map<String, int> _salespersonTodayCalls = {};
  final Map<String, int> _salespersonCalledCustomers = {};
  final Map<String, String> _uidToEmpCodeMap = {};

  @override
  void initState() {
    super.initState();
    _salesStatusFuture = _fetchAndProcessData();
  }

  @override
  void dispose() {
    _salesScrollTimer?.cancel();
    _dataEntryScrollTimer?.cancel();
    _salesTeamScrollController.dispose();
    _dataEntryTeamScrollController.dispose();
    super.dispose();
  }

  Future<List<DailySalesStatus>> _fetchAndProcessData() async {
    const String apiUrl = 'https://www.wangpharma.com/API/sale/day-status.php';
    const String token =
        'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJtZW1fY29kZSI6IjAzNTAifQ.9xQokBCn6ED-xwHQFXsa5Bah57dNc8vWJ_4Iin8E3m0';

    try {
      // Fetch roles, employees from API, and salesperson UIDs simultaneously
      final rolesFuture =
          FirebaseFirestore.instance.collection('employee_roles').get();
      final apiFuture = http.get(
        Uri.parse(apiUrl),
        headers: {'Authorization': 'Bearer $token'},
      );
      final salespeopleFuture =
          FirebaseFirestore.instance.collection('salespeople').get();

      final responses = await Future.wait([rolesFuture, apiFuture, salespeopleFuture]);

      final rolesSnapshot = responses[0] as QuerySnapshot<Map<String, dynamic>>;
      final response = responses[1] as http.Response;
      final salespeopleSnapshot = responses[2] as QuerySnapshot<Map<String, dynamic>>;

      // Process roles
      final rolesMap = {
        for (var doc in rolesSnapshot.docs) doc.id: doc.data()['role']
      };
      final salesTeamIds =
          rolesMap.entries.where((e) => e.value == 'sales').map((e) => e.key).toSet();
      final dataEntryTeamIds = rolesMap.entries
          .where((e) => e.value == 'data_entry')
          .map((e) => e.key)
          .toSet();
      
      // Process UID to EmpCode mapping
      for (var doc in salespeopleSnapshot.docs) {
        final data = doc.data();
        if (data.containsKey('employeeId')) {
          _uidToEmpCodeMap[doc.id] = data['employeeId'];
        }
      }

      // Process API data
      if (response.statusCode == 200) {
        final List<DailySalesStatus> salesStatusList =
            dailySalesStatusFromJson(response.body);
        if (salesStatusList.isNotEmpty) {
          final allEmployees = salesStatusList.first.payload;
          allEmployees.sort(
              (a, b) => double.parse(b.price).compareTo(double.parse(a.price)));

          final salesTeam = allEmployees
              .where((emp) => salesTeamIds.contains(emp.empCode))
              .toList();
          final dataEntryTeam = allEmployees
              .where((emp) => dataEntryTeamIds.contains(emp.empCode))
              .toList();
          
          final grandTotal = allEmployees.fold(
              0.0, (sum, item) => sum + (double.tryParse(item.price) ?? 0.0));

          // Aggregate team stats
          _salesTeamTotalShops = salesTeam.fold(0, (sum, item) => sum + (int.tryParse(item.shop) ?? 0));
          _salesTeamTotalItems = salesTeam.fold(0, (sum, item) => sum + (int.tryParse(item.list) ?? 0));
          _dataEntryTeamTotalShops = dataEntryTeam.fold(0, (sum, item) => sum + (int.tryParse(item.shop) ?? 0));
          _dataEntryTeamTotalItems = dataEntryTeam.fold(0, (sum, item) => sum + (int.tryParse(item.list) ?? 0));

          // Fetch and process detailed stats for salespeople
          await _fetchSalespersonDetails();

          if (mounted) {
            setState(() {
              _salesTeam = salesTeam;
              _dataEntryTeam = dataEntryTeam;
              _grandTotalSales = grandTotal;
            });
            _startAutoScroll();
          }
        }
        return salesStatusList;
      } else {
        throw Exception('Failed to load data from API');
      }
    } catch (e) {
      throw Exception('Error fetching data: $e');
    }
  }

  // NEW: Separated function to fetch detailed salesperson stats from Firestore
  Future<void> _fetchSalespersonDetails() async {
    // 1. Fetch all customers and aggregate counts per salesperson
    final customersSnapshot = await FirebaseFirestore.instance.collection('customers').get();
    final tempCustomerCounts = <String, int>{};
    for (var doc in customersSnapshot.docs) {
        final customer = Customer.fromFirestore(doc);
        final salespersonCode = customer.salesperson;
        if (salespersonCode.isNotEmpty) {
            tempCustomerCounts[salespersonCode] = (tempCustomerCounts[salespersonCode] ?? 0) + 1;
        }
    }
    _salespersonTotalCustomers = tempCustomerCounts;

    // 2. Fetch today's call logs and aggregate counts
    final now = DateTime.now();
    final startOfToday = Timestamp.fromDate(DateTime(now.year, now.month, now.day));
    final callsSnapshot = await FirebaseFirestore.instance
        .collection('call_logs')
        .where('callTimestamp', isGreaterThanOrEqualTo: startOfToday)
        .get();

    final tempTodayCalls = <String, int>{}; // Keyed by UID
    final tempCalledCustomers = <String, Set<String>>{}; // Keyed by UID

    for (var doc in callsSnapshot.docs) {
        final data = doc.data();
        final uid = data['salespersonId'] as String?;
        final customerId = data['customerId'] as String?;
        if (uid != null && customerId != null) {
            tempTodayCalls[uid] = (tempTodayCalls[uid] ?? 0) + 1;
            tempCalledCustomers.putIfAbsent(uid, () => {}).add(customerId);
        }
    }

    // 3. Convert call stats from UID-keyed to EmployeeCode-keyed maps
    _salespersonTodayCalls.clear();
    _salespersonCalledCustomers.clear();
    tempTodayCalls.forEach((uid, count) {
        final empCode = _uidToEmpCodeMap[uid];
        if (empCode != null) {
            _salespersonTodayCalls[empCode] = count;
        }
    });
    tempCalledCustomers.forEach((uid, customerSet) {
        final empCode = _uidToEmpCodeMap[uid];
        if (empCode != null) {
            _salespersonCalledCustomers[empCode] = customerSet.length;
        }
    });
  }


  void _startAutoScroll() {
    _salesScrollTimer?.cancel();
    _dataEntryScrollTimer?.cancel();

    _salesScrollTimer =
        Timer.periodic(const Duration(milliseconds: 30), (timer) {
      _autoScrollView(_salesTeamScrollController);
    });
    _dataEntryScrollTimer =
        Timer.periodic(const Duration(milliseconds: 30), (timer) {
      _autoScrollView(_dataEntryTeamScrollController);
    });
  }

  void _autoScrollView(ScrollController controller) {
    if (controller.hasClients) {
      final maxScroll = controller.position.maxScrollExtent;
      final currentScroll = controller.offset;

      if (currentScroll < maxScroll) {
        controller.animateTo(
          currentScroll + 1.0,
          duration: const Duration(milliseconds: 30),
          curve: Curves.linear,
        );
      } else {
        controller.jumpTo(0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DailySalesStatus>>(
      future: _salesStatusFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            _salesTeam.isEmpty) {
          return const SizedBox(
              height: 340, child: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return SizedBox(
              height: 340,
              child: Center(
                  child: Text('Error: ${snapshot.error}',
                      style: const TextStyle(color: Colors.white))));
        }
        if (_salesTeam.isEmpty && _dataEntryTeam.isEmpty) {
          return const SizedBox(
              height: 340,
              child: Center(
                  child: Text('ไม่พบข้อมูลพนักงานขาย',
                      style: TextStyle(color: Colors.white))));
        }

        const double dailyTarget = 3000000.0;
        final double targetPercentage = _grandTotalSales > 0 ? (_grandTotalSales / dailyTarget) * 100 : 0.0;
        final int totalItemsAllTeams = _salesTeamTotalItems + _dataEntryTeamTotalItems;
        final double totalSalesPerHour = _grandTotalSales / 24;

        return Column(
          children: [
            _buildOverallSummaryCard(
              grandTotalSales: _grandTotalSales,
              targetPercentage: targetPercentage,
              totalItemsAllTeams: totalItemsAllTeams,
              totalSalesPerHour: totalSalesPerHour
            ),
            if (_salesTeam.isNotEmpty)
              _buildTeamSection(
                  "ฝ่ายขาย", _salesTeam, _salesTeamScrollController, _salesTeamTotalShops, _salesTeamTotalItems),
            if (_dataEntryTeam.isNotEmpty)
              _buildTeamSection("ฝ่ายคีย์ข้อมูล", _dataEntryTeam,
                  _dataEntryTeamScrollController, _dataEntryTeamTotalShops, _dataEntryTeamTotalItems),
          ],
        );
      },
    );
  }
  
  Widget _buildOverallSummaryCard({
    required double grandTotalSales,
    required double targetPercentage,
    required int totalItemsAllTeams,
    required double totalSalesPerHour,
  }) {
    final currencyFormat = NumberFormat("#,##0.00", "en_US");
    final numberFormat = NumberFormat("#,##0", "en_US");

    return Container(
      margin: const EdgeInsets.only(top: 8.0),
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
               const Text(
                'ภาพรวมยอดขายวันนี้',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Text(
                '${currencyFormat.format(grandTotalSales)} บาท',
                style: const TextStyle(color: Colors.lightGreenAccent, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          const Divider(color: Colors.white24, height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildOverallInfoChip('เป้าหมาย 3M', '${targetPercentage.toStringAsFixed(2)}%', Icons.track_changes),
              _buildOverallInfoChip('รายการรวม', numberFormat.format(totalItemsAllTeams), Icons.list_alt),
              _buildOverallInfoChip('ยอด/ชม.', currencyFormat.format(totalSalesPerHour), Icons.hourglass_bottom),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOverallInfoChip(String label, String value, IconData icon) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          ],
        ),
      ],
    );
  }


  Widget _buildTeamSection(
      String title, List<EmployeePayload> team, ScrollController controller, int totalShops, int totalItems) {
    final double totalSales = team.fold(
        0.0, (sum, item) => sum + (double.tryParse(item.price) ?? 0.0));
    final double percentage = _grandTotalSales > 0 ? (totalSales / _grandTotalSales) * 100 : 0.0;
    final double salesPerHour = totalSales / 24;
    final currencyFormat = NumberFormat("#,##0.00", "en_US");
    final numberFormat = NumberFormat("#,##0", "en_US");

    return Container(
      margin: const EdgeInsets.only(top: 16.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'ยอดรวม ${currencyFormat.format(totalSales)} บาท',
                    style: const TextStyle(
                        color: Colors.amberAccent,
                        fontSize: 17,
                        fontWeight: FontWeight.bold),
                  ),
                   Text(
                    'เปอร์เซ็นต์เฉลี่ย ${percentage.toStringAsFixed(2)}%',
                    style: TextStyle(
                        color: Colors.yellow.shade200,
                        fontSize: 14,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildTeamInfoChip(Icons.hourglass_bottom, 'ยอด/ชม.', currencyFormat.format(salesPerHour)),
                _buildTeamInfoChip(Icons.store, 'ร้านค้ารวม', numberFormat.format(totalShops)),
                _buildTeamInfoChip(Icons.list_alt, 'รายการรวม', numberFormat.format(totalItems)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 200, // Increased height to accommodate the new row
            child: Listener(
              onPointerDown: (_) {
                _salesScrollTimer?.cancel();
                _dataEntryScrollTimer?.cancel();
              },
              onPointerUp: (_) => _startAutoScroll(),
              child: ListView.builder(
                controller: controller,
                scrollDirection: Axis.horizontal,
                itemCount: team.length,
                itemBuilder: (context, index) {
                  return _buildSalespersonCard(team[index], index + 1, title);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamInfoChip(IconData icon, String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 14),
              const SizedBox(width: 4),
              Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSalespersonCard(EmployeePayload salesperson, int rank, String teamTitle) {
    final currencyFormat = NumberFormat("#,##0.00", "en_US");
    final numberFormat = NumberFormat("#,##0", "en_US");
    final price = double.tryParse(salesperson.price) ?? 0.0;
    
    // Get stats for this employee
    final totalCalls = _salespersonTodayCalls[salesperson.empCode] ?? 0;
    final totalCustomers = _salespersonTotalCustomers[salesperson.empCode] ?? 0;
    final calledCustomers = _salespersonCalledCustomers[salesperson.empCode] ?? 0;
    final itemsEntered = int.tryParse(salesperson.list) ?? 0;
    final itemsPerHour = itemsEntered / 24;

    Widget rankIcon;
    switch (rank) {
      case 1:
        rankIcon = const Icon(Icons.emoji_events, color: Color(0xFFFFD700), size: 18); // Gold
        break;
      case 2:
        rankIcon = const Icon(Icons.emoji_events, color: Color(0xFFC0C0C0), size: 18); // Silver
        break;
      case 3:
        rankIcon = const Icon(Icons.emoji_events, color: Color(0xFFCD7F32), size: 18); // Bronze
        break;
      default:
        rankIcon = const SizedBox.shrink();
    }

    final cardWidth = MediaQuery.of(context).size.width / 3.2;

    return SizedBox(
      width: cardWidth,
      child: Stack(
        children: [
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween, // Adjusted for better spacing
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundImage: NetworkImage(salesperson.empImg),
                    onBackgroundImageError: (exception, stackTrace) {},
                  ),
                  Text(
                    salesperson.empNickname ?? salesperson.empCode,
                    style:
                        const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'รหัส ${salesperson.empCode}',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                  ),
                  Text(
                    '${currencyFormat.format(price)} บาท',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Theme.of(context).primaryColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildInfoChip(Icons.storefront,
                            numberFormat.format(int.tryParse(salesperson.shop) ?? 0)),
                        const Text('/'),
                        _buildInfoChip(Icons.receipt_long,
                            numberFormat.format(int.tryParse(salesperson.bill) ?? 0)),
                        const Text('/'),
                        _buildInfoChip(Icons.list_alt,
                            numberFormat.format(int.tryParse(salesperson.list) ?? 0)),
                      ],
                    ),
                  ),
                  // NEW: Conditional stats row
                  const Divider(height: 12, thickness: 0.5),
                  if (teamTitle == "ฝ่ายขาย")
                    _buildStatRow(
                      icon1: Icons.phone_in_talk_outlined,
                      value1: '$totalCalls สาย',
                      icon2: Icons.people_alt_outlined,
                      value2: '$calledCustomers/$totalCustomers',
                    ),
                  if (teamTitle == "ฝ่ายคีย์ข้อมูล")
                     _buildStatRow(
                      icon1: Icons.speed_outlined,
                      value1: '${itemsPerHour.toStringAsFixed(1)}/ชม.',
                      icon2: Icons.list_alt_outlined,
                      value2: '$itemsEntered รายการ',
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  if (rank <= 3) ...[
                    rankIcon,
                    const SizedBox(width: 4),
                  ],
                  Text(
                    '$rank',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  // NEW: Helper for the bottom stat row in the card
  Widget _buildStatRow({required IconData icon1, required String value1, required IconData icon2, required String value2}) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon1, size: 12, color: Colors.grey.shade700),
          const SizedBox(width: 2),
          Text(value1, style: const TextStyle(fontSize: 11)),
          const Text(' | ', style: TextStyle(fontSize: 11)),
          Icon(icon2, size: 12, color: Colors.grey.shade700),
          const SizedBox(width: 2),
          Text(value2, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.0),
      child: Tooltip(
        message: label,
        child: Row(
          children: [
            Icon(icon, size: 12, color: Colors.grey.shade800),
            const SizedBox(width: 2),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
