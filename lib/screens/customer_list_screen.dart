// lib/screens/customer_list_screen.dart

import 'package:flutter/material.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:salewang/models/customer.dart';
import 'package:salewang/models/new_customer_prospect.dart';
import 'package:salewang/screens/add_edit_new_customer_screen.dart';
import 'package:salewang/screens/customer_detail_screen.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({super.key});

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _mainTabController;

  @override
  void initState() {
    super.initState();
    _mainTabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _mainTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          TabBar(
            controller: _mainTabController,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white.withOpacity(0.7),
            indicatorColor: Colors.yellowAccent,
            tabs: const [
              Tab(text: 'ข้อมูลลูกค้า'),
              Tab(text: 'ลูกค้าใหม่'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _mainTabController,
              children: const [
                _CustomerSearchTab(),
                _NewCustomerProspectListTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerSearchTab extends StatefulWidget {
  const _CustomerSearchTab();

  @override
  State<_CustomerSearchTab> createState() => _CustomerSearchTabState();
}

class _CustomerSearchTabState extends State<_CustomerSearchTab> {
  final TextEditingController _nameSearchController = TextEditingController();
  final TextEditingController _codeSearchController = TextEditingController();
  Timer? _debounce;
  
  List<Customer> _allCustomers = [];
  List<Customer> _searchResults = [];
  
  bool _isLoading = true;
  String? _errorMessage;
  String _statusMessage = 'กำลังโหลดข้อมูลลูกค้า...';

  @override
  void initState() {
    super.initState();
    _fetchAllCustomers();
    _nameSearchController.addListener(_onSearchChanged);
    _codeSearchController.addListener(_onSearchChanged);
  }

  void _clearController(TextEditingController controller) {
    controller.clear();
    _debounce?.cancel();
    _filterCustomers('');
    setState(() {}); // refresh to hide the clear button immediately
  }

  @override
  void dispose() {
    _nameSearchController.dispose();
    _codeSearchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }
  
  Future<void> _fetchAllCustomers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final customersSnapshot = await FirebaseFirestore.instance.collection('customers').get();
      if (!mounted) return;

      final customers = customersSnapshot.docs.map((doc) => Customer.fromFirestore(doc)).toList();
      
      setState(() {
        _allCustomers = customers;
        _statusMessage = 'กรุณาค้นหาลูกค้า...';
        _isLoading = false;
      });

    } catch (e) {
      if(mounted) {
        setState(() {
          _errorMessage = 'เกิดข้อผิดพลาดในการโหลดข้อมูล: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final nameQuery = _nameSearchController.text.trim();
      final codeQuery = _codeSearchController.text.trim();
      
      final query = nameQuery.isNotEmpty ? nameQuery : codeQuery;
      
      if (nameQuery.isNotEmpty && _codeSearchController.text.isNotEmpty) {
        _codeSearchController.clear();
      } else if (codeQuery.isNotEmpty && _nameSearchController.text.isNotEmpty) {
        _nameSearchController.clear();
      }
      
      _filterCustomers(query);
    });
  }

  void _filterCustomers(String query) {
    final trimmedQuery = query.trim().toLowerCase();
    if (trimmedQuery.isEmpty) {
      setState(() {
        _searchResults = [];
        _statusMessage = 'กรุณาค้นหาลูกค้า...';
      });
      return;
    }
    
    final filteredList = _allCustomers.where((customer) {
      final nameLower = customer.name.toLowerCase();
      final idLower = customer.customerId.toLowerCase();
      
      return nameLower.contains(trimmedQuery) || idLower.contains(trimmedQuery);
    }).toList();

    setState(() {
      _searchResults = filteredList;
      if (_searchResults.isEmpty) {
        _statusMessage = 'ไม่พบข้อมูลลูกค้า';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _nameSearchController,
                  builder: (context, value, _) {
                    return TextField(
                      controller: _nameSearchController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'ค้นชื่อลูกค้า',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                        prefixIcon: const Icon(Icons.keyboard_alt_outlined, color: Colors.white),
                        suffixIcon: value.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Colors.white),
                                tooltip: 'ล้าง',
                                onPressed: () => _clearController(_nameSearchController),
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.black.withOpacity(0.2),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _codeSearchController,
                  builder: (context, value, _) {
                    return TextField(
                      controller: _codeSearchController,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'ค้นรหัสลูกค้า',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                        prefixIcon: const Icon(Icons.grid_on_outlined, color: Colors.white),
                        suffixIcon: value.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Colors.white),
                                tooltip: 'ล้าง',
                                onPressed: () => _clearController(_codeSearchController),
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.black.withOpacity(0.2),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : _errorMessage != null
                  ? Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.white)))
                  : _searchResults.isNotEmpty
                      ? ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            return _FirestoreCustomerInfoCard(customer: _searchResults[index]);
                          },
                        )
                      : Center(child: Text(_statusMessage, style: const TextStyle(color: Colors.white70))),
        ),
      ],
    );
  }
}

class _NewCustomerProspectListTab extends StatelessWidget {
  const _NewCustomerProspectListTab();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('new_customer_prospects')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }
          if (snapshot.hasError) {
            return Center(child: Text('เกิดข้อผิดพลาดในการโหลดข้อมูล: ${snapshot.error}', style: const TextStyle(color: Colors.white)));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('ไม่มีข้อมูลลูกค้าใหม่', style: TextStyle(color: Colors.white70)));
          }
          final prospects = snapshot.data!.docs.map((doc) => NewCustomerProspect.fromFirestore(doc)).toList();
          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: prospects.length,
            itemBuilder: (context, index) {
              return _ProspectCard(prospect: prospects[index]);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const AddEditNewCustomerScreen()));
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _ProspectCard extends StatefulWidget {
  final NewCustomerProspect prospect;
  const _ProspectCard({required this.prospect});

  @override
  State<_ProspectCard> createState() => _ProspectCardState();
}

