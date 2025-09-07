// lib/screens/product_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:salewang/models/product.dart';
import 'package:salewang/widgets/info_card.dart'; // Helper widget for displaying info

class ProductDetailScreen extends StatelessWidget {
  final Product product;

  const ProductDetailScreen({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat("#,##0.00", "en_US");
    final quantityFormat = NumberFormat("#,##0", "en_US");

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
          title: Text(product.description, style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoCard(
                title: 'ข้อมูลทั่วไป',
                details: {
                  'รหัสสินค้า': product.id,
                  'รายละเอียด': product.description,
                  'แผนก': product.department,
                  'หมวด': product.category,
                  'สถานที่เก็บ': product.storageLocation,
                },
              ),
              const SizedBox(height: 16),
              InfoCard(
                title: 'ราคาขาย',
                details: {
                  'ราคาขาย A': '฿${currencyFormat.format(product.priceA)}',
                  'ราคาขาย B': '฿${currencyFormat.format(product.priceB)}',
                  'ราคาขาย C': '฿${currencyFormat.format(product.priceC)}',
                  'วันที่ขายล่าสุด': product.lastSaleDate.isNotEmpty ? product.lastSaleDate : '-',
                },
              ),
              const SizedBox(height: 16),
              InfoCard(
                title: 'สต็อกและหน่วยนับ',
                details: {
                  'จำนวนคงเหลือ': '${quantityFormat.format(product.stockQuantity)} ${product.unit1}',
                  'จำนวนต่ำสุด': quantityFormat.format(product.minQuantity),
                  'จำนวนสั่งต่อครั้ง': quantityFormat.format(product.reorderQuantity),
                  'หน่วยนับ 1': '${product.unit1} (อัตราส่วน: ${product.ratio1})',
                  'หน่วยนับ 2': '${product.unit2} (อัตราส่วน: ${product.ratio2})',
                  'หน่วยนับ 3': '${product.unit3} (อัตราส่วน: ${product.ratio3})',
                },
              ),
              const SizedBox(height: 16),
              InfoCard(
                title: 'ข้อมูลการจัดซื้อ',
                details: {
                  'ราคาต้นทุนมาตรฐาน': '฿${currencyFormat.format(product.standardCostPrice)}',
                  'ราคาซื้อล่าสุด': '฿${currencyFormat.format(product.lastPurchasePrice)}',
                  'วันที่ซื้อล่าสุด': product.lastPurchaseDate.isNotEmpty ? product.lastPurchaseDate : '-',
                  'รหัสผู้จำหน่าย': product.supplierId.isNotEmpty ? product.supplierId : '-',
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
