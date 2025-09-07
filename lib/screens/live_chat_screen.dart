// lib/screens/live_chat_screen.dart

import 'dart:async';
// import 'dart:io'; // REMOVED: This import is not safe for web
// UPDATED
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:salewang/models/customer.dart';
import 'package:salewang/screens/customer_detail_screen.dart';

// Model for a chat message
class ChatMessage {
  final String id;
  final String text;
  final String userId;
  final String userName;
  final String? userPhotoUrl;
  final Timestamp timestamp;
  final List<String> imageUrls;
  final String? originalMessageId; // For edited messages

  ChatMessage({
    required this.id,
    required this.text,
    required this.userId,
    required this.userName,
    this.userPhotoUrl,
    required this.timestamp,
    this.imageUrls = const [],
    this.originalMessageId,
  });

  factory ChatMessage.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return ChatMessage(
      id: doc.id,
      text: data['text'] ?? '',
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? 'Unknown',
      userPhotoUrl: data['userPhotoUrl'],
      timestamp: data['timestamp'] ?? Timestamp.now(),
      imageUrls: List<String>.from(data['imageUrls'] ?? []),
      originalMessageId: data['originalMessageId'],
    );
  }
}

// Model for a task in the "ติดตามงาน" tab
class TaskItem {
  final String id;
  final String customerId;
  final String createdBy;
  final Timestamp createdAt;
  final List<String> sourceMessageIds;
  final Map<String, bool> messageStatus;

  TaskItem({
    required this.id,
    required this.customerId,
    required this.createdBy,
    required this.createdAt,
    required this.sourceMessageIds,
    required this.messageStatus,
  });

  factory TaskItem.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return TaskItem(
      id: doc.id,
      customerId: data['customerId'] ?? '',
      createdBy: data['createdBy'] ?? 'Unknown',
      createdAt: data['createdAt'] ?? Timestamp.now(),
      sourceMessageIds: List<String>.from(data['sourceMessageIds'] ?? []),
      messageStatus: Map<String, bool>.from(data['messageStatus'] ?? {}),
    );
  }
}


class LiveChatScreen extends StatefulWidget {
  const LiveChatScreen({super.key});

  @override
  State<LiveChatScreen> createState() => _LiveChatScreenState();
}

