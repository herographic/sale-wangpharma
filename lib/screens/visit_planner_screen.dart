// lib/screens/visit_planner_screen.dart

import 'dart:ui';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:salewang/models/customer.dart';
import 'package:salewang/models/visit_plan.dart';
import 'package:salewang/screens/visit_submit_screen.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

// Route code mapping for provinces
const Map<String, String> kRouteNameMap = {
  'L1-1': 'หาดใหญ่ 1',
  'L1-2': 'เมืองสงขลา',
  'L1-3': 'สะเดา',
  'L2': 'ปัตตานี',
  'L3': 'สตูล',
  'L4': 'พัทลุง',
  'L5-1': 'นราธิวาส',
  'L5-2': 'สุไหงโกลก',
  'L6': 'ยะลา',
  'L7': 'เบตง',
  'L9': 'ตรัง',
  'L10': 'นครศรีฯ',
  'Office': 'วังเภสัช',
  'R-00': 'อื่นๆ',
  'L1-5': 'สทิงพระ',
  'Logistic': 'ฝากขนส่ง',
  'L11': 'กระบี่',
  'L12': 'ภูเก็ต',
  'L13': 'สุราษฎร์ฯ',
  'L17': 'พังงา',
  'L16': 'ยาแห้ง',
  'L4-1': 'พัทลุง VIP',
  'L18': 'เกาะสมุย',
  'L19': 'พัทลุง-นคร',
  'L20': 'ชุมพร',
  'L9-11': 'กระบี่-ตรัง',
  'L21': 'เกาะลันตา',
  'L22': 'เกาะพะงัน',
  'L23': 'หาดใหญ่ 2',
};

class VisitPlannerScreen extends StatefulWidget {
  const VisitPlannerScreen({super.key});

  @override
  State<VisitPlannerScreen> createState() => _VisitPlannerScreenState();
}

class _VisitPlannerScreenState extends State<VisitPlannerScreen> {
  DateTime _selectedDay = DateTime.now();
  // Cached salespeople for assignment
  List<_Salesperson> _assignees = [];
  bool _loadingAssignees = false;
  // Cache customers to support substring search
  List<Customer>? _customersCache;
  bool _loadingCustomers = false;
  // Selection
  String? _selectedPlanId;
  DateTime? _selectedPendingDate; // chips for pending dates

  @override
  void initState() {
    super.initState();
  }

  // Removed old broad search; use _queryByCode/_queryByNamePrefix instead

  // New: precise Firestore-backed lookups
  Future<List<Customer>> _queryByCode(String code) async {
    final c = code.trim();
    if (c.isEmpty) return [];
    try {
      final snap = await FirebaseFirestore.instance
          .collection('customers')
          .where('รหัสลูกค้า', isEqualTo: c)
          .limit(5)
          .get();
      return snap.docs.map((d) => Customer.fromFirestore(d)).toList();
    } catch (_) {
      // Fallback to client filter
      final snap = await FirebaseFirestore.instance.collection('customers').limit(500).get();
      return snap.docs.map(Customer.fromFirestore).where((x) => x.customerId == c).toList();
    }
  }

  Future<List<Customer>> _queryByNamePrefix(String name) async {
    final n = name.trim();
    if (n.isEmpty) return [];
    try {
      final snap = await FirebaseFirestore.instance
          .collection('customers')
          .orderBy('ชื่อลูกค้า')
          .startAt([n])
          .endAt([n + '\uf8ff'])
          .limit(20)
          .get();
      return snap.docs.map((d) => Customer.fromFirestore(d)).toList();
    } catch (_) {
      // Fallback to client filter
      final snap = await FirebaseFirestore.instance.collection('customers').limit(500).get();
      return snap.docs
          .map(Customer.fromFirestore)
          .where((x) => x.name.toLowerCase().contains(n.toLowerCase()))
          .take(20)
          .toList();
    }
  }

