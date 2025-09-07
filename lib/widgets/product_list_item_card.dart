// lib/widgets/product_list_item_card.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:salewang/models/product.dart';
import 'package:salewang/screens/product_detail_screen.dart';
import 'dart:math';

// A dedicated class to hold calculated unit information for clarity.
class UnitInfo {
  final String name;
  final double multiplier; // How many base units are in this unit.
  final double priceA;
  final double priceB;
  final double priceC;

  UnitInfo({
    required this.name,
    required this.multiplier,
    required this.priceA,
    required this.priceB,
    required this.priceC,
  });
}

class ProductListItemCard extends StatelessWidget {
  final Product product;
  final NumberFormat currencyFormat = NumberFormat("#,##0.00", "en_US");
  final NumberFormat quantityFormat = NumberFormat("#,##0", "en_US");

  ProductListItemCard({super.key, required this.product});

  // This function processes the product data based on the new logic.
  // The price in Firestore is for the SMALLEST unit, and we MULTIPLY to get the price of larger units.
  List<UnitInfo> _getUnitInfo() {
    final List<UnitInfo> units = [];
    
    final allUnits = [
      {'name': product.unit1, 'ratio': product.ratio1},
      {'name': product.unit2, 'ratio': product.ratio2},
      {'name': product.unit3, 'ratio': product.ratio3},
    ];

    // Filter out invalid units and find the largest ratio, which corresponds to the smallest unit.
    final validUnits = allUnits.where((u) => (u['name'] as String).isNotEmpty && (u['ratio'] as double) > 0).toList();
    if (validUnits.isEmpty) return [];

    double maxRatio = validUnits.map((u) => u['ratio'] as double).reduce(max);

    for (var unitData in validUnits) {
      final String name = unitData['name'] as String;
      final double ratio = unitData['ratio'] as double;
      
      // The multiplier is how many base units (the one with maxRatio) are in the current unit.
      final double multiplier = maxRatio / ratio;

      units.add(UnitInfo(
        name: name,
        multiplier: multiplier,
        // Calculate the price for this unit by multiplying the base price by the multiplier.
        priceA: product.priceA * multiplier,
        priceB: product.priceB * multiplier,
        priceC: product.priceC * multiplier,
      ));
    }
    
    // Sort units by multiplier, from smallest multiplier (base unit) to largest (largest unit).
    units.sort((a, b) => a.multiplier.compareTo(b.multiplier));
    
    return units;
  }

  // Helper widget to build each price level row (A, B, C).
  Widget _buildPriceRow({
    required String level,
    required Color color,
    required List<UnitInfo> unitInfos,
    required double Function(UnitInfo) getPrice,
  }) {
    // Create a list of widgets, each representing a price for a unit.
    List<Widget> priceWidgets = [];
    for (int i = 0; i < unitInfos.length; i++) {
      final unit = unitInfos[i];
      priceWidgets.add(
        Flexible(
          child: Text(
            '${currencyFormat.format(getPrice(unit))}/${unit.name}',
            style: TextStyle(fontSize: 13, color: Colors.grey[800]),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
      // Add a separator if it's not the last item.
      if (i < unitInfos.length - 1) {
        priceWidgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Text('|', style: TextStyle(color: Colors.grey[300])),
          ),
        );
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Price Level Label (A, B, C)
        Text(
          'ราคา $level: ',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        // The row of prices for each unit
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: priceWidgets,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<UnitInfo> unitInfos = _getUnitInfo();

    return Card(
      color: Colors.white.withOpacity(0.95),
      margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProductDetailScreen(product: product),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // -- Row 1: Product ID and Supplier Product ID --
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('รหัส: ${product.id}', style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                  Text(product.supplierProductId, style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                ],
              ),
              const SizedBox(height: 6),

              // -- Row 2: Description --
              Text(product.description, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),

              // -- Row 3: Stock Quantity --
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'คงเหลือ: ${quantityFormat.format(product.stockQuantity)}',
                  style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              const Divider(height: 16),

              // -- NEW: Grouped Unit Price Breakdown --
              if (unitInfos.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPriceRow(
                      level: 'A',
                      color: Colors.green.shade700,
                      unitInfos: unitInfos,
                      getPrice: (unit) => unit.priceA,
                    ),
                    const SizedBox(height: 4),
                    _buildPriceRow(
                      level: 'B',
                      color: Colors.orange.shade800,
                      unitInfos: unitInfos,
                      getPrice: (unit) => unit.priceB,
                    ),
                    const SizedBox(height: 4),
                    _buildPriceRow(
                      level: 'C',
                      color: Colors.blue.shade800,
                      unitInfos: unitInfos,
                      getPrice: (unit) => unit.priceC,
                    ),
                  ],
                )
              else
                const Text('ไม่สามารถคำนวณราคาต่อหน่วยได้', style: TextStyle(color: Colors.red, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