class _LiveChatScreenState extends State<LiveChatScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white.withOpacity(0.7),
            indicatorColor: Colors.yellowAccent,
            tabs: const [
              Tab(icon: Icon(Icons.chat), text: 'แชทไลฟ์สด'),
              Tab(icon: Icon(Icons.task_alt), text: 'ติดตามงาน'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                LiveChatTab(),
                TaskTrackerTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// #############################################################################
// #                             Live Chat Tab Widget                          #
// #############################################################################
class LiveChatTab extends StatefulWidget {
  const LiveChatTab({super.key});

  @override
  State<LiveChatTab> createState() => _LiveChatTabState();
}

class _LiveChatTabState extends State<LiveChatTab> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  final List<XFile> _selectedImages = [];
  bool _isUploading = false;
  String? _editingMessageId;
  
  final RegExp _tagRegExp = RegExp(r'@([CEce])-([\w-]+)\[([^\]]+)\]');


  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final List<XFile> pickedFiles = await _picker.pickMultiImage(
      imageQuality: 70,
      maxWidth: 1024,
    );
    if (pickedFiles.isNotEmpty) {
      setState(() {
        _selectedImages.addAll(pickedFiles);
      });
    }
  }

  Future<void> _takePicture() async {
    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
      maxWidth: 1024,
    );
    if (pickedFile != null) {
      setState(() {
        _selectedImages.add(pickedFile);
      });
    }
  }

  Future<List<String>> _uploadImages(List<XFile> images) async {
    List<String> downloadUrls = [];
    final storageRef = FirebaseStorage.instance.ref().child('chat_images');

    for (var image in images) {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}-${image.name}';
      final uploadTask = storageRef.child(fileName);
      
      // Read bytes once, works for both web and mobile
      final imageBytes = await image.readAsBytes();
      await uploadTask.putData(imageBytes, SettableMetadata(contentType: 'image/jpeg'));

      downloadUrls.add(await uploadTask.getDownloadURL());
    }
    return downloadUrls;
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty && _selectedImages.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isUploading = true);

    try {
      List<String> imageUrls = [];
      if (_selectedImages.isNotEmpty) {
        imageUrls = await _uploadImages(_selectedImages);
      }

      final messageData = {
        'text': text,
        'userId': user.uid,
        'userName': user.displayName ?? user.email?.split('@').first,
        'userPhotoUrl': user.photoURL,
        'timestamp': FieldValue.serverTimestamp(),
        'imageUrls': imageUrls,
      };

      if (_editingMessageId != null) {
        await FirebaseFirestore.instance
            .collection('live_chat')
            .doc(_editingMessageId)
            .update(messageData);
        setState(() => _editingMessageId = null);
      } else {
        final docRef = await FirebaseFirestore.instance
            .collection('live_chat')
            .add(messageData);
        
        await _processTags(text, docRef.id);
      }

      _messageController.clear();
      _selectedImages.clear();
      _scrollController.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาด: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _processTags(String text, String messageId) async {
    final matches = _tagRegExp.allMatches(text);
    if (matches.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    final batch = FirebaseFirestore.instance.batch();
    final tasksCollection = FirebaseFirestore.instance.collection('tasks');

    for (final match in matches) {
      final type = match.group(1)?.toUpperCase();
      final id = match.group(2);

      if (id == null) continue;

      if (type == 'C') {
        final existingTaskQuery = await tasksCollection
            .where('customerId', isEqualTo: id)
            .limit(1)
            .get();

        if (existingTaskQuery.docs.isNotEmpty) {
          final existingTaskDoc = existingTaskQuery.docs.first;
          batch.update(existingTaskDoc.reference, {
            'sourceMessageIds': FieldValue.arrayUnion([messageId]),
            'messageStatus.$messageId': false,
          });
        } else {
          final taskRef = tasksCollection.doc();
          batch.set(taskRef, {
            'customerId': id,
            'createdBy': user?.displayName ?? 'Unknown',
            'createdAt': FieldValue.serverTimestamp(),
            'sourceMessageIds': [messageId],
            'messageStatus': {messageId: false},
          });
        }
      } else if (type == 'E') {
        final notificationRef = FirebaseFirestore.instance.collection('notifications').doc();
        batch.set(notificationRef, {
          'taggedEmployeeId': id,
          'message': text,
          'createdBy': user?.displayName,
          'createdAt': FieldValue.serverTimestamp(),
          'isAcknowledged': false,
          'sourceMessageId': messageId,
        });
      }
    }
    await batch.commit();
  }
  
  void _editMessage(ChatMessage message) {
    setState(() {
      _editingMessageId = message.id;
      _messageController.text = message.text;
    });
  }

  Future<void> _deleteMessage(String messageId) async {
    final password = await showDialog<String>(
      context: context,
      builder: (context) => const _PasswordConfirmationDialog(),
    );

    if (password == '123456') {
      await FirebaseFirestore.instance.collection('live_chat').doc(messageId).delete();
    } else if (password != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('รหัสผ่านไม่ถูกต้อง'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showTagDialog() async {
    final String? tag = await showDialog<String>(
      context: context,
      builder: (context) => const _TagSelectionDialog(),
    );

    if (tag != null && tag.isNotEmpty) {
      final currentText = _messageController.text;
      final cursorPos = _messageController.selection.baseOffset;
      final newText =
          '${currentText.substring(0, cursorPos)}$tag\n${currentText.substring(cursorPos)}';
      _messageController.text = newText;
      _messageController.selection =
          TextSelection.fromPosition(TextPosition(offset: cursorPos + tag.length + 1));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('live_chat')
                .orderBy('timestamp', descending: true)
                .limit(50)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Colors.white));
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(child: Text('ไม่มีข้อความ', style: TextStyle(color: Colors.white70)));
              }

              final messages = snapshot.data!.docs
                  .map((doc) => ChatMessage.fromFirestore(doc))
                  .toList();

              return ListView.builder(
                controller: _scrollController,
                reverse: true,
                padding: const EdgeInsets.all(8.0),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  return _ChatMessageBubble(
                    message: messages[index],
                    onEdit: () => _editMessage(messages[index]),
                    onDelete: () => _deleteMessage(messages[index].id),
                  );
                },
              );
            },
          ),
        ),
        _buildMessageComposer(),
      ],
    );
  }

  Widget _buildMessageComposer() {
    return Card(
      margin: const EdgeInsets.all(8.0),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Column(
          children: [
            if (_selectedImages.isNotEmpty) _buildImagePreview(),
            Row(
              children: [
                IconButton(
                  icon: Icon(Icons.photo_library_outlined, color: Theme.of(context).primaryColor),
                  onPressed: _pickImages,
                ),
                IconButton(
                  icon: Icon(Icons.camera_alt_outlined, color: Theme.of(context).primaryColor),
                  onPressed: _takePicture,
                ),
                IconButton(
                  icon: Icon(Icons.alternate_email, color: Theme.of(context).primaryColor),
                  onPressed: _showTagDialog,
                  tooltip: 'แท็กพนักงาน/ลูกค้า',
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration.collapsed(
                      hintText: _editingMessageId != null ? 'กำลังแก้ไขข้อความ...' : 'พิมพ์ข้อความ...',
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 5,
                    minLines: 1,
                  ),
                ),
                if (_editingMessageId != null)
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () {
                      setState(() {
                        _editingMessageId = null;
                        _messageController.clear();
                      });
                    },
                  ),
                _isUploading
                    ? const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: CircularProgressIndicator(),
                      )
                    : IconButton(
                        icon: Icon(Icons.send, color: Theme.of(context).primaryColor),
                        onPressed: _sendMessage,
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    return Container(
      height: 100,
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _selectedImages.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: GestureDetector(
              onTap: () async { // Make onTap async
                // Read all images into memory first
                final imageBytesList = await Future.wait(
                  _selectedImages.map((file) => file.readAsBytes()).toList()
                );
                // Then navigate
                if(mounted) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) {
                    return _FullScreenImageViewer(
                      // Pass the list of bytes
                      images: imageBytesList,
                      initialIndex: index,
                    );
                  }));
                }
              },
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8.0),
                    child: FutureBuilder<Uint8List>(
                      future: _selectedImages[index].readAsBytes(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
                          return Image.memory(
                            snapshot.data!,
                            height: 100,
                            width: 100,
                            fit: BoxFit.cover,
                          );
                        }
                        return Container(
                          height: 100,
                          width: 100,
                          color: Colors.grey.shade200,
                          child: const Center(child: CircularProgressIndicator()),
                        );
                      },
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedImages.removeAt(index);
                        });
                      },
                      child: const CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.black54,
                        child: Icon(Icons.close, color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// #############################################################################
// #                           Task Tracker Tab Widget (UPDATED)               #
// #############################################################################
class TaskTrackerTab extends StatelessWidget {
  const TaskTrackerTab({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('tasks')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('ไม่มีงานให้ติดตาม', style: TextStyle(color: Colors.white70)));
        }

        final tasks = snapshot.data!.docs
            .map((doc) => TaskItem.fromFirestore(doc))
            .toList();

        return ListView.builder(
          padding: const EdgeInsets.all(8.0),
          itemCount: tasks.length,
          itemBuilder: (context, index) {
            return _TaskItemCard(task: tasks[index]);
          },
        );
      },
    );
  }
}

