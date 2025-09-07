// lib/screens/key_order_screen.dart

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:salewang/models/customer.dart';
import 'package:salewang/models/product.dart';
import 'package:salewang/utils/date_helper.dart';
import 'package:salewang/widgets/product_search_dialog.dart';
import 'package:salewang/screens/key_order_summary_screen.dart'; // Import the new summary screen

// --- NEW: Singleton Service to hold the order state ---
class OrderStateService {
  Customer? selectedCustomer;
  List<KeyOrderItem> orderItems = [];
  String soNumber = '';
  TextEditingController noteController = TextEditingController();

  static final OrderStateService _instance = OrderStateService._internal();

  factory OrderStateService() {
    return _instance;
  }

  OrderStateService._internal();

  void generateSoNumber() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    soNumber = 'APP-KEY-$timestamp';
  }

  void clearState() {
    selectedCustomer = null;
    orderItems.clear();
    noteController.clear();
    generateSoNumber();
  }
}


// Helper class to manage the state of each item in the order list
class KeyOrderItem {
  Product product;
  double quantity;
  String selectedUnit;
  double calculatedPrice;

  KeyOrderItem({
    required this.product,
    required this.quantity,
    required this.selectedUnit,
    required this.calculatedPrice,
  });
}

class KeyOrderScreen extends StatefulWidget {
  const KeyOrderScreen({super.key});

  @override
  State<KeyOrderScreen> createState() => _KeyOrderScreenState();
}

class _KeyOrderScreenState extends State<KeyOrderScreen> {
  // Use the singleton to manage state
  final OrderStateService _orderState = OrderStateService();
  
  final _customerSearchController = TextEditingController();
  final NumberFormat _currencyFormat = NumberFormat("#,##0.00", "en_US");
  Timer? _debounce;

  List<Customer> _customerSearchResults = [];
  bool _isCustomerLoading = false;

  @override
  void initState() {
    super.initState();
    if (_orderState.soNumber.isEmpty) {
      _orderState.generateSoNumber();
    }
    _customerSearchController.addListener(_onCustomerSearchChanged);
  }

  @override
  void dispose() {
    _customerSearchController.removeListener(_onCustomerSearchChanged);
    _customerSearchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }
  
  void _clearOrderState() {
    setState(() {
      _orderState.clearState();
      _customerSearchController.clear();
    });
  }

