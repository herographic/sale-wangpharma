// lib/screens/price_negotiation_screen.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:salewang/models/product.dart';
import 'package:salewang/models/customer.dart';
import 'package:salewang/utils/date_helper.dart';

// Main Screen Widget with Tabs
class PriceNegotiationScreen extends StatefulWidget {
  const PriceNegotiationScreen({super.key});

  @override
  State<PriceNegotiationScreen> createState() => _PriceNegotiationScreenState();
}

class _PriceNegotiationScreenState extends State<PriceNegotiationScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
          title: const Text('ต่อรองราคา', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          bottom: TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white.withOpacity(0.7),
            indicatorColor: Colors.yellowAccent,
            tabs: const [
              Tab(text: 'ค้นหาและต่อรอง'),
              Tab(text: 'รายการอนุมัติ'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: const [
            NegotiationSearchTab(),
            NegotiationHistoryTab(),
          ],
        ),
      ),
    );
  }
}

// Tab 1: Search and Negotiate
class NegotiationSearchTab extends StatefulWidget {
  const NegotiationSearchTab({super.key});

  @override
  State<NegotiationSearchTab> createState() => _NegotiationSearchTabState();
}

class _NegotiationSearchTabState extends State<NegotiationSearchTab> {
  final _customerSearchController = TextEditingController();
  final _productSearchController = TextEditingController();
  
  Customer? _selectedCustomer;
  
  bool _isCustomerLoading = false;
  bool _isProductLoading = false;

  final List<_NegotiationItem> _negotiationItems = [];

  Future<void> _searchCustomer() async {
    final customerId = _customerSearchController.text.trim();
    if (customerId.isEmpty) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    FocusScope.of(context).unfocus();
    setState(() {
      _isCustomerLoading = true;
      _selectedCustomer = null;
      _negotiationItems.clear();
    });
    try {
      final sanitizedDocId = customerId.replaceAll('/', '-');
      final doc = await FirebaseFirestore.instance.collection('customers').doc(sanitizedDocId).get();
      
      if (mounted && doc.exists) {
        setState(() => _selectedCustomer = Customer.fromFirestore(doc));
      } else {
        scaffoldMessenger.showSnackBar(SnackBar(content: Text('ไม่พบรหัสลูกค้า "$customerId"')));
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
    } finally {
      if(mounted) setState(() => _isCustomerLoading = false);
    }
  }

  Future<void> _searchProductAndAddToList() async {
    final productId = _productSearchController.text.trim();
    if (productId.isEmpty) return;
    
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    FocusScope.of(context).unfocus();
    setState(() => _isProductLoading = true);
    try {
      final sanitizedDocId = productId.replaceAll('/', '-');
      final doc = await FirebaseFirestore.instance.collection('products').doc(sanitizedDocId).get();
      
      if (mounted && doc.exists) {
        final newProduct = Product.fromFirestore(doc);
        if (!_negotiationItems.any((item) => item.product.id == newProduct.id)) {
          setState(() {
            _negotiationItems.add(_NegotiationItem(product: newProduct));
            _productSearchController.clear();
          });
        } else {
           scaffoldMessenger.showSnackBar(const SnackBar(content: Text('สินค้านี้อยู่ในรายการแล้ว')));
        }
      } else {
        scaffoldMessenger.showSnackBar(SnackBar(content: Text('ไม่พบรหัสสินค้า "$productId"')));
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
    } finally {
      if(mounted) setState(() => _isProductLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("1. ค้นหาลูกค้า", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _customerSearchController,
                          decoration: const InputDecoration(labelText: 'รหัสลูกค้า', border: OutlineInputBorder()),
                          onSubmitted: (_) => _searchCustomer(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        icon: const Icon(Icons.search),
                        onPressed: _searchCustomer,
                      ),
                    ],
                  ),
                  if (_isCustomerLoading) const Padding(padding: EdgeInsets.all(8.0), child: Center(child: CircularProgressIndicator())),
                  if (_selectedCustomer != null)
                    _buildSelectedCustomerInfo(_selectedCustomer!),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text("2. ค้นหาสินค้าเพื่อต่อรอง", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _productSearchController,
                          decoration: InputDecoration(
                            labelText: 'รหัสสินค้า',
                            border: const OutlineInputBorder(),
                            enabled: _selectedCustomer != null,
                          ),
                          onSubmitted: (_) => _searchProductAndAddToList(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        icon: const Icon(Icons.add),
                        onPressed: _selectedCustomer != null ? _searchProductAndAddToList : null,
                      ),
                    ],
                  ),
                  if (_isProductLoading) const Padding(padding: EdgeInsets.all(8.0), child: Center(child: CircularProgressIndicator())),
                  const Divider(height: 24),
                  if (_negotiationItems.isNotEmpty)
                    ..._negotiationItems.map((item) => _NegotiationItemForm(
                      key: ValueKey(item.product.id),
                      item: item,
                      customer: _selectedCustomer!,
                    )),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildSelectedCustomerInfo(Customer customer) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(customer.name, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('ระดับราคา: ${customer.p}'),
        ],
      ),
    );
  }
}