class _TaskItemCard extends StatefulWidget {
  final TaskItem task;
  const _TaskItemCard({required this.task});

  @override
  State<_TaskItemCard> createState() => _TaskItemCardState();
}

class _TaskItemCardState extends State<_TaskItemCard> {
  List<ChatMessage> _sourceMessages = [];
  Customer? _customer;
  bool _isLoadingDetails = true;

  @override
  void initState() {
    super.initState();
    _fetchDetails();
  }

  Future<void> _fetchDetails() async {
    try {
      if (widget.task.sourceMessageIds.isNotEmpty) {
        final messageDocs = await FirebaseFirestore.instance
            .collection('live_chat')
            .where(FieldPath.documentId, whereIn: widget.task.sourceMessageIds)
            .get();
        
        _sourceMessages = messageDocs.docs
            .map((doc) => ChatMessage.fromFirestore(doc))
            .toList();
        _sourceMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      }

      final customerQuery = await FirebaseFirestore.instance
          .collection('customers')
          .where('รหัสลูกค้า', isEqualTo: widget.task.customerId)
          .limit(1)
          .get();
      if (customerQuery.docs.isNotEmpty) {
        _customer = Customer.fromFirestore(customerQuery.docs.first);
      }
    } catch (e) {
      debugPrint("Error fetching task details: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingDetails = false;
        });
      }
    }
  }

  void _updateMessageStatus(String messageId, bool isCompleted) {
    FirebaseFirestore.instance
        .collection('tasks')
        .doc(widget.task.id)
        .update({'messageStatus.$messageId': isCompleted});
  }

  void _removeMessageFromTask(String messageId) async {
    final password = await showDialog<String>(
      context: context,
      builder: (context) => const _PasswordConfirmationDialog(),
    );
    if (password != '123456') {
      if (password != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('รหัสผ่านไม่ถูกต้อง'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    final taskRef = FirebaseFirestore.instance.collection('tasks').doc(widget.task.id);
    
    if (widget.task.sourceMessageIds.length <= 1) {
      taskRef.delete();
    } else {
      taskRef.update({
        'sourceMessageIds': FieldValue.arrayRemove([messageId]),
        'messageStatus.$messageId': FieldValue.delete(),
      });
    }
  }
  
  void _deleteTask() async {
    final password = await showDialog<String>(
      context: context,
      builder: (context) => const _PasswordConfirmationDialog(),
    );
     if (password == '123456') {
      FirebaseFirestore.instance.collection('tasks').doc(widget.task.id).delete();
    } else if (password != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('รหัสผ่านไม่ถูกต้อง'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _navigateToCustomerDetails() {
    if (_customer != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CustomerDetailScreen(customer: _customer!),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่พบข้อมูลลูกค้าในระบบ'), backgroundColor: Colors.orange),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isTaskCompleted = widget.task.messageStatus.isNotEmpty && widget.task.messageStatus.values.every((status) => status == true);

    return Card(
      color: isTaskCompleted ? Colors.green.shade50 : Colors.amber.shade50,
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      child: InkWell(
        onTap: _navigateToCustomerDetails,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ลูกค้า: ${widget.task.customerId} - ${_customer?.name ?? ""}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
                        ),
                        Text(
                          'สร้างโดย: ${widget.task.createdBy} | วันที่: ${DateFormat('dd/MM/yy HH:mm').format(widget.task.createdAt.toDate())}',
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_forever_outlined, color: Colors.red),
                    onPressed: _deleteTask,
                    tooltip: 'ลบงานทั้งหมด',
                  ),
                ],
              ),
              const Divider(),
              if (_isLoadingDetails)
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Center(child: LinearProgressIndicator()),
                )
              else if (_sourceMessages.isNotEmpty)
                ..._sourceMessages.map((msg) => Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 8.0),
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              "ข้อความ (${DateFormat('dd/MM/yy HH:mm').format(msg.timestamp.toDate())}):",
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)
                            ),
                          ),
                          Checkbox(
                            value: widget.task.messageStatus[msg.id] ?? false,
                            onChanged: (value) => _updateMessageStatus(msg.id, value ?? false),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                            onPressed: () => _removeMessageFromTask(msg.id),
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (msg.imageUrls.isNotEmpty) _buildImageGrid(msg.imageUrls),
                      if (msg.text.isNotEmpty) Text(msg.text),
                    ],
                  ),
                )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageGrid(List<String> imageUrls) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: imageUrls.length,
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) {
              return _FullScreenImageViewer(
                images: imageUrls.map((url) => NetworkImage(url)).toList(),
                initialIndex: index,
              );
            }));
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              imageUrls[index],
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                return progress == null ? child : const Center(child: CircularProgressIndicator());
              },
            ),
          ),
        );
      },
    );
  }
}


