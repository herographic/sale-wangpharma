// lib/screens/app_orders_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:salewang/models/app_order.dart';
import 'package:salewang/screens/printable_invoice_screen.dart'; // Import the new screen
import 'package:share_plus/share_plus.dart';

class AppOrdersScreen extends StatefulWidget {
  const AppOrdersScreen({super.key});

  @override
  State<AppOrdersScreen> createState() => _AppOrdersScreenState();
}

class _AppOrdersScreenState extends State<AppOrdersScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  bool _isLoading = true;
  List<AppOrder> _allOrders = [];

  @override
  void initState() {
    super.initState();
    _fetchOrders();
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
      _fetchOrders(searchQuery: _searchController.text);
    });
  }

  Future<void> _fetchOrders({String? searchQuery}) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      Query baseQuery = FirebaseFirestore.instance
          .collection('app_sales_orders')
          .orderBy('orderDate', descending: true);

      List<AppOrder> fetchedOrders;

      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final queryUpper = searchQuery.trim();

        final nameQuery = baseQuery
            .where('customerName', isGreaterThanOrEqualTo: queryUpper)
            .where('customerName', isLessThanOrEqualTo: '$queryUpper\uf8ff')
            .get();

        final customerIdQuery = baseQuery
            .where('customerId', isGreaterThanOrEqualTo: queryUpper)
            .where('customerId', isLessThanOrEqualTo: '$queryUpper\uf8ff')
            .get();
        
        final soNumberQuery = baseQuery
            .where('soNumber', isGreaterThanOrEqualTo: queryUpper)
            .where('soNumber', isLessThanOrEqualTo: '$queryUpper\uf8ff')
            .get();

        final results = await Future.wait([nameQuery, customerIdQuery, soNumberQuery]);

        final Map<String, AppOrder> uniqueOrders = {};
        for (final snapshot in results) {
          for (final doc in snapshot.docs) {
            uniqueOrders[doc.id] = AppOrder.fromFirestore(doc);
          }
        }
        fetchedOrders = uniqueOrders.values.toList();
        fetchedOrders.sort((a, b) => b.orderDate.compareTo(a.orderDate));
      } else {
        final snapshot = await baseQuery.limit(50).get();
        fetchedOrders = snapshot.docs.map((doc) => AppOrder.fromFirestore(doc)).toList();
      }

      if (mounted) {
        setState(() {
          _allOrders = fetchedOrders;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการค้นหา: $e')),
        );
      }
    }
  }

  void _deleteOrder(String orderId) async {
    final bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: const Text('คุณแน่ใจหรือไม่ว่าต้องการลบใบสั่งจองนี้?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('ยกเลิก')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('ลบ', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance.collection('app_sales_orders').doc(orderId).delete();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ลบใบสั่งจองสำเร็จ'), backgroundColor: Colors.green),
        );
        _fetchOrders(searchQuery: _searchController.text);
      } catch (e) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการลบ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _shareOrder(AppOrder order) async {
    final currencyFormat = NumberFormat("#,##0.00");
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    String itemsText = '';
    for (var item in order.items) {
      final itemTotal = item.unitPrice * item.quantity;
      itemsText += 
        '------------------------------------\n'
        'สินค้า: ${item.productDescription}\n'
        'รหัส: ${item.productId}\n'
        'จำนวน: ${item.quantity.toStringAsFixed(0)} ${item.unit}\n'
        'ราคา: ${currencyFormat.format(item.unitPrice)} / หน่วย\n'
        'รวม: ${currencyFormat.format(itemTotal)} บาท\n';
    }

    final String noteText = order.note.isNotEmpty ? '\n**หมายเหตุ:** ${order.note}\n' : '';

    final String shareText = 
      '📋 ใบสั่งจอง (สำเนา) 📋\n\n'
      'ลูกค้า: ${order.customerName}\n'
      'รหัส: ${order.customerId}\n\n'
      'เลขที่ SO: ${order.soNumber}\n'
      'วันที่: ${dateFormat.format(order.orderDate.toDate())}\n'
      'พนักงานขาย: ${order.salespersonName}\n'
      '$noteText'
      '\n-- รายการสินค้า --\n'
      '$itemsText'
      '------------------------------------\n'
      'ยอดรวมทั้งสิ้น: ${currencyFormat.format(order.totalAmount)} บาท';

    try {
      await Share.share(shareText, subject: 'ใบสั่งจองสำหรับ ${order.customerName}');
    } catch (e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ไม่สามารถแชร์ได้: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'ค้นหา (ชื่อ, รหัสลูกค้า, เลข SO)',
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
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : _allOrders.isEmpty
                    ? const Center(child: Text('ไม่พบใบสั่งจอง', style: TextStyle(color: Colors.white)))
                    : RefreshIndicator(
                        onRefresh: () => _fetchOrders(searchQuery: _searchController.text),
                        child: ListView.builder(
                          padding: const EdgeInsets.only(bottom: 16),
                          itemCount: _allOrders.length,
                          itemBuilder: (context, index) {
                            final order = _allOrders[index];
                            return _buildOrderCard(order);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(AppOrder order) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ExpansionTile(
        title: Row(
          children: [
            Expanded(
              child: Text(
                '${order.customerName} (${order.customerId})', 
                style: const TextStyle(fontWeight: FontWeight.bold)
              ),
            ),
            // --- UPDATED: Button Row ---
            IconButton(
              icon: Icon(Icons.share, color: Theme.of(context).primaryColor, size: 20),
              tooltip: 'แชร์ใบสั่งจอง',
              onPressed: () => _shareOrder(order),
            ),
            IconButton(
              icon: Icon(Icons.print_outlined, color: Colors.blue.shade700, size: 20),
              tooltip: 'ปริ้นท์เอกสาร',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => PrintableInvoiceScreen(order: order)),
                );
              },
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.red.shade700, size: 20),
              tooltip: 'ลบใบสั่งจอง',
              onPressed: () => _deleteOrder(order.id),
            ),
          ],
        ),
        subtitle: Text(
          'SO: ${order.soNumber}\nโดย: ${order.salespersonName}\nวันที่: ${DateFormat('dd/MM/yyyy HH:mm').format(order.orderDate.toDate())}',
        ),
        trailing: Text(
          '฿${NumberFormat("#,##0.00").format(order.totalAmount)}',
          style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        children: [
          ...order.items.map((item) {
            return ListTile(
              title: Text(item.productDescription),
              subtitle: Text(
                '${item.quantity.toStringAsFixed(0)} x ${item.unit} @ ${NumberFormat("#,##0.00").format(item.unitPrice)}',
              ),
              trailing: Text(
                '฿${NumberFormat("#,##0.00").format(item.unitPrice * item.quantity)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            );
          }),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // --- UPDATED: Button Row ---
                TextButton.icon(
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text('แชร์'),
                  onPressed: () => _shareOrder(order),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  icon: const Icon(Icons.print_outlined, size: 18),
                  label: const Text('ปริ้นท์'),
                  style: TextButton.styleFrom(foregroundColor: Colors.blue.shade700),
                  onPressed: () {
                     Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => PrintableInvoiceScreen(order: order)),
                    );
                  },
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('ลบ'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: () => _deleteOrder(order.id),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