// Helper classes for managing negotiation item state
class NegotiationDeal {
  final TextEditingController quantityController = TextEditingController();
  final TextEditingController priceController = TextEditingController();
  String? selectedUnit;
}

class _NegotiationItem {
  final Product product;
  final List<NegotiationDeal> deals = [NegotiationDeal()];
  final TextEditingController sourceController = TextEditingController();
  XFile? imageFile;
  Uint8List? imageBytes;
  _NegotiationItem({required this.product});
}

// Form widget for a single negotiation item
class _NegotiationItemForm extends StatefulWidget {
  final _NegotiationItem item;
  final Customer customer;
  const _NegotiationItemForm({super.key, required this.item, required this.customer});

  @override
  State<_NegotiationItemForm> createState() => _NegotiationItemFormState();
}

class _NegotiationItemFormState extends State<_NegotiationItemForm> {
  bool _isSaving = false;
  final ImagePicker _picker = ImagePicker();
  List<String> _unitOptions = [];

  @override
  void initState() {
    super.initState();
    _unitOptions = _getUnitOptions(widget.item.product);
    if (_unitOptions.isNotEmpty) {
      widget.item.deals.first.selectedUnit = _unitOptions.first;
    }
  }

  List<String> _getUnitOptions(Product product) {
    return [product.unit1, product.unit2, product.unit3]
        .where((u) => u.isNotEmpty)
        .toList();
  }
  
