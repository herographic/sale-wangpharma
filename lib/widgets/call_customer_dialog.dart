// lib/widgets/call_customer_dialog.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:salewang/models/customer.dart';
import 'package:salewang/models/product.dart';
import 'package:salewang/models/sales_order.dart';
import 'package:salewang/utils/date_helper.dart';
// ignore: depend_on_referenced_packages
import 'package:collection/collection.dart'; // Import for groupBy

// Helper class to combine SalesOrder with its corresponding Product data
class EnrichedSalesOrder {
  final SalesOrder order;
  final Product? product;

  EnrichedSalesOrder({required this.order, this.product});
}

class CallCustomerDialog extends StatefulWidget {
  final Customer customer;

  const CallCustomerDialog({super.key, required this.customer});

  @override
  State<CallCustomerDialog> createState() => _CallCustomerDialogState();
}

class _CallCustomerDialogState extends State<CallCustomerDialog> {
  late Future<List<EnrichedSalesOrder>> _pendingOrdersFuture;
  final NumberFormat _currencyFormat = NumberFormat("#,##0.00", "en_US");

  @override
  void initState() {
    super.initState();
    _pendingOrdersFuture = _fetchPendingOrdersAndProducts();
  }

  Future<List<EnrichedSalesOrder>> _fetchPendingOrdersAndProducts() async {
    final orderSnapshot = await FirebaseFirestore.instance
        .collection('sales_orders')
        .where('รหัสลูกหนี้', isEqualTo: widget.customer.customerId)
        .get();
    final orders = orderSnapshot.docs.map((doc) => SalesOrder.fromFirestore(doc)).toList();

    if (orders.isEmpty) return [];

    final productIds = orders.map((o) => o.productId.replaceAll('/', '-')).where((id) => id.isNotEmpty).toSet().toList();
    final Map<String, Product> productsMap = {};

    if (productIds.isNotEmpty) {
      const batchSize = 30;
      for (var i = 0; i < productIds.length; i += batchSize) {
        final batchIds = productIds.sublist(i, i + batchSize > productIds.length ? productIds.length : i + batchSize);
        if (batchIds.isNotEmpty) {
          final productSnapshot = await FirebaseFirestore.instance
              .collection('products')
              .where(FieldPath.documentId, whereIn: batchIds)
              .get();
          for (final doc in productSnapshot.docs) {
            final product = Product.fromFirestore(doc);
            productsMap[product.id] = product;
          }
        }
      }
    }

    return orders.map((order) {
      final sanitizedId = order.productId.replaceAll('/', '-');
      return EnrichedSalesOrder(order: order, product: productsMap[sanitizedId]);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      actionsPadding: const EdgeInsets.all(8),
      title: Row(children: [
        const Icon(Icons.receipt_long_outlined, size: 28),
        const SizedBox(width: 12),
        Expanded(child: Text('ค้างสั่งจอง: ${widget.customer.name}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
      ]),
      content: SizedBox(
        width: double.maxFinite,
        child: _buildPendingOrdersSection(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('ปิด')),
      ],
    );
  }

  Widget _buildPendingOrdersSection() {
    return FutureBuilder<List<EnrichedSalesOrder>>(
      future: _pendingOrdersFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator()));
        }
        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.check_circle_outline, color: Colors.green, size: 28),
            title: Text('ไม่มีรายการค้างส่ง', style: TextStyle(fontSize: 16)),
          );
        }
        
        final orders = snapshot.data!;
        final groupedByInvoice = groupBy(orders, (EnrichedSalesOrder o) => o.order.invoiceNumber);
        
        final sortedInvoiceEntries = groupedByInvoice.entries.toList()
          ..sort((a, b) {
            final dateAStr = a.value.first.order.orderDate;
            final dateBStr = b.value.first.order.orderDate;
            return dateBStr.compareTo(dateAStr);
          });

        return SizedBox(
          height: 400,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: sortedInvoiceEntries.length,
            itemBuilder: (context, index) {
              final entry = sortedInvoiceEntries[index];
              final invoiceNumber = entry.key;
              final ordersForInvoice = entry.value;
              ordersForInvoice.sort((a, b) => b.order.totalAmount.compareTo(a.order.totalAmount));
              return _buildInvoiceGroup(invoiceNumber, ordersForInvoice);
            },
          ),
        );
      },
    );
  }

  Widget _buildInvoiceGroup(String invoiceNumber, List<EnrichedSalesOrder> orders) {
    final String date = DateHelper.formatDateToThai(orders.first.order.orderDate);
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'วันที่: $date | SO: $invoiceNumber',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo),
          ),
          const Divider(color: Colors.indigo, thickness: 0.5),
          ...orders.map((enrichedOrder) {
            return Column(
              children: [
                _buildOrderItem(enrichedOrder),
                const Divider(height: 1), 
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildOrderItem(EnrichedSalesOrder enrichedOrder) {
    final order = enrichedOrder.order;
    final product = enrichedOrder.product;
    final bool isLowStock = product != null && product.stockQuantity < product.minQuantity;
    final stockTextStyle = TextStyle(
      fontSize: 16, // Adjusted size
      fontWeight: FontWeight.bold,
      color: isLowStock ? Colors.red.shade700 : Colors.black87,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  order.productDescription,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), 
                ),
              ),
              const SizedBox(width: 8),
              order.totalAmount == 0
                  ? Text('ฟรี', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red.shade700))
                  : Text('฿${_currencyFormat.format(order.totalAmount)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
            ],
          ),
          Text('รหัส: ${order.productId}', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('สั่ง: ${order.quantity} ${order.unit}', style: const TextStyle(fontSize: 16)), // Adjusted size
              Text('คงเหลือ: ${product != null ? product.stockQuantity.toStringAsFixed(0) : '?'} ${product?.unit1 ?? ''}', style: stockTextStyle),
            ],
          ),
          const SizedBox(height: 8),
          // --- RE-ADDED: The extra info widget ---
          _ProductExtraInfo(productId: order.productId),
        ],
      ),
    );
  }
}


