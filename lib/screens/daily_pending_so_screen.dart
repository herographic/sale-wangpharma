// lib/screens/daily_pending_so_screen.dart

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:math';
import 'package:intl/intl.dart';
import 'package:salewang/models/daily_so.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:salewang/models/customer.dart';
import 'package:salewang/models/new_arrival.dart';
import 'package:salewang/models/product.dart';
import 'package:salewang/utils/date_helper.dart';
import 'package:salewang/utils/launcher_helper.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// Helper class to hold combined and aggregated data for a single customer
class AggregatedDailySO {
  final Customer? customer;
  final String customerCode;
  final List<String> soCodes;
  final List<DailySO> sourceSOs;
  final double totalSumPrice;
  final Map<String, SOProduct> aggregatedProducts;
  final Map<String, int> productSourceSoCount; // How many SOs a product appears in
  final Map<String, Product?> productDetails;
  final Map<String, NewArrival?> arrivals;

  AggregatedDailySO({
    this.customer,
    required this.customerCode,
    required this.soCodes,
    required this.sourceSOs,
    required this.totalSumPrice,
    required this.aggregatedProducts,
    required this.productSourceSoCount,
    required this.productDetails,
    required this.arrivals,
  });
}

class DailyPendingSoScreen extends StatefulWidget {
  const DailyPendingSoScreen({super.key});

  @override
  State<DailyPendingSoScreen> createState() => _DailyPendingSoScreenState();
}

