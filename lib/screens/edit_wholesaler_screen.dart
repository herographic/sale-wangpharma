// lib/screens/edit_wholesaler_screen.dart

import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:salewang/models/wholesaler.dart';
import 'dart:io';

class EditWholesalerScreen extends StatefulWidget {
  final String? wholesalerId;

  // UPDATED: Type is no longer required here, it will be handled by the state
  const EditWholesalerScreen({super.key, this.wholesalerId});

  @override
  State<EditWholesalerScreen> createState() => _EditWholesalerScreenState();
}

class _EditWholesalerScreenState extends State<EditWholesalerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _addressController = TextEditingController();
  final _openingHoursController = TextEditingController();
  final _deliveryRoutesController = TextEditingController();
  final _promotionsController = TextEditingController();
  final _transportInfoController = TextEditingController();
  final _prosController = TextEditingController();
  final _consController = TextEditingController();
  final _customerFeedbackController = TextEditingController();
  final _repFeedbackController = TextEditingController();
  final _chatController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _logoUrl;
  XFile? _selectedImageFile;
  Uint8List? _webImageBytes;

  // NEW: State to manage the type ('wholesaler' or 'competitor')
  String _selectedType = 'wholesaler'; 

  @override
  void initState() {
    super.initState();
    if (widget.wholesalerId != null) {
      _loadWholesalerData();
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadWholesalerData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('wholesalers')
          .doc(widget.wholesalerId)
          .get();
      if (doc.exists) {
        final wholesaler = Wholesaler.fromFirestore(doc);
        _nameController.text = wholesaler.name;
        _nicknameController.text = wholesaler.nickname ?? '';
        _addressController.text = wholesaler.address ?? '';
        _openingHoursController.text = wholesaler.openingHours ?? '';
        _deliveryRoutesController.text = (wholesaler.deliveryRoutes ?? []).join(', ');
        _promotionsController.text = wholesaler.promotions ?? '';
        _transportInfoController.text = wholesaler.transportInfo ?? '';
        _prosController.text = wholesaler.pros ?? '';
        _consController.text = wholesaler.cons ?? '';
        _customerFeedbackController.text = wholesaler.customerFeedback ?? '';
        _repFeedbackController.text = wholesaler.repFeedback ?? '';
        _logoUrl = wholesaler.logoUrl;
        // Load the type from existing data
        _selectedType = wholesaler.type;
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาดในการโหลดข้อมูล: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 800);
    if (pickedFile != null) {
      _selectedImageFile = pickedFile;
      if (kIsWeb) {
        _webImageBytes = await pickedFile.readAsBytes();
      }
      setState(() {});
    }
  }

  Future<void> _saveData() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isSaving = true);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      String? newLogoUrl = _logoUrl;
      if (_selectedImageFile != null) {
        final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
        final ref = FirebaseStorage.instance.ref('wholesaler_logos').child(widget.wholesalerId ?? _nameController.text).child(fileName);
        
        if (kIsWeb) {
          await ref.putData(_webImageBytes!, SettableMetadata(contentType: 'image/jpeg'));
        } else {
          await ref.putFile(File(_selectedImageFile!.path));
        }
        newLogoUrl = await ref.getDownloadURL();
      }

      final data = {
        'name': _nameController.text.trim(),
        'nickname': _nicknameController.text.trim(),
        'address': _addressController.text.trim(),
        'openingHours': _openingHoursController.text.trim(),
        'deliveryRoutes': _deliveryRoutesController.text.split(',').map((e) => e.trim()).toList(),
        'promotions': _promotionsController.text.trim(),
        'transportInfo': _transportInfoController.text.trim(),
        'pros': _prosController.text.trim(),
        'cons': _consController.text.trim(),
        'customerFeedback': _customerFeedbackController.text.trim(),
        'repFeedback': _repFeedbackController.text.trim(),
        'logoUrl': newLogoUrl,
        'lastUpdated': Timestamp.now(),
        'type': _selectedType, // Save the selected type
      };

      if (widget.wholesalerId != null) {
        await FirebaseFirestore.instance.collection('wholesalers').doc(widget.wholesalerId).update(data);
      } else {
        await FirebaseFirestore.instance.collection('wholesalers').add(data);
      }

      scaffoldMessenger.showSnackBar(const SnackBar(content: Text('บันทึกข้อมูลสำเร็จ'), backgroundColor: Colors.green));
      if (mounted) Navigator.pop(context);

    } catch (e) {
      scaffoldMessenger.showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // UPDATED: Added gradient background
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
           title: Text(
            widget.wholesalerId == null ? 'เพิ่มข้อมูลใหม่' : 'แก้ไขข้อมูล',
            style: const TextStyle(color: Colors.white)
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white)) : const Icon(Icons.save),
              onPressed: _isSaving ? null : _saveData,
            )
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16.0),
                  children: [
                    // UPDATED: Grouped fields into cards
                    _buildSectionCard(
                      child: Column(
                        children: [
                           if (widget.wholesalerId == null) _buildTypeSelector(), // Show only when creating
                          _buildImagePicker(),
                          const SizedBox(height: 16),
                          _buildTextField(_nameController, 'ชื่อยี่ปั๊ว / คู่แข่ง', isRequired: true),
                          _buildTextField(_nicknameController, 'นามแฝง / ฉายา'),
                          _buildTextField(_addressController, 'ที่อยู่ / สถานที่ตั้ง'),
                          _buildTextField(_openingHoursController, 'เวลาเปิด-ปิด'),
                        ],
                      ),
                    ),
                    _buildSectionCard(
                      title: 'ข้อมูลการดำเนินงาน',
                      child: Column(
                         children: [
                            _buildTextField(_deliveryRoutesController, 'เส้นทาง/ขอบเขตการส่ง (คั่นด้วย ,)'),
                            _buildTextField(_promotionsController, 'โปรโมชั่น / ข้อมูลการตลาด', maxLines: 3),
                            _buildTextField(_transportInfoController, 'ข้อมูลรถขนส่ง', maxLines: 2),
                         ],
                      ),
                    ),
                     _buildSectionCard(
                      title: 'วิเคราะห์และข้อมูลเชิงลึก',
                      child: Column(
                         children: [
                            _buildTextField(_prosController, 'ข้อดี', maxLines: 3),
                            _buildTextField(_consController, 'ข้อเสีย', maxLines: 3),
                            _buildTextField(_customerFeedbackController, 'คำกล่าวอ้างจากลูกค้า', maxLines: 3),
                            _buildTextField(_repFeedbackController, 'คำกล่าวอ้างจากผู้แทนยา', maxLines: 3),
                         ],
                      ),
                    ),
                    if (widget.wholesalerId != null)
                      _buildSectionCard(
                        title: 'บันทึกการทำงาน (Live Chat)',
                        child: _buildChatSection(),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  // NEW: Widget for section cards
  Widget _buildSectionCard({String? title, required Widget child}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const Divider(height: 20),
            ],
            child,
          ],
        ),
      ),
    );
  }

  // NEW: Widget for selecting the type
  Widget _buildTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ประเภทข้อมูล:', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const <ButtonSegment<String>>[
            ButtonSegment<String>(value: 'wholesaler', label: Text('ยี่ปั๊ว'), icon: Icon(Icons.storefront)),
            ButtonSegment<String>(value: 'competitor', label: Text('คู่แข่ง'), icon: Icon(Icons.shield_outlined)),
          ],
          selected: <String>{_selectedType},
          onSelectionChanged: (Set<String> newSelection) {
            setState(() {
              _selectedType = newSelection.first;
            });
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }


  Widget _buildImagePicker() {
    return Center(
      child: Stack(
        children: [
          CircleAvatar(
            radius: 60,
            backgroundColor: Colors.grey.shade200,
            backgroundImage: _webImageBytes != null
                ? MemoryImage(_webImageBytes!)
                : (_selectedImageFile != null
                    ? FileImage(File(_selectedImageFile!.path))
                    : (_logoUrl != null ? NetworkImage(_logoUrl!) : null)) as ImageProvider?,
            child: _webImageBytes == null && _selectedImageFile == null && _logoUrl == null
                ? const Icon(Icons.business, size: 60, color: Colors.grey)
                : null,
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: CircleAvatar(
              radius: 20,
              backgroundColor: Theme.of(context).primaryColor,
              child: IconButton(
                icon: const Icon(Icons.edit, color: Colors.white, size: 20),
                onPressed: _pickImage,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, {bool isRequired = false, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
           filled: true,
          fillColor: Colors.grey.shade50,
        ),
        maxLines: maxLines,
        validator: (value) {
          if (isRequired && (value == null || value.trim().isEmpty)) {
            return 'กรุณากรอกข้อมูล';
          }
          return null;
        },
      ),
    );
  }
  
  Widget _buildChatSection() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 300,
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('wholesalers')
                .doc(widget.wholesalerId)
                .collection('chat')
                .orderBy('timestamp', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
               if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
               final messages = snapshot.data!.docs;
               return ListView.builder(
                 reverse: true,
                 itemCount: messages.length,
                 itemBuilder: (context, index) {
                   final msg = messages[index];
                   final isMe = msg['userId'] == user.uid;
                   return Align(
                     alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                     child: Container(
                       margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                       padding: const EdgeInsets.all(12),
                       decoration: BoxDecoration(
                         color: isMe ? Theme.of(context).primaryColorLight.withOpacity(0.8) : Colors.grey.shade200,
                         borderRadius: BorderRadius.circular(12),
                       ),
                       child: Column(
                         crossAxisAlignment: CrossAxisAlignment.start,
                         children: [
                           Text(msg['userName'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                           Text(msg['text']),
                         ],
                       ),
                     ),
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
                controller: _chatController,
                decoration: const InputDecoration(hintText: 'พิมพ์ข้อความ...'),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: () async {
                if (_chatController.text.trim().isNotEmpty) {
                  await FirebaseFirestore.instance
                      .collection('wholesalers')
                      .doc(widget.wholesalerId)
                      .collection('chat')
                      .add({
                    'text': _chatController.text.trim(),
                    'userId': user.uid,
                    'userName': user.displayName ?? 'N/A',
                    'timestamp': FieldValue.serverTimestamp(),
                  });
                  _chatController.clear();
                  await FirebaseFirestore.instance
                      .collection('wholesalers')
                      .doc(widget.wholesalerId)
                      .update({'lastUpdated': Timestamp.now()});
                }
              },
            ),
          ],
        )
      ],
    );
  }
}
