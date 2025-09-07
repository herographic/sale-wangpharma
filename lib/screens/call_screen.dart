// lib/screens/call_screen.dart

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:salewang/models/customer.dart';
import 'package:salewang/models/product.dart';
import 'package:salewang/models/sales_order.dart';
import 'package:salewang/screens/shopping_cart_screen.dart';
import 'package:salewang/widgets/product_search_dialog.dart';
import 'package:salewang/utils/launcher_helper.dart';
import 'package:salewang/utils/date_helper.dart';
import 'package:share_plus/share_plus.dart'; // Import for sharing functionality

class CartItem {
  final EnrichedSalesOrder enrichedOrder;
  double quantity;
  bool isConfirmed;
  String selectedUnit;

  CartItem({
    required this.enrichedOrder,
    required this.quantity,
    required this.selectedUnit,
    this.isConfirmed = true,
  });
}

class EnrichedSalesOrder {
  final SalesOrder order;
  final Product? product;

  EnrichedSalesOrder({required this.order, this.product});
}

class CallScreen extends StatefulWidget {
  final Customer customer;

  const CallScreen({super.key, required this.customer});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final List<CartItem> _cartItems = [];
  bool _isLoading = true;
  final NumberFormat _currencyFormat = NumberFormat("#,##0.00", "en_US");
  late Stream<DocumentSnapshot> _customerStream;

  @override
  void initState() {
    super.initState();
    _loadInitialCart();
    _customerStream = FirebaseFirestore.instance
        .collection('customers')
        .doc(widget.customer.id)
        .snapshots();
  }

  // --- DIALOG FOR CONFIRMATION ---
  Future<bool> _showConfirmationDialog({
    required BuildContext context,
    required String title,
    required String content,
    required String confirmText,
    Color? confirmColor,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: confirmColor),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // --- DIALOG FOR ADD/EDIT FORM ---
  void _showContactForm({
    required Customer currentCustomer,
    Map<String, String>? contact,
    int? index,
  }) {
    final bool isEditing = contact != null;
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: isEditing ? contact['name'] : '');
    final phoneController = TextEditingController(text: isEditing ? contact['phone'] : '');

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(isEditing ? 'แก้ไขผู้ติดต่อ' : 'เพิ่มผู้ติดต่อใหม่'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'ชื่อผู้ติดต่อ', icon: Icon(Icons.person)),
                  validator: (value) => (value == null || value.isEmpty) ? 'กรุณาใส่ชื่อ' : null,
                ),
                TextFormField(
                  controller: phoneController,
                  decoration: const InputDecoration(labelText: 'เบอร์โทรศัพท์', icon: Icon(Icons.phone)),
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'กรุณาใส่เบอร์โทร';
                    if (!RegExp(r'^[0-9-]{9,}$').hasMatch(value)) return 'รูปแบบเบอร์โทรไม่ถูกต้อง';
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('ยกเลิก')),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  final newContact = {'name': nameController.text.trim(), 'phone': phoneController.text.trim()};
                  final docRef = FirebaseFirestore.instance.collection('customers').doc(currentCustomer.id);
                  
                  final currentContacts = List<Map<String, dynamic>>.from(currentCustomer.contacts.map((c) => Map<String, dynamic>.from(c)));

                  if (isEditing) {
                    currentContacts[index!] = newContact;
                  } else {
                    currentContacts.add(newContact);
                  }
                  
