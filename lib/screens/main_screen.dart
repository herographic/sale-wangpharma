// lib/screens/main_screen.dart

import 'package:flutter/material.dart';
import 'package:salewang/screens/app_orders_screen.dart';
import 'package:salewang/screens/customer_list_screen.dart';
import 'package:salewang/screens/home_screen.dart';
import 'package:salewang/screens/live_chat_screen.dart'; // Import the new screen
import 'package:salewang/screens/product_list_screen.dart';
import 'package:salewang/widgets/main_drawer.dart';
import 'package:salewang/widgets/salesperson_header.dart';

class MainScreen extends StatefulWidget {
  final int initialIndex;
  const MainScreen({super.key, this.initialIndex = 0});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late int _selectedIndex;
  
  // Replace PlaceholderScreen with the new LiveChatScreen
  static const List<Widget> _pages = <Widget>[
    HomeScreen(),
    CustomerListScreen(),
    ProductListScreen(),
    LiveChatScreen(), // UPDATED
    AppOrdersScreen(),
  ];
  
  static const List<String> _titles = <String>[
    'หน้าหลัก',
    'รายชื่อลูกค้า',
    'สินค้าทั้งหมด',
    'แชทไลฟ์สด', // Title remains the same
    'ใบสั่งจอง (แอป)',
  ];

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
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
          title: Text(_titles[_selectedIndex], style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
        drawer: MainDrawer(onSelectItem: (int index) {
          _onItemTapped(index);
          Navigator.pop(context);
        }),
        body: Column(
          children: [
            const SalespersonHeader(),
            Expanded(
              child: IndexedStack(
                index: _selectedIndex,
                children: _pages,
              ),
            ),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'หน้าหลัก'),
            BottomNavigationBarItem(icon: Icon(Icons.people), label: 'ลูกค้า'),
            BottomNavigationBarItem(icon: Icon(Icons.inventory_2), label: 'สินค้า'),
            BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'แชท'),
            BottomNavigationBarItem(icon: Icon(Icons.receipt_long), label: 'ใบสั่งจอง'),
          ],
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: Theme.of(context).primaryColor,
          unselectedItemColor: Colors.grey[600],
        ),
      ),
    );
  }
}
