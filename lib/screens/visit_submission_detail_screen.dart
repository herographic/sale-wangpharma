import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:salewang/models/visit_plan.dart';

class VisitSubmissionDetailScreen extends StatelessWidget {
  final VisitPlan plan;
  const VisitSubmissionDetailScreen({super.key, required this.plan});

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
          title: const Text('รายละเอียดภารกิจ', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _glass(_info(plan)),
            const SizedBox(height: 12),
            if (plan.photoUrls.isNotEmpty) _glass(_photos(plan)),
          ],
        ),
      ),
    );
  }

  Widget _info(VisitPlan p) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${p.customerName} (${p.customerId})', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text('กำหนด: ${DateFormat('dd/MM/yyyy HH:mm', 'th_TH').format(p.plannedAt.toDate())}', style: const TextStyle(color: Colors.white70)),
        if (p.completedByName != null) ...[
          const SizedBox(height: 6),
          Text('ผู้ส่งสรุป: ${p.completedByName}', style: const TextStyle(color: Colors.white70)),
        ],
        const SizedBox(height: 10),
        const Text('สรุปงาน', style: TextStyle(color: Colors.white)),
        const SizedBox(height: 4),
        Text(p.resultNotes ?? '-', style: const TextStyle(color: Colors.white)),
        const SizedBox(height: 10),
        const Text('ลายเซ็นยืนยัน', style: TextStyle(color: Colors.white)),
        const SizedBox(height: 6),
        if (p.signatureUrl != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(p.signatureUrl!, height: 150, fit: BoxFit.contain),
          )
        else
          const Text('-', style: TextStyle(color: Colors.white70)),
      ]),
    );
  }

  Widget _photos(VisitPlan p) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('รูปภาพประกอบ', style: TextStyle(color: Colors.white)),
        const SizedBox(height: 8),
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: p.photoUrls.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(p.photoUrls[i], width: 120, height: 100, fit: BoxFit.cover),
            ),
          ),
        )
      ]),
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