  Future<bool> _showConfirmationDialog(String title, String content) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('ยืนยัน')),
        ],
      ),
    );
    return result ?? false;
  }

  void _onCustomerSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _searchCustomer();
    });
  }

  Future<void> _searchCustomer() async {
    final query = _customerSearchController.text.trim();
    
    if (_orderState.orderItems.isNotEmpty) {
      final confirm = await _showConfirmationDialog(
        'ยืนยันการกระทำ',
        'คุณมีรายการสินค้าที่ยังไม่ได้บันทึก การค้นหาลูกค้าใหม่จะลบรายการปัจจุบันทิ้งทั้งหมด ยืนยันที่จะดำเนินการต่อหรือไม่?',
      );
      if (!confirm) {
        return;
      }
      _clearOrderState();
      _customerSearchController.text = query;
    }

    if (query.length < 2) {
      setState(() => _customerSearchResults = []);
      return;
    }

    setState(() => _isCustomerLoading = true);
    try {
      final idQuery = FirebaseFirestore.instance.collection('customers').where('รหัสลูกค้า', isGreaterThanOrEqualTo: query).where('รหัสลูกค้า', isLessThanOrEqualTo: '$query\uf8ff').limit(5);
      final nameQuery = FirebaseFirestore.instance.collection('customers').where('ชื่อลูกค้า', isGreaterThanOrEqualTo: query).where('ชื่อลูกค้า', isLessThanOrEqualTo: '$query\uf8ff').limit(5);

      final results = await Future.wait([idQuery.get(), nameQuery.get()]);
      final allDocs = [...results[0].docs, ...results[1].docs];
      
      final uniqueIds = <String>{};
      final uniqueCustomers = allDocs.where((doc) => uniqueIds.add(doc.id)).map((doc) => Customer.fromFirestore(doc)).toList();

      setState(() {
        _customerSearchResults = uniqueCustomers;
      });
    } catch (e) {
      _showErrorSnackbar('เกิดข้อผิดพลาดในการค้นหา: $e');
    } finally {
      setState(() => _isCustomerLoading = false);
    }
  }

  void _selectCustomer(Customer customer) {
    setState(() {
      _orderState.selectedCustomer = customer;
      _customerSearchResults = [];
      _customerSearchController.clear();
      FocusScope.of(context).unfocus();
    });
  }

  void _addProductToOrder(ProductSearchResult result) {
    final product = result.product;
    if (_orderState.selectedCustomer == null) return;

    final unitOptions = _getUnitOptions(product);
    final selectedUnit = result.unit;
    final selectedUnitData = unitOptions.firstWhere((u) => u['name'] == selectedUnit, orElse: () => unitOptions.first);

    double basePrice = _getBasePriceForCustomer(product, _orderState.selectedCustomer!.p);
    double calculatedPrice = basePrice * (selectedUnitData['multiplier'] as double);

    final newItem = KeyOrderItem(
      product: product,
      quantity: result.quantity,
      selectedUnit: selectedUnit,
      calculatedPrice: calculatedPrice,
    );

    setState(() {
      _orderState.orderItems.add(newItem);
    });
  }

  void _onItemChanged() {
    setState(() {});
  }

  void _removeItem(int index) {
    setState(() {
      _orderState.orderItems.removeAt(index);
    });
  }

  // --- UPDATED: This function now navigates to the summary screen ---
  void _proceedToSummary() {
    if (_orderState.selectedCustomer == null) {
      _showErrorSnackbar('กรุณาเลือกลูกค้าก่อน');
      return;
    }
    if (_orderState.orderItems.isEmpty) {
      _showErrorSnackbar('กรุณาเพิ่มสินค้าอย่างน้อย 1 รายการ');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => KeyOrderSummaryScreen(
          customer: _orderState.selectedCustomer!,
          orderItems: _orderState.orderItems,
          soNumber: _orderState.soNumber,
          note: _orderState.noteController.text,
        ),
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  double _getBasePriceForCustomer(Product product, String priceLevel) {
    switch (priceLevel.toUpperCase()) {
      case 'B': return product.priceB;
      case 'C': return product.priceC;
      default: return product.priceA;
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

  @override
  Widget build(BuildContext context) {
    final totalAmount = _orderState.orderItems.fold(0.0, (sum, item) => sum + (item.calculatedPrice * item.quantity));
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
          title: const Text('คีย์ออเดอร์', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.brush_outlined),
              onPressed: () async {
                final confirm = await _showConfirmationDialog('ล้างข้อมูล', 'คุณต้องการล้างข้อมูลในหน้านี้ทั้งหมดใช่หรือไม่?');
                if(confirm) _clearOrderState();
              },
              tooltip: 'ล้างหน้าต่าง',
            ),
          ],
        ),
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(12.0),
                  children: [
                    _buildHeaderCard(),
                    const SizedBox(height: 12),
                    _buildCustomerCard(),
                    const SizedBox(height: 12),
                    _buildOrderItemsCard(),
                    const SizedBox(height: 12),
                    _buildSummaryCard(totalAmount, amountBeforeVat, vatAmount),
                  ],
                ),
              ),
              _buildCreateOrderButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    final thaiDateFormat = DateFormat('d MMMM yyyy', 'th_TH');
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                const Text('วันที่:', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(thaiDateFormat.format(DateTime.now())),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.receipt_long, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                const Text('เลขที่ใบสั่งขาย:', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(_orderState.soNumber, style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('1. ค้นหาลูกค้า', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: _customerSearchController,
              decoration: InputDecoration(
                hintText: 'พิมพ์รหัส หรือ ชื่อลูกค้า...',
                border: const OutlineInputBorder(),
                isDense: true,
                prefixIcon: const Icon(Icons.person_search),
                suffixIcon: _customerSearchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _customerSearchController.clear();
                          setState(() => _customerSearchResults = []);
                        },
                      )
                    : null,
              ),
            ),
            if (_isCustomerLoading)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_customerSearchResults.isNotEmpty)
              _buildCustomerSearchResults(),
            if (_orderState.selectedCustomer != null)
              _buildSelectedCustomerDetails(),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerSearchResults() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      child: Card(
        elevation: 4,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: _customerSearchResults.length,
          itemBuilder: (context, index) {
            final customer = _customerSearchResults[index];
            return ListTile(
              title: Text(customer.name),
              subtitle: Text('รหัส: ${customer.customerId}'),
              onTap: () => _selectCustomer(customer),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSelectedCustomerDetails() {
    if (_orderState.selectedCustomer == null) return const SizedBox.shrink();
    final customer = _orderState.selectedCustomer!;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Table(
        columnWidths: const {
          0: IntrinsicColumnWidth(),
          1: FlexColumnWidth(),
        },
        children: [
          _buildDetailTableRow('นามลูกค้า:', customer.name, isHeader: true),
          _buildDetailTableRow('ที่อยู่:', '${customer.address1} ${customer.address2}'),
          _buildDetailTableRow('ติดต่อ:', customer.contacts.isNotEmpty ? customer.contacts.first['phone'] ?? '-' : '-'),
          _buildDetailTableRow('เงื่อนไข:', '${customer.paymentTerms} วัน'),
          _buildDetailTableRow('วงเงิน:', _currencyFormat.format(double.tryParse(customer.creditLimit) ?? 0)),
          _buildDetailTableRow('พนักงานขาย:', customer.salesperson),
        ],
      ),
    );
  }

  TableRow _buildDetailTableRow(String label, String value, {bool isHeader = false}) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
          child: Text(
            value,
            style: isHeader
                ? TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).primaryColor)
                : const TextStyle(),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderItemsCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('2. รายการสินค้า', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('เพิ่มสินค้า'),
                  onPressed: _orderState.selectedCustomer == null
                      ? null
                      : () {
                          showDialog(
                            context: context,
                            builder: (_) => ProductSearchDialog(
                              onProductAdded: _addProductToOrder,
                              customerPriceLevel: _orderState.selectedCustomer!.p,
                            ),
                          );
                        },
                ),
              ],
            ),
            const Divider(),
            if (_orderState.orderItems.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24.0),
                child: Text('ยังไม่มีรายการสินค้า', style: TextStyle(color: Colors.grey)),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _orderState.orderItems.length,
                itemBuilder: (context, index) {
                  return OrderItemCard(
                    key: ValueKey(_orderState.orderItems[index].product.id + _orderState.orderItems[index].selectedUnit),
                    item: _orderState.orderItems[index],
                    customerPriceLevel: _orderState.selectedCustomer?.p ?? 'A',
                    onChanged: _onItemChanged,
                    onRemove: () => _removeItem(index),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSummaryCard(double totalAmount, double amountBeforeVat, double vatAmount) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('3. สรุปและหมายเหตุ', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: _orderState.noteController,
              decoration: const InputDecoration(
                hintText: 'เพิ่มหมายเหตุ (ถ้ามี)...',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            _buildSummaryRow('ยอดก่อนภาษี:', '฿${_currencyFormat.format(amountBeforeVat)}'),
            _buildSummaryRow('ภาษีมูลค่าเพิ่ม (7%):', '฿${_currencyFormat.format(vatAmount)}'),
            const Divider(),
            _buildSummaryRow(
              'ยอดรวมทั้งสิ้น:',
              '฿${_currencyFormat.format(totalAmount)}',
              isTotal: true,
            ),
          ],
        ),
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

  Widget _buildCreateOrderButton() {
    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, spreadRadius: 2)],
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          icon: const Icon(Icons.arrow_circle_right_outlined),
          label: const Text('ดำเนินการต่อ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          onPressed: _proceedToSummary, // UPDATED ACTION
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );
  }
}

