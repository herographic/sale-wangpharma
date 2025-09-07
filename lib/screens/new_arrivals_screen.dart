// lib/screens/new_arrivals_screen.dart

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:salewang/models/customer.dart';
import 'package:salewang/models/new_arrival.dart';
import 'package:salewang/models/sales_order.dart';
import 'package:salewang/models/daily_so.dart';
import 'package:salewang/utils/date_helper.dart';
import 'package:salewang/utils/launcher_helper.dart';
import 'package:share_plus/share_plus.dart';
import 'package:collection/collection.dart';

// Enum for view filtering
enum ArrivalFilter { today, pendingSO }

// Model to hold combined SO and Customer data for the arrival card
class PendingSOInfo {
  final SalesOrder order;
  final Customer customer;

  PendingSOInfo({required this.order, required this.customer});
}

class NewArrivalsScreen extends StatefulWidget {
  const NewArrivalsScreen({super.key});

  @override
  State<NewArrivalsScreen> createState() => _NewArrivalsScreenState();
}

class _NewArrivalsScreenState extends State<NewArrivalsScreen> {
  List<NewArrival> _allArrivals = [];
  Map<String, List<PendingSOInfo>> _pendingOrdersMap = {};
  final Set<String> _clearedOrderIds = {};
  final String _currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