class _ProspectCardState extends State<_ProspectCard> {
  final _commentController = TextEditingController();
  bool _isSendingComment = false;

  Future<void> _updateApprovalStatus(String newStatus) async {
    await FirebaseFirestore.instance.collection('new_customer_prospects').doc(widget.prospect.id).update({'approvalStatus': newStatus});
  }

  Future<void> _deleteProspect() async {
    final passwordController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('คุณต้องการลบรายการนี้ใช่หรือไม่? การกระทำนี้ไม่สามารถย้อนกลับได้'),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'กรุณาใส่รหัสผ่านเพื่อยืนยัน'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
          TextButton(
            onPressed: () {
              if (passwordController.text == '141300') {
                Navigator.pop(context, true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('รหัสผ่านไม่ถูกต้อง'), backgroundColor: Colors.red));
              }
            },
            child: const Text('ลบ', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance.collection('new_customer_prospects').doc(widget.prospect.id).delete();
    }
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    final user = FirebaseAuth.instance.currentUser;
    if (text.isEmpty || user == null) return;

    setState(() => _isSendingComment = true);
    try {
      await FirebaseFirestore.instance
          .collection('new_customer_prospects')
          .doc(widget.prospect.id)
          .collection('notes')
          .add({
        'text': text,
        'timestamp': FieldValue.serverTimestamp(),
        'userId': user.uid,
        'userName': user.displayName ?? user.email?.split('@').first ?? 'Unknown',
      });
      _commentController.clear();
      FocusScope.of(context).unfocus();
    } finally {
      if (mounted) setState(() => _isSendingComment = false);
    }
  }
  
