// lib/screens/transport_status_screen.dart

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:salewang/models/logistic_report.dart';
import 'package:salewang/utils/launcher_helper.dart';
import 'package:salewang/models/member.dart' as member_model;

enum TransportSearchType { employee, route }

class TransportStatusScreen extends StatefulWidget {
  const TransportStatusScreen({super.key});

  @override
  State<TransportStatusScreen> createState() => _TransportStatusScreenState();
}

class _TransportStatusScreenState extends State<TransportStatusScreen> {
  TransportSearchType _searchType = TransportSearchType.employee;
  final TextEditingController _employeeCodeController = TextEditingController();
  String? _selectedRouteCode;
  bool _isLoading = false;
  String? _errorMessage;
  LogisticReport? _reportData;
  String _statusMessage = 'กรุณาเลือกเงื่อนไขและกดค้นหา';

  final Map<String, String> _routeMap = {
    'L1-1': 'อ.หาดใหญ่1', 'L1-2': 'เมืองสงขลา', 'L1-3': 'สะเดา', 'L2': 'ปัตตานี', 'L3': 'สตูล',
    'L4': 'พัทลุง', 'L5-1': 'นราธิวาส', 'L5-2': 'สุไหงโกลก', 'L6': 'ยะลา', 'L7': 'เบตง',
    'L9': 'ตรัง', 'L10': 'นครศรีฯ', 'Office': 'วังเภสัช', 'R-00': 'อื่นๆ', 'L1-5': 'สทิงพระ',
    'Logistic': 'ฝากขนส่ง', 'L11': 'กระบี่', 'L12': 'ภูเก็ต', 'L13': 'สุราษฎร์ฯ', 'L17': 'พังงา',
    'L16': 'ยาแห้ง', 'L4-1': 'พัทลุง VIP', 'L18': 'เกาะสมุย', 'L19': 'พัทลุง-นคร', 'L20': 'ชุมพร',
    'L9-11': 'กระบี่-ตรัง', 'L21': 'เกาะลันตา', 'L22': 'เกาะพะงัน', 'L23': 'อ.หาดใหญ่2',
  };

  @override
  void dispose() {
    _employeeCodeController.dispose();
    super.dispose();
  }

  /// Fetches transport data from the API based on the selected search criteria.
  Future<void> _fetchTransportData() async {
    FocusScope.of(context).unfocus();
    if (_searchType == TransportSearchType.employee && _employeeCodeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กรุณากรอกรหัสพนักงานขนส่ง')));
      return;
    }
    if (_searchType == TransportSearchType.route && _selectedRouteCode == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กรุณาเลือกเส้นทาง')));
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _reportData = null;
    });

    try {
      const String baseUrl = 'www.wangpharma.com';
      const String path = '/API/appV3/report-logistic.php';
      const String token = 'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJtZW1fY29kZSI6IjAzNTAifQ.9xQokBCn6ED-xwHQFXsa5Bah57dNc8vWJ_4Iin8E3m0';

      Map<String, String> queryParams = {};
      if (_searchType == TransportSearchType.employee) {
        queryParams['lg'] = _employeeCodeController.text.trim();
      } else {
        queryParams['route'] = _selectedRouteCode!;
      }

      final url = Uri.http(baseUrl, path, queryParams);
      final response = await http.get(url, headers: {'Authorization': 'Bearer $token'});

      if (!mounted) return;

      if (response.statusCode == 200) {
        final report = logisticReportFromJson(response.body);
        setState(() {
          _reportData = report;
          if (report.data.isEmpty) {
            _statusMessage = 'ไม่พบข้อมูลการจัดส่ง';
          }
        });
      } else if (response.statusCode == 404) {
         setState(() {
          _reportData = LogisticReport(data: []);
          _statusMessage = 'ไม่พบข้อมูลการจัดส่งสำหรับเงื่อนไขที่เลือก';
        });
      }
      else {
        throw Exception('API Error: ${response.statusCode}');
      }
    } catch (e) {
      setState(() => _errorMessage = 'เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
          title: const Text('สถานะขนส่ง', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
        body: Column(
          children: [
            _buildSearchPanel(),
            Expanded(child: _buildResultsView()),
          ],
        ),
      ),
    );
  }

