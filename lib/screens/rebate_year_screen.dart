// lib/screens/rebate_year_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:salewang/models/rebate.dart';
import 'package:salewang/utils/launcher_helper.dart';
import 'package:salewang/models/customer.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class RebateYearScreen extends StatefulWidget {
  const RebateYearScreen({super.key});

  @override
  State<RebateYearScreen> createState() => _RebateYearScreenState();
}

class _RebateYearScreenState extends State<RebateYearScreen> {
  RebateData? _foundRebateData;
  bool _isLoading = false;
  String? _errorMessage;
  String _statusMessage = 'กรุณาค้นหารหัสลูกค้าเพื่อดูข้อมูล';
  bool _hasSearched = false;

  final TextEditingController _searchController = TextEditingController();
  DateTime _selectedYear = DateTime(2025); // Default to 2025 as per UI
  final NumberFormat _currencyFormat = NumberFormat("#,##0.00", "en_US");

  Future<void> _searchCustomerData() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาป้อนรหัสลูกค้าเพื่อค้นหา')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _foundRebateData = null;
      _hasSearched = true;
      _statusMessage = 'กำลังค้นหาข้อมูล...';
    });

    try {
      final sanitizedQuery = query.replaceAll('/', '-');
      final docSnapshot = await FirebaseFirestore.instance
          .collection('rebate')
          .doc(sanitizedQuery)
          .get();

      if (!docSnapshot.exists) {
        _statusMessage = 'ไม่พบข้อมูลรีเบทสำหรับลูกค้า "$query"';
      } else {
        _foundRebateData = RebateData.fromFirestore(docSnapshot);
      }
    } catch (e) {
      _errorMessage = 'เกิดข้อผิดพลาด: $e';
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectYear(BuildContext context) async {
    final now = DateTime.now();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("เลือกปี"),
        content: SizedBox(
          width: 300,
          height: 300,
          child: YearPicker(
            firstDate: DateTime(2020),
            lastDate: DateTime(now.year + 5),
            selectedDate: _selectedYear,
            onChanged: (dateTime) {
              setState(() => _selectedYear = dateTime);
              Navigator.pop(context);
            },
          ),
        ),
      ),
    );
  }
  
  // --- UPDATED: PDF Report Generation Logic ---
  Future<void> _printReport(RebateData rebateData) async {
    final doc = pw.Document();
    final font = await PdfGoogleFonts.promptBold();
    final fontRegular = await PdfGoogleFonts.promptRegular();

    final monthlyData = {
      'ม.ค.': rebateData.salesJan, 'ก.พ.': rebateData.salesFeb, 'มี.ค.': rebateData.salesMar,
      'เม.ย.': rebateData.salesApr, 'พ.ค.': rebateData.salesMay, 'มิ.ย.': rebateData.salesJun,
      'ก.ค.': rebateData.salesJul, 'ส.ค.': rebateData.salesAug, 'ก.ย.': rebateData.salesSep,
      'ต.ค.': rebateData.salesOct, 'พ.ย.': rebateData.salesNov, 'ธ.ค.': rebateData.salesDec,
    };
     final percentageData = {
      'เม.ย.': rebateData.percentApr, 'พ.ค.': rebateData.percentMay, 'มิ.ย.': rebateData.percentJun,
      'ก.ค.': rebateData.percentJul, 'ส.ค.': rebateData.percentAug, 'ก.ย.': rebateData.percentSep,
      'ต.ค.': rebateData.percentOct, 'พ.ย.': rebateData.percentNov, 'ธ.ค.': rebateData.percentDec,
    };

    final totalActual = monthlyData.values.reduce((a, b) => a + b);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('บริษัท วังเภสัชฟาร์มาซูติคอล จำกัด', style: pw.TextStyle(font: font, fontSize: 16)),
              pw.Text('23 ซ.พัฒโน ถ.อนุสรณ์อาจาร์ยทอง อ.หาดใหญ่ จ.สงขลา 90110', style: pw.TextStyle(font: fontRegular, fontSize: 10)),
              pw.SizedBox(height: 5),
              pw.Text('รายงานสรุปยอดรีเบท ปี ${_selectedYear.year + 543}', style: pw.TextStyle(font: font, fontSize: 18)),
              pw.SizedBox(height: 10),
              pw.Text('${rebateData.customerName} (รหัส: ${rebateData.customerId})', style: pw.TextStyle(font: fontRegular, fontSize: 12)),
              pw.Text('ผู้ดูแล: ${rebateData.salesperson ?? '-'} | เส้นทาง: ${rebateData.route ?? '-'}', style: pw.TextStyle(font: fontRegular, fontSize: 10)),
              pw.Divider(height: 20),
            ]
          );
        },
        build: (pw.Context context) {
          return [
            pw.Table.fromTextArray(
              headers: ['เดือน', 'เป้า/เดือน', 'ยอดขาย', 'ขาดอีก', '%'],
              data: monthlyData.entries.where((e) => e.value > 0).map((entry){
                final month = entry.key;
                final sales = entry.value;
                final target = rebateData.monthlyTarget;
                final shortfall = target - sales;
                
                double percentage = percentageData[month] ?? 0.0;
                if (percentage == 0.0 && target > 0) {
                   percentage = (sales / target) * 100;
                }

                return [
                  month,
                  _currencyFormat.format(target),
                  _currencyFormat.format(sales),
                  _currencyFormat.format(shortfall > 0 ? shortfall : 0),
                  '${percentage.toStringAsFixed(2)}%',
                ];
              }).toList(),
              headerStyle: pw.TextStyle(font: font, fontSize: 10),
              cellStyle: pw.TextStyle(font: fontRegular, fontSize: 10),
              border: pw.TableBorder.all(),
              cellAlignments: {
                1: pw.Alignment.centerRight,
                2: pw.Alignment.centerRight,
                3: pw.Alignment.centerRight,
                4: pw.Alignment.centerRight,
              }
            ),
            pw.SizedBox(height: 20),
            pw.Divider(),
            pw.SizedBox(height: 10),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('ยอดขายรวมทั้งปี: ${_currencyFormat.format(totalActual)}', style: pw.TextStyle(font: fontRegular, fontSize: 11)),
                    pw.Text('เป้าที่ต้องทำรวมแล้วทั้งปี: ${_currencyFormat.format(rebateData.nineMonthTarget)}', style: pw.TextStyle(font: fontRegular, fontSize: 11)),
                    pw.Text('สมนาคุณที่ได้รับ: ${_currencyFormat.format(rebateData.bonus)}', style: pw.TextStyle(font: font, fontSize: 12)),
                  ]
                )
              ]
            )
          ];
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => doc.save());
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
          title: const Text('ตรวจสอบยอดรีเบท', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
        body: Column(
          children: [
            _buildControlsPanel(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsPanel() {
    final String yearText = 'ข้อมูลปี พ.ศ. ${_selectedYear.year + 543}';

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.calendar_today),
              label: Text(yearText),
              onPressed: () => _selectYear(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey.shade100,
                foregroundColor: Colors.black87,
                minimumSize: const Size(double.infinity, 40),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'ค้นหา (รหัสลูกค้า)...',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _searchCustomerData,
                ),
              ),
              onSubmitted: (_) => _searchCustomerData(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: Colors.white));
    if (_errorMessage != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(_errorMessage!, style: const TextStyle(color: Colors.white, fontSize: 16), textAlign: TextAlign.center,),
      ));
    }
    if (!_hasSearched || _foundRebateData == null) {
      return Center(child: Text(_statusMessage, style: const TextStyle(color: Colors.white, fontSize: 16), textAlign: TextAlign.center));
    }

    final rebate = _foundRebateData!;
    final monthlyData = {
      'ม.ค.': rebate.salesJan, 'ก.พ.': rebate.salesFeb, 'มี.ค.': rebate.salesMar,
      'เม.ย.': rebate.salesApr, 'พ.ค.': rebate.salesMay, 'มิ.ย.': rebate.salesJun,
      'ก.ค.': rebate.salesJul, 'ส.ค.': rebate.salesAug, 'ก.ย.': rebate.salesSep,
      'ต.ค.': rebate.salesOct, 'พ.ย.': rebate.salesNov, 'ธ.ค.': rebate.salesDec,
    };
    final percentageData = {
      'เม.ย.': rebate.percentApr, 'พ.ค.': rebate.percentMay, 'มิ.ย.': rebate.percentJun,
      'ก.ค.': rebate.percentJul, 'ส.ค.': rebate.percentAug, 'ก.ย.': rebate.percentSep,
      'ต.ค.': rebate.percentOct, 'พ.ย.': rebate.percentNov, 'ธ.ค.': rebate.percentDec,
    };
    
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        _CustomerInfoCard(rebate: rebate, currencyFormat: _currencyFormat, onPrint: () => _printReport(rebate)),
        _YearlySummaryCard(rebate: rebate, currencyFormat: _currencyFormat, selectedYear: _selectedYear),
        ...monthlyData.entries.map((entry) {
          if (entry.value > 0) {
            double percentage = percentageData[entry.key] ?? 0.0;
            if (percentage == 0.0 && ['ม.ค.', 'ก.พ.', 'มี.ค.'].contains(entry.key)) {
              if (rebate.monthlyTarget > 0) {
                percentage = (entry.value / rebate.monthlyTarget) * 100;
              }
            }
            return _RebateMonthCard(
              month: entry.key,
              salesActual: entry.value,
              monthlyTarget: rebate.monthlyTarget,
              percentage: percentage,
              currencyFormat: _currencyFormat,
            );
          }
          return const SizedBox.shrink();
        }),
      ],
    );
  }
}

