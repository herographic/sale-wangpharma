// lib/screens/task_tracker_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:salewang/models/task_note.dart';
import 'package:salewang/screens/edit_task_note_screen.dart';

class TaskTrackerScreen extends StatefulWidget {
  const TaskTrackerScreen({super.key});

  @override
  State<TaskTrackerScreen> createState() => _TaskTrackerScreenState();
}

class _TaskTrackerScreenState extends State<TaskTrackerScreen> {
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
          title: const Text('ติดตามงาน', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('task_notes')
              .where('isDeleted', isEqualTo: false)
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: Colors.white));
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const Center(
                  child: Text('ไม่มีงานให้ติดตาม',
                      style: TextStyle(color: Colors.white70)));
            }
            final tasks = snapshot.data!.docs
                .map((doc) => TaskNote.fromFirestore(doc))
                .toList();
            return ListView.builder(
              padding: const EdgeInsets.all(8.0),
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                return TaskNoteCard(taskNote: tasks[index]);
              },
            );
          },
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const EditTaskNoteScreen()),
            );
          },
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

class TaskNoteCard extends StatefulWidget {
  final TaskNote taskNote;

  const TaskNoteCard({super.key, required this.taskNote});

  @override
  State<TaskNoteCard> createState() => _TaskNoteCardState();
}

class _TaskNoteCardState extends State<TaskNoteCard> {
  final _commentController = TextEditingController();
  bool _isSendingComment = false;

  Future<void> _softDeleteTask() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: const Text('คุณแน่ใจหรือไม่ว่าต้องการลบรายการนี้ออกจากหน้าติดตามงาน? (ข้อมูลจะยังคงอยู่ในหน้าลูกค้า)'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('ยกเลิก')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('ลบ', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance
          .collection('task_notes')
          .doc(widget.taskNote.id)
          .update({'isDeleted': true});
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    final user = FirebaseAuth.instance.currentUser;
    await FirebaseFirestore.instance
        .collection('task_notes')
        .doc(widget.taskNote.id)
        .update({
          'status': newStatus,
          'approvedBy': user?.displayName,
          'approvedAt': Timestamp.now(),
        });
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    final user = FirebaseAuth.instance.currentUser;
    if (text.isEmpty || user == null) return;

    setState(() => _isSendingComment = true);
    try {
      await FirebaseFirestore.instance
          .collection('customers')
          .doc(widget.taskNote.customerId)
          .collection('notes')
          .add({
        'text': 'Re: ${widget.taskNote.title}\n$text',
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

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm', 'th_TH');
    IconData statusIcon;
    Color statusColor;
    switch (widget.taskNote.status) {
      case 'approved':
        statusIcon = Icons.check_circle;
        statusColor = Colors.green;
        break;
      case 'rejected':
        statusIcon = Icons.cancel;
        statusColor = Colors.red;
        break;
      default:
        statusIcon = Icons.hourglass_empty;
        statusColor = Colors.orange;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: ExpansionTile(
        leading: Icon(statusIcon, color: statusColor),
        title: Text(widget.taskNote.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(widget.taskNote.customerName),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.taskNote.details),
                if (widget.taskNote.imageUrls.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 100,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: widget.taskNote.imageUrls.length,
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: Image.network(widget.taskNote.imageUrls[index]),
                      ),
                    ),
                  ),
                ],
                const Divider(height: 20),
                Text('วันที่นัดหมาย: ${dateFormat.format(widget.taskNote.taskDateTime.toDate())}'),
                Text('สร้างโดย: ${widget.taskNote.createdBy}'),
                Text('วันที่สร้าง: ${dateFormat.format(widget.taskNote.createdAt.toDate())}'),
                
                // Chat Input
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
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
                ),

                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.approval, color: Colors.blueGrey),
                      onSelected: _updateStatus,
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'approved', child: Text('อนุมัติ')),
                        const PopupMenuItem(value: 'rejected', child: Text('ไม่อนุมัติ')),
                        const PopupMenuItem(value: 'pending', child: Text('รอดำเนินการ')),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => EditTaskNoteScreen(taskNote: widget.taskNote),
                          ),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: _softDeleteTask,
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
}
