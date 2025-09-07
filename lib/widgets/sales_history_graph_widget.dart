// lib/widgets/sales_history_graph_widget.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:salewang/models/sales_history.dart';

class SalesHistoryGraphWidget extends StatefulWidget {
  const SalesHistoryGraphWidget({super.key});

  @override
  State<SalesHistoryGraphWidget> createState() => _SalesHistoryGraphWidgetState();
}

class _SalesHistoryGraphWidgetState extends State<SalesHistoryGraphWidget> {
  List<SalesHistory>? _allSalesHistory;
  List<SalesHistory>? _displaySalesHistory;
  bool _isLoading = true;
  String? _errorMessage;
  DateTime _endDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _fetchSalesHistory();
  }

  Future<void> _fetchSalesHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    const String apiUrl = 'https://www.wangpharma.com/API/sale/historyday-status.php';
    const String token = 'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJtZW1fY29kZSI6IjAzNTAifQ.9xQokBCn6ED-xwHQFXsa5Bah57dNc8vWJ_4Iin8E3m0';

    try {
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        List<SalesHistory> history = salesHistoryFromJson(response.body);
        history.sort((a, b) => a.saleDate.compareTo(b.saleDate));
        _allSalesHistory = history;
        _filterHistoryForDisplay(_endDate);
      } else {
        throw Exception('API Error: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'ไม่สามารถเชื่อมต่อได้: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _filterHistoryForDisplay(DateTime endDate) {
    if (_allSalesHistory == null) return;
    final relevantHistory = _allSalesHistory!
        .where((h) => !h.saleDate.isAfter(endDate))
        .toList();
    _displaySalesHistory = relevantHistory.length > 7
        ? relevantHistory.sublist(relevantHistory.length - 7)
        : relevantHistory;
    setState(() {});
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('th', 'TH'),
    );
    if (picked != null && picked != _endDate) {
      setState(() {
        _endDate = picked;
        _filterHistoryForDisplay(_endDate);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Card(
        child: SizedBox(height: 280, child: Center(child: CircularProgressIndicator())),
      );
    }
    if (_errorMessage != null) {
      return Card(
        color: Colors.red.shade50,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 40),
              const SizedBox(height: 8),
              Text('ไม่สามารถโหลดข้อมูลกราฟได้', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade800)),
              const SizedBox(height: 8),
              Text(_errorMessage!, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.red.shade600)),
            ],
          ),
        ),
      );
    }
    if (_displaySalesHistory == null || _displaySalesHistory!.isEmpty) {
      return Card(
        child: SizedBox(
          height: 280,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('ไม่พบข้อมูลการขายสำหรับช่วงเวลานี้'),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () => _selectDate(context),
                  child: const Text('เลือกวันที่อื่น'),
                )
              ],
            ),
          ),
        ),
      );
    }

    return _buildGraphCard(_displaySalesHistory!);
  }

  Widget _buildGraphCard(List<SalesHistory> salesData) {
    final fullThaiDateFormat = DateFormat('d MMMM yyyy', 'th_TH');
    final latestData = salesData.last;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: Colors.white.withOpacity(0.95),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'ยอดขาย 7 วันล่าสุด',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.calendar_month_outlined),
                  onPressed: () => _selectDate(context),
                  tooltip: 'เลือกช่วงวันที่',
                )
              ],
            ),
            Text(
              'ข้อมูลถึงวันที่: ${fullThaiDateFormat.format(latestData.saleDate)}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 220,
              child: _buildBarChart(salesData),
            ),
          ],
        ),
      ),
    );
  }

  String _formatYAxisLabel(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(value % 1000000 == 0 ? 0 : 1)} ล้าน';
    }
    if (value >= 100000) {
      return '${(value / 100000).toStringAsFixed(0)} แสน';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(0)}K';
    }
    return value.toStringAsFixed(0);
  }

  // --- NEW: Helper to format tooltip values as requested (e.g., 3.20 ล้าน) ---
  String _formatTooltipLabel(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(2)} ล้าน';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return value.toStringAsFixed(0);
  }

  Widget _buildBarChart(List<SalesHistory> salesData) {
    final maxSales = salesData.map((d) => d.salePrice).reduce((a, b) => a > b ? a : b);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxSales * 1.25,
        gridData: FlGridData(
          show: true,
          drawHorizontalLine: true,
          horizontalInterval: maxSales > 0 ? maxSales / 4 : 1,
          getDrawingHorizontalLine: (value) => const FlLine(
            color: Color(0xffe7e8ec),
            strokeWidth: 1,
            dashArray: [5, 5],
          ),
          drawVerticalLine: false,
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= salesData.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    DateFormat('E\ndd/MM', 'th_TH').format(salesData[index].saleDate),
                    style: const TextStyle(fontSize: 10, color: Colors.black54),
                    textAlign: TextAlign.center,
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 50,
              getTitlesWidget: (value, meta) {
                if (value == 0 || value >= meta.max) return const SizedBox.shrink();
                return Text(
                  _formatYAxisLabel(value),
                  style: const TextStyle(fontSize: 10, color: Colors.black54),
                  textAlign: TextAlign.left,
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: salesData.asMap().entries.map((entry) {
          final index = entry.key;
          final data = entry.value;
          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: data.salePrice,
                gradient: LinearGradient(
                  colors: [Theme.of(context).primaryColor, Colors.cyan],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
                width: 20,
                borderRadius: const BorderRadius.all(Radius.circular(6)),
              ),
            ],
            showingTooltipIndicators: [0],
          );
        }).toList(),
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => Colors.blueGrey.withOpacity(0.8),
            tooltipPadding: const EdgeInsets.all(8),
            tooltipMargin: 8,
            // --- UPDATED: Tooltip now shows only the formatted value ---
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                _formatTooltipLabel(rod.toY), // Use the new formatting function
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              );
            },
          ),
        ),
      ),
      swapAnimationDuration: const Duration(milliseconds: 500),
      swapAnimationCurve: Curves.easeInOut,
    );
  }
}