  bool _isLoading = true;
  String? _errorMessage;
  DateTime _selectedDate = DateTime.now();
  final TextEditingController _searchController = TextEditingController();
  final List<String> _forbiddenKeywords = const [
    'รีเบท', 'ส่งเสริมการขาย', '-', 'ค่าเชียร์', 'ฟรี'
  ];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetchNewArrivals(_selectedDate);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }
  
  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      // This will just filter the currently displayed list, not re-fetch
      setState(() {});
    });
  }

  Future<void> _fetchNewArrivals(DateTime date) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _allArrivals.clear();
      _pendingOrdersMap.clear();
      _clearedOrderIds.clear();
    });

  const String bearerToken = 'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJtZW1fY29kZSI6Ii4wNjM1In0.5U_Yle8l5bZqOVTxqlvQo36XyQaW2bf3Q-h91bw3UL8';
    final String formattedDate = DateFormat('yyyy-MM-dd').format(date);
    final url = Uri.parse('https://www.wangpharma.com/API/appV3/recive_list.php?start=$formattedDate&end=$formattedDate&limit=1000&offset=0');

    try {
      // 1. Fetch new arrivals from API
      final response = await http.get(url, headers: {'Authorization': 'Bearer $bearerToken'});
      if (response.statusCode != 200) {
        if (response.statusCode == 404) {
           setState(() {
            _allArrivals = [];
            _isLoading = false;
          });
          return;
        }
        throw Exception('API Error: ${response.statusCode}');
      }
      
      List<NewArrival> rawArrivals = newArrivalFromJson(response.body);
      
      List<NewArrival> validArrivals = rawArrivals.where((item) {
        final hasForbiddenKeyword = _forbiddenKeywords.any((keyword) => item.poiPname.trim().startsWith(keyword));
        final amount = double.tryParse(item.poiAmount) ?? 0.0;
        return amount > 0 && !hasForbiddenKeyword;
      }).toList();

      if (validArrivals.isEmpty) {
        setState(() {
          _allArrivals = [];
          _isLoading = false;
        });
        return;
      }

      // 2. Fetch pending Sales Orders from SO API (instead of Firestore)
      final productCodes = validArrivals.map((a) => a.poiPcode).toSet();
    final String soStartDate = DateFormat('yyyy-MM-dd').format(date.subtract(const Duration(days: 30)));
    final soUrl = Uri.parse(
      'https://www.wangpharma.com/API/appV3/so_list.php?start=$soStartDate&end=$formattedDate&limit=1000&offset=0');
      final soResponse = await http.get(soUrl, headers: {'Authorization': 'Bearer $bearerToken'});
      if (soResponse.statusCode != 200 && soResponse.statusCode != 404) {
        throw Exception('SO API Error: ${soResponse.statusCode}');
      }
      final List<DailySO> soList = soResponse.statusCode == 200
          ? dailySOFromJson(soResponse.body)
          : <DailySO>[];

      // Filter SOs that are related to today's arriving products
      // Deduplicate by (so_code|pro_code), sum quantities/amounts across duplicate lines in the same SO
      final Map<String, SalesOrder> combinedOrders = {};
      for (final so in soList) {
        if (so.soMemcode == null || so.soCode == null || so.soDate == null) continue;
        for (final p in so.soProduct) {
          if (p.proCode == null || p.proName == null) continue;
          if (!productCodes.contains(p.proCode)) continue;
          final qty = double.tryParse(p.proAmount ?? '0') ?? 0.0;
          final unitPrice = double.tryParse((p.proPriceUnit ?? '0').toString().replaceAll(',', '')) ?? 0.0;
          final lineAmount = double.tryParse((p.proPrice ?? '0').toString().replaceAll(',', '')) ?? (qty * unitPrice);
          final key = '${so.soCode}|${p.proCode}';
          if (combinedOrders.containsKey(key)) {
            final existing = combinedOrders[key]!;
            combinedOrders[key] = SalesOrder(
              id: existing.id,
              orderDate: existing.orderDate,
              cd: existing.cd,
              invoiceNumber: existing.invoiceNumber,
              customerId: existing.customerId,
              accountId: existing.accountId,
              dueDate: existing.dueDate,
              salesperson: existing.salesperson,
              productId: existing.productId,
              productDescription: existing.productDescription,
              quantity: existing.quantity + qty,
              unit: existing.unit.isNotEmpty ? existing.unit : (p.proUnit ?? ''),
              unitPrice: existing.unitPrice != 0 ? existing.unitPrice : unitPrice,
              discount: existing.discount,
              totalAmount: existing.totalAmount + lineAmount,
              clearedBy: existing.clearedBy,
            );
          } else {
            combinedOrders[key] = SalesOrder(
              id: key,
              orderDate: so.soDate ?? '',
              cd: '',
              invoiceNumber: so.soCode ?? '',
              customerId: so.soMemcode ?? '',
              accountId: '',
              dueDate: '',
              salesperson: '',
              productId: p.proCode ?? '',
              productDescription: p.proName ?? '',
              quantity: qty,
              unit: p.proUnit ?? '',
              unitPrice: unitPrice,
              discount: p.proDiscount ?? '',
              totalAmount: lineAmount,
              clearedBy: const [],
            );
          }
        }
      }
      final List<SalesOrder> allPendingSOs = combinedOrders.values.toList();

      // 3. Populate the cleared IDs set from 'daily_so_cleared_status' (by date & user)
      final clearedSnapshot = await FirebaseFirestore.instance
          .collection('daily_so_cleared_status')
          .where('userId', isEqualTo: _currentUserId)
          .where('clearedDate', isEqualTo: formattedDate)
          .get();
      for (final doc in clearedSnapshot.docs) {
        _clearedOrderIds.add(doc.id);
      }

      // 4. Fetch customer data for these SOs (Firestore)
      final customerIds = allPendingSOs.map((so) => so.customerId).toSet().toList();
      final Map<String, Customer> customerMap = {};
      for (var i = 0; i < customerIds.length; i += 10) {
        final chunk = customerIds.sublist(i, i + 10 > customerIds.length ? customerIds.length : i + 10);
        if (chunk.isNotEmpty) {
          final customerSnapshot = await FirebaseFirestore.instance.collection('customers').where('รหัสลูกค้า', whereIn: chunk).get();
          for (var doc in customerSnapshot.docs) {
            final customer = Customer.fromFirestore(doc);
            customerMap[customer.customerId] = customer;
          }
        }
      }

      // 5. Create the map of product codes to their pending orders with customer info
      final pendingMap = <String, List<PendingSOInfo>>{};
      for (final order in allPendingSOs) {
        final customer = customerMap[order.customerId];
        if (customer == null) continue;
        final list = pendingMap.putIfAbsent(order.productId, () => []);
        // Deduplicate by so_code (invoiceNumber) per product; keep first occurrence
        final hasSameSO = list.any((info) => info.order.invoiceNumber == order.invoiceNumber);
        if (!hasSameSO) {
          list.add(PendingSOInfo(order: order, customer: customer));
        }
      }

      // REQUIREMENT 3: Sort the arrivals list
      validArrivals.sort((a, b) {
        final aHasSO = pendingMap.containsKey(a.poiPcode);
        final bHasSO = pendingMap.containsKey(b.poiPcode);
        if (aHasSO && !bHasSO) return -1; // a comes first
        if (!aHasSO && bHasSO) return 1;  // b comes first
        return a.poiPcode.compareTo(b.poiPcode); // Otherwise, sort by product code
      });

  setState(() {
        _allArrivals = validArrivals;
        _pendingOrdersMap = pendingMap;
      });

    } catch (e) {
      setState(() => _errorMessage = 'การเชื่อมต่อล้มเหลว: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('th', 'TH'),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _fetchNewArrivals(_selectedDate);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Filter the list based on search query before building
    final query = _searchController.text.toLowerCase();
    final filteredArrivals = _allArrivals.where((arrival) {
      if (query.isEmpty) return true;
      final hasPendingMatch = _pendingOrdersMap[arrival.poiPcode]?.any((info) => 
        info.customer.name.toLowerCase().contains(query) || 
        info.customer.customerId.toLowerCase().contains(query)
      ) ?? false;
      return arrival.poiPname.toLowerCase().contains(query) ||
             arrival.poiPcode.toLowerCase().contains(query) ||
             hasPendingMatch;
    }).toList();

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
          title: const Text('สินค้าเข้าใหม่', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
        body: Column(
          children: [
            _buildControls(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _fetchNewArrivals(_selectedDate),
                child: _buildBody(filteredArrivals),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    final thaiDateFormat = DateFormat('d MMMM yyyy', 'th_TH');
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          ElevatedButton.icon(
            icon: const Icon(Icons.calendar_today),
            label: Text(thaiDateFormat.format(_selectedDate)),
            onPressed: () => _selectDate(context),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 40),
              backgroundColor: Colors.white,
              foregroundColor: Theme.of(context).primaryColor,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'ค้นหาสินค้า หรือ ลูกค้า...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
              prefixIcon: const Icon(Icons.search, color: Colors.white),
              filled: true,
              fillColor: Colors.black.withOpacity(0.2),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(List<NewArrival> filteredArrivals) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_errorMessage != null) {
      return Center(
        child: Text('เกิดข้อผิดพลาด:\n$_errorMessage', style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
      );
    }
    if (_allArrivals.isEmpty) {
      return const Center(child: Text('ไม่พบข้อมูลสินค้าเข้าในวันที่เลือก', style: TextStyle(color: Colors.white)));
    }
    if (filteredArrivals.isEmpty) {
      return const Center(child: Text('ไม่พบรายการที่ตรงกับการค้นหา', style: TextStyle(color: Colors.white)));
    }
    
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8.0, 0, 8.0, 8.0),
      itemCount: filteredArrivals.length,
      itemBuilder: (context, index) {
        final item = filteredArrivals[index];
        final pendingOrders = _pendingOrdersMap[item.poiPcode] ?? [];
        return ArrivalCard(
          key: ValueKey(item.poiPcode), // Use a unique key
          item: item,
          itemNumber: index + 1,
          pendingOrders: pendingOrders,
          clearedOrderIds: _clearedOrderIds,
          onClearToggle: (orderId) async {
            // Toggle cleared status in 'daily_so_cleared_status'
            setState(() {
              if (_clearedOrderIds.contains(orderId)) {
                _clearedOrderIds.remove(orderId);
              } else {
                _clearedOrderIds.add(orderId);
              }
            });
            final docRef = FirebaseFirestore.instance.collection('daily_so_cleared_status').doc(orderId);
            final exists = (await docRef.get()).exists;
            if (exists) {
              await docRef.delete();
            } else {
              await docRef.set({
                'userId': _currentUserId,
                'clearedDate': DateFormat('yyyy-MM-dd').format(_selectedDate),
              });
            }
          },
          onDelete: (orderId) async {
            // Treat delete as force-clear for API-based entries
            final confirm = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('ยืนยันการเคลียร์'),
                content: const Text('ทำเครื่องหมายรายการนี้ว่าเคลียร์แล้วใช่หรือไม่?'),
                actions: [
                  TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('ยกเลิก')),
                  FilledButton(onPressed: () => Navigator.of(context).pop(true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('ยืนยัน')),
                ],
              ),
            );
            if (confirm == true) {
              setState(() => _clearedOrderIds.add(orderId));
              await FirebaseFirestore.instance.collection('daily_so_cleared_status').doc(orderId).set({
                'userId': _currentUserId,
                'clearedDate': DateFormat('yyyy-MM-dd').format(_selectedDate),
              });
            }
          },
        );
      },
    );
  }
}