  double _getCustomerPrice() {
    switch (widget.customer.p.toUpperCase()) {
      case 'B': return widget.item.product.priceB;
      case 'C': return widget.item.product.priceC;
      default: return widget.item.product.priceA;
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(source: source, imageQuality: 70, maxWidth: 1024);
    if (pickedFile != null) {
      widget.item.imageFile = pickedFile;
      if (kIsWeb) {
        widget.item.imageBytes = await pickedFile.readAsBytes();
      }
      if (mounted) setState(() {});
    }
  }

  Future<void> _saveNegotiation() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    if (widget.item.deals.every((d) => d.priceController.text.trim().isEmpty)) {
      scaffoldMessenger.showSnackBar(const SnackBar(content: Text('กรุณากรอกราคาที่ต้องการต่อรองอย่างน้อย 1 เงื่อนไข')));
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isSaving = true);
    String? imageUrl;

    try {
      if (widget.item.imageFile != null) {
        final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
        final ref = FirebaseStorage.instance.ref('negotiation_proofs').child(widget.item.product.id).child(fileName);
        if (kIsWeb) {
          await ref.putData(widget.item.imageBytes!, SettableMetadata(contentType: 'image/jpeg'));
        } else {
          await ref.putFile(File(widget.item.imageFile!.path));
        }
        imageUrl = await ref.getDownloadURL();
      }

      final conditions = widget.item.deals
          .where((d) => d.priceController.text.isNotEmpty)
          .map((d) => {
                'quantity': int.tryParse(d.quantityController.text) ?? 1,
                'unit': d.selectedUnit,
                'price': double.tryParse(d.priceController.text) ?? 0.0,
              })
          .toList();

      await FirebaseFirestore.instance
          .collection('products')
          .doc(widget.item.product.id)
          .collection('negotiations')
          .add({
        'productName': widget.item.product.description,
        'productId': widget.item.product.id,
        'priceA': widget.item.product.priceA,
        'priceB': widget.item.product.priceB,
        'priceC': widget.item.product.priceC,
        'conditions': conditions,
        'customerIdentifier': widget.customer.name,
        'customerId': widget.customer.customerId,
        'customerPriceLevel': widget.customer.p,
        'source': widget.item.sourceController.text.trim(),
        'recordedBy': user.displayName ?? user.email,
        'userId': user.uid,
        'timestamp': FieldValue.serverTimestamp(),
        'imageUrl': imageUrl,
        'status': 'pending',
      });
      
      scaffoldMessenger.showSnackBar(const SnackBar(content: Text('บันทึกข้อมูลสำเร็จ'), backgroundColor: Colors.green));
      
      if (mounted) {
        setState(() {
          widget.item.deals.clear();
          widget.item.deals.add(NegotiationDeal());
           if (_unitOptions.isNotEmpty) {
            widget.item.deals.first.selectedUnit = _unitOptions.first;
          }
          widget.item.sourceController.clear();
          widget.item.imageFile = null;
          widget.item.imageBytes = null;
        });
      }

    } catch (e) {
       scaffoldMessenger.showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e'), backgroundColor: Colors.red));
    } finally {
       if(mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat("#,##0.00");
    final customerPrice = _getCustomerPrice();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.item.product.description, style: const TextStyle(fontWeight: FontWeight.bold)),
          RichText(
            text: TextSpan(
              style: DefaultTextStyle.of(context).style,
              children: [
                const TextSpan(text: 'ราคาปกติ A/B/C: '),
                TextSpan(text: '${currencyFormat.format(widget.item.product.priceA)} / '),
                TextSpan(text: '${currencyFormat.format(widget.item.product.priceB)} / '),
                TextSpan(text: '${currencyFormat.format(widget.item.product.priceC)} '),
                TextSpan(
                  text: '(ราคาลูกค้า: ${currencyFormat.format(customerPrice)})',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor)
                ),
              ]
            ),
          ),
          const Divider(height: 20),

          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.item.deals.length,
            itemBuilder: (context, index) {
              return _buildDealRow(widget.item.deals[index], index);
            },
          ),
          
          TextButton.icon(
            icon: const Icon(Icons.add_circle_outline, size: 18),
            label: const Text('เพิ่มเงื่อนไขต่อรอง'),
            onPressed: () {
              setState(() {
                widget.item.deals.add(NegotiationDeal());
                if (_unitOptions.isNotEmpty) {
                  widget.item.deals.last.selectedUnit = _unitOptions.first;
                }
              });
            },
          ),

          const SizedBox(height: 12),
          TextFormField(
            controller: widget.item.sourceController,
            decoration: const InputDecoration(labelText: 'จากแหล่งใด (เช่น ยี่ปั้ว/ร้านค้า)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('แนปรูป'),
                onPressed: () => _pickImage(ImageSource.gallery),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('ถ่ายรูป'),
                onPressed: () => _pickImage(ImageSource.camera),
              ),
            ],
          ),
          if (widget.item.imageFile != null)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: kIsWeb 
                ? Image.memory(widget.item.imageBytes!, height: 100) 
                : Image.file(File(widget.item.imageFile!.path), height: 100),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isSaving ? null : _saveNegotiation,
              child: _isSaving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2,)) : const Text('บันทึกรายการนี้'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDealRow(NegotiationDeal deal, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: deal.quantityController,
              decoration: const InputDecoration(labelText: 'จำนวน', border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String>(
              value: deal.selectedUnit,
              items: _unitOptions.map((String unit) {
                return DropdownMenuItem<String>(value: unit, child: Text(unit));
              }).toList(),
              onChanged: (String? newValue) {
                setState(() {
                  deal.selectedUnit = newValue;
                });
              },
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: TextFormField(
              controller: deal.priceController,
              decoration: const InputDecoration(labelText: 'ราคาต่อรอง', border: OutlineInputBorder()),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ),
          if (index > 0)
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
              onPressed: () {
                setState(() {
                  widget.item.deals.removeAt(index);
                });
              },
            ),
        ],
      ),
    );
  }
}

