// lib/models/product.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class Product {
  // Fields from price.csv
  final String id; // รหัสสินค้า
  final String description;
  final String department;
  final String unit1;
  final double ratio1;
  final String unit2;
  final double ratio2;
  final String unit3;
  final double ratio3;
  final String supplierId;
  final String supplierProductId;
  final double minQuantity;
  final double reorderQuantity;
  final double standardCostPrice;
  final double lastPurchasePrice;
  final double priceA;
  final double priceB;
  final double priceC;
  final String lastSaleDate;
  final String lastPurchaseDate;

  // Fields from stock.csv
  final String category;
  final double stockQuantity;
  final String storageLocation;

  Product({
    required this.id,
    required this.description,
    required this.department,
    required this.unit1,
    required this.ratio1,
    required this.unit2,
    required this.ratio2,
    required this.unit3,
    required this.ratio3,
    required this.supplierId,
    required this.supplierProductId,
    required this.minQuantity,
    required this.reorderQuantity,
    required this.standardCostPrice,
    required this.lastPurchasePrice,
    required this.priceA,
    required this.priceB,
    required this.priceC,
    required this.lastSaleDate,
    required this.lastPurchaseDate,
    required this.category,
    required this.stockQuantity,
    required this.storageLocation,
  });

  // Helper function to safely parse doubles
  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  factory Product.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Product(
      id: doc.id,
      description: data['รายละเอียด'] ?? '',
      department: data['แผนก'] ?? '',
      unit1: data['หน่วยนับ 1'] ?? '',
      ratio1: _parseDouble(data['อัตราส่วน 1']),
      unit2: data['หน่วยนับ 2'] ?? '',
      ratio2: _parseDouble(data['อัตราส่วน 2']),
      unit3: data['หน่วยนับ 3'] ?? '',
      ratio3: _parseDouble(data['อัตราส่วน 3']),
      supplierId: data['รหัสผู้จำหน่าย'] ?? '',
      supplierProductId: data['รหัสส/คผู้จำหน่าย'] ?? '',
      minQuantity: _parseDouble(data['จำนวนต่ำสุด']),
      reorderQuantity: _parseDouble(data['จำนวนสั่งต่อครั้ง']),
      standardCostPrice: _parseDouble(data['ราคาต้นทุนมาตรฐาน']),
      lastPurchasePrice: _parseDouble(data['ราคาซื้อล่าสุด']),
      priceA: _parseDouble(data['ราคาขาย A']),
      priceB: _parseDouble(data['ราคาขาย B']),
      priceC: _parseDouble(data['ราคาขาย C']),
      lastSaleDate: data['วันที่ขายล่าสุด'] ?? '',
      lastPurchaseDate: data['วันที่ซื้อล่าสุด'] ?? '',
      category: data['หมวด'] ?? '',
      stockQuantity: _parseDouble(data['จำนวนคงเหลือ']),
      storageLocation: data['สถานที่เก็บ'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'รหัสสินค้า': id,
      'รายละเอียด': description,
      'แผนก': department,
      'หน่วยนับ 1': unit1,
      'อัตราส่วน 1': ratio1,
      'หน่วยนับ 2': unit2,
      'อัตราส่วน 2': ratio2,
      'หน่วยนับ 3': unit3,
      'อัตราส่วน 3': ratio3,
      'รหัสผู้จำหน่าย': supplierId,
      'รหัสส/คผู้จำหน่าย': supplierProductId,
      'จำนวนต่ำสุด': minQuantity,
      'จำนวนสั่งต่อครั้ง': reorderQuantity,
      'ราคาต้นทุนมาตรฐาน': standardCostPrice,
      'ราคาซื้อล่าสุด': lastPurchasePrice,
      'ราคาขาย A': priceA,
      'ราคาขาย B': priceB,
      'ราคาขาย C': priceC,
      'วันที่ขายล่าสุด': lastSaleDate,
      'วันที่ซื้อล่าสุด': lastPurchaseDate,
      'หมวด': category,
      'จำนวนคงเหลือ': stockQuantity,
      'สถานที่เก็บ': storageLocation,
    };
  }
}