// #############################################################################
// #                             Chat Message Bubble (UPDATED)                 #
// #############################################################################
class _ChatMessageBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ChatMessageBubble({
    required this.message,
    required this.onEdit,
    required this.onDelete,
  });

  Widget _buildMessageContent(BuildContext context) {
    final RegExp tagRegex = RegExp(r'@([CEce])-([\w-]+)\[([^\]]+)\]');
    List<TextSpan> textSpans = [];
    
    message.text.splitMapJoin(
      tagRegex,
      onMatch: (match) {
        final id = match.group(2);
        final name = match.group(3);
        textSpans.add(
          TextSpan(
            text: '$id - $name',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).primaryColor,
              backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
            ),
          )
        );
        return '';
      },
      onNonMatch: (nonMatch) {
        textSpans.add(TextSpan(text: nonMatch, style: const TextStyle(color: Colors.black87)));
        return '';
      },
    );

    return RichText(text: TextSpan(children: textSpans));
  }

  @override
  Widget build(BuildContext context) {
    final isMe = message.userId == FirebaseAuth.instance.currentUser?.uid;
    final alignment = isMe ? Alignment.centerRight : Alignment.centerLeft;
    final color = isMe ? Colors.blue.shade100 : Colors.grey.shade200;

    return Container(
      alignment: alignment,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.userName,
              style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor),
            ),
            if (message.imageUrls.isNotEmpty) _buildImageGrid(context),
            if (message.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: _buildMessageContent(context),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat('HH:mm').format(message.timestamp.toDate()),
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
                if (isMe) ...[
                  IconButton(
                    icon: const Icon(Icons.edit, size: 14),
                    onPressed: onEdit,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 14, color: Colors.red),
                    onPressed: onDelete,
                  )
                ]
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageGrid(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: message.imageUrls.length,
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) {
              return _FullScreenImageViewer(
                images: message.imageUrls.map((url) => NetworkImage(url)).toList(),
                initialIndex: index,
              );
            }));
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              message.imageUrls[index],
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                return progress == null ? child : const Center(child: CircularProgressIndicator());
              },
            ),
          ),
        );
      },
    );
  }
}