// --- Stateful Widget for each Order Item Card ---
class OrderItemCard extends StatefulWidget {
  final KeyOrderItem item;
  final String customerPriceLevel;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const OrderItemCard({
    super.key,
    required this.item,
    required this.customerPriceLevel,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  State<OrderItemCard> createState() => _OrderItemCardState();
}

class _OrderItemCardState extends State<OrderItemCard> {
  late List<Map<String, dynamic>> _unitOptions;

  @override
  void initState() {
    super.initState();
    _unitOptions = _getUnitOptions(widget.item.product);
  }

  List<Map<String, dynamic>> _getUnitOptions(Product product) {
    final List<Map<String, dynamic>> options = [];
    final allUnits = [
      {'name': product.unit1, 'ratio': product.ratio1},
      {'name': product.unit2, 'ratio': product.ratio2},
      {'name': product.unit3, 'ratio': product.ratio3},
    ];
    final validUnits = allUnits.where((u) => (u['name'] as String).isNotEmpty && (u['ratio'] as double) > 0).toList();
    if (validUnits.isEmpty) return [{'name': 'หน่วย', 'multiplier': 1.0}];
    double maxRatio = validUnits.map((u) => u['ratio'] as double).reduce(max);
    for (var unitData in validUnits) {
      options.add({
        'name': unitData['name'] as String,
        'multiplier': maxRatio / (unitData['ratio'] as double)
      });
    }
    options.sort((a, b) => (a['multiplier'] as double).compareTo(b['multiplier'] as double));
    return options;
  }

  double _getBasePriceForCustomer(Product product, String priceLevel) {
    switch (priceLevel.toUpperCase()) {
      case 'B': return product.priceB;
      case 'C': return product.priceC;
      default: return product.priceA;
    }
  }

  void _updatePrice() {
    final selectedUnitData = _unitOptions.firstWhere((u) => u['name'] == widget.item.selectedUnit);
    double basePrice = _getBasePriceForCustomer(widget.item.product, widget.customerPriceLevel);
    widget.item.calculatedPrice = basePrice * (selectedUnitData['multiplier'] as double);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final itemTotal = widget.item.quantity * widget.item.calculatedPrice;
    final currencyFormat = NumberFormat("#,##0.00", "en_US");

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(widget.item.product.description, style: const TextStyle(fontWeight: FontWeight.bold))),
                IconButton(
                  icon: Icon(Icons.delete_outline, color: Colors.red.shade600),
                  onPressed: widget.onRemove,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _ProductExtraInfo(productId: widget.item.product.id),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Quantity Controls
                Row(
                  children: [
                    IconButton.outlined(
                      icon: const Icon(Icons.remove),
                      onPressed: () {
                        if (widget.item.quantity > 1) {
                          setState(() => widget.item.quantity--);
                          widget.onChanged();
                        }
                      },
                      iconSize: 18,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text(widget.item.quantity.toStringAsFixed(0), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    IconButton.filled(
                      icon: const Icon(Icons.add),
                      onPressed: () {
                        setState(() => widget.item.quantity++);
                        widget.onChanged();
                      },
                      iconSize: 18,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ],
                ),
                // Unit Selector
                if (_unitOptions.length > 1)
                  DropdownButton<String>(
                    value: widget.item.selectedUnit,
                    items: _unitOptions.map((option) {
                      return DropdownMenuItem<String>(
                        value: option['name'],
                        child: Text(option['name']),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        setState(() {
                          widget.item.selectedUnit = newValue;
                          _updatePrice();
                        });
                      }
                    },
                    underline: Container(),
                  )
                else
                  Text(widget.item.selectedUnit),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'รวม: ${currencyFormat.format(itemTotal)} บาท',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Reusable Widget for Extra Product Info ---
class _ProductExtraInfo extends StatefulWidget {
  final String productId;
  const _ProductExtraInfo({required this.productId});

  @override
  State<_ProductExtraInfo> createState() => _ProductExtraInfoState();
}

class _ProductExtraInfoState extends State<_ProductExtraInfo> {
  String? purchaseDate;
  String? poInfo;
  String? stockInfo;

  @override
  void initState() {
    super.initState();
    _fetchExtraInfo();
  }

  Future<void> _fetchExtraInfo() async {
    final cleanProductId = widget.productId.trim().replaceAll('/', '-');
    if (cleanProductId.isEmpty) return;

    try {
      // Fetch Product Stock
      final productDoc = await FirebaseFirestore.instance.collection('products').doc(cleanProductId).get();
      if (productDoc.exists) {
        final product = Product.fromFirestore(productDoc);
        stockInfo = '${product.stockQuantity.toStringAsFixed(0)} ${product.unit1}';
      }

      // Fetch Last Purchase
      final purchaseSnapshot = await FirebaseFirestore.instance.collection('purchases').where('รหัสสินค้า', isEqualTo: cleanProductId).orderBy('วันที่', descending: true).limit(1).get();
      if (purchaseSnapshot.docs.isNotEmpty) {
        final dateStr = purchaseSnapshot.docs.first.data()['วันที่']?.toString() ?? '';
        if (dateStr.isNotEmpty) purchaseDate = DateHelper.formatDateToThai(dateStr);
      }

      // Fetch Last PO
      final poSnapshot = await FirebaseFirestore.instance.collection('po').where('รหัสสินค้า', isEqualTo: cleanProductId).orderBy('วันที่', descending: true).limit(1).get();
      if (poSnapshot.docs.isNotEmpty) {
        final poData = poSnapshot.docs.first.data();
        final poNumber = poData['เลขที่ใบกำกับ']?.toString() ?? "-";
        final dateStr = poData['วันที่']?.toString() ?? '';
        final poDate = dateStr.isNotEmpty ? DateHelper.formatDateToThai(dateStr) : "-";
        poInfo = '$poNumber | $poDate';
      }
    } catch (e) {
      debugPrint("Error fetching extra info: $e");
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _buildInfoRow(Icons.inventory_2_outlined, 'รหัส: ${widget.productId} | สต็อก: ${stockInfo ?? '...'}'),
          _buildInfoRow(Icons.history_outlined, 'ซื้อล่าสุด: ${purchaseDate ?? '...'}'),
          _buildInfoRow(Icons.receipt_long_outlined, 'ใบสั่งซื้อ: ${poInfo ?? '...'}'),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
        ],
      ),
    );
  }
}
