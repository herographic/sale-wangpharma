// lib/screens/pending_so_report_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:salewang/models/customer.dart';
import 'package:salewang/models/product.dart';
import 'package:salewang/models/sales_order.dart';
import 'package:collection/collection.dart';
import 'package:salewang/utils/date_helper.dart';
import 'package:salewang/utils/launcher_helper.dart';
import 'package:share_plus/share_plus.dart';

// Model to hold combined Customer and their pending SOs
class CustomerPendingOrders {
  final Customer customer;
  final List<SalesOrder> orders;

  CustomerPendingOrders({required this.customer, required this.orders});
}

class PendingSoReportScreen extends StatefulWidget {
  final String salespersonCode;
  final String salespersonName;

  const PendingSoReportScreen({
    super.key,
    required this.salespersonCode,
    required this.salespersonName,
  });

  @override
  State<PendingSoReportScreen> createState() => _PendingSoReportScreenState();
}

class _PendingSoReportScreenState extends State<PendingSoReportScreen> {
  List<CustomerPendingOrders>? _reportData;
  bool _isLoading = true;
  // This set now acts as a local cache for quick UI updates
  final Set<String> _clearedOrderIds = {};
  final String _currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _fetchPendingOrders();
  }

  Future<void> _fetchPendingOrders() async {
    setState(() => _isLoading = true);
    final firestore = FirebaseFirestore.instance;

    final customerSnapshot = await firestore
        .collection('customers')
        .where('พนักงานขาย', isEqualTo: widget.salespersonCode)
        .get();

    if (customerSnapshot.docs.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final customers =
        customerSnapshot.docs.map((doc) => Customer.fromFirestore(doc)).toList();
    final customerIds = customers.map((c) => c.customerId).toList();

    final List<SalesOrder> allOrders = [];
    for (var i = 0; i < customerIds.length; i += 30) {
      final chunk = customerIds.sublist(
          i, i + 30 > customerIds.length ? customerIds.length : i + 30);
      if (chunk.isNotEmpty) {
        final soSnapshot = await firestore
            .collection('sales_orders')
            .where('รหัสลูกหนี้', whereIn: chunk)
            .get();
        allOrders
            .addAll(soSnapshot.docs.map((doc) => SalesOrder.fromFirestore(doc)));
      }
    }

    if (allOrders.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    _clearedOrderIds.clear();
    for (final order in allOrders) {
      if (order.clearedBy.contains(_currentUserId)) {
        _clearedOrderIds.add(order.id);
      }
    }

    final groupedByCustomer =
        groupBy(allOrders, (SalesOrder order) => order.customerId);

    final List<CustomerPendingOrders> reportData = [];
    for (var customer in customers) {
      final pendingOrders = groupedByCustomer[customer.customerId];
      if (pendingOrders != null && pendingOrders.isNotEmpty) {
        reportData.add(
            CustomerPendingOrders(customer: customer, orders: pendingOrders));
      }
    }

    reportData.sort((a, b) => a.customer.name.compareTo(b.customer.name));

    if (mounted) {
      setState(() {
        _reportData = reportData;
        _isLoading = false;
      });
    }
  }

  void _toggleClearedStatus(String orderId) {
    final isCleared = _clearedOrderIds.contains(orderId);
    final firestoreRef =
        FirebaseFirestore.instance.collection('sales_orders').doc(orderId);

    setState(() {
      if (isCleared) {
        _clearedOrderIds.remove(orderId);
      } else {
        _clearedOrderIds.add(orderId);
      }
    });

    if (isCleared) {
      firestoreRef.update({
        'clearedBy': FieldValue.arrayRemove([_currentUserId])
      });
    } else {
      firestoreRef.update({
        'clearedBy': FieldValue.arrayUnion([_currentUserId])
      });
    }
  }

  void _callCustomer(Customer customer) {
    if (customer.contacts.isEmpty ||
        customer.contacts.first['phone']!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('ลูกค้ารายนี้ไม่มีเบอร์โทรศัพท์'),
            backgroundColor: Colors.orange),
      );
      return;
    }
    LauncherHelper.makeAndLogPhoneCall(
      context: context,
      phoneNumber: customer.contacts.first['phone']!,
      customer: customer,
    );
  }

  void _shareOrders(CustomerPendingOrders customerOrder) {
    final currencyFormat = NumberFormat("#,##0.00", "en_US");
    final totalAmount = customerOrder.orders.fold<double>(0.0, (sum, order) => sum + order.totalAmount);
    final vatAmount = totalAmount * 7 / 107;
    final amountBeforeVat = totalAmount - vatAmount;

    String itemsText = customerOrder.orders.map((o) {
      final status =
          _clearedOrderIds.contains(o.id) ? '✅ (เคลียร์แล้ว)' : '❌ (สินค้าขาด)';
      return '📦 ${o.productDescription}\n'
          '  - รหัส: ${o.productId}\n'
          '  - SO: ${o.invoiceNumber}\n'
          '  - จำนวน: ${o.quantity.toInt()} ${o.unit}\n'
          '  - ยอดเงิน: ${currencyFormat.format(o.totalAmount)} บาท\n'
          '  - สถานะ: $status';
    }).join('\n------------------------------------\n');

    String summaryText = 'ยอดรวมก่อน VAT: ${currencyFormat.format(amountBeforeVat)} บาท\n'
                         'ภาษี 7%: ${currencyFormat.format(vatAmount)} บาท\n'
                         'ยอดรวมสุทธิ: ${currencyFormat.format(totalAmount)} บาท';

    String shareText =
        '✨ สรุปรายการค้างส่ง ✨\n'
        'ลูกค้า: ${customerOrder.customer.name}\n'
        'รหัส: ${customerOrder.customer.customerId}\n'
        '====================\n'
        '$itemsText\n'
        '====================\n'
        '📋 สรุปยอดรวม\n'
        '$summaryText';

    Share.share(shareText);
  }

  Future<void> _printReport(CustomerPendingOrders customerOrder) async {
    final doc = pw.Document();
    final font = await PdfGoogleFonts.promptBold();
    final fontRegular = await PdfGoogleFonts.promptRegular();
    final currencyFormat = NumberFormat("#,##0.00", "en_US");

    final productIds = customerOrder.orders
        .map((o) => o.productId.replaceAll('/', '-'))
        .toSet()
        .toList();
    final Map<String, Product> productMap = {};
    if (productIds.isNotEmpty) {
       for (var i = 0; i < productIds.length; i += 30) {
        final chunk = productIds.sublist(i, i + 30 > productIds.length ? productIds.length : i + 30);
         if (chunk.isNotEmpty) {
            final productSnapshot = await FirebaseFirestore.instance.collection('products').where(FieldPath.documentId, whereIn: chunk).get();
            for (final doc in productSnapshot.docs) {
              productMap[doc.id] = Product.fromFirestore(doc);
            }
         }
       }
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            pw.Text('รายการค้างส่ง: ${customerOrder.customer.name}',
                style: pw.TextStyle(font: font, fontSize: 18)),
            pw.Text('รหัสลูกค้า: ${customerOrder.customer.customerId}',
                style: pw.TextStyle(font: fontRegular, fontSize: 12)),
            pw.Text('พิมพ์วันที่: ${DateFormat('d MMMM yyyy', 'th_TH').format(DateTime.now())}',
                style: pw.TextStyle(font: fontRegular, fontSize: 10)),
            pw.Divider(height: 20),
            pw.Table.fromTextArray(
              headers: ['รหัส', 'รายการ', 'SO/วันที่', 'สต็อก', 'จำนวน', 'ยอดเงิน', 'สถานะ'],
              data: customerOrder.orders.map((order) {
                final product = productMap[order.productId.replaceAll('/', '-')];
                final status = _clearedOrderIds.contains(order.id) ? 'เคลียร์' : 'ขาด';
                return [
                  order.productId,
                  order.productDescription,
                  '${order.invoiceNumber}\n(${DateHelper.formatDateToThai(order.orderDate)})',
                  product != null ? '${product.stockQuantity.toInt()} ${product.unit1}' : 'N/A',
                  '${order.quantity.toInt()} ${order.unit}',
                  currencyFormat.format(order.totalAmount),
                  status,
                ];
              }).toList(),
              headerStyle: pw.TextStyle(font: font, fontSize: 9),
              cellStyle: pw.TextStyle(font: fontRegular, fontSize: 9),
              border: pw.TableBorder.all(),
              cellAlignment: pw.Alignment.centerLeft,
              cellAlignments: {
                3: pw.Alignment.centerRight,
                4: pw.Alignment.centerRight,
                5: pw.Alignment.centerRight,
                6: pw.Alignment.center,
              },
              columnWidths: {
                0: const pw.FlexColumnWidth(1.2),
                1: const pw.FlexColumnWidth(2.5),
                2: const pw.FlexColumnWidth(1.5),
                3: const pw.FlexColumnWidth(0.8),
                4: const pw.FlexColumnWidth(0.8),
                5: const pw.FlexColumnWidth(1),
                6: const pw.FlexColumnWidth(0.6),
              },
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
    );
  }

  Future<void> _deleteOrders(CustomerPendingOrders customerOrder) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: Text(
            'คุณต้องการลบ SO ค้างส่งทั้งหมดของ "${customerOrder.customer.name}" ใช่หรือไม่?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('ยืนยันลบ'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final batch = FirebaseFirestore.instance.batch();
    final soCollection = FirebaseFirestore.instance.collection('sales_orders');
    for (var order in customerOrder.orders) {
      batch.delete(soCollection.doc(order.id));
    }

    try {
      await batch.commit();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('ลบรายการสำเร็จ'), backgroundColor: Colors.green),
      );
      setState(() {
        _reportData?.remove(customerOrder);
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาด: $e'), backgroundColor: Colors.red),
      );
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
          title: Text('SO ค้าง: ${widget.salespersonName}',
              style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : (_reportData == null || _reportData!.isEmpty)
                ? const Center(
                    child: Text('ไม่พบรายการ SO ค้างส่ง',
                        style: TextStyle(color: Colors.white, fontSize: 16)))
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _reportData!.length,
                    itemBuilder: (context, index) {
                      final customerOrder = _reportData![index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        clipBehavior: Clip.antiAlias,
                        child: ExpansionTile(
                          title: Text(
                            customerOrder.customer.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                              'รหัส: ${customerOrder.customer.customerId}'),
                          children: [
                            ...customerOrder.orders.map((order) {
                              return PendingOrderItemTile(
                                key: ValueKey(order.id),
                                order: order,
                                isCleared: _clearedOrderIds.contains(order.id),
                                onTap: () => _toggleClearedStatus(order.id),
                              );
                            }),
                            const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8.0, vertical: 4.0),
                              child: OverflowBar(
                                alignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  TextButton.icon(
                                    icon: const Icon(Icons.call, size: 18),
                                    label: const Text('โทร'),
                                    onPressed: () =>
                                        _callCustomer(customerOrder.customer),
                                  ),
                                  TextButton.icon(
                                    icon: const Icon(Icons.print, size: 18),
                                    label: const Text('พิมพ์'),
                                    onPressed: () =>
                                        _printReport(customerOrder),
                                  ),
                                  TextButton.icon(
                                    icon: const Icon(Icons.share, size: 18),
                                    label: const Text('แชร์'),
                                    onPressed: () =>
                                        _shareOrders(customerOrder),
                                  ),
                                  TextButton.icon(
                                    icon: const Icon(Icons.delete_forever,
                                        size: 18),
                                    label: const Text('ลบ'),
                                    style: TextButton.styleFrom(
                                        foregroundColor: Colors.red),
                                    onPressed: () =>
                                        _deleteOrders(customerOrder),
                                  ),
                                ],
                              ),
                            )
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

class PendingOrderItemTile extends StatefulWidget {
  final SalesOrder order;
  final bool isCleared;
  final VoidCallback onTap;

  const PendingOrderItemTile({
    super.key,
    required this.order,
    required this.isCleared,
    required this.onTap,
  });

  @override
  State<PendingOrderItemTile> createState() => _PendingOrderItemTileState();
}

class _PendingOrderItemTileState extends State<PendingOrderItemTile> {
  Future<Product?>? _productFuture;

  @override
  void initState() {
    super.initState();
    _productFuture = _fetchProduct(widget.order.productId);
  }

  Future<Product?> _fetchProduct(String productId) async {
    try {
      final sanitizedId = productId.replaceAll('/', '-');
      final doc = await FirebaseFirestore.instance
          .collection('products')
          .doc(sanitizedId)
          .get();
      if (doc.exists) {
        return Product.fromFirestore(doc);
      }
    } catch (e) {
      debugPrint("Error fetching product $productId: $e");
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat("#,##0.00", "en_US");

    return FutureBuilder<Product?>(
      future: _productFuture,
      builder: (context, snapshot) {
        final product = snapshot.data;
        final stockText = product != null
            ? '${product.stockQuantity.toStringAsFixed(0)} ${product.unit1}'
            : '...';

        return ListTile(
          isThreeLine: true,
          tileColor:
              widget.isCleared ? Colors.green.shade50 : Colors.red.shade50,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'รหัสสินค้า: ${widget.order.productId}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              Text(widget.order.productDescription,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                  'SO: ${widget.order.invoiceNumber} (${DateHelper.formatDateToThai(widget.order.orderDate)})'),
              Text('สต็อก: $stockText',
                  style: TextStyle(
                      color: (product?.stockQuantity ?? 0) > 0
                          ? Colors.green.shade800
                          : Colors.red.shade800,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${widget.order.quantity.toInt()} ${widget.order.unit}',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              Text(
                '฿${currencyFormat.format(widget.order.totalAmount)}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
          onTap: widget.onTap,
        );
      },
    );
  }
}
