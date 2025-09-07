// lib/widgets/customer_list_item_card.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:salewang/models/call_log.dart';
import 'package:salewang/models/customer.dart';
import 'package:salewang/screens/call_screen.dart';
import 'package:salewang/screens/customer_detail_screen.dart';
import 'package:salewang/utils/date_helper.dart';
import 'package:salewang/widgets/contact_manager_dialog.dart';

enum CallStatus { calledToday, notCalledToday }

class CustomerListItemCard extends StatefulWidget {
  final Customer customer;

  const CustomerListItemCard({super.key, required this.customer});

  @override
  State<CustomerListItemCard> createState() => _CustomerListItemCardState();
}

class _CustomerListItemCardState extends State<CustomerListItemCard> {
  Stream<QuerySnapshot>? _callHistoryStream;
  Stream<QuerySnapshot>? _todayCallStatusStream;

  @override
  void initState() {
    super.initState();
    _setupCallStreams();
  }

  void _setupCallStreams() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final historyQuery = FirebaseFirestore.instance
        .collection('call_logs')
        .where('customerId', isEqualTo: widget.customer.customerId)
        .orderBy('callTimestamp', descending: true)
        .limit(5);

    final now = DateTime.now();
    final startOfToday = Timestamp.fromDate(DateTime(now.year, now.month, now.day));
    final statusQuery = FirebaseFirestore.instance
        .collection('call_logs')
        .where('salespersonId', isEqualTo: user.uid)
        .where('customerId', isEqualTo: widget.customer.customerId)
        .where('callTimestamp', isGreaterThanOrEqualTo: startOfToday);

    setState(() {
      _callHistoryStream = historyQuery.snapshots();
      _todayCallStatusStream = statusQuery.snapshots();
    });
  }

  (CallStatus, Color) _getCallStatusAndColor(AsyncSnapshot<QuerySnapshot> snapshot) {
    if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
      return (CallStatus.calledToday, const Color(0xFFE8F5E9)); // Light Green
    } else {
      return (CallStatus.notCalledToday, const Color(0xFFFFEBEE)); // Light Red
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _todayCallStatusStream,
      builder: (context, statusSnapshot) {
        if (statusSnapshot.hasError) {
          debugPrint("Firestore Status Query Error: ${statusSnapshot.error}");
        }
        
        final (callStatus, cardColor) = _getCallStatusAndColor(statusSnapshot);

        return Card(
          color: cardColor,
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          elevation: 2,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: Colors.grey.shade200, width: 1),
            borderRadius: BorderRadius.circular(16)
          ),
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CustomerDetailScreen(customer: widget.customer),
                ),
              );
            },
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: _buildCustomerInfo(),
                    ),
                  ),
                  _buildActionButtons(context),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCustomerInfo() {
    final String address = ('${widget.customer.address1} ${widget.customer.address2}').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                widget.customer.name,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF263238)),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'ราคา: ${widget.customer.p.isNotEmpty ? widget.customer.p : '-'}',
                style: TextStyle(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text('รหัส: ${widget.customer.customerId}', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        const SizedBox(height: 12),
        _buildInfoRow(Icons.location_on_outlined, address.isNotEmpty ? address : 'ไม่มีข้อมูลที่อยู่'),
        const SizedBox(height: 6),
        _buildInfoRow(Icons.person_outline, widget.customer.contacts.isNotEmpty ? '${widget.customer.contacts.first['name']} (${widget.customer.contacts.first['phone']})' : 'ไม่มีข้อมูลผู้ติดต่อ'),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12.0),
          child: Divider(height: 1),
        ),
        Row(
          children: [
            Expanded(child: _buildDateInfo('ขายล่าสุด', widget.customer.lastSaleDate)),
            Expanded(child: _buildDateInfo('รับเงินล่าสุด', widget.customer.lastPaymentDate)),
          ],
        ),
        StreamBuilder<QuerySnapshot>(
          stream: _callHistoryStream,
          builder: (context, historySnapshot) {
            if (historySnapshot.connectionState == ConnectionState.waiting && !historySnapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))),
              );
            }
            if (historySnapshot.hasError) {
              debugPrint("Firestore History Query Error (Check for missing index): ${historySnapshot.error}");
            }
            if (historySnapshot.hasData && historySnapshot.data!.docs.isNotEmpty) {
              return _buildCallHistoryTable(historySnapshot.data!.docs);
            }
            return const SizedBox.shrink();
          },
        ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Container(
      width: 80,
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.05),
        border: Border(left: BorderSide(color: Colors.grey.shade200, width: 1)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildActionButton(
            context,
            icon: Icons.contact_phone_outlined,
            label: 'ผู้ติดต่อ',
            color: Theme.of(context).primaryColor,
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => ContactManagerDialog(customer: widget.customer),
              );
            },
          ),
          _buildActionButton(
            context,
            icon: Icons.receipt_long_outlined,
            label: 'ค้างสั่งจอง',
            color: Colors.orange.shade800,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CallScreen(customer: widget.customer),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, {required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildDateInfo(String label, String dateStr) {
    final String displayDate = DateHelper.formatDateToThai(dateStr);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        Text(displayDate, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
      ],
    );
  }

  Widget _buildCallHistoryTable(List<DocumentSnapshot> docs) {
    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildTableHeader('วันที่', flex: 2),
              _buildTableHeader('เวลา', flex: 2),
              _buildTableHeader('ผู้โทร', flex: 3),
            ],
          ),
          const Divider(height: 8, thickness: 1),
          ...docs.map((doc) {
            final log = CallLog.fromFirestore(doc);
            final timeFormat = DateFormat('HH:mm', 'th_TH');
            final dateFormat = DateFormat('dd/MM/yy', 'th_TH');
            final callTime = log.callTimestamp.toDate();
            
            // --- UPDATED: Improved Display Name Logic ---
            final String displayName;
            if (log.salespersonName.isNotEmpty && log.salespersonName != 'N/A' && !log.salespersonName.contains('@')) {
              // Use the display name if it's a proper name
              displayName = log.salespersonName;
            } else if (log.salespersonName.contains('@')) {
              // Use the part before @ if it's an email
              displayName = log.salespersonName.split('@').first;
            } else {
              // Fallback to the first 6 characters of the UID for old records
              displayName = log.salespersonId.length > 6 ? log.salespersonId.substring(0, 6) : log.salespersonId;
            }

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3.0),
              child: Row(
                children: [
                  _buildTableCell(dateFormat.format(callTime), flex: 2),
                  _buildTableCell('${timeFormat.format(callTime)} น.', flex: 2),
                  _buildTableCell(displayName, flex: 3),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTableHeader(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade800),
      ),
    );
  }

  Widget _buildTableCell(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade700),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
