// lib/screens/customer_detail_screen.dart

import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:salewang/models/customer.dart';
import 'package:salewang/models/rebate.dart';
import 'package:salewang/models/sales_order.dart';
import 'package:salewang/models/sale_support_customer.dart';
import 'package:salewang/models/customer_contact_info.dart';
import 'package:salewang/models/task_note.dart';
import 'package:salewang/models/visit_plan.dart';
import 'package:salewang/screens/customer_contact_tab.dart';
import 'package:salewang/utils/date_helper.dart';
import 'package:salewang/utils/launcher_helper.dart';
import 'package:salewang/widgets/salesperson_header.dart';
import 'package:share_plus/share_plus.dart';
import 'package:collection/collection.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';

// Route name mapping
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
Color priceLevelColor(String? level) {
  switch ((level ?? '').toUpperCase()) {
    case 'A':
    case 'A+':
    case 'A-':
      return Colors.red.shade700;
    case 'B':
      return Colors.green.shade700;
    case 'C':
      return Colors.blue.shade700;
    default:
      return Colors.grey.shade600;
  }
}

Widget priceLevelBigText(String level) {
  final c = priceLevelColor(level);
  return Text(level, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: c));
}

Widget priceLevelTitleText(String level) {
  final c = priceLevelColor(level);
  return Text(level, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: c));
}

// Hotline/support mapping: sales support code -> { phone, name }
const Map<String, Map<String, String>> kSupportPhoneByCode = {
  '0350': {'phone': '063-525-2927', 'name': 'นัท'},
  '0770': {'phone': '063-525-2234', 'name': 'ไหม'},
  '0526': {'phone': '063-525-2235', 'name': 'อั้ม'},
  '1210': {'phone': '063-525-2236', 'name': 'เฟิร์ส'},
  '0429': {'phone': '063-525-2239', 'name': 'ดา'},
  '0236': {'phone': '086-491-5416', 'name': 'อ้อม'},
  '0210': {'phone': '086-491-5414', 'name': 'หวีด'},
  '0636': {'phone': '085-081-0975', 'name': 'แป๋ว'},
};

// Data class to hold combined API and processed data
class CustomerApiData {
  final SaleSupportCustomer apiCustomer;
  final double currentMonthSales;
  final double previousMonthSales;
  final RebateData? rebateData;

  CustomerApiData({
    required this.apiCustomer,
    required this.currentMonthSales,
    required this.previousMonthSales,
    this.rebateData,
  });
}

// Main screen widget
class CustomerDetailScreen extends StatefulWidget {
  final Customer customer;

  const CustomerDetailScreen({super.key, required this.customer});

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen>
  with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Future<CustomerApiData> _customerApiDataFuture;

  @override
  void initState() {
    super.initState();
  _tabController = TabController(length: 6, vsync: this);
    _customerApiDataFuture = _fetchAndProcessDataFromFirestore();
  }

  /// Fetches all necessary data from Firestore caches and processes it.
  Future<CustomerApiData> _fetchAndProcessDataFromFirestore() async {
    final firestore = FirebaseFirestore.instance;
    final customerId = widget.customer.customerId;
    final sanitizedId = customerId.replaceAll('/', '-');

    final saleSupportFuture =
        firestore.collection('api_sale_support_cache').doc(sanitizedId).get();
    final rebateDocFuture = firestore.collection('rebate').doc(sanitizedId).get();

    final responses = await Future.wait([saleSupportFuture, rebateDocFuture]);
    final saleSupportDoc = responses[0] as DocumentSnapshot;
    final rebateDoc = responses[1] as DocumentSnapshot;

    RebateData? rebateData;
    if (rebateDoc.exists) {
      rebateData = RebateData.fromFirestore(rebateDoc);
    }

    if (saleSupportDoc.exists) {
      final customer = SaleSupportCustomer.fromFirestore(saleSupportDoc);
      final now = DateTime.now();
      final previousMonthDate = DateTime(now.year, now.month - 1, 1);

      double currentMonthSales = 0.0;
      double previousMonthSales = 0.0;

      for (var order in customer.order) {
        final orderDate = DateTime.tryParse(order.date ?? '');
        if (orderDate != null) {
          double priceBeforeVat =
              double.tryParse(order.price?.replaceAll(',', '') ?? '0') ?? 0.0;
          double priceWithVat = priceBeforeVat * 1.07;

          if (orderDate.year == now.year && orderDate.month == now.month) {
            currentMonthSales += priceWithVat;
          }
          if (orderDate.year == previousMonthDate.year &&
              orderDate.month == previousMonthDate.month) {
            previousMonthSales += priceWithVat;
          }
        }
      }

      return CustomerApiData(
        apiCustomer: customer,
        currentMonthSales: currentMonthSales,
        previousMonthSales: previousMonthSales,
        rebateData: rebateData,
      );
    } else {
      return CustomerApiData(
        apiCustomer: SaleSupportCustomer(order: [], statusOrder: []),
        currentMonthSales: 0.0,
        previousMonthSales: 0.0,
        rebateData: rebateData,
      );
    }
  }

  Widget _buildGlobalHotlineBar() {
    return FutureBuilder<CustomerApiData>(
      future: _customerApiDataFuture,
      builder: (context, snapshot) {
        String? supportCode;
        String? supportDialPhone;
        String? supportName;
        if (snapshot.hasData) {
          // Use mem_sale from API cache to identify the store manager code
          supportCode = snapshot.data!.apiCustomer.memSale?.trim();
          if (supportCode != null && kSupportPhoneByCode.containsKey(supportCode)) {
            final m = kSupportPhoneByCode[supportCode]!;
            supportDialPhone = m['phone'];
            supportName = m['name'];
          }
        }

        Widget pill(
          String title, {
          String? phone, // dialable phone number
          String? display, // optional display text (unused now)
          IconData icon = Icons.phone_in_talk_outlined,
        }) {
          final shownPhone = (phone ?? '.......');
          final hasPhone = (phone != null && phone.trim().isNotEmpty);
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              children: [
                Icon(icon, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 2.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        shownPhone,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.05),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (hasPhone) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    icon: Icon(Icons.call, size: 22, color: Colors.green.shade700),
                    onPressed: () => LauncherHelper.makeAndLogPhoneCall(
                      context: context,
                      phoneNumber: phone,
                      customer: widget.customer,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    tooltip: 'โทร',
                  ),
                ],
              ],
            ),
          );
        }