  Future<void> _shareProspect() async {
    final dateFormat = DateFormat('dd/MM/yy HH:mm', 'th_TH');
    final p = widget.prospect;
    final data = p.rawData;

    String statusDetails = '';
    if (p.status == 'ร้านใหม่' && p.openingDate != null) {
      statusDetails = 'จะเปิดภายในวันที่: ${DateFormat('dd MMMM yyyy', 'th_TH').format(p.openingDate!.toDate())}';
    } else if (p.status == 'ร้านเก่าลูกค้าใหม่') {
      statusDetails = 'เดิมซื้อกับ: ${p.previousSupplier ?? '-'}';
    }
    
    final storeAddress = data['storeAddress'] ?? {};
    final fullAddress = [
      'เลขที่ ${storeAddress['houseNumber'] ?? ''}', 'หมู่ ${storeAddress['moo'] ?? ''}', 'ซอย ${storeAddress['soi'] ?? ''}', 'ถนน ${storeAddress['road'] ?? ''}',
      'อ.${storeAddress['district'] ?? ''}', 'จ.${storeAddress['province'] ?? ''}', storeAddress['zipcode'] ?? ''
    ].where((s) => s.split(' ').last.isNotEmpty).join(' ');

    final contacts = data['contacts'] ?? {};
    final owner = contacts['owner'] ?? {};
    final pharmacist = contacts['pharmacist'] ?? {};
    final purchaser = contacts['purchaser'] ?? {};

    final shareText = '''
📋 บันทึกลูกค้าใหม่
รหัสชั่วคราว: ${p.tempId} | สถานะ: ${p.approvalStatus.toUpperCase()}
--------------------
ชื่อร้าน: ${p.storeName} (${p.branch ?? 'สนญ.'})
สถานะร้าน: ${p.status}
$statusDetails
ที่อยู่: $fullAddress
--------------------
ผู้ติดต่อ:
- เจ้าของ: ${owner['nickname'] ?? '-'} (${owner['phone'] ?? '-'})
- เภสัชกร: ${pharmacist['nickname'] ?? '-'} (${pharmacist['phone'] ?? '-'})
- ผู้สั่งซื้อ: ${purchaser['nickname'] ?? '-'} (${purchaser['phone'] ?? '-'})
--------------------
ผู้ดูแล: ${p.salesperson} | ซัพพอร์ท: ${p.salesSupport}
--------------------
สร้างโดย: ${p.createdBy} | วันที่: ${dateFormat.format(p.createdAt.toDate())}
''';
    Share.share(shareText);
  }