  Future<Map<String, dynamic>?> _lastVisitOf(String customerId) async {
    final snap = await FirebaseFirestore.instance
        .collection('call_logs')
        .where('customerId', isEqualTo: customerId)
        .orderBy('callTimestamp', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return snap.docs.first.data();
  }

  Future<void> _pickDateTime() async {
    // First pick date
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime(2020), // Allow past dates
      lastDate: DateTime(2030),   // Allow future dates
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.blue,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null) {
      // Then pick time
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedDay),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(
                primary: Colors.blue,
                onPrimary: Colors.white,
                surface: Colors.white,
                onSurface: Colors.black,
              ),
            ),
            child: child!,
          );
        },
      );

      if (pickedTime != null) {
        // Combine date and time
        final DateTime newDateTime = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );

        setState(() {
          _selectedDay = newDateTime;
          if (_selectedPendingDate != null) {
            _selectedPendingDate = DateTime(newDateTime.year, newDateTime.month, newDateTime.day);
          }
        });
      }
    }
  }

  // Show customer list with trading history and mission creation
  Future<void> _showCustomerList() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.9,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0052D4), Color(0xFF4364F7), Color(0xFF6FB1FC)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: _CustomerListView(
          selectedDay: _selectedDay,
          assignees: _assignees,
          onEnsureAssigneesLoaded: _ensureAssigneesLoaded,
          glassWidget: _glass,
        ),
      ),
    );
  }

  Future<void> _ensureAssigneesLoaded() async {
    if (_loadingAssignees || _assignees.isNotEmpty) return;
    setState(() => _loadingAssignees = true);
    final snap = await FirebaseFirestore.instance.collection('salespeople').get();
    _assignees = [
      for (final d in snap.docs)
        _Salesperson(
          id: d.id,
          name: (d.data()['name'] ?? d.data()['displayName'] ?? d.data()['employeeName'] ?? d.id).toString(),
          code: (d.data()['employeeId'] ?? '').toString(),
        )
    ];
    setState(() => _loadingAssignees = false);
  }

  // Print pending missions report
  Future<void> _printPendingReport() async {
    try {
      final pendingPlans = await _getPendingPlansForDate(_selectedPendingDate ?? _selectedDay);
      if (pendingPlans.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่มีรายการที่ยังไม่ได้ส่งในวันที่เลือก')),
        );
        return;
      }

      final pdfBytes = await _generatePendingReportPDF(pendingPlans);
      await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => Uint8List.fromList(pdfBytes));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
      );
    }
  }

  // Share pending missions report
  Future<void> _sharePendingReport() async {
    try {
      final pendingPlans = await _getPendingPlansForDate(_selectedPendingDate ?? _selectedDay);
      if (pendingPlans.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่มีรายการที่ยังไม่ได้ส่งในวันที่เลือก')),
        );
        return;
      }

      // Show loading while generating detailed report
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กำลังเตรียมข้อมูลลูกค้า...')),
      );

      final reportText = await _generatePendingReportText(pendingPlans);
      await Share.share(reportText, subject: 'แผนการเยี่ยมลูกค้า');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
      );
    }
  }

  // Get pending plans for specific date
  Future<List<VisitPlan>> _getPendingPlansForDate(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    
    final snapshot = await FirebaseFirestore.instance
        .collection('visit_plans')
        .where('plannedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('plannedAt', isLessThan: Timestamp.fromDate(end))
        .get();

    // Filter only pending plans (plans that are not completed yet)
    final plans = snapshot.docs
        .map((doc) => VisitPlan.fromFirestore(doc))
        .where((plan) => plan.doneAt == null) // Only pending missions
        .toList();

    return plans;
  }

  // Generate PDF report
  Future<List<int>> _generatePendingReportPDF(List<VisitPlan> plans) async {
    final pdf = pw.Document();
    final dateStr = DateFormat('dd MMMM yyyy', 'th_TH').format(_selectedPendingDate ?? _selectedDay);
    
    // Load Thai font
    final fontData = await rootBundle.load('google_fonts/Kanit-Regular.ttf');
    final thaiFont = pw.Font.ttf(fontData);
    final boldFontData = await rootBundle.load('google_fonts/Kanit-Bold.ttf');
    final thaiBoldFont = pw.Font.ttf(boldFontData);
    
    // Group plans by route (using route_code from api_sale_support_cache)
    final routeGroups = <String, List<VisitPlan>>{};
    
    // Load route information for each plan
    for (final plan in plans) {
      try {
        // Get route code from api_sale_support_cache
        final customerDoc = await FirebaseFirestore.instance
            .collection('api_sale_support_cache')
            .doc(plan.customerId)
            .get();
        
        String routeKey = 'ไม่ระบุเส้นทาง';
        if (customerDoc.exists) {
          final data = customerDoc.data()!;
          final routeCode = data['route_code']?.toString();
          if (routeCode != null && routeCode.isNotEmpty) {
            // Use route name from mapping, fallback to route code if not found
            final routeName = kRouteNameMap[routeCode] ?? routeCode;
            routeKey = routeName;
          }
        }
        
        if (!routeGroups.containsKey(routeKey)) {
          routeGroups[routeKey] = [];
        }
        routeGroups[routeKey]!.add(plan);
      } catch (e) {
        // Fallback to unspecified route
        const fallbackKey = 'ไม่ระบุเส้นทาง';
        if (!routeGroups.containsKey(fallbackKey)) {
          routeGroups[fallbackKey] = [];
        }
        routeGroups[fallbackKey]!.add(plan);
      }
    }

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      'บริษัท วังเภสัชฟาร์มาซูติคอล จำกัด',
                      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, font: thaiBoldFont),
                    ),
                    pw.SizedBox(height: 5),
                    pw.Text(
                      '23 ซ.พัฒโน ถ.อนุสรณ์อาจาร์ยทอง อ.หาดใหญ่ จ.สงขลา 90110',
                      style: pw.TextStyle(fontSize: 12, font: thaiFont),
                    ),
                    pw.SizedBox(height: 20),
                    pw.Text(
                      'รายงานแผนการเยี่ยมลูกค้าแยกตามเส้นทาง',
                      style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, font: thaiBoldFont),
                    ),
                    pw.SizedBox(height: 5),
                    pw.Text(
                      'วันที่ $dateStr',
                      style: pw.TextStyle(fontSize: 14, font: thaiFont),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 30),
              
              // Summary section
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(5),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                  children: [
                    pw.Text(
                      'จำนวนเส้นทาง: ${routeGroups.length}',
                      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, font: thaiBoldFont),
                    ),
                    pw.Text(
                      'จำนวนร้านทั้งหมด: ${plans.length}',
                      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, font: thaiBoldFont),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
            ],
          );
        },
      ),
    );

    // Add route tables on separate pages
    for (final entry in routeGroups.entries) {
      final routeName = entry.key;
      final routePlans = entry.value;
      
      // Prepare table data with customer details
      final List<List<String>> tableData = [];
      for (int i = 0; i < routePlans.length; i++) {
        final plan = routePlans[i];
        final customerDetails = await _getCustomerDetailsForShare(plan.customerId);
        
        tableData.add([
          (i + 1).toString(),
          plan.customerId,
          plan.customerName.isNotEmpty ? plan.customerName : '-',
          customerDetails['address'] != '-' && customerDetails['address']!.isNotEmpty 
              ? customerDetails['address']! 
              : 'ไม่ระบุ',
          customerDetails['phone'] != '-' && customerDetails['phone']!.isNotEmpty 
              ? customerDetails['phone']! 
              : 'ไม่ระบุ',
          plan.assignedToName ?? 'ไม่ระบุ',
          plan.notes ?? '-',
        ]);
      }
      
      pdf.addPage(
        pw.Page(
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.blue100,
                    borderRadius: pw.BorderRadius.circular(5),
                  ),
                  child: pw.Row(
                    children: [
                      pw.Icon(pw.IconData(0xe0c8), size: 16, color: PdfColors.blue800), // location icon
                      pw.SizedBox(width: 8),
                      pw.Text(
                        'เส้นทาง: $routeName (${routePlans.length} ร้าน)',
                        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, font: thaiBoldFont, color: PdfColors.blue800),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 15),
                pw.Expanded(
                  child: pw.Table.fromTextArray(
                    headers: ['ลำดับ', 'รหัสลูกค้า', 'ชื่อลูกค้า', 'ที่อยู่', 'โทรศัพท์', 'ผู้รับผิดชอบ', 'หมายเหตุ'],
                    data: tableData,
                    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: thaiBoldFont, fontSize: 10),
                    cellStyle: pw.TextStyle(fontSize: 9, font: thaiFont),
                    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
                    cellAlignments: {
                      0: pw.Alignment.center,  // ลำดับ
                      1: pw.Alignment.center,  // รหัสลูกค้า
                      2: pw.Alignment.centerLeft,  // ชื่อลูกค้า
                      3: pw.Alignment.centerLeft,  // ที่อยู่
                      4: pw.Alignment.center,  // โทรศัพท์
                      5: pw.Alignment.centerLeft,  // ผู้รับผิดชอบ
                      6: pw.Alignment.centerLeft,  // หมายเหตุ
                    },
                    columnWidths: {
                      0: const pw.FixedColumnWidth(30),  // ลำดับ
                      1: const pw.FixedColumnWidth(60),  // รหัสลูกค้า
                      2: const pw.FlexColumnWidth(1.5), // ชื่อลูกค้า
                      3: const pw.FlexColumnWidth(2.5), // ที่อยู่
                      4: const pw.FixedColumnWidth(80),  // โทรศัพท์
                      5: const pw.FlexColumnWidth(1),   // ผู้รับผิดชอบ
                      6: const pw.FlexColumnWidth(1),   // หมายเหตุ
                    },
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Divider(),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'พิมพ์เมื่อ: ${DateFormat('dd/MM/yyyy HH:mm', 'th_TH').format(DateTime.now())}',
                      style: pw.TextStyle(fontSize: 10, font: thaiFont, color: PdfColors.grey700),
                    ),
                    pw.Text(
                      'เส้นทาง: $routeName',
                      style: pw.TextStyle(fontSize: 10, font: thaiFont, color: PdfColors.grey700),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );
    }

    return pdf.save();
  }

  // Generate text report for sharing
  Future<String> _generatePendingReportText(List<VisitPlan> plans) async {
    final dateStr = DateFormat('dd/MM/yyyy', 'th_TH').format(_selectedPendingDate ?? _selectedDay);
    final buffer = StringBuffer();
    
    // Header with simple format for LINE
    buffer.writeln('📋 แผนการเยี่ยมลูกค้า');
    buffer.writeln('📅 วันที่: $dateStr');
    buffer.writeln('');

    if (plans.isEmpty) {
      buffer.writeln('ไม่มีภารกิจในวันนี้');
      return buffer.toString();
    }

    // Group plans by route (using route_code from api_sale_support_cache)
    final routeGroups = <String, List<VisitPlan>>{};
    
    // Load route information for each plan
    for (final plan in plans) {
      try {
        // Get route code from api_sale_support_cache
        final customerDoc = await FirebaseFirestore.instance
            .collection('api_sale_support_cache')
            .doc(plan.customerId)
            .get();
        
        String routeKey = 'ไม่ระบุเส้นทาง';
        if (customerDoc.exists) {
          final data = customerDoc.data()!;
          final routeCode = data['route_code']?.toString();
          if (routeCode != null && routeCode.isNotEmpty) {
            // Use route name from mapping, fallback to route code if not found
            final routeName = kRouteNameMap[routeCode] ?? routeCode;
            routeKey = routeName;
          }
        }
        
        if (!routeGroups.containsKey(routeKey)) {
          routeGroups[routeKey] = [];
        }
        routeGroups[routeKey]!.add(plan);
      } catch (e) {
        // Fallback to unspecified route
        const fallbackKey = 'ไม่ระบุเส้นทาง';
        if (!routeGroups.containsKey(fallbackKey)) {
          routeGroups[fallbackKey] = [];
        }
        routeGroups[fallbackKey]!.add(plan);
      }
    }

    int totalShops = 0;
    final assigneeSet = <String>{};

    for (final entry in routeGroups.entries) {
      final routeName = entry.key;
      final routePlans = entry.value;
      
      buffer.writeln('� เส้นทาง: $routeName');
      buffer.writeln('========================');
      
      for (int i = 0; i < routePlans.length; i++) {
        final plan = routePlans[i];
        assigneeSet.add(plan.assignedToName ?? 'ไม่ระบุ');
        
        // Get customer details from api_sale_support_cache
        final customerDetails = await _getCustomerDetailsForShare(plan.customerId);
        
        // Basic customer info
        final customerName = plan.customerName.isNotEmpty ? plan.customerName : plan.customerId;
        buffer.writeln('${i + 1}. $customerName (${plan.customerId})');
        
        // Customer address
        final address = customerDetails['address'] ?? '-';
        if (address != '-' && address.isNotEmpty) {
          buffer.writeln('   📍 ที่อยู่: $address');
        } else {
          buffer.writeln('   📍 ที่อยู่: ไม่ระบุ');
        }
        
        // Customer phone
        final phone = customerDetails['phone'] ?? '-';
        if (phone != '-' && phone.isNotEmpty) {
          buffer.writeln('   📞 โทรศัพท์: $phone');
        } else {
          buffer.writeln('   📞 โทรศัพท์: ไม่ระบุ');
        }
        
        // Last sale date
        final lastSale = customerDetails['lastSale'] ?? '-';
        if (lastSale != '-' && lastSale.isNotEmpty) {
          buffer.writeln('   📈 ซื้อครั้งสุดท้าย: $lastSale');
        } else {
          buffer.writeln('   📈 ซื้อครั้งสุดท้าย: ไม่ระบุ');
        }
        
        if (plan.notes?.isNotEmpty == true) {
          buffer.writeln('   📝 หมายเหตุ: ${plan.notes}');
        }
        
        if (plan.assignedToName != null && plan.assignedToName!.isNotEmpty) {
          buffer.writeln('   👤 รับผิดชอบ: ${plan.assignedToName}');
        }
        
        if (i < routePlans.length - 1) {
          buffer.writeln('');
        }
      }
      
      totalShops += routePlans.length;
      
      // Add separator between routes if there are more routes
      if (entry.key != routeGroups.keys.last) {
        buffer.writeln('');
        buffer.writeln('========================');
        buffer.writeln('');
      }
    }

    // Summary
    final totalAssignees = assigneeSet.length;
    buffer.writeln('');
    buffer.writeln('📊 สรุป: $totalShops ร้าน $totalAssignees ผู้รับผิดชอบ ใน ${routeGroups.length} เส้นทาง');
    
    return buffer.toString();
  }

  // Helper function to get customer details for sharing
  Future<Map<String, String?>> _getCustomerDetailsForShare(String customerId) async {
    try {
      final customerDoc = await FirebaseFirestore.instance
          .collection('api_sale_support_cache')
          .doc(customerId)
          .get();
      
      if (customerDoc.exists) {
        final data = customerDoc.data()!;
        final routeCode = data['route_code']?.toString();
        final routeName = routeCode != null ? (kRouteNameMap[routeCode] ?? routeCode) : null;
        
        return {
          'address': data['mem_address']?.toString() ?? '-',
          'phone': data['mem_phone']?.toString() ?? '-',
          'lastSale': data['mem_lastsale']?.toString() ?? '-',
          'routeCode': routeCode ?? '-',
          'routeName': routeName ?? '-',
        };
      }
    } catch (e) {
      // Error loading customer details
    }
    return {
      'address': '-', 
      'phone': '-', 
      'lastSale': '-',
      'routeCode': '-',
      'routeName': '-',
    };
  }

  Future<void> _ensureCustomersCache() async {
    if (_customersCache != null || _loadingCustomers) return;
    _loadingCustomers = true;
    try {
      // Fetch a broad set once; reuse for contains() filtering like the customer list screen
      final snap = await FirebaseFirestore.instance.collection('customers').get();
      _customersCache = snap.docs.map((d) => Customer.fromFirestore(d)).toList();
    } finally {
      _loadingCustomers = false;
    }
  }

  // Group plans by route/province for better organization
  Future<Map<String, List<VisitPlan>>> _groupPlansByRoute(List<VisitPlan> plans) async {
    final Map<String, List<VisitPlan>> grouped = {};
    
    for (final plan in plans) {
      try {
        // Get route information from api_sale_support_cache
        final routeDoc = await FirebaseFirestore.instance
            .collection('api_sale_support_cache')
            .doc(plan.customerId)
            .get();
        
        String routeKey = 'ไม่ระบุเส้นทาง';
        if (routeDoc.exists) {
          final routeCode = routeDoc.data()?['route_code'];
          if (routeCode != null && routeCode.toString().isNotEmpty) {
            final provinceName = kRouteNameMap[routeCode] ?? routeCode;
            routeKey = '$provinceName ($routeCode)';
          }
        }
        
        // Add to group
        if (!grouped.containsKey(routeKey)) {
          grouped[routeKey] = [];
        }
        grouped[routeKey]!.add(plan);
      } catch (e) {
        // Add to unspecified route group
        const unspecifiedKey = 'ไม่ระบุเส้นทาง';
        if (!grouped.containsKey(unspecifiedKey)) {
          grouped[unspecifiedKey] = [];
        }
        grouped[unspecifiedKey]!.add(plan);
      }
    }
    
    return grouped;
  }

  // Get all plans for route statistics
  Stream<List<VisitPlan>> _getAllPlansForStats() {
    return FirebaseFirestore.instance
        .collection('visit_plans')
        .orderBy('plannedAt', descending: true)
        .limit(200)
        .snapshots()
        .map((snap) => snap.docs.map((d) => VisitPlan.fromFirestore(d)).toList());
  }

  // Calculate route-based statistics
  Future<Map<String, Map<String, int>>> _getRouteStats(List<VisitPlan> allPlans) async {
    final Map<String, Map<String, int>> routeStats = {};
    
    for (final plan in allPlans) {
      try {
        // Get route information from api_sale_support_cache
        final routeDoc = await FirebaseFirestore.instance
            .collection('api_sale_support_cache')
            .doc(plan.customerId)
            .get();
        
        String routeKey = 'ไม่ระบุเส้นทาง';
        if (routeDoc.exists) {
          final routeCode = routeDoc.data()?['route_code'];
          if (routeCode != null && routeCode.toString().isNotEmpty) {
            final provinceName = kRouteNameMap[routeCode] ?? routeCode;
            routeKey = '$provinceName ($routeCode)';
          }
        }
        
        // Initialize route stats if not exists
        if (!routeStats.containsKey(routeKey)) {
          routeStats[routeKey] = {
            'total': 0,
            'completed': 0,
            'pending': 0,
          };
        }
        
        // Count totals
        routeStats[routeKey]!['total'] = (routeStats[routeKey]!['total'] ?? 0) + 1;
        
        // Count completed vs pending
        final isCompleted = plan.doneAt != null && 
                           (plan.resultNotes?.isNotEmpty == true || 
                            plan.photoUrls.isNotEmpty || 
                            plan.signatureUrl?.isNotEmpty == true);
        
        if (isCompleted) {
          routeStats[routeKey]!['completed'] = (routeStats[routeKey]!['completed'] ?? 0) + 1;
        } else {
          routeStats[routeKey]!['pending'] = (routeStats[routeKey]!['pending'] ?? 0) + 1;
        }
      } catch (e) {
        print('Error getting route stats for customer ${plan.customerId}: $e');
        // Add to unspecified route group
        const unspecifiedKey = 'ไม่ระบุเส้นทาง';
        if (!routeStats.containsKey(unspecifiedKey)) {
          routeStats[unspecifiedKey] = {
            'total': 0,
            'completed': 0,
            'pending': 0,
          };
        }
        routeStats[unspecifiedKey]!['total'] = (routeStats[unspecifiedKey]!['total'] ?? 0) + 1;
        
        final isCompleted = plan.doneAt != null && 
                           (plan.resultNotes?.isNotEmpty == true || 
                            plan.photoUrls.isNotEmpty || 
                            plan.signatureUrl?.isNotEmpty == true);
        
        if (isCompleted) {
          routeStats[unspecifiedKey]!['completed'] = (routeStats[unspecifiedKey]!['completed'] ?? 0) + 1;
        } else {
          routeStats[unspecifiedKey]!['pending'] = (routeStats[unspecifiedKey]!['pending'] ?? 0) + 1;
        }
      }
    }
    
    return routeStats;
  }

  // Build statistics box widget
  Widget _buildStatBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 10,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Stream<List<VisitPlan>> _plansOfDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return FirebaseFirestore.instance
        .collection('visit_plans')
        .where('plannedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('plannedAt', isLessThan: Timestamp.fromDate(end))
        .orderBy('plannedAt')
        .snapshots()
        .map((snap) => snap.docs.map((d) => VisitPlan.fromFirestore(d)).toList());
  }

  // removed legacy print function

  @override
  Widget build(BuildContext context) {
  _selectedPendingDate ??= DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0052D4), Color(0xFF4364F7), Color(0xFF6FB1FC)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('วางแผน', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'ส่งสรุปแล้ว', icon: Icon(Icons.done_all)),
              Tab(text: 'ยังไม่ได้ส่ง', icon: Icon(Icons.pending_actions)),
              Tab(text: 'สถิติ', icon: Icon(Icons.analytics)),
            ],
          ),
          actions: [
            // Document/Print button
            IconButton(
              onPressed: _printPendingReport,
              icon: const Icon(Icons.print, color: Colors.white, size: 20),
              tooltip: 'พิมพ์รายงาน',
            ),
            // Share button
            IconButton(
              onPressed: _sharePendingReport,
              icon: const Icon(Icons.share, color: Colors.white, size: 20),
              tooltip: 'แชร์รายงาน',
            ),
            OutlinedButton.icon(
              onPressed: _showCustomerList,
              icon: const Icon(Icons.people, color: Colors.white, size: 18),
              label: const Text('ลูกค้า', style: TextStyle(color: Colors.white)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.white.withOpacity(0.6)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.calendar_today_outlined),
              onPressed: _pickDateTime,
              tooltip: 'กำหนดวัน/เวลา',
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openAddPlanDialog,
          icon: const Icon(Icons.add_task),
          label: const Text('เพิ่มนัดหมาย'),
        ),
        body: TabBarView(
          children: [
            // TAB 1: Submitted across all dates
            ListView(
              padding: const EdgeInsets.all(12),
              children: [
                StreamBuilder<List<VisitPlan>>(
                  stream: _submittedPlans(),
                  builder: (context, snap) {
                    final submitted = (snap.data ?? []).take(50).toList();
                    return _glass(
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.done_all, color: Colors.white),
                                const SizedBox(width: 8),
                                const Text('ส่งสรุปแล้ว', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                const Spacer(),
                                if (submitted.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade600,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${submitted.length}',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (submitted.isEmpty)
                              const Text('ยังไม่มีรายการที่ส่งสรุป', style: TextStyle(color: Colors.white70))
                            else
                              FutureBuilder<Map<String, List<VisitPlan>>>(
                                future: _groupPlansByRoute(submitted),
                                builder: (context, routeSnapshot) {
                                  if (!routeSnapshot.hasData) {
                                    return const Center(child: CircularProgressIndicator(color: Colors.white));
                                  }
                                  
                                  final groupedPlans = routeSnapshot.data!;
                                  final sortedRoutes = groupedPlans.keys.toList()..sort();
                                  
                                  return Column(
                                    children: [
                                      // Show summary
                                      if (groupedPlans.isNotEmpty)
                                        Container(
                                          width: double.infinity,
                                          margin: const EdgeInsets.only(bottom: 8),
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Colors.green.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: Colors.green.withOpacity(0.3)),
                                          ),
                                          child: Text(
                                            'รวม ${submitted.length} ภารกิจ • ${groupedPlans.length} เส้นทาง',
                                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      
                                      // Group by route
                                      for (final routeKey in sortedRoutes) ...[
                                        // Route header
                                        Container(
                                          width: double.infinity,
                                          margin: const EdgeInsets.symmetric(vertical: 4),
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: Colors.green.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: Colors.green.withOpacity(0.4)),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(Icons.check_circle, color: Colors.green.shade300, size: 16),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  routeKey,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.green.shade400,
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  '${groupedPlans[routeKey]!.length}',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        
                                        // Plans in this route
                                        for (final p in groupedPlans[routeKey]!)
                                          _SubmittedPlanCard(plan: p),
                                        
                                        const SizedBox(height: 8),
                                      ],
                                    ],
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),

            // TAB 2: Pending with date chips
            ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _glass(
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        const Icon(Icons.event_note, color: Colors.white),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "แผนงานวันที่ ${DateFormat('dd MMM yyyy', 'th_TH').format(_selectedDay)}",
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_month, color: Colors.white),
                          label: Text(DateFormat('dd/MM HH:mm').format(_selectedDay), style: const TextStyle(color: Colors.white)),
                          style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.white.withOpacity(0.6))),
                          onPressed: _pickDateTime,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                StreamBuilder<List<DateTime>>(
                  stream: _pendingDates(),
                  builder: (context, dsnap) {
                    final dates = dsnap.data ?? [];
                    if (dates.isNotEmpty && (_selectedPendingDate == null || !dates.any((d) => _isSameDate(d, _selectedPendingDate!)))) {
                      _selectedPendingDate = dates.first; // default latest
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _glass(
                          Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('ยังไม่ได้ส่ง', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                if (dates.isNotEmpty)
                                  SizedBox(
                                    height: 36,
                                    child: ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: dates.length,
                                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                                      itemBuilder: (_, i) {
                                        final d = dates[i];
                                        final selected = _selectedPendingDate != null && _isSameDate(d, _selectedPendingDate!);
                                        return ChoiceChip(
                                          label: Text(DateFormat('dd/MM', 'th_TH').format(d)),
                                          selected: selected,
                                          onSelected: (_) => setState(() => _selectedPendingDate = d),
                                        );
                                      },
                                    ),
                                  )
                                else
                                  const Text('ไม่มีภารกิจที่ค้างส่ง', style: TextStyle(color: Colors.white70)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (_selectedPendingDate != null)
                          StreamBuilder<List<VisitPlan>>(
                            stream: _plansOfDay(_selectedPendingDate!),
                            builder: (context, psnap) {
                              final allPlans = (psnap.data ?? [])
                                  .where((p) => p.doneAt == null && (p.resultNotes == null || p.resultNotes!.isEmpty) && p.photoUrls.isEmpty && (p.signatureUrl == null || p.signatureUrl!.isEmpty))
                                  .toList();
                              
                              // Remove duplicate customers on the same day - keep only the first one by planned time
                              final Map<String, VisitPlan> uniqueCustomerPlans = {};
                              for (final plan in allPlans) {
                                final customerId = plan.customerId;
                                if (!uniqueCustomerPlans.containsKey(customerId) || 
                                    plan.plannedAt.compareTo(uniqueCustomerPlans[customerId]!.plannedAt) < 0) {
                                  uniqueCustomerPlans[customerId] = plan;
                                }
                              }
                              final plans = uniqueCustomerPlans.values.toList();
                              
                              // Group plans by route/province for better organization
                              return FutureBuilder<Map<String, List<VisitPlan>>>(
                                future: _groupPlansByRoute(plans),
                                builder: (context, routeSnapshot) {
                                  if (!routeSnapshot.hasData) {
                                    return const Center(child: CircularProgressIndicator(color: Colors.white));
                                  }
                                  
                                  final groupedPlans = routeSnapshot.data!;
                                  final sortedRoutes = groupedPlans.keys.toList()..sort();
                                  
                                  return Column(
                                    children: [
                                      // Show summary
                                      if (groupedPlans.isNotEmpty)
                                        _glass(
                                          Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: Text(
                                              'รวม ${plans.length} ภารกิจ • ${groupedPlans.length} เส้นทาง',
                                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                                            ),
                                          ),
                                        ),
                                      const SizedBox(height: 8),
                                      
                                      // Group by route
                                      for (final routeKey in sortedRoutes) ...[
                                        // Route header
                                        Container(
                                          width: double.infinity,
                                          margin: const EdgeInsets.symmetric(vertical: 4),
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: Colors.white.withOpacity(0.3)),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(Icons.location_on, color: Colors.blue.shade300, size: 16),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  routeKey,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.blue.shade300,
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  '${groupedPlans[routeKey]!.length}',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        
                                        // Plans in this route
                                        for (final p in groupedPlans[routeKey]!)
                                          _PlanTile(
                                            key: ValueKey('p_${p.id}'),
                                            plan: p,
                                            selected: _selectedPlanId == p.id,
                                            onSelected: () => setState(() => _selectedPlanId = _selectedPlanId == p.id ? null : p.id),
                                          ),
                                        
                                        const SizedBox(height: 8),
                                      ],
                                    ],
                                  );
                                },
                              );
                            },
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),

            // TAB 3: Statistics
            ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _glass(
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.analytics, color: Colors.white),
                            SizedBox(width: 8),
                            Text('สถิติการรับภารกิจ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        StreamBuilder<List<Map<String, dynamic>>>(
                          stream: _getAcceptanceStats(),
                          builder: (context, snap) {
                            final stats = snap.data ?? [];
                            if (stats.isEmpty) {
                              return const Text('ยังไม่มีข้อมูลสถิติ', style: TextStyle(color: Colors.white70));
                            }
                            return Column(
                              children: [
                                for (int i = 0; i < stats.length; i++)
                                  _StatCard(rank: i + 1, data: stats[i]),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // Route-based Statistics
                _glass(
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.location_on, color: Colors.white),
                            SizedBox(width: 8),
                            Text('สถิติตามเส้นทาง', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        StreamBuilder<List<VisitPlan>>(
                          stream: _getAllPlansForStats(),
                          builder: (context, snap) {
                            final allPlans = snap.data ?? [];
                            if (allPlans.isEmpty) {
                              return const Text('ยังไม่มีข้อมูลภารกิจ', style: TextStyle(color: Colors.white70));
                            }
                            
                            return FutureBuilder<Map<String, Map<String, int>>>(
                              future: _getRouteStats(allPlans),
                              builder: (context, routeSnapshot) {
                                if (!routeSnapshot.hasData) {
                                  return const Center(child: CircularProgressIndicator(color: Colors.white));
                                }
                                
                                final routeStats = routeSnapshot.data!;
                                final sortedRoutes = routeStats.keys.toList()..sort();
                                
                                return Column(
                                  children: [
                                    // Summary
                                    Container(
                                      width: double.infinity,
                                      margin: const EdgeInsets.only(bottom: 12),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.purple.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.purple.withOpacity(0.3)),
                                      ),
                                      child: Column(
                                        children: [
                                          Text(
                                            'สรุปภาพรวม ${sortedRoutes.length} เส้นทาง',
                                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'ทั้งหมด ${allPlans.length} ภารกิจ',
                                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                    
                                    // Route statistics
                                    for (final routeKey in sortedRoutes) ...[
                                      Container(
                                        width: double.infinity,
                                        margin: const EdgeInsets.symmetric(vertical: 4),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.white.withOpacity(0.3)),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(Icons.location_on, color: Colors.purple.shade300, size: 16),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    routeKey,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: _buildStatBox(
                                                    'เสร็จแล้ว',
                                                    '${routeStats[routeKey]!['completed'] ?? 0}',
                                                    Colors.green,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: _buildStatBox(
                                                    'รอดำเนินการ',
                                                    '${routeStats[routeKey]!['pending'] ?? 0}',
                                                    Colors.orange,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: _buildStatBox(
                                                    'รวม',
                                                    '${routeStats[routeKey]!['total'] ?? 0}',
                                                    Colors.blue,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  }

  bool _isSameDate(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  // Submitted plans across all dates, ordered by doneAt desc  
  Stream<List<VisitPlan>> _submittedPlans() {
    return FirebaseFirestore.instance
        .collection('visit_plans')
        .orderBy('doneAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) {
          final allSubmitted = snap.docs
              .map((d) => VisitPlan.fromFirestore(d))
              .where((p) => p.doneAt != null || (p.resultNotes?.isNotEmpty ?? false) || p.photoUrls.isNotEmpty || (p.signatureUrl?.isNotEmpty ?? false))
              .toList();
          
          // Group by customerId and keep only the latest submission for each customer
          final Map<String, VisitPlan> latestSubmissions = {};
          for (final plan in allSubmitted) {
            final customerId = plan.customerId;
            if (!latestSubmissions.containsKey(customerId) || 
                (plan.doneAt != null && latestSubmissions[customerId]!.doneAt != null && 
                 plan.doneAt!.compareTo(latestSubmissions[customerId]!.doneAt!) > 0)) {
              latestSubmissions[customerId] = plan;
            }
          }
          
          // Return sorted list by doneAt descending
          final uniqueSubmissions = latestSubmissions.values.toList();
          uniqueSubmissions.sort((a, b) => (b.doneAt ?? Timestamp.now()).compareTo(a.doneAt ?? Timestamp.now()));
          return uniqueSubmissions;
        });
  }

  // Pending dates: latest first within +/- range
  Stream<List<DateTime>> _pendingDates() {
    final start = DateTime.now().subtract(const Duration(days: 7));
    final end = DateTime.now().add(const Duration(days: 30));
    return FirebaseFirestore.instance
        .collection('visit_plans')
        .where('plannedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('plannedAt', isLessThan: Timestamp.fromDate(end))
        .orderBy('plannedAt', descending: true)
        .snapshots()
        .map((snap) {
          final pending = snap.docs.map((d) => VisitPlan.fromFirestore(d)).where((p) => p.doneAt == null && (p.resultNotes == null || p.resultNotes!.isEmpty) && p.photoUrls.isEmpty && (p.signatureUrl == null || p.signatureUrl!.isEmpty));
          final set = <String, DateTime>{};
          for (final p in pending) {
            final day = DateTime(p.plannedAt.toDate().year, p.plannedAt.toDate().month, p.plannedAt.toDate().day);
            set['${day.year}-${day.month}-${day.day}'] = day;
          }
          final list = set.values.toList();
          list.sort((a,b)=>b.compareTo(a));
          return list;
        });
  }

  // Get acceptance statistics for all assignees
  Stream<List<Map<String, dynamic>>> _getAcceptanceStats() {
    return FirebaseFirestore.instance
        .collection('visit_plans')
        .where('acceptedAt', isNull: false)
        .snapshots()
        .map((snap) {
          final plans = snap.docs.map((d) => VisitPlan.fromFirestore(d)).toList();
          final stats = <String, Map<String, dynamic>>{};
          
          for (final plan in plans) {
            final assigneeId = plan.acceptedById ?? plan.assignedToId;
            final assigneeName = plan.acceptedByName ?? plan.assignedToName ?? 'ไม่ระบุ';
            
            if (assigneeId != null) {
              if (!stats.containsKey(assigneeId)) {
                stats[assigneeId] = {
                  'id': assigneeId,
                  'name': assigneeName,
                  'acceptedCount': 0,
                  'completedCount': 0,
                  'allMissions': <VisitPlan>[],
                  'completedMissions': <VisitPlan>[],
                };
              }
              stats[assigneeId]!['acceptedCount'] = (stats[assigneeId]!['acceptedCount'] as int) + 1;
              (stats[assigneeId]!['allMissions'] as List<VisitPlan>).add(plan);
              
              // Check if mission is completed (has submission data)
              if (plan.doneAt != null || (plan.resultNotes?.isNotEmpty ?? false) || plan.photoUrls.isNotEmpty) {
                stats[assigneeId]!['completedCount'] = (stats[assigneeId]!['completedCount'] as int) + 1;
                (stats[assigneeId]!['completedMissions'] as List<VisitPlan>).add(plan);
              }
            }
          }
          
          // Sort missions by date/time (newest first)
          for (final stat in stats.values) {
            (stat['allMissions'] as List<VisitPlan>).sort((a, b) => b.plannedAt.compareTo(a.plannedAt));
            (stat['completedMissions'] as List<VisitPlan>).sort((a, b) {
              final aDate = a.doneAt ?? a.plannedAt;
              final bDate = b.doneAt ?? b.plannedAt;
              return bDate.compareTo(aDate);
            });
          }
          
          final result = stats.values.toList();
          result.sort((a, b) => (b['completedCount'] as int).compareTo(a['completedCount'] as int));
          return result;
        });
  }

  Future<void> _openAddPlanDialog() async {
    await _ensureAssigneesLoaded();
    final nameSearchController = TextEditingController();
    final codeSearchController = TextEditingController();
    final noteController = TextEditingController();
    DateTime plannedAt = _selectedDay;
    Customer? chosenCustomer;
    _Salesperson? chosenAssignee = _assignees.isNotEmpty ? _assignees.first : null;
    List<Customer> suggestions = [];

    Future<void> pickDateTime() async {
      final date = await showDatePicker(
        context: context,
        initialDate: plannedAt,
        firstDate: DateTime.now().subtract(const Duration(days: 0)),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      );
      if (date == null) return;
      final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(plannedAt));
      if (time == null) return;
      plannedAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      (context as Element).markNeedsBuild();
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: _glass(
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: StatefulBuilder(
                builder: (ctx, setModal) {
                  Future<void> doSearch() async {
                    final code = codeSearchController.text;
                    final name = nameSearchController.text;
                    // Run code lookup via Firestore
                    final List<Customer> byCode = code.trim().isEmpty ? [] : await _queryByCode(code);
                    // Name: contains anywhere using cached list (same behavior as customer_list_screen)
                    List<Customer> byName = [];
                    if (name.trim().isNotEmpty) {
                      await _ensureCustomersCache();
                      final q = name.trim().toLowerCase();
                      byName = (_customersCache ?? [])
                          .where((c) => c.name.toLowerCase().contains(q))
                          .take(30)
                          .toList();
                      // If cache was not yet loaded (shouldn’t happen), fallback to prefix Firestore query
                      if (byName.isEmpty && (_customersCache == null)) {
                        byName = await _queryByNamePrefix(name);
                      }
                    }
                    // Merge & dedupe
                    final map = <String, Customer>{};
                    for (final c in [...byCode, ...byName]) { map[c.customerId] = c; }
                    suggestions = map.values.toList()
                      ..sort((a,b)=>a.name.toLowerCase().compareTo(b.name.toLowerCase()));
                    setModal(() {});
                  }

                  return SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.add_task, color: Colors.white),
                            SizedBox(width: 6),
                            Text('เพิ่มนัดหมาย', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text('ค้นหารหัสลูกค้า', style: TextStyle(color: Colors.white70)),
                        TextField(
                          controller: codeSearchController,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => doSearch(),
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.numbers, color: Colors.white),
                            suffixIcon: codeSearchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, color: Colors.white),
                                    onPressed: () { codeSearchController.clear(); doSearch(); },
                                  )
                                : null,
                            hintText: 'ป้อนรหัสลูกค้า',
                            hintStyle: const TextStyle(color: Colors.white70),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text('ค้นหาชื่อลูกค้า', style: TextStyle(color: Colors.white70)),
                        TextField(
                          controller: nameSearchController,
                          onChanged: (_) => doSearch(),
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search, color: Colors.white),
                            suffixIcon: nameSearchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, color: Colors.white),
                                    onPressed: () { nameSearchController.clear(); doSearch(); },
                                  )
                                : null,
                            hintText: 'ป้อนชื่อลูกค้า',
                            hintStyle: const TextStyle(color: Colors.white70),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                        ),
                        if (suggestions.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          ...suggestions.map((c) => ListTile(
                                dense: true,
                                title: Text(c.name, style: const TextStyle(color: Colors.white)),
                                subtitle: Text(c.customerId, style: const TextStyle(color: Colors.white70)),
                                onTap: () {
                                  chosenCustomer = c;
                                  // Fill inputs and hide suggestions until user clears/edits
                                  nameSearchController.text = c.name;
                                  codeSearchController.text = c.customerId;
                                  suggestions = [];
                                  FocusScope.of(ctx).unfocus();
                                  setModal((){});
                                },
                              )),
                        ],
                        const SizedBox(height: 8),
                        if (chosenCustomer != null)
                          FutureBuilder<Map<String, dynamic>?>(
                            future: _lastVisitOf(chosenCustomer!.customerId),
                            builder: (context, snap) {
                              final last = snap.data;
                              final when = last?['callTimestamp'] is Timestamp
                                  ? DateFormat('dd/MM/yyyy HH:mm', 'th_TH').format((last!['callTimestamp'] as Timestamp).toDate())
                                  : '-';
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('ลูกค้าที่เลือก: ${chosenCustomer!.name} (${chosenCustomer!.customerId})', style: const TextStyle(color: Colors.white)),
                                  const SizedBox(height: 4),
                                  Text('เข้าพบล่าสุด: $when', style: const TextStyle(color: Colors.white70)),
                                ],
                              );
                            },
                          ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: noteController,
                          style: const TextStyle(color: Colors.white),
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: 'รายละเอียดงานที่ต้องทำ',
                            hintStyle: const TextStyle(color: Colors.white70),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text('กำหนดเวลา: ', style: TextStyle(color: Colors.white70)),
                            Text(DateFormat('dd/MM/yyyy HH:mm', 'th_TH').format(plannedAt), style: const TextStyle(color: Colors.white)),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.schedule),
                              label: const Text('เปลี่ยนเวลา'),
                              onPressed: () async { await pickDateTime(); setModal((){}); },
                            )
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text('มอบหมายให้: ', style: TextStyle(color: Colors.white70)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButton<_Salesperson>(
                                value: chosenAssignee,
                                dropdownColor: Colors.blueGrey.shade800,
                                items: _assignees
                                    .map((s) => DropdownMenuItem(
                                          value: s,
                                          child: Text('${s.name} (${s.code})', style: const TextStyle(color: Colors.white)),
                                        ))
                                    .toList(),
                                onChanged: (v) => setModal(() => chosenAssignee = v),
                                underline: const SizedBox(),
                                iconEnabledColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.save_alt),
                            label: const Text('บันทึกนัดหมาย'),
                            onPressed: () async {
                              if (chosenCustomer == null) return;
                              final user = FirebaseAuth.instance.currentUser;
                              if (user == null) return;
                              await FirebaseFirestore.instance.collection('visit_plans').add({
                                'customerId': chosenCustomer!.customerId,
                                'customerName': chosenCustomer!.name,
                                'notes': noteController.text.trim().isEmpty ? null : noteController.text.trim(),
                                'plannedAt': Timestamp.fromDate(plannedAt),
                                'createdAt': Timestamp.now(),
                                'createdBy': user.displayName ?? user.email ?? user.uid,
                                'salespersonId': user.uid,
                                'assignedToId': chosenAssignee?.id,
                                'assignedToName': chosenAssignee?.name,
                              });
                              if (mounted) Navigator.pop(ctx);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('บันทึกแผนสำเร็จ')));
                              }
                            },
                          ),
                        )
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _glass(Widget child) {
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

class _PlanTile extends StatefulWidget {
  final VisitPlan plan;
  final bool selected;
  final VoidCallback onSelected;
  const _PlanTile({super.key, required this.plan, required this.selected, required this.onSelected});

  @override
  State<_PlanTile> createState() => _PlanTileState();
}

class _PlanTileState extends State<_PlanTile> {
  String? _routeName;
  List<VisitPlan> _visitHistory = [];
  int _currentRound = 1;
  DateTime? _lastVisitDate;
  String? _customerAddress;
  String? _customerPhone;
  String? _lastSaleDate;

  @override
  void initState() {
    super.initState();
    _loadRouteInfo();
    _loadVisitHistory();
    _loadCustomerDetails();
  }

  Future<void> _loadRouteInfo() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('api_sale_support_cache')
          .doc(widget.plan.customerId)
          .get();
      
      if (doc.exists && mounted) {
        final data = doc.data()!;
        final routeCode = data['route_code'] as String?;
        setState(() {
          _routeName = routeCode != null ? kRouteNameMap[routeCode] : null;
        });
      }
    } catch (e) {
      // Handle error silently
    }
  }

  Future<void> _loadVisitHistory() async {
    try {
      // Get all visit plans for this customer
      final plansSnapshot = await FirebaseFirestore.instance
          .collection('visit_plans')
          .where('customerId', isEqualTo: widget.plan.customerId)
          .orderBy('plannedAt', descending: true)
          .get();
      
      if (mounted) {
        final allPlans = plansSnapshot.docs.map((doc) => VisitPlan.fromFirestore(doc)).toList();
        final otherPlans = allPlans.where((p) => p.id != widget.plan.id).toList();
        
        // Count only completed/submitted visits for this customer
        final completedPlans = allPlans.where((p) => 
          p.doneAt != null && p.resultNotes?.isNotEmpty == true
        ).toList();
        
        // The current pending plan will be the next round after all completed visits
        final currentRound = completedPlans.length + 1;
        
        setState(() {
          _visitHistory = otherPlans;
          _currentRound = currentRound;
          _lastVisitDate = otherPlans.isNotEmpty ? otherPlans.first.plannedAt.toDate() : null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          // Handle error silently
        });
      }
    }
  }

  Future<void> _loadCustomerDetails() async {
    try {
      // Get customer details from api_sale_support_cache collection (not customers)
      final customerDoc = await FirebaseFirestore.instance
          .collection('api_sale_support_cache')
          .doc(widget.plan.customerId)
          .get();
      
      if (customerDoc.exists && mounted) {
        final data = customerDoc.data()!;
        setState(() {
          _customerAddress = data['mem_address']?.toString();
          _customerPhone = data['mem_phone']?.toString();
          _lastSaleDate = data['mem_lastsale']?.toString();
        });
      }
    } catch (e) {
      // Error loading customer details
    }
  }

  // Delete plan function for this tile
  Future<void> _deletePlan() async {
    print('Delete plan called for: ${widget.plan.customerName}');
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: Text('ต้องการลบภารกิจ "${widget.plan.customerName}" หรือไม่?\n\nการดำเนินการนี้ไม่สามารถยกเลิกได้'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('ลบ', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        print('Deleting plan with ID: ${widget.plan.id}');
        await FirebaseFirestore.instance
            .collection('visit_plans')
            .doc(widget.plan.id)
            .delete();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ลบภารกิจสำเร็จ'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        print('Error deleting plan: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('เกิดข้อผิดพลาด: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'done':
        return Colors.green.withOpacity(0.25);
      case 'in_progress':
        return Colors.yellow.withOpacity(0.28);
      default:
        return Colors.red.withOpacity(0.28);
    }
  }

  Future<void> _acceptTask(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance.collection('visit_plans').doc(widget.plan.id).update({
      'acceptedById': user.uid,
      'acceptedByName': user.displayName ?? user.email ?? user.uid,
      'acceptedAt': Timestamp.now(),
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('รับภารกิจแล้ว')));
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.plan.status;
    
    return Stack(
      children: [
        // Main card content
        Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: _statusColor(status),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.selected ? Colors.yellowAccent : Colors.white.withOpacity(0.25), 
              width: widget.selected ? 2 : 1
            ),
          ),
          child: Stack(
            children: [
              // Route badge with round number - positioned at top-left corner
              if (_routeName != null)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Row(
                    children: [
                      // Province badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.blue.shade300),
                        ),
                        child: Text(
                          _routeName!,
                          style: TextStyle(
                            color: Colors.blue.shade700,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Round number badge - rectangular design
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade600,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white.withOpacity(0.5)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Text(
                          'รอบที่ $_currentRound',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              
              // Main content with expanded info
              GestureDetector(
                onTap: widget.onSelected,
                child: ExpansionTile(
                  collapsedIconColor: Colors.white,
                  iconColor: Colors.white,
                  tilePadding: EdgeInsets.only(
                    top: _routeName != null ? 35 : 8,
                    left: 16,
                    right: 60, // Space for delete button
                    bottom: 8,
                  ),
                  leading: const Icon(Icons.assignment, color: Colors.white),
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.plan.customerName} (${widget.plan.customerId})', 
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)
                      ),
                      // Show customer data if available
                      if (_customerAddress != null)
                        Text(
                          '📍 $_customerAddress',
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      else
                        const Text(
                          '📍 กำลังโหลดที่อยู่...',
                          style: TextStyle(color: Colors.white60, fontSize: 11),
                        ),
                      if (_customerPhone != null)
                        Text(
                          '📞 $_customerPhone',
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        )
                      else
                        const Text(
                          '📞 กำลังโหลดเบอร์โทร...',
                          style: TextStyle(color: Colors.white60, fontSize: 11),
                        ),
                      if (_lastSaleDate != null)
                        Text(
                          '🛒 ซื้อล่าสุด: $_lastSaleDate',
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        )
                      else
                        const Text(
                          '🛒 กำลังโหลดประวัติซื้อ...',
                          style: TextStyle(color: Colors.white60, fontSize: 11),
                        ),
                      if (_lastVisitDate != null)
                        Text(
                          'เยี่ยมล่าสุด: ${DateFormat('dd/MM/yyyy', 'th_TH').format(_lastVisitDate!)}',
                          style: const TextStyle(color: Colors.white60, fontSize: 11),
                        ),
                    ],
                  ),
                  subtitle: Text(
                    "${DateFormat('dd/MM/yyyy HH:mm', 'th_TH').format(widget.plan.plannedAt.toDate())} • ผู้รับผิดชอบ: ${widget.plan.assignedToName ?? '-'}", 
                    style: const TextStyle(color: Colors.white70, fontSize: 12)
                  ),
                  children: [
                    // Current mission details
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade600,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'ภารกิจปัจจุบัน - รอบที่ $_currentRound',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (widget.plan.notes?.isNotEmpty == true)
                            Text(
                              'รายละเอียด: ${widget.plan.notes}',
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                            ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _navigateToSubmit(context),
                                  icon: const Icon(Icons.send, size: 18),
                                  label: const Text('ส่งภารกิจ'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue.shade600,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: () => _acceptTask(context),
                                icon: const Icon(Icons.how_to_reg, size: 18),
                                label: const Text('รับทราบ'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green.shade600,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    
                    // Visit history
                    if (_visitHistory.isNotEmpty) ...[
                      const Divider(color: Colors.white24),
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.withOpacity(0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.history, color: Colors.white70, size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  'ประวัติการเยี่ยม (${_visitHistory.length} ครั้ง)',
                                  style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            for (int i = 0; i < _visitHistory.length && i < 3; i++) ...[
                              Container(
                                padding: const EdgeInsets.all(8),
                                margin: const EdgeInsets.only(bottom: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade600,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'รอบ ${_visitHistory.length - i}',
                                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            DateFormat('dd/MM/yyyy HH:mm', 'th_TH').format(_visitHistory[i].plannedAt.toDate()),
                                            style: const TextStyle(color: Colors.white60, fontSize: 11),
                                          ),
                                          if (_visitHistory[i].notes?.isNotEmpty == true)
                                            Text(
                                              _visitHistory[i].notes!,
                                              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      _visitHistory[i].doneAt != null ? Icons.check_circle : Icons.schedule,
                                      color: _visitHistory[i].doneAt != null ? Colors.green : Colors.orange,
                                      size: 16,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (_visitHistory.length > 3)
                              Text(
                                'และอีก ${_visitHistory.length - 3} รายการ...',
                                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10, fontStyle: FontStyle.italic),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        
        // Delete button - positioned outside of the card content to prevent interference
        Positioned(
          top: 6,
          right: 6,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                print('Delete button tapped for: ${widget.plan.customerName}');
                _deletePlan();
              },
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade600,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.delete,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _navigateToSubmit(BuildContext context) async {
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VisitSubmitScreen(plan: widget.plan),
    ));
  }
}

class _SubmittedPlanCard extends StatefulWidget {
  final VisitPlan plan;
  const _SubmittedPlanCard({required this.plan});

  @override
  State<_SubmittedPlanCard> createState() => _SubmittedPlanCardState();
}

class _SubmittedPlanCardState extends State<_SubmittedPlanCard> {
  String? _routeName;
  List<VisitPlan> _visitHistory = [];
  int _currentRound = 1;
  DateTime? _lastVisitDate;
  String? _customerAddress;
  String? _customerPhone;
  String? _lastSaleDate;

  @override
  void initState() {
    super.initState();
    _loadRouteInfo();
    _loadVisitHistory();
    _loadCustomerDetails();
  }

  Future<void> _loadRouteInfo() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('api_sale_support_cache')
          .doc(widget.plan.customerId)
          .get();
      
      if (doc.exists && mounted) {
        final data = doc.data()!;
        final routeCode = data['route_code'] as String?;
        setState(() {
          _routeName = routeCode != null ? kRouteNameMap[routeCode] : null;
        });
      }
    } catch (e) {
      // Handle error silently
    }
  }

  Future<void> _loadVisitHistory() async {
    try {
      // Get all visit plans for this customer (both submitted and pending)
      final plansSnapshot = await FirebaseFirestore.instance
          .collection('visit_plans')
          .where('customerId', isEqualTo: widget.plan.customerId)
          .orderBy('plannedAt', descending: true)
          .get();
      
      if (mounted) {
        final allPlans = plansSnapshot.docs.map((doc) => VisitPlan.fromFirestore(doc)).toList();
        
        // Filter only completed/submitted plans for round calculation
        final allSubmittedPlans = allPlans.where((p) => 
          p.doneAt != null && p.resultNotes?.isNotEmpty == true
        ).toList();
        
        // Get other plans for history display (excluding current plan)
        final otherPlans = allPlans.where((p) => p.id != widget.plan.id).toList();
        
        // Round number = total number of submitted reports for this customer
        final currentRound = allSubmittedPlans.length;
        
        setState(() {
          _visitHistory = otherPlans; // Show all other plans (submitted + pending) for complete history
          _currentRound = currentRound;
          _lastVisitDate = otherPlans.isNotEmpty ? 
            (otherPlans.first.doneAt?.toDate() ?? otherPlans.first.plannedAt.toDate()) : null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          // Handle error silently
        });
      }
    }
  }

  Future<void> _loadCustomerDetails() async {
    try {
      // Get customer details from api_sale_support_cache collection (not customers)
      final customerDoc = await FirebaseFirestore.instance
          .collection('api_sale_support_cache')
          .doc(widget.plan.customerId)
          .get();
      
      if (customerDoc.exists && mounted) {
        final data = customerDoc.data()!;
        setState(() {
          _customerAddress = data['mem_address']?.toString();
          _customerPhone = data['mem_phone']?.toString();
          _lastSaleDate = data['mem_lastsale']?.toString();
        });
      }
    } catch (e) {
      // Error loading customer details
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.25)),
      ),
      child: Stack(
        children: [
          // Route badge with round number - top left
          if (_routeName != null)
            Positioned(
              top: 8,
              left: 8,
              child: Row(
                children: [
                  // Province badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green.shade600,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                    ),
                    child: Text(
                      _routeName!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Round indicator for completed missions - rectangular design
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green.shade700,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white.withOpacity(0.5)),
                    ),
                    child: Text(
                      'รอบที่ $_currentRound',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          ExpansionTile(
            collapsedIconColor: Colors.white,
            iconColor: Colors.white,
            tilePadding: EdgeInsets.only(
              top: _routeName != null ? 35 : 8,
              left: 16,
              right: 16,
              bottom: 8,
            ),
            leading: const Icon(Icons.assignment_turned_in, color: Colors.white),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.plan.customerName} (${widget.plan.customerId})', 
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)
                ),
                if (_customerAddress?.isNotEmpty == true)
                  Text(
                    '📍 ${_customerAddress}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (_customerPhone?.isNotEmpty == true)
                  Text(
                    '📞 ${_customerPhone}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                if (_lastSaleDate?.isNotEmpty == true)
                  Text(
                    '🛒 ซื้อล่าสุด: ${_lastSaleDate}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                if (_lastVisitDate != null && _lastVisitDate != widget.plan.plannedAt.toDate())
                  Text(
                    'เยี่ยมก่อนหน้า: ${DateFormat('dd/MM/yyyy', 'th_TH').format(_lastVisitDate!)}',
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
              ],
            ),
            subtitle: Text(
              "เสร็จเมื่อ: ${DateFormat('dd/MM/yyyy HH:mm', 'th_TH').format(widget.plan.plannedAt.toDate())} • ผู้ส่ง: ${widget.plan.completedByName ?? '-'}", 
              style: const TextStyle(color: Colors.white70, fontSize: 12)
            ),
            children: [
              // Current completed mission
              Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.shade700,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'ภารกิจเสร็จแล้ว - รอบที่ $_currentRound',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (widget.plan.resultNotes != null && widget.plan.resultNotes!.isNotEmpty)
                      Text('สรุปงาน: ${widget.plan.resultNotes}', style: const TextStyle(color: Colors.white)),
                    const SizedBox(height: 6),
                    if (widget.plan.photoUrls.isNotEmpty)
                      SizedBox(
                        height: 90,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: widget.plan.photoUrls.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 6),
                          itemBuilder: (_, i) => ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(widget.plan.photoUrls[i], width: 120, height: 90, fit: BoxFit.cover),
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _acknowledge(context, widget.plan),
                          icon: const Icon(Icons.done_all),
                          label: const Text('รับทราบ'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => _deletePlan(context, widget.plan),
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          label: const Text('ลบ', style: TextStyle(color: Colors.red)),
                          style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Visit history for completed missions
              if (_visitHistory.isNotEmpty) ...[
                const Divider(color: Colors.white24),
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.history, color: Colors.white70, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            'ประวัติการเยี่ยมอื่นๆ (${_visitHistory.length} ครั้ง)',
                            style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (int i = 0; i < _visitHistory.length && i < 3; i++) ...[
                        Container(
                          padding: const EdgeInsets.all(8),
                          margin: const EdgeInsets.only(bottom: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _visitHistory[i].doneAt != null ? Colors.green.shade600 : Colors.grey.shade600,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'รอบ ${_visitHistory.length - i}',
                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      DateFormat('dd/MM/yyyy HH:mm', 'th_TH').format(_visitHistory[i].plannedAt.toDate()),
                                      style: const TextStyle(color: Colors.white60, fontSize: 11),
                                    ),
                                    if (_visitHistory[i].resultNotes?.isNotEmpty == true)
                                      Text(
                                        _visitHistory[i].resultNotes!,
                                        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              Icon(
                                _visitHistory[i].doneAt != null ? Icons.check_circle : Icons.schedule,
                                color: _visitHistory[i].doneAt != null ? Colors.green : Colors.orange,
                                size: 16,
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_visitHistory.length > 3)
                        Text(
                          'และอีก ${_visitHistory.length - 3} รายการ...',
                          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10, fontStyle: FontStyle.italic),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _acknowledge(BuildContext context, VisitPlan p) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance.collection('visit_plans').doc(p.id).update({
      'acknowledgedBy': FieldValue.arrayUnion([
        {
          'id': user.uid,
          'name': user.displayName ?? user.email ?? user.uid,
          'at': Timestamp.now(),
        }
      ])
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('รับทราบแล้ว')));
  }

  Future<void> _deletePlan(BuildContext context, VisitPlan p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ลบภารกิจ'),
        content: const Text('ยืนยันการลบภารกิจนี้หรือไม่?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('ลบ', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    await FirebaseFirestore.instance.collection('visit_plans').doc(p.id).delete();
  }
}

class _CommentsSection extends StatefulWidget {
  final String planId;
  const _CommentsSection({required this.planId});

  @override
  State<_CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<_CommentsSection> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('คอมเม้นท์', style: TextStyle(color: Colors.white)),
        const SizedBox(height: 6),
        StreamBuilder(
          stream: FirebaseFirestore.instance
              .collection('visit_plans')
              .doc(widget.planId)
              .collection('comments')
              .orderBy('createdAt', descending: false)
              .snapshots(),
          builder: (context, snap) {
            final docs = (snap.data as QuerySnapshot?)?.docs ?? [];
            return Column(
              children: [
                ...docs.map((d) {
                  final data = d.data() as Map<String, dynamic>;
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Text('${data['author'] ?? ''}: ${data['text'] ?? ''}', style: const TextStyle(color: Colors.white70)),
                    ),
                  );
                }),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: InputDecoration(
                          hintText: 'พิมพ์คอมเม้นท์...',
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                        ),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: _send,
                    )
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    await FirebaseFirestore.instance
        .collection('visit_plans')
        .doc(widget.planId)
        .collection('comments')
        .add({
      'text': text,
      'createdAt': Timestamp.now(),
      'authorId': user?.uid,
      'author': user?.displayName ?? user?.email ?? 'ผู้ใช้',
    });
    _controller.clear();
  }
}

class _Salesperson {
  final String id;
  final String name;
  final String code;
  _Salesperson({required this.id, required this.name, required this.code});
}

class _CustomerWithHistory {
  final Customer customer;
  final DateTime? lastSaleDate;
  final DateTime? lastVisitPlan;
  bool hasRecentMission;
  
  _CustomerWithHistory({
    required this.customer,
    this.lastSaleDate,
    this.lastVisitPlan,
    this.hasRecentMission = false,
  });

  // Calculate priority score (lower is higher priority)
  double get priorityScore {
    final now = DateTime.now();
    double score = 0;
    
    // If has recent mission (within 30 days), lower priority
    if (hasRecentMission) {
      score += 1000;
    }
    
    // If never had mission, higher priority
    if (lastVisitPlan == null) {
      score -= 500;
    } else {
      // Add days since last visit plan
      score += now.difference(lastVisitPlan!).inDays;
    }
    
    // If has sales history, consider time since last sale
    if (lastSaleDate != null) {
      final daysSinceLastSale = now.difference(lastSaleDate!).inDays;
      score += daysSinceLastSale * 2; // Weight sales history more
    } else {
      // No sales history, very high priority
      score -= 1000;
    }
    
    return score;
  }
}

class _CustomerListView extends StatefulWidget {
  final DateTime selectedDay;
  final List<_Salesperson> assignees;
  final Future<void> Function() onEnsureAssigneesLoaded;
  final Widget Function(Widget) glassWidget;

  const _CustomerListView({
    required this.selectedDay,
    required this.assignees,
    required this.onEnsureAssigneesLoaded,
    required this.glassWidget,
  });

  @override
  State<_CustomerListView> createState() => _CustomerListViewState();
}

class _CustomerListViewState extends State<_CustomerListView> {
  final TextEditingController _searchController = TextEditingController();
  List<_CustomerWithHistory> _allCustomers = [];
  List<_CustomerWithHistory> _filteredCustomers = [];
  bool _loading = true;
  Set<String> _selectedCustomers = {};
  
  // Performance optimization
  bool _isSearchMode = false;
  final int _pageSize = 20;
  bool _hasMore = true;
  Map<String, _CustomerWithHistory> _customerCache = {};
  String _lastSearchQuery = '';
  bool _showOnlyPriority = false;
  
  // Progress tracking
  double _loadingProgress = 0.0;
  String _loadingMessage = '';
  int _totalSteps = 0;
  int _currentStep = 0;
  
  // Pagination for incremental loading
  bool _isLoadingMore = false;
  List<String> _allCustomerIds = [];
  int _loadedCount = 0;

  @override
  void initState() {
    super.initState();
    _loadInitialCustomers();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      _loadInitialCustomers();
    } else if (query.length >= 2) {
      _searchCustomers(query);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Fast initial load with incremental display
  Future<void> _loadInitialCustomers() async {
    try {
      setState(() {
        _loading = true;
        _isSearchMode = false;
        _loadingProgress = 0.0;
        _currentStep = 0;
        _totalSteps = 3; // Reduced steps for faster initial load
        _allCustomers.clear();
        _filteredCustomers.clear();
        _allCustomerIds.clear();
        _loadedCount = 0;
      });
      
      // Step 1: Get sales cache data quickly
      _updateProgress(1, 'กำลังดึงข้อมูลการขาย...');
      final today = DateTime.now();
      final oneMonthAgo = DateTime(today.year, today.month - 1, today.day);
      
      // Optimized: Query only documents that have mem_lastsale field and limit initial fetch
      final salesCacheSnap = await FirebaseFirestore.instance
          .collection('api_sale_support_cache')
          .where('mem_lastsale', isNotEqualTo: null)
          .limit(100) // Limit initial batch for faster response
          .get();
      
      // Step 2: Process sales data and get customer IDs
      _updateProgress(2, 'กำลังประมวลผลข้อมูล...');
      final customersWithRecentSales = <String, DateTime>{};
      
      for (final doc in salesCacheSnap.docs) {
        final data = doc.data();
        final memLastsale = data['mem_lastsale'];
        
        DateTime? lastSaleDate;
        if (memLastsale != null) {
          if (memLastsale is Timestamp) {
            lastSaleDate = memLastsale.toDate();
          } else if (memLastsale is String) {
            try {
              lastSaleDate = DateTime.parse(memLastsale);
            } catch (_) {
              continue;
            }
          }
        }
        
        // Check if sale is within the last month
        if (lastSaleDate != null && 
            lastSaleDate.isAfter(oneMonthAgo) && 
            lastSaleDate.isBefore(today.add(const Duration(days: 1)))) {
          customersWithRecentSales[doc.id] = lastSaleDate;
        }
      }
      
      if (customersWithRecentSales.isEmpty) {
        setState(() {
          _loading = false;
          _hasMore = false;
          _loadingProgress = 1.0;
          _loadingMessage = 'ไม่พบลูกค้าที่มีการซื้อขายใน 1 เดือนล่าสุด';
        });
        return;
      }
      
      // Sort customer IDs by sales date (oldest first)
      final sortedEntries = customersWithRecentSales.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      
      _allCustomerIds = sortedEntries.map((e) => e.key).toList();
      
      // Step 3: Load first batch quickly
      _updateProgress(3, 'กำลังโหลดลูกค้าชุดแรก...');
      
      await _loadNextBatch(customersWithRecentSales, isInitial: true);
      
      // Continue loading in background
      _loadRemainingDataInBackground(customersWithRecentSales);
      
    } catch (e) {
      setState(() {
        _loading = false;
        _loadingProgress = 0.0;
        _loadingMessage = 'เกิดข้อผิดพลาด';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
      );
    }
  }
  
  // Load next batch of customers
  Future<void> _loadNextBatch(Map<String, DateTime> customersWithRecentSales, {bool isInitial = false}) async {
    if (_loadedCount >= _allCustomerIds.length) {
      setState(() {
        _hasMore = false;
        if (isInitial) _loading = false;
      });
      return;
    }
    
    final startIndex = _loadedCount;
    final endIndex = (_loadedCount + _pageSize).clamp(0, _allCustomerIds.length);
    final batchIds = _allCustomerIds.sublist(startIndex, endIndex);
    
    if (batchIds.isEmpty) {
      setState(() {
        _hasMore = false;
        if (isInitial) _loading = false;
      });
      return;
    }
    
    try {
      // Process in sub-batches of 10 (Firestore limit)
      final newCustomers = <_CustomerWithHistory>[];
      
      for (int i = 0; i < batchIds.length; i += 10) {
        final subBatch = batchIds.skip(i).take(10).toList();
        final customers = await _processCustomerBatch(subBatch, customersWithRecentSales);
        newCustomers.addAll(customers);
      }
      
      setState(() {
        _allCustomers.addAll(newCustomers);
        _filteredCustomers = List.from(_allCustomers);
        _loadedCount = endIndex;
        _hasMore = endIndex < _allCustomerIds.length;
        
        if (isInitial) {
          _loading = false;
          _loadingProgress = 1.0;
          _loadingMessage = 'โหลดชุดแรกสำเร็จ';
        }
      });
      
      print('Loaded batch: ${newCustomers.length} customers (${_loadedCount}/${_allCustomerIds.length})');
      
    } catch (e) {
      print('Error loading batch: $e');
      setState(() {
        if (isInitial) _loading = false;
      });
    }
  }
  
  // Load remaining data in background
  void _loadRemainingDataInBackground(Map<String, DateTime> customersWithRecentSales) async {
    // Wait a bit to let UI render
    await Future.delayed(const Duration(milliseconds: 500));
    
    while (_loadedCount < _allCustomerIds.length && mounted) {
      setState(() => _isLoadingMore = true);
      
      await _loadNextBatch(customersWithRecentSales);
      
      setState(() => _isLoadingMore = false);
      
      // Add small delay between batches to not overwhelm the UI
      await Future.delayed(const Duration(milliseconds: 200));
    }
    
    // Final step: Update mission status for all loaded customers
    if (mounted && _allCustomers.isNotEmpty) {
      _updateMissionStatusInBackground();
    }
  }
  
  // Update mission status in background
  void _updateMissionStatusInBackground() async {
    try {
      final oneMonthAgo = DateTime.now().subtract(const Duration(days: 30));
      final recentMissionsSnap = await FirebaseFirestore.instance
          .collection('visit_plans')
          .where('plannedAt', isGreaterThan: Timestamp.fromDate(oneMonthAgo))
          .get();
      
      final customersWithRecentMissions = <String>{};
      for (final doc in recentMissionsSnap.docs) {
        final plan = VisitPlan.fromFirestore(doc);
        customersWithRecentMissions.add(plan.customerId);
      }
      
      if (mounted) {
        setState(() {
          for (final customer in _allCustomers) {
            customer.hasRecentMission = customersWithRecentMissions.contains(customer.customer.customerId);
          }
          _filteredCustomers = List.from(_allCustomers);
        });
      }
      
      print('Updated mission status for ${_allCustomers.length} customers');
    } catch (e) {
      print('Error updating mission status: $e');
    }
  }
  
  void _updateProgress(int step, String message) {
    setState(() {
      _currentStep = step;
      _loadingProgress = step / _totalSteps;
      _loadingMessage = message;
    });
  }
  
  // Process customer batch with parallel loading
  Future<List<_CustomerWithHistory>> _processCustomerBatch(
    List<String> customerIds, 
    Map<String, DateTime> customersWithRecentSales
  ) async {
    try {
      final customersSnap = await FirebaseFirestore.instance
          .collection('customers')
          .where('รหัสลูกค้า', whereIn: customerIds)
          .get();
      
      final results = <_CustomerWithHistory>[];
      
      for (final doc in customersSnap.docs) {
        final customer = Customer.fromFirestore(doc);
        final lastSaleDate = customersWithRecentSales[customer.customerId];
        
        final customerWithHistory = _CustomerWithHistory(
          customer: customer,
          lastSaleDate: lastSaleDate,
          lastVisitPlan: null,
          hasRecentMission: false, // Will be updated later
        );
        
        results.add(customerWithHistory);
        _customerCache[customer.customerId] = customerWithHistory;
      }
      
      return results;
    } catch (e) {
      print('Error loading customer batch: $e');
      return [];
    }
  }

  // Fast search within filtered customer data
  Future<void> _searchCustomers(String query) async {
    if (query == _lastSearchQuery) return;
    _lastSearchQuery = query;
    
    try {
      setState(() {
        _loading = true;
        _isSearchMode = true;
      });
      
      // Search within already loaded customers (with recent sales)
      final searchResults = _allCustomers.where((customerWithHistory) {
        final customer = customerWithHistory.customer;
        if (RegExp(r'^\d+$').hasMatch(query)) {
          // Pure number - search by customer ID
          return customer.customerId.contains(query);
        } else {
          // Text search - search by name
          return customer.name.toLowerCase().contains(query.toLowerCase());
        }
      }).toList();
      
      setState(() {
        _filteredCustomers = searchResults;
        _loading = false;
      });
      
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาดในการค้นหา: $e')),
      );
    }
  }

  // Load more customers when scrolling
  Future<void> _loadMoreCustomers() async {
    if (_loading || _isLoadingMore || !_hasMore || _isSearchMode) return;
    
    print('Loading more customers... (${_loadedCount}/${_allCustomerIds.length})');
    
    // Load next batch in background
    if (_allCustomerIds.isNotEmpty) {
      setState(() => _isLoadingMore = true);
      
      try {
        // This will be called by the background loading process
        // We just set the flag to show loading indicator
        await Future.delayed(const Duration(milliseconds: 100));
        
        setState(() => _isLoadingMore = false);
      } catch (e) {
        setState(() => _isLoadingMore = false);
      }
    }
  }
  
  Widget _buildLoadingWidget() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(32),
        margin: const EdgeInsets.symmetric(horizontal: 32),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Progress indicator
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 80,
                  height: 80,
                  child: CircularProgressIndicator(
                    value: _loadingProgress,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                    strokeWidth: 6,
                  ),
                ),
                Text(
                  '${(_loadingProgress * 100).toInt()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Progress text
            Text(
              _loadingMessage.isEmpty ? 'กำลังโหลด...' : _loadingMessage,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            
            // Step indicator
            Text(
              'ขั้นตอน $_currentStep จาก $_totalSteps',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            
            // Linear progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _loadingProgress,
                backgroundColor: Colors.white.withOpacity(0.2),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                minHeight: 8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _applyFilters() {
    if (_isSearchMode) return; // Don't filter during search mode
    
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredCustomers = _allCustomers.where((customerWithHistory) {
        final customer = customerWithHistory.customer;
        final matchesSearch = query.isEmpty || 
            customer.name.toLowerCase().contains(query) ||
            customer.customerId.toLowerCase().contains(query);
            
        final matchesPriority = !_showOnlyPriority || 
            (!customerWithHistory.hasRecentMission && // No recent missions
             customerWithHistory.lastSaleDate != null && // Has sales data
             DateTime.now().difference(customerWithHistory.lastSaleDate!).inDays > 15); // Bought more than 15 days ago
            
        return matchesSearch && matchesPriority;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.people, color: Colors.white),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('รายชื่อลูกค้า', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Search bar with filters
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'ค้นหาชื่อลูกค้าหรือรหัส...',
                    hintStyle: const TextStyle(color: Colors.white70),
                    prefixIcon: const Icon(Icons.search, color: Colors.white),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Quick filter button
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white.withOpacity(0.12),
                ),
                child: IconButton(
                  icon: Icon(
                    Icons.priority_high,
                    color: _showOnlyPriority ? Colors.red : Colors.white70,
                  ),
                  tooltip: 'แสดงเฉพาะลูกค้าที่ต้องติดตามด่วน (ซื้อนาน >15 วัน)',
                  onPressed: () {
                    setState(() {
                      _showOnlyPriority = !_showOnlyPriority;
                      _applyFilters();
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Refresh button
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white.withOpacity(0.12),
                ),
                child: IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white70),
                  tooltip: 'รีเฟรชข้อมูล',
                  onPressed: () {
                    _customerCache.clear();
                    _hasMore = true;
                    _loadInitialCustomers();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Status summary
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.white.withOpacity(0.1),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _loading ? 'กำลังโหลดข้อมูล...' : 'ลูกค้าที่ซื้อใน 1 เดือนล่าสุด: ${_filteredCustomers.length}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      if (!_loading) ...[
                        Text(
                          'เรียงจากที่ซื้อนานที่สุด (ต้องติดตาม)',
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                        if (_hasMore || _isLoadingMore)
                          Text(
                            'กำลังโหลดเพิ่มเติมในเบื้องหลัง... (${_loadedCount}/${_allCustomerIds.length})',
                            style: TextStyle(color: Colors.blue.shade300, fontSize: 10),
                          ),
                        if (_isSearchMode)
                          Text(
                            'จากการค้นหา: "$_lastSearchQuery"',
                            style: const TextStyle(color: Colors.orange, fontSize: 12),
                          ),
                        if (_showOnlyPriority)
                          const Text(
                            'แสดงเฉพาะลูกค้าที่ต้องติดตามด่วน',
                            style: TextStyle(color: Colors.orange, fontSize: 12),
                          ),
                      ] else ...[
                        Text(
                          _loadingMessage,
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                        if (_totalSteps > 0)
                          Text(
                            '${(_loadingProgress * 100).toInt()}% (ขั้นตอน $_currentStep/$_totalSteps)',
                            style: const TextStyle(color: Colors.white60, fontSize: 10),
                          ),
                      ],
                    ],
                  ),
                ),
                if (_loading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          // Action buttons
          if (_selectedCustomers.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Text('เลือกแล้ว ${_selectedCustomers.length} คน', 
                    style: const TextStyle(color: Colors.white)),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: _createMissionsForSelected,
                    icon: const Icon(Icons.add_task),
                    label: const Text('สร้างภารกิจ'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => setState(() => _selectedCustomers.clear()),
                    child: const Text('ยกเลิก', style: TextStyle(color: Colors.white70)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          
          // Customer list
          Expanded(
            child: _loading && _filteredCustomers.isEmpty
                ? _buildLoadingWidget()
                : NotificationListener<ScrollNotification>(
                    onNotification: (scrollInfo) {
                      // Trigger load more when near bottom
                      if (!_loading && _hasMore && !_isSearchMode &&
                          scrollInfo.metrics.pixels > scrollInfo.metrics.maxScrollExtent - 200) {
                        _loadMoreCustomers();
                      }
                      return false;
                    },
                    child: RefreshIndicator(
                      onRefresh: () async {
                        _customerCache.clear();
                        _hasMore = true;
                        await _loadInitialCustomers();
                      },
                      child: ListView.builder(
                        itemCount: _filteredCustomers.length + (_hasMore || _isLoadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          // Loading indicator at the end
                          if (index == _filteredCustomers.length) {
                            return Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'กำลังโหลดเพิ่มเติม... (${_loadedCount}/${_allCustomerIds.length})',
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                ],
                              ),
                            );
                          }
                          
                          final customerWithHistory = _filteredCustomers[index];
                          final customer = customerWithHistory.customer;
                          final isSelected = _selectedCustomers.contains(customer.customerId);
                          
                          return _CustomerTile(
                            customerWithHistory: customerWithHistory,
                            isSelected: isSelected,
                            onSelectionChanged: (selected) {
                              setState(() {
                                if (selected) {
                                  _selectedCustomers.add(customer.customerId);
                                } else {
                                  _selectedCustomers.remove(customer.customerId);
                                }
                              });
                            },
                            onQuickMission: () => _createQuickMission(customer),
                          );
                        },
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _createQuickMission(Customer customer) async {
    // Similar to the existing _openAddPlanDialog but pre-filled with customer
    await _showQuickMissionDialog(customer);
  }

  Future<void> _createMissionsForSelected() async {
    if (_selectedCustomers.isEmpty) return;
    
    final selectedCustomerList = _filteredCustomers
        .where((ch) => _selectedCustomers.contains(ch.customer.customerId))
        .map((ch) => ch.customer)
        .toList();
    
    await _showBulkMissionDialog(selectedCustomerList);
  }

  Future<void> _showQuickMissionDialog(Customer customer) async {
    await widget.onEnsureAssigneesLoaded();
    final noteController = TextEditingController();
    DateTime plannedAt = widget.selectedDay;
    _Salesperson? chosenAssignee = widget.assignees.isNotEmpty ? widget.assignees.first : null;

    Future<void> pickDateTime() async {
      final date = await showDatePicker(
        context: context,
        initialDate: plannedAt,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      );
      if (date == null) return;
      final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(plannedAt));
      if (time == null) return;
      plannedAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    }

    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: widget.glassWidget(
          Padding(
            padding: const EdgeInsets.all(16),
            child: StatefulBuilder(
              builder: (ctx, setDialog) => SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.add_task, color: Colors.white),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text('สร้างภารกิจด่วน', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('ลูกค้า: ${customer.name} (${customer.customerId})', 
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteController,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'รายละเอียดงานที่ต้องทำ',
                        hintStyle: const TextStyle(color: Colors.white70),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('กำหนดเวลา: ', style: TextStyle(color: Colors.white70)),
                        Text(DateFormat('dd/MM/yyyy HH:mm', 'th_TH').format(plannedAt), style: const TextStyle(color: Colors.white)),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.schedule, color: Colors.white),
                          label: const Text('เปลี่ยนเวลา', style: TextStyle(color: Colors.white)),
                          onPressed: () async { await pickDateTime(); setDialog((){}); },
                          style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.white.withOpacity(0.6))),
                        )
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('มอบหมายให้: ', style: TextStyle(color: Colors.white70)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButton<_Salesperson>(
                            value: chosenAssignee,
                            dropdownColor: Colors.blueGrey.shade800,
                            items: widget.assignees
                                .map((s) => DropdownMenuItem(
                                      value: s,
                                      child: Text('${s.name} (${s.code})', style: const TextStyle(color: Colors.white)),
                                    ))
                                .toList(),
                            onChanged: (v) => setDialog(() => chosenAssignee = v),
                            underline: const SizedBox(),
                            iconEnabledColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.save_alt),
                        label: const Text('สร้างภารกิจ'),
                        onPressed: () async {
                          final user = FirebaseAuth.instance.currentUser;
                          if (user == null) return;
                          await FirebaseFirestore.instance.collection('visit_plans').add({
                            'customerId': customer.customerId,
                            'customerName': customer.name,
                            'notes': noteController.text.trim().isEmpty ? null : noteController.text.trim(),
                            'plannedAt': Timestamp.fromDate(plannedAt),
                            'createdAt': Timestamp.now(),
                            'createdBy': user.displayName ?? user.email ?? user.uid,
                            'salespersonId': user.uid,
                            'assignedToId': chosenAssignee?.id,
                            'assignedToName': chosenAssignee?.name,
                          });
                          if (mounted) Navigator.pop(ctx);
                          if (mounted) Navigator.pop(context); // Close customer list
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('สร้างภารกิจสำเร็จ')));
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showBulkMissionDialog(List<Customer> customers) async {
    await widget.onEnsureAssigneesLoaded();
    final noteController = TextEditingController();
    DateTime plannedAt = widget.selectedDay;
    _Salesperson? chosenAssignee = widget.assignees.isNotEmpty ? widget.assignees.first : null;

    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: widget.glassWidget(
          Padding(
            padding: const EdgeInsets.all(16),
            child: StatefulBuilder(
              builder: (ctx, setDialog) => SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.group_add, color: Colors.white),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('สร้างภารกิจหลายคน (${customers.length} คน)', 
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('ลูกค้าที่เลือก:', style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 8),
                    Container(
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        itemCount: customers.length,
                        itemBuilder: (context, index) {
                          final customer = customers[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            child: Text('${index + 1}. ${customer.name} (${customer.customerId})',
                              style: const TextStyle(color: Colors.white, fontSize: 12)),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteController,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'รายละเอียดงานที่ต้องทำ (จะใช้กับทุกคน)',
                        hintStyle: const TextStyle(color: Colors.white70),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('มอบหมายให้: ', style: TextStyle(color: Colors.white70)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButton<_Salesperson>(
                            value: chosenAssignee,
                            dropdownColor: Colors.blueGrey.shade800,
                            items: widget.assignees
                                .map((s) => DropdownMenuItem(
                                      value: s,
                                      child: Text('${s.name} (${s.code})', style: const TextStyle(color: Colors.white)),
                                    ))
                                .toList(),
                            onChanged: (v) => setDialog(() => chosenAssignee = v),
                            underline: const SizedBox(),
                            iconEnabledColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.save_alt),
                        label: Text('สร้างภารกิจ ${customers.length} คน'),
                        onPressed: () async {
                          final user = FirebaseAuth.instance.currentUser;
                          if (user == null) return;
                          
                          // Create missions for all selected customers
                          final batch = FirebaseFirestore.instance.batch();
                          for (final customer in customers) {
                            final docRef = FirebaseFirestore.instance.collection('visit_plans').doc();
                            batch.set(docRef, {
                              'customerId': customer.customerId,
                              'customerName': customer.name,
                              'notes': noteController.text.trim().isEmpty ? null : noteController.text.trim(),
                              'plannedAt': Timestamp.fromDate(plannedAt),
                              'createdAt': Timestamp.now(),
                              'createdBy': user.displayName ?? user.email ?? user.uid,
                              'salespersonId': user.uid,
                              'assignedToId': chosenAssignee?.id,
                              'assignedToName': chosenAssignee?.name,
                            });
                          }
                          
                          await batch.commit();
                          if (mounted) Navigator.pop(ctx);
                          if (mounted) Navigator.pop(context); // Close customer list
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('สร้างภารกิจสำเร็จ ${customers.length} คน')));
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  final _CustomerWithHistory customerWithHistory;
  final bool isSelected;
  final Function(bool) onSelectionChanged;
  final VoidCallback onQuickMission;

  const _CustomerTile({
    required this.customerWithHistory,
    required this.isSelected,
    required this.onSelectionChanged,
    required this.onQuickMission,
  });

  @override
  Widget build(BuildContext context) {
    final customer = customerWithHistory.customer;
    final hasRecentMission = customerWithHistory.hasRecentMission;
    final lastSaleDate = customerWithHistory.lastSaleDate;
    final lastVisitPlan = customerWithHistory.lastVisitPlan;

    String priorityText = '';
    Color priorityColor = Colors.white70;
    
    if (!hasRecentMission && lastVisitPlan == null) {
      priorityText = 'ไม่เคยนัดหมาย';
      priorityColor = Colors.red.shade300;
    } else if (!hasRecentMission) {
      final daysSinceLastVisit = DateTime.now().difference(lastVisitPlan!).inDays;
      priorityText = 'นัดครั้งสุดท้าย $daysSinceLastVisit วันที่แล้ว';
      priorityColor = daysSinceLastVisit > 30 ? Colors.orange.shade300 : Colors.white70;
    } else {
      priorityText = 'มีภารกิจในเดือนนี้';
      priorityColor = Colors.green.shade300;
    }

    String salesText = '';
    Color salesColor = Colors.white70;
    if (lastSaleDate != null) {
      final daysSinceLastSale = DateTime.now().difference(lastSaleDate).inDays;
      salesText = 'ซื้อครั้งสุดท้าย: ${DateFormat('dd/MM/yyyy').format(lastSaleDate)}';
      
      // Highlight customers who haven't bought recently
      if (daysSinceLastSale > 20) {
        salesText += ' (ห่างจากปัจจุบัน $daysSinceLastSale วัน - ควรติดตาม!)';
        salesColor = Colors.red.shade300;
      } else if (daysSinceLastSale > 10) {
        salesText += ' ($daysSinceLastSale วันที่แล้ว)';
        salesColor = Colors.orange.shade300;
      } else {
        salesText += ' ($daysSinceLastSale วันที่แล้ว)';
        salesColor = Colors.green.shade300;
      }
    } else {
      salesText = 'ไม่มีประวัติซื้อขาย';
      salesColor = Colors.grey;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? Colors.blue.withOpacity(0.3) : Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? Colors.blue : Colors.white.withOpacity(0.2),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: ListTile(
        leading: Checkbox(
          value: isSelected,
          onChanged: (value) => onSelectionChanged(value ?? false),
          fillColor: MaterialStateProperty.all(Colors.white.withOpacity(0.8)),
          checkColor: Colors.blue,
        ),
        title: Text(
          '${customer.name} (${customer.customerId})',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(priorityText, style: TextStyle(color: priorityColor, fontSize: 12)),
            Text(salesText, style: TextStyle(color: salesColor, fontSize: 11, fontWeight: FontWeight.w500)),
          ],
        ),
        trailing: IconButton(
          onPressed: onQuickMission,
          icon: const Icon(Icons.add_task, color: Colors.white),
          tooltip: 'สร้างภารกิจด่วน',
        ),
      ),
    );
  }
}

class _StatCard extends StatefulWidget {
  final int rank;
  final Map<String, dynamic> data;
  
  const _StatCard({required this.rank, required this.data});

  @override
  State<_StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<_StatCard> {
  bool _showAllMissions = false;
  static const int _missionsPerPage = 5;

  @override
  Widget build(BuildContext context) {
    final name = widget.data['name'] as String;
    final acceptedCount = widget.data['acceptedCount'] as int;
    final completedCount = widget.data['completedCount'] as int;
    final completedMissions = widget.data['completedMissions'] as List<VisitPlan>;
    
    Color rankColor = Colors.white;
    IconData rankIcon = Icons.person;
    
    switch (widget.rank) {
      case 1:
        rankColor = Colors.amber;
        rankIcon = Icons.emoji_events;
        break;
      case 2:
        rankColor = Colors.grey.shade300;
        rankIcon = Icons.military_tech;
        break;
      case 3:
        rankColor = Colors.brown.shade300;
        rankIcon = Icons.workspace_premium;
        break;
    }
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: rankColor,
          child: widget.rank <= 3 
            ? Icon(rankIcon, color: Colors.black87, size: 20)
            : Text('${widget.rank}', style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        ),
        title: GestureDetector(
          onTap: () => _showPersonDetails(context),
          child: Row(
            children: [
              Expanded(
                child: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const Icon(Icons.info_outline, color: Colors.white70, size: 16),
            ],
          ),
        ),
        subtitle: Text('รับภารกิจ $acceptedCount ครั้ง • ทำเสร็จ $completedCount ครั้ง', 
          style: const TextStyle(color: Colors.white70)),
        iconColor: Colors.white,
        collapsedIconColor: Colors.white,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('ภารกิจที่ทำเสร็จ:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    if (completedMissions.length > _missionsPerPage)
                      TextButton(
                        onPressed: () => setState(() => _showAllMissions = !_showAllMissions),
                        child: Text(
                          _showAllMissions ? 'ซ่อน' : 'ดูทั้งหมด (${completedMissions.length})',
                          style: const TextStyle(color: Colors.blue, fontSize: 12),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                if (completedMissions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('ยังไม่มีภารกิจที่ทำเสร็จ', style: TextStyle(color: Colors.white54, fontStyle: FontStyle.italic)),
                  )
                else
                  _buildMissionsList(completedMissions),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMissionsList(List<VisitPlan> missions) {
    if (_showAllMissions) {
      return SizedBox(
        height: 300,
        child: PageView.builder(
          itemCount: (missions.length / _missionsPerPage).ceil(),
          itemBuilder: (context, pageIndex) {
            final startIndex = pageIndex * _missionsPerPage;
            final endIndex = (startIndex + _missionsPerPage).clamp(0, missions.length);
            final pageMissions = missions.sublist(startIndex, endIndex);
            
            return Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: pageMissions.length,
                    itemBuilder: (context, index) => _buildMissionTile(pageMissions[index]),
                  ),
                ),
                if ((missions.length / _missionsPerPage).ceil() > 1)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('หน้า ${pageIndex + 1} จาก ${(missions.length / _missionsPerPage).ceil()}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
              ],
            );
          },
        ),
      );
    } else {
      return Column(
        children: missions.take(_missionsPerPage).map((mission) => _buildMissionTile(mission)).toList(),
      );
    }
  }

  Widget _buildMissionTile(VisitPlan mission) {
    final completedDate = mission.doneAt?.toDate() ?? mission.plannedAt.toDate();
    return GestureDetector(
      onTap: () => _showMissionDetails(context, mission),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${mission.customerName} (${mission.customerId})',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  Text(
                    'เสร็จ: ${DateFormat('dd/MM/yyyy HH:mm', 'th_TH').format(completedDate)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 12),
          ],
        ),
      ),
    );
  }

  Future<Map<String, String?>> _getCustomerDetails(String customerId) async {
    try {
      final customerDoc = await FirebaseFirestore.instance
          .collection('api_sale_support_cache')
          .doc(customerId)
          .get();
      
      if (customerDoc.exists) {
        final data = customerDoc.data()!;
        return {
          'address': data['mem_address']?.toString(),
          'phone': data['mem_phone']?.toString(),
          'lastSale': data['mem_lastsale']?.toString(),
        };
      }
    } catch (e) {
      print('Error loading customer details: $e');
    }
    return {'address': null, 'phone': null, 'lastSale': null};
  }

  void _showPersonDetails(BuildContext context) {
    final name = widget.data['name'] as String;
    final acceptedCount = widget.data['acceptedCount'] as int;
    final completedCount = widget.data['completedCount'] as int;
    final allMissions = widget.data['allMissions'] as List<VisitPlan>;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.8,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0052D4), Color(0xFF4364F7), Color(0xFF6FB1FC)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.white.withOpacity(0.2),
                    child: Text(name.substring(0, 1), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        Text('รับภารกิจทั้งหมด $acceptedCount ครั้ง • ทำเสร็จ $completedCount ครั้ง', 
                          style: const TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('ประวัติภารกิจทั้งหมด:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: allMissions.length,
                  itemBuilder: (context, index) {
                    final mission = allMissions[index];
                    final isCompleted = mission.doneAt != null || (mission.resultNotes?.isNotEmpty ?? false) || mission.photoUrls.isNotEmpty;
                    return Card(
                      color: Colors.white.withOpacity(0.1),
                      child: ListTile(
                        leading: Icon(
                          isCompleted ? Icons.check_circle : Icons.pending,
                          color: isCompleted ? Colors.green : Colors.orange,
                        ),
                        title: Text('${mission.customerName} (${mission.customerId})', 
                          style: const TextStyle(color: Colors.white)),
                        subtitle: FutureBuilder<Map<String, String?>>(
                          future: _getCustomerDetails(mission.customerId),
                          builder: (context, snapshot) {
                            final customerData = snapshot.data;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (customerData != null) ...[
                                  if (customerData['address']?.isNotEmpty == true)
                                    Text('📍 ${customerData['address']}', 
                                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  if (customerData['phone']?.isNotEmpty == true)
                                    Text('📞 ${customerData['phone']}', 
                                      style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                  if (customerData['lastSale']?.isNotEmpty == true)
                                    Text('🛒 ซื้อล่าสุด: ${customerData['lastSale']}', 
                                      style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                ],
                                Text('กำหนด: ${DateFormat('dd/MM/yyyy HH:mm', 'th_TH').format(mission.plannedAt.toDate())}', 
                                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                if (isCompleted && mission.doneAt != null)
                                  Text('เสร็จ: ${DateFormat('dd/MM/yyyy HH:mm', 'th_TH').format(mission.doneAt!.toDate())}', 
                                    style: const TextStyle(color: Colors.green, fontSize: 12)),
                              ],
                            );
                          },
                        ),
                        trailing: isCompleted 
                          ? IconButton(
                              icon: const Icon(Icons.visibility, color: Colors.white70),
                              onPressed: () => _showMissionDetails(ctx, mission),
                            )
                          : null,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMissionDetails(BuildContext context, VisitPlan mission) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.8,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0052D4), Color(0xFF4364F7), Color(0xFF6FB1FC)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.assignment_turned_in, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('รายละเอียดภารกิจ', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDetailRow('ลูกค้า', '${mission.customerName} (${mission.customerId})'),
                      _buildDetailRow('วันที่กำหนด', DateFormat('dd/MM/yyyy HH:mm', 'th_TH').format(mission.plannedAt.toDate())),
                      if (mission.doneAt != null)
                        _buildDetailRow('วันที่ส่ง', DateFormat('dd/MM/yyyy HH:mm', 'th_TH').format(mission.doneAt!.toDate())),
                      if (mission.notes?.isNotEmpty ?? false)
                        _buildDetailRow('รายละเอียดงาน', mission.notes!),
                      if (mission.resultNotes?.isNotEmpty ?? false)
                        _buildDetailRow('สรุปผลงาน', mission.resultNotes!),
                      if (mission.completedByName?.isNotEmpty ?? false)
                        _buildDetailRow('ผู้ส่งงาน', mission.completedByName!),
                      if (mission.photoUrls.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text('รูปภาพ:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 120,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: mission.photoUrls.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (_, i) => GestureDetector(
                              onTap: () => _showImageDialog(ctx, mission.photoUrls[i]),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  mission.photoUrls[i], 
                                  width: 160, 
                                  height: 120, 
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => Container(
                                    width: 160,
                                    height: 120,
                                    color: Colors.grey,
                                    child: const Icon(Icons.error, color: Colors.white),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text('$label:', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showImageDialog(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.8,
            maxWidth: MediaQuery.of(ctx).size.width * 0.9,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              imageUrl,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Container(
                height: 200,
                color: Colors.grey,
                child: const Center(child: Icon(Icons.error, color: Colors.white, size: 50)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// removed legacy filter enum
