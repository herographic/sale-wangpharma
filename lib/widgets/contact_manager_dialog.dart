// lib/widgets/contact_manager_dialog.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:salewang/models/customer.dart';
import 'package:salewang/utils/launcher_helper.dart';

class ContactManagerDialog extends StatefulWidget {
  final Customer customer;

  const ContactManagerDialog({super.key, required this.customer});

  @override
  State<ContactManagerDialog> createState() => _ContactManagerDialogState();
}

class _ContactManagerDialogState extends State<ContactManagerDialog> {
  late Stream<DocumentSnapshot> _customerStream;

  @override
  void initState() {
    super.initState();
    _customerStream = FirebaseFirestore.instance
        .collection('customers')
        .doc(widget.customer.id)
        .snapshots();
  }

  // --- DIALOG FOR CONFIRMATION ---
  Future<bool> _showConfirmationDialog({
    required BuildContext context,
    required String title,
    required String content,
    required String confirmText,
    Color? confirmColor,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: confirmColor),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // --- DIALOG FOR ADD/EDIT FORM ---
  void _showContactForm({Map<String, String>? contact, int? index}) {
    final bool isEditing = contact != null;
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: isEditing ? contact['name'] : '');
    final phoneController = TextEditingController(text: isEditing ? contact['phone'] : '');

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(isEditing ? 'แก้ไขผู้ติดต่อ' : 'เพิ่มผู้ติดต่อใหม่'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'ชื่อผู้ติดต่อ', icon: Icon(Icons.person)),
                  validator: (value) => (value == null || value.isEmpty) ? 'กรุณาใส่ชื่อ' : null,
                ),
                TextFormField(
                  controller: phoneController,
                  decoration: const InputDecoration(labelText: 'เบอร์โทรศัพท์', icon: Icon(Icons.phone)),
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'กรุณาใส่เบอร์โทร';
                    if (!RegExp(r'^[0-9-]{9,}$').hasMatch(value)) return 'รูปแบบเบอร์โทรไม่ถูกต้อง';
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('ยกเลิก')),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  final newContact = {'name': nameController.text.trim(), 'phone': phoneController.text.trim()};
                  final docRef = FirebaseFirestore.instance.collection('customers').doc(widget.customer.id);
                  
                  final customerDoc = await docRef.get();
                  final currentContacts = List<Map<String, dynamic>>.from(customerDoc.data()?['contacts'] ?? []);

                  if (isEditing) {
                    currentContacts[index!] = newContact;
                  } else {
                    currentContacts.add(newContact);
                  }
                  
                  await docRef.update({'contacts': currentContacts});
                  Navigator.of(dialogContext).pop();
                }
              },
              child: const Text('บันทึก'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('จัดการผู้ติดต่อ'),
      contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: StreamBuilder<DocumentSnapshot>(
          stream: _customerStream,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final customerData = snapshot.data!.data() as Map<String, dynamic>?;
            final contacts = List<Map<String, String>>.from((customerData?['contacts'] as List<dynamic>? ?? []).map((e) => Map<String, String>.from(e)));

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.customer.name, style: Theme.of(context).textTheme.titleMedium),
                const Divider(height: 20),
                Expanded(
                  child: contacts.isEmpty
                      ? const Center(child: Text('ไม่มีข้อมูลผู้ติดต่อ'))
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: contacts.length,
                          itemBuilder: (context, index) {
                            return _buildContactCard(contacts, index);
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('เพิ่มผู้ติดต่อใหม่'),
                    onPressed: _showContactForm,
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ปิด'),
        ),
      ],
    );
  }

  // --- NEW BEAUTIFUL CONTACT CARD WIDGET ---
  Widget _buildContactCard(List<Map<String, String>> contacts, int index) {
    final contact = contacts[index];
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.grey.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.person_pin, color: Theme.of(context).primaryColor, size: 28),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(contact['name'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(contact['phone'] ?? 'N/A', style: TextStyle(color: Colors.grey.shade700, fontSize: 15)),
                  ],
                ),
              ],
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // EDIT BUTTON
                TextButton.icon(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('แก้ไข'),
                  onPressed: () => _showContactForm(contact: contact, index: index),
                ),
                // DELETE BUTTON
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('ลบ'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                  onPressed: () async {
                    final confirm = await _showConfirmationDialog(
                      context: context,
                      title: 'ยืนยันการลบ',
                      content: 'คุณแน่ใจหรือไม่ว่าต้องการลบผู้ติดต่อ "${contact['name']}"?',
                      confirmText: 'ลบ',
                      confirmColor: Colors.red.shade700,
                    );
                    if (confirm) {
                      final currentContacts = List<Map<String, dynamic>>.from(contacts);
                      currentContacts.removeAt(index);
                      await FirebaseFirestore.instance
                          .collection('customers')
                          .doc(widget.customer.id)
                          .update({'contacts': currentContacts});
                    }
                  },
                ),
                // CALL BUTTON
                ElevatedButton.icon(
                  icon: const Icon(Icons.call_outlined, size: 18),
                  label: const Text('โทร'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => LauncherHelper.makeAndLogPhoneCall(
                    context: context,
                    phoneNumber: contact['phone'] ?? '',
                    customer: widget.customer,
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