                  await docRef.update({'contacts': currentContacts});
                  Navigator.of(dialogContext).pop();
                }
              },
              child: const Text('บันทึก'),
            ),
          ],
        );
      },
    );
  }


  Future<void> _loadInitialCart() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final orderSnapshot = await FirebaseFirestore.instance
          .collection('sales_orders')
          .where('รหัสลูกหนี้', isEqualTo: widget.customer.customerId)
          .get();

      final orders = orderSnapshot.docs.map((doc) => SalesOrder.fromFirestore(doc)).toList();

      if (orders.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final productIds = orders.map((o) => o.productId.replaceAll('/', '-')).where((id) => id.isNotEmpty).toSet().toList();
      final Map<String, Product> productsMap = {};

      if (productIds.isNotEmpty) {
        const batchSize = 30;
        for (var i = 0; i < productIds.length; i += batchSize) {
          final end = (i + batchSize > productIds.length) ? productIds.length : i + batchSize;
          final batchIds = productIds.sublist(i, end);

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

      final newCartItems = <CartItem>[];
      for (final order in orders) {
        final sanitizedProductId = order.productId.replaceAll('/', '-');
        final enrichedOrder = EnrichedSalesOrder(
          order: order,
          product: productsMap[sanitizedProductId],
        );
        newCartItems.add(CartItem(
          enrichedOrder: enrichedOrder,
          quantity: order.quantity,
          isConfirmed: true,
          selectedUnit: order.unit,
        ));
      }

      if (mounted) {
        setState(() {
          _cartItems.clear();
          _cartItems.addAll(newCartItems);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการโหลดข้อมูล: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  double _getBasePriceForCustomer(Product product) {
    switch (widget.customer.p.toUpperCase()) {
      case 'B': return product.priceB;
      case 'C': return product.priceC;
      case 'A': default: return product.priceA;
    }
  }

  List<Map<String, dynamic>> _getUnitOptions(Product product) {
    final List<Map<String, dynamic>> options = [];
    final allUnits = [
      {'name': product.unit1, 'ratio': product.ratio1},
      {'name': product.unit2, 'ratio': product.ratio2},
      {'name': product.unit3, 'ratio': product.ratio3},
    ];

    final validUnits = allUnits.where((u) => (u['name'] as String).isNotEmpty && (u['ratio'] as double) > 0).toList();
    if (validUnits.isEmpty) return [];

    double maxRatio = validUnits.map((u) => u['ratio'] as double).reduce(max);

    for (var unitData in validUnits) {
      final String name = unitData['name'] as String;
      final double ratio = unitData['ratio'] as double;
      final double multiplier = maxRatio / ratio;
      options.add({'name': name, 'multiplier': multiplier});
    }
    options.sort((a, b) => (a['multiplier'] as double).compareTo(b['multiplier'] as double));
    return options;
  }

  void _addProductToCart(ProductSearchResult result) {
    final product = result.product;
    final existingItemIndex = _cartItems.indexWhere((item) =>
        item.enrichedOrder.order.productId == product.id &&
        item.selectedUnit == result.unit);

    if (existingItemIndex != -1) {
      setState(() {
        _cartItems[existingItemIndex].quantity += result.quantity;
      });
    } else {
      final double customerPrice = _getBasePriceForCustomer(product);
      final dummyOrder = SalesOrder(
        id: 'new_${product.id}',
        orderDate: DateTime.now().toIso8601String(),
        customerId: widget.customer.customerId,
        productId: product.id,
        productDescription: product.description,
        quantity: result.quantity,
        unit: result.unit,
        unitPrice: customerPrice,
        totalAmount: customerPrice * result.quantity,
        cd: '',
        invoiceNumber: 'NEW',
        accountId: '',
        dueDate: '',
        salesperson: '',
        discount: '',
      );

      final enrichedOrder = EnrichedSalesOrder(order: dummyOrder, product: product);
      final newCartItem = CartItem(
        enrichedOrder: enrichedOrder,
        quantity: result.quantity,
        isConfirmed: true,
        selectedUnit: result.unit,
      );

      setState(() => _cartItems.insert(0, newCartItem));
    }
  }

  void _proceedToCheckout() async {
    final confirmedItems = _cartItems.where((item) => item.isConfirmed && item.quantity > 0).toList();
    if (confirmedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกสินค้าอย่างน้อย 1 รายการ')),
      );
      return;
    }

    final bool? orderCreated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => ShoppingCartScreen(
          confirmedItems: confirmedItems,
          customer: widget.customer,
        ),
      ),
    );

    if (orderCreated == true && mounted) {
      setState(() {
        final confirmedIds = confirmedItems.map((item) => item.enrichedOrder.order.id).toSet();
        _cartItems.removeWhere((cartItem) => confirmedIds.contains(cartItem.enrichedOrder.order.id));
      });
    }
  }

  Future<void> _deleteSalesOrderItem(CartItem itemToDelete) async {
    if (itemToDelete.enrichedOrder.order.invoiceNumber == 'NEW') {
      setState(() {
        _cartItems.remove(itemToDelete);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ลบรายการใหม่ออกจากรถเข็นแล้ว'), backgroundColor: Colors.orange),
      );
      return;
    }

    final confirm = await _showConfirmationDialog(
      context: context,
      title: 'ยืนยันการลบ',
      content: 'คุณต้องการลบรายการสั่งจอง "${itemToDelete.enrichedOrder.order.productDescription}" ใช่หรือไม่?',
      confirmText: 'ลบ',
      confirmColor: Colors.red,
    );

    if (confirm) {
      try {
        await FirebaseFirestore.instance
            .collection('sales_orders')
            .doc(itemToDelete.enrichedOrder.order.id)
            .delete();
        
        setState(() {
          _cartItems.remove(itemToDelete);
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ลบรายการสั่งจองสำเร็จ'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('เกิดข้อผิดพลาดในการลบ: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // --- UPDATED: Function to share item with detailed PO info ---
  Future<void> _shareSalesOrderItem(CartItem itemToShare) async {
    final order = itemToShare.enrichedOrder.order;
    final product = itemToShare.enrichedOrder.product;
    if (product == null) return;

    // 1. Fetch extra info for the share text
    String purchaseDateInfo = "ไม่มีข้อมูล";
    String poInfo = "ไม่มีข้อมูล";
    String supplierIdInfo = "ไม่มีข้อมูล"; // Variable for supplier ID
    final cleanProductId = product.id.trim().replaceAll('/', '-');

    try {
      // Fetch last purchase date
      final purchaseSnapshot = await FirebaseFirestore.instance
          .collection('purchases')
          .where('รหัสสินค้า', isEqualTo: cleanProductId)
          .orderBy('วันที่', descending: true)
          .limit(1)
          .get();
      if (purchaseSnapshot.docs.isNotEmpty) {
        final dateStr = purchaseSnapshot.docs.first.data()['วันที่']?.toString() ?? '';
        if (dateStr.isNotEmpty) {
          purchaseDateInfo = DateHelper.formatDateToThai(dateStr);
        }
      }

      // Fetch last PO with new details
      final poSnapshot = await FirebaseFirestore.instance
          .collection('po')
          .where('รหัสสินค้า', isEqualTo: cleanProductId)
          .orderBy('วันที่', descending: true)
          .limit(1)
          .get();
      if (poSnapshot.docs.isNotEmpty) {
        final poData = poSnapshot.docs.first.data();
        final poNumber = poData['เลขที่ใบกำกับ']?.toString() ?? "-";
        final dateStr = poData['วันที่']?.toString() ?? '';
        final poDate = dateStr.isNotEmpty ? DateHelper.formatDateToThai(dateStr) : "-";
        
        final qtyValue = poData['จำนวน'];
        final poQuantity = (qtyValue is num) ? qtyValue.toStringAsFixed(0) : (qtyValue?.toString() ?? "-");
        final poUnit = poData['หน่วย']?.toString() ?? "";

        supplierIdInfo = poData['รหัสเจ้าหนี้']?.toString() ?? "ไม่มีข้อมูล";

        poInfo = '''
เลขที่ใบสั่งซื้อ: $poNumber | วันที่: $poDate
จำนวน: $poQuantity $poUnit''';
      }
    } catch (e) {
      debugPrint("Error fetching extra info for sharing: $e");
    }

    // 2. Format the main share text
    final thaiDateFormat = DateFormat('d MMMM yyyy', 'th_TH');
    final currentDate = thaiDateFormat.format(DateTime.now());
    final customerPhone = widget.customer.contacts.isNotEmpty ? widget.customer.contacts.first['phone'] : 'N/A';

    final shareText = '''
แจ้งทีมจัดซื้อ ($currentDate)
-------------------------
🏬 ร้าน: ${widget.customer.name}
👤 รหัสลูกค้า: ${widget.customer.customerId} | 📞 เบอร์โทร: $customerPhone
------------------
📦 สินค้า: ${order.productDescription}
🔢 รหัส: ${order.productId} | 🛍️ สั่งจำนวน: ${itemToShare.quantity.toStringAsFixed(0)} ${itemToShare.selectedUnit}
📊 สต็อกคงเหลือ: ${product.stockQuantity.toStringAsFixed(0)} ${product.unit1}
📅 ซื้อล่าสุด: $purchaseDateInfo
------------------
🚚 รหัสเจ้าหนี้: $supplierIdInfo
🧾 $poInfo
''';

    // 3. Share the text
    Share.share(shareText);
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
          title: Text('รับออเดอร์: ${widget.customer.name}', style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 80),
          children: [
            _buildContactsCard(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.search),
                label: const Text('ค้นหาและเพิ่มสินค้า'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  backgroundColor: Colors.white,
                  foregroundColor: Theme.of(context).primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (context) => ProductSearchDialog(
                      customerPriceLevel: widget.customer.p,
                      onProductAdded: (result) {
                        _addProductToCart(result);
                      },
                    ),
                  );
                },
              ),
            ),
            _buildCartSection(),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _proceedToCheckout,
          label: const Text('ไปที่รถเข็น'),
          icon: const Icon(Icons.shopping_cart_checkout),
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      ),
    );
  }

  Widget _buildContactsCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: StreamBuilder<DocumentSnapshot>(
          stream: _customerStream,
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final updatedCustomer = Customer.fromFirestore(snapshot.data!);
            final contacts = updatedCustomer.contacts;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text('เบอร์ติดต่อ (ระดับราคา: ${widget.customer.p})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                const Divider(),
                if (contacts.isEmpty)
                  const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 16.0), child: Text('ไม่มีเบอร์ติดต่อ')))
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: contacts.length,
                    itemBuilder: (context, index) {
                      return _buildContactItemCard(updatedCustomer, contacts, index);
                    },
                  ),
                const SizedBox(height: 8),
                Center(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('เพิ่มเบอร์ติดต่อ'),
                    onPressed: () => _showContactForm(currentCustomer: updatedCustomer),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildContactItemCard(Customer customer, List<Map<String, String>> contacts, int index) {
    final contact = contacts[index];
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.grey.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.person_pin, color: Theme.of(context).primaryColor, size: 28),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(contact['name'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(contact['phone'] ?? 'N/A', style: TextStyle(color: Colors.grey.shade700, fontSize: 15)),
                  ],
                ),
              ],
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('แก้ไข'),
                  onPressed: () => _showContactForm(currentCustomer: customer, contact: contact, index: index),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('ลบ'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                  onPressed: () async {
                    final confirm = await _showConfirmationDialog(
                      context: context,
                      title: 'ยืนยันการลบ',
                      content: 'คุณแน่ใจหรือไม่ว่าต้องการลบผู้ติดต่อ "${contact['name']}"?',
                      confirmText: 'ลบ',
                      confirmColor: Colors.red.shade700,
                    );
                    if (confirm) {
                      final currentContacts = List<Map<String, dynamic>>.from(contacts.map((c)=>Map<String,dynamic>.from(c)));
                      currentContacts.removeAt(index);
                      await FirebaseFirestore.instance.collection('customers').doc(customer.id).update({'contacts': currentContacts});
                    }
                  },
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.call_outlined, size: 18),
                  label: const Text('โทร'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade600, foregroundColor: Colors.white),
                  onPressed: () => LauncherHelper.makeAndLogPhoneCall(
                    context: context,
                    phoneNumber: contact['phone'] ?? '',
                    customer: customer,
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }


  Widget _buildCartSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text('รายการสินค้า', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const Divider(),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_cartItems.isEmpty)
              const Center(child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('ไม่มีรายการสั่งจอง\nกดค้นหาเพื่อเพิ่มสินค้าใหม่', textAlign: TextAlign.center),
              ))
            else
              ListView.separated(
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                itemCount: _cartItems.length,
                itemBuilder: (context, index) => _buildCartItemWidget(_cartItems[index]),
                separatorBuilder: (context, index) => const Divider(height: 1),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailInfoRow({
    required IconData icon,
    required Color iconColor,
    required List<TextSpan> textSpans,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                children: textSpans,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartItemWidget(CartItem item) {
    final order = item.enrichedOrder.order;
    final product = item.enrichedOrder.product;

    if (product == null) {
      return ListTile(
        leading: const Icon(Icons.error_outline, color: Colors.red),
        title: Text(order.productDescription),
        subtitle: const Text('ไม่พบข้อมูลสินค้า'),
      );
    }

    final unitOptions = _getUnitOptions(product);
    final selectedUnitOption = unitOptions.firstWhere(
        (opt) => opt['name'] == item.selectedUnit,
        orElse: () => unitOptions.isNotEmpty ? unitOptions.first : {'name': item.selectedUnit, 'multiplier': 1.0});

    final basePrice = _getBasePriceForCustomer(product);
    
    final currentUnitPrice = basePrice * (selectedUnitOption['multiplier'] as double);
    final totalItemPrice = currentUnitPrice * item.quantity;
    final bool isLowStock = item.quantity > product.stockQuantity;
    final bool isNewItem = order.invoiceNumber == 'NEW';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Checkbox(
                value: item.isConfirmed,
                onChanged: (bool? value) => setState(() => item.isConfirmed = value ?? false),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, color: Colors.red.shade700),
                onPressed: () => _deleteSalesOrderItem(item),
                tooltip: 'ลบรายการสั่งจองนี้',
              ),
              IconButton(
                icon: Icon(Icons.share_outlined, color: Colors.blue.shade700),
                onPressed: () => _shareSalesOrderItem(item),
                tooltip: 'แชร์ข้อมูลสินค้า',
              ),
            ],
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8.0,
                  runSpacing: 4.0,
                  children: [
                    Text(order.productDescription, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    if (isNewItem)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'ออเดอร์ใหม่',
                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
                
                Container(
                  margin: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                  padding: const EdgeInsets.all(10.0),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEA), // Beige color
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(color: const Color(0xFFF5E6B6))
                  ),
                  child: Column(
                    children: [
                      _buildDetailInfoRow(
                        icon: Icons.qr_code_2,
                        iconColor: Colors.grey.shade700,
                        textSpans: [
                          TextSpan(text: 'รหัส : ', style: TextStyle(color: Colors.grey.shade800)),
                          TextSpan(text: order.productId, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                        ],
                      ),
                      if (!isNewItem)
                        _buildDetailInfoRow(
                          icon: Icons.article_outlined,
                          iconColor: Colors.blue.shade700,
                          textSpans: [
                            TextSpan(text: 'SO : ', style: TextStyle(color: Colors.grey.shade800)),
                            TextSpan(
                              text: '${order.invoiceNumber} (${DateHelper.formatDateToThai(order.orderDate)})',
                              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade700),
                            ),
                          ],
                        ),
                      const Divider(height: 12, thickness: 0.5),
                      _buildDetailInfoRow(
                        icon: Icons.sell_outlined,
                        iconColor: Colors.grey.shade700,
                        textSpans: [
                          TextSpan(text: 'ราคา : ', style: TextStyle(color: Colors.grey.shade800)),
                          TextSpan(
                            text: '${_currencyFormat.format(currentUnitPrice)} / ${item.selectedUnit}',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                          ),
                        ],
                      ),
                      _buildDetailInfoRow(
                        icon: Icons.inventory_2_outlined,
                        iconColor: isLowStock ? Colors.red.shade700 : Colors.grey.shade700,
                        textSpans: [
                          TextSpan(text: 'คงเหลือ : ', style: TextStyle(color: Colors.grey.shade800)),
                          TextSpan(
                            text: '${product.stockQuantity.toStringAsFixed(0)} ${product.unit1}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isLowStock ? Colors.red.shade700 : Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            iconSize: 22,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: item.quantity > 1 ? () => setState(() => item.quantity--) : null,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12.0),
                            child: Text(item.quantity.toStringAsFixed(0), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          ),
                          IconButton(
                            iconSize: 22,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () => setState(() => item.quantity++),
                          ),
                        ],
                      ),

                      if (unitOptions.length > 1)
                        DropdownButton<String>(
                          value: item.selectedUnit,
                          items: unitOptions.map((option) {
                            return DropdownMenuItem<String>(
                              value: option['name'],
                              child: Text(option['name'], style: const TextStyle(fontSize: 14)),
                            );
                          }).toList(),
                          onChanged: (String? newValue) {
                            if (newValue != null) {
                              setState(() {
                                item.selectedUnit = newValue;
                              });
                            }
                          },
                          isDense: true,
                          underline: Container(),
                        )
                      else 
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Text(item.selectedUnit, style: const TextStyle(fontSize: 14)),
                        ),

                      Flexible(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 8.0, right: 4.0),
                              child: Text(
                                '฿${_currencyFormat.format(totalItemPrice)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _ProductExtraInfo(
                  productId: order.productId,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductExtraInfo extends StatefulWidget {
  final String productId;

  const _ProductExtraInfo({
    required this.productId,
  });

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
      // Handle errors silently in release mode
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
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
        color: const Color(0xFFFFFBEA), // Beige color
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: const Color(0xFFF5E6B6)) // Matching border color
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
                decoration: TextDecoration.none, // Explicitly remove underlines
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
