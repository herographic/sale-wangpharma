// lib/screens/profile_screen.dart

import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  final _auth = FirebaseAuth.instance;

  // Use XFile to handle web and mobile uniformly from the picker
  XFile? _selectedImageFile;
  // For web preview, we need to store the image bytes
  Uint8List? _webImageBytes;

  @override
  void initState() {
    super.initState();
    _nameController.text = _auth.currentUser?.displayName ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    // Request a smaller image to save bandwidth and storage
    final pickedFile = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 50, maxWidth: 800);

    if (pickedFile != null) {
      _selectedImageFile = pickedFile;
      // If on web, read the file's bytes to generate a preview
      if (kIsWeb) {
        _webImageBytes = await pickedFile.readAsBytes();
      }
      // Re-render the widget to show the new image preview
      setState(() {});
    }
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = _auth.currentUser;
      if (user == null) return;

      String? photoURL = user.photoURL;

      // 1. Upload new image to Firebase Storage if one was selected
      if (_selectedImageFile != null) {
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('profile_pictures')
            .child('${user.uid}.jpg');

        // Handle upload based on the platform (Web vs. Mobile)
        if (kIsWeb) {
          final imageBytes = await _selectedImageFile!.readAsBytes();
          // Use putData for web
          await storageRef.putData(
              imageBytes, SettableMetadata(contentType: 'image/jpeg'));
        } else {
          // Use putFile for mobile (iOS/Android)
          await storageRef.putFile(File(_selectedImageFile!.path));
        }

        photoURL = await storageRef.getDownloadURL();
      }

      // 2. Update user's display name and photo URL in Firebase Auth
      final newName = _nameController.text.trim();
      if (newName != user.displayName || photoURL != user.photoURL) {
        await user.updateProfile(displayName: newName, photoURL: photoURL);
        // Reload user to get the latest data reflected in the app
        await user.reload();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('บันทึกโปรไฟล์สำเร็จ!'),
              backgroundColor: Colors.green),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('เกิดข้อผิดพลาด: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Helper to get the correct image provider for the CircleAvatar
  ImageProvider? _getImageProvider() {
    // If a new image was picked on the web, use its bytes
    if (kIsWeb && _webImageBytes != null) {
      return MemoryImage(_webImageBytes!);
    }
    // If a new image was picked on mobile, use its file path
    if (!kIsWeb && _selectedImageFile != null) {
      return FileImage(File(_selectedImageFile!.path));
    }
    // If there is an existing photoURL from Firebase, use that
    if (_auth.currentUser?.photoURL != null) {
      return NetworkImage(_auth.currentUser!.photoURL!);
    }
    // If no image is available, return null
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    final imageProvider = _getImageProvider();

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
          title: const Text('ตั้งค่าโปรไฟล์',
              style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Profile Picture
                      GestureDetector(
                        onTap: _pickImage,
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 60,
                              backgroundColor: Colors.grey.shade200,
                              backgroundImage: imageProvider,
                              child: (imageProvider == null)
                                  ? Icon(Icons.person,
                                      size: 60, color: Colors.grey.shade400)
                                  : null,
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: CircleAvatar(
                                radius: 20,
                                backgroundColor: Theme.of(context).primaryColor,
                                child: const Icon(Icons.camera_alt,
                                    color: Colors.white, size: 20),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        user?.email ?? 'N/A',
                        style:
                            TextStyle(fontSize: 16, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 24),

                      // Display Name Field
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'ชื่อที่แสดง',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'กรุณาใส่ชื่อที่ต้องการแสดง';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 32),

                      // Save Button
                      SizedBox(
                        width: double.infinity,
                        child: _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : ElevatedButton.icon(
                                icon: const Icon(Icons.save_outlined),
                                label: const Text('บันทึกการเปลี่ยนแปลง'),
                                onPressed: _updateProfile,
                                style: ElevatedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  textStyle: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