// #############################################################################
// #                         Tag Selection Dialog (UPDATED)                      #
// #############################################################################

class _TagSelectionDialog extends StatefulWidget {
  const _TagSelectionDialog();

  @override
  State<_TagSelectionDialog> createState() => _TagSelectionDialogState();
}

class _TagSelectionDialogState extends State<_TagSelectionDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  List<DocumentSnapshot> _searchResults = [];
  bool _isLoading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      _performSearch(_searchController.text);
    });
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _performSearch(_searchController.text);
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isLoading = false;
      });
      return;
    }
    
    setState(() => _isLoading = true);

    List<DocumentSnapshot> finalResults = [];

    if (_tabController.index == 0) { // Customers
      final customersRef = FirebaseFirestore.instance.collection('customers');
      
      final nameQuery = customersRef
          .where('ชื่อลูกค้า', isGreaterThanOrEqualTo: query)
          .where('ชื่อลูกค้า', isLessThanOrEqualTo: '$query\uf8ff')
          .limit(10)
          .get();
      
      final idQuery = customersRef
          .where('รหัสลูกค้า', isGreaterThanOrEqualTo: query)
          .where('รหัสลูกค้า', isLessThanOrEqualTo: '$query\uf8ff')
          .limit(10)
          .get();

      final results = await Future.wait([nameQuery, idQuery]);
      final nameDocs = results[0].docs;
      final idDocs = results[1].docs;

      final Map<String, DocumentSnapshot> uniqueDocs = {};
      for (var doc in [...nameDocs, ...idDocs]) {
        uniqueDocs[doc.id] = doc;
      }
      finalResults = uniqueDocs.values.toList();

    } else { // Employees
      final snapshot = await FirebaseFirestore.instance
          .collection('salespeople')
          .where('employeeId', isGreaterThanOrEqualTo: query)
          .where('employeeId', isLessThanOrEqualTo: '$query\uf8ff')
          .limit(10)
          .get();
      finalResults = snapshot.docs;
    }

    if(mounted) {
      setState(() {
        _searchResults = finalResults;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('แท็กพนักงาน / ลูกค้า'),
      contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'ลูกค้า'),
                Tab(text: 'พนักงาน'),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'ค้นหา...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _searchResults.isEmpty
                      ? const Center(child: Text('ไม่พบข้อมูล'))
                      : ListView.builder(
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final doc = _searchResults[index];
                            final data = doc.data() as Map<String, dynamic>;
                            
                            String title;
                            String subtitle;
                            String tag;

                            if (_tabController.index == 0) {
                              final customerId = data['รหัสลูกค้า'] ?? 'N/A';
                              final customerName = data['ชื่อลูกค้า'] ?? 'N/A';
                              title = customerName;
                              subtitle = 'รหัส: $customerId';
                              tag = '@C-$customerId[$customerName]';
                            } else {
                              final employeeId = data['employeeId'] ?? 'N/A';
                              final employeeName = data['displayName'] ?? 'N/A';
                              title = employeeName;
                              subtitle = 'รหัส: $employeeId';
                              tag = '@E-$employeeId[$employeeName]';
                            }

                            return ListTile(
                              title: Text(title),
                              subtitle: Text(subtitle),
                              onTap: () {
                                Navigator.of(context).pop(tag);
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ยกเลิก'),
        ),
      ],
    );
  }
}