        return Material(
          color: Colors.transparent,
          child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            color: Colors.white.withOpacity(0.9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: pill('คุณกิตติพงศ์ (CEO)', phone: '086-491-4623')),
                    const SizedBox(width: 6),
                    Expanded(child: pill('คุณลิขิต (ผู้จัดการ)', phone: '094-819-3666')),
                  ],
                ),
        const SizedBox(height: 1),
                Row(
                  children: [
                    Expanded(child: pill('คุณบุญชัย (เครดิต)', phone: '094-491-3337')),
          const SizedBox(width: 6),
                    Expanded(
                      child: pill(
                        supportName != null && supportName.isNotEmpty
                            ? 'ผู้ดูแล(${supportCode ?? 'รหัส'}) - $supportName'
                            : 'ผู้ดูแล(${supportCode ?? 'รหัส'})',
                        phone: supportDialPhone,
                        icon: Icons.verified_user_outlined,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
          title: Text(widget.customer.name,
              style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          bottom: TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white.withOpacity(0.7),
            indicatorColor: Colors.yellowAccent,
            isScrollable: true,
            tabs: const [
              Tab(icon: Icon(Icons.person), text: 'ข้อมูลลูกค้า'),
              Tab(icon: Icon(Icons.sticky_note_2_outlined), text: 'บันทึกลูกค้า'),
              Tab(icon: Icon(Icons.contacts), text: 'ติดต่อลูกค้า'),
              Tab(icon: Icon(Icons.support_agent), text: 'เซลล์ซัพพอร์ท'),
              Tab(icon: Icon(Icons.receipt_long), text: 'สั่งจอง SO'),
              Tab(icon: Icon(Icons.history), text: 'ประวัติการซื้อ'),
            ],
          ),
        ),
        body: Column(
          children: [
            _buildGlobalHotlineBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _CustomerInfoTab(
                    customer: widget.customer,
                    customerApiDataFuture: _customerApiDataFuture,
                  ),
                  _CustomerNotesTab(
                    customer: widget.customer,
                    customerApiDataFuture: _customerApiDataFuture,
                  ),
                  CustomerContactTab(customer: widget.customer),
                  _SalesSupportTab(
                    customer: widget.customer,
                    customerApiDataFuture: _customerApiDataFuture,
                  ),
                  _SalesOrdersTab(customerId: widget.customer.customerId),
                  _PurchaseHistoryTab(customerApiDataFuture: _customerApiDataFuture),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

}


// --- Customer Info Tab (Merged) ---
class _CustomerInfoTab extends StatefulWidget {
  final Customer customer;
  final Future<CustomerApiData> customerApiDataFuture;

  const _CustomerInfoTab({
    required this.customer,
    required this.customerApiDataFuture,
  });

  @override
  State<_CustomerInfoTab> createState() => _CustomerInfoTabState();
}

class _CustomerInfoTabState extends State<_CustomerInfoTab> {
  List<DocumentSnapshot> _salespeople = [];
  String? _currentSupportId;
  // ignore: unused_field
  String _supportName = 'ยังไม่ได้กำหนด';
  // member_search.php (ติดต่อร้าน) ข้อมูลย่อสำหรับสรุปผู้ติดต่อหลัก
  late Future<CustomerContactInfo?> _contactInfoFuture;
  final ImagePicker _picker = ImagePicker();
  // รายละเอียดวันที่ที่เลือกจากกราฟ
  DateTime? _selectedSalesDate;
  List<OrderHistory> _selectedInvoices = const [];
  double _selectedTotal = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchSalespeopleAndSupport();
  _contactInfoFuture = _fetchContactInfo();
  }

  Future<void> _fetchSalespeopleAndSupport() async {
    final salespeopleSnapshot =
        await FirebaseFirestore.instance.collection('salespeople').get();
    if (mounted) {
      setState(() {
        _salespeople = salespeopleSnapshot.docs;
      });
    }
    await _fetchCurrentSupport();
  }

  Future<void> _fetchCurrentSupport() async {
    final doc = await FirebaseFirestore.instance
        .collection('customers')
        .doc(widget.customer.id)
        .get();
    if (mounted && doc.exists) {
      final data = doc.data();
      _currentSupportId = data?['salesSupportId'];

      String name = 'ยังไม่ได้กำหนด';
      if (_currentSupportId != null) {
        final supportDoc =
            _salespeople.firstWhereOrNull((doc) => doc.id == _currentSupportId);
        if (supportDoc != null) {
          name = supportDoc['displayName'] ?? 'N/A';
        }
      }
      setState(() {
        _supportName = name;
      });
    }
  }

  // (เมธอดเดิมสำหรับเปลี่ยนผู้ดูแลเสริมถูกนำออก เพราะไม่ใช้แล้ว)

  // Removed: per-card hotline box. We now use a global hotline bar under TabBar.

  // เปิดฟอร์มเพิ่มเบอร์ใหม่: ตำแหน่ง | ชื่อเล่น | เบอร์โทร  => บันทึก Firestore ไว้รวมแสดงกับ API
  Future<void> _showAddOfficerDialog() async {
    final careerCtrl = TextEditingController();
    final nickCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('เพิ่มผู้ติดต่อใหม่'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: careerCtrl,
                decoration: const InputDecoration(labelText: 'ตำแหน่ง (เช่น เจ้าของ/เภสัชกร/เจ้าหน้าที่ร้าน)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nickCtrl,
                decoration: const InputDecoration(labelText: 'ชื่อเล่น'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'เบอร์โทร'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () async {
              final career = careerCtrl.text.trim();
              final nick = nickCtrl.text.trim();
              final phone = phoneCtrl.text.trim();
              if (phone.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('กรุณากรอกเบอร์โทร')),
                );
                return;
              }
              try {
                await FirebaseFirestore.instance
                    .collection('customers')
                    .doc(widget.customer.id)
                    .collection('extra_officers')
                    .add({
                  'career': career.isNotEmpty ? career : 'อื่นๆ',
                  'nick': nick.isNotEmpty ? nick : '-',
                  'phone': phone,
                  'createdAt': FieldValue.serverTimestamp(),
                });
                if (mounted) Navigator.pop(ctx);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('บันทึกล้มเหลว: $e')),
                  );
                }
              }
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }

  // รายการผู้ติดต่อที่เพิ่มเอง (เก็บ Firestore) แสดงต่อท้าย 3 บทบาทหลัก
  Widget _buildExtraOfficerList() {
    final col = FirebaseFirestore.instance
        .collection('customers')
        .doc(widget.customer.id)
        .collection('extra_officers')
        .orderBy('createdAt');

    return StreamBuilder<QuerySnapshot>(
      stream: col.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) return const SizedBox.shrink();
        final docs = snap.data!.docs;
        return Column(
          children: docs.map((d) {
            final data = d.data() as Map<String, dynamic>;
            final career = (data['career']?.toString() ?? '').trim();
            final nick = (data['nick']?.toString() ?? '').trim();
            final phone = (data['phone']?.toString() ?? '').trim();
            final avatarUrl = (data['avatarUrl']?.toString() ?? '').trim();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 110,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          career.isNotEmpty ? career : 'อื่นๆ',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: () async {
                            await _showExtraOfficerAvatarOptions(d.id, currentUrl: avatarUrl.isNotEmpty ? avatarUrl : null);
                          },
                          onLongPress: () {
                            if (avatarUrl.isEmpty) return;
                            showDialog(context: context, builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(avatarUrl))));
                          },
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.grey.shade400, width: 2),
                            ),
                            child: CircleAvatar(
                              radius: 18,
                              backgroundColor: Colors.grey.shade300,
                              backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                              child: avatarUrl.isEmpty ? const Icon(Icons.person, color: Colors.white) : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.badge_outlined, size: 16, color: Colors.grey),
                              const SizedBox(width: 6),
                              Text('ชื่อเล่น: ', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                              Expanded(
                                child: Text(
                                  nick.isNotEmpty ? nick : '-',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.phone_iphone, size: 16, color: Colors.grey),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  phone.isNotEmpty ? phone : '-',
                                  softWrap: true,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                              if (phone.trim().isNotEmpty) ...[
                                IconButton(
                                  icon: const Icon(Icons.copy, size: 18),
                                  onPressed: () async {
                                    await Clipboard.setData(ClipboardData(text: phone));
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('คัดลอกเบอร์แล้ว')));
                                    }
                                  },
                                  constraints: const BoxConstraints(),
                                  padding: EdgeInsets.zero,
                                  tooltip: 'คัดลอก',
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: Icon(Icons.call, color: Colors.green.shade700, size: 18),
                                  onPressed: () => LauncherHelper.makeAndLogPhoneCall(
                                    context: context,
                                    phoneNumber: phone,
                                    customer: widget.customer,
                                  ),
                                  constraints: const BoxConstraints(),
                                  padding: EdgeInsets.zero,
                                  tooltip: 'โทร',
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Future<void> _showExtraOfficerAvatarOptions(String docId, {String? currentUrl}) async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('เลือกจากแกลเลอรี่'),
              onTap: () async {
                Navigator.pop(ctx);
                await _pickAndUploadExtraOfficerAvatar(docId, ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('ถ่ายรูปใหม่'),
              onTap: () async {
                Navigator.pop(ctx);
                await _pickAndUploadExtraOfficerAvatar(docId, ImageSource.camera);
              },
            ),
            if ((currentUrl ?? '').isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('ลบรูป', style: TextStyle(color: Colors.red)),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    await FirebaseStorage.instance.refFromURL(currentUrl!).delete();
                  } catch (_) {}
                  await FirebaseFirestore.instance
                      .collection('customers')
                      .doc(widget.customer.id)
                      .collection('extra_officers')
                      .doc(docId)
                      .update({'avatarUrl': FieldValue.delete()});
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUploadExtraOfficerAvatar(String docId, ImageSource source) async {
    final XFile? file = await _picker.pickImage(source: source, imageQuality: 70, maxWidth: 800);
    if (file == null) return;
    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('customers/${widget.customer.id}/extra_officers/$docId/avatar.jpg');
      await ref.putFile(File(file.path));
      final url = await ref.getDownloadURL();
      await FirebaseFirestore.instance
          .collection('customers')
          .doc(widget.customer.id)
          .collection('extra_officers')
          .doc(docId)
          .update({'avatarUrl': url});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('อัปโหลดรูปไม่สำเร็จ: $e')));
      }
    }
  }

  // ===== Avatar helpers for each role (owner / pharmacist / staff) =====
  Stream<DocumentSnapshot<Map<String, dynamic>>> _avatarDoc(String roleKey) {
    return FirebaseFirestore.instance
        .collection('customers')
        .doc(widget.customer.id)
        .collection('officer_avatars')
        .doc(roleKey)
        .snapshots();
  }

  Future<void> _pickAndUploadAvatar(String roleKey, ImageSource source) async {
    final XFile? file = await _picker.pickImage(source: source, imageQuality: 70, maxWidth: 800);
    if (file == null) return;
    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('customers/${widget.customer.id}/officer_avatars/$roleKey.jpg');
      await ref.putFile(File(file.path));
      final url = await ref.getDownloadURL();
      await FirebaseFirestore.instance
          .collection('customers')
          .doc(widget.customer.id)
          .collection('officer_avatars')
          .doc(roleKey)
          .set({'url': url, 'updatedAt': FieldValue.serverTimestamp()});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('อัปโหลดรูปไม่สำเร็จ: $e')));
      }
    }
  }

  Future<void> _showAvatarOptions(String roleKey, {String? currentUrl}) async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('เลือกจากแกลเลอรี่'),
              onTap: () async {
                Navigator.pop(ctx);
                await _pickAndUploadAvatar(roleKey, ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('ถ่ายรูปใหม่'),
              onTap: () async {
                Navigator.pop(ctx);
                await _pickAndUploadAvatar(roleKey, ImageSource.camera);
              },
            ),
            if ((currentUrl ?? '').isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('ลบรูป', style: TextStyle(color: Colors.red)),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    await FirebaseStorage.instance.refFromURL(currentUrl!).delete();
                  } catch (_) {}
                  await FirebaseFirestore.instance
                      .collection('customers')
                      .doc(widget.customer.id)
                      .collection('officer_avatars')
                      .doc(roleKey)
                      .delete();
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleLabelWithAvatar(String title, String roleKey) {
    Color borderColor;
    switch (roleKey) {
      case 'owner':
        borderColor = const Color(0xFFDAA520); // goldenrod
        break;
      case 'pharmacist':
        borderColor = Colors.blueAccent;
        break;
      case 'staff':
      default:
        borderColor = Colors.green;
    }

    return SizedBox(
      width: 90,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _avatarDoc(roleKey),
            builder: (context, snap) {
              final url = (snap.data?.data()?['url']?.toString() ?? '').trim();
              return InkWell(
                onTap: () => _showAvatarOptions(roleKey, currentUrl: url.isNotEmpty ? url : null),
                onLongPress: () {
                  if (url.isEmpty) return;
                  showDialog(
                    context: context,
                    builder: (_) => Dialog(
                      child: InteractiveViewer(child: Image.network(url)),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: borderColor, width: 2),
                  ),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.grey.shade300,
                    backgroundImage: url.isNotEmpty ? NetworkImage(url) : null,
                    child: url.isEmpty ? const Icon(Icons.person, color: Colors.white) : null,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ดึงข้อมูลแถบ "ติดต่อลูกค้า" จาก API เดียวกัน เพื่อสรุป 3 บทบาทหลัก
  Future<CustomerContactInfo?> _fetchContactInfo() async {
    try {
      const String bearerToken =
          'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJtZW1fY29kZSI6Ii4wNjM1In0.5U_Yle8l5bZqOVTxqlvQo36XyQaW2bf3Q-h91bw3UL8';
      final url = Uri.https('www.wangpharma.com', '/API/appV3/member_search.php',
          {'search': widget.customer.customerId});

      final response = await http
          .get(url, headers: {'Authorization': 'Bearer $bearerToken'});
      if (response.statusCode == 200 &&
          response.body.isNotEmpty &&
          response.body != "[]") {
        final list = customerContactInfoFromJson(response.body);
        return list.isNotEmpty ? list.first : null;
      }
      return null;
    } catch (_) {
      return null;
    }
  }


  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                const SalespersonHeader(),
                const SizedBox(height: 8),
                // หมายเหตุเร่งด่วน/ติดต่อด่วนถูกย้ายออกในเวอร์ชันนี้
                _buildCombinedInfoCard(context),
                const SizedBox(height: 16),
                _DailySalesGraph(
                  customerApiDataFuture: widget.customerApiDataFuture,
                  onDaySelected: (date, invoices, total) {
                    setState(() {
                      _selectedSalesDate = date;
                      _selectedInvoices = invoices;
                      _selectedTotal = total;
                    });
                  },
                ),
                const SizedBox(height: 12),
                _buildDailyDetailCard(),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDailyDetailCard() {
    final date = _selectedSalesDate;
    final invoices = _selectedInvoices;
    final total = _selectedTotal;
    final money = NumberFormat("#,##0.00", "en_US").format(total);
    final titleDate = date != null ? DateFormat('d MMMM yyyy', 'th_TH').format(date) : null;

    return Card(
      elevation: 4,
      color: Colors.white.withOpacity(0.95),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long, color: Colors.indigo),
                const SizedBox(width: 8),
                Text('รายละเอียดรายวัน', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            if (date == null) ...[
              const Text('แตะที่แท่งกราฟเพื่อดูรายละเอียดของวันนั้น', style: TextStyle(color: Colors.black54)),
            ] else ...[
              Text('วันที่ $titleDate', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('ยอดเงินรวมทั้งหมด $money บาท', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              if (invoices.isEmpty)
                const Text('ไม่มีรายการใบกำกับในวันนี้')
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: invoices.length,
                  separatorBuilder: (_, __) => const Divider(height: 12),
                  itemBuilder: (context, i) {
                    final inv = invoices[i];
                    final p = double.tryParse(inv.price?.replaceAll(',', '') ?? '0') ?? 0.0;
                    final pText = NumberFormat("#,##0.00", "en_US").format(p);
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text('เลขที่ใบกำกับ ${inv.bill ?? '-'}')),
                        Text('$pText บาท', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    );
                  },
                ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildCombinedInfoCard(BuildContext context) {
    return Card(
      elevation: 4,
      color: Colors.white.withOpacity(0.9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text('ข้อมูลลูกค้าและผู้ติดต่อ',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: Colors.black87, fontWeight: FontWeight.bold)),
        initiallyExpanded: true,
        childrenPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPrimaryInfoContent(context),
          const Divider(height: 24),
          _buildContactsContent(context),
        ],
      ),
    );
  }

  Widget _buildContactsContent(BuildContext context) {
    final customerDocStream = FirebaseFirestore.instance
        .collection('customers')
        .doc(widget.customer.id)
        .snapshots();

    return StreamBuilder<DocumentSnapshot>(
      stream: customerDocStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final updatedCustomer = Customer.fromFirestore(snapshot.data!);
        final contacts = updatedCustomer.contacts;
        final firstContact = contacts.isNotEmpty ? contacts.first : null;

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          margin: EdgeInsets.zero,
          child: ExpansionTile(
            title: Row(
              children: [
                const Icon(Icons.phone_in_talk_outlined, color: Colors.grey),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    firstContact != null ? '${firstContact['name']} (${firstContact['phone']})' : 'เบอร์โทรศัพท์และผู้ติดต่อ',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (firstContact != null)
                  IconButton(
                    icon: const Icon(Icons.call, color: Colors.green),
                    tooltip: 'โทรหาผู้ติดต่อหลัก',
                    onPressed: () => LauncherHelper.makeAndLogPhoneCall(
                      context: context,
                      phoneNumber: firstContact['phone'] ?? '',
                      customer: updatedCustomer,
                    ),
                  ),
                const Icon(Icons.keyboard_arrow_down),
              ],
            ),
            children: [
              if (contacts.isEmpty)
                const Center(child: Padding(padding: EdgeInsets.all(8.0), child: Text('ไม่มีข้อมูลผู้ติดต่อ')))
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: contacts.length,
                  itemBuilder: (context, index) {
                    return _buildContactRow(context, updatedCustomer, index);
                  },
                  separatorBuilder: (context, index) => const Divider(height: 1, indent: 16, endIndent: 16),
                ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('เพิ่ม/แก้ไขเบอร์โทร'),
                  onPressed: () => _showContactDialog(context, existingContacts: contacts),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPrimaryInfoContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ร้านค้า + เส้นทาง (จาก Firestore api_sale_support_cache)
        FutureBuilder<CustomerApiData>(
          future: widget.customerApiDataFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox.shrink();
            final api = snapshot.data!.apiCustomer;
            final storeName = api.memName ?? widget.customer.name;
            final routeCode = (api.toMap()['route_code']?.toString() ?? '').trim();
            final routeName = routeCode.isNotEmpty ? (kRouteNameMap[routeCode] ?? routeCode) : '-';
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.storefront, color: Colors.indigo, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            storeName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.alt_route, color: Colors.grey.shade700, size: 16),
                        const SizedBox(width: 6),
                        Text('เส้นทาง: ', style: TextStyle(color: Colors.grey.shade700)),
                        Text(routeName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _BranchLinksSection(customer: widget.customer),
                  ],
                ),
              ),
            );
          },
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
          ),
          child: RichText(
            text: TextSpan(
              style: DefaultTextStyle.of(context).style.copyWith(fontSize: 14),
              children: [
                TextSpan(text: 'รหัสลูกค้า: ', style: TextStyle(color: Colors.grey.shade700)),
                TextSpan(text: '${widget.customer.customerId} ', style: const TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(text: '| ราคา: ', style: TextStyle(color: Colors.grey.shade700)),
                TextSpan(text: '${widget.customer.p} ', style: const TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(text: '| ผู้ดูแล: ', style: TextStyle(color: Colors.grey.shade700)),
                TextSpan(text: widget.customer.salesperson, style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // สรุปผู้ติดต่อหลัก: เจ้าของ / เภสัชกร / เจ้าหน้าที่ร้าน (ดึงจาก API member_search.php)
        FutureBuilder<CustomerContactInfo?>(
          future: _contactInfoFuture,
          builder: (context, snapshot) {
            final contactInfo = snapshot.data;
            // เตรียม Officer ตามบทบาทที่ต้องการ
            Officer? findByCareer(String key) {
              if (contactInfo == null) return null;
              return contactInfo.officer.firstWhereOrNull((o) {
                final c = o.career.trim();
                return c == key || c.contains(key);
              });
            }

            final owner = findByCareer('เจ้าของ');
            final pharmacist = findByCareer('เภสัชกร');
            final staff = findByCareer('เจ้าหน้าที่ร้าน');

            Widget row(String title, Officer? o) {
              final nick = (o?.nick.trim().isNotEmpty ?? false)
                  ? o!.nick.trim()
                  : '-';
              final phone = (o?.phone.trim().isNotEmpty ?? false)
                  ? o!.phone.trim()
                  : '-';
              // map role title to a stable roleKey for avatar storage
              String roleKey;
              if (title.contains('เจ้าของ')) {
                roleKey = 'owner';
              } else if (title.contains('เภสัช')) {
                roleKey = 'pharmacist';
              } else {
                roleKey = 'staff';
              }
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildRoleLabelWithAvatar(title, roleKey),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.max,
                              children: [
                                const Icon(Icons.badge_outlined, size: 17, color: Colors.grey),
                                const SizedBox(width: 6),
                                Text('ชื่อเล่น: ', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                                Expanded(
                                  child: Text(nick, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                const Icon(Icons.phone_iphone, size: 17, color: Colors.grey),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    phone,
                                    softWrap: true,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                ),
                                if (phone != '-') ...[
                                  IconButton(
                                    icon: const Icon(Icons.copy, size: 17),
                                    onPressed: () async {
                                      await Clipboard.setData(ClipboardData(text: phone));
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('คัดลอกเบอร์แล้ว')));
                                      }
                                    },
                                    constraints: const BoxConstraints(),
                                    padding: EdgeInsets.zero,
                                    tooltip: 'คัดลอก',
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: Icon(Icons.call, color: Colors.green.shade700, size: 17),
                                    onPressed: () => LauncherHelper.makeAndLogPhoneCall(
                                      context: context,
                                      phoneNumber: phone,
                                      customer: widget.customer,
                                    ),
                                    constraints: const BoxConstraints(),
                                    padding: EdgeInsets.zero,
                                    tooltip: 'โทร',
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            // โครงร่าง UI ระหว่างรอโหลดข้อมูล
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: const LinearProgressIndicator(minHeight: 3),
              );
            }

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.group_outlined, size: 18, color: Colors.grey),
                      const SizedBox(width: 8),
                      const Text('ผู้ติดต่อหลัก',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _showAddOfficerDialog,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('เพิ่มเบอร์ใหม่'),
                        style: TextButton.styleFrom(
                          visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  row('เจ้าของ', owner),
                  row('เภสัชกร', pharmacist),
                  row('เจ้าหน้าที่ร้าน', staff),
                  const SizedBox(height: 4),
                  _buildExtraOfficerList(),
                ],
              ),
            );
          },
        ),
        FutureBuilder<CustomerApiData>(
          future: widget.customerApiDataFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const LinearProgressIndicator();
            }
            if (snapshot.hasData) {
              final apiData = snapshot.data!;
              final salesSupportCode = apiData.apiCustomer.memSalesupport;
              String salesSupportDisplayName = 'ยังไม่ได้กำหนด';

              if (salesSupportCode != null && salesSupportCode.isNotEmpty) {
                final supportDoc = _salespeople.firstWhereOrNull((doc) => doc['employeeId'] == salesSupportCode);
                if (supportDoc != null) {
                  salesSupportDisplayName = '${supportDoc['displayName'] ?? 'N/A'} ($salesSupportCode)';
                } else {
                  salesSupportDisplayName = salesSupportCode;
                }
              }
              return _buildSalesSupportSelector(salesSupportDisplayName);
            }
            return _buildSalesSupportSelector('กำลังโหลด...');
          },
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.location_on,
                color: Theme.of(context).primaryColor, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${widget.customer.address1} ${widget.customer.address2}',
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
        const Divider(height: 24),
        FutureBuilder<CustomerApiData>(
          future: widget.customerApiDataFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: LinearProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                  child: Text('ไม่สามารถโหลดยอดขายได้',
                      style: TextStyle(color: Colors.red.shade700)));
            }
            if (snapshot.hasData) {
              final apiData = snapshot.data!;
              final balance = double.tryParse(
                      apiData.apiCustomer.memBalance?.replaceAll(',', '') ?? '0') ??
                  0.0;

              return Column(
                children: [
                  _buildSalesSummaryBlock(
                    previousMonthSales: apiData.previousMonthSales,
                    currentMonthSales: apiData.currentMonthSales,
                    monthlyTarget: apiData.rebateData?.monthlyTarget ?? 0.0,
                  ),
                  const Divider(height: 24),
                  _buildApiDetailRow(
                    context,
                    Icons.calendar_today_outlined,
                    "ขายล่าสุด",
                    DateHelper.formatDateToThai(
                        apiData.apiCustomer.memLastsale ?? ''),
                  ),
                  _buildApiDetailRow(
                    context,
                    Icons.payment_outlined,
                    "ชำระล่าสุด",
                    DateHelper.formatDateToThai(
                        apiData.apiCustomer.memLastpayments ?? ''),
                  ),
                  _buildApiDetailRow(
                    context,
                    Icons.account_balance_wallet_outlined,
                    "ยอดค้าง",
                    NumberFormat("#,##0.00", "en_US").format(balance),
                    valueColor: balance > 0
                        ? Colors.red.shade700
                        : Colors.green.shade700,
                  ),
                ],
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ],
    );
  }

  Widget _buildSalesSupportSelector(String supportDisplay) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _InfoChip(
                label: 'เซลล์ซัพพอร์ท',
                value: supportDisplay,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LayoutBuilder(builder: (context, constraints) {
          // Center the whole row, auto-wrap when tight
          return Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 6,
            children: [
              // Leftmost: latest price level + approved date + urgency (if any)
              FutureBuilder<QuerySnapshot>(
                future: FirebaseFirestore.instance
                    .collection('task_notes')
                    .where('customerId', isEqualTo: widget.customer.id)
                    .orderBy('createdAt', descending: true)
                    .limit(8)
                    .get(),
                builder: (context, snap) {
                  if (snap.hasError || !snap.hasData) return const SizedBox.shrink();
                  final docs = snap.data!.docs;
                  String? level;
                  Timestamp? approvedAt;
                  String? urgency;
                  for (final d in docs) {
                    final data = d.data() as Map<String, dynamic>;
                    if ((data['title']?.toString() ?? '') == 'ราคาใหม่' &&
                        (data['priceLevel']?.toString().isNotEmpty ?? false)) {
                      level = data['priceLevel'].toString();
                      if (data['approvedAt'] is Timestamp) {
                        approvedAt = data['approvedAt'] as Timestamp?;
                      }
                      if ((data['urgency']?.toString().isNotEmpty ?? false)) {
                        urgency = data['urgency'].toString();
                      }
                      break;
                    }
                  }
                  if (level == null && approvedAt == null && urgency == null) {
                    return const SizedBox.shrink();
                  }
                  final List<Widget> chips = [];
                  if (level != null) {
                    final c = priceLevelColor(level);
                    chips.add(Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: c.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: c.withOpacity(0.4)),
                      ),
                      child: Text(level, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: c)),
                    ));
                  }
                  if (approvedAt != null) {
                    final d = approvedAt.toDate();
                    final text = DateFormat('dd/MM/yy').format(d);
                    chips.add(Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.withOpacity(0.3)),
                      ),
                      child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.black87)),
                    ));
                  }
                  if (urgency != null) {
                    Color bg;
                    String label;
                    switch (urgency) {
                      case 'urgent':
                        bg = Colors.red;
                        label = 'เร่งด่วน';
                        break;
                      case 'asap':
                        bg = Colors.green;
                        label = 'ทำทันที';
                        break;
                      default:
                        bg = Colors.amber;
                        label = 'รอแก้ไข';
                    }
                    chips.add(Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                    ));
                  }
                  return Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: chips,
                  );
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.price_change, size: 16),
                label: const Text('ราคาใหม่', overflow: TextOverflow.ellipsis),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: const Size(0, 32),
                  visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: _openNewPriceDialog,
              ),
            ],
          );
        }),
      ],
    );
  }

  Future<void> _openNewPriceDialog() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กรุณาเข้าสู่ระบบ')));
      return;
    }
    String approverName = user.displayName ?? user.email?.split('@').first ?? 'ไม่ทราบชื่อ';
    DateTime? approvedDate = DateTime.now();
    String? priceLevel;
    String? urgency;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setStateDialog) {
          Widget urgencyChip(String label, String value, Color bg) {
            final selected = urgency == value;
            return ChoiceChip(
              label: Text(label, style: const TextStyle(color: Colors.white)),
              selected: selected,
              onSelected: (_) => setStateDialog(() => urgency = value),
              selectedColor: bg,
              backgroundColor: bg.withOpacity(0.7),
            );
          }

          return AlertDialog(
            title: const Text('ราคาใหม่'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('1) เลือกผู้อนุมัติ (จากไอดีผู้ล็อกอิน)'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: TextEditingController(text: approverName),
                    readOnly: true,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.verified_user), labelText: 'ผู้อนุมัติ'),
                  ),
                  const SizedBox(height: 12),
                  const Text('2) วันที่อนุมัติ'),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: approvedDate ?? now,
                        firstDate: DateTime(now.year - 1),
                        lastDate: DateTime(now.year + 1),
                      );
                      if (picked != null) setStateDialog(() => approvedDate = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.event), labelText: 'วัน/เดือน/ปี'),
                      child: Text(approvedDate != null ? DateFormat('dd/MM/yyyy').format(approvedDate!) : 'เลือกวันที่'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('3.1) ระดับราคา'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: priceLevel,
                    items: const [
                      DropdownMenuItem(value: 'A+', child: Text('A+')),
                      DropdownMenuItem(value: 'A', child: Text('A')),
                      DropdownMenuItem(value: 'A-', child: Text('A-')),
                      DropdownMenuItem(value: 'B', child: Text('B')),
                      DropdownMenuItem(value: 'C', child: Text('C')),
                    ],
                    onChanged: (v) => setStateDialog(() => priceLevel = v),
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.stacked_bar_chart), hintText: 'เลือกระดับราคา'),
                  ),
                  const SizedBox(height: 12),
                  const Text('3.2) ความเร่งด่วน'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      urgencyChip('เร่งด่วน', 'urgent', Colors.red),
                      urgencyChip('ทำทันที', 'asap', Colors.green),
                      urgencyChip('รอแก้ไข', 'pending_fix', Colors.amber.shade700),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
              ElevatedButton(
                onPressed: (approvedDate != null && priceLevel != null && urgency != null)
                    ? () async {
                        try {
                          await FirebaseFirestore.instance.collection('task_notes').add({
                            'customerId': widget.customer.id,
                            'customerCode': widget.customer.customerId,
                            'customerName': widget.customer.name,
                            'title': 'ราคาใหม่',
                            'details': 'ระดับราคา: ' + priceLevel! + ' | ความเร่งด่วน: ' +
                                (urgency == 'urgent' ? 'เร่งด่วน' : urgency == 'asap' ? 'ทำทันที' : 'รอแก้ไข'),
                            'taskDateTime': Timestamp.fromDate(approvedDate!),
                            'imageUrls': <String>[],
                            'createdBy': approverName,
                            'createdById': user.uid,
                            'createdAt': FieldValue.serverTimestamp(),
                            'status': 'approved',
                            'approvedBy': approverName,
                            'approvedAt': Timestamp.fromDate(approvedDate!),
                            'priceLevel': priceLevel,
                            'urgency': urgency,
                          });
                          if (mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('บันทึก ราคาใหม่ แล้ว')));
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')));
                          }
                        }
                      }
                    : null,
                child: const Text('บันทึก'),
              ),
            ],
          );
        });
      },
    );
  }

  Widget _buildSalesSummaryBlock({
    required double previousMonthSales,
    required double currentMonthSales,
    required double monthlyTarget,
  }) {
    final currencyFormat = NumberFormat("#,##0", "en_US");
    final shortfall = monthlyTarget - currentMonthSales;
    final percentage =
        monthlyTarget > 0 ? (currentMonthSales / monthlyTarget) * 100 : 0.0;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildSummaryBox('เดือนก่อน', previousMonthSales, Colors.grey.shade600),
            _buildSummaryBox(
                'เดือนปัจจุบัน', currentMonthSales, Colors.red.shade700),
            _buildSummaryBox('เป้าหมาย', monthlyTarget, Colors.orange.shade800),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              shortfall > 0
                  ? 'เป้าในเดือนขาดอีก ${currencyFormat.format(shortfall)} บาท | ปัจจุบัน ${percentage.toStringAsFixed(1)}%'
                  : 'ยอดขายถึงเป้าแล้ว!',
              style: TextStyle(
                fontSize: 14,
                color: shortfall > 0
                    ? Colors.red.shade700
                    : Colors.green.shade700,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryBox(String label, double value, Color color) {
    final currencyFormat = NumberFormat("#,##0", "en_US");
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(
              currencyFormat.format(value),
              style: TextStyle(
                fontFamily: 'Orbitron',
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildContactRow(
      BuildContext context, Customer currentCustomer, int index) {
    final contact = currentCustomer.contacts[index];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 16.0),
      child: Row(
        children: [
          const Icon(Icons.person_pin_circle_outlined,
              color: Colors.grey, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(contact['name'] ?? 'N/A',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                Text(contact['phone'] ?? 'N/A',
                    style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.call, color: Colors.green, size: 20),
            tooltip: 'โทร',
            onPressed: () => LauncherHelper.makeAndLogPhoneCall(
              context: context,
              phoneNumber: contact['phone'] ?? '',
              customer: currentCustomer,
            ),
          ),
        ],
      ),
    );
  }

  void _showContactDialog(BuildContext context,
      {required List<Map<String, String>> existingContacts,
      int? contactIndex}) {
    final bool isEditing = contactIndex != null;
    final contact =
        isEditing ? existingContacts[contactIndex] : {'name': '', 'phone': ''};

    final nameController = TextEditingController(text: contact['name']);
    final phoneController = TextEditingController(text: contact['phone']);
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isEditing ? 'แก้ไขผู้ติดต่อ' : 'เพิ่มผู้ติดต่อใหม่'),
        content: Form(
          key: formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'ชื่อผู้ติดต่อ'),
              validator: (value) =>
                  (value == null || value.isEmpty) ? 'กรุณาใส่ชื่อ' : null,
            ),
            TextFormField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'เบอร์โทรศัพท์'),
              validator: (value) =>
                  (value == null || !RegExp(r'^[0-9-]{9,}$').hasMatch(value))
                      ? 'รูปแบบเบอร์โทรไม่ถูกต้อง'
                      : null,
            ),
          ]),
        ),
        actions: [
          if (isEditing)
            TextButton(
              onPressed: () async {
                List<Map<String, String>> updatedContacts =
                    List.from(existingContacts);
                updatedContacts.removeAt(contactIndex);
                await FirebaseFirestore.instance
                    .collection('customers')
                    .doc(widget.customer.id)
                    .update({'contacts': updatedContacts});
                Navigator.of(dialogContext).pop();
              },
              child: const Text('ลบ', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('ยกเลิก')),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                final newContact = {
                  'name': nameController.text,
                  'phone': phoneController.text
                };
                List<Map<String, String>> updatedContacts =
                    List.from(existingContacts);
                if (isEditing) {
                  updatedContacts[contactIndex] = newContact;
                } else {
                  updatedContacts.add(newContact);
                }
                await FirebaseFirestore.instance
                    .collection('customers')
                    .doc(widget.customer.id)
                    .update({'contacts': updatedContacts});
                Navigator.of(dialogContext).pop();
              }
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }
}

