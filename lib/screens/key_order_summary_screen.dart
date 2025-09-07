// lib/screens/key_order_summary_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:salewang/models/app_order.dart';
import 'package:salewang/models/customer.dart';
import 'package:salewang/screens/key_order_screen.dart'; // For KeyOrderItem
import 'package:salewang/screens/main_screen.dart';

class KeyOrderSummaryScreen extends StatefulWidget {
  final Customer customer;
  final List<KeyOrderItem> orderItems;
  final String soNumber;
  final String note;

  const KeyOrderSummaryScreen({
    super.key,
    required this.customer,
    required this.orderItems,
    required this.soNumber,
    required this.note,
  });

  @override
  State<KeyOrderSummaryScreen> createState() => _KeyOrderSummaryScreenState();
}

class _KeyOrderSummaryScreenState extends State<KeyOrderSummaryScreen> {
  bool _isSaving = false;
  final NumberFormat _currencyFormat = NumberFormat("#,##0.00", "en_US");

  Future<void> _saveOrder() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่พบข้อมูลผู้ใช้'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final itemsToSave = widget.orderItems.map((item) {
        return AppOrderItem(
          productId: item.product.id,
          productDescription: item.product.description,
          quantity: item.quantity,
          unit: item.selectedUnit,
          unitPrice: item.calculatedPrice,
        );
      }).toList();

      final totalAmount = itemsToSave.fold(0.0, (sum, item) => sum + (item.unitPrice * item.quantity));

      final newOrder = {
        'soNumber': widget.soNumber,
        'customerId': widget.customer.customerId,
        'customerName': widget.customer.name,
        'orderDate': Timestamp.now(),
        'totalAmount': totalAmount,
        'items': itemsToSave.map((item) => item.toMap()).toList(),
        'status': 'pending',
        'salespersonId': user.uid,
        'salespersonName': user.displayName ?? user.email ?? 'N/A',
        'note': widget.note,
      };

      await FirebaseFirestore.instance.collection('app_sales_orders').add(newOrder);
      
      // Clear the state after successful save
      OrderStateService().clearState();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกออเดอร์สำเร็จ!'), backgroundColor: Colors.green),
        );
        // Navigate to the main screen (App Orders tab) and remove all previous routes
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const MainScreen(initialIndex: 4)),
          (Route<dynamic> route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการบันทึก: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalAmount = widget.orderItems.fold(0.0, (sum, item) => sum + (item.calculatedPrice * item.quantity));
    final vatAmount = totalAmount * 7 / 107;
    final amountBeforeVat = totalAmount - vatAmount;

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
          title: const Text('ตรวจสอบและยืนยันออเดอร์', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12.0),
                children: [
                  _buildCustomerCard(),
                  const SizedBox(height: 12),
                  _buildItemsCard(),
                ],
              ),
            ),
            _buildSummaryAndConfirm(totalAmount, amountBeforeVat, vatAmount),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.customer.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('รหัสลูกค้า: ${widget.customer.customerId}', style: TextStyle(color: Colors.grey.shade700)),
            Text('${widget.customer.address1} ${widget.customer.address2}', style: TextStyle(color: Colors.grey.shade700)),
          ],
        ),
      ),
    );
  }

  Widget _buildItemsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('รายการสินค้า', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Divider(),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.orderItems.length,
              itemBuilder: (context, index) {
                final item = widget.orderItems[index];
                final itemTotal = item.calculatedPrice * item.quantity;
                return ListTile(
                  title: Text(item.product.description),
                  subtitle: Text('${item.quantity.toStringAsFixed(0)} x ${item.selectedUnit} (${_currencyFormat.format(item.calculatedPrice)}/หน่วย)'),
                  trailing: Text(_currencyFormat.format(itemTotal), style: const TextStyle(fontWeight: FontWeight.bold)),
                );
              },
              separatorBuilder: (context, index) => const Divider(height: 1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryAndConfirm(double totalAmount, double amountBeforeVat, double vatAmount) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Column(
        children: [
          if (widget.note.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text('หมายเหตุ: ${widget.note}', style: const TextStyle(fontStyle: FontStyle.italic)),
            ),
            const SizedBox(height: 16),
          ],
          _buildSummaryRow('ยอดก่อนภาษี:', '฿${_currencyFormat.format(amountBeforeVat)}'),
          _buildSummaryRow('ภาษีมูลค่าเพิ่ม (7%):', '฿${_currencyFormat.format(vatAmount)}'),
          const Divider(),
          _buildSummaryRow('ยอดรวมทั้งสิ้น:', '฿${_currencyFormat.format(totalAmount)}', isTotal: true),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: _isSaving ? const SizedBox.shrink() : const Icon(Icons.check_circle),
              label: _isSaving
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('ยืนยันและสร้างใบสั่งจอง', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              onPressed: _isSaving ? null : _saveOrder,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String title, String amount, {bool isTotal = false}) {
    final textStyle = TextStyle(
      fontSize: isTotal ? 20 : 16,
      fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
      color: isTotal ? Colors.green.shade800 : Colors.black87,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: textStyle.copyWith(fontWeight: FontWeight.normal, fontSize: 16)),
          Text(amount, style: textStyle),
        ],
      ),
    );
  }
}
