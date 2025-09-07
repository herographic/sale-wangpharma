// lib/screens/sales_summary_time_screen.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:salewang/models/sale_order_time.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Global text shadows for better legibility on gradients
const List<Shadow> _textShadows = [
  Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 1)),
];

class SalesSummaryTimeScreen extends StatefulWidget {
  const SalesSummaryTimeScreen({super.key});

  @override
  State<SalesSummaryTimeScreen> createState() => _SalesSummaryTimeScreenState();
}

class _SalesSummaryTimeScreenState extends State<SalesSummaryTimeScreen> {
  final _base = Uri.parse('https://www.wangpharma.com');
  DateTime _selected = DateTime.now();
  bool _monthly = false; // false=single day, true=whole month
  bool _loading = false;
  List<SaleOrderTimeEntry> _entries = [];
  String? _error;
  bool _tableMode = true; // true = ตาราง, false = รายละเอียด
  int _fetchToken = 0; // guards against race conditions

  // Firestore-backed call stats keyed by empCode
  final Map<String, _EmpCallInfo> _callInfo = {};
  final Map<String, String> _uidToEmpCode = {};

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final int token = ++_fetchToken;
    setState(() {
      _loading = true;
      _error = null;
      _entries = [];
    });
    try {
      if (_monthly) {
        // fetch each day of month and aggregate
        final first = DateTime(_selected.year, _selected.month, 1);
        final last = DateTime(_selected.year, _selected.month + 1, 0);
        final lists = <List<SaleOrderTimeEntry>>[];
        for (int d = 0; d < last.day; d++) {
          if (token != _fetchToken) return; // outdated request
          final date = DateTime(first.year, first.month, d + 1);
          final list = await _fetchDay(date);
          if (token != _fetchToken) return; // outdated request
          lists.add(list);
        }
        if (token != _fetchToken) return; // outdated request
        _entries = aggregateMonthly(lists)
          ..sort((a, b) => b.salePriceValue.compareTo(a.salePriceValue));
      } else {
        final list = await _fetchDay(_selected);
        if (token != _fetchToken) return; // outdated request
        _entries = list..sort((a, b) => b.salePriceValue.compareTo(a.salePriceValue));
      }

  // Also fetch call metrics for today (independent of selected date)
  await _loadCallStats(token);
    } catch (e) {
      if (token == _fetchToken) {
        _error = e.toString();
      } else {
        return;
      }
    } finally {
      if (mounted && token == _fetchToken) setState(() => _loading = false);
    }
  }

  Future<List<SaleOrderTimeEntry>> _fetchDay(DateTime date) async {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    final url = Uri.https(_base.host, '/API/appV3/sale-order-time.php', {'date': dateStr});
    final res = await http.get(url);
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    if (res.body.isEmpty || res.body == '[]') return <SaleOrderTimeEntry>[];
    return saleOrderTimeListFromJson(res.body);
  }

  Future<void> _loadCallStats(int token) async {
    try {
      // Build UID -> empCode map
      _uidToEmpCode.clear();
      final salespeopleSnap = await FirebaseFirestore.instance.collection('salespeople').get();
      for (final doc in salespeopleSnap.docs) {
        final data = doc.data();
        final emp = data['employeeId'];
        if (emp is String && emp.isNotEmpty) {
          _uidToEmpCode[doc.id] = emp;
        }
      }
      if (token != _fetchToken) return;

      // Query today's call logs
      final now = DateTime.now();
      final startOfToday = Timestamp.fromDate(DateTime(now.year, now.month, now.day));
      final callsSnap = await FirebaseFirestore.instance
          .collection('call_logs')
          .where('callTimestamp', isGreaterThanOrEqualTo: startOfToday)
          .orderBy('callTimestamp', descending: true)
          .get();

      if (token != _fetchToken) return;

      final Map<String, _EmpCallInfo> tmp = {};
      for (final d in callsSnap.docs) {
        final data = d.data();
        final uid = data['salespersonId'] as String?;
        final custName = data['customerName'] as String?;
        final custId = data['customerId'] as String?;
        final ts = data['callTimestamp'] as Timestamp?;
        if (uid == null) continue;
        final emp = _uidToEmpCode[uid];
        if (emp == null || emp.isEmpty) continue;
        final info = tmp.putIfAbsent(emp, () => _EmpCallInfo());
        info.todayCalls += 1;
        // since ordered desc by timestamp, first hit is latest
        if (info.lastTimestamp == null && ts != null) {
          info.lastTimestamp = ts;
          info.lastCustomerName = custName;
          info.lastCustomerId = custId;
        }
      }

      if (mounted && token == _fetchToken) {
        setState(() {
          _callInfo
            ..clear()
            ..addAll(tmp);
        });
      }
    } catch (_) {
      // Silent fail; keep UI without call stats
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selected,
      firstDate: DateTime(_selected.year - 1, 1, 1),
      lastDate: DateTime(_selected.year + 1, 12, 31),
    );
    if (picked != null) {
      setState(() => _selected = picked);
      _fetch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateText = DateFormat('yyyy-MM-dd').format(_selected);
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
          title: const Text('สรุปการขาย', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.calendar_today_outlined),
              onPressed: _pickDate,
              tooltip: 'เลือกวันที่',
            ),
            Row(children: [
              const Text('รายเดือน'),
              Switch(
                value: _monthly,
                onChanged: (v) {
                  setState(() => _monthly = v);
                  _fetch();
                },
              ),
            ]),
            const SizedBox(width: 8),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : _error != null
                ? _glassCenter(Text('เกิดข้อผิดพลาด: $_error', style: const TextStyle(color: Colors.white)))
                : _entries.isEmpty
                    ? _glassCenter(Text(_monthly ? 'ไม่พบข้อมูลทั้งเดือน' : 'ไม่พบข้อมูลวันที่ $dateText', style: const TextStyle(color: Colors.white)))
                    : RefreshIndicator(
                        onRefresh: _fetch,
                        child: ListView(
                          padding: const EdgeInsets.all(12),
                          children: [
                            _buildHeaderSummary(context),
                            const SizedBox(height: 8),
                            _buildModeSwitcher(),
                            const SizedBox(height: 8),
                            if (_tableMode) _buildTableView(context) else _buildDetailList(context),
                          ],
                        ),
                      ),
      ),
    );
  }

  Widget _buildHeaderSummary(BuildContext context) {
    final totalPrice = _entries.fold<double>(0.0, (s, e) => s + e.salePriceValue);
    final totalBills = _entries.fold<int>(0, (s, e) => s + e.saleBill);
    final totalCus = _entries.fold<int>(0, (s, e) => s + e.saleCus);
    final currency = NumberFormat('#,##0.00', 'en_US');
    return _GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.assessment_outlined, color: Colors.white),
                const SizedBox(width: 8),
                const Text('สรุปรวม', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                const Spacer(),
                Text('${_entries.length} คน', style: const TextStyle(color: Colors.white)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 12, runSpacing: 8, children: [
              _chip('ยอดขายรวม', currency.format(totalPrice), Colors.greenAccent.shade200),
              _chip('จำนวนบิล', '$totalBills', Colors.lightBlueAccent.shade200),
              _chip('จำนวนลูกค้า', '$totalCus', Colors.cyanAccent.shade200),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
  Widget _buildModeSwitcher() {
      return _GlassCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              _segBtn('ตาราง', _tableMode, () => setState(() => _tableMode = true)),
              const SizedBox(width: 8),
              _segBtn('รายละเอียด', !_tableMode, () => setState(() => _tableMode = false)),
              const Spacer(),
              const Icon(Icons.today, color: Colors.white70, size: 16),
              const SizedBox(width: 6),
              Text(DateFormat('dd MMM yyyy', 'th_TH').format(_selected), style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      );
    }

  Widget _segBtn(String label, bool selected, VoidCallback onTap) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? Colors.white.withOpacity(0.2) : Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.25)),
          ),
          child: Text(label, style: TextStyle(color: selected ? Colors.white : Colors.white70, fontWeight: FontWeight.w600)),
        ),
      );
    }

  Widget _buildTableView(BuildContext context) {
      final currency = NumberFormat('#,##0.00', 'en_US');
      final sellers = _entries.where((e) => e.salePriceValue > 0).toList();
      final avgSale = sellers.isEmpty
          ? 0.0
          : sellers.fold<double>(0.0, (s, e) => s + e.salePriceValue) / sellers.length;
      return _GlassCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          child: Column(
            children: [
              for (int i = 0; i < _entries.length; i++) _compactRow(context, i + 1, _entries[i], currency, avgSale),
            ],
          ),
        ),
      );
    }

  Widget _compactRow(BuildContext context, int idx, SaleOrderTimeEntry e, NumberFormat currency, double avgSale) {
      final saleText = currency.format(e.salePriceValue);
      final calls = _callInfo[e.empCode]?.todayCalls ?? 0;
      final lastShop = _callInfo[e.empCode]?.lastLabel ?? '-';
      final score = _scoreFor(e);
      final bg = _bgColorForScore(score);
  final ratio = (avgSale > 0 ? (e.salePriceValue / avgSale) : 0.0);
  final widthFactor = ratio.clamp(0.0, 2.0);
  final percent = (ratio * 100).clamp(0.0, 9999.0);
      return Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _rankIcon(idx),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Line 1: อันดับ | รหัส | ชื่อ
                      Wrap(spacing: 6, runSpacing: 2, children: [
                        Text('อันดับ $idx', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, shadows: _textShadows)),
                        const Text('|', style: TextStyle(color: Colors.black, shadows: _textShadows)),
                        Text('รหัส ${e.empCode}', style: const TextStyle(color: Colors.white, shadows: _textShadows)),
                        const Text('|', style: TextStyle(color: Colors.black, shadows: _textShadows)),
                        Text('ชื่อ ${e.empNickname}', style: const TextStyle(color: Colors.white, shadows: _textShadows)),
                      ]),

                      const SizedBox(height: 6),
                      // EXP-like bar for Sales vs team average
                      LayoutBuilder(builder: (context, constraints) {
                        return SizedBox(
                          height: 25,
                          child: Stack(
                            children: [
                              Container(
                                width: constraints.maxWidth,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.8),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                                ),
                              ),
                              FractionallySizedBox(
                                widthFactor: (widthFactor / 2.0), // clamp to [0,1]
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFFA8FF78), Color.fromARGB(255, 4, 205, 145)],
                                    ),
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                ),
                              ),
                              Positioned.fill(
                                child: Center(
                                  child: Text(
                                    'ยอดขาย $saleText บาท | เฉลี่ย ${percent.toStringAsFixed(0)}%',
                                    style: const TextStyle(color: Colors.black,fontSize: 15, fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),

                      const SizedBox(height: 6),
                      // Line 2: ลูกค้า : care_cus | บิล : sale_bill | รายการ : sale_list | KPI : price_time
                      Wrap(spacing: 6, runSpacing: 2, children: [
                        Text('ลูกค้า : ${e.careCus}', style: const TextStyle(color: Colors.white, fontSize: 16, shadows: _textShadows)),
                        const Text('|', style: TextStyle(color: Colors.white24, fontSize: 14, shadows: _textShadows)),
                        Text('บิล : ${e.saleBill}', style: const TextStyle(color: Colors.white, fontSize: 16, shadows: _textShadows)),
                        const Text('|', style: TextStyle(color: Colors.white24, fontSize: 14, shadows: _textShadows)),
                        Text('รายการ : ${e.saleList}', style: const TextStyle(color: Colors.white, fontSize: 16, shadows: _textShadows)),
                        const Text('|', style: TextStyle(color: Colors.white24, fontSize: 14, shadows: _textShadows)),
                        Text('KPI : ${e.priceTime ?? '-'}', style: const TextStyle(color: Colors.white, fontSize: 17,fontWeight: FontWeight.bold, shadows: _textShadows)),
                      ]),

                      const SizedBox(height: 6),
                      // Line 3: โทร : today | โทรร้านล่าสุด : name(id)
                      Wrap(spacing: 6, runSpacing: 2, children: [
                        Text('โทร : $calls', style: const TextStyle(color: Colors.white, fontSize: 16, shadows: _textShadows)),
                        const Text('|', style: TextStyle(color: Colors.white24, fontSize: 14, shadows: _textShadows)),
                        Text('โทรร้านล่าสุด : $lastShop', style: const TextStyle(color: Colors.white, fontSize: 16, shadows: _textShadows)),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

  // --- Helpers for score and coloring ---
  double _scoreFor(SaleOrderTimeEntry e) {
    final p = _parsePriceTimeNumber(e.priceTime);
    final m = _parseMinutes(e.periodMinutes, e.firstBillAt, e.lastBillAt);
    if (m <= 0) return 0.0;
    return (p / m) * 100.0;
  }

  double _parsePriceTimeNumber(String? priceTime) {
    if (priceTime == null || priceTime.isEmpty) return 0.0;
    final match = RegExp(r"([0-9]+(?:\.[0-9]+)?)").firstMatch(priceTime);
    if (match == null) return 0.0;
    return double.tryParse(match.group(1)!) ?? 0.0;
  }

  int _parseMinutes(String? minutesText, DateTime? first, DateTime? last) {
    if (minutesText != null && minutesText.isNotEmpty) {
      final m = RegExp(r"(\d+)").firstMatch(minutesText);
      if (m != null) {
        return int.tryParse(m.group(1)!) ?? 0;
      }
    }
    if (first != null && last != null) {
      return last.difference(first).inMinutes;
    }
    return 0;
  }

  Color _bgColorForScore(double s) {
    if (s < 30) return const Color.fromARGB(255, 255, 37, 59).withOpacity(0.35); // red light
    if (s < 50) return const Color.fromARGB(171, 197, 181, 41).withOpacity(0.90); // yellow light
    if (s < 70) return const Color.fromARGB(255, 36, 217, 42).withOpacity(0.50); // green light
    if (s < 100) return const Color.fromARGB(255, 116, 41, 254).withOpacity(0.75); // dark gold-ish
    return Colors.white.withOpacity(0.10);
  }

  Widget _buildDetailList(BuildContext context) {
      return Column(
        children: [
          for (int i = 0; i < _entries.length; i++)
            _EmployeeCard(
              entry: _entries[i],
              rank: i + 1,
              callInfo: _callInfo[_entries[i].empCode],
            ),
        ],
      );
    }

  Widget _glassCenter(Widget child) {
      return Center(
        child: _GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: child,
          ),
        ),
      );
    }
  }

  class _GlassCard extends StatelessWidget {
    final Widget child;
    const _GlassCard({required this.child});

    @override
    Widget build(BuildContext context) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.25)),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: child,
          ),
        ),
      );
    }
}

