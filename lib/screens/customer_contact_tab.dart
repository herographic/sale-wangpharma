// lib/screens/customer_contact_tab.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:salewang/models/customer.dart';
import 'package:salewang/models/customer_contact_info.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;


class CustomerContactTab extends StatefulWidget {
  final Customer customer;

  const CustomerContactTab({super.key, required this.customer});

  @override
  State<CustomerContactTab> createState() => _CustomerContactTabState();
}

class _CustomerContactTabState extends State<CustomerContactTab> {
  late Future<List<CustomerContactInfo>> _contactInfoFuture;

  @override
  void initState() {
    super.initState();
    _contactInfoFuture = _fetchContactInfo();
  }

  // This function still uses the direct API call as it was not part of the
  // original request to cache 'sale-support.php' and 'member.php'.
  // If 'member_search.php' should also be cached, this needs to be updated.
  Future<List<CustomerContactInfo>> _fetchContactInfo() async {
    const String bearerToken = 'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJtZW1fY29kZSI6Ii4wNjM1In0.5U_Yle8l5bZqOVTxqlvQo36XyQaW2bf3Q-h91bw3UL8';
    final url = Uri.https('www.wangpharma.com', '/API/appV3/member_search.php', {'search': widget.customer.customerId});

    final response = await http.get(url, headers: {'Authorization': 'Bearer $bearerToken'});

    if (response.statusCode == 200) {
      if (response.body.isNotEmpty && response.body != "[]") {
        return customerContactInfoFromJson(response.body);
      } else {
        return [];
      }
    } else {
      throw Exception('ไม่สามารถโหลดข้อมูลการติดต่อได้ (Code: ${response.statusCode})');
    }
  }