class _CustomerInfoCard extends StatelessWidget {
  final RebateData rebate;
  final NumberFormat currencyFormat;
  final VoidCallback onPrint;

  const _CustomerInfoCard({required this.rebate, required this.currencyFormat, required this.onPrint});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(rebate.customerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Row(
              children: [
                Text("รหัส: ${rebate.customerId}", style: TextStyle(color: Colors.grey.shade700)),
                const SizedBox(width: 16),
                Text("เส้นทาง: ${rebate.route ?? '-'}", style: TextStyle(color: Colors.grey.shade700)),
              ],
            ),
            const Divider(height: 20),
            _buildInfoRowWithActions("เบอร์โทร:", rebate.phoneNumber ?? '-', context),
            _buildInfoRow("ผู้ดูแล:", rebate.salesperson ?? '-'),
            _buildInfoRow("ระดับราคา:", rebate.priceLevel ?? '-'),
            _buildInfoRow("ยอดขายปี 2024:", currencyFormat.format(rebate.sales2024)),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          SizedBox(width: 100, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildInfoRowWithActions(String label, String value, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          SizedBox(width: 100, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500))),
          Expanded(child: Text(value)),
          if (value != '-')
            IconButton(
              icon: Icon(Icons.call_outlined, color: Colors.green.shade700),
              onPressed: () {
                final tempCustomer = Customer(id: rebate.customerId, customerId: rebate.customerId, name: rebate.customerName, contacts: [{'name': 'เบอร์หลัก', 'phone': value}], address1: '', address2: '', phone: '', contactPerson: '', email: '', customerType: '', taxId: '', branch: '', paymentTerms: '', creditLimit: '', salesperson: '', p: '', b1: '', b2: '', b3: '', startDate: '', lastSaleDate: '', lastPaymentDate: '');
                LauncherHelper.makeAndLogPhoneCall(context: context, phoneNumber: value, customer: tempCustomer);
              },
              tooltip: 'โทร',
            ),
          IconButton(
            icon: Icon(Icons.print_outlined, color: Colors.blue.shade700),
            onPressed: onPrint,
            tooltip: 'พิมพ์รายงานรีเบท',
          ),
        ],
      ),
    );
  }
}