// --- RE-ADDED: This stateful widget fetches and displays extra product info ---
class _ProductExtraInfo extends StatefulWidget {
  final String productId;

  const _ProductExtraInfo({required this.productId});

  @override
  State<_ProductExtraInfo> createState() => _ProductExtraInfoState();
}

class _ProductExtraInfoState extends State<_ProductExtraInfo> {
  String? _purchaseDate;
  String? _poNumber;
  String? _poDate;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchExtraInfo();
  }

  Future<void> _fetchExtraInfo() async {
    if (!mounted) return;
    final cleanProductId = widget.productId.trim().replaceAll('/', '-');
    if (cleanProductId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final purchaseSnapshot = await FirebaseFirestore.instance
          .collection('purchases')
          .where('รหัสสินค้า', isEqualTo: cleanProductId)
          .orderBy('วันที่', descending: true)
          .limit(1)
          .get();

      if (purchaseSnapshot.docs.isNotEmpty) {
        final purchaseData = purchaseSnapshot.docs.first.data();
        final dateStr = purchaseData['วันที่']?.toString() ?? '';
        if (dateStr.isNotEmpty) {
          _purchaseDate = DateHelper.formatDateToThai(dateStr);
        }
      }

      final poSnapshot = await FirebaseFirestore.instance
          .collection('po')
          .where('รหัสสินค้า', isEqualTo: cleanProductId)
          .orderBy('วันที่', descending: true)
          .limit(1)
          .get();
      
      if (poSnapshot.docs.isNotEmpty) {
        final poData = poSnapshot.docs.first.data();
        _poNumber = poData['เลขที่ใบกำกับ']?.toString();
        final dateStr = poData['วันที่']?.toString() ?? '';
        if (dateStr.isNotEmpty) {
          _poDate = DateHelper.formatDateToThai(dateStr);
        }
      }
    } catch (e) {
      debugPrint("Error fetching extra info: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 8.0),
        child: SizedBox(height: 15.0, child: LinearProgressIndicator(minHeight: 2)),
      );
    }

    if (_purchaseDate == null && _poNumber == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 12.0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEA),
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: const Color(0xFFF5E6B6))
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_purchaseDate != null)
            _buildInfoRow(
              icon: Icons.history,
              iconColor: Colors.red.shade700,
              label: 'ซื้อล่าสุด : ',
              value: _purchaseDate!,
              valueColor: Colors.red.shade700,
            ),
          
          if (_purchaseDate != null && _poNumber != null)
            const Divider(height: 12, thickness: 0.5),

          if (_poNumber != null)
            _buildInfoRow(
              icon: Icons.receipt_long,
              iconColor: Colors.blue.shade800,
              label: 'ใบสั่งซื้อ : ',
              value: '${_poNumber ?? "-"} | ${_poDate ?? "-"}',
              valueColor: Colors.blue.shade800,
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: DefaultTextStyle.of(context).style.copyWith(
                fontSize: 13,
                decoration: TextDecoration.none,
              ),
              children: <TextSpan>[
                TextSpan(text: label, style: TextStyle(color: Colors.grey.shade800)),
                TextSpan(
                  text: value,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: valueColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