// --- UPDATED WIDGET: Daily Sales Graph (Bar Chart) ---
class _DailySalesGraph extends StatefulWidget {
  final Future<CustomerApiData> customerApiDataFuture;
  final void Function(DateTime date, List<OrderHistory> invoices, double total)? onDaySelected;
  const _DailySalesGraph({required this.customerApiDataFuture, this.onDaySelected});

  @override
  State<_DailySalesGraph> createState() => _DailySalesGraphState();
}

class _DailySalesGraphState extends State<_DailySalesGraph> {
  DateTime? _startDate;
  DateTime? _endDate;
  final ScrollController _chartScrollController = ScrollController();

  // แสดงโหมดช่วงวันที่
  RangeView _rangeView = RangeView.thisMonth;

  // Data holders
  Map<DateTime, double> _allDailySales = {};
  Map<DateTime, List<OrderHistory>> _allDailyInvoices = {};
  List<MapEntry<DateTime, double>> _filteredSalesData = [];

  @override
  void initState() {
    super.initState();
    _setFilterToCurrentMonth();
  }
  
  void _setFilterToCurrentMonth() {
      final now = DateTime.now();
      _startDate = DateTime(now.year, now.month, 1);
      _endDate = DateTime(now.year, now.month + 1, 0);
  _rangeView = RangeView.thisMonth;
      _applyDateFilter();
  }

