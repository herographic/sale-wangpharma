// lib/widgets/product_search_dialog.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:salewang/models/product.dart';

// A result class to return the product, quantity, and selected unit.
class ProductSearchResult {
  final Product product;
  final double quantity;
  final String unit;

  ProductSearchResult({
    required this.product,
    required this.quantity,
    required this.unit,
  });
}

class ProductSearchDialog extends StatefulWidget {
  final Function(ProductSearchResult) onProductAdded;
  final String customerPriceLevel;

  const ProductSearchDialog({
    super.key,
    required this.onProductAdded,
    required this.customerPriceLevel,
  });

  @override
  State<ProductSearchDialog> createState() => _ProductSearchDialogState();
}

class _ProductSearchDialogState extends State<ProductSearchDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<Product> _searchResults = [];
  bool _isLoading = false;
  Timer? _debounce;
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
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      final productsRef = FirebaseFirestore.instance.collection('products');
      
      final nameQuery = productsRef
          .where('รายละเอียด', isGreaterThanOrEqualTo: query)
          .where('รายละเอียด', isLessThanOrEqualTo: '$query\uf8ff')
          .limit(10).get();
          
      final idQuery = productsRef
          .where('รหัสสินค้า', isGreaterThanOrEqualTo: query)
          .where('รหัสสินค้า', isLessThanOrEqualTo: '$query\uf8ff')
          .limit(10).get();

      final results = await Future.wait([nameQuery, idQuery]);
      final allDocs = [...results[0].docs, ...results[1].docs];
      
      final uniqueIds = <String>{};
      final uniqueDocs = allDocs.where((doc) => uniqueIds.add(doc.id)).toList();
      final allProducts = uniqueDocs.map((doc) => Product.fromFirestore(doc)).toList();

      final sellableItems = <Product>[];
      final otherItems = <Product>[];

      for (final product in allProducts) {
        final bool isLowPriority = _lowPriorityKeywords.any((keyword) => product.description.trim().startsWith(keyword));
        if (isLowPriority) {
          otherItems.add(product);
        } else {
          sellableItems.add(product);
        }
      }

      setState(() {
        _searchResults = [...sellableItems, ...otherItems];
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error during product search: $e");
      setState(() {
        _searchResults = [];
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ค้นหาสินค้า'),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      content: SizedBox(
        width: double.maxFinite,
        height: 500,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'ชื่อ หรือ รหัสสินค้า',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _searchResults.isEmpty
                      ? const Center(child: Text('ไม่พบสินค้า'))
                      : ListView.builder(
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final product = _searchResults[index];
                            return _ProductAddItemCard(
                              product: product,
                              onProductAdded: widget.onProductAdded,
                              customerPriceLevel: widget.customerPriceLevel,
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
          child: const Text('ปิด'),
        ),
      ],
    );
  }
}

class _ProductAddItemCard extends StatefulWidget {
  final Product product;
  final Function(ProductSearchResult) onProductAdded;
  final String customerPriceLevel;

  const _ProductAddItemCard({
    required this.product,
    required this.onProductAdded,
    required this.customerPriceLevel,
  });

  @override
  State<_ProductAddItemCard> createState() => _ProductAddItemCardState();
}

class _ProductAddItemCardState extends State<_ProductAddItemCard> {
  double _quantity = 1;
  bool _isAdded = false;
  final NumberFormat _currencyFormat = NumberFormat("#,##0.00", "en_US");

  double _getBasePriceForCustomer() {
    switch (widget.customerPriceLevel.toUpperCase()) {
      case 'B': return widget.product.priceB;
      case 'C': return widget.product.priceC;
      case 'A': default: return widget.product.priceA;
    }
  }

  void _handleAddButtonPressed() {
    // We always use the base unit (unit1) in this simplified version
    final result = ProductSearchResult(
      product: widget.product,
      quantity: _quantity,
      unit: widget.product.unit1,
    );
    widget.onProductAdded(result);

    setState(() => _isAdded = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _isAdded = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final displayPrice = _getBasePriceForCustomer();
    final displayUnit = widget.product.unit1.isNotEmpty ? widget.product.unit1 : 'หน่วย';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.product.description, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('รหัส: ${widget.product.id}', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            const SizedBox(height: 8),

            // Simplified display in a clean row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('ราคา: ${_currencyFormat.format(displayPrice)} / $displayUnit'),
                Text('คงเหลือ: ${widget.product.stockQuantity.toStringAsFixed(0)} $displayUnit'),
              ],
            ),
            
            const Divider(height: 16),
            
            Row(
              children: [
                // Quantity controls
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                ),
                Text(_quantity.toStringAsFixed(0), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => setState(() => _quantity++),
                ),
                const Spacer(),
                // Add to cart button
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    icon: Icon(_isAdded ? Icons.check_circle : Icons.add_shopping_cart, size: 18),
                    label: Text(_isAdded ? 'เพิ่มแล้ว!' : 'เพิ่มลงรายการ'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isAdded ? Colors.green : Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      textStyle: const TextStyle(fontSize: 14)
                    ),
                    onPressed: _isAdded ? null : _handleAddButtonPressed,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