  // NEW: Function to show the image viewer dialog
  void _showImageViewer(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: InteractiveViewer(
                panEnabled: true,
                minScale: 0.5,
                maxScale: 4,
                child: Image.network(imageUrl),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.share),
                    onPressed: () {
                      Share.share('ดูรูปภาพนี้: $imageUrl');
                    },
                    tooltip: 'แชร์รูปภาพ',
                  ),
                  IconButton(
                    icon: const Icon(Icons.save_alt),
                    onPressed: () async {
                      final uri = Uri.parse(imageUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                    tooltip: 'บันทึกรูปภาพ',
                  ),
                   IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'ปิด',
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yy HH:mm');
    final p = widget.prospect;
    final data = p.rawData;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ExpansionTile(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             _StatusChip(status: p.approvalStatus),
             const SizedBox(height: 4),
             Text('${p.tempId}: ${p.storeName}', style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        subtitle: Text('โดย: ${p.createdBy} | วันที่: ${dateFormat.format(p.createdAt.toDate())}'),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader('ข้อมูลร้านค้า'),
                _buildInfoRow('สถานะ:', p.status),
                if(p.status == 'ร้านใหม่' && p.openingDate != null)
                  _buildInfoRow('วันที่เปิด:', DateFormat('dd MMMM yyyy', 'th_TH').format(p.openingDate!.toDate())),
                if(p.status == 'ร้านเก่าลูกค้าใหม่')
                  _buildInfoRow('ซื้อจาก:', p.previousSupplier ?? '-'),
                
                _buildSectionHeader('ที่อยู่ร้านค้า'),
                _buildAddressDisplay(data['storeAddress'] ?? {}),

                _buildSectionHeader('ข้อมูลผู้ติดต่อ'),
                _buildContactDisplay(data['contacts'] ?? {}),
                
                _buildSectionHeader('ข้อมูลการชำระเงิน'),
                _buildInfoRow('เงื่อนไข:', data['paymentInfo']?['term'] ?? '-'),
                _buildInfoRow('สะดวกชำระทุกวันที่:', data['paymentInfo']?['dueDate'] ?? '-'),

                _buildSectionHeader('รายละเอียดเพิ่มเติม'),
                _buildInfoRow('เวลาเปิด-ปิด:', '${data['additionalInfo']?['openingTime'] ?? '-'} - ${data['additionalInfo']?['closingTime'] ?? '-'}'),
                _buildInfoRow('รายละเอียด:', p.details),
                _buildInfoRow('หมายเหตุ:', p.notes),

                _buildSectionHeader('ข้อมูลการจัดส่ง'),
                 _buildInfoRow('วันสะดวก:', (data['deliveryInfo']?['days'] as List<dynamic>? ?? []).join(', ')),
                 _buildInfoRow('เวลา:', data['deliveryInfo']?['time'] ?? '-'),
                _buildAddressDisplay(data['deliveryInfo']?['address'] ?? {}),

                _buildSectionHeader('รูปภาพและเอกสาร'),
                // UPDATED: Call the new _buildFileGallery widget
                _buildFileGallery('รูปภาพ:', data['categorizedImageUrls'] ?? {}),
                _buildFileGallery('เอกสาร:', data['categorizedDocumentUrls'] ?? {}),

                const Divider(),
                _buildChatSection(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    PopupMenuButton<String>(
                      onSelected: _updateApprovalStatus,
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'approved', child: Text('อนุมัติ')),
                        const PopupMenuItem(value: 'rejected', child: Text('ไม่อนุมัติ')),
                        const PopupMenuItem(value: 'pending', child: Text('รอดำเนินการ')),
                        const PopupMenuItem(value: 'request_info', child: Text('ขอข้อมูลเพิ่ม')),
                        const PopupMenuItem(value: 'urgent', child: Text('ด่วน')),
                      ],
                      child: const Chip(label: Text('เปลี่ยนสถานะ'), avatar: Icon(Icons.approval, size: 16)),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      icon: const Icon(Icons.share, size: 18),
                      label: const Text('แชร์'),
                      onPressed: _shareProspect,
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('แก้ไข'),
                      onPressed: () {
                         Navigator.push(context, MaterialPageRoute(builder: (context) => AddEditNewCustomerScreen(prospect: widget.prospect)));
                      },
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.delete, size: 18),
                      label: const Text('ลบ'),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      onPressed: _deleteProspect,
                    ),
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 12.0, bottom: 4.0),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.indigo)),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
  
  Widget _buildInfoRowWithCall(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(value)),
          IconButton(
            icon: const Icon(Icons.call, color: Colors.green, size: 20),
            onPressed: () async {
              final Uri launchUri = Uri(scheme: 'tel', path: value);
              if (await canLaunchUrl(launchUri)) {
                await launchUrl(launchUri);
              }
            },
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
          )
        ],
      ),
    );
  }

  Widget _buildAddressDisplay(Map address) {
    final addressParts = [
      'เลขที่ ${address['houseNumber'] ?? ''}',
      'หมู่ ${address['moo'] ?? ''}',
      'ซอย ${address['soi'] ?? ''}',
      'ถนน ${address['road'] ?? ''}',
      'อ.${address['district'] ?? ''}',
      'จ.${address['province'] ?? ''}',
      address['zipcode'] ?? '',
    ].where((s) => s.split(' ').last.isNotEmpty).join(' ');
    
    return _buildInfoRow('ที่อยู่:', addressParts);
  }

  Widget _buildContactDisplay(Map contacts) {
    final owner = contacts['owner'] ?? {};
    final pharmacist = contacts['pharmacist'] ?? {};
    final purchaser = contacts['purchaser'] ?? {};

    return Column(
      children: [
        if (owner['phone']?.isNotEmpty ?? false)
          _buildInfoRowWithCall('เจ้าของ:', '${owner['nickname']} (${owner['phone']})'),
        if (pharmacist['phone']?.isNotEmpty ?? false)
          _buildInfoRowWithCall('เภสัชกร:', '${pharmacist['nickname']} (${pharmacist['phone']})'),
        if (purchaser['phone']?.isNotEmpty ?? false)
          _buildInfoRowWithCall('ผู้สั่งซื้อ:', '${purchaser['nickname']} (${purchaser['phone']})'),
      ],
    );
  }

  // UPDATED: This widget now displays image thumbnails or file chips.
  Widget _buildFileGallery(String title, Map files) {
    if (files.values.where((v) => v != null).isEmpty) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8.0,
          runSpacing: 4.0,
          children: files.entries.map<Widget>((entry) {
            final String key = entry.key;
            final String? url = entry.value;
            if (url == null) return const SizedBox.shrink();

            final isImage = ['.jpg', '.jpeg', '.png', '.gif'].any((ext) => url.toLowerCase().contains(ext));

            if (isImage) {
              // Display image thumbnail
              return GestureDetector(
                onTap: () => _showImageViewer(context, url),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8.0),
                  child: Image.network(
                    url,
                    width: 70,
                    height: 70,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) {
                      return progress == null ? child : const Center(child: CircularProgressIndicator());
                    },
                    errorBuilder: (context, error, stack) => const Icon(Icons.broken_image, size: 70),
                  ),
                ),
              );
            } else {
              // Display file chip for non-images (like PDFs)
              return InkWell(
                onTap: () async {
                  final uri = Uri.tryParse(url);
                  if (uri != null && await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: Chip(
                  avatar: const Icon(Icons.picture_as_pdf, color: Colors.red),
                  label: Text(key),
                ),
              );
            }
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildChatSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('บันทึกเพิ่มเติม', style: Theme.of(context).textTheme.titleSmall),
        SizedBox(
          height: 150,
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
              .collection('new_customer_prospects')
              .doc(widget.prospect.id)
              .collection('notes')
              .orderBy('timestamp', descending: true)
              .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              if (snapshot.data!.docs.isEmpty) return const Center(child: Text('ไม่มีบันทึก'));
              return ListView.builder(
                itemCount: snapshot.data!.docs.length,
                itemBuilder: (context, index) {
                  final note = snapshot.data!.docs[index];
                  final data = note.data() as Map<String, dynamic>;
                  final timestamp = data.containsKey('timestamp') ? data['timestamp'] as Timestamp? : null;
                  final formattedDate = timestamp != null
                      ? DateFormat('dd/MM/yy HH:mm').format(timestamp.toDate())
                      : 'กำลังบันทึก...';
                  return ListTile(
                    title: Text(data['text'] ?? ''),
                    subtitle: Text('${data['userName'] ?? '...'} - $formattedDate'),
                  );
                },
              );
            },
          ),
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _commentController,
                decoration: const InputDecoration(hintText: 'เพิ่มความคิดเห็น...', isDense: true),
              ),
            ),
            IconButton(
              icon: _isSendingComment ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
              onPressed: _isSendingComment ? null : _sendComment,
            )
          ],
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    String label;
    Color color;
    switch (status) {
      case 'approved':
      label = 'อนุมัติ';
      color = Colors.green;
      break;
      case 'rejected':
      label = 'ไม่อนุมัติ';
      color = Colors.redAccent;
      break;
      case 'request_info':
      label = 'ขอข้อมูลเพิ่ม';
      color = Colors.blue;
      break;
      case 'urgent':
      label = 'ด่วน';
      color = Colors.red;
      break;
      default:
      label = 'รอดำเนินการ';
      color = Colors.orange;
    }
    
    return Chip(
      label: Text(
      label,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
      ),
      backgroundColor: color,
      // No avatar for now
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      labelPadding: const EdgeInsets.only(left: 4, right: 4),
    );
  }
}


class _FirestoreCustomerInfoCard extends StatelessWidget {
  final Customer customer;
  const _FirestoreCustomerInfoCard({required this.customer});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CustomerDetailScreen(customer: customer),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 24,
                backgroundColor: Colors.grey,
                child: Icon(Icons.person, color: Colors.white),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      'รหัส: ${customer.customerId}',
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
