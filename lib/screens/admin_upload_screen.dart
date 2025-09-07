// lib/screens/admin_upload_screen.dart

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:salewang/models/bill_history.dart';
import 'package:salewang/models/purchase.dart';
import 'package:salewang/models/purchase_order.dart';
import 'package:salewang/models/rebate.dart'; // Import the new Rebate model
import 'dart:convert';

class AdminUploadScreen extends StatefulWidget {
  const AdminUploadScreen({super.key});

  @override
  State<AdminUploadScreen> createState() => _AdminUploadScreenState();
}

class _AdminUploadScreenState extends State<AdminUploadScreen> {
  final ValueNotifier<double> _progressNotifier = ValueNotifier(0.0);
  final ValueNotifier<String> _statusNotifier = ValueNotifier('');
  bool _isUploading = false;

  PlatformFile? _customerFile;
  PlatformFile? _orderFile;
  PlatformFile? _billFile;
  PlatformFile? _priceFile;
  PlatformFile? _stockFile;
  PlatformFile? _purchaseFile;
  PlatformFile? _poFile;
  PlatformFile? _rebateFile; // State for rebate file

  Future<PlatformFile?> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx'],
    );
    return result?.files.first;
  }

  Future<List<Map<String, dynamic>>?> _processFile(PlatformFile file) async {
    final extension = file.extension?.toLowerCase();
    List<List<dynamic>> rows;

    if (extension == 'csv') {
      final csvString = utf8.decode(file.bytes!);
      rows = const CsvToListConverter(eol: '\n', fieldDelimiter: ',').convert(csvString);
    } else if (extension == 'xlsx') {
      var bytes = file.bytes!;
      var excel = Excel.decodeBytes(bytes);
      var sheet = excel.tables.keys.first;
      rows = excel.tables[sheet]!.rows;
    } else {
      _showSnackBar('ไฟล์ประเภทนี้ไม่รองรับ กรุณาใช้ .csv หรือ .xlsx', isError: true);
      return null;
    }

    if (rows.length < 2) throw Exception('ไฟล์ไม่มีข้อมูล');

    final headers = rows[0].map((cell) {
      final headerValue = (cell is Data) ? cell.value?.toString() : cell?.toString();
      return (headerValue ?? '').trim();
    }).toList();
    
    final List<Map<String, dynamic>> dataList = [];

    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.where((cell) => cell != null && cell.toString().trim().isNotEmpty).isEmpty) {
        continue;
      }
      
      final Map<String, dynamic> data = {};
      for (int j = 0; j < headers.length; j++) {
        final header = headers[j];
        final cell = (j < row.length) ? row[j] : null;
        final cellValue = (cell is Data) ? cell.value : cell;
        data[header] = cellValue?.toString().trim() ?? '';
      }
      dataList.add(data);
    }
    return dataList;
  }
  
  // --- REVISED AND CORRECTED REBATE UPLOAD LOGIC ---
  Future<void> _startRebateUpload(PlatformFile? file) async {
    if (file == null) {
      _showSnackBar('กรุณาเลือกไฟล์ข้อมูลรีเบทก่อน', isError: true);
      return;
    }
    setState(() => _isUploading = true);
    _showProgressDialog();

    try {
      _statusNotifier.value = 'กำลังลบข้อมูลรีเบทเก่า...';
      await _deleteCollection(FirebaseFirestore.instance.collection('rebate'));
      _statusNotifier.value = 'ลบข้อมูลเก่าสำเร็จ!';

      _statusNotifier.value = 'กำลังอ่านข้อมูลจากไฟล์...';
      final dataList = await _processFile(file);
      if (dataList == null || dataList.isEmpty) {
        throw Exception('ไม่พบข้อมูลในไฟล์');
      }

      final firestore = FirebaseFirestore.instance;
      final collectionRef = firestore.collection('rebate');
      final totalItems = dataList.length;
      const batchSize = 400; // Firestore batch write limit is 500

      _statusNotifier.value = 'กำลังเตรียมข้อมูลเพื่ออัปโหลด...';

      for (int i = 0; i < totalItems; i += batchSize) {
        var batch = firestore.batch();
        final end = (i + batchSize > totalItems) ? totalItems : i + batchSize;

        for (int j = i; j < end; j++) {
          final rowData = dataList[j];
          final rebateData = RebateData.fromMap(rowData);
          
          if (rebateData.customerId.isNotEmpty) {
            // --- FIX: Sanitize the customer ID to replace '/' with '-' ---
            final sanitizedDocId = rebateData.customerId.replaceAll('/', '-');
            final docRef = collectionRef.doc(sanitizedDocId);
            batch.set(docRef, rebateData.toMap());
          }
        }
        
        _statusNotifier.value = 'กำลังอัปโหลดข้อมูลรีเบท... (${(end / totalItems * 100).toStringAsFixed(0)}%)';
        await batch.commit();
        _progressNotifier.value = end / totalItems;
      }

      if (mounted) Navigator.of(context).pop();
      _showSnackBar('อัปโหลดข้อมูลรีเบท $totalItems รายการสำเร็จ!', isError: false);

    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      _showSnackBar('เกิดข้อผิดพลาด (Rebate Upload): ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // --- Other existing upload functions (unchanged) ---
  
  Future<void> _startCustomerUpload(PlatformFile? file) async {
    if (file == null) {
      _showSnackBar('กรุณาเลือกไฟล์ข้อมูลลูกค้าก่อน', isError: true);
      return;
    }
    setState(() => _isUploading = true);
    _showProgressDialog();

    try {
      _statusNotifier.value = 'กำลังอ่านข้อมูลจากไฟล์...';
      final dataList = await _processFile(file);
      if (dataList == null || dataList.isEmpty) throw Exception('ไม่พบข้อมูลในไฟล์');

      _statusNotifier.value = 'กำลังตรวจสอบข้อมูลผู้ติดต่อเดิม...';
      final firestore = FirebaseFirestore.instance;
      final customersRef = firestore.collection('customers');
      
      final allFileCustomerIds = dataList
          .map((data) => data['รหัสลูกค้า']?.toString().trim().replaceAll('/', '-'))
          .where((id) => id != null && id.isNotEmpty)
          .toSet()
          .toList();

      final Map<String, List<dynamic>> existingContactsMap = {};
      for (var i = 0; i < allFileCustomerIds.length; i += 30) {
        final chunk = allFileCustomerIds.sublist(
            i,
            i + 30 > allFileCustomerIds.length
                ? allFileCustomerIds.length
                : i + 30);
        if (chunk.isNotEmpty) {
          final querySnapshot = await customersRef.where(FieldPath.documentId, whereIn: chunk).get();
          for (final doc in querySnapshot.docs) {
            final data = doc.data();
            if (data.containsKey('contacts') && data['contacts'] is List) {
              existingContactsMap[doc.id] = data['contacts'];
            }
          }
        }
      }

      _statusNotifier.value = 'กำลังเตรียมข้อมูลเพื่ออัปโหลด...';
      const batchSize = 400;
      final totalItems = dataList.length;

      for (int i = 0; i < totalItems; i += batchSize) {
        var batch = firestore.batch();
        final end = (i + batchSize > totalItems) ? totalItems : i + batchSize;
        
        for (int j = i; j < end; j++) {
          final fileData = dataList[j];
          final rawDocId = fileData['รหัสลูกค้า']?.toString().trim();
          if (rawDocId != null && rawDocId.isNotEmpty) {
            final sanitizedDocId = rawDocId.replaceAll('/', '-');
            final docRef = customersRef.doc(sanitizedDocId);

            final Map<String, dynamic> newData = Map.from(fileData);
            
            if (existingContactsMap.containsKey(sanitizedDocId)) {
              newData['contacts'] = existingContactsMap[sanitizedDocId];
            } else if (fileData['โทรศัพท์'] != null && fileData['โทรศัพท์'].toString().trim().isNotEmpty) {
              final newContactList = [{
                'name': (fileData['ติดต่อกับ']?.toString() ?? 'เบอร์หลัก').trim(),
                'phone': fileData['โทรศัพท์'].toString().trim(),
              }];
              newData['contacts'] = newContactList;
            } else {
              newData['contacts'] = [];
            }
            
            newData.remove('โทรศัพท์');
            newData.remove('ติดต่อกับ');

            batch.set(docRef, newData, SetOptions(merge: true));
          }
        }
        
        _statusNotifier.value = 'กำลังอัปโหลดข้อมูลลูกค้า... (${(end / totalItems * 100).toStringAsFixed(0)}%)';
        await batch.commit();
        _progressNotifier.value = end / totalItems;
      }
      
      if(mounted) Navigator.of(context).pop();
      _showSnackBar('อัปโหลดข้อมูลลูกค้า $totalItems รายการสำเร็จ!', isError: false);
    } catch (e) {
      if(mounted) Navigator.of(context).pop();
      _showSnackBar('เกิดข้อผิดพลาด (Customer): ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _startGenericUpload(PlatformFile? file, String collectionName, String processName, {bool deleteOld = false}) async {
     if (file == null) {
      _showSnackBar('กรุณาเลือกไฟล์$processNameก่อน', isError: true);
      return;
    }
    setState(() => _isUploading = true);
    _showProgressDialog();

    try {
      if (deleteOld) {
        _statusNotifier.value = 'กำลังลบข้อมูล$processNameเก่า...';
        await _deleteCollection(FirebaseFirestore.instance.collection(collectionName));
        _statusNotifier.value = 'ลบข้อมูลเก่าสำเร็จ!';
      }

      _statusNotifier.value = 'กำลังอ่านข้อมูลจากไฟล์...';
      final dataList = await _processFile(file);
      if (dataList == null || dataList.isEmpty) throw Exception('ไม่พบข้อมูลในไฟล์');

      final firestore = FirebaseFirestore.instance;
      final totalItems = dataList.length;
      const batchSize = 400;

      for (int i = 0; i < totalItems; i += batchSize) {
        var batch = firestore.batch();
        final end = (i + batchSize > totalItems) ? totalItems : i + batchSize;
        
        for (int j = i; j < end; j++) {
          final data = dataList[j];
          final rawDocId = data['รหัสลูกค้า']?.toString().trim() ?? data['รหัสสินค้า']?.toString().trim();
          if (rawDocId != null && rawDocId.isNotEmpty) {
            final sanitizedDocId = rawDocId.replaceAll('/', '-');
            final docRef = firestore.collection(collectionName).doc(sanitizedDocId);
            batch.set(docRef, data, SetOptions(merge: true));
          }
        }
        
        _statusNotifier.value = 'กำลังอัปโหลด$processName... (${(end / totalItems * 100).toStringAsFixed(0)}%)';
        await batch.commit();
        _progressNotifier.value = end / totalItems;
      }
      
      if(mounted) Navigator.of(context).pop();
      _showSnackBar('อัปโหลด$processName $totalItems รายการสำเร็จ!', isError: false);
    } catch (e) {
      if(mounted) Navigator.of(context).pop();
      _showSnackBar('เกิดข้อผิดพลาด ($processName): ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _startBillUpload(PlatformFile? file) async {
    if (file == null) {
      _showSnackBar('กรุณาเลือกไฟล์ประวัติการซื้อก่อน', isError: true);
      return;
    }
    setState(() => _isUploading = true);
    _showProgressDialog();
    try {
      _statusNotifier.value = 'กำลังอ่านข้อมูลจากไฟล์...';
      final dataList = await _processFile(file);
      if (dataList == null || dataList.isEmpty) throw Exception('ไม่พบข้อมูลในไฟล์');

      _statusNotifier.value = 'กำลังรวมข้อมูลบิล...';
      final Map<String, List<Map<String, dynamic>>> groupedBills = {};
      for (final row in dataList) {
        final customerId = row['รหัสลูกหนี้']?.toString() ?? '';
        final invoiceNumber = row['เลขที่ใบกำกับ']?.toString() ?? '';
        if (customerId.isNotEmpty && invoiceNumber.isNotEmpty) {
          final key = '$customerId-$invoiceNumber';
          if (groupedBills[key] == null) groupedBills[key] = [];
          groupedBills[key]!.add(row);
        }
      }

      final firestore = FirebaseFirestore.instance;
      final allBills = groupedBills.entries.toList();
      final totalBills = allBills.length;
      const int batchSize = 400;

      for (int i = 0; i < totalBills; i += batchSize) {
        var batch = firestore.batch();
        final end = (i + batchSize > totalBills) ? totalBills : i + batchSize;
        for (int j = i; j < end; j++) {
          final entry = allBills[j];
          final firstItem = entry.value.first;
          final billHistory = BillHistory(
            id: entry.key,
            customerId: firstItem['รหัสลูกหนี้']?.toString() ?? '',
            invoiceNumber: firstItem['เลขที่ใบกำกับ']?.toString() ?? '',
            date: firstItem['วันที่']?.toString() ?? '',
            cd: firstItem['CD']?.toString() ?? '',
            accountId: firstItem['รหัสบัญชี']?.toString() ?? '',
            dueDate: firstItem['ครบกำหนด']?.toString() ?? '',
            salesperson: firstItem['พนง.ขาย']?.toString() ?? '',
            items: entry.value.map((row) => BillItem.fromMap(row)).toList(),
          );
          final sanitizedDocId = entry.key.replaceAll('/', '-');
          final docRef = firestore.collection('bill_history').doc(sanitizedDocId);
          batch.set(docRef, billHistory.toMap(), SetOptions(merge: true));
        }
        _statusNotifier.value = 'กำลังอัปโหลดประวัติการซื้อ... ($end/$totalBills)';
        await batch.commit();
        _progressNotifier.value = end / totalBills;
      }
      if(mounted) Navigator.of(context).pop();
      _showSnackBar('อัปโหลดประวัติการซื้อ $totalBills บิลสำเร็จ!', isError: false);
    } catch (e) {
      if(mounted) Navigator.of(context).pop();
      _showSnackBar('เกิดข้อผิดพลาด (Bill): ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _startStockUpload(PlatformFile? file) async {
    if (file == null) {
      _showSnackBar('กรุณาเลือกไฟล์สต็อกก่อน', isError: true);
      return;
    }
    setState(() => _isUploading = true);
    _showProgressDialog();
    try {
      _statusNotifier.value = 'กำลังอ่านข้อมูลสต็อก...';
      final dataList = await _processFile(file);
      if (dataList == null || dataList.isEmpty) throw Exception('ไม่พบข้อมูลในไฟล์');

      final firestore = FirebaseFirestore.instance;
      final totalItems = dataList.length;
      const batchSize = 400;

      for (int i = 0; i < totalItems; i += batchSize) {
        var batch = firestore.batch();
        final end = (i + batchSize > totalItems) ? totalItems : i + batchSize;
        for (int j = i; j < end; j++) {
          final data = dataList[j];
          final productId = data['รหัสสินค้า']?.toString().trim();
          if (productId != null && productId.isNotEmpty) {
            final sanitizedDocId = productId.replaceAll('/', '-');
            final docRef = firestore.collection('products').doc(sanitizedDocId);
            
            final stockData = {
              'หมวด': data['หมวด'],
              'จำนวนคงเหลือ': double.tryParse(data['จำนวนคงเหลือ']?.toString() ?? '0') ?? 0.0,
              'สถานที่เก็บ': data['สถานที่เก็บ'],
            };
            batch.set(docRef, stockData, SetOptions(merge: true));
          }
        }
        _statusNotifier.value = 'กำลังอัปเดต/สร้างสต็อก... (${(end / totalItems * 100).toStringAsFixed(0)}%)';
        await batch.commit();
        _progressNotifier.value = end / totalItems;
      }
      if(mounted) Navigator.of(context).pop();
      _showSnackBar('อัปเดต/สร้างสต็อก $totalItems รายการสำเร็จ!', isError: false);
    } catch (e) {
      if(mounted) Navigator.of(context).pop();
      _showSnackBar('เกิดข้อผิดพลาด (Stock): ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _startPurchaseUpload(PlatformFile? file) async {
    if (file == null) {
      _showSnackBar('กรุณาเลือกไฟล์ข้อมูลการซื้อ (Pur) ก่อน', isError: true);
      return;
    }
    setState(() => _isUploading = true);
    _showProgressDialog();

    try {
      _statusNotifier.value = 'กำลังลบข้อมูลการซื้อเก่า...';
      await _deleteCollection(FirebaseFirestore.instance.collection('purchases'));
      _statusNotifier.value = 'ลบข้อมูลเก่าสำเร็จ!';

      _statusNotifier.value = 'กำลังอ่านข้อมูลจากไฟล์...';
      final dataList = await _processFile(file);
      if (dataList == null || dataList.isEmpty) {
        throw Exception('ไม่พบข้อมูลในไฟล์');
      }

      final firestore = FirebaseFirestore.instance;
      final collectionRef = firestore.collection('purchases');
      final totalItems = dataList.length;
      const batchSize = 400; 

      _statusNotifier.value = 'กำลังเตรียมข้อมูลเพื่ออัปโหลด...';

      for (int i = 0; i < totalItems; i += batchSize) {
        var batch = firestore.batch();
        final end = (i + batchSize > totalItems) ? totalItems : i + batchSize;

        for (int j = i; j < end; j++) {
          final rowData = dataList[j];
          final purchase = Purchase.fromMap(rowData);
          final docRef = collectionRef.doc(); 
          batch.set(docRef, purchase.toMap());
        }

        _statusNotifier.value = 'กำลังอัปโหลดข้อมูลการซื้อ... (${(end / totalItems * 100).toStringAsFixed(0)}%)';
        await batch.commit();
        _progressNotifier.value = end / totalItems;
      }

      if (mounted) Navigator.of(context).pop();
      _showSnackBar('อัปโหลดข้อมูลการซื้อ $totalItems รายการสำเร็จ!', isError: false);

    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      _showSnackBar('เกิดข้อผิดพลาด (Purchase): ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _startPoUpload(PlatformFile? file) async {
    if (file == null) {
      _showSnackBar('กรุณาเลือกไฟล์ใบขอสั่งซื้อ (PO) ก่อน', isError: true);
      return;
    }
    setState(() => _isUploading = true);
    _showProgressDialog();

    try {
      _statusNotifier.value = 'กำลังลบข้อมูลใบขอสั่งซื้อเก่า...';
      await _deleteCollection(FirebaseFirestore.instance.collection('po'));
      _statusNotifier.value = 'ลบข้อมูลเก่าสำเร็จ!';

      _statusNotifier.value = 'กำลังอ่านข้อมูลจากไฟล์...';
      final dataList = await _processFile(file);
      if (dataList == null || dataList.isEmpty) {
        throw Exception('ไม่พบข้อมูลในไฟล์');
      }

      final firestore = FirebaseFirestore.instance;
      final collectionRef = firestore.collection('po');
      final totalItems = dataList.length;
      const batchSize = 400;

      _statusNotifier.value = 'กำลังเตรียมข้อมูลเพื่ออัปโหลด...';

      for (int i = 0; i < totalItems; i += batchSize) {
        var batch = firestore.batch();
        final end = (i + batchSize > totalItems) ? totalItems : i + batchSize;

        for (int j = i; j < end; j++) {
          final rowData = dataList[j];
          final po = PurchaseOrder.fromMap(rowData);
          final docRef = collectionRef.doc(); 
          batch.set(docRef, po.toMap());
        }

        _statusNotifier.value = 'กำลังอัปโหลดใบขอสั่งซื้อ... (${(end / totalItems * 100).toStringAsFixed(0)}%)';
        await batch.commit();
        _progressNotifier.value = end / totalItems;
      }

      if (mounted) Navigator.of(context).pop();
      _showSnackBar('อัปโหลดใบขอสั่งซื้อ $totalItems รายการสำเร็จ!', isError: false);

    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      _showSnackBar('เกิดข้อผิดพลาด (PO): ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('อัปโหลดข้อมูล (Admin)')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            _buildUploaderCard(title: '1. ข้อมูลลูกค้า', subtitle: '(อัปเดตข้อมูล, คงเบอร์โทรเดิม)', onPickFile: () async { final file = await _pickFile(); if (file != null) setState(() => _customerFile = file); }, fileName: _customerFile?.name, onUpload: () => _startCustomerUpload(_customerFile)),
            const SizedBox(height: 24),
            _buildUploaderCard(title: '2. ข้อมูลสั่งจอง (SO)', subtitle: '(ลบของเก่าและลงใหม่)', onPickFile: () async { final file = await _pickFile(); if (file != null) setState(() => _orderFile = file); }, fileName: _orderFile?.name, onUpload: () => _startGenericUpload(_orderFile, 'sales_orders', 'ข้อมูลสั่งจอง', deleteOld: true)),
            const SizedBox(height: 24),
            _buildUploaderCard(title: '3. ประวัติการซื้อ (Bill)', onPickFile: () async { final file = await _pickFile(); if (file != null) setState(() => _billFile = file); }, fileName: _billFile?.name, onUpload: () => _startBillUpload(_billFile)),
            const SizedBox(height: 24),
            _buildUploaderCard(title: '4. ข้อมูลราคาและสินค้า', subtitle: '(สร้าง/ทับข้อมูลหลัก)', onPickFile: () async { final file = await _pickFile(); if (file != null) setState(() => _priceFile = file); }, fileName: _priceFile?.name, onUpload: () => _startGenericUpload(_priceFile, 'products', 'ข้อมูลราคา')),
            const SizedBox(height: 24),
            _buildUploaderCard(title: '5. ข้อมูลสต็อกสินค้า', subtitle: '(อัปเดต/สร้างข้อมูลสต็อก)', onPickFile: () async { final file = await _pickFile(); if (file != null) setState(() => _stockFile = file); }, fileName: _stockFile?.name, onUpload: () => _startStockUpload(_stockFile)),
            const SizedBox(height: 24),
            _buildUploaderCard(title: '6. ข้อมูลการซื้อ (Pur)', subtitle: '(ลบของเก่าและลงใหม่ทั้งหมด)', onPickFile: () async { final file = await _pickFile(); if (file != null) setState(() => _purchaseFile = file); }, fileName: _purchaseFile?.name, onUpload: () => _startPurchaseUpload(_purchaseFile)),
            const SizedBox(height: 24),
            _buildUploaderCard(
              title: '7. ใบขอสั่งซื้อ (PO)',
              subtitle: '(ลบของเก่าและลงใหม่ทั้งหมด)',
              onPickFile: () async {
                final file = await _pickFile();
                if (file != null) setState(() => _poFile = file);
              },
              fileName: _poFile?.name,
              onUpload: () => _startPoUpload(_poFile),
            ),
            const SizedBox(height: 24),
            _buildUploaderCard(
              title: '8. ข้อมูลรีเบทลูกค้า',
              subtitle: '(ลบของเก่าและลงใหม่ทั้งหมด)',
              onPickFile: () async {
                final file = await _pickFile();
                if (file != null) setState(() => _rebateFile = file);
              },
              fileName: _rebateFile?.name,
              onUpload: () => _startRebateUpload(_rebateFile),
            ),
            const SizedBox(height: 24),
            const Padding(padding: EdgeInsets.all(8.0), child: Text('คำแนะนำ: หากไฟล์ของคุณเป็น .xls (Excel รุ่นเก่า) กรุณาเปิดไฟล์และ "บันทึกเป็น" (Save As) ชนิด Excel Workbook (*.xlsx) ก่อนทำการอัปโหลด', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))),
          ],
        ),
      ),
    );
  }
  
  Future<void> _deleteCollection(CollectionReference collection) async {
    const int batchSize = 400;
    var query = collection.limit(batchSize);
    while (true) {
      var snapshot = await query.get();
      if (snapshot.size == 0) break;
      var batch = FirebaseFirestore.instance.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  void _showProgressDialog() {
    showDialog(context: context, barrierDismissible: false, builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('กำลังอัปโหลดข้อมูล'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          ValueListenableBuilder<String>(valueListenable: _statusNotifier, builder: (context, status, child) => Text(status)),
          const SizedBox(height: 20),
          ValueListenableBuilder<double>(valueListenable: _progressNotifier, builder: (context, progress, child) {
            return Column(children: [
              LinearProgressIndicator(value: progress, minHeight: 12),
              const SizedBox(height: 8),
              Text('${(progress * 100).toStringAsFixed(0)} %'),
            ]);
          }),
        ]),
      );
    });
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: isError ? Colors.redAccent : Colors.green));
  }

  Widget _buildUploaderCard({ required String title, String? subtitle, required VoidCallback onPickFile, required VoidCallback onUpload, String? fileName}) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            if (subtitle != null) Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            Row(children: [
              ElevatedButton.icon(icon: const Icon(Icons.attach_file), label: const Text('เลือกไฟล์'), onPressed: onPickFile),
              const SizedBox(width: 16),
              Expanded(child: Text(fileName ?? 'ยังไม่ได้เลือกไฟล์', overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 24),
            Center(child: ElevatedButton.icon(icon: const Icon(Icons.cloud_upload), label: const Text('เริ่มอัปโหลด'), style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15)), onPressed: _isUploading ? null : onUpload)),
          ],
        ),
      ),
    );
  }
}
