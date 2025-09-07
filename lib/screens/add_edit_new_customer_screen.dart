// lib/screens/add_edit_new_customer_screen.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:salewang/models/new_customer_prospect.dart';
import 'package:flutter/services.dart';

// Helper class to hold contact information
class ContactInfo {
  final TextEditingController nicknameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
}

// Custom TextInputFormatter for phone numbers (e.g., 081-234-5678)
class PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text.replaceAll(RegExp(r'\D'), '');
    var newText = '';

    if (text.isNotEmpty) {
      if (text.length > 3) {
        newText += '${text.substring(0, 3)}-';
        if (text.length > 6) {
          newText += '${text.substring(3, 6)}-';
          newText += text.substring(6, text.length > 10 ? 10 : text.length);
        } else {
          newText += text.substring(3);
        }
      } else {
        newText += text;
      }
    }

    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}


class AddEditNewCustomerScreen extends StatefulWidget {
  final NewCustomerProspect? prospect;
  const AddEditNewCustomerScreen({super.key, this.prospect});

  @override
  State<AddEditNewCustomerScreen> createState() =>
      _AddEditNewCustomerScreenState();
}

class _AddEditNewCustomerScreenState extends State<AddEditNewCustomerScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers for various fields
  final _storeNameController = TextEditingController();
  final _branchController = TextEditingController();
  final _houseNumberController = TextEditingController();
  final _mooController = TextEditingController();
  final _roadController = TextEditingController();
  final _soiController = TextEditingController();
  final _paymentDueDateController = TextEditingController();
  final _detailsController = TextEditingController();
  final _notesController = TextEditingController();
  final _salespersonController = TextEditingController();
  final _salesSupportController = TextEditingController();
  final _previousSupplierController = TextEditingController();

  final _deliveryHouseNumberController = TextEditingController();
  final _deliveryMooController = TextEditingController();
  final _deliveryRoadController = TextEditingController();
  final _deliverySoiController = TextEditingController();

  // State variables
  String _storeStatus = 'ร้านใหม่';
  DateTime? _openingDate;
  String? _selectedPaymentTerm;
  TimeOfDay? _openingTime;
  TimeOfDay? _closingTime;
  TimeOfDay? _deliveryTime;

  final Map<String, bool> _deliveryDays = {
    'จันทร์': false, 'อังคาร': false, 'พุธ': false, 'พฤหัสบดี': false, 
    'ศุกร์': false, 'เสาร์': false, 'อาทิตย์': false,
  };


  // Contact controllers
  final _ownerContact = ContactInfo();
  final _pharmacistContact = ContactInfo();
  final _purchaserContact = ContactInfo();

  // Address data and state
  Map<String, dynamic> _addressData = {};
  List<String> _provinces = [];
  List<String> _districts = [];
  List<String> _zipcodes = [];
  String? _selectedProvince;
  String? _selectedDistrict;
  String? _selectedZipcode;

  List<String> _deliveryProvinces = [];
  List<String> _deliveryDistricts = [];
  List<String> _deliveryZipcodes = [];
  String? _selectedDeliveryProvince;
  String? _selectedDeliveryDistrict;
  String? _selectedDeliveryZipcode;

  bool _isSaving = false;

  // Image and file holders
  final Map<String, XFile?> _images = {
    'location': null,
    'storefront': null,
    'pharmacist': null,
    'other': null,
  };
  final Map<String, dynamic> _documents = {
    'id_card': null,
    'house_reg': null,
    'pharmacy_license': null,
    'pharmacist_license': null,
  };
  
  // Web image bytes for preview
  final Map<String, Uint8List?> _webImageBytes = {};
  final Map<String, Uint8List?> _webDocumentBytes = {};
  
  // To store existing URLs when editing
  Map<String, String?> _existingImageUrls = {};
  Map<String, String?> _existingDocumentUrls = {};


  @override
  void initState() {
    super.initState();
    // Load address data first, then load prospect data if it exists
    _loadAddressData().then((_) {
      if (widget.prospect != null) {
        _loadProspectData(widget.prospect!);
      }
    });
  }

  @override
  void dispose() {
    // Dispose all controllers
    _storeNameController.dispose();
    _branchController.dispose();
    _houseNumberController.dispose();
    _mooController.dispose();
    _roadController.dispose();
    _soiController.dispose();
    _paymentDueDateController.dispose();
    _detailsController.dispose();
    _notesController.dispose();
    _salespersonController.dispose();
    _salesSupportController.dispose();
    _previousSupplierController.dispose();
    _deliveryHouseNumberController.dispose();
    _deliveryMooController.dispose();
    _deliveryRoadController.dispose();
    _deliverySoiController.dispose();
    _ownerContact.nicknameController.dispose();
    _ownerContact.phoneController.dispose();
    _pharmacistContact.nicknameController.dispose();
    _pharmacistContact.phoneController.dispose();
    _purchaserContact.nicknameController.dispose();
    _purchaserContact.phoneController.dispose();
    super.dispose();
  }

  // NEW: Function to load existing data into the form for editing
  void _loadProspectData(NewCustomerProspect prospect) {
    final data = prospect.rawData;
    
    // Use setState to update the UI with the loaded data
    setState(() {
      // Basic Info
      _storeStatus = data['status'] ?? 'ร้านใหม่';
      if (data['openingDate'] != null) {
        _openingDate = (data['openingDate'] as Timestamp).toDate();
      }
      _previousSupplierController.text = data['previousSupplier'] ?? '';
      
      // Store Info
      _storeNameController.text = data['storeInfo']?['name'] ?? '';
      _branchController.text = data['storeInfo']?['branch'] ?? '';

      // Store Address
      final storeAddr = data['storeAddress'] ?? {};
      _houseNumberController.text = storeAddr['houseNumber'] ?? '';
      _mooController.text = storeAddr['moo'] ?? '';
      _roadController.text = storeAddr['road'] ?? '';
      _soiController.text = storeAddr['soi'] ?? '';
      if (storeAddr['province'] != null && _provinces.contains(storeAddr['province'])) {
        _selectedProvince = storeAddr['province'];
        _districts = _addressData[_selectedProvince!]!.keys.toList()..sort();
        if (storeAddr['district'] != null && _districts.contains(storeAddr['district'])) {
          _selectedDistrict = storeAddr['district'];
          _zipcodes = List<String>.from(_addressData[_selectedProvince]![_selectedDistrict] as List);
          if (storeAddr['zipcode'] != null && _zipcodes.contains(storeAddr['zipcode'])) {
            _selectedZipcode = storeAddr['zipcode'];
          }
        }
      }
      
      // Contacts
      final contacts = data['contacts'] ?? {};
      _ownerContact.nicknameController.text = contacts['owner']?['nickname'] ?? '';
      _ownerContact.phoneController.text = contacts['owner']?['phone'] ?? '';
      _pharmacistContact.nicknameController.text = contacts['pharmacist']?['nickname'] ?? '';
      _pharmacistContact.phoneController.text = contacts['pharmacist']?['phone'] ?? '';
      _purchaserContact.nicknameController.text = contacts['purchaser']?['nickname'] ?? '';
      _purchaserContact.phoneController.text = contacts['purchaser']?['phone'] ?? '';
      
      // Payment Info
      final paymentInfo = data['paymentInfo'] ?? {};
      _selectedPaymentTerm = paymentInfo['term'];
      _paymentDueDateController.text = paymentInfo['dueDate'] ?? '';

      // Additional Info
      final additionalInfo = data['additionalInfo'] ?? {};
      _detailsController.text = additionalInfo['details'] ?? '';
      _notesController.text = additionalInfo['notes'] ?? '';
      _openingTime = _timeOfDayFromString(additionalInfo['openingTime']);
      _closingTime = _timeOfDayFromString(additionalInfo['closingTime']);

      // Delivery Info
      final deliveryInfo = data['deliveryInfo'] ?? {};
      final deliveryDaysList = List<String>.from(deliveryInfo['days'] ?? []);
      for (var day in deliveryDaysList) {
        if (_deliveryDays.containsKey(day)) {
          _deliveryDays[day] = true;
        }
      }
      _deliveryTime = _timeOfDayFromString(deliveryInfo['time']);
      final deliveryAddr = deliveryInfo['address'] ?? {};
      _deliveryHouseNumberController.text = deliveryAddr['houseNumber'] ?? '';
      _deliveryMooController.text = deliveryAddr['moo'] ?? '';
      _deliveryRoadController.text = deliveryAddr['road'] ?? '';
      _deliverySoiController.text = deliveryAddr['soi'] ?? '';
       if (deliveryAddr['province'] != null && _deliveryProvinces.contains(deliveryAddr['province'])) {
        _selectedDeliveryProvince = deliveryAddr['province'];
        _deliveryDistricts = _addressData[_selectedDeliveryProvince!]!.keys.toList()..sort();
        if (deliveryAddr['district'] != null && _deliveryDistricts.contains(deliveryAddr['district'])) {
          _selectedDeliveryDistrict = deliveryAddr['district'];
          _deliveryZipcodes = List<String>.from(_addressData[_selectedDeliveryProvince]![_selectedDeliveryDistrict] as List);
           if (deliveryAddr['zipcode'] != null && _deliveryZipcodes.contains(deliveryAddr['zipcode'])) {
            _selectedDeliveryZipcode = deliveryAddr['zipcode'];
          }
        }
      }

      // Staff Info
      final staffInfo = data['staffInfo'] ?? {};
      _salespersonController.text = staffInfo['salesperson'] ?? '';
      _salesSupportController.text = staffInfo['salesSupport'] ?? '';

      // Files
      _existingImageUrls = Map<String, String?>.from(data['categorizedImageUrls'] ?? {});
      _existingDocumentUrls = Map<String, String?>.from(data['categorizedDocumentUrls'] ?? {});
    });
  }

  // Helper to convert "HH:mm" string back to TimeOfDay
  TimeOfDay? _timeOfDayFromString(String? timeString) {
    if (timeString == null || !timeString.contains(':')) return null;
    try {
      final parts = timeString.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (e) {
      return null;
    }
  }


  Future<void> _loadAddressData() async {
    try {
      final String jsonString =
          await rootBundle.loadString('assets/thailand_provinces.json');
      final data = json.decode(jsonString);
      if(mounted) {
        setState(() {
          _addressData = data;
          _provinces = _addressData.keys.toList()..sort();
          _deliveryProvinces = List.from(_provinces);
        });
      }
    } catch (e) {
      if(mounted){
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่สามารถโหลดข้อมูลที่อยู่ได้'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _onProvinceChanged(String? newValue, {bool isDelivery = false}) {
    if (newValue == null) return;
    setState(() {
      if (isDelivery) {
        _selectedDeliveryProvince = newValue;
        _selectedDeliveryDistrict = null;
        _selectedDeliveryZipcode = null;
        _deliveryDistricts = _addressData[newValue]!.keys.toList()..sort();
        _deliveryZipcodes = [];
      } else {
        _selectedProvince = newValue;
        _selectedDistrict = null;
        _selectedZipcode = null;
        _districts = _addressData[newValue]!.keys.toList()..sort();
        _zipcodes = [];
      }
    });
  }

  void _onDistrictChanged(String? newValue, {bool isDelivery = false}) {
     if (newValue == null) return;
    setState(() {
      if (isDelivery) {
        _selectedDeliveryDistrict = newValue;
        _selectedDeliveryZipcode = null;
        _deliveryZipcodes = List<String>.from(
            _addressData[_selectedDeliveryProvince]![newValue] as List);
      } else {
        _selectedDistrict = newValue;
        _selectedZipcode = null;
        _zipcodes =
            List<String>.from(_addressData[_selectedProvince]![newValue] as List);
      }
    });
  }

  Future<void> _pickTime(BuildContext context,
      {required bool isOpening, bool isDelivery = false}) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) {
        return Localizations.override(
          context: context,
          locale: const Locale('th', 'TH'),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isDelivery) {
          _deliveryTime = picked;
        } else if (isOpening) {
          _openingTime = picked;
        } else {
          _closingTime = picked;
        }
      });
    }
  }

  Future<ImageSource?> _showImageSourceActionSheet(BuildContext context) async {
    return await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('เลือกจากคลังภาพ'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('ถ่ายรูปใหม่'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(String key) async {
    final source = await _showImageSourceActionSheet(context);
    if (source == null) return;

    final picker = ImagePicker();
    final XFile? pickedFile =
        await picker.pickImage(source: source, imageQuality: 70);
    if (pickedFile != null) {
      if (kIsWeb) {
        _webImageBytes[key] = await pickedFile.readAsBytes();
      }
      setState(() {
        _images[key] = pickedFile;
      });
    }
  }

  Future<void> _pickDocument(String key) async {
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('ถ่ายรูปเอกสาร'),
              onTap: () => Navigator.of(context).pop('camera'),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('เลือกไฟล์จากเครื่อง'),
              onTap: () => Navigator.of(context).pop('file'),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    if (source == 'camera') {
      final picker = ImagePicker();
      final XFile? pickedFile = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
      if (pickedFile != null) {
        if (kIsWeb) {
          _webDocumentBytes[key] = await pickedFile.readAsBytes();
        }
        setState(() {
          _documents[key] = pickedFile;
        });
      }
    } else if (source == 'file') {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      );
      if (result != null) {
        if (kIsWeb) {
          _webDocumentBytes[key] = result.files.first.bytes;
        }
        setState(() {
          _documents[key] = result.files.first;
        });
      }
    }
  }

  Future<String?> _uploadFile(dynamic file, String path) async {
    if (file == null) return null;
    final ref = FirebaseStorage.instance.ref(path);
    try {
      if (kIsWeb) {
        Uint8List? fileBytes;
        if (file is XFile) {
          fileBytes = await file.readAsBytes();
        } else if (file is PlatformFile) {
          fileBytes = file.bytes;
        }
        if (fileBytes != null) {
          await ref.putData(fileBytes);
        } else {
          throw Exception("File bytes are null for web upload.");
        }
      } else {
        final String? filePath = (file is XFile) ? file.path : (file as PlatformFile).path;
         if (filePath != null) {
           await ref.putFile(File(filePath));
         } else {
           throw Exception("File path is null for mobile upload.");
         }
      }
      return await ref.getDownloadURL();
    } catch (e) {
      print('Error uploading file to $path: $e');
      return null;
    }
  }

  Future<void> _saveProspect() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกข้อมูลที่บังคับให้ครบถ้วน'), backgroundColor: Colors.red),
      );
      return;
    }
    
    if (_ownerContact.phoneController.text.isEmpty &&
        _pharmacistContact.phoneController.text.isEmpty &&
        _purchaserContact.phoneController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกข้อมูลผู้ติดต่ออย่างน้อย 1 ท่าน'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSaving = true);
    final user = FirebaseAuth.instance.currentUser!;

    try {
      final collection = FirebaseFirestore.instance.collection('new_customer_prospects');
      
      final isEditing = widget.prospect != null;
      final docId = isEditing ? widget.prospect!.id : 'C${(((await collection.count().get()).count ?? 0) + 1).toString().padLeft(5, '0')}';

      final Map<String, String?> categorizedImageUrls = Map.from(_existingImageUrls);
      for (var key in _images.keys) {
        if(_images[key] != null) {
          categorizedImageUrls[key] = await _uploadFile(_images[key], 'new_customer_prospects/$docId/images/$key.jpg');
        }
      }
      final Map<String, String?> categorizedDocumentUrls = Map.from(_existingDocumentUrls);
      for (var key in _documents.keys) {
         if(_documents[key] != null) {
          final fileName = _documents[key] is XFile ? (_documents[key] as XFile).name : (_documents[key] as PlatformFile).name;
          categorizedDocumentUrls[key] = await _uploadFile(_documents[key], 'new_customer_prospects/$docId/documents/$fileName');
        }
      }

      final selectedDays = _deliveryDays.entries.where((e) => e.value).map((e) => e.key).toList();

      final data = {
        'tempId': isEditing ? widget.prospect!.tempId : docId,
        'status': _storeStatus,
        'openingDate': _storeStatus == 'ร้านใหม่' && _openingDate != null ? Timestamp.fromDate(_openingDate!) : null,
        'previousSupplier': _storeStatus == 'ร้านเก่าลูกค้าใหม่' ? _previousSupplierController.text : null,
        'storeInfo': {'name': _storeNameController.text, 'branch': _branchController.text},
        'storeAddress': {
          'houseNumber': _houseNumberController.text, 'moo': _mooController.text, 'road': _roadController.text,
          'soi': _soiController.text, 'province': _selectedProvince, 'district': _selectedDistrict, 'zipcode': _selectedZipcode,
        },
        'contacts': {
          'owner': {'nickname': _ownerContact.nicknameController.text, 'phone': _ownerContact.phoneController.text},
          'pharmacist': {'nickname': _pharmacistContact.nicknameController.text, 'phone': _pharmacistContact.phoneController.text},
          'purchaser': {'nickname': _purchaserContact.nicknameController.text, 'phone': _purchaserContact.phoneController.text},
        },
        'paymentInfo': {'term': _selectedPaymentTerm, 'dueDate': _paymentDueDateController.text},
        'additionalInfo': {
          'details': _detailsController.text, 'notes': _notesController.text,
          'openingTime': _openingTime?.format(context), 'closingTime': _closingTime?.format(context),
        },
        'deliveryInfo': {
          'days': selectedDays, 'time': _deliveryTime?.format(context),
          'address': {
            'houseNumber': _deliveryHouseNumberController.text, 'moo': _deliveryMooController.text, 'road': _deliveryRoadController.text,
            'soi': _deliverySoiController.text, 'province': _selectedDeliveryProvince, 'district': _selectedDeliveryDistrict, 'zipcode': _selectedDeliveryZipcode,
          }
        },
        'categorizedImageUrls': categorizedImageUrls,
        'categorizedDocumentUrls': categorizedDocumentUrls,
        'staffInfo': {'salesperson': _salespersonController.text, 'salesSupport': _salesSupportController.text},
        'createdAt': isEditing ? widget.prospect!.createdAt : FieldValue.serverTimestamp(),
        'createdBy': isEditing ? widget.prospect!.createdBy : (user.displayName ?? user.email),
        'approvalStatus': isEditing ? widget.prospect!.approvalStatus : 'pending',
      };
      
      await collection.doc(docId).set(data, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกข้อมูลสำเร็จ!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }

    } catch (e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาดในการบันทึก: $e'), backgroundColor: Colors.red,));
      }
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
          title: Text(widget.prospect == null ? 'บันทึกลูกค้าใหม่' : 'แก้ไขข้อมูล',
              style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.save),
              onPressed: _isSaving ? null : _saveProspect,
            )
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSectionCard(title: 'ข้อมูลร้านค้า', children: [
                const Text('สถานะร้านค้า', style: TextStyle(fontWeight: FontWeight.bold)),
                RadioListTile<String>(
                  title: const Text('ร้านใหม่'),
                  value: 'ร้านใหม่',
                  groupValue: _storeStatus,
                  onChanged: (v) => setState(() => _storeStatus = v!),
                ),
                if (_storeStatus == 'ร้านใหม่')
                  ListTile(
                    title: Text(
                        'จะเปิดภายในวันที่: ${_openingDate == null ? 'กรุณาเลือก' : DateFormat('dd/MM/yyyy').format(_openingDate!)}'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final pickedDate = await showDatePicker(
                          context: context,
                          initialDate: _openingDate ?? DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2100));
                      if (pickedDate != null) {
                        setState(() => _openingDate = pickedDate);
                      }
                    },
                  ),
                RadioListTile<String>(
                  title: const Text('ร้านเก่าลูกค้าใหม่'),
                  value: 'ร้านเก่าลูกค้าใหม่',
                  groupValue: _storeStatus,
                  onChanged: (v) => setState(() => _storeStatus = v!),
                ),
                 if (_storeStatus == 'ร้านเก่าลูกค้าใหม่')
                  _buildTextField(controller: _previousSupplierController, label: 'เดิมซื้อกับยี่ปั้วไหน'),
                const Divider(height: 20),
                _buildTextField(
                    controller: _storeNameController,
                    label: 'ชื่อร้านค้า',
                    isRequired: true),
                _buildTextField(controller: _branchController, label: 'สาขา'),
                const SizedBox(height: 8),
                const Text('ที่อยู่ร้านค้า', style: TextStyle(fontWeight: FontWeight.bold)),
                _buildAddressFields(isDelivery: false),
              ]),
              _buildSectionCard(title: 'ข้อมูลผู้ติดต่อ (กรอกอย่างน้อย 1 ท่าน)', children: [
                _buildContactGroup('เจ้าของร้าน', _ownerContact),
                _buildContactGroup('เภสัชกร', _pharmacistContact),
                _buildContactGroup('ผู้สั่งซื้อยา', _purchaserContact),
              ]),
               _buildSectionCard(title: 'ข้อมูลการชำระเงิน', children: [
                 _buildDropdownField(
                  label: 'การชำระเงิน',
                  value: _selectedPaymentTerm,
                  items: ['เงินสด', '3 วัน', '7 วัน', '30 วัน', '1 เดือน', '2 เดือน'],
                  onChanged: (val) => setState(() => _selectedPaymentTerm = val),
                  isRequired: true,
                ),
                _buildTextField(controller: _paymentDueDateController, label: 'สะดวกชำระเงินทุกวันที่...ของเดือน'),
              ]),
              _buildSectionCard(title: 'รายละเอียดลูกค้า (เพิ่มเติม)', children: [
                _buildTextField(controller: _detailsController, label: 'รายละเอียด', maxLines: 3, isRequired: true),
                _buildTextField(controller: _notesController, label: 'หมายเหตุ', maxLines: 2, isRequired: true),
                _buildTimePickerRow('เวลาเปิด-ปิดร้าน:', _openingTime, _closingTime, () => _pickTime(context, isOpening: true), () => _pickTime(context, isOpening: false)),
                const SizedBox(height: 16),
                const Text('ข้อมูลการจัดส่ง', style: TextStyle(fontWeight: FontWeight.bold)),
                _buildDeliveryDayPicker(),
                ListTile(
                  title: Text('เวลาจัดส่ง: ${_deliveryTime == null ? 'เลือกเวลา' : _deliveryTime!.format(context)}'),
                  trailing: const Icon(Icons.access_time),
                  onTap: () => _pickTime(context, isOpening: false, isDelivery: true),
                ),
                const SizedBox(height: 8),
                const Text('สถานที่จัดส่งสินค้า', style: TextStyle(fontWeight: FontWeight.bold)),
                 _buildAddressFields(isDelivery: true),
              ]),
              _buildSectionCard(title: 'รูปภาพ', children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildImagePickerButton('สถานที่', 'location'),
                    _buildImagePickerButton('หน้าร้าน', 'storefront'),
                    _buildImagePickerButton('เภสัชกร', 'pharmacist'),
                    _buildImagePickerButton('อื่นๆ', 'other'),
                  ],
                )
              ]),
              _buildSectionCard(title: 'เอกสารแนบ (PDF หรือ รูปภาพ)', children: [
                _buildDocumentPickerButton('สำเนาบัตรประชาชน', 'id_card'),
                _buildDocumentPickerButton('สำเนาทะเบียนบ้าน', 'house_reg'),
                _buildDocumentPickerButton('ใบอนุญาตขายยา (ข.ย.)', 'pharmacy_license'),
                _buildDocumentPickerButton('สำเนาใบประกอบฯ', 'pharmacist_license'),
              ]),
              _buildSectionCard(title: 'ผู้ดูแล', children: [
                _buildTextField(controller: _salespersonController, label: 'รหัสพนักงานขาย', keyboardType: TextInputType.number),
                _buildTextField(controller: _salesSupportController, label: 'รหัสเซลล์ซัพพอร์ท', keyboardType: TextInputType.number),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  // Helper Widgets
  Widget _buildSectionCard({required String title, required List<Widget> children}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const Divider(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({required TextEditingController controller, required String label, bool isRequired = false, int maxLines = 1, TextInputType? keyboardType, List<TextInputFormatter>? inputFormatters}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        maxLines: maxLines,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        validator: (value) {
          if (isRequired && (value == null || value.isEmpty)) {
            return 'กรุณากรอกข้อมูล';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildAddressFields({required bool isDelivery}) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildTextField(controller: isDelivery ? _deliveryHouseNumberController : _houseNumberController, label: 'บ้านเลขที่')),
            const SizedBox(width: 8),
            Expanded(child: _buildTextField(controller: isDelivery ? _deliveryMooController : _mooController, label: 'หมู่ที่')),
          ],
        ),
        Row(
          children: [
            Expanded(child: _buildTextField(controller: isDelivery ? _deliveryRoadController : _roadController, label: 'ถนน')),
            const SizedBox(width: 8),
            Expanded(child: _buildTextField(controller: isDelivery ? _deliverySoiController : _soiController, label: 'ซอย')),
          ],
        ),
        _buildDropdownField(
          label: 'จังหวัด',
          value: isDelivery ? _selectedDeliveryProvince : _selectedProvince,
          items: isDelivery ? _deliveryProvinces : _provinces,
          onChanged: (val) => _onProvinceChanged(val, isDelivery: isDelivery),
          isRequired: true,
        ),
        _buildDropdownField(
          label: 'อำเภอ',
          value: isDelivery ? _selectedDeliveryDistrict : _selectedDistrict,
          items: isDelivery ? _deliveryDistricts : _districts,
          onChanged: (val) => _onDistrictChanged(val, isDelivery: isDelivery),
          isRequired: true,
        ),
        _buildDropdownField(
          label: 'รหัสไปรษณีย์',
          value: isDelivery ? _selectedDeliveryZipcode : _selectedZipcode,
          items: isDelivery ? _deliveryZipcodes : _zipcodes,
          onChanged: (val) => setState(() => isDelivery ? _selectedDeliveryZipcode = val : _selectedZipcode = val),
          isRequired: true,
        ),
      ],
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    bool isRequired = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: DropdownButtonFormField<String>(
        value: value,
        items: items.map((String item) {
          return DropdownMenuItem<String>(value: item, child: Text(item));
        }).toList(),
        onChanged: onChanged,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        validator: (value) {
          if (isRequired && value == null) {
            return 'กรุณาเลือกข้อมูล';
          }
          return null;
        },
      ),
    );
  }

   Widget _buildContactGroup(String title, ContactInfo contact) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          Row(
            children: [
              Expanded(flex: 2, child: _buildTextField(controller: contact.nicknameController, label: 'ชื่อเล่น')),
              const SizedBox(width: 8),
              Expanded(
                flex: 3, 
                child: _buildTextField(
                  controller: contact.phoneController, 
                  label: 'เบอร์โทรศัพท์', 
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    PhoneInputFormatter(),
                  ],
                )
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildTimePickerRow(String label, TimeOfDay? startTime, TimeOfDay? endTime, VoidCallback onStartTap, VoidCallback onEndTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(label)),
          Expanded(
            flex: 3,
            child: InkWell(
              onTap: onStartTap,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(4)),
                child: Text(startTime?.format(context) ?? 'เลือกเวลา'),
              ),
            ),
          ),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('-')),
          Expanded(
            flex: 3,
            child: InkWell(
              onTap: onEndTap,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(4)),
                child: Text(endTime?.format(context) ?? 'เลือกเวลา'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryDayPicker() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('วันสะดวกในการจัดส่ง (เลือกได้หลายวัน)', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8.0,
            runSpacing: 4.0,
            children: _deliveryDays.keys.map((String day) {
              return ChoiceChip(
                label: Text(day),
                selected: _deliveryDays[day]!,
                onSelected: (bool selected) {
                  setState(() {
                    _deliveryDays[day] = selected;
                  });
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePickerButton(String label, String key) {
    final hasExistingImage = _existingImageUrls[key] != null;
    final hasNewImage = _images[key] != null;
    
    ImageProvider? imageProvider;
    if (hasNewImage) {
      imageProvider = kIsWeb 
        ? MemoryImage(_webImageBytes[key]!) 
        : FileImage(File(_images[key]!.path)) as ImageProvider;
    } else if (hasExistingImage) {
      imageProvider = NetworkImage(_existingImageUrls[key]!);
    }

    return Column(
      children: [
        InkWell(
          onTap: () => _pickImage(key),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(8),
              image: imageProvider != null ? DecorationImage(image: imageProvider, fit: BoxFit.cover) : null,
            ),
            child: imageProvider == null
                ? const Icon(Icons.add_a_photo_outlined, color: Colors.grey)
                : null,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
  
  Widget _buildDocumentPickerButton(String label, String key) {
    final file = _documents[key];
    final existingUrl = _existingDocumentUrls[key];
    final hasFile = file != null || existingUrl != null;

    final fileName = file is XFile ? file.name : (file is PlatformFile ? file.name : (existingUrl != null ? 'ไฟล์ที่มีอยู่' : 'ยังไม่ได้เลือกไฟล์'));
    final isImage = file != null && (file.name.endsWith('.jpg') || file.name.endsWith('.jpeg') || file.name.endsWith('.png')) || (existingUrl?.contains('.jpg') ?? false) || (existingUrl?.contains('.jpeg') ?? false) || (existingUrl?.contains('.png') ?? false);

    return Card(
      elevation: 1,
      child: ListTile(
        leading: isImage
          ? (file != null ? (kIsWeb ? Image.memory(_webDocumentBytes[key]!, width: 40, height: 40, fit: BoxFit.cover) : Image.file(File(file.path!), width: 40, height: 40, fit: BoxFit.cover)) : Image.network(existingUrl!, width: 40, height: 40, fit: BoxFit.cover))
          : Icon(hasFile ? Icons.picture_as_pdf : Icons.attach_file, color: hasFile ? Colors.red : Colors.grey),
        title: Text(label),
        subtitle: Text(fileName, overflow: TextOverflow.ellipsis),
        trailing: Icon(hasFile ? Icons.check_circle : Icons.add_circle_outline, color: hasFile ? Colors.green : Colors.grey),
        onTap: () => _pickDocument(key),
      ),
    );
  }
}