class _YearlySummaryCard extends StatelessWidget {
  final RebateData rebate;
  final NumberFormat currencyFormat;
  final DateTime selectedYear;

  const _YearlySummaryCard({required this.rebate, required this.currencyFormat, required this.selectedYear});

  @override
  Widget build(BuildContext context) {
    final totalActual = [
      rebate.salesJan, rebate.salesFeb, rebate.salesMar, rebate.salesApr,
      rebate.salesMay, rebate.salesJun, rebate.salesJul, rebate.salesAug,
      rebate.salesSep, rebate.salesOct, rebate.salesNov, rebate.salesDec
    ].reduce((a, b) => a + b);

    return Card(
      color: Colors.indigo.shade50,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("สรุปยอดรวมปี ${selectedYear.year + 543}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo)),
            const SizedBox(height: 8),
            _buildSummaryRow("ยอดขายรวม:", totalActual),
            _buildSummaryRow("เป้า 9 เดือน:", rebate.nineMonthTarget),
            _buildSummaryRow("สมนาคุณ:", rebate.bonus, isTotal: true),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String title, double value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(fontSize: 14, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal)),
          Text(
            currencyFormat.format(value),
            style: TextStyle(fontSize: 16, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal, color: isTotal ? Colors.purple : Colors.black87),
          ),
        ],
      ),
    );
  }
}

