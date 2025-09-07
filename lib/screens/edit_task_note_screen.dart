// lib/screens/edit_task_note_screen.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:salewang/models/customer.dart';
import 'package:salewang/models/task_note.dart';

class EditTaskNoteScreen extends StatefulWidget {
  final TaskNote? taskNote;
  const EditTaskNoteScreen({super.key, this.taskNote});

  @override
  State<EditTaskNoteScreen> createState() => _EditTaskNoteScreenState();
}

class _EditTaskNoteScreenState extends State<EditTaskNoteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _detailsController = TextEditingController();
  final _customerSearchController = TextEditingController();

  Customer? _selectedCustomer;
  DateTime _selectedDateTime = DateTime.now();
  final List<XFile> _selectedImages = [];
  List<String> _existingImageUrls = [];
  bool _isSaving = false;
  Timer? _debounce;
  List<Customer> _customerSearchResults = [];
  bool _isCustomerLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.taskNote != null) {
      final task = widget.taskNote!;
      _titleController.text = task.title;
      _detailsController.text = task.details;
      _selectedDateTime = task.taskDateTime.toDate();
      _existingImageUrls = List.from(task.imageUrls);
      _loadInitialCustomer(task.customerId);
    }
    _customerSearchController.addListener(_onCustomerSearchChanged);
  }
  
  @override
  void dispose() {
    _titleController.dispose();
    _detailsController.dispose();
    _customerSearchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }


  Future<void> _loadInitialCustomer(String customerDocId) async {
    final doc = await FirebaseFirestore.instance.collection('customers').doc(customerDocId).get();
    if (doc.exists) {
      setState(() {
        _selectedCustomer = Customer.fromFirestore(doc);
      });
    }
  }

  void _onCustomerSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _searchCustomer);
  }

  Future<void> _searchCustomer() async {
    final query = _customerSearchController.text.trim();
    if (query.length < 2) {
      setState(() => _customerSearchResults = []);
      return;
    }
    setState(() => _isCustomerLoading = true);
    final nameQuery = FirebaseFirestore.instance.collection('customers').where('ชื่อลูกค้า', isGreaterThanOrEqualTo: query).where('ชื่อลูกค้า', isLessThanOrEqualTo: '$query\uf8ff').limit(5);
    final idQuery = FirebaseFirestore.instance.collection('customers').where('รหัสลูกค้า', isGreaterThanOrEqualTo: query).where('รหัสลูกค้า', isLessThanOrEqualTo: '$query\uf8ff').limit(5);
    
    final results = await Future.wait([nameQuery.get(), idQuery.get()]);
    final allDocs = [...results[0].docs, ...results[1].docs];
    final uniqueIds = <String>{};
    final uniqueCustomers = allDocs.where((doc) => uniqueIds.add(doc.id)).map((doc) => Customer.fromFirestore(doc)).toList();

    setState(() {
      _customerSearchResults = uniqueCustomers;
      _isCustomerLoading = false;
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFiles = source == ImageSource.gallery
        ? await picker.pickMultiImage(imageQuality: 70, maxWidth: 1024)
        : await picker.pickImage(source: source, imageQuality: 70, maxWidth: 1024);

    setState(() {
      if (pickedFiles == null) return;
      if (pickedFiles is List<XFile>) {
        _selectedImages.addAll(pickedFiles);
      } else if (pickedFiles is XFile) {
        _selectedImages.add(pickedFiles);
      }
    });
  }

  Future<void> _saveTaskNote() async {
    if (!_formKey.currentState!.validate() || _selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกข้อมูลให้ครบถ้วนและเลือกลูกค้า')),
      );
      return;
    }

    setState(() => _isSaving = true);
    final user = FirebaseAuth.instance.currentUser!;

    try {
      // Upload new images
      List<String> newImageUrls = [];
      if (_selectedImages.isNotEmpty) {
        final storageRef = FirebaseStorage.instance.ref().child('task_notes');
        for (var imageFile in _selectedImages) {
          final fileName = '${DateTime.now().millisecondsSinceEpoch}-${imageFile.name}';
          final uploadTask = storageRef.child(fileName);
          if (kIsWeb) {
            await uploadTask.putData(await imageFile.readAsBytes(), SettableMetadata(contentType: 'image/jpeg'));
          } else {
            await uploadTask.putFile(File(imageFile.path));
          }
          newImageUrls.add(await uploadTask.getDownloadURL());
        }
      }

      final taskData = {
        'customerId': _selectedCustomer!.id, // Use Firestore document ID
        'customerCode': _selectedCustomer!.customerId, // Use human-readable code
        'customerName': _selectedCustomer!.name,
        'title': _titleController.text.trim(),
        'details': _detailsController.text.trim(),
        'taskDateTime': Timestamp.fromDate(_selectedDateTime),
        'imageUrls': [..._existingImageUrls, ...newImageUrls],
        'createdBy': user.displayName ?? user.email,
        'createdById': user.uid,
        'createdAt': widget.taskNote?.createdAt ?? FieldValue.serverTimestamp(),
        'isDeleted': false,
        'status': widget.taskNote?.status ?? 'pending',
      };

      if (widget.taskNote != null) {
        await FirebaseFirestore.instance.collection('task_notes').doc(widget.taskNote!.id).update(taskData);
      } else {
        await FirebaseFirestore.instance.collection('task_notes').add(taskData);
      }

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
          title: Text(widget.taskNote == null ? 'เพิ่มรายการติดตามงาน' : 'แก้ไขรายการ', style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2,)) : const Icon(Icons.save),
              onPressed: _isSaving ? null : _saveTaskNote,
            )
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                       if (_selectedCustomer != null)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.person, color: Colors.blue),
                          title: Text(_selectedCustomer!.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(_selectedCustomer!.customerId),
                          trailing: IconButton(
                            icon: const Icon(Icons.clear, color: Colors.red),
                            onPressed: () => setState(() => _selectedCustomer = null),
                          ),
                        )
                      else
                        Column(
                          children: [
                            TextFormField(
                              controller: _customerSearchController,
                              decoration: const InputDecoration(labelText: 'ค้นหาลูกค้า (รหัส หรือ ชื่อ)', border: OutlineInputBorder()),
                              validator: (value) => _selectedCustomer == null ? 'กรุณาเลือกลูกค้า' : null,
                            ),
                            if (_isCustomerLoading) const Padding(padding: EdgeInsets.symmetric(vertical: 8.0), child: LinearProgressIndicator()),
                            if (_customerSearchResults.isNotEmpty)
                              SizedBox(
                                height: 200,
                                child: ListView.builder(
                                  itemCount: _customerSearchResults.length,
                                  itemBuilder: (context, index) {
                                    final customer = _customerSearchResults[index];
                                    return ListTile(
                                      title: Text(customer.name),
                                      subtitle: Text(customer.customerId),
                                      onTap: () {
                                        setState(() {
                                          _selectedCustomer = customer;
                                          _customerSearchResults = [];
                                          _customerSearchController.clear();
                                          FocusScope.of(context).unfocus();
                                        });
                                      },
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _titleController,
                        decoration: const InputDecoration(labelText: 'หัวข้อ', border: OutlineInputBorder()),
                        validator: (value) => (value == null || value.isEmpty) ? 'กรุณากรอกหัวข้อ' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _detailsController,
                        decoration: const InputDecoration(labelText: 'รายละเอียด', border: OutlineInputBorder()),
                        maxLines: 4,
                        validator: (value) => (value == null || value.isEmpty) ? 'กรุณากรอกรายละเอียด' : null,
                      ),
                      const SizedBox(height: 16),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('วันที่และเวลานัดหมาย'),
                        subtitle: Text(DateFormat('dd/MM/yyyy HH:mm', 'th_TH').format(_selectedDateTime)),
                        trailing: const Icon(Icons.calendar_today),
                        onTap: () async {
                          final date = await showDatePicker(context: context, initialDate: _selectedDateTime, firstDate: DateTime(2020), lastDate: DateTime(2100));
                          if (date == null) return;
                          final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_selectedDateTime));
                          if (time == null) return;
                          setState(() {
                            _selectedDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton.icon(onPressed: () => _pickImage(ImageSource.gallery), icon: const Icon(Icons.photo_library), label: const Text('เลือกรูป')),
                          ElevatedButton.icon(onPressed: () => _pickImage(ImageSource.camera), icon: const Icon(Icons.camera_alt), label: const Text('ถ่ายรูป')),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8.0,
                        runSpacing: 8.0,
                        children: [
                          ..._existingImageUrls.map((url) => Image.network(url, width: 100, height: 100, fit: BoxFit.cover)),
                          ..._selectedImages.map((file) => kIsWeb
                            ? FutureBuilder<Uint8List>(
                                future: file.readAsBytes(),
                                builder: (context, snapshot) {
                                  if (!snapshot.hasData) return const SizedBox(width: 100, height: 100, child: Center(child: CircularProgressIndicator()));
                                  return Image.memory(snapshot.data!, width: 100, height: 100, fit: BoxFit.cover);
                                },
                              )
                            : Image.file(File(file.path), width: 100, height: 100, fit: BoxFit.cover)),
                        ],
                      )
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