class _DailyPendingSoScreenState extends State<DailyPendingSoScreen> {
  List<AggregatedDailySO> _aggregatedSoList = [];
  bool _isLoading = true;
  String? _errorMessage;
  DateTime _selectedDate = DateTime.now();
  final Set<String> _clearedProductIds = {};
  final String _currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _fetchAndEnrichData();
  }

  Future<void> _fetchAndEnrichData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final String soDate = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final String arrivalStartDate =
          DateFormat('yyyy-MM-dd').format(_selectedDate.subtract(const Duration(days: 1)));
      final String arrivalEndDate =
          DateFormat('yyyy-MM-dd').format(_selectedDate.add(const Duration(days: 1)));

      const String bearerToken =
          'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJtZW1fY29kZSI6Ii4wNjM1In0.5U_Yle8l5bZqOVTxqlvQo36XyQaW2bf3Q-h91bw3UL8';

      final soUrl = Uri.parse(
          'https://www.wangpharma.com/API/appV3/so_list.php?start=$soDate&end=$soDate&limit=1000&offset=0');
      final soResponse =
          await http.get(soUrl, headers: {'Authorization': 'Bearer $bearerToken'});

      if (soResponse.statusCode != 200 && soResponse.statusCode != 404) {
        throw Exception('SO API Error: ${soResponse.statusCode}');
      }
      List<DailySO> soList =
          soResponse.statusCode == 200 ? dailySOFromJson(soResponse.body) : [];

      if (soList.isEmpty) {
        setState(() {
          _aggregatedSoList = [];
          _isLoading = false;
        });
        return;
      }

      // Filter to only 40 unique so_memcode (customer) per day
      final Set<String> allowedMemcodes = {};
      for (final so in soList) {
        final mem = so.soMemcode;
        if (mem != null && allowedMemcodes.length < 40) {
          allowedMemcodes.add(mem);
        }
        if (allowedMemcodes.length >= 40) break;
      }
      // Keep all SOs that belong to the first 40 unique memcodes
      final List<DailySO> filteredSoList = soList
          .where((so) => so.soMemcode != null && allowedMemcodes.contains(so.soMemcode))
          .toList();

      Map<String, AggregatedDailySO> aggregationMap = {};
      for (var so in filteredSoList) {
        if (so.soMemcode == null) continue;

        aggregationMap.putIfAbsent(
            so.soMemcode!,
            () => AggregatedDailySO(
                  customerCode: so.soMemcode!,
                  sourceSOs: [],
                  soCodes: [],
                  totalSumPrice: 0,
                  aggregatedProducts: {},
                  productSourceSoCount: {},
                  productDetails: {},
                  arrivals: {},
                ));

        final entry = aggregationMap[so.soMemcode!]!;

        entry.sourceSOs.add(so);
        final currentPrice =
            double.tryParse(so.soSumprice?.replaceAll(',', '') ?? '0') ?? 0;
        final newTotalPrice = entry.totalSumPrice + currentPrice;

        for (var product in so.soProduct) {
          if (product.proCode == null) continue;
          entry.productSourceSoCount[product.proCode!] =
              (entry.productSourceSoCount[product.proCode] ?? 0) + 1;

          if (entry.aggregatedProducts.containsKey(product.proCode)) {
            final existingProduct = entry.aggregatedProducts[product.proCode!]!;
            final existingAmount =
                double.tryParse(existingProduct.proAmount ?? '0') ?? 0;
            final newAmount = double.tryParse(product.proAmount ?? '0') ?? 0;
            final totalAmount = existingAmount + newAmount;

            entry.aggregatedProducts[product.proCode!] = SOProduct(
              proCode: product.proCode,
              proName: product.proName,
              proAmount: totalAmount.toString(),
              proUnit: product.proUnit,
              proPriceUnit: product.proPriceUnit,
              proDiscount: product.proDiscount,
              proPrice: product.proPrice,
            );
          } else {
            entry.aggregatedProducts[product.proCode!] = product;
          }
        }

        aggregationMap[so.soMemcode!] = AggregatedDailySO(
          customerCode: entry.customerCode,
          sourceSOs: entry.sourceSOs,
          soCodes: entry.sourceSOs.map((e) => e.soCode!).toSet().toList(),
          totalSumPrice: newTotalPrice,
          aggregatedProducts: entry.aggregatedProducts,
          productSourceSoCount: entry.productSourceSoCount,
          productDetails: entry.productDetails,
          arrivals: entry.arrivals,
          customer: entry.customer,
        );
      }

      final arrivalUrl = Uri.parse(
          'https://www.wangpharma.com/API/appV3/recive_list.php?start=$arrivalStartDate&end=$arrivalEndDate&limit=1000&offset=0');
      final arrivalResponse = await http
          .get(arrivalUrl, headers: {'Authorization': 'Bearer $bearerToken'});

      final Map<String, NewArrival> arrivalMap = {};
      if (arrivalResponse.statusCode == 200) {
        final arrivals = newArrivalFromJson(arrivalResponse.body);
        for (var arrival in arrivals) {
          arrivalMap[arrival.poiPcode] = arrival;
        }
      }

  // Fetch cleared statuses; support both String and Timestamp schema for 'clearedDate'
  QuerySnapshot<Map<String, dynamic>> clearedSnapshot;
  try {
    clearedSnapshot = await FirebaseFirestore.instance
    .collection('daily_so_cleared_status')
    .where('userId', isEqualTo: _currentUserId)
    .where('clearedDate', isEqualTo: soDate)
    .get();
  } catch (_) {
    // Fallback: treat clearedDate as Timestamp in [startOfDay, endOfDay)
    final startOfDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    clearedSnapshot = await FirebaseFirestore.instance
    .collection('daily_so_cleared_status')
    .where('userId', isEqualTo: _currentUserId)
    .where('clearedDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
    .where('clearedDate', isLessThan: Timestamp.fromDate(endOfDay))
    .get();
  }

      _clearedProductIds.clear();
      for (var doc in clearedSnapshot.docs) {
        _clearedProductIds.add(doc.id);
      }

      final Set<String> customerCodes = aggregationMap.keys.toSet();
      final Set<String> productCodes = aggregationMap.values
          .expand((agg) => agg.aggregatedProducts.keys)
          .toSet();

      final Map<String, Customer> customerMap = {};
      if (customerCodes.isNotEmpty) {
        List<String> customerCodeList = customerCodes.toList();
        for (int i = 0; i < customerCodeList.length; i += 10) {
          final chunk = customerCodeList.sublist(
              i,
              i + 10 > customerCodeList.length
                  ? customerCodeList.length
                  : i + 10);
          if (chunk.isNotEmpty) {
            final customerSnapshot = await FirebaseFirestore.instance
                .collection('customers')
                .where('รหัสลูกค้า', whereIn: chunk)
                .get();
            for (var doc in customerSnapshot.docs) {
              final customer = Customer.fromFirestore(doc);
              customerMap[customer.customerId] = customer;
            }
          }
        }
      }

      final Map<String, Product> productMap = {};
      if (productCodes.isNotEmpty) {
        List<String> productCodeList = productCodes.toList();
        for (int i = 0; i < productCodeList.length; i += 10) {
          final chunk = productCodeList.sublist(
              i,
              i + 10 > productCodeList.length
                  ? productCodeList.length
                  : i + 10);
          if (chunk.isNotEmpty) {
      // Query by field 'รหัสสินค้า' instead of documentId to support codes containing '/'
      final productSnapshot = await FirebaseFirestore.instance
        .collection('products')
        .where('รหัสสินค้า', whereIn: chunk)
        .get();
            for (var doc in productSnapshot.docs) {
              final product = Product.fromFirestore(doc);
              productMap[product.id] = product;
            }
          }
        }
      }

      final List<AggregatedDailySO> enrichedList = [];
      for (var entry in aggregationMap.values) {
        enrichedList.add(AggregatedDailySO(
          customerCode: entry.customerCode,
          customer: customerMap[entry.customerCode],
          sourceSOs: entry.sourceSOs,
          soCodes: entry.soCodes,
          totalSumPrice: entry.totalSumPrice,
          aggregatedProducts: entry.aggregatedProducts,
          productSourceSoCount: entry.productSourceSoCount,
          productDetails: {
            for (var code in entry.aggregatedProducts.keys) code: productMap[code]
          },
          arrivals: {
            for (var code in entry.aggregatedProducts.keys)
              code: arrivalMap[code]
          },
        ));
      }

      enrichedList.sort((a, b) {
        final bool aHasArrivals =
            a.arrivals.values.any((arrival) => arrival != null);
        final bool bHasArrivals =
            b.arrivals.values.any((arrival) => arrival != null);

        if (aHasArrivals && !bHasArrivals) {
          return -1;
        } else if (!aHasArrivals && bHasArrivals) {
          return 1;
        } else {
          return (a.customer?.name ?? a.customerCode)
              .compareTo(b.customer?.name ?? b.customerCode);
        }
      });

      setState(() {
        _aggregatedSoList = enrichedList;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'ไม่สามารถโหลดข้อมูลได้: $e';
        _isLoading = false;
      });
    }
  }

  void _toggleClearedStatus(String customerCode, String proCode) {
    final uniqueId =
        '$customerCode-$proCode-${DateFormat('yyyy-MM-dd').format(_selectedDate)}';
    final isCleared = _clearedProductIds.contains(uniqueId);
    final docRef = FirebaseFirestore.instance
        .collection('daily_so_cleared_status')
        .doc(uniqueId);

    setState(() {
      if (isCleared) {
        _clearedProductIds.remove(uniqueId);
        docRef.delete();
      } else {
        _clearedProductIds.add(uniqueId);
        docRef.set({
          'userId': _currentUserId,
          'clearedAt': Timestamp.now(),
          'clearedDate': DateFormat('yyyy-MM-dd').format(_selectedDate),
        });
      }
    });
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 3)),
      lastDate: DateTime.now(),
      locale: const Locale('th', 'TH'),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _fetchAndEnrichData();
    }
  }

  void _callCustomer(Customer? customer) {
    if (customer == null || customer.contacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่มีข้อมูลเบอร์โทรศัพท์')));
      return;
    }
    LauncherHelper.makeAndLogPhoneCall(
        context: context,
        phoneNumber: customer.contacts.first['phone']!,
        customer: customer);
  }

  void _shareReport(AggregatedDailySO aggregatedSO) {
    final currencyFormat = NumberFormat("#,##0.00", "en_US");

    String shareText =
        '📦 รายการค้างส่ง ${aggregatedSO.customer?.name ?? ""} (รหัสลูกค้า: ${aggregatedSO.customerCode})\n';

    DateTime? earliestDate;
    for (var so in aggregatedSO.sourceSOs) {
      final date = DateTime.tryParse(so.soDate ?? '');
      if (date != null && (earliestDate == null || date.isBefore(earliestDate))) {
        earliestDate = date;
      }
    }

    shareText +=
        'เลขคำสั่งซื้อ : ${aggregatedSO.soCodes.join(", ")} (วันที่ ${earliestDate != null ? DateFormat('dd ส.ค. yyyy', 'th_TH').format(earliestDate) : '-'})';

    aggregatedSO.aggregatedProducts.forEach((proCode, product) {
      final productDetails = aggregatedSO.productDetails[proCode];
      final arrivalDetails = aggregatedSO.arrivals[proCode];
      double pricePerUnit = 0;
      if (productDetails != null &&
          aggregatedSO.customer != null &&
          product.proUnit != null) {
        pricePerUnit =
            _calculatePricePerUnit(productDetails, aggregatedSO.customer!, product.proUnit!);
      }
      final totalAmount =
          pricePerUnit * (double.tryParse(product.proAmount ?? '0') ?? 0);

      shareText += '\n--------------\n'
          'สินค้า: ${product.proName}\n'
          'รหัสสินค้า : ${product.proCode}\n'
          'ค้างส่งคุณลูกค้า : จำนวน: ${double.tryParse(product.proAmount ?? '0')?.toStringAsFixed(0)} ${product.proUnit}\n'
          'ยอดเงิน : ${currencyFormat.format(totalAmount)} บาท';

      if (arrivalDetails != null) {
        final arrivalQty =
            double.tryParse(arrivalDetails.poiAmount)?.toStringAsFixed(0);
        shareText += '\n--------------\n'
            '📦 สินค้าเข้าแล้วจ้า จำนวน $arrivalQty ${arrivalDetails.poiUnit}\n'
            'คุณลูกค้า ต้องการให้ดำเนินการจัดส่งให้เลยไหมคะ?\n'
            'กรุณาแจ้งกลับมาได้เลยค่ะ 😊';
      }
    });

    Share.share(shareText);
  }

  Future<void> _printReport(AggregatedDailySO aggregatedSO) async {
    final doc = pw.Document();
    final font = await PdfGoogleFonts.promptBold();
    final fontRegular = await PdfGoogleFonts.promptRegular();
    final currencyFormat = NumberFormat("#,##0.00", "en_US");

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (pw.Context context) {
          return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('บริษัท วังเภสัชฟาร์มาซูติคอล จำกัด',
                    style: pw.TextStyle(font: font, fontSize: 16)),
                pw.Text(
                    '23 ซ.พัฒโน ถ.อนุสรณ์อาจาร์ยทอง อ.หาดใหญ่ จ.สงขลา 90110',
                    style: pw.TextStyle(font: fontRegular, fontSize: 10)),
                pw.Divider(height: 10),
                pw.Text(
                    'สรุปรายการ SO ค้างส่ง ประจำวันที่ ${DateFormat('d MMMM yyyy', 'th_TH').format(_selectedDate)}',
                    style: pw.TextStyle(font: font, fontSize: 18)),
                pw.SizedBox(height: 10),
                pw.Text(
                    'ลูกค้า: ${aggregatedSO.customer?.name ?? aggregatedSO.customerCode}',
                    style: pw.TextStyle(font: fontRegular, fontSize: 12)),
                pw.Text('เลขที่ SO: ${aggregatedSO.soCodes.join(", ")}',
                    style: pw.TextStyle(font: fontRegular, fontSize: 10)),
                pw.Divider(height: 20),
              ]);
        },
        build: (pw.Context context) {
          return [
            pw.Table.fromTextArray(
                headers: [
                  'รายการ',
                  'สต็อก',
                  'ของเข้า',
                  'จำนวน',
                  'ราคา/หน่วย',
                  'รวม',
                  'สถานะ'
                ],
                data: aggregatedSO.aggregatedProducts.values.map((p) {
                  final productInfo = aggregatedSO.productDetails[p.proCode];
                  final arrivalInfo = aggregatedSO.arrivals[p.proCode];
                  final stock = productInfo != null
                      ? '${productInfo.stockQuantity.toInt()} ${productInfo.unit1}'
                      : 'N/A';
          final arrival = arrivalInfo != null
            ? '${(double.tryParse(arrivalInfo.poiAmount) ?? 0).toInt()} ${arrivalInfo.poiUnit}'
            : '-';

                  double pricePerUnit = 0;
                  if (productInfo != null &&
                      aggregatedSO.customer != null &&
                      p.proUnit != null) {
                    pricePerUnit = _calculatePricePerUnit(
                        productInfo, aggregatedSO.customer!, p.proUnit!);
                  }
                  final totalAmount =
                      pricePerUnit * (double.tryParse(p.proAmount ?? '0') ?? 0);

                  final uniqueId =
                      '${aggregatedSO.customerCode}-${p.proCode}-${DateFormat('yyyy-MM-dd').format(_selectedDate)}';
                  final status =
                      _clearedProductIds.contains(uniqueId) ? 'เคลียร์แล้ว' : 'ยังไม่เคลียร์';

                  return [
                    p.proName,
                    stock,
                    arrival,
                    '${double.tryParse(p.proAmount ?? '0')?.toInt()} ${p.proUnit}',
                    currencyFormat.format(pricePerUnit),
                    currencyFormat.format(totalAmount),
                    status
                  ];
                }).toList(),
                headerStyle: pw.TextStyle(font: font, fontSize: 9),
                cellStyle: pw.TextStyle(font: fontRegular, fontSize: 9),
                border: pw.TableBorder.all(),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(1),
                  2: const pw.FlexColumnWidth(1),
                  3: const pw.FlexColumnWidth(1),
                  4: const pw.FlexColumnWidth(1),
                  5: const pw.FlexColumnWidth(1),
                  6: const pw.FlexColumnWidth(1),
                },
                cellAlignments: {
                  1: pw.Alignment.center,
                  2: pw.Alignment.center,
                  3: pw.Alignment.centerRight,
                  4: pw.Alignment.centerRight,
                  5: pw.Alignment.centerRight,
                  6: pw.Alignment.center,
                }),
          ];
        },
      ),
    );
    await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save());
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
          title: const Text('SO ค้างรายวัน',
              style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
        body: Column(
          children: [
            _buildDateSelector(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildDateSelector() {
    final thaiDateFormat = DateFormat('d MMMM yyyy', 'th_TH');
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ElevatedButton.icon(
        icon: const Icon(Icons.calendar_today),
        label: Text(thaiDateFormat.format(_selectedDate)),
        onPressed: () => _selectDate(context),
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 48),
          backgroundColor: Colors.white,
          foregroundColor: Theme.of(context).primaryColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_errorMessage != null) {
      return Center(
          child: Text(_errorMessage!,
              style: const TextStyle(color: Colors.white)));
    }
    if (_aggregatedSoList.isEmpty) {
      return const Center(
          child: Text('ไม่พบข้อมูล SO ค้างส่งในวันที่เลือก',
              style: TextStyle(color: Colors.white)));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      itemCount: _aggregatedSoList.length,
      itemBuilder: (context, index) {
        return _soCard(_aggregatedSoList[index]);
      },
    );
  }

  Widget _soCard(AggregatedDailySO aggregatedSO) {
    final customer = aggregatedSO.customer;
    final customerDisplayName = customer != null
        ? customer.name
        : 'ลูกค้า: ${aggregatedSO.customerCode}';

    final bool hasArrivals =
        aggregatedSO.arrivals.values.any((arrival) => arrival != null);

    // --- UPDATED: Safer province extraction logic ---
    String province = 'N/A';
    if (customer?.address2 != null && customer!.address2.isNotEmpty) {
      final parts = customer.address2.split(' ');
      if (parts.isNotEmpty) {
        province = parts.last;
      }
    }
    final salesperson = customer?.salesperson ?? 'N/A';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: hasArrivals ? Colors.amber.shade100 : null,
      child: ExpansionTile(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              customerDisplayName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            // --- UPDATED: Changed display format for customer code ---
            Text(
              'รหัสลูกค้า : ${aggregatedSO.customerCode}',
              style: TextStyle(color: Colors.grey.shade800, fontSize: 13),
            ),
          ],
        ),
        // --- UPDATED: Changed "เส้นทาง" to "จังหวัด" ---
        subtitle: Text(
          'จังหวัด: $province / ผู้ดูแล: $salesperson',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          '${NumberFormat("#,##0.00").format(aggregatedSO.totalSumPrice)} บาท',
          style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green),
        ),
        children: [
          ...aggregatedSO.aggregatedProducts.values.map((product) {
            final uniqueId =
                '${aggregatedSO.customerCode}-${product.proCode}-${DateFormat('yyyy-MM-dd').format(_selectedDate)}';
            final isCleared = _clearedProductIds.contains(uniqueId);
            return _buildProductTile(
                product: product,
                productDetails: aggregatedSO.productDetails[product.proCode],
                arrivalDetails: aggregatedSO.arrivals[product.proCode],
                customer: customer,
                sourceSoCount:
                    aggregatedSO.productSourceSoCount[product.proCode] ?? 1,
                isCleared: isCleared,
                onConfirm: () => _toggleClearedStatus(
                    aggregatedSO.customerCode, product.proCode!));
          }),
          const Divider(height: 1),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: OverflowBar(
              alignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton.icon(
                    icon: const Icon(Icons.call, size: 20),
                    label: const Text('โทร'),
                    onPressed: () => _callCustomer(customer)),
                TextButton.icon(
                    icon: const Icon(Icons.print, size: 20),
                    label: const Text('พิมพ์'),
                    onPressed: () => _printReport(aggregatedSO)),
                TextButton.icon(
                    icon: const Icon(Icons.share, size: 20),
                    label: const Text('แชร์'),
                    onPressed: () => _shareReport(aggregatedSO)),
              ],
            ),
          )
        ],
      ),
    );
  }

  double _calculatePricePerUnit(
      Product product, Customer customer, String unitName) {
    double getBasePrice() {
      switch (customer.p.toUpperCase()) {
        case 'B':
          return product.priceB;
        case 'C':
          return product.priceC;
        default:
          return product.priceA;
      }
    }

    final allUnits = [
      {'name': product.unit1, 'ratio': product.ratio1},
      {'name': product.unit2, 'ratio': product.ratio2},
      {'name': product.unit3, 'ratio': product.ratio3},
    ];

    final validUnits = allUnits
        .where((u) => (u['name'] as String).isNotEmpty && (u['ratio'] as double) > 0)
        .toList();
    if (validUnits.isEmpty) return 0.0;

    double maxRatio =
        validUnits.map((u) => u['ratio'] as double).reduce(max);
    final selectedUnitData = validUnits.firstWhere(
        (u) => u['name'] == unitName,
        orElse: () => validUnits.first);
    final multiplier = maxRatio / (selectedUnitData['ratio'] as double);

    return getBasePrice() * multiplier;
  }

  Widget _buildProductTile(
      {required SOProduct product,
      required Product? productDetails,
      required NewArrival? arrivalDetails,
      required Customer? customer,
      required int sourceSoCount,
      required bool isCleared,
      required VoidCallback onConfirm}) {
    final currencyFormat = NumberFormat("#,##0.00", "en_US");
    final stockInfo = productDetails != null
        ? 'คงเหลือ: ${productDetails.stockQuantity.toStringAsFixed(0)} ${productDetails.unit1}'
        : 'คงเหลือ: ?';

    final arrivalDate =
        arrivalDetails != null ? DateHelper.formatDateToThai(arrivalDetails.poiDate) : null;
    final arrivalQty = arrivalDetails != null
        ? double.tryParse(arrivalDetails.poiAmount)?.toStringAsFixed(0)
        : null;
    final arrivalUnit = arrivalDetails?.poiUnit;

    double pricePerUnit = 0;
    if (productDetails != null && customer != null && product.proUnit != null) {
      pricePerUnit =
          _calculatePricePerUnit(productDetails, customer, product.proUnit!);
    }

    final totalAmount =
        pricePerUnit * (double.tryParse(product.proAmount ?? '0') ?? 0);
    final aggregationText = sourceSoCount > 1 ? ' (ค้าง $sourceSoCount ใบ)' : '';

    return Container(
      color: isCleared ? Colors.green.shade50 : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (arrivalDetails != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: Chip(
                label: const Text('สินค้าเข้าแล้ววันนี้'),
                backgroundColor: Colors.red,
                labelStyle: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                visualDensity: VisualDensity.compact,
              ),
            ),
          Text(product.proName ?? 'N/A',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('รหัส: ${product.proCode} | $stockInfo',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          if (arrivalDetails != null)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                'ซื้อเข้าวันที่ $arrivalDate | จำนวน $arrivalQty $arrivalUnit',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue.shade800,
                    fontWeight: FontWeight.bold),
              ),
            ),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              InkWell(
                onTap: onConfirm,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4.0, vertical: 2.0),
                  child: Column(
                    children: [
                      Icon(
                        isCleared
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        color: isCleared ? Colors.green : Colors.grey,
                        size: 24,
                      ),
                      const SizedBox(width: 4),
                      Text("ยืนยัน",
                          style: TextStyle(
                              color: isCleared ? Colors.green : Colors.grey,
                              fontSize: 12))
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                        'จำนวน ${double.tryParse(product.proAmount ?? '0')?.toStringAsFixed(0)} ${product.proUnit}$aggregationText',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                    if (pricePerUnit > 0)
                      Text('ราคา ${currencyFormat.format(pricePerUnit)} บาท',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade800)),
                  ],
                ),
              ),
              SizedBox(
                width: 80,
                child: Text(
                    '${currencyFormat.format(totalAmount)} บาท',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.green)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
