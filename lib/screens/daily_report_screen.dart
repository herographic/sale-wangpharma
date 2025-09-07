// lib/screens/daily_report_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:salewang/models/daily_report.dart';

class DailyReportScreen extends StatefulWidget {
  const DailyReportScreen({super.key});

  @override
  State<DailyReportScreen> createState() => _DailyReportScreenState();
}

class _DailyReportScreenState extends State<DailyReportScreen> {
  DateTime _selectedDate = DateTime.now();
  Future<DailyReport?>? _reportFuture;

  @override
  void initState() {
    super.initState();
    _fetchReportForDate(_selectedDate);
  }

  void _fetchReportForDate(DateTime date) {
    setState(() {
      _reportFuture = _getReportFromFirestore(date);
    });
  }

  Future<DailyReport?> _getReportFromFirestore(DateTime date) async {
    try {
      final dateString = DateFormat('yyyy-MM-dd').format(date);
      final docSnapshot = await FirebaseFirestore.instance
          .collection('daily_reports')
          .doc(dateString)
          .get();

      if (docSnapshot.exists) {
        return DailyReport.fromFirestore(docSnapshot);
      }
      return null; // No report found for this date
    } catch (e) {
      // Re-throw the error to be caught by the FutureBuilder
      throw Exception('Failed to load report: $e');
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      locale: const Locale('th', 'TH'),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _fetchReportForDate(_selectedDate);
      });
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
           title: const Text('รายงานย้อนหลัง', style: TextStyle(color: Colors.white)),
           backgroundColor: Colors.transparent,
           elevation: 0,
           foregroundColor: Colors.white,
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.calendar_today),
                label: Text('วันที่: ${DateFormat('d MMMM yyyy', 'th_TH').format(_selectedDate)}'),
                onPressed: () => _selectDate(context),
                 style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Theme.of(context).primaryColor,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<DailyReport?>(
                future: _reportFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Colors.white));
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('เกิดข้อผิดพลาด: ${snapshot.error}', style: const TextStyle(color: Colors.white)));
                  }
                  if (!snapshot.hasData || snapshot.data == null) {
                    return const Center(child: Text('ไม่พบข้อมูลสำหรับวันที่เลือก', style: TextStyle(color: Colors.white70, fontSize: 16)));
                  }

                  final report = snapshot.data!;
                  return _buildReportView(report);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportView(DailyReport report) {
     // Calculations for the overall summary
    const double dailyTarget = 3000000.0;
    final double targetPercentage = report.grandTotalSales > 0 ? (report.grandTotalSales / dailyTarget) * 100 : 0.0;
    final double totalSalesPerHour = report.grandTotalSales / 24;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      children: [
         _buildOverallSummaryCard(
            grandTotalSales: report.grandTotalSales,
            targetPercentage: targetPercentage,
            totalItemsAllTeams: report.totalItemsAllTeams,
            totalSalesPerHour: totalSalesPerHour
          ),
        if (report.salesTeam.isNotEmpty)
          _buildTeamSection("ฝ่ายขาย", report.salesTeam, report.grandTotalSales),
        if (report.dataEntryTeam.isNotEmpty)
          _buildTeamSection("ฝ่ายคีย์ข้อมูล", report.dataEntryTeam, report.grandTotalSales),
      ],
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
      margin: const EdgeInsets.all(8.0),
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
                'ภาพรวมยอดขาย',
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


  Widget _buildTeamSection(String title, List<EmployeeDailyPerformance> team, double grandTotalSales) {
    final double totalSales = team.fold(0.0, (sum, item) => sum + item.price);
    final int totalShops = team.fold(0, (sum, item) => sum + item.shop);
    final int totalItems = team.fold(0, (sum, item) => sum + item.list);
    final double percentage = grandTotalSales > 0 ? (totalSales / grandTotalSales) * 100 : 0.0;
    final double salesPerHour = totalSales / 24;
    final currencyFormat = NumberFormat("#,##0.00", "en_US");
    final numberFormat = NumberFormat("#,##0", "en_US");

    return Container(
      margin: const EdgeInsets.only(top: 16.0, left: 8.0, right: 8.0),
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
                style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'ยอดรวม ${currencyFormat.format(totalSales)} บาท',
                    style: const TextStyle(color: Colors.amberAccent, fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                   Text(
                    'เปอร์เซ็นต์เฉลี่ย ${percentage.toStringAsFixed(2)}%',
                    style: TextStyle(color: Colors.yellow.shade200, fontSize: 14, fontWeight: FontWeight.bold),
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
            height: 200,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: team.length,
              itemBuilder: (context, index) {
                return _buildSalespersonCard(team[index], index + 1, title);
              },
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

  Widget _buildSalespersonCard(EmployeeDailyPerformance salesperson, int rank, String teamTitle) {
    final currencyFormat = NumberFormat("#,##0.00", "en_US");
    final numberFormat = NumberFormat("#,##0", "en_US");
    final itemsPerHour = salesperson.list / 24;

    Widget rankIcon;
    switch (rank) {
      case 1: rankIcon = const Icon(Icons.emoji_events, color: Color(0xFFFFD700), size: 18); break;
      case 2: rankIcon = const Icon(Icons.emoji_events, color: Color(0xFFC0C0C0), size: 18); break;
      case 3: rankIcon = const Icon(Icons.emoji_events, color: Color(0xFFCD7F32), size: 18); break;
      default: rankIcon = const SizedBox.shrink();
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundImage: NetworkImage(salesperson.empImg),
                    onBackgroundImageError: (exception, stackTrace) {},
                  ),
                  Text(
                    salesperson.empNickname ?? salesperson.empCode,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'รหัส ${salesperson.empCode}',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                  ),
                  Text(
                    '${currencyFormat.format(salesperson.price)} บาท',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Theme.of(context).primaryColor),
                    overflow: TextOverflow.ellipsis,
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildInfoChip(Icons.storefront, numberFormat.format(salesperson.shop)),
                        const Text('/'),
                        _buildInfoChip(Icons.receipt_long, numberFormat.format(salesperson.bill)),
                        const Text('/'),
                        _buildInfoChip(Icons.list_alt, numberFormat.format(salesperson.list)),
                      ],
                    ),
                  ),
                  const Divider(height: 12, thickness: 0.5),
                  if (teamTitle == "ฝ่ายขาย")
                    _buildStatRow(
                      icon1: Icons.phone_in_talk_outlined,
                      value1: '${salesperson.totalCalls} สาย',
                      icon2: Icons.people_alt_outlined,
                      value2: '${salesperson.calledCustomers}/${salesperson.totalCustomers}',
                    ),
                  if (teamTitle == "ฝ่ายคีย์ข้อมูล")
                     _buildStatRow(
                      icon1: Icons.speed_outlined,
                      value1: '${itemsPerHour.toStringAsFixed(1)}/ชม.',
                      icon2: Icons.list_alt_outlined,
                      value2: '${salesperson.list} รายการ',
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
                  Text('$rank', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

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