  /// Builds the top panel containing search controls.
  Widget _buildSearchPanel() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            SegmentedButton<TransportSearchType>(
              segments: const [
                ButtonSegment(value: TransportSearchType.employee, label: Text('พนักงาน'), icon: Icon(Icons.badge)),
                ButtonSegment(value: TransportSearchType.route, label: Text('เส้นทาง'), icon: Icon(Icons.map)),
              ],
              selected: {_searchType},
              onSelectionChanged: (Set<TransportSearchType> newSelection) {
                setState(() {
                  _searchType = newSelection.first;
                  _reportData = null; // Clear previous results
                  _statusMessage = 'กรุณาเลือกเงื่อนไขและกดค้นหา';
                });
              },
            ),
            const SizedBox(height: 12),
            if (_searchType == TransportSearchType.employee)
              TextField(
                controller: _employeeCodeController,
                decoration: const InputDecoration(
                  labelText: 'รหัสพนักงานขนส่ง',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                onSubmitted: (_) => _fetchTransportData(),
              )
            else
              DropdownButtonFormField<String>(
                value: _selectedRouteCode,
                decoration: const InputDecoration(
                  labelText: 'เลือกเส้นทาง',
                  border: OutlineInputBorder(),
                ),
                items: _routeMap.entries.map((entry) {
                  return DropdownMenuItem<String>(
                    value: entry.key,
                    child: Text(entry.value),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedRouteCode = value;
                  });
                },
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.search),
                label: const Text('ค้นหา'),
                onPressed: _isLoading ? null : _fetchTransportData,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the main content area to display results, loading, or status messages.
  Widget _buildResultsView() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_errorMessage != null) {
      return Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.white)));
    }
    if (_reportData == null || _reportData!.data.isEmpty) {
      return Center(child: Text(_statusMessage, style: const TextStyle(color: Colors.white70)));
    }

    final items = _reportData!.data;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return _LogisticItemCard(item: items[index]);
      },
    );
  }
}

/// A card widget to display a single logistic item.
class _LogisticItemCard extends StatelessWidget {
  final LogisticItem item;

  const _LogisticItemCard({required this.item});

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'กำลังส่ง':
        return Colors.blue.shade700;
      case 'ส่งสำเร็จ':
        return Colors.green.shade700;
      case 'ส่งไม่สำเร็จ':
        return Colors.red.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat("#,##0.00", "en_US");
    final sumPrice = double.tryParse(item.sumprice?.replaceAll(',', '') ?? '0') ?? 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    item.memName ?? 'N/A',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                if (item.memPhone != null && item.memPhone!.isNotEmpty)
                  IconButton(
                    icon: Icon(Icons.phone_forwarded_outlined, color: Colors.green.shade700),
                    onPressed: () {
                      final tempMember = member_model.Member(
                        memCode: item.memCode,
                        memName: item.memName,
                        memTel: item.memPhone,
                        empCode: item.empSale,
                      );
                      LauncherHelper.makeAndLogApiCall(
                        context: context,
                        phoneNumber: item.memPhone!,
                        member: tempMember,
                      );
                    },
                  ),
              ],
            ),
            Text('รหัส: ${item.memCode ?? '-'} | ราคา: ${item.memPrice ?? '-'} | โดย: ${item.empSale ?? '-'}', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
            const Divider(height: 16),
            _buildInfoRow(Icons.route_outlined, 'เส้นทาง:', item.memRoute ?? '-'),
            _buildInfoRow(Icons.inventory_2_outlined, 'จำนวนบิล/กล่อง:', '${item.billAmount ?? '0'} / ${item.boxAmount ?? '0'}'),
            _buildInfoRow(Icons.price_check_outlined, 'ยอดรวม:', '฿${currencyFormat.format(sumPrice)}'),
            const Divider(height: 16),
            _buildInfoRow(Icons.access_time, 'เวลาออก:', item.timeOut ?? '-'),
            _buildInfoRow(Icons.check_circle_outline, 'เวลาถึง:', item.timeFinish ?? '-'),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Chip(
                label: Text(item.status ?? 'ไม่ทราบสถานะ', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                backgroundColor: _getStatusColor(item.status),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(width: 8),
          Expanded(child: Text(value, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}
