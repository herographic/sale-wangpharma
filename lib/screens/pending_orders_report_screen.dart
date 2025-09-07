// lib/screens/pending_orders_report_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:salewang/models/member.dart';
import 'package:salewang/models/sales_order.dart';

class PendingOrdersReportScreen extends StatelessWidget {
  final Member member;
  final List<SalesOrder> pendingOrders;

  const PendingOrdersReportScreen({
    super.key,
    required this.member,
    required this.pendingOrders,
  });

  Future<void> _printReport(BuildContext context) async {
    final doc = pw.Document();
    final font = await PdfGoogleFonts.promptBold();
    final fontRegular = await PdfGoogleFonts.promptRegular();
    final currencyFormat = NumberFormat("#,##0.00", "en_US");
    final dateFormat = DateFormat('d MMMM yyyy', 'th_TH');

    // --- VAT Calculation ---
    final totalAmount = pendingOrders.fold<double>(0.0, (sum, order) => sum + order.totalAmount);
    final vatAmount = totalAmount * 7 / 107;
    final amountBeforeVat = totalAmount - vatAmount;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            // --- PDF Header ---
            _buildPdfHeader(font, fontRegular, dateFormat),
            pw.Divider(thickness: 2, height: 20),
            _buildPdfCustomerInfo(font, fontRegular),
            pw.SizedBox(height: 24),

            // --- PDF Items Table ---
            _buildPdfItemsTable(currencyFormat, font, fontRegular),
            
            // --- PDF Summary ---
            pw.SizedBox(height: 20),
            _buildPdfSummary(currencyFormat, amountBeforeVat, vatAmount, totalAmount, font, fontRegular),
            pw.Divider(height: 20),
            
            // --- PDF Footer ---
            pw.Center(
              child: pw.Text('เอกสารนี้จัดทำเพื่อสรุปรายการค้างส่งเท่านั้น', style: pw.TextStyle(font: fontRegular, fontSize: 9, fontStyle: pw.FontStyle.italic, color: PdfColors.grey)),
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat("#,##0.00", "en_US");
    final dateFormat = DateFormat('d MMMM yyyy', 'th_TH');

    // --- VAT Calculation ---
    final totalAmount = pendingOrders.fold<double>(0.0, (sum, order) => sum + order.totalAmount);
    final vatAmount = totalAmount * 7 / 107;
    final amountBeforeVat = totalAmount - vatAmount;

    return Scaffold(
      // --- THEME FIX: Set background color ---
      backgroundColor: Colors.grey[200], 
      appBar: AppBar(
        title: const Text('รายงานใบสั่งจองค้างส่ง'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: () => _printReport(context),
            tooltip: 'พิมพ์รายงาน',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        // --- NEW LAYOUT: Use a Card for a paper-like feel ---
        child: Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(dateFormat),
                const Divider(thickness: 2, height: 40),
                _buildCustomerInfo(),
                const SizedBox(height: 24),
                _buildItemsTable(currencyFormat),
                const Divider(height: 32),
                _buildSummary(currencyFormat, amountBeforeVat, vatAmount, totalAmount),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- UI WIDGETS (for screen display) ---

  Widget _buildHeader(DateFormat dateFormat) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'บริษัท วังเภสัชฟาร์มาซูติคอล จำกัด',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo.shade800),
              ),
              const Text('23 ซ.พัฒโน ถ.อนุสรณ์อาจาร์ยทอง\nอ.หาดใหญ่ จ.สงขลา 90110'),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('ใบสั่งจอง (ค้างส่ง)', style: TextStyle(fontSize: 20, color: Colors.grey.shade800, fontWeight: FontWeight.bold)),
            Text('SALES ORDER (PENDING)', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            Text('วันที่: ${dateFormat.format(DateTime.now())}', style: const TextStyle(fontSize: 12)),
          ],
        )
      ],
    );
  }

  Widget _buildCustomerInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ข้อมูลลูกค้า', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _buildInfoRow('รหัสลูกค้า:', member.memCode ?? '-'),
        _buildInfoRow('ชื่อลูกค้า:', member.memName ?? '-'),
        _buildInfoRow('ที่อยู่:', member.addressLine1 ?? '-'),
        _buildInfoRow('เบอร์โทร:', member.memTel ?? '-'),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 80, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildItemsTable(NumberFormat currencyFormat) {
    return DataTable(
      columnSpacing: 16.0,
      horizontalMargin: 0,
      headingRowHeight: 32,
      headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black),
      dataTextStyle: const TextStyle(fontSize: 13, color: Colors.black87),
      columns: const [
        DataColumn(label: Text('รายการ')),
        DataColumn(label: Text('จำนวน'), numeric: true),
        DataColumn(label: Text('ยอดเงิน'), numeric: true),
      ],
      rows: pendingOrders.map((order) => DataRow(
        cells: [
          DataCell(Text(order.productDescription)),
          DataCell(Text('${order.quantity.toStringAsFixed(0)} ${order.unit}')),
          DataCell(Text(currencyFormat.format(order.totalAmount))),
        ]
      )).toList(),
    );
  }

  Widget _buildSummary(NumberFormat currencyFormat, double beforeVat, double vat, double total) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SizedBox(
          width: 280,
          child: Column(
            children: [
              _summaryRow('ยอดรวมก่อนภาษี:', currencyFormat.format(beforeVat)),
              _summaryRow('ภาษีมูลค่าเพิ่ม 7%:', currencyFormat.format(vat)),
              const Divider(),
              _summaryRow('ยอดรวมทั้งสิ้น:', currencyFormat.format(total), isTotal: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(String title, String amount, {bool isTotal = false}) {
    final style = TextStyle(
      fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
      fontSize: isTotal ? 16 : 14,
      color: isTotal ? Colors.indigo.shade800 : Colors.black,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: style),
          Text(amount, style: style),
        ],
      ),
    );
  }

  // --- PDF WIDGETS (for printing) ---

  pw.Widget _buildPdfHeader(pw.Font font, pw.Font fontRegular, DateFormat dateFormat) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('บริษัท วังเภสัชฟาร์มาซูติคอล จำกัด', style: pw.TextStyle(font: font, fontSize: 16)),
              pw.Text('23 ซ.พัฒโน ถ.อนุสรณ์อาจาร์ยทอง อ.หาดใหญ่ จ.สงขลา 90110', style: pw.TextStyle(font: fontRegular, fontSize: 9)),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('ใบสั่งจอง (ค้างส่ง)', style: pw.TextStyle(font: font, fontSize: 18)),
            pw.Text('SALES ORDER (PENDING)', style: pw.TextStyle(font: fontRegular, fontSize: 10, color: PdfColors.grey700)),
            pw.SizedBox(height: 8),
            pw.Text('วันที่พิมพ์: ${dateFormat.format(DateTime.now())}', style: pw.TextStyle(font: fontRegular, fontSize: 9)),
          ],
        )
      ],
    );
  }

  pw.Widget _buildPdfCustomerInfo(pw.Font font, pw.Font fontRegular) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('ข้อมูลลูกค้า', style: pw.TextStyle(font: font, fontSize: 14)),
        pw.SizedBox(height: 8),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(width: 70, child: pw.Text('รหัสลูกค้า:', style: pw.TextStyle(font: font))),
            pw.Text(member.memCode ?? '-', style: pw.TextStyle(font: fontRegular)),
          ],
        ),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(width: 70, child: pw.Text('ชื่อลูกค้า:', style: pw.TextStyle(font: font))),
            pw.Expanded(child: pw.Text(member.memName ?? '-', style: pw.TextStyle(font: fontRegular))),
          ],
        ),
         pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(width: 70, child: pw.Text('ที่อยู่:', style: pw.TextStyle(font: font))),
            pw.Expanded(child: pw.Text(member.addressLine1 ?? '-', style: pw.TextStyle(font: fontRegular))),
          ],
        ),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(width: 70, child: pw.Text('เบอร์โทร:', style: pw.TextStyle(font: font))),
            pw.Text(member.memTel ?? '-', style: pw.TextStyle(font: fontRegular)),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildPdfItemsTable(NumberFormat currencyFormat, pw.Font font, pw.Font fontRegular) {
    return pw.Table.fromTextArray(
      headers: ['รหัสสินค้า', 'รายการ', 'จำนวน', 'หน่วย', 'ยอดเงิน'],
      data: pendingOrders.map((order) => [
        order.productId,
        order.productDescription,
        order.quantity.toStringAsFixed(0),
        order.unit,
        currencyFormat.format(order.totalAmount),
      ]).toList(),
      headerStyle: pw.TextStyle(font: font, fontSize: 10),
      cellStyle: pw.TextStyle(font: fontRegular, fontSize: 10),
      border: pw.TableBorder.all(color: PdfColors.grey400),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellAlignments: {
        2: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
      },
      columnWidths: {
        0: const pw.FlexColumnWidth(1.5),
        1: const pw.FlexColumnWidth(4),
        2: const pw.FlexColumnWidth(0.8),
        3: const pw.FlexColumnWidth(0.8),
        4: const pw.FlexColumnWidth(1.2),
      },
    );
  }

  pw.Widget _buildPdfSummary(NumberFormat currencyFormat, double beforeVat, double vat, double total, pw.Font font, pw.Font fontRegular) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.SizedBox(
          width: 250,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              _pdfSummaryRow('ยอดรวมก่อนภาษี:', currencyFormat.format(beforeVat), fontRegular),
              _pdfSummaryRow('ภาษีมูลค่าเพิ่ม 7%:', currencyFormat.format(vat), fontRegular),
              pw.Divider(color: PdfColors.grey, height: 10),
              _pdfSummaryRow('ยอดรวมทั้งสิ้น:', currencyFormat.format(total), font, isTotal: true),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _pdfSummaryRow(String title, String amount, pw.Font font, {bool isTotal = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.0),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(title, style: pw.TextStyle(font: font, fontSize: isTotal ? 11 : 10)),
          pw.Text(amount, style: pw.TextStyle(font: font, fontSize: isTotal ? 11 : 10)),
        ],
      ),
    );
  }
}
