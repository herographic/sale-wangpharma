// lib/screens/shopping_cart_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:salewang/models/app_order.dart';
import 'package:salewang/models/customer.dart';
import 'package:salewang/screens/call_screen.dart';
import 'package:salewang/screens/main_screen.dart';

class ShoppingCartScreen extends StatefulWidget {
  final List<CartItem> confirmedItems;
  final Customer customer;

  const ShoppingCartScreen({
    super.key,
    required this.confirmedItems,
    required this.customer,
  });

  @override
  State<ShoppingCartScreen> createState() => _ShoppingCartScreenState();
}

class _ShoppingCartScreenState extends State<ShoppingCartScreen> {
  bool _isCreatingOrder = false;
  final _noteController = TextEditingController(); // ADDED

  @override
  void dispose() {
    _noteController.dispose(); // ADDED
    super.dispose();
  }

  Future<void> _createNewSalesOrder() async {
    if (widget.confirmedItems.isEmpty) return;
    setState(() => _isCreatingOrder = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่พบข้อมูลผู้ใช้ กรุณาล็อกอินใหม่'), backgroundColor: Colors.red),
        );
        setState(() => _isCreatingOrder = false);
      }
      return;
    }

    try {
      final totalAmount = widget.confirmedItems.fold(0.0, (sum, item) {
          final product = item.enrichedOrder.product;
          if (product == null) return sum;

          final allUnits = [
            {'name': product.unit1, 'ratio': product.ratio1},
            {'name': product.unit2, 'ratio': product.ratio2},
            {'name': product.unit3, 'ratio': product.ratio3},
          ];
          final validUnits = allUnits.where((u) => (u['name'] as String).isNotEmpty && (u['ratio'] as double) > 0).toList();
          if (validUnits.isEmpty) return sum;
          
          final maxRatio = validUnits.map((u) => u['ratio'] as double).reduce((a, b) => a > b ? a : b);
          final selectedUnitOption = validUnits.firstWhere((u) => u['name'] == item.selectedUnit, orElse: () => validUnits.first);
          final multiplier = maxRatio / (selectedUnitOption['ratio'] as double);
          
          double basePrice;
          switch (widget.customer.p.toUpperCase()) {
            case 'B': basePrice = product.priceB; break;
            case 'C': basePrice = product.priceC; break;
            default: basePrice = product.priceA;
          }

          final currentUnitPrice = basePrice * multiplier;
          return sum + (currentUnitPrice * item.quantity);
      });

      final newSoNumber = 'APP-${DateTime.now().millisecondsSinceEpoch}';

      final newOrderItems = widget.confirmedItems.map((cartItem) {
        final product = cartItem.enrichedOrder.product;
        if (product == null) return null;

        final allUnits = [
            {'name': product.unit1, 'ratio': product.ratio1},
            {'name': product.unit2, 'ratio': product.ratio2},
            {'name': product.unit3, 'ratio': product.ratio3},
        ];
        final validUnits = allUnits.where((u) => (u['name'] as String).isNotEmpty && (u['ratio'] as double) > 0).toList();
        if (validUnits.isEmpty) return null;

        final maxRatio = validUnits.map((u) => u['ratio'] as double).reduce((a,b) => a > b ? a : b);
        final selectedUnitOption = validUnits.firstWhere((u) => u['name'] == cartItem.selectedUnit, orElse: () => validUnits.first);
        final multiplier = maxRatio / (selectedUnitOption['ratio'] as double);

        double basePrice;
        switch (widget.customer.p.toUpperCase()) {
            case 'B': basePrice = product.priceB; break;
            case 'C': basePrice = product.priceC; break;
            default: basePrice = product.priceA;
        }
        final finalUnitPrice = basePrice * multiplier;

        return AppOrderItem(
          productId: cartItem.enrichedOrder.order.productId,
          productDescription: cartItem.enrichedOrder.order.productDescription,
          quantity: cartItem.quantity,
          unit: cartItem.selectedUnit,
          unitPrice: finalUnitPrice,
        ).toMap();
      }).where((item) => item != null).toList();

      final String noteText = _noteController.text.trim(); // ADDED

      await FirebaseFirestore.instance.collection('app_sales_orders').add({
        'soNumber': newSoNumber,
        'customerId': widget.customer.customerId,
        'customerName': widget.customer.name,
        'orderDate': Timestamp.now(),
        'totalAmount': totalAmount,
        'items': newOrderItems,
        'status': 'pending',
        'salespersonId': user.uid,
        'salespersonName': user.displayName ?? user.email ?? 'N/A',
        'note': noteText, // ADDED
      });

      final originalSoIdsToDelete = widget.confirmedItems
          .where((item) => item.enrichedOrder.order.invoiceNumber != 'NEW')
          .map((item) => item.enrichedOrder.order.id)
          .toSet()
          .toList();

      if (originalSoIdsToDelete.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        final soCollection = FirebaseFirestore.instance.collection('sales_orders');

        for (final docId in originalSoIdsToDelete) {
          batch.delete(soCollection.doc(docId));
        }
        await batch.commit();
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('สร้างใบสั่งจองสำเร็จ!'), backgroundColor: Colors.green),
      );
      
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const MainScreen(initialIndex: 4)),
        (Route<dynamic> route) => false,
      );

    } catch (e) {
      if(mounted) {
        setState(() => _isCreatingOrder = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาด: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final NumberFormat currencyFormat = NumberFormat("#,##0.00", "en_US");
    double totalAmount = widget.confirmedItems.fold(0.0, (sum, item) {
        final product = item.enrichedOrder.product;
        if (product == null) return sum;

        final allUnits = [
          {'name': product.unit1, 'ratio': product.ratio1},
          {'name': product.unit2, 'ratio': product.ratio2},
          {'name': product.unit3, 'ratio': product.ratio3},
        ];
        final validUnits = allUnits.where((u) => (u['name'] as String).isNotEmpty && (u['ratio'] as double) > 0).toList();
        if (validUnits.isEmpty) return sum;
        
        final maxRatio = validUnits.map((u) => u['ratio'] as double).reduce((a, b) => a > b ? a : b);
        final selectedUnitOption = validUnits.firstWhere((u) => u['name'] == item.selectedUnit, orElse: () => validUnits.first);
        final multiplier = maxRatio / (selectedUnitOption['ratio'] as double);
        
        double basePrice;
        switch (widget.customer.p.toUpperCase()) {
          case 'B': basePrice = product.priceB; break;
          case 'C': basePrice = product.priceC; break;
          default: basePrice = product.priceA;
        }

        final currentUnitPrice = basePrice * multiplier;
        return sum + (currentUnitPrice * item.quantity);
    });


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
          title: const Text('สรุปรายการ (รถเข็น)', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
        body: Column(
          children: [
            Card(
              margin: const EdgeInsets.all(8.0),
              elevation: 2,
              child: ListTile(
                leading: Icon(Icons.person, color: Theme.of(context).primaryColor),
                title: Text(widget.customer.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('รหัสลูกค้า: ${widget.customer.customerId}'),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                itemCount: widget.confirmedItems.length,
                itemBuilder: (context, index) {
                  final item = widget.confirmedItems[index];
                  final order = item.enrichedOrder.order;
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4.0),
                    child: ListTile(
                      title: Text(order.productDescription),
                      subtitle: Text('ราคา/หน่วย: ${currencyFormat.format(order.unitPrice)} (ราคาตั้งต้น)'),
                      trailing: Text(
                        '${item.quantity.toStringAsFixed(0)} x ${item.selectedUnit}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                )
              ),
              child: Column(
                children: [
                  // --- START: NEW NOTE TEXT FIELD ---
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: TextField(
                      controller: _noteController,
                      decoration: const InputDecoration(
                        labelText: 'หมายเหตุ',
                        hintText: 'เช่น ไม่รับสินค้าใกล้หมดอายุ...',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.note_add_outlined),
                      ),
                      maxLines: 2,
                    ),
                  ),
                  // --- END: NEW NOTE TEXT FIELD ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('ยอดรวม:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text(
                        '฿${currencyFormat.format(totalAmount)}',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: _isCreatingOrder
                        ? const Center(child: CircularProgressIndicator())
                        : ElevatedButton.icon(
                            icon: const Icon(Icons.receipt_long),
                            label: const Text('ยืนยันและสร้างใบสั่งจอง'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              backgroundColor: Theme.of(context).primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)
                              )
                            ),
                            onPressed: _createNewSalesOrder,
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