  // ล่าสุด 7 วัน รวมวันนี้
  void _setFilterToLast7Days() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _startDate = today.subtract(const Duration(days: 6));
      _endDate = today;
  _rangeView = RangeView.last7;
    });
    _applyDateFilter();
  }
  
  Future<void> _showDateRangePicker() async {
    // จำกัดย้อนหลังได้เฉพาะ 2 เดือนล่าสุด
    final now = DateTime.now();
    final earliest = DateTime(now.year, now.month - 2, 1);

    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: earliest,
      lastDate: now,
      initialDateRange: DateTimeRange(
        start: _startDate ?? now.subtract(const Duration(days: 29)),
        end: _endDate ?? now,
      ),
      locale: const Locale('th', 'TH'),
    );

    if (picked != null) {
      setState(() {
        _startDate = DateTime(picked.start.year, picked.start.month, picked.start.day);
        _endDate = DateTime(picked.end.year, picked.end.month, picked.end.day);
  _rangeView = RangeView.custom;
      });
      _applyDateFilter();
    }
  }

  void _processSalesData(List<OrderHistory> orders) {
    final Map<DateTime, double> dailySales = {};
    final Map<DateTime, List<OrderHistory>> dailyInvoices = {};

    for (var order in orders) {
      final orderDate = DateTime.tryParse(order.date ?? '');
      if (orderDate != null) {
        final dayOnly = DateTime(orderDate.year, orderDate.month, orderDate.day);
        final price = double.tryParse(order.price?.replaceAll(',', '') ?? '0') ?? 0.0;
        
        dailySales[dayOnly] = (dailySales[dayOnly] ?? 0) + price;
        dailyInvoices.putIfAbsent(dayOnly, () => []).add(order);
      }
    }
    _allDailySales = dailySales;
    _allDailyInvoices = dailyInvoices;
    _applyDateFilter();
  }

  void _applyDateFilter() {
    if (_startDate == null || _endDate == null) {
      if (mounted) setState(() => _filteredSalesData = []);
      return;
    }

    final start = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
    final end = DateTime(_endDate!.year, _endDate!.month, _endDate!.day);

    final result = <MapEntry<DateTime, double>>[];
    for (DateTime d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      result.add(MapEntry(d, _allDailySales[d] ?? 0.0));
    }

    if (mounted) {
      // ซ่อนวันที่มียอด 0 เพื่อความสวยงาม ให้แท่งเรียงชิดกัน
      final filteredNoZero = result.where((e) => e.value != 0.0).toList();
      setState(() => _filteredSalesData = filteredNoZero);
      // ถ้าจำนวนวันมากกว่า 7 ให้เลื่อนไปด้านหน้าสุด (ขวาสุด)
      if (_filteredSalesData.length > 7) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_chartScrollController.hasClients) {
            _chartScrollController.animateTo(
              _chartScrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            );
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      color: Colors.white.withOpacity(0.9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'กราฟแสดงยอดขาย',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                // ใช้ Flexible + Wrap เพื่อหลีกเลี่ยง overflow เมื่อหน้าจอแคบ
                Flexible(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: _setFilterToLast7Days,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            backgroundColor: _rangeView == RangeView.last7 ? Colors.indigo.shade50 : null,
                          ),
                          child: const Text('7 วัน', style: TextStyle(fontSize: 12)),
                        ),
                        OutlinedButton(
                          onPressed: _setFilterToCurrentMonth,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            backgroundColor: _rangeView == RangeView.thisMonth ? Colors.indigo.shade50 : null,
                          ),
                          child: const Text('ภายในเดือน', style: TextStyle(fontSize: 12)),
                        ),
                        ElevatedButton.icon(
                          onPressed: _showDateRangePicker,
                          icon: const Icon(Icons.date_range, size: 16),
                          label: const Text('ระบุวันที่', style: TextStyle(fontSize: 12)),
                          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FutureBuilder<CustomerApiData>(
              future: widget.customerApiDataFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(height: 250, child: Center(child: CircularProgressIndicator()));
                }
                if (snapshot.hasError || !snapshot.hasData || snapshot.data!.apiCustomer.order.isEmpty) {
                  return const SizedBox(height: 250, child: Center(child: Text('ไม่มีข้อมูลยอดขาย')));
                }
                
                // Process data only once after future completes
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_allDailySales.isEmpty) {
                     _processSalesData(snapshot.data!.apiCustomer.order);
                  }
                });
                
                if (_filteredSalesData.isEmpty) {
                  return const SizedBox(height: 250, child: Center(child: Text('ไม่มีข้อมูลยอดขายในช่วงที่เลือก')));
                }

                // ทำให้กราฟเลื่อนซ้ายขวาได้ และ freeze แกน Y เมื่อเลือก "ภายในเดือน"
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final barsCount = _filteredSalesData.length.toDouble();
                    final barsPerScreen = _getBarsPerScreen();
                    final widthFactor = barsCount > barsPerScreen ? (barsCount / barsPerScreen) : 1.0;
                    final chartWidth = constraints.maxWidth * widthFactor;
                    final maxSales = _getMaxSales();

                    // กรณีต้องการ freeze แกน Y ในเดือนและกราฟยาวกว่าหน้าจอ
                    if (_rangeView == RangeView.thisMonth && chartWidth > constraints.maxWidth) {
                      const axisWidth = 40.0;
                      return Row(
                        children: [
                          SizedBox(
                            width: axisWidth,
                            height: 250,
                            child: _buildStaticYAxis(maxSales),
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              controller: _chartScrollController,
                              child: SizedBox(
                                width: chartWidth - axisWidth,
                                height: 250,
                                child: BarChart(
                                  _buildBarChartData(showLeftTitles: false, forcedMaxY: _normalizedMaxY(maxSales)),
                                  swapAnimationDuration: const Duration(milliseconds: 300),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }

                    // ปกติ
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      controller: _chartScrollController,
                      child: SizedBox(
                        width: chartWidth,
                        height: 250,
                        child: BarChart(
                          _buildBarChartData(forcedMaxY: _normalizedMaxY(maxSales)),
                          swapAnimationDuration: const Duration(milliseconds: 300),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  double _getBarsPerScreen() {
    switch (_rangeView) {
      case RangeView.last7:
        return 7; // แสดงประมาณ 7 แท่งพอดีจอ
      case RangeView.thisMonth:
        return 7; // ถ้าเกิน 7 วันให้เลื่อน
      case RangeView.custom:
        return 10; // คัสตอมให้กว้างขึ้นเล็กน้อย
    }
  }

  double _getMaxSales() {
    return _filteredSalesData.isEmpty
        ? 0.0
        : _filteredSalesData.map((e) => e.value).reduce(max);
  }

  double _normalizedMaxY(double maxSales) {
    // ปรับ maxY ให้เป็นค่าที่อ่านง่ายขึ้นเล็กน้อยถ้าต้องการ
    return (maxSales > 0 ? maxSales * 1.2 : 1.0);
  }

  BarChartData _buildBarChartData({bool showLeftTitles = true, double? forcedMaxY}) {
  final maxSales = _getMaxSales();
  // ตัวเลขเต็มด้วยคอมมา
  final currencyFormat = NumberFormat('#,##0', 'en_US');

    return BarChartData(
      maxY: forcedMaxY ?? (maxSales > 0 ? maxSales * 1.2 : 1.0),
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          fitInsideVertically: true,
          fitInsideHorizontally: true,
          tooltipPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              // แสดงเฉพาะ "ยอดรวมของวันนั้น" เป็นตัวเลขสั้นๆ เหนือแท่ง
              // ใช้ค่า rod.toY โดยตรงเพื่อเลี่ยงปัญหาดัชนีไม่ตรงเมื่อข้อมูลถูกกรอง/อัปเดต
              final total = rod.toY;
              final short = NumberFormat('#,##0', 'en_US').format(total);
              return BarTooltipItem(
                short,
                const TextStyle(color: Colors.amber, fontWeight: FontWeight.w600, fontSize: 11),
              );
            },
        ),
        touchCallback: (event, response) {
          // อัปเดตรายละเอียดทันทีเมื่อมีการสัมผัสแท่ง (ทุกประเภทอีเวนต์)
          if (!event.isInterestedForInteractions) return;
          final spot = response?.spot;
          if (spot == null) return;
          final idx = spot.touchedBarGroupIndex;
          if (idx < 0 || idx >= _filteredSalesData.length) return;
          final date = _filteredSalesData[idx].key;
          final invoices = _allDailyInvoices[date] ?? const <OrderHistory>[];
          final total = _filteredSalesData[idx].value;
          if (widget.onDaySelected != null) {
            widget.onDaySelected!(date, invoices, total);
          }
        },
      ),
      titlesData: FlTitlesData(
        show: true,
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (value, meta) {
              final index = value.toInt();
              if (index < 0 || index >= _filteredSalesData.length) return const SizedBox.shrink();
              final date = _filteredSalesData[index].key;
              return SideTitleWidget(
                meta: meta,
                space: 4,
                child: Text(DateFormat('d/M', 'th_TH').format(date), style: const TextStyle(fontSize: 10)),
              );
            },
            reservedSize: 30,
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: showLeftTitles,
            reservedSize: 50,
            getTitlesWidget: (value, meta) {
              if (value == 0 || value >= meta.max) return const SizedBox.shrink();
              return Text(currencyFormat.format(value), style: const TextStyle(fontSize: 10));
            },
          ),
        ),
      ),
      borderData: FlBorderData(
        show: true,
        border: const Border(
          bottom: BorderSide(color: Colors.black26, width: 1),
          left: BorderSide(color: Colors.black26, width: 1),
        ),
      ),
      barGroups: _filteredSalesData.asMap().entries.map((entry) {
        final index = entry.key;
        final data = entry.value;
        final isMax = (data.value - maxSales).abs() < 0.01;
        return BarChartGroupData(
          x: index,
          showingTooltipIndicators: const [0],
          barRods: [
            BarChartRodData(
              toY: data.value,
              color: isMax ? Colors.amber.shade700 : Theme.of(context).primaryColor,
              width: 16,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
            ),
          ],
        );
      }).toList(),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: maxSales > 0 ? maxSales / 4 : 1,
        getDrawingHorizontalLine: (value) => const FlLine(
          color: Colors.black12,
          strokeWidth: 1,
          dashArray: [3, 3],
        ),
      ),
    );
  }

  // สร้างคอลัมน์แกน Y แบบคงที่ (freeze)
  Widget _buildStaticYAxis(double maxSales) {
    final displayMax = _normalizedMaxY(maxSales);
  final currencyFormat = NumberFormat('#,##0', 'en_US');
    final tickValues = [0.0, displayMax * 0.25, displayMax * 0.50, displayMax * 0.75, displayMax];

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        return Stack(
          children: [
            for (int i = 0; i < tickValues.length; i++)
              Positioned(
                // 0 ที่ล่างสุด, displayMax บนสุด
                bottom: (height - 16) * (i / (tickValues.length - 1)),
                right: 0,
                child: Text(
                  currencyFormat.format(tickValues[i]),
                  style: const TextStyle(fontSize: 10),
                  textAlign: TextAlign.right,
                ),
              ),
          ],
        );
      },
    );
  }

  // ย้ายการแสดงรายละเอียดไปที่การ์ดด้านล่างแทน dialog
}

