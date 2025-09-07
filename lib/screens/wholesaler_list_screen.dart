// lib/screens/wholesaler_list_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:salewang/models/wholesaler.dart';
import 'package:salewang/screens/edit_wholesaler_screen.dart';
import 'package:flutter_tts/flutter_tts.dart';

class WholesalerListScreen extends StatelessWidget {
  const WholesalerListScreen({super.key});

  void _navigateAndCreate(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const EditWholesalerScreen(),
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
          title: const Text('บันทึกยี่ปั๊วและคู่แข่ง', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.add_business_outlined),
                      label: const Text('เพิ่มข้อมูลใหม่ (ยี่ปั๊ว / คู่แข่ง)'),
                      onPressed: () => _navigateAndCreate(context),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('wholesalers')
                    .orderBy('lastUpdated', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Colors.white));
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(
                      child: Text('ยังไม่มีข้อมูล\nกดปุ่มด้านบนเพื่อเริ่มต้น',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 16)),
                    );
                  }

                  final wholesalers = snapshot.data!.docs
                      .map((doc) => Wholesaler.fromFirestore(doc))
                      .toList();

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    itemCount: wholesalers.length,
                    itemBuilder: (context, index) {
                      return WholesalerCard(wholesaler: wholesalers[index]);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WholesalerCard extends StatefulWidget {
  final Wholesaler wholesaler;

  const WholesalerCard({super.key, required this.wholesaler});

  @override
  State<WholesalerCard> createState() => _WholesalerCardState();
}

class _WholesalerCardState extends State<WholesalerCard> {
  bool _isChatExpanded = false;
  final _chatController = TextEditingController();
  bool _isSending = false;
  // TTS state
  late final FlutterTts _tts;
  bool _isTtsPlaying = false;
  String? _playingMsgId;

  @override
  void initState() {
    super.initState();
    _tts = FlutterTts();
    _initTts();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('th-TH');
    await _tts.setSpeechRate(0.5); // ช้าลงเพื่อฟังง่าย
    await _tts.setVolume(1.0); // เสียง 100%
    await _tts.setPitch(1.0);

    _tts.setCompletionHandler(() {
      if (!mounted) return;
      setState(() {
        _isTtsPlaying = false;
        _playingMsgId = null;
      });
    });

    _tts.setErrorHandler((msg) {
      if (!mounted) return;
      setState(() {
        _isTtsPlaying = false;
        _playingMsgId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาด TTS: $msg')),
      );
    });
  }

  Future<void> _speakMessage(String text, String msgId) async {
    // Toggle play/stop for the same message
    if (_isTtsPlaying && _playingMsgId == msgId) {
      await _tts.stop();
      if (!mounted) return;
      setState(() {
        _isTtsPlaying = false;
        _playingMsgId = null;
      });
      return;
    }

    // Stop any current speech and play new
    await _tts.stop();
    if (!mounted) return;
    setState(() {
      _isTtsPlaying = true;
      _playingMsgId = msgId;
    });
    await _tts.speak(text);
  }

  @override
  void dispose() {
    _tts.stop();
    _chatController.dispose();
    super.dispose();
  }

  Future<void> _sendChatMessage() async {
    final text = _chatController.text.trim();
    final user = FirebaseAuth.instance.currentUser;
    if (text.isEmpty || user == null) return;

    setState(() => _isSending = true);

    try {
      final chatCollection = FirebaseFirestore.instance
          .collection('wholesalers')
          .doc(widget.wholesaler.id)
          .collection('chat');
      
      await chatCollection.add({
        'text': text,
        'userId': user.uid,
        'userName': user.displayName ?? 'N/A',
        'timestamp': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance
          .collection('wholesalers')
          .doc(widget.wholesaler.id)
          .update({'lastUpdated': Timestamp.now()});
      
      _chatController.clear();

    } catch (e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาด: $e'), backgroundColor: Colors.red)
        );
      }
    } finally {
      if(mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeFormat = DateFormat('dd/MM/yy HH:mm');
    final isWholesaler = widget.wholesaler.type == 'wholesaler';
    final cardColor = isWholesaler ? Colors.white : Colors.orange.shade50;
    final iconData = isWholesaler ? Icons.storefront : Icons.shield_outlined;

    // UPDATED: Combine nickname and last updated time for the subtitle
    final String subtitleText;
    final nickname = widget.wholesaler.nickname;
    if (nickname != null && nickname.isNotEmpty) {
      subtitleText = '$nickname • อัปเดต: ${timeFormat.format(widget.wholesaler.lastUpdated.toDate())}';
    } else {
      subtitleText = 'อัปเดตล่าสุด: ${timeFormat.format(widget.wholesaler.lastUpdated.toDate())}';
    }


    return Card(
      color: cardColor,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16.0, top: 8.0, bottom: 8.0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundImage: widget.wholesaler.logoUrl != null ? NetworkImage(widget.wholesaler.logoUrl!) : null,
                  child: widget.wholesaler.logoUrl == null ? Icon(iconData) : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.wholesaler.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      // UPDATED: Display the new subtitle text
                      Text(subtitleText, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_note_outlined, color: Colors.blueGrey),
                  tooltip: 'แก้ไขข้อมูล',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EditWholesalerScreen(wholesalerId: widget.wholesaler.id),
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: Icon(Icons.chat_bubble_outline, color: _isChatExpanded ? Theme.of(context).primaryColor : Colors.blueGrey),
                  tooltip: 'เปิด/ปิดแชท',
                  onPressed: () {
                    setState(() {
                      _isChatExpanded = !_isChatExpanded;
                    });
                  },
                ),
              ],
            ),
          ),
          Visibility(
            visible: _isChatExpanded,
            child: Column(
              children: [
                const Divider(height: 1),
                _buildChatHistory(),
                _buildChatInput(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatHistory() {
    final user = FirebaseAuth.instance.currentUser;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('wholesalers')
          .doc(widget.wholesaler.id)
          .collection('chat')
          .orderBy('timestamp', descending: true)
          .limit(3)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox(height: 50, child: Center(child: CircularProgressIndicator()));
        if (snapshot.data!.docs.isEmpty) return const SizedBox(height: 50, child: Center(child: Text('ยังไม่มีข้อความ')));
        
        final messages = snapshot.data!.docs;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Column(
            children: messages.map((msg) {
              final isMe = msg['userId'] == user?.uid;
              final timestamp = msg['timestamp'] as Timestamp?;
              // UPDATED: Format the timestamp for display
              final formattedTime = timestamp != null 
                  ? DateFormat('dd/MM/yy HH:mm').format(timestamp.toDate())
                  : '';
              final msgId = msg.id;
              final isPlayingThis = _isTtsPlaying && _playingMsgId == msgId;

              return Align(
                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isMe ? Theme.of(context).primaryColor.withOpacity(0.1) : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: [
                      // Header row: name + TTS button
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Expanded(
                            child: Text(
                              msg['userName'],
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              isPlayingThis ? Icons.stop : Icons.volume_up,
                              color: isPlayingThis ? Colors.red : Colors.blueGrey,
                              size: 18,
                            ),
                            tooltip: isPlayingThis ? 'หยุดอ่านข้อความนี้' : 'อ่านข้อความนี้',
                            onPressed: () {
                              final text = (msg['text'] as String?)?.trim() ?? '';
                              final userName = (msg['userName'] as String?)?.trim() ?? '';
                              // อ่านเฉพาะเนื้อหา เพื่อกระชับ
                              final speakText = text.isEmpty ? userName : text;
                              _speakMessage(speakText, msgId);
                            },
                          ),
                        ],
                      ),
                      // Message text
                      Text(msg['text'], style: const TextStyle(fontSize: 13)),
                      // Time
                      const SizedBox(height: 4),
                      Text(formattedTime, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
              );
            }).toList().reversed.toList(),
          ),
        );
      },
    );
  }

  Widget _buildChatInput() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _chatController,
              decoration: const InputDecoration(
                hintText: 'พิมพ์บันทึกการทำงาน...',
                isDense: true,
              ),
              onSubmitted: (_) => _sendChatMessage(),
            ),
          ),
          IconButton(
            icon: _isSending 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                : const Icon(Icons.send),
            onPressed: _isSending ? null : _sendChatMessage,
            color: Theme.of(context).primaryColor,
          ),
        ],
      ),
    );
  }
}