// Tab 2: Negotiation History
class NegotiationHistoryTab extends StatelessWidget {
  const NegotiationHistoryTab({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collectionGroup('negotiations')
          .orderBy('timestamp', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }
        if (snapshot.hasError) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text("Error: ${snapshot.error}\n\nโปรดตรวจสอบว่าได้สร้าง Firestore Index ตามคำแนะนำแล้ว", style: const TextStyle(color: Colors.white)),
          ));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('ยังไม่มีประวัติการต่อรอง', style: TextStyle(color: Colors.white70)));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(8.0),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];
            return _NegotiationHistoryItem(doc: doc);
          },
        );
      },
    );
  }
}

// Widget for displaying a single history item
class _NegotiationHistoryItem extends StatefulWidget {
  final DocumentSnapshot doc;
  const _NegotiationHistoryItem({required this.doc});

  @override
  State<_NegotiationHistoryItem> createState() => _NegotiationHistoryItemState();
}

class _NegotiationHistoryItemState extends State<_NegotiationHistoryItem> {
  late String _currentStatus;
  String? _stock;
  String? _lastPurchaseInfo;
  String? _supplierId;
  String? _invoiceNumber;
  String? _lastPurchaseQty;
  String? _lastPurchaseDate;
  bool _detailsLoading = true;
  final _commentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final data = widget.doc.data() as Map<String, dynamic>;
    _currentStatus = data['status'] ?? 'pending';
    _commentController.text = data['approverComment'] ?? '';
    _fetchExtraDetails();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _fetchExtraDetails() async {
    try {
      final data = widget.doc.data() as Map<String, dynamic>;
      final productId = data['productId'] as String?;
      if (productId == null) return;

      final productDoc = await FirebaseFirestore.instance.collection('products').doc(productId.replaceAll('/', '-')).get();
      if (productDoc.exists) {
        _stock = (productDoc.data()?['จำนวนคงเหลือ'] ?? 0.0).toStringAsFixed(0);
      }

      final purchaseSnapshot = await FirebaseFirestore.instance
          .collection('purchases')
          .where('รหัสสินค้า', isEqualTo: productId)
          .orderBy('วันที่', descending: true)
          .limit(1)
          .get();
      
      if (purchaseSnapshot.docs.isNotEmpty) {
        final purchaseData = purchaseSnapshot.docs.first.data();
        final price = (purchaseData['ราคา/หน่วย'] ?? 0.0).toDouble();
        final priceWithVat = price * 1.07;
        final unit = purchaseData['หน่วย'] ?? '';
        
        _lastPurchaseDate = purchaseData['วันที่']?.toString() ?? '';
        _lastPurchaseInfo = '${priceWithVat.toStringAsFixed(2)} บาท / $unit';
        _supplierId = purchaseData['รหัสเจ้าหนี้'] ?? 'N/A';
        _invoiceNumber = purchaseData['เลขที่ใบกำกับ'] ?? 'N/A';
        _lastPurchaseQty = (purchaseData['จำนวน'] ?? 0.0).toStringAsFixed(0);
      }
    } catch (e) {
      print("Error fetching extra details: $e");
    } finally {
      if (mounted) {
        setState(() => _detailsLoading = false);
      }
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      await widget.doc.reference.update({
        'status': newStatus,
        'approverComment': _commentController.text.trim(),
        'approvedBy': FirebaseAuth.instance.currentUser?.displayName ?? 'N/A',
        'approvedAt': Timestamp.now(),
      });
      if (mounted) {
        setState(() {
          _currentStatus = newStatus;
        });
      }
      scaffoldMessenger.showSnackBar(const SnackBar(content: Text('อัปเดตสถานะสำเร็จ'), backgroundColor: Colors.green,));
    } catch (e) {
      scaffoldMessenger.showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาดในการอัปเดต: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.doc.data() as Map<String, dynamic>;
    final conditions = (data['conditions'] as List<dynamic>? ?? [])
        .map((c) => c as Map<String, dynamic>)
        .toList();
    final currencyFormat = NumberFormat("#,##0.00", "en_US");

    IconData statusIcon;
    Color statusColor;

    switch (_currentStatus) {
      case 'approved': statusIcon = Icons.check_circle; statusColor = Colors.green; break;
      case 'rejected': statusIcon = Icons.cancel; statusColor = Colors.red; break;
      default: statusIcon = Icons.hourglass_empty; statusColor = Colors.orange;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ExpansionTile(
        leading: Icon(statusIcon, color: statusColor),
        title: Text(
          '${data['customerId']} | ${data['customerIdentifier'] ?? 'N/A'} | ราคา: ${data['customerPriceLevel'] ?? 'A'}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        subtitle: Text(
          '${data['productName'] ?? 'N/A'}',
           maxLines: 1,
           overflow: TextOverflow.ellipsis,
        ),
        trailing: PopupMenuButton<String>(
          onSelected: _updateStatus,
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            const PopupMenuItem<String>(value: 'approved', child: Text('อนุมัติ')),
            const PopupMenuItem<String>(value: 'rejected', child: Text('ไม่อนุมัติ')),
            const PopupMenuItem<String>(value: 'pending', child: Text('รอดำเนินการ')),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 16.0),
            child: _detailsLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow('รหัสสินค้า:', data['productId'] ?? 'N/A'),
                    // FIXED: Correctly format A/B/C prices from the negotiation document
                    Text(
                      'ราคา A: ${currencyFormat.format(data['priceA'] ?? 0)} | B: ${currencyFormat.format(data['priceB'] ?? 0)} | C: ${currencyFormat.format(data['priceC'] ?? 0)}',
                      style: const TextStyle(fontSize: 15, color: Colors.blueAccent),
                    ),
                    const SizedBox(height: 8),
                    const Text('เงื่อนไขการต่อรองทั้งหมด:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ...conditions.map((c) => Text(' - เสนอ ${c['quantity']} ${c['unit']} ราคา ${currencyFormat.format(c['price'])} บาท', style: const TextStyle(fontSize: 15,color: Colors.red))),
                    _buildInfoRow('แหล่งที่มา:', '${data['source'] ?? '-'} (โดย: ${data['recordedBy'] ?? 'N/A'})'),
                    const Divider(height: 16),
                    _buildInfoRow('รหัสเจ้าหนี้:', _supplierId ?? 'N/A', 'เลขที่ใบกำกับ:', _invoiceNumber ?? 'N/A'),
                    // FIXED: Use the correct date string and format it
                    _buildInfoRow('ซื้อล่าสุดวันที่:', DateHelper.formatDateToThai(_lastPurchaseDate ?? ''), 'จำนวน:', _lastPurchaseQty ?? 'N/A'),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: RichText(text: TextSpan(
                              style: DefaultTextStyle.of(context).style.copyWith(fontSize: 13, color: Colors.green),
                              children: [
                                const TextSpan(text: 'ราคาซื้อ : ', style: TextStyle(fontWeight: FontWeight.bold)),
                                TextSpan(text: _lastPurchaseInfo ?? 'N/A'),
                              ]
                            )),
                          ),
                          Expanded(
                            child: RichText(text: TextSpan(
                              style: DefaultTextStyle.of(context).style.copyWith(fontSize: 12),
                              children: [
                                const TextSpan(text: 'คงเหลือ: ', style: TextStyle(fontWeight: FontWeight.bold)),
                                TextSpan(text: _stock ?? 'N/A'),
                              ]
                            )),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 16),
                    TextFormField(
                      controller: _commentController,
                      decoration: const InputDecoration(
                        labelText: 'หมายเหตุ&คอมเม้นท์ จากผู้อนุมัติ',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      maxLines: 2,
                    ),
                    if (data['imageUrl'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: InkWell(
                          onTap: () => showDialog(context: context, builder: (_) => Dialog(child: Image.network(data['imageUrl']))),
                          child: Image.network(data['imageUrl'], height: 100),
                        ),
                      ),
                  ],
                ),
          )
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label1, String value1, [String? label2, String? value2]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: RichText(text: TextSpan(
              style: DefaultTextStyle.of(context).style.copyWith(fontSize: 12),
              children: [
                TextSpan(text: '$label1 ', style: const TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(text: value1),
              ]
            )),
          ),
          if (label2 != null && value2 != null)
            Expanded(
              child: RichText(text: TextSpan(
                style: DefaultTextStyle.of(context).style.copyWith(fontSize: 12),
                children: [
                  TextSpan(text: '$label2 ', style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: value2),
                ]
              )),
            ),
        ],
      ),
    );
  }
}