// โหมดการแสดงช่วงวันที่
enum RangeView { last7, thisMonth, custom }


class _TaskNoteHistoryList extends StatefulWidget {
  final Customer customer;
  const _TaskNoteHistoryList({required this.customer});

  @override
  State<_TaskNoteHistoryList> createState() => _TaskNoteHistoryListState();
}

class _TaskNoteHistoryListState extends State<_TaskNoteHistoryList> {
  FlutterTts flutterTts = FlutterTts();
  bool isPlaying = false;
  String? currentPlayingTaskId;

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  void _initTts() async {
    await flutterTts.setLanguage("th-TH"); // ภาษาไทย
    await flutterTts.setSpeechRate(0.5); // ความเร็วในการพูด (ช้าลงเพื่อฟังง่าย)
    await flutterTts.setVolume(1.0); // ระดับเสียง 100%
    await flutterTts.setPitch(1.0); // ระดับเสียงสูงต่ำ

    flutterTts.setCompletionHandler(() {
      setState(() {
        isPlaying = false;
        currentPlayingTaskId = null;
      });
    });

    flutterTts.setErrorHandler((msg) {
      setState(() {
        isPlaying = false;
        currentPlayingTaskId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาดในการอ่านข้อความ: $msg')),
      );
    });
  }

  Future<void> _speak(String text, String taskId) async {
    if (isPlaying && currentPlayingTaskId == taskId) {
      await flutterTts.stop();
      setState(() {
        isPlaying = false;
        currentPlayingTaskId = null;
      });
    } else {
      await flutterTts.stop(); // หยุดการเล่นปัจจุบัน
      setState(() {
        isPlaying = true;
        currentPlayingTaskId = taskId;
      });
      await flutterTts.speak(text);
    }
  }

  @override
  void dispose() {
    flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      color: Colors.white.withOpacity(0.9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('ประวัติการติดตามงาน',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(color: Colors.black87)),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isPlaying)
                      ElevatedButton.icon(
                        onPressed: () async {
                          await flutterTts.stop();
                          setState(() {
                            isPlaying = false;
                            currentPlayingTaskId = null;
                          });
                        },
                        icon: const Icon(Icons.stop, size: 16),
                        label: const Text('หยุด', style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade100,
                          foregroundColor: Colors.red.shade700,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: const Size(0, 30),
                        ),
                      ),
                    if (isPlaying)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.shade300),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.volume_up, size: 16, color: Colors.red.shade700),
                            const SizedBox(width: 4),
                            Text('กำลังอ่าน...', 
                              style: TextStyle(
                                fontSize: 12, 
                                color: Colors.red.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('task_notes')
                .where('customerId', isEqualTo: widget.customer.id)
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator()));
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(child: Padding(padding: EdgeInsets.all(24.0), child: Text('ไม่มีประวัติการติดตามงาน')));
              }
              final tasks = snapshot.data!.docs.map((doc) => TaskNote.fromFirestore(doc)).toList();
              return Column(
                children: tasks.map((task) {
                  final dateFormat = DateFormat('dd/MM/yy HH:mm', 'th_TH');
                  final taskId = task.id;
                  final isCurrentlyPlaying = isPlaying && currentPlayingTaskId == taskId;
                  
                  return ExpansionTile(
                    title: Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Expanded(child: Text(task.title, style: const TextStyle(fontWeight: FontWeight.bold))),
                              if ((task.title == 'ราคาใหม่') && (task.priceLevel != null && task.priceLevel!.isNotEmpty)) ...[
                                const SizedBox(width: 8),
                                priceLevelTitleText(task.priceLevel!),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            isCurrentlyPlaying ? Icons.stop : Icons.volume_up,
                            color: isCurrentlyPlaying ? Colors.red : Colors.blue,
                            size: 20,
                          ),
                          onPressed: () {
                            final textToSpeak = '${task.title}. ${task.details}';
                            _speak(textToSpeak, taskId);
                          },
                          tooltip: isCurrentlyPlaying ? 'หยุดอ่าน' : 'อ่านข้อความ',
                        ),
                      ],
                    ),
                    subtitle: Text('นัดหมาย: ${dateFormat.format(task.taskDateTime.toDate())} • ผู้ติดตามงาน: ${task.createdBy}'),
                    children: [
                       Padding(
                         padding: const EdgeInsets.all(16.0),
                         child: Column(
                           crossAxisAlignment: CrossAxisAlignment.start,
                           children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(task.details),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      isCurrentlyPlaying ? Icons.stop : Icons.play_circle_outline,
                                      color: isCurrentlyPlaying ? Colors.red : Colors.green,
                                    ),
                                    onPressed: () {
                                      _speak(task.details, taskId);
                                    },
                                    tooltip: isCurrentlyPlaying ? 'หยุดอ่านรายละเอียด' : 'อ่านรายละเอียด',
                                  ),
                                ],
                              ),
                              if (task.imageUrls.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: 100,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: task.imageUrls.length,
                                    itemBuilder: (context, index) => Padding(
                                      padding: const EdgeInsets.only(right: 8.0),
                                      child: Image.network(task.imageUrls[index]),
                                    ),
                                  ),
                                ),
                              ],
                              const Divider(height: 20),
                              Text('สร้างโดย: ${task.createdBy}'),
                              Text('วันที่สร้าง: ${dateFormat.format(task.createdAt.toDate())}'),
                           ],
                         ),
                       )
                    ],
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}


class _CustomerNotesList extends StatefulWidget {
  final Customer customer;
  final Future<CustomerApiData> customerApiDataFuture;
  final String supportName;

  const _CustomerNotesList({
    required this.customer,
    required this.customerApiDataFuture,
    required this.supportName,
  });

  @override
  State<_CustomerNotesList> createState() => _CustomerNotesListState();
}

class _CustomerNotesListState extends State<_CustomerNotesList> {
  FlutterTts flutterTts = FlutterTts();
  bool isPlaying = false;
  String? currentPlayingNoteId;

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  void _initTts() async {
    await flutterTts.setLanguage("th-TH");
    await flutterTts.setSpeechRate(0.4); // ช้าลงเพื่อฟังง่ายขึ้น
    await flutterTts.setVolume(1.0); // เสียงดัง 100%
    await flutterTts.setPitch(1.0);

    flutterTts.setCompletionHandler(() {
      setState(() {
        isPlaying = false;
        currentPlayingNoteId = null;
      });
    });

    flutterTts.setErrorHandler((msg) {
      setState(() {
        isPlaying = false;
        currentPlayingNoteId = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการอ่านข้อความ: $msg')),
        );
      }
    });
  }

  Future<void> _speakNote(String text, String noteId) async {
    if (isPlaying && currentPlayingNoteId == noteId) {
      await flutterTts.stop();
      setState(() {
        isPlaying = false;
        currentPlayingNoteId = null;
      });
    } else {
      await flutterTts.stop();
      setState(() {
        isPlaying = true;
        currentPlayingNoteId = noteId;
      });
      await flutterTts.speak(text);
    }
  }

  Future<void> _speakAllNotes(List<QueryDocumentSnapshot> notes) async {
    if (isPlaying) {
      await flutterTts.stop();
      setState(() {
        isPlaying = false;
        currentPlayingNoteId = null;
      });
      return;
    }

    if (notes.isEmpty) return;

    setState(() {
      isPlaying = true;
      currentPlayingNoteId = 'all';
    });

    // เรียงลำดับจากเก่าไปใหม่เพื่อการฟังที่เป็นลำดับ
    final sortedNotes = notes.reversed.toList();

    try {
      for (int i = 0; i < sortedNotes.length; i++) {
        // ตรวจสอบว่ายังคงเล่นอยู่หรือไม่
        if (!isPlaying || currentPlayingNoteId != 'all') break;
        
        final noteData = sortedNotes[i].data() as Map<String, dynamic>;
        final noteText = noteData['text'] as String? ?? '';
        final userName = noteData['userName'] as String? ?? 'ไม่ทราบชื่อ';
        final timestamp = noteData['timestamp'] as Timestamp?;
        
        String timeText = '';
        if (timestamp != null) {
          final date = timestamp.toDate();
          timeText = DateFormat('วันที่ dd MMMM เวลา HH:mm', 'th_TH').format(date);
        }
        
        // สร้างข้อความที่จะอ่าน
        String fullText = 'บันทึกที่ ${i + 1}';
        if (timeText.isNotEmpty) fullText += ' $timeText';
        fullText += ' โดย $userName. เนื้อหา: $noteText';
        
        // อ่านข้อความ
        await flutterTts.speak(fullText);
        
        // รอสักครู่ระหว่างข้อความ
        await Future.delayed(const Duration(milliseconds: 800));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการอ่าน: $e')),
        );
      }
    }