class ArrivalCard extends StatelessWidget {
  final NewArrival item;
  final int itemNumber;
  final List<PendingSOInfo> pendingOrders;
  final Set<String> clearedOrderIds;
  final Function(String) onClearToggle;
  final Function(String) onDelete;


  const ArrivalCard({
    super.key,
    required this.item,
    required this.itemNumber,
    required this.pendingOrders,
    required this.clearedOrderIds,
    required this.onClearToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat("#,##0.00", "en_US");
    final amount = double.tryParse(item.poiAmount) ?? 0.0;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$itemNumber. ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Expanded(
                  child: Text(
                    item.poiPname,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.share_outlined, size: 20),
                  onPressed: () {
                    Share.share('สินค้าเข้าใหม่: ${item.poiPname}\nรหัส: ${item.poiPcode}\nบาร์โค้ด: ${item.poiCode}');
                  },
                  tooltip: 'แชร์',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text('รหัสสินค้า: ${item.poiPcode}', style: const TextStyle(color: Colors.black54, fontSize: 12))),
                Text(
                  '${currencyFormat.format(amount)} ${item.poiUnit}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 14),
                ),
              ],
            ),
            if (pendingOrders.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 12.0),
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200)
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ลูกค้าที่ค้างส่ง:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
                    const SizedBox(height: 4),
                    ...pendingOrders.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final info = entry.value;
                      return PendingSOItem(
                        key: ValueKey('${info.order.id}#$idx'),
                        arrivalItem: item,
                        info: info,
                        isCleared: clearedOrderIds.contains(info.order.id),
                        onTap: () => onClearToggle(info.order.id),
                        onDelete: () => onDelete(info.order.id),
                      );
                    }),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Widget for displaying each pending SO line item
