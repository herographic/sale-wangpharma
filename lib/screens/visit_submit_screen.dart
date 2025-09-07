import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:signature/signature.dart';
import 'package:salewang/models/visit_plan.dart';

class VisitSubmitScreen extends StatefulWidget {
  final VisitPlan plan;
  const VisitSubmitScreen({super.key, required this.plan});

  @override
  State<VisitSubmitScreen> createState() => _VisitSubmitScreenState();
}

class _VisitSubmitScreenState extends State<VisitSubmitScreen> {
  final _resultController = TextEditingController();
  DateTime _doneAt = DateTime.now();
  final _sigController = SignatureController(penStrokeWidth: 3, penColor: Colors.black);
  final ImagePicker _picker = ImagePicker();
  final List<XFile> _picked = [];
  bool _busy = false;

  @override
  void dispose() {
    _resultController.dispose();
    _sigController.dispose();
    super.dispose();
  }

  Future<void> _pickDoneTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _doneAt,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_doneAt));
    if (time == null) return;
    setState(() => _doneAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _pickFromCamera() async {
    final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (x != null) setState(() => _picked.add(x));
  }

  Future<void> _pickFromGallery() async {
    final xs = await _picker.pickMultiImage(imageQuality: 80);
    if (xs.isNotEmpty) setState(() => _picked.addAll(xs));
  }

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _busy = true);
    try {
      final docRef = FirebaseFirestore.instance.collection('visit_plans').doc(widget.plan.id);
      final List<String> urls = [];
      // Upload photos
      for (final x in _picked) {
        final path = 'visit_plans/${widget.plan.id}/photos/${DateTime.now().millisecondsSinceEpoch}.jpg';
        final ref = FirebaseStorage.instance.ref(path);
        await ref.putFile(File(x.path));
        urls.add(await ref.getDownloadURL());
      }
      // Upload signature if drawn
      String? sigUrl;
      if (_sigController.isNotEmpty) {
        final bytes = await _sigController.toPngBytes();
        if (bytes != null) {
          final ref = FirebaseStorage.instance.ref('visit_plans/${widget.plan.id}/signature.png');
          await ref.putData(bytes, SettableMetadata(contentType: 'image/png'));
          sigUrl = await ref.getDownloadURL();
        }
      }

      // Update visit plan
      await docRef.update({
        'resultNotes': _resultController.text.trim().isEmpty ? null : _resultController.text.trim(),
        'doneAt': Timestamp.fromDate(_doneAt),
        if (urls.isNotEmpty) 'photoUrls': FieldValue.arrayUnion(urls),
        if (sigUrl != null) 'signatureUrl': sigUrl,
        'completedById': user.uid,
        'completedByName': user.displayName ?? user.email ?? user.uid,
      });
      
      // Also save to visit_reports collection using customerId as document ID
      await FirebaseFirestore.instance
          .collection('visit_reports')
          .doc(widget.plan.customerId)
          .set({
        'customerId': widget.plan.customerId,
        'customerName': widget.plan.customerName,
        'planId': widget.plan.id,
        'resultNotes': _resultController.text.trim().isEmpty ? null : _resultController.text.trim(),
        'plannedAt': widget.plan.plannedAt,
        'submittedAt': Timestamp.fromDate(_doneAt),
        'doneAt': Timestamp.fromDate(_doneAt),
        if (urls.isNotEmpty) 'photoUrls': urls,
        if (sigUrl != null) 'signatureUrl': sigUrl,
        'completedById': user.uid,
        'completedByName': user.displayName ?? user.email ?? user.uid,
      }, SetOptions(merge: true)); // Use merge to handle multiple visits for same customer

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ส่งสรุปภารกิจแล้ว')));
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
          title: const Text('ส่งภารกิจ', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _glass(
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
          Text('${widget.plan.customerName} (${widget.plan.customerId})', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('กำหนด: ${DateFormat('dd/MM/yyyy HH:mm', 'th_TH').format(widget.plan.plannedAt.toDate())}'),
          const SizedBox(height: 12),
          TextField(
            controller: _resultController,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'สรุปงาน',
              filled: true,
              fillColor: Colors.white.withOpacity(0.9),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            const Text('เวลาที่ทำงานเสร็จ: '),
            Text(DateFormat('dd/MM/yyyy HH:mm', 'th_TH').format(_doneAt)),
            const SizedBox(width: 8),
            OutlinedButton.icon(onPressed: _pickDoneTime, icon: const Icon(Icons.access_time), label: const Text('เลือกเวลา')),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            ElevatedButton.icon(onPressed: _pickFromCamera, icon: const Icon(Icons.photo_camera), label: const Text('ถ่ายรูป')),
            const SizedBox(width: 8),
            OutlinedButton.icon(onPressed: _pickFromGallery, icon: const Icon(Icons.photo_library), label: const Text('เลือกรูป')),
          ]),
          const SizedBox(height: 8),
          if (_picked.isNotEmpty)
            SizedBox(
              height: 80,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _picked.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (ctx, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(File(_picked[i].path), width: 100, height: 80, fit: BoxFit.cover),
                ),
              ),
            ),
          const SizedBox(height: 12),
          const Text('ลายเซ็นยืนยัน', style: TextStyle(color: Colors.white)),
          const SizedBox(height: 6),
          Container(
            height: 160,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
            child: Signature(controller: _sigController, backgroundColor: Colors.white),
          ),
          const SizedBox(height: 12),
          Row(children: [
            TextButton(onPressed: _sigController.clear, child: const Text('ล้างลายเซ็น')),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
              label: const Text('ส่งสรุป'),
            )
          ])
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _glass(Widget child) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: child,
    ),
  );
}
