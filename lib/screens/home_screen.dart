// lib/screens/home_screen.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:salewang/screens/call_summary_screen.dart';
import 'package:salewang/screens/customer_ranking_screen.dart';
import 'package:salewang/screens/daily_pending_so_screen.dart';
import 'package:salewang/screens/daily_report_screen.dart';
import 'package:salewang/screens/key_order_screen.dart';
import 'package:salewang/screens/new_arrivals_screen.dart';
import 'package:salewang/screens/price_negotiation_screen.dart';
import 'package:salewang/screens/rebate_year_screen.dart';
import 'package:salewang/screens/sales_summary_screen.dart';
import 'package:salewang/screens/sales_summary_time_screen.dart';
import 'package:salewang/screens/task_tracker_screen.dart';
import 'package:salewang/screens/transport_status_screen.dart';
import 'package:salewang/screens/wholesaler_list_screen.dart';
import 'package:salewang/screens/visit_planner_screen.dart';
import 'package:salewang/widgets/sales_history_graph_widget.dart';
import 'package:salewang/widgets/salesperson_slider.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

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
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const WholesalerListScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> menuItems = [
      {
        'icon': Icons.monetization_on_outlined,
        'title': 'ค้นหาลูกค้า',
        'page': const SalesSummaryScreen(),
        'gradient': const LinearGradient(colors: [Color(0xFFF9A825), Color(0xFFFBC02D)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      },
      {
        'icon': Icons.leaderboard_outlined,
        'title': 'อันดับลูกค้า',
        'page': const CustomerRankingScreen(),
        'gradient': const LinearGradient(colors: [Color(0xFF8E24AA), Color(0xFFAB47BC)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      },
      {
        'icon': Icons.edit_note_outlined,
        'title': 'คีย์ออเดอร์',
        'page': const KeyOrderScreen(),
        'gradient': const LinearGradient(colors: [Color(0xFFD81B60), Color(0xFFF06292)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      },
      {
        'icon': Icons.summarize_outlined,
        'title': 'สรุปการโทร',
        'page': const CallSummaryScreen(),
        'gradient': const LinearGradient(colors: [Color(0xFF1E88E5), Color(0xFF42A5F5)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      },
      {
        'icon': Icons.stacked_bar_chart,
        'title': 'สรุปการขาย',
  'page': const SalesSummaryTimeScreen(),
        'gradient': const LinearGradient(colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      },
      {
        'icon': Icons.history_edu_outlined,
        'title': 'สรุปย้อนหลัง',
        'page': const DailyReportScreen(),
        'gradient': const LinearGradient(colors: [Color(0xFF6D4C41), Color(0xFF8D6E63)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      },
      {
        'icon': Icons.inventory_2_outlined,
        'title': 'สินค้าเข้าใหม่',
        'page': const NewArrivalsScreen(),
        'gradient': const LinearGradient(colors: [Color(0xFF43A047), Color(0xFF66BB6A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      },
      {
        'icon': Icons.pending_actions_outlined,
        'title': 'SO ค้างส่ง',
        'page': const DailyPendingSoScreen(),
        'gradient': const LinearGradient(colors: [Color(0xFF00897B), Color(0xFF26A69A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      },
       {
        'icon': Icons.price_change_outlined,
        'title': 'ต่อรองราคา',
        'page': const PriceNegotiationScreen(),
        'gradient': const LinearGradient(colors: [Color(0xFFEF6C00), Color(0xFFFB8C00)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      },
      {
        'icon': Icons.card_giftcard_outlined,
        'title': 'ตรวจสอบรีเบท',
        'page': const RebateYearScreen(),
        'gradient': const LinearGradient(colors: [Color(0xFF5E35B1), Color(0xFF7E57C2)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      },
      {
        'icon': Icons.add_business_outlined,
        'title': 'บันทึกยี่ปั๊ว',
        'page': null,
        'onTap': () => _showPasswordDialog(context),
        'gradient': const LinearGradient(colors: [Color(0xFF455A64), Color(0xFF607D8B)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      },
      {
        'icon': Icons.local_shipping_outlined,
        'title': 'สถานะขนส่ง',
        'page': const TransportStatusScreen(),
        'gradient': const LinearGradient(colors: [Color(0xFF00838F), Color(0xFF00ACC1)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      },
      {
        'icon': Icons.rule_folder_outlined,
        'title': 'ติดตามงาน',
        'page': const TaskTrackerScreen(),
        'gradient': const LinearGradient(colors: [Color(0xFFC62828), Color(0xFFF44336)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      },
      {
        'icon': Icons.event_note_outlined,
        'title': 'วางแผน',
        'page': const VisitPlannerScreen(),
        'gradient': const LinearGradient(colors: [Color(0xFF00695C), Color(0xFF26A69A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      },
    ];

    return Container(
      color: Colors.transparent,
      child: ListView(
        padding: const EdgeInsets.all(12.0),
        children: [
          const SalesHistoryGraphWidget(),
          const SizedBox(height: 20),
          const SalespersonSlider(),
          const SizedBox(height: 20),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.9,
            ),
            itemCount: menuItems.length,
            itemBuilder: (context, index) {
              final item = menuItems[index];
              return _MenuCard(
                title: item['title'],
                icon: item['icon'],
                gradient: item['gradient'],
                onTap: () {
                  if (item['onTap'] != null) {
                    item['onTap']();
                  } else if (item['page'] != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => item['page']),
                    );
                  }
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Gradient gradient;
  final VoidCallback onTap;

  const _MenuCard({
    required this.title,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: gradient,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(icon, size: 32, color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: Colors.black26,
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          )
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
