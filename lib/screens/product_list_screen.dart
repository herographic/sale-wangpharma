// lib/screens/product_list_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:salewang/models/product.dart';
import 'package:salewang/widgets/product_list_item_card.dart'; // Import the new card widget
import 'dart:async';

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Product> _searchResults = [];
  bool _isLoading = false;
  bool _hasSearched = false;
  Timer? _debounce;

  // Keywords for items that should be ranked lower in search results.
  final List<String> _lowPriorityKeywords = const [
    'ฟรี', 'แจก', '-', 'ยกเลิก', 'รีเบท', 'สนับสนุน', 'ส่งเสริม', 'โฆษณา', 'โอน'
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
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
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _hasSearched = false;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _hasSearched = true;
    });

    try {
      final productsRef = FirebaseFirestore.instance.collection('products');
      
      const int fetchLimit = 20;
      final nameQuery = productsRef
          .where('รายละเอียด', isGreaterThanOrEqualTo: query)
          .where('รายละเอียด', isLessThanOrEqualTo: '$query\uf8ff')
          .limit(fetchLimit);
          
      final idQuery = productsRef
          .where('รหัสสินค้า', isGreaterThanOrEqualTo: query)
          .where('รหัสสินค้า', isLessThanOrEqualTo: '$query\uf8ff')
          .limit(fetchLimit);

      final results = await Future.wait([nameQuery.get(), idQuery.get()]);
      final nameDocs = results[0].docs;
      final idDocs = results[1].docs;

      final Map<String, Product> uniqueProducts = {};
      for (var doc in [...nameDocs, ...idDocs]) {
        uniqueProducts[doc.id] = Product.fromFirestore(doc);
      }

      final List<Product> sellableItems = [];
      final List<Product> otherItems = [];

      for (final product in uniqueProducts.values) {
        final bool isLowPriority = _lowPriorityKeywords.any((keyword) => product.description.trim().startsWith(keyword));
        if (isLowPriority) {
          otherItems.add(product);
        } else {
          sellableItems.add(product);
        }
      }
      
      final sortedList = [...sellableItems, ...otherItems];

      const int displayLimit = 10; // Increased display limit
      _searchResults = sortedList.length > displayLimit ? sortedList.sublist(0, displayLimit) : sortedList;

    } catch (e) {
      _showErrorSnackbar('เกิดข้อผิดพลาดในการค้นหา: $e');
      _searchResults = [];
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  void _showErrorSnackbar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'ค้นหา (ชื่อ หรือ รหัสสินค้า)',
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                prefixIcon: const Icon(Icons.search, color: Colors.white),
                filled: true,
                fillColor: Colors.black.withOpacity(0.2),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.5)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white),
                ),
              ),
              style: const TextStyle(color: Colors.white),
            ),
          ),
          Expanded(
            child: _buildResultsWidget(),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsWidget() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    if (!_hasSearched) {
      return const Center(
        child: Text(
          'กรุณาพิมพ์เพื่อค้นหาสินค้า...',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return const Center(
        child: Text(
          'ไม่พบข้อมูลที่ค้นหา',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
      );
    }

    return ListView.builder(
      // Removed padding from ListView to let the Card handle its own margin.
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final product = _searchResults[index];
        // Use the new custom widget for displaying product info.
        return ProductListItemCard(product: product);
      },
    );
  }
}