    // อ่านเสร็จแล้ว
    if (mounted) {
      setState(() {
        isPlaying = false;
        currentPlayingNoteId = null;
      });
    }
  }

  @override
  void dispose() {
    flutterTts.stop();
    super.dispose();
  }

  Future<void> _editCustomerNote(BuildContext context, DocumentSnapshot note) async {
    final noteData = note.data() as Map<String, dynamic>;
    final initialText = noteData['text'] as String? ?? '';
    final initialImages = (noteData['imageUrls'] as List?)?.cast<String>().toList() ?? <String>[];

    final textController = TextEditingController(text: initialText);
    final picker = ImagePicker();

    // รายการรูปเดิมที่ยังคงไว้ + รูปใหม่ที่เลือกเข้ามา
    List<String> remainUrls = List.of(initialImages);
    List<XFile> newImages = [];

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Future<void> pickFromGallery() async {
              final files = await picker.pickMultiImage(imageQuality: 85);
              if (files.isNotEmpty) {
                setModalState(() => newImages.addAll(files));
              }
            }

            Future<void> captureFromCamera() async {
              final file = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
              if (file != null) {
                setModalState(() => newImages.add(file));
              }
            }

            void removeExistingUrl(String url) {
              setModalState(() => remainUrls.remove(url));
            }

            void removeNewImageAt(int index) {
              setModalState(() => newImages.removeAt(index));
            }

            return AlertDialog(
              title: const Text('แก้ไขบันทึก'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: textController,
                      maxLines: null,
                      decoration: const InputDecoration(
                        labelText: 'ข้อความ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: pickFromGallery,
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('เพิ่มรูป'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: captureFromCamera,
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('ถ่ายรูป'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (remainUrls.isNotEmpty) ...[
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('รูปเดิม', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: remainUrls.map((url) {
                          return Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.network(url, width: 80, height: 80, fit: BoxFit.cover),
                              ),
                              Positioned(
                                top: -6,
                                right: -6,
                                child: IconButton(
                                  icon: const Icon(Icons.cancel, color: Colors.red, size: 20),
                                  onPressed: () => removeExistingUrl(url),
                                  tooltip: 'ลบรูปนี้',
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (newImages.isNotEmpty) ...[
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('รูปใหม่ที่เพิ่ม', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(newImages.length, (i) {
                          final x = newImages[i];
                          return Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.file(File(x.path), width: 80, height: 80, fit: BoxFit.cover),
                              ),
                              Positioned(
                                top: -6,
                                right: -6,
                                child: IconButton(
                                  icon: const Icon(Icons.cancel, color: Colors.red, size: 20),
                                  onPressed: () => removeNewImageAt(i),
                                  tooltip: 'ลบรูปนี้',
                                ),
                              ),
                            ],
                          );
                        }),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('ยกเลิก'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      // ลบรูปเดิมที่ผู้ใช้ตัดออก
                      final removedUrls = initialImages.where((u) => !remainUrls.contains(u)).toList();
                      for (final url in removedUrls) {
                        try {
                          final ref = FirebaseStorage.instance.refFromURL(url);
                          await ref.delete();
                        } catch (_) {}
                      }

                      // อัปโหลดรูปใหม่
                      final List<String> newUrls = [];
                      for (int i = 0; i < newImages.length; i++) {
                        final x = newImages[i];
                        final storageRef = FirebaseStorage.instance
                            .ref()
                            .child('customer_notes/${widget.customer.id}/${note.id}/${DateTime.now().millisecondsSinceEpoch}_$i.jpg');
                        await storageRef.putFile(File(x.path));
                        final url = await storageRef.getDownloadURL();
                        newUrls.add(url);
                      }

                      await FirebaseFirestore.instance
                          .collection('customers')
                          .doc(widget.customer.id)
                          .collection('notes')
                          .doc(note.id)
                          .update({
                        'text': textController.text.trim(),
                        'imageUrls': [...remainUrls, ...newUrls],
                        'editedAt': Timestamp.now(),
                        'editedBy': FirebaseAuth.instance.currentUser?.displayName ?? FirebaseAuth.instance.currentUser?.email,
                      });

                      if (mounted) {
                        Navigator.of(ctx).pop();
                        // แสดง SnackBar หลังเฟรมถัดไป เพื่อลดปัญหา scope/build
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            const SnackBar(content: Text('บันทึกการแก้ไขสำเร็จ'), backgroundColor: Colors.green),
                          );
                        });
                      }
                    } catch (e) {
                      if (mounted) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(content: Text('เกิดข้อผิดพลาดในการแก้ไข: $e'), backgroundColor: Colors.red),
                          );
                        });
                      }
                    }
                  },
                  child: const Text('บันทึก'),
                ),
              ],
            );
          },
        );
      },
    );

  // อย่าจัดการ dispose ที่นี่เพื่อหลีกเลี่ยงปัญหา controller ถูกใช้หลัง dispose ใน lifecycle ของ dialog
  }

  Future<void> _shareNote(BuildContext context, DocumentSnapshot note) async {
    try {
      final salesData = await widget.customerApiDataFuture;
      final apiData = salesData.apiCustomer;
      final rebateData = salesData.rebateData;
      final currencyFormat = NumberFormat("#,##0", "en_US");
      final noteData = note.data() as Map<String, dynamic>;
      final noteText = noteData['text'] as String? ?? '';
      final userName = noteData['userName'] as String? ?? 'N/A';
      final timestamp = noteData['timestamp'] as Timestamp?;
      final formattedDate = timestamp != null
          ? DateFormat('EEEE ที่ dd/MM/yy เวลา HH:mm', 'th_TH').format(timestamp.toDate())
          : 'N/A';
      final nowFormatted =
          DateFormat('EEEE ที่ dd/MM/yy เวลา HH:mm', 'th_TH').format(DateTime.now());

      String province = '';
      if (widget.customer.address2.isNotEmpty) {
        final parts = widget.customer.address2.split(' ');
        if (parts.isNotEmpty) province = parts.last;
      }

      final monthlyTarget = rebateData?.monthlyTarget ?? 0.0;
      final shortfall = monthlyTarget - salesData.currentMonthSales;
      final targetSummary = monthlyTarget > 0 
        ? (shortfall > 0 ? 'ขาดอีก ${currencyFormat.format(shortfall)} บาท' : 'ถึงเป้าแล้ว')
        : 'ไม่มีเป้าหมาย';

      final shareText = '''
$nowFormatted
--------
บันทึก : ${widget.customer.name}
รหัสลูกค้า : ${widget.customer.customerId} | เส้นทาง : $province
ผู้ดูแล : ${widget.customer.salesperson} | ซัพพอร์ท : ${widget.supportName}
เบอร์โทรศัพท์: ${widget.customer.contacts.map((c) => c['phone']).join(', ')}
ยอดค้าง : ${apiData.memBalance ?? '0.00'} | ชำระล่าสุด : ${DateHelper.formatDateToThai(apiData.memLastpayments ?? '')}
--------
เป้าหมาย : ${currencyFormat.format(monthlyTarget)}
ยอดเดือนก่อน: ${currencyFormat.format(salesData.previousMonthSales)} บาท
ยอดปัจจุบัน: ${currencyFormat.format(salesData.currentMonthSales)} บาท
สรุปเป้าในเดือน : $targetSummary
--------
$noteText
--------
บันทึก : $formattedDate 
โพสต์โดย : $userName
''';
      await Share.share(shareText);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาดในการแชร์: $e')),
      );
    }
  }

  Future<void> _shareImageUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final name = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'image.jpg';
        final lower = name.toLowerCase();
        final mime = lower.endsWith('.png') ? 'image/png' : 'image/jpeg';
        await Share.shareXFiles([
          XFile.fromData(
            res.bodyBytes,
            name: name,
            mimeType: mime,
          )
        ]);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('ดาวน์โหลดรูปไม่สำเร็จ (${res.statusCode})')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('แชร์รูปภาพไม่สำเร็จ: $e')),
        );
      }
    }
  }

  void _openImageViewer(List<String> urls, int initialIndex) {
    showDialog(
      context: context,
      builder: (ctx) {
        final controller = PageController(initialPage: initialIndex);
        return Dialog(
          insetPadding: const EdgeInsets.all(8),
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              PageView.builder(
                controller: controller,
                itemCount: urls.length,
                itemBuilder: (context, index) {
                  final u = urls[index];
                  return InteractiveViewer(
                    panEnabled: true,
                    minScale: 0.5,
                    maxScale: 4,
                    child: Center(
                      child: Image.network(u, fit: BoxFit.contain),
                    ),
                  );
                },
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      color: Colors.white.withOpacity(0.9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('customers')
                .doc(widget.customer.id)
                .collection('notes')
                .orderBy('timestamp', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              final notes = snapshot.hasData ? snapshot.data!.docs : <QueryDocumentSnapshot>[];
              
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('บันทึกข้อมูลลูกค้า',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(color: Colors.black87)),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!isPlaying && notes.isNotEmpty)
                          ElevatedButton.icon(
                            onPressed: () => _speakAllNotes(notes),
                            icon: const Icon(Icons.play_circle_outline, size: 16),
                            label: const Text('อ่านทั้งหมด', style: TextStyle(fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade100,
                              foregroundColor: Colors.green.shade700,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: const Size(0, 30),
                            ),
                          ),
                        if (isPlaying)
                          ElevatedButton.icon(
                            onPressed: () async {
                              await flutterTts.stop();
                              setState(() {
                                isPlaying = false;
                                currentPlayingNoteId = null;
                              });
                            },
                            icon: const Icon(Icons.stop, size: 16),
                            label: const Text('หยุด', style: TextStyle(fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade100,
                              foregroundColor: Colors.red.shade700,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: const Size(0, 30),
                            ),
                          ),
                        if (isPlaying)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.green.shade300),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.volume_up, size: 16, color: Colors.green.shade700),
                                const SizedBox(width: 4),
                                Text(
                                  currentPlayingNoteId == 'all' ? 'กำลังอ่านทั้งหมด...' : 'กำลังอ่าน...',
                                  style: TextStyle(
                                    fontSize: 12, 
                                    color: Colors.green.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          const Divider(),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('customers')
                .doc(widget.customer.id)
                .collection('notes')
                .orderBy('timestamp', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ));
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(
                    child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Text('ไม่มีบันทึก'),
                ));
              }
              final notes = snapshot.data!.docs;
              return Column(
                children: notes.map((note) {
                  final noteData = note.data() as Map<String, dynamic>;
                  final timestamp = noteData['timestamp'] as Timestamp?;
                  final date = timestamp?.toDate();
                  final formattedDate = date != null
                      ? DateFormat('dd/MM/yy HH:mm').format(date)
                      : '...';
                  final noteText = noteData['text'] as String? ?? '';
                  final imageUrls = (noteData['imageUrls'] as List?)?.cast<String>() ?? const <String>[];
                  final noteId = note.id;
                  final isCurrentlyPlaying = isPlaying && currentPlayingNoteId == noteId;

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: Text(noteText)),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      isCurrentlyPlaying ? Icons.stop : Icons.volume_up,
                                      color: isCurrentlyPlaying ? Colors.red : Colors.blue,
                                      size: 20,
                                    ),
                                    onPressed: () => _speakNote(noteText, noteId),
                                    tooltip: isCurrentlyPlaying ? 'หยุดอ่าน' : 'อ่านข้อความ',
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.orange),
                                    onPressed: () => _editCustomerNote(context, note),
                                    tooltip: 'แก้ไขบันทึกนี้',
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.share_outlined, color: Colors.blueGrey),
                                    onPressed: () => _shareNote(context, note),
                                    tooltip: 'แชร์บันทึกนี้',
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text('โดย: ${noteData['userName']} - $formattedDate', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                          if (imageUrls.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: List.generate(imageUrls.length, (i) {
                                final url = imageUrls[i];
                                return GestureDetector(
                                  onTap: () => _openImageViewer(imageUrls, i),
                                  child: Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: Image.network(url, width: 80, height: 80, fit: BoxFit.cover),
                                      ),
                                      Positioned(
                                        right: -6,
                                        top: -6,
                                        child: IconButton(
                                          icon: const Icon(Icons.share, size: 18, color: Colors.white),
                                          style: IconButton.styleFrom(
                                            backgroundColor: Colors.black45,
                                            minimumSize: const Size(28, 28),
                                            padding: EdgeInsets.zero,
                                          ),
                                          tooltip: 'แชร์รูปนี้',
                                          onPressed: () => _shareImageUrl(url),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CustomerNoteInput extends StatefulWidget {
  final Customer customer;
  const _CustomerNoteInput({required this.customer});

  @override
  State<_CustomerNoteInput> createState() => _CustomerNoteInputState();
}

// ยกเลิกโหมด AI ทั้งหมด: ใช้การทำความสะอาดข้อความแบบโลคัลเท่านั้น

class _CustomerNoteInputState extends State<_CustomerNoteInput> {
  final _noteController = TextEditingController();
  bool _isSending = false;
  // ปิดปุ่มปรับสำนวนแบบกดเอง: ใช้เฉพาะการปรับอัตโนมัติขณะส่ง
  // ปิดโหมดปรับสำนวนอัตโนมัติและโทนภาษา ตามคำขอ: เหลือแค่ปุ่ม "ปรับสำนวน" แบบกดเอง
  // แนบรูปภาพ
  final ImagePicker _picker = ImagePicker();
  final List<XFile> _images = [];

  // ปิดการเรียกใช้งานภายนอกชั่วคราว เพื่อป้องกันข้อความ HTML แทรก

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  // ทำความสะอาดข้อความล้วนแบบโลคัล (ไม่เรียกเซิร์ฟเวอร์/ไม่ใช้ AI)
  String _sanitizePlainTextLocal(String input) {
    var s = input.trim();
    if (s.isEmpty) return s;
    // ลบโค้ดบล็อกและโค้ดอินไลน์
    s = s.replaceAll(RegExp(r'```[\s\S]*?```', multiLine: true), ' ');
    s = s.replaceAll(RegExp(r'`([^`]*)`'), r'$1');
    // ตัดแท็ก HTML ออก
    s = s.replaceAll(RegExp(r'<[^>]+>'), ' ');
    // ถอดรหัส entity ที่พบบ่อย
    s = s
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
    // ปรับเครื่องหมาย quote ให้เป็นมาตรฐาน
    s = s.replaceAll(RegExp(r'[“”]'), '"').replaceAll(RegExp(r'[‘’]'), "'");
    // ตัดอักขระแปลกๆ ให้เหลือไทย/อังกฤษ/ตัวเลข และวรรคตอนพื้นฐาน + ฿
  s = s.replaceAll(
    RegExp('[^\\w\\s\\.,!?;:\\(\\)\\[\\]\\{\\}\\\'\"\\-\\/\\+@#%&\\*=฿\\u0E00-\\u0E7F]'),
    ' ');
    // รวมช่องว่างซ้ำ และตัดหัวท้าย
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.length > 2000) s = s.substring(0, 2000).trim();
    return s;
  }

  // เดิมมีตัวช่วยเกลาข้อความแบบ heuristic แต่ยกเลิกใช้งานแล้ว

  // เดิมมีฟังก์ชันปรับสำนวนทางการ แต่เลิกใช้แล้วเพื่อให้เป็นโลคัลล้วน

  // ตัดการเรียกใช้งานเซิร์ฟเวอร์ทั้งหมดแล้ว

  Future<void> _addNote() async {
    var text = _noteController.text.trim();
    final user = FirebaseAuth.instance.currentUser;
    if ((text.isEmpty && _images.isEmpty) || user == null) return;

    setState(() => _isSending = true);

    try {
      // ทำความสะอาดข้อความแบบโลคัลเท่านั้น
      if (text.isNotEmpty) {
        text = _sanitizePlainTextLocal(text);
      }
      final docRef = FirebaseFirestore.instance
          .collection('customers')
          .doc(widget.customer.id)
          .collection('notes')
          .doc();

      final List<String> urls = [];
      for (int i = 0; i < _images.length; i++) {
        final x = _images[i];
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('customer_notes/${widget.customer.id}/${docRef.id}/${DateTime.now().millisecondsSinceEpoch}_$i.jpg');
        await storageRef.putFile(File(x.path));
        final url = await storageRef.getDownloadURL();
        urls.add(url);
      }

      await docRef.set({
        'text': text,
        'imageUrls': urls,
        'timestamp': FieldValue.serverTimestamp(),
        'userId': user.uid,
        'userName': user.displayName ?? user.email?.split('@').first ?? 'Unknown',
      });
      _noteController.clear();
      setState(() => _images.clear());
      FocusScope.of(context).unfocus();
      if (mounted && (text.isNotEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกแล้ว (ทำความสะอาดข้อความ)')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการบันทึก: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _pickFromGallery() async {
    final files = await _picker.pickMultiImage(imageQuality: 85);
    if (!mounted) return;
    if (files.isNotEmpty) {
      setState(() => _images.addAll(files));
    }
  }

  Future<void> _captureFromCamera() async {
    final file = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (!mounted) return;
    if (file != null) {
      setState(() => _images.add(file));
    }
  }

  void _removeImageAt(int index) {
    setState(() => _images.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ตัด UI โหมดแต่งคำ: ไม่ใช้ AI/เซิร์ฟเวอร์อีกต่อไป
            if (_images.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(_images.length, (i) {
                    final img = _images[i];
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.file(
                            File(img.path),
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: -6,
                          right: -6,
                          child: IconButton(
                            icon: const Icon(Icons.cancel, color: Colors.red, size: 18),
                            onPressed: _isSending ? null : () => _removeImageAt(i),
                            tooltip: 'ลบรูปนี้',
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            if (_images.isNotEmpty) const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _noteController,
                    decoration: const InputDecoration(
                      hintText: 'พิมพ์ข้อความ...',
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _addNote(),
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 1,
                    maxLines: 4,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.photo_library_outlined),
                  tooltip: 'เลือกรูปจากแกลลอรี่',
                  onPressed: _isSending ? null : _pickFromGallery,
                  color: Theme.of(context).primaryColor,
                ),
                IconButton(
                  icon: const Icon(Icons.photo_camera_outlined),
                  tooltip: 'ถ่ายรูป',
                  onPressed: _isSending ? null : _captureFromCamera,
                  color: Theme.of(context).primaryColor,
                ),
                IconButton(
                  icon: _isSending
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                  onPressed: _isSending ? null : _addNote,
                  color: Theme.of(context).primaryColor,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SalesOrdersTab extends StatelessWidget {
  final String customerId;
  const _SalesOrdersTab({required this.customerId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('sales_orders')
          .where('รหัสลูกหนี้', isEqualTo: customerId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.white));
        }
        if (snapshot.hasError) {
          return Center(
              child: Text('เกิดข้อผิดพลาด: ${snapshot.error}',
                  style: const TextStyle(color: Colors.white)));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Card(
              color: Colors.white.withOpacity(0.85),
              child: const Padding(
                padding: EdgeInsets.all(16.0),
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('ไม่มีรายการสั่งจอง'),
                ),
              ),
            ),
          );
        }

        final orders = snapshot.data!.docs
            .map((doc) => SalesOrder.fromFirestore(doc))
            .toList();
        orders.sort((a, b) => b.orderDate.compareTo(a.orderDate));

        return ListView(
          padding: const EdgeInsets.all(8.0),
          children: orders.map((order) {
            String formattedDate = DateHelper.formatExcelDate(order.orderDate);
            return Card(
              color: Colors.white.withOpacity(0.85),
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                title: Text(order.productDescription,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                    'จำนวน: ${order.quantity} ${order.unit} • ราคา: ${NumberFormat("#,##0.00").format(order.totalAmount)} บาท'),
                trailing: Text(formattedDate),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _PurchaseHistoryTab extends StatelessWidget {
  final Future<CustomerApiData> customerApiDataFuture;
  const _PurchaseHistoryTab({required this.customerApiDataFuture});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CustomerApiData>(
      future: customerApiDataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.white));
        }
        if (snapshot.hasError) {
          return Center(
              child: Text('เกิดข้อผิดพลาด: ${snapshot.error}',
                  style: const TextStyle(color: Colors.white)));
        }
        if (!snapshot.hasData) {
          return const Center(
              child:
                  Text('ไม่พบข้อมูล', style: TextStyle(color: Colors.white)));
        }

        final apiCustomer = snapshot.data!.apiCustomer;
        final now = DateTime.now();
        final firstDayOfMonth = DateTime(now.year, now.month, 1);

        final recentOrders = apiCustomer.order.where((order) {
          final orderDate = DateTime.tryParse(order.date ?? '');
          return orderDate != null && !orderDate.isBefore(firstDayOfMonth);
        }).toList();

        recentOrders.sort((a, b) {
          final dateA = DateTime.tryParse(a.date ?? '');
          final dateB = DateTime.tryParse(b.date ?? '');
          if (dateA == null || dateB == null) return 0;
          return dateB.compareTo(dateA);
        });

        if (recentOrders.isEmpty) {
          return Center(
            child: Card(
              color: Colors.white.withOpacity(0.85),
              child: const Padding(
                padding: EdgeInsets.all(16.0),
                child: ListTile(
                  leading: Icon(Icons.history, color: Colors.grey),
                  title: Text('ไม่พบประวัติการซื้อในเดือนนี้'),
                ),
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(8.0),
          itemCount: recentOrders.length,
          itemBuilder: (context, index) {
            final order = recentOrders[index];
            final priceValue =
                double.tryParse(order.price?.replaceAll(',', '') ?? '0') ?? 0.0;
            final isCreditNote = priceValue < 0;
            final date = DateTime.tryParse(order.date ?? '');
            final formattedDate =
                date != null ? DateFormat('dd/MM/yy').format(date) : '-';

            return Card(
              color: Colors.white.withOpacity(0.9),
              margin: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Container(
                    width: 5,
                    height: 60,
                    color: isCreditNote ? Colors.red : Colors.green,
                  ),
                  Expanded(
                    child: ListTile(
                      title: Text(
                        'เลขที่: ${order.bill ?? '-'}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('วันที่: $formattedDate'),
                      trailing: Text(
                        NumberFormat("#,##0.00", "en_US").format(priceValue),
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isCreditNote ? Colors.red : Colors.black87,
                            fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;

  const _InfoChip({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: TextStyle(color: Colors.grey.shade700)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _BranchLinksSection extends StatefulWidget {
  final Customer customer;
  const _BranchLinksSection({required this.customer});

  @override
  State<_BranchLinksSection> createState() => _BranchLinksSectionState();
}

class _BranchLinksSectionState extends State<_BranchLinksSection> {
  late final DocumentReference metaRef;
  late final CollectionReference codesRef;
  final Map<String, String> _nameCache = {};
  bool _isBackfilling = false;

  @override
  void initState() {
    super.initState();
    metaRef = FirebaseFirestore.instance
        .collection('customers')
        .doc(widget.customer.id)
        .collection('branch_links')
        .doc('_meta');
    codesRef = FirebaseFirestore.instance
        .collection('customers')
        .doc(widget.customer.id)
        .collection('branch_links');
  }

  Future<String> _resolveCustomerName(String code) async {
    if (_nameCache.containsKey(code)) return _nameCache[code]!;
    final snap = await FirebaseFirestore.instance
        .collection('customers')
        .where('รหัสลูกค้า', isEqualTo: code)
        .limit(1)
        .get();
    String name = '';
    if (snap.docs.isNotEmpty) {
      final data = snap.docs.first.data();
      name = (data['ชื่อลูกค้า']?.toString() ?? '').trim();
    }
    _nameCache[code] = name;
    return name;
  }

  // Removed: _resolveCustomerByDocId is not needed after simplifying to outgoing-only list.

  Future<void> _backfillMissingNames(List<QueryDocumentSnapshot> docs) async {
    if (_isBackfilling) return;
    _isBackfilling = true;
    try {
      for (final d in docs) {
        final data = d.data() as Map<String, dynamic>;
        final code = (data['code']?.toString() ?? '').trim();
        final name = (data['name']?.toString() ?? '').trim();
        if (code.isEmpty) continue;
        if (name.isEmpty) {
          final resolved = await _resolveCustomerName(code);
          if (resolved.isNotEmpty) {
            await d.reference.update({'name': resolved});
          }
        }
      }
    } catch (_) {
      // silent
    } finally {
      _isBackfilling = false;
    }
  }

  Future<void> _makeSymmetricWith(String otherCode) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final otherSnap = await firestore
          .collection('customers')
          .where('รหัสลูกค้า', isEqualTo: otherCode)
          .limit(1)
          .get();
      if (otherSnap.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('ไม่พบรหัสลูกค้า $otherCode')),
          );
        }
        return;
      }

      final otherDoc = otherSnap.docs.first;
      final otherCodesRef = firestore
          .collection('customers')
          .doc(otherDoc.id)
          .collection('branch_links');

      final currentCode = widget.customer.customerId.trim();
      final currentName = widget.customer.name.trim();
      final otherName = await _resolveCustomerName(otherCode);

      final ourExists = await codesRef.where('code', isEqualTo: otherCode).limit(1).get();
      final theirExists = await otherCodesRef.where('code', isEqualTo: currentCode).limit(1).get();

      final batch = firestore.batch();
      if (ourExists.docs.isEmpty) {
        batch.set(codesRef.doc(), {
          'code': otherCode,
          'name': otherName,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      if (theirExists.docs.isEmpty) {
        batch.set(otherCodesRef.doc(), {
          'code': currentCode,
          'name': currentName,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      if (ourExists.docs.isEmpty || theirExists.docs.isEmpty) {
        await batch.commit();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เชื่อมโยงสองทางสำเร็จ')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการเชื่อมโยง: $e')),
        );
      }
    }
  }

  Future<void> _removeSymmetricWith(String otherCode) async {
    try {
      final firestore = FirebaseFirestore.instance;
      // Find other customer by code
      final otherSnap = await firestore
          .collection('customers')
          .where('รหัสลูกค้า', isEqualTo: otherCode)
          .limit(1)
          .get();
      if (otherSnap.docs.isEmpty) {
        // If we can't resolve, just remove local entries that match code
        final local = await codesRef.where('code', isEqualTo: otherCode).get();
        for (final d in local.docs) {
          await d.reference.delete();
        }
        return;
      }

      final otherDoc = otherSnap.docs.first;
      final otherCodesRef = firestore
          .collection('customers')
          .doc(otherDoc.id)
          .collection('branch_links');

      final batch = firestore.batch();
      final local = await codesRef.where('code', isEqualTo: otherCode).get();
      for (final d in local.docs) {
        batch.delete(d.reference);
      }

      final currentCode = widget.customer.customerId.trim();
      final theirs = await otherCodesRef.where('code', isEqualTo: currentCode).get();
      for (final d in theirs.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ยกเลิกการเชื่อมโยงแล้ว')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ลบการเชื่อมโยงล้มเหลว: $e')));
      }
    }
  }

  Future<void> _addCodeDialog() async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('เพิ่มรหัสร้านสาขา'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'เช่น 01030'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
          ElevatedButton(
            onPressed: () async {
              final code = ctrl.text.trim();
              if (code.isEmpty) return;
              if (code == widget.customer.customerId.trim()) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ไม่สามารถเพิ่มรหัสของตัวเองได้')));
                }
                return;
              }
              await _makeSymmetricWith(code);
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('บันทึก'),
          )
        ],
      ),
    );
  }

  Future<void> _navigateToCode(String code) async {
    // Find customer by customerId field
    final snap = await FirebaseFirestore.instance
        .collection('customers')
        .where('รหัสลูกค้า', isEqualTo: code)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ไม่พบรหัสลูกค้า $code')));
      }
      return;
    }
    final cust = Customer.fromFirestore(snap.docs.first);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CustomerDetailScreen(customer: cust)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: metaRef.snapshots(),
      builder: (context, metaSnap) {
        bool enabled = false;
        if (metaSnap.hasData && metaSnap.data!.exists) {
          final m = metaSnap.data!.data() as Map<String, dynamic>?;
          enabled = (m?['enabled'] as bool?) ?? false;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle_outline, color: enabled ? Colors.green : Colors.grey, size: 18),
                const SizedBox(width: 6),
                const Text('ร้านสาขา', style: TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                Switch(
                  value: enabled,
                  onChanged: (v) => metaRef.set({'enabled': v}, SetOptions(merge: true)),
                  activeColor: Colors.green,
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  tooltip: 'เพิ่มรหัสลูกค้าสาขา',
                  onPressed: enabled ? _addCodeDialog : null,
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'กลุ่มร้านสาขาเดียวกัน (แสดงทั้งที่อ้างถึงและถูกอ้างถึง)',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            // Simple outgoing list (symmetric linking guarantees both sides see each other)
            StreamBuilder<QuerySnapshot>(
              stream: codesRef.snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return const SizedBox.shrink();
                }
                final docs = snap.data?.docs.where((d) => d.id != '_meta').toList() ?? [];
                if (docs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Text('ยังไม่มีการเชื่อมโยงสาขา', style: TextStyle(color: Colors.grey)),
                  );
                }
                // Backfill any missing names in background
                final needs = docs.where((d) {
                  final m = d.data() as Map<String, dynamic>;
                  return ((m['name']?.toString() ?? '').trim()).isEmpty;
                }).toList();
                if (needs.isNotEmpty) {
                  _backfillMissingNames(needs);
                }
                final items = docs.map((d) {
                  final m = d.data() as Map<String, dynamic>;
                  final code = (m['code']?.toString() ?? '').trim();
                  final name = (m['name']?.toString() ?? '').trim();
                  return MapEntry(code, name);
                }).where((e) => e.key.isNotEmpty && e.key != widget.customer.customerId).toList()
                  ..sort((a, b) => a.key.compareTo(b.key));
                if (items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Text('ยังไม่มีการเชื่อมโยงสาขา', style: TextStyle(color: Colors.grey)),
                  );
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: items.map((e) {
                    final code = e.key;
                    final label = e.value.isNotEmpty ? '${e.key} - ${e.value}' : e.key;
                    return InputChip(
                      label: Text(label),
                      onPressed: () => _navigateToCode(code),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: enabled ? () => _removeSymmetricWith(code) : null,
                    );
                  }).toList(),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

// แท็บใหม่: บันทึกลูกค้า (รวมประวัติการติดตามงาน + บันทึกข้อมูลลูกค้า)
class _CustomerNotesTab extends StatelessWidget {
  final Customer customer;
  final Future<CustomerApiData> customerApiDataFuture;
  const _CustomerNotesTab({required this.customer, required this.customerApiDataFuture});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                _TaskNoteHistoryList(customer: customer),
                const SizedBox(height: 16),
                _VisitHistoryList(customer: customer),
                const SizedBox(height: 16),
                _CustomerNotesList(
                  customer: customer,
                  customerApiDataFuture: customerApiDataFuture,
                  supportName: '',
                ),
              ],
            ),
          ),
        ),
        _CustomerNoteInput(customer: customer),
      ],
    );
  }
}

// การ์ดใหม่: ประวัติการเข้าเยี่ยม (Gradient/Glass + แชร์สรุปงาน)
class _VisitHistoryList extends StatefulWidget {
  final Customer customer;
  const _VisitHistoryList({required this.customer});

  @override
  State<_VisitHistoryList> createState() => _VisitHistoryListState();
}

class _VisitHistoryListState extends State<_VisitHistoryList> {
  final FlutterTts _tts = FlutterTts();
  String? _playingId;

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('th-TH');
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _tts.setCompletionHandler(() => setState(() => _playingId = null));
    _tts.setErrorHandler((msg) => setState(() => _playingId = null));
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Widget _glass(Widget child) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0x880052D4), Color(0x884364F7), Color(0x886FB1FC)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.25)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 12, offset: const Offset(0, 6)),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Future<void> _speak(String id, String text) async {
    if (_playingId == id) {
      await _tts.stop();
      setState(() => _playingId = null);
    } else {
      await _tts.stop();
      setState(() => _playingId = id);
      await _tts.speak(text);
    }
  }

  void _openImage(String url) {
    showDialog(
      context: context,
      builder: (_) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: InteractiveViewer(child: Image.network(url)),
        ),
      ),
    );
  }

  Future<void> _sharePlan(VisitPlan p) async {
    final dt = DateFormat('dd/MM/yyyy HH:mm', 'th_TH').format((p.doneAt ?? p.plannedAt).toDate());
    final images = p.photoUrls.isNotEmpty ? '\nรูปภาพ: ${p.photoUrls.join(', ')}' : '';
    final text = [
      'สรุปงานเข้าเยี่ยมลูกค้า',
      'ลูกค้า: ${widget.customer.name} (${widget.customer.customerId})',
      'เวลา: $dt',
      'ผู้ทำภารกิจ: ${p.completedByName ?? '-'}',
      'สรุป: ${p.resultNotes?.trim().isNotEmpty == true ? p.resultNotes : '-'}',
      images,
    ].where((e) => e.isNotEmpty).join('\n');
    await Share.share(text, subject: 'สรุปงานเข้าเยี่ยม');
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.customer.customerId;
    final dateFmt = DateFormat('dd/MM/yy HH:mm', 'th_TH');
    return _glass(
      Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.fact_check, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('ประวัติการเข้าเยี่ยม',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('visit_plans')
                  .where('customerId', isEqualTo: code)
                  .orderBy('doneAt', descending: true)
                  .limit(50)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator(color: Colors.white)));
                }
                final all = snap.data?.docs.map((d) => VisitPlan.fromFirestore(d)).toList() ?? [];
                final submitted = all.where((p) => p.doneAt != null || (p.resultNotes?.isNotEmpty ?? false) || p.photoUrls.isNotEmpty || (p.signatureUrl?.isNotEmpty ?? false)).toList();
                if (submitted.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Text('ยังไม่มีประวัติการเข้าเยี่ยม', style: TextStyle(color: Colors.white70)),
                  );
                }
                return Column(
                  children: submitted.map((p) {
                    final id = p.id;
                    final playing = _playingId == id;
                    final timeText = dateFmt.format((p.doneAt ?? p.plannedAt).toDate());
                    final content = (p.resultNotes ?? '').isEmpty ? 'ไม่มีสรุปงาน' : p.resultNotes!;
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.25)),
                      ),
                      child: ExpansionTile(
                        collapsedIconColor: Colors.white,
                        iconColor: Colors.white,
                        leading: const Icon(Icons.assignment_turned_in, color: Colors.white),
                        title: Text('${widget.customer.name} (${widget.customer.customerId})', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        subtitle: Text('เวลาส่งสรุป: $timeText • ผู้ทำ: ${p.completedByName ?? '-'}', style: const TextStyle(color: Colors.white70)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(playing ? Icons.stop : Icons.volume_up, color: playing ? Colors.redAccent : Colors.white),
                              onPressed: () => _speak(id, 'สรุปงาน: $content โดย ${p.completedByName ?? 'ไม่ทราบชื่อ'} ที่เวลา $timeText'),
                              tooltip: playing ? 'หยุดอ่าน' : 'อ่านข้อความ',
                            ),
                            IconButton(
                              icon: const Icon(Icons.share, color: Colors.white),
                              onPressed: () => _sharePlan(p),
                              tooltip: 'แชร์สรุปงาน',
                            ),
                          ],
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('สรุปงาน: $content', style: const TextStyle(color: Colors.white)),
                                if (p.photoUrls.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    height: 110,
                                    child: ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: p.photoUrls.length,
                                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                                      itemBuilder: (_, i) => GestureDetector(
                                        onTap: () => _openImage(p.photoUrls[i]),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Image.network(p.photoUrls[i], height: 110, fit: BoxFit.cover),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

Widget _buildApiDetailRow(
    BuildContext context, IconData icon, String label, String? value,
    {Color? valueColor}) {
  final displayValue = (value != null && value.isNotEmpty) ? value : '-';
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4.0),
    child: Row(
  crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: Colors.grey.shade600, size: 20),
        const SizedBox(width: 12),
        Text(label,
            style: const TextStyle(fontSize: 14, color: Colors.black87)),
        const Spacer(),
        Text(
          displayValue,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: valueColor ?? Colors.black87,
          ),
        ),
      ],
    ),
  );
}

class _SalesSupportTab extends StatefulWidget {
  final Customer customer;
  final Future<CustomerApiData> customerApiDataFuture;

  const _SalesSupportTab({
    required this.customer,
    required this.customerApiDataFuture,
  });

  @override
  State<_SalesSupportTab> createState() => _SalesSupportTabState();
}

class _SalesSupportTabState extends State<_SalesSupportTab> {
  Map<String, double> _monthlySales = {};
  bool _isLoading = true;
  final NumberFormat _currencyFormat = NumberFormat("#,##0", "en_US");
  
  double _commissionRate = 100.0;
  double _commissionTarget = 100000.0;
  bool _isAdmin = false;
  final _rateController = TextEditingController();
  final _targetController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();
    _loadAllData();
  }

  @override
  void dispose() {
    _rateController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  void _checkAdminStatus() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.email == '0539@salewang.com') {
      setState(() {
        _isAdmin = true;
      });
    }
  }

  Future<void> _loadAllData() async {
    await _archiveAndFetchSalesHistory();
    await _fetchCommissionSettings();
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _archiveAndFetchSalesHistory() async {
    final firestore = FirebaseFirestore.instance;
    final customerSalesRef = firestore.collection('customers').doc(widget.customer.id).collection('monthly_sales');
    
    try {
      final apiData = await widget.customerApiDataFuture;
      final now = DateTime.now();
      final prevMonth = DateTime(now.year, now.month - 1);
      final prevMonthId = DateFormat('yyyy-MM').format(prevMonth);
      
      final prevMonthDoc = await customerSalesRef.doc(prevMonthId).get();
      if (!prevMonthDoc.exists && apiData.previousMonthSales > 0) {
        await customerSalesRef.doc(prevMonthId).set({
          'salesAmount': apiData.previousMonthSales,
          'timestamp': Timestamp.fromDate(prevMonth),
        });
      }

      final salesSnapshot = await customerSalesRef
          .orderBy('timestamp', descending: true)
          .limit(6)
          .get();
      
      final historicalSales = <String, double>{};
      for (var doc in salesSnapshot.docs) {
        historicalSales[doc.id] = (doc.data()['salesAmount'] as num).toDouble();
      }
      
      final currentMonthId = DateFormat('yyyy-MM').format(now);
      historicalSales[currentMonthId] = apiData.currentMonthSales;

      final sortedSales = Map.fromEntries(
        historicalSales.entries.toList()..sort((e1, e2) => e1.key.compareTo(e2.key))
      );

      if (mounted) {
        setState(() {
          _monthlySales = sortedSales;
        });
      }
    } catch (e) {
      debugPrint("Error fetching sales history: $e");
    }
  }

  Future<void> _fetchCommissionSettings() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('commission_settings').doc('config').get();
      if (doc.exists) {
        setState(() {
          _commissionRate = (doc.data()?['rate'] as num?)?.toDouble() ?? 100.0;
          _commissionTarget = (doc.data()?['target'] as num?)?.toDouble() ?? 100000.0;
          _rateController.text = _commissionRate.toString();
          _targetController.text = _commissionTarget.toString();
        });
      }
    } catch (e) {
      debugPrint("Error fetching commission settings: $e");
    }
  }

  Future<void> _saveCommissionSettings() async {
    final rate = double.tryParse(_rateController.text);
    final target = double.tryParse(_targetController.text);

    if (rate == null || target == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กรุณาใส่ข้อมูลให้ถูกต้อง')));
      return;
    }

    await FirebaseFirestore.instance.collection('commission_settings').doc('config').set({
      'rate': rate,
      'target': target,
      'updatedBy': FirebaseAuth.instance.currentUser?.displayName,
      'updatedAt': Timestamp.now(),
    });
    
    if(mounted) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('บันทึกการตั้งค่าสำเร็จ'), backgroundColor: Colors.green));
       _fetchCommissionSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? const Center(child: CircularProgressIndicator(color: Colors.white))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                _buildSalesGrowthCard(),
                const SizedBox(height: 16),
                _buildCommissionCard(),
                if (_isAdmin) ...[
                  const SizedBox(height: 16),
                  _buildAdminSettingsCard(),
                ]
              ],
            ),
          );
  }

  Widget _buildSalesGrowthCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('กราฟยอดขายย้อนหลัง', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: _monthlySales.isEmpty
                  ? const Center(child: Text('ไม่มีข้อมูลเพียงพอสำหรับแสดงกราฟ'))
                  : LineChart(_buildChartData()),
            ),
          ],
        ),
      ),
    );
  }

  LineChartData _buildChartData() {
    final spots = _monthlySales.entries.map((entry) {
      final monthIndex = int.parse(entry.key.split('-')[1]);
      return FlSpot(monthIndex.toDouble(), entry.value);
    }).toList();

    return LineChartData(
      gridData: const FlGridData(show: true),
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (value, meta) {
          final monthName = DateFormat('MMM', 'th_TH').format(DateTime(0, value.toInt()));
          return Text(monthName, style: const TextStyle(fontSize: 10));
        })),
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 50, getTitlesWidget: (value, meta) {
           if (value == meta.max || value == meta.min) return const Text('');
           return Text(_currencyFormat.format(value), style: const TextStyle(fontSize: 10));
        })),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: true, border: Border.all(color: const Color(0xff37434d), width: 1)),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: Theme.of(context).primaryColor,
          barWidth: 4,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(show: true, color: Theme.of(context).primaryColor.withOpacity(0.3)),
        ),
      ],
    );
  }

  Widget _buildCommissionCard() {
    return FutureBuilder<CustomerApiData>(
      future: widget.customerApiDataFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        
        final apiData = snapshot.data!;
        final rebateData = apiData.rebateData;
        final currentSales = apiData.currentMonthSales;
        final monthlyTarget = rebateData?.monthlyTarget ?? 0.0;
        
        double commission = 0;
        if (monthlyTarget > 0 && currentSales >= monthlyTarget) {
          commission = (currentSales / _commissionTarget).floor() * _commissionRate;
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('คำนวณค่าคอมมิชชั่น (โดยประมาณ)', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const Divider(),
                _buildInfoRow('เป้าหมายเดือนนี้:', _currencyFormat.format(monthlyTarget)),
                _buildInfoRow('ยอดขายปัจจุบัน:', _currencyFormat.format(currentSales)),
                const Divider(),
                _buildInfoRow('ค่าคอมมิชชั่น:', '฿${_currencyFormat.format(commission)}', isTotal: true),
                const SizedBox(height: 8),
                Text(
                  'เงื่อนไข: ทุกๆ ${_currencyFormat.format(_commissionTarget)} บาท ของยอดขาย จะได้รับ ${_currencyFormat.format(_commissionRate)} บาท (เมื่อทำถึงเป้าหมาย)',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAdminSettingsCard() {
    return Card(
      color: Colors.indigo.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ตั้งค่าคอมมิชชั่น (Admin)', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.indigo)),
            const SizedBox(height: 12),
            TextField(
              controller: _targetController,
              decoration: const InputDecoration(labelText: 'ยอดขายสำหรับคำนวณ (บาท)', border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rateController,
              decoration: const InputDecoration(labelText: 'ค่าคอมมิชชั่น (บาท)', border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveCommissionSettings,
                child: const Text('บันทึกการตั้งค่า'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 16, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal, color: isTotal ? Colors.green.shade800 : null)),
        ],
      ),
    );
  }
}