  Future<void> _launchPhone(String phoneNumber, BuildContext context) async {
    if (phoneNumber.trim().isEmpty) return;
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber.replaceAll(RegExp(r'[^0-9]'), ''));
    if (!await launchUrl(launchUri)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ไม่สามารถโทรออกไปที่ $phoneNumber ได้')),
      );
    }
  }

  bool _isBirthday(String birthdayString) {
    if (birthdayString.startsWith('0000-')) return false;
    try {
      final birthday = DateTime.parse(birthdayString);
      final today = DateTime.now();
      return birthday.month == today.month && birthday.day == today.day;
    } catch (e) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CustomerContactInfo>>(
      future: _contactInfoFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }
        if (snapshot.hasError) {
          return Center(child: Text('เกิดข้อผิดพลาด: ${snapshot.error}', style: const TextStyle(color: Colors.white)));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('ไม่พบข้อมูลการติดต่อ', style: TextStyle(color: Colors.white)));
        }

        final contactInfo = snapshot.data!.first;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              _buildHeaderCard(contactInfo),
              const SizedBox(height: 16),
              _ImageGallery(
                title: 'รูปภาพร้านค้า',
                firestorePath: 'customers/${widget.customer.id}/store_images',
              ),
              const SizedBox(height: 16),
              _buildOfficerList(contactInfo.officer),
              const SizedBox(height: 16),
              _buildTelephoneCard(contactInfo.telephone),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeaderCard(CustomerContactInfo contactInfo) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(contactInfo.memName, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: RichText(
                text: TextSpan(
                  style: DefaultTextStyle.of(context).style.copyWith(fontSize: 14),
                  children: [
                    TextSpan(text: 'รหัสลูกค้า: ', style: TextStyle(color: Colors.grey.shade700)),
                    TextSpan(text: '${contactInfo.memCode} ', style: const TextStyle(fontWeight: FontWeight.bold)),
                    TextSpan(text: '| ราคา: ', style: TextStyle(color: Colors.grey.shade700)),
                    TextSpan(text: '${widget.customer.p} ', style: const TextStyle(fontWeight: FontWeight.bold)),
                    TextSpan(text: '| ผู้ดูแล: ', style: TextStyle(color: Colors.grey.shade700)),
                    TextSpan(text: widget.customer.salesperson, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfficerList(List<Officer> officers) {
    final validOfficers = officers.where((o) => o.name.trim().isNotEmpty).toList();
    if (validOfficers.isEmpty) return const SizedBox.shrink();

    return Column(
      children: validOfficers.map((officer) {
        final officerId = officer.name.replaceAll(RegExp(r'[^a-zA-Z0-9ก-๙]'), '');
        return _buildOfficerCard(officer, officerId);
      }).toList(),
    );
  }

  Widget _buildOfficerCard(Officer officer, String officerId) {
    final isBirthdayToday = _isBirthday(officer.birthday);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(officer.career, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor)),
            const Divider(),
            _buildInfoRow(label: 'ชื่อ', value: officer.name),
            _buildInfoRow(label: 'ชื่อเล่น', value: officer.nick.isNotEmpty ? officer.nick : '-'),
            _buildInfoRow(label: 'เพศ', value: officer.sex.isNotEmpty ? officer.sex : '-'),
            Row(
              children: [
                const SizedBox(width: 80, child: Text('วันเกิด', style: TextStyle(fontWeight: FontWeight.w500))),
                if (isBirthdayToday)
                  const Icon(Icons.cake, color: Colors.red, size: 18),
                const SizedBox(width: 4),
                Text(
                  officer.birthday.startsWith('0000-') ? '-' : DateFormat('dd MMMM', 'th_TH').format(DateTime.parse(officer.birthday)),
                  style: TextStyle(color: isBirthdayToday ? Colors.red : Colors.black87, fontWeight: isBirthdayToday ? FontWeight.bold : FontWeight.normal),
                ),
              ],
            ),
            _buildInfoRowWithCall(label: 'เบอร์โทร', phone: officer.phone),
            const SizedBox(height: 8),
            _ImageGallery(
              title: 'รูปภาพผู้ติดต่อ',
              firestorePath: 'customers/${widget.customer.id}/officer_images/$officerId/images',
              maxImages: 3,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTelephoneCard(Telephone telephone) {
    final phones = [
      {'name': telephone.phone1Name, 'job': telephone.phone1Job, 'phone': telephone.phone1},
      {'name': telephone.phone2Name, 'job': telephone.phone2Job, 'phone': telephone.phone2},
      {'name': telephone.phone3Name, 'job': telephone.phone3Job, 'phone': telephone.phone3},
      {'name': telephone.phone4Name, 'job': telephone.phone4Job, 'phone': telephone.phone4},
    ].where((p) => (p['phone'] as String).trim().isNotEmpty).toList();

    if (phones.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('เบอร์โทรศัพท์ร้าน', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const Divider(),
            ...phones.map((p) => _buildInfoRowWithCall(
              label: (p['name'] as String).isNotEmpty ? p['name']! : ((p['job'] as String).isNotEmpty ? p['job']! : 'เบอร์ร้าน'),
              phone: p['phone'] as String,
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildInfoRowWithCall({required String label, required String phone}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500))),
          Expanded(child: Text(phone.isNotEmpty ? phone : '-')),
          if (phone.isNotEmpty)
            IconButton(
              icon: Icon(Icons.call, color: Colors.green.shade700, size: 20),
              onPressed: () => _launchPhone(phone, context),
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }
}

class _ImageGallery extends StatefulWidget {
  final String title;
  final String firestorePath;
  final int? maxImages;

  const _ImageGallery({required this.title, required this.firestorePath, this.maxImages});

  @override
  State<_ImageGallery> createState() => _ImageGalleryState();
}

class _ImageGalleryState extends State<_ImageGallery> {
  final ImagePicker _picker = ImagePicker();

  Future<void> _uploadImage(ImageSource source) async {
    final XFile? pickedFile = await _picker.pickImage(source: source, imageQuality: 70, maxWidth: 1024);
    if (pickedFile == null) return;

    final storageRef = FirebaseStorage.instance.ref().child(widget.firestorePath).child('${DateTime.now().millisecondsSinceEpoch}.jpg');
    try {
      if (kIsWeb) {
        await storageRef.putData(await pickedFile.readAsBytes(), SettableMetadata(contentType: 'image/jpeg'));
      } else {
        await storageRef.putFile(File(pickedFile.path));
      }
      final downloadUrl = await storageRef.getDownloadURL();
      await FirebaseFirestore.instance.collection(widget.firestorePath).add({
        'url': downloadUrl,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('อัปโหลดรูปภาพล้มเหลว: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection(widget.firestorePath).orderBy('createdAt').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final imageDocs = snapshot.data?.docs ?? [];
            final canAddMore = widget.maxImages == null || imageDocs.length < widget.maxImages!;

            return SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: imageDocs.length + (canAddMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == imageDocs.length) {
                    return _buildAddImageButton();
                  }
                  final doc = imageDocs[index];
                  final imageUrl = doc['url'];
                  return _buildImageThumbnail(imageUrl, doc.reference);
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildAddImageButton() {
    return Container(
      width: 100,
      height: 100,
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade400, style: BorderStyle.solid),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.photo_library_outlined, color: Colors.grey),
            tooltip: 'แนบจากแกลเลอรี่',
            onPressed: () => _uploadImage(ImageSource.gallery),
          ),
          IconButton(
            icon: const Icon(Icons.camera_alt_outlined, color: Colors.grey),
            tooltip: 'ถ่ายรูปใหม่',
            onPressed: () => _uploadImage(ImageSource.camera),
          ),
        ],
      ),
    );
  }

  Widget _buildImageThumbnail(String url, DocumentReference docRef) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: GestureDetector(
        onTap: () => showDialog(context: context, builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(url)))),
        onLongPress: () => _showDeleteConfirmDialog(docRef, url),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(url, width: 100, height: 100, fit: BoxFit.cover),
        ),
      ),
    );
  }

  void _showDeleteConfirmDialog(DocumentReference docRef, String url) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ลบรูปภาพ?'),
        content: const Text('คุณต้องการลบรูปภาพนี้ใช่หรือไม่?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
          TextButton(
            onPressed: () async {
              try {
                await FirebaseStorage.instance.refFromURL(url).delete();
                await docRef.delete();
              } catch (e) {
                debugPrint('Error deleting image: $e');
              }
              Navigator.pop(context);
            },
            child: const Text('ลบ', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