class _EmployeeCard extends StatelessWidget {
  final SaleOrderTimeEntry entry;
  final int rank;
  final _EmpCallInfo? callInfo;
  const _EmployeeCard({required this.entry, required this.rank, this.callInfo});

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat('#,##0.00', 'en_US');
    final hours = entry.saleTimeByHour;
    final hoursSorted = hours.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final maxVal = hours.values.fold<double>(0, (m, v) => v > m ? v : m);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
      Row(
              children: [
        _rankIcon(rank),
        const SizedBox(width: 6),
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.grey.shade200,
                  backgroundImage: entry.empImg.isNotEmpty ? NetworkImage(entry.empImg) : null,
                  child: entry.empImg.isEmpty ? const Icon(Icons.person) : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${entry.empNickname} (${entry.empCode})', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            // First info line
            Text('ลูกค้า ${entry.saleCus} | บิล ${entry.saleBill} | รายการ ${entry.saleList} | KPI ${entry.priceTime ?? '-'}',
              style: const TextStyle(fontSize: 12, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
            // Second info line with call metrics
            Text('โทรวันนี้ ${callInfo?.todayCalls ?? 0} | โทรร้านล่าสุด: ${callInfo?.lastLabel ?? '-'}',
              style: const TextStyle(fontSize: 11, color: Colors.black54), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(entry.empFullname, style: const TextStyle(fontSize: 12, color: Colors.black87)),
                      Text('มือถือ: ${entry.empMobile}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('ยอดขาย', style: TextStyle(color: Colors.grey.shade700)),
                    Text(currency.format(entry.salePriceValue), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: [
              _smallChip(Icons.people_outline, 'ดูแลลูกค้า', '${entry.careCus}'),
              _smallChip(Icons.alt_route, 'เส้นทาง', '${entry.careRoute}'),
              _smallChip(Icons.receipt_long_outlined, 'บิล', '${entry.saleBill}'),
              _smallChip(Icons.shopping_basket_outlined, 'รายการ', '${entry.saleList}'),
              if (entry.periodMinutes != null && entry.periodMinutes!.isNotEmpty)
                _smallChip(Icons.timer_outlined, 'เวลาขาย', entry.periodMinutes!),
              if (entry.priceTime != null && entry.priceTime!.isNotEmpty)
                _smallChip(Icons.price_check_outlined, 'บาท/นาที', entry.priceTime!),
            ]),
            const SizedBox(height: 8),
            _HourBarChart(data: hoursSorted, maxVal: maxVal),
          ],
        ),
      ),
    );
  }

  Widget _smallChip(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade700),
          const SizedBox(width: 4),
          Text('$label: ', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _HourBarChart extends StatelessWidget {
  final List<MapEntry<String, double>> data;
  final double maxVal;
  const _HourBarChart({required this.data, required this.maxVal});

  @override
  Widget build(BuildContext context) {
    final barColor = Colors.indigo.shade400;
    final maxWidth = maxVal <= 0 ? 1 : maxVal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: data.map((e) {
        final ratio = (e.value / maxWidth).clamp(0.0, 1.0);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.0),
          child: Row(
            children: [
              SizedBox(width: 44, child: Text(e.key, style: const TextStyle(fontSize: 10, color: Colors.black54))),
              Expanded(
                child: Stack(
                  children: [
                    Container(height: 10, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(5))),
                    FractionallySizedBox(
                      widthFactor: ratio,
                      child: Container(height: 10, decoration: BoxDecoration(color: barColor, borderRadius: BorderRadius.circular(5))),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: Text(NumberFormat('#,##0.00', 'en_US').format(e.value),
                    textAlign: TextAlign.right, style: const TextStyle(fontSize: 10)),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// Helper: call metrics per employee
class _EmpCallInfo {
  int todayCalls = 0;
  Timestamp? lastTimestamp;
  String? lastCustomerName;
  String? lastCustomerId;

  String get lastLabel {
    final name = lastCustomerName?.trim();
    final id = lastCustomerId?.trim();
    if ((name == null || name.isEmpty) && (id == null || id.isEmpty)) return '-';
    if (name != null && name.isNotEmpty && id != null && id.isNotEmpty) return '$name ($id)';
    return name?.isNotEmpty == true ? name! : id!;
  }
}

// Helper: rank icon for top 3
Widget _rankIcon(int rank) {
  if (rank == 1) {
    return const Icon(Icons.emoji_events, color: Colors.amber, size: 18);
  } else if (rank == 2) {
    return const Icon(Icons.emoji_events, color: Colors.grey, size: 18);
  } else if (rank == 3) {
    return Icon(Icons.emoji_events, color: Colors.brown.shade400, size: 18);
  }
  return const SizedBox.shrink();
}
