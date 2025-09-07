// lib/screens/data_sync_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:salewang/services/api_sync_service.dart';

class DataSyncScreen extends StatefulWidget {
  const DataSyncScreen({super.key});

  @override
  State<DataSyncScreen> createState() => _DataSyncScreenState();
}

class _DataSyncScreenState extends State<DataSyncScreen> {
  bool _isSyncing = false;
  final ValueNotifier<String> _statusNotifier = ValueNotifier('พร้อมที่จะซิงค์ข้อมูล');
  final ValueNotifier<double> _progressNotifier = ValueNotifier(0.0);

  Future<void> _runSync() async {
    setState(() => _isSyncing = true);
    try {
      await ApiSyncService.syncAllCustomerData(
        statusNotifier: _statusNotifier,
        progressNotifier: _progressNotifier,
      );
      _showSnackBar('ซิงค์ข้อมูลสำเร็จ!', isError: false);
    } catch (e) {
      _statusNotifier.value = 'เกิดข้อผิดพลาด: ${e.toString()}';
      _showSnackBar('เกิดข้อผิดพลาด: ${e.toString()}', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
        _progressNotifier.value = 0.0;
        _statusNotifier.value = 'พร้อมที่จะซิงค์ข้อมูล';
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
      ),
    );
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
          title: const Text('ซิงค์ข้อมูล API', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              _buildStatusCard(),
              const SizedBox(height: 24),
              _buildSyncCard(
                title: 'ข้อมูลลูกค้าและเส้นทาง',
                lastUpdatedField: 'allCustomerDataLastUpdated',
                onSync: _runSync,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ValueListenableBuilder<String>(
              valueListenable: _statusNotifier,
              builder: (context, status, child) {
                return Text(
                  status,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                );
              },
            ),
            if (_isSyncing) ...[
              const SizedBox(height: 16),
              ValueListenableBuilder<double>(
                valueListenable: _progressNotifier,
                builder: (context, progress, child) {
                  return LinearProgressIndicator(
                    value: progress,
                    minHeight: 12,
                    borderRadius: BorderRadius.circular(6),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSyncCard({
    required String title,
    required String lastUpdatedField,
    required VoidCallback onSync,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('api_data_cache').doc('metadata').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Text('กำลังโหลดสถานะ...');
                }
                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return const Text('อัปเดตล่าสุด: ยังไม่เคยซิงค์');
                }
                final data = snapshot.data!.data() as Map<String, dynamic>;
                final timestamp = data[lastUpdatedField] as Timestamp?;
                final lastUpdated = timestamp != null
                    ? DateFormat('d MMMM yyyy, HH:mm', 'th_TH').format(timestamp.toDate())
                    : 'ยังไม่เคยซิงค์';
                return Text('อัปเดตล่าสุด: $lastUpdated');
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.sync),
                label: const Text('ซิงค์ข้อมูลทั้งหมด'),
                onPressed: _isSyncing ? null : onSync,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
