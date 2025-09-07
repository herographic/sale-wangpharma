// lib/widgets/main_drawer.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:salewang/screens/admin_upload_screen.dart';
import 'package:salewang/screens/daily_report_screen.dart';
import 'package:salewang/screens/data_sync_screen.dart'; // IMPORT THE NEW SCREEN
import 'package:salewang/screens/employee_role_manager_screen.dart';
import 'package:salewang/screens/profile_screen.dart';
import 'package:salewang/screens/wholesaler_list_screen.dart';

class MainDrawer extends StatelessWidget {
  final Function(int) onSelectItem;

  const MainDrawer({super.key, required this.onSelectItem});

  Future<void> _showPasswordDialog(BuildContext context) async {
    final passwordController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('กรุณาใส่รหัสผ่าน'),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'รหัสผ่าน'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
          ElevatedButton(
            onPressed: () {
              if (passwordController.text == '141300') {
                Navigator.pop(context, true);
              } else {
                Navigator.pop(context, false);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('รหัสผ่านไม่ถูกต้อง'), backgroundColor: Colors.red),
                );
              }
            },
            child: const Text('ตกลง'),
          ),
        ],
      ),
    );

    if (result == true) {
      Navigator.pop(context); // Close the drawer first
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const WholesalerListScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final bool isAdmin = user?.email?.startsWith('0539@') ?? false;

    ImageProvider? backgroundImage;
    if (user?.photoURL != null) {
      backgroundImage = NetworkImage(user!.photoURL!);
    }

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            accountName: Text(
              user?.displayName ?? 'ผู้ใช้งาน',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            accountEmail: Text(user?.email ?? 'ไม่พบอีเมล'),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              backgroundImage: backgroundImage,
              child: (backgroundImage == null)
                  ? Text(
                      user?.displayName?.isNotEmpty == true
                          ? user!.displayName![0].toUpperCase()
                          : (user?.email?.isNotEmpty == true
                              ? user!.email![0].toUpperCase()
                              : '?'),
                      style:
                          const TextStyle(fontSize: 40.0, color: Colors.indigo),
                    )
                  : null,
            ),
            decoration: const BoxDecoration(
              color: Colors.indigo,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.home_outlined),
            title: const Text('หน้าหลัก'),
            onTap: () => onSelectItem(0),
          ),
          ListTile(
            leading: const Icon(Icons.people_outline),
            title: const Text('รายชื่อลูกค้า'),
            onTap: () => onSelectItem(1),
          ),
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: const Text('สินค้าทั้งหมด'),
            onTap: () => onSelectItem(2),
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('ใบสั่งจอง (แอป)'),
            onTap: () => onSelectItem(4),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.history_edu_outlined),
            title: const Text('รายงานย้อนหลัง'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DailyReportScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.add_business_outlined),
            title: const Text('บันทึกยี่ปั๊ว'),
            onTap: () => _showPasswordDialog(context),
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('ตั้งค่าโปรไฟล์'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfileScreen()),
              ).then((_) {
                (context as Element).reassemble();
              });
            },
          ),
          if (isAdmin) ...[
            const Divider(),
            // NEW: Data Sync Menu Item
            ListTile(
              leading: const Icon(Icons.sync_alt_outlined),
              title: const Text('ซิงค์ข้อมูล API (Admin)'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const DataSyncScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('อัปโหลดข้อมูล (Admin)'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const AdminUploadScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.manage_accounts_outlined),
              title: const Text('จัดการตำแหน่ง (Admin)'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const EmployeeRoleManagerScreen()),
                );
              },
            ),
          ],
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('ออกจากระบบ'),
            onTap: () async {
              Navigator.pop(context);
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
    );
  }
}