class PendingSOItem extends StatelessWidget {
  final PendingSOInfo info;
  final NewArrival arrivalItem; // Added to access arrival data
  final bool isCleared;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const PendingSOItem({
    super.key,
    required this.info,
    required this.arrivalItem,
    required this.isCleared,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat("#,##0.00", "en_US");

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        decoration: BoxDecoration(
          color: isCleared ? Colors.green.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '• ${info.customer.customerId} ${info.customer.name}',
              style: TextStyle(color: Colors.grey.shade800, fontSize: 13, fontWeight: FontWeight.bold),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 16.0, top: 4.0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // REQUIREMENT 2: Display SO date
                        Text(
                          'SO: ${info.order.invoiceNumber} (${DateHelper.formatDateToThai(info.order.orderDate)})',
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                        ),
                        Text(
                          'ค้าง ${info.order.quantity.toInt()} ${info.order.unit} | ฿${currencyFormat.format(info.order.totalAmount)}',
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  // REQUIREMENT 1: Action Buttons
                  _actionButton(Icons.call, Colors.green, 'โทร', () => LauncherHelper.makeAndLogPhoneCall(context: context, phoneNumber: info.customer.contacts.firstOrNull?['phone'] ?? '', customer: info.customer)),
                  _actionButton(Icons.print, Colors.blue, 'พิมพ์', () => _printSingleOrder(context, info)),
                  _actionButton(Icons.share, Colors.orange, 'แชร์', () => _shareSingleOrder(context, info)),
                  _actionButton(Icons.delete_outline, Colors.red, 'ลบ', onDelete),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(IconData icon, Color color, String tooltip, VoidCallback onPressed) {
    return IconButton(
      icon: Icon(icon, size: 20, color: color),
      onPressed: onPressed,
      tooltip: tooltip,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      constraints: const BoxConstraints(),
    );
  }

  // UPDATED SHARE FUNCTION
  void _shareSingleOrder(BuildContext context, PendingSOInfo info) {
    final currencyFormat = NumberFormat("#,##0.00", "en_US");
    final arrivalDate = DateHelper.formatDateToThai(arrivalItem.poiDate);
    final arrivalQty = double.tryParse(arrivalItem.poiAmount)?.toStringAsFixed(0) ?? '0';
    final arrivalUnit = arrivalItem.poiUnit;

    String shareText = '🎉 มีข่าวดีมาแจ้งคะ!\n'
        'สินค้าที่คุณลูกค้ารอเข้ามาแล้วเมื่อวันที่ $arrivalDate\n'
        '--------------\n'
        '📦 รายการค้างส่ง ${info.customer.name} (${info.customer.customerId})\n'
        'เลขคำสั่งซื้อ : ${info.order.invoiceNumber} (วันที่ ${DateHelper.formatDateToThai(info.order.orderDate)})\n'
        'สินค้า: ${info.order.productDescription}\n'
        'รหัสสินค้า : ${info.order.productId}\n'
        'ค้างส่งคุณลูกค้า : จำนวน: ${info.order.quantity.toInt()} ${info.order.unit}\n'
        'ยอดเงิน : ${currencyFormat.format(info.order.totalAmount)} บาท\n'
        '--------------\n'
        '📦 สินค้าเข้าแล้วจ้า จำนวน $arrivalQty $arrivalUnit\n'
        'คุณลูกค้า ต้องการให้ดำเนินการจัดส่งให้เลยไหมคะ?\n'
        'กรุณาแจ้งกลับมาได้เลยค่ะ 😊';
    Share.share(shareText);
  }

  Future<void> _printSingleOrder(BuildContext context, PendingSOInfo info) async {
    final doc = pw.Document();
    final font = await PdfGoogleFonts.promptBold();
    final fontRegular = await PdfGoogleFonts.promptRegular();
    final currencyFormat = NumberFormat("#,##0.00", "en_US");

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('รายการค้างส่ง (เฉพาะรายการ)', style: pw.TextStyle(font: font, fontSize: 18)),
              pw.Text('ลูกค้า: ${info.customer.name} (${info.customer.customerId})', style: pw.TextStyle(font: fontRegular, fontSize: 12)),
              pw.Divider(height: 20),
              pw.Text('สินค้า: ${info.order.productDescription}', style: pw.TextStyle(font: font, fontSize: 14)),
              pw.Text('รหัส: ${info.order.productId}', style: pw.TextStyle(font: fontRegular, fontSize: 10)),
              pw.SizedBox(height: 10),
              pw.Text('SO: ${info.order.invoiceNumber} วันที่: ${DateHelper.formatDateToThai(info.order.orderDate)}', style: pw.TextStyle(font: fontRegular, fontSize: 10)),
              pw.Text('จำนวน: ${info.order.quantity.toInt()} ${info.order.unit}', style: pw.TextStyle(font: fontRegular, fontSize: 10)),
              pw.Text('ยอดเงิน: ${currencyFormat.format(info.order.totalAmount)} บาท', style: pw.TextStyle(font: fontRegular, fontSize: 10)),
            ]
          );
        },
      ),
    );
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => doc.save());
  }
}