// *** UPDATED: Password Confirmation Dialog ***
class _PasswordConfirmationDialog extends StatefulWidget {
  const _PasswordConfirmationDialog();

  @override
  State<_PasswordConfirmationDialog> createState() => __PasswordConfirmationDialogState();
}

class __PasswordConfirmationDialogState extends State<_PasswordConfirmationDialog> {
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ยืนยันการลบ'),
      content: TextField(
        controller: _passwordController,
        autofocus: true,
        obscureText: true,
        decoration: const InputDecoration(
          labelText: 'กรุณาใส่รหัสผ่าน',
          icon: Icon(Icons.lock_outline),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(_passwordController.text);
          },
          child: const Text('ยืนยัน'),
        ),
      ],
    );
  }
}

// *** UPDATED: Full Screen Image Viewer Widget to handle various image types ***
class _FullScreenImageViewer extends StatelessWidget {
  final List<dynamic> images; // Can be List<Uint8List> or List<ImageProvider>
  final int initialIndex;

  const _FullScreenImageViewer({
    required this.images,
    required this.initialIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: PageView.builder(
        controller: PageController(initialPage: initialIndex),
        itemCount: images.length,
        itemBuilder: (context, index) {
          final item = images[index];
          Widget imageWidget;

          if (item is Uint8List) {
            imageWidget = Image.memory(item, fit: BoxFit.contain);
          } else if (item is ImageProvider) {
            imageWidget = Image(image: item, fit: BoxFit.contain);
          } else {
            imageWidget = const Center(child: Text('Unsupported image type', style: TextStyle(color: Colors.white)));
          }

          return InteractiveViewer(
            child: imageWidget,
          );
        },
      ),
    );
  }
}