class _RebateMonthCard extends StatelessWidget {
  final String month;
  final double salesActual;
  final double monthlyTarget;
  final double percentage;
  final NumberFormat currencyFormat;

  const _RebateMonthCard({
    required this.month,
    required this.salesActual,
    required this.monthlyTarget,
    required this.percentage,
    required this.currencyFormat,
  });

  // --- WIDGET UPDATED ---
  Widget _buildCustomProgressBar(double percentage) {
    final achievedPercent = percentage.clamp(0.0, 100.0);
    final shortfallPercent = 100.0 - achievedPercent;

    return SizedBox(
        height: 22,
        child: Stack(
            children: [
                // Background (Shortfall color)
                Container(
                    decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                    ),
                ),
                // Foreground (Achieved color)
                FractionallySizedBox(
                    widthFactor: achievedPercent / 100,
                    child: Container(
                        decoration: BoxDecoration(
                            color: percentage >= 100 ? Colors.green : Colors.orange,
                            borderRadius: BorderRadius.circular(10),
                        ),
                    ),
                ),
                // Text labels
                Center(
                    child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              shadows: [Shadow(color: Colors.black, blurRadius: 5, offset: Offset(0,0))],
                            ),
                            children: percentage >= 100
                                ? [
                                    TextSpan(
                                      text: '${percentage.toStringAsFixed(2)}%',
                                      style: TextStyle(color: Colors.amberAccent),
                                    ),
                                  ]
                                : [
                                    TextSpan(
                                      text: '${achievedPercent.toStringAsFixed(2)}%',
                                      style: TextStyle(color: Colors.amberAccent),
                                    ),
                                    const TextSpan(
                                      text: ' | ',
                                      style: TextStyle(color: Colors.yellow),
                                    ),
                                    TextSpan(
                                      text: '${shortfallPercent.toStringAsFixed(2)}%',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ],
                          ),
                        ),
                    ),
                ),
            ],
        ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double shortfall = monthlyTarget - salesActual;
    final double surplus = salesActual - monthlyTarget; // New calculation

    final Color cardColor;
    final Widget statusWidget;

    if (percentage >= 100) {
      cardColor = Colors.green.shade50;
      statusWidget = Text("ถึงเป้าหมายที่กำหนด", style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.bold, fontSize: 14));
    } else {
      cardColor = Colors.red.shade50;
      statusWidget = Text("ไม่ถึงเป้าหมายที่กำหนด", style: TextStyle(color: Colors.red.shade800, fontSize: 14));
    }

    return Card(
      color: cardColor,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(month, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo)),
                statusWidget,
              ],
            ),
            const SizedBox(height: 12),
            
            // Using the new custom progress bar
            _buildCustomProgressBar(percentage),

            const SizedBox(height: 12),

            _buildTargetRow('เป้า/เดือน:', currencyFormat.format(monthlyTarget), Colors.blue.shade800),
            _buildTargetRow('ยอดขาย:', currencyFormat.format(salesActual), Colors.green.shade800),
            _buildTargetRow('ขาดอีก:', currencyFormat.format(shortfall > 0 ? shortfall : 0), Colors.red),
            
            // Conditionally display the surplus row
            if (surplus > 0)
              _buildTargetRow('ยอดเกิน:', currencyFormat.format(surplus), Colors.green.shade900, isBold: true),
          ],
        ),
      ),
    );
  }

  // Modified to accept a bold flag
  Widget _buildTargetRow(String title, String value, Color valueColor, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 16)),
          Text(
            value,
            style: TextStyle(fontSize: 16, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: valueColor),
          ),
        ],
      ),
    );
  }
}
