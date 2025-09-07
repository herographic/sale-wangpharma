// lib/screens/printable_invoice_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:salewang/models/app_order.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PrintableInvoiceScreen extends StatelessWidget {
  final AppOrder order;

  const PrintableInvoiceScreen({super.key, required this.order});

  // --- NEW: Function to generate PDF and print ---
  Future<void> _printInvoice(BuildContext context) async {
    final doc = pw.Document();
    // ใช้ Google Fonts สำหรับภาษาไทยใน PDF
    final font = await PdfGoogleFonts.promptBold();
    final fontRegular = await PdfGoogleFonts.promptRegular();
    final currencyFormat = NumberFormat("#,##0.00", "en_US");
    final dateFormat = DateFormat('d MMMM yyyy', 'th_TH');

    final totalAmount = order.totalAmount;
    final vatAmount = totalAmount * 7 / 107;
    final amountBeforeVat = totalAmount - vatAmount;

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              _buildPdfHeader(font, fontRegular),
              pw.Divider(thickness: 2, height: 20),
              // Customer and Order Info
              _buildPdfCustomerAndOrderInfo(dateFormat, font, fontRegular),
              pw.SizedBox(height: 24),
              // Items Table
              _buildPdfItemsTable(currencyFormat, font, fontRegular),
              pw.Spacer(), // ดันส่วนสรุปไปด้านล่าง
              // Summary
              _buildPdfSummary(currencyFormat, amountBeforeVat, vatAmount,
                  totalAmount, font, fontRegular),
              pw.Divider(thickness: 1, height: 20),
              // Note and Footer
              _buildPdfFooter(font, fontRegular),
            ],
          );
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
    final totalAmount = order.totalAmount;
    final vatAmount = totalAmount * 7 / 107;
    final amountBeforeVat = totalAmount - vatAmount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ดูตัวอย่างก่อนพิมพ์'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            onPressed: () => _printInvoice(context),
            tooltip: 'ปริ้นท์เอกสาร',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const Divider(thickness: 2, height: 40),
                _buildCustomerAndOrderInfo(dateFormat),
                const SizedBox(height: 24),
                _buildItemsTable(currencyFormat),
                const Divider(height: 32),
                _buildSummary(
                    currencyFormat, amountBeforeVat, vatAmount, totalAmount),
                const Divider(thickness: 1, height: 32),
                _buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Flutter Widgets for Display (Screen Preview) ---

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'บริษัท วังเภสัชฟาร์มาซูติคอล จำกัด',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo.shade800),
              ),
              const Text(
                  '23 ซ.พัฒโน ถ.อนุสรณ์อาจาร์ยทอง\nอ.หาดใหญ่ จ.สงขลา 90110'),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
             Text(
              'ใบสั่งจอง',
              style: TextStyle(fontSize: 22, color: Colors.grey.shade800, fontWeight: FontWeight.bold),
            ),
            Text(
              'SALES ORDER',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
          ],
        )
      ],
    );
  }

  Widget _buildCustomerAndOrderInfo(DateFormat dateFormat) {
    return Column(
      children: [
        _buildInfoRow('รหัสลูกค้า:', order.customerId, 'ชื่อลูกค้า:', order.customerName),
        _buildInfoRow('เลขที่:', order.soNumber, 'พนักงานขาย:', order.salespersonName),
        _buildInfoRow('วันที่:', dateFormat.format(order.orderDate.toDate()), '', ''),
      ],
    );
  }
  
  Widget _buildInfoRow(String label1, String value1, String label2, String value2) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: Text(label1, style: const TextStyle(fontWeight: FontWeight.bold))),
          Expanded(flex: 5, child: Text(value1)),
          const SizedBox(width: 16),
          Expanded(flex: 3, child: Text(label2, style: const TextStyle(fontWeight: FontWeight.bold))),
          Expanded(flex: 5, child: Text(value2)),
        ],
      ),
    );
  }


  Widget _buildItemsTable(NumberFormat currencyFormat) {
    return DataTable(
      columnSpacing: 16.0,
      horizontalMargin: 0,
      headingRowHeight: 32,
      headingTextStyle: const TextStyle(
          fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black),
      dataTextStyle: const TextStyle(fontSize: 13, color: Colors.black87),
      columns: const [
        DataColumn(label: Text('ลำดับ')),
        DataColumn(label: Text('รายการ')),
        DataColumn(label: Text('จำนวน'), numeric: true),
        DataColumn(label: Text('ราคา'), numeric: true),
        DataColumn(label: Text('รวม'), numeric: true),
      ],
      rows: order.items.asMap().entries.map((entry) {
        int index = entry.key;
        AppOrderItem item = entry.value;
        final itemTotal = item.quantity * item.unitPrice;
        return DataRow(
          cells: [
            DataCell(Text((index + 1).toString())),
            DataCell(Text('${item.productDescription} (${item.unit})')),
            DataCell(Text(item.quantity.toStringAsFixed(0))),
            DataCell(Text(currencyFormat.format(item.unitPrice))),
            DataCell(Text(currencyFormat.format(itemTotal))),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildSummary(
      NumberFormat currencyFormat, double beforeVat, double vat, double total) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SizedBox(
          width: 280,
          child: Column(
            children: [
              _summaryRow('ยอดรวม:', currencyFormat.format(beforeVat)),
              _summaryRow('ภาษีมูลค่าเพิ่ม 7%:', currencyFormat.format(vat)),
              const Divider(),
              _summaryRow('ยอดรวมทั้งสิ้น:', currencyFormat.format(total),
                  isTotal: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(String title, String amount, {bool isTotal = false}) {
    final style = TextStyle(
      fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
      fontSize: isTotal ? 18 : 14,
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

  Widget _buildFooter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (order.note.isNotEmpty) ...[
          const Text('หมายเหตุ:', style: TextStyle(fontWeight: FontWeight.bold)),
          Text(order.note),
          const SizedBox(height: 24),
        ],
        const Center(
          child: Text(
            'ขอบคุณที่ใช้บริการ',
            style: TextStyle(
                fontSize: 16, fontStyle: FontStyle.italic, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  // --- PDF Generation Widgets ---

  pw.Widget _buildPdfHeader(pw.Font font, pw.Font fontRegular) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('บริษัท วังเภสัชฟาร์มาซูติคอล จำกัด',
                  style: pw.TextStyle(font: font, fontSize: 20)),
              pw.Text('23 ซ.พัฒโน ถ.อนุสรณ์อาจาร์ยทอง อ.หาดใหญ่ จ.สงขลา 90110',
                  style: pw.TextStyle(font: fontRegular, fontSize: 10)),
            ],
          ),
        ),
        pw.SizedBox(width: 20),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('ใบสั่งจอง', style: pw.TextStyle(font: font, fontSize: 22)),
            pw.Text('SALES ORDER', style: pw.TextStyle(font: fontRegular, fontSize: 12, color: PdfColors.grey700)),
          ],
        )
      ],
    );
  }

  pw.Widget _buildPdfCustomerAndOrderInfo(
      DateFormat dateFormat, pw.Font font, pw.Font fontRegular) {
    return pw.Column(children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
              flex: 1,
              child: pw.Text('รหัสลูกค้า:', style: pw.TextStyle(font: font))),
          pw.Expanded(
              flex: 3,
              child: pw.Text(order.customerId,
                  style: pw.TextStyle(font: fontRegular))),
          pw.SizedBox(width: 20),
          pw.Expanded(
              flex: 1,
              child: pw.Text('ชื่อลูกค้า:', style: pw.TextStyle(font: font))),
          pw.Expanded(
              flex: 3,
              child: pw.Text(order.customerName,
                  style: pw.TextStyle(font: fontRegular))),
        ],
      ),
      pw.SizedBox(height: 5),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
              flex: 1, child: pw.Text('เลขที่:', style: pw.TextStyle(font: font))),
          pw.Expanded(
              flex: 3,
              child: pw.Text(order.soNumber,
                  style: pw.TextStyle(font: fontRegular))),
          pw.SizedBox(width: 20),
          pw.Expanded(
              flex: 1,
              child: pw.Text('พนักงานขาย:', style: pw.TextStyle(font: font))),
          pw.Expanded(
              flex: 3,
              child: pw.Text(order.salespersonName,
                  style: pw.TextStyle(font: fontRegular))),
        ],
      ),
       pw.SizedBox(height: 5),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
              flex: 1, child: pw.Text('วันที่:', style: pw.TextStyle(font: font))),
          pw.Expanded(
              flex: 3,
              child: pw.Text(dateFormat.format(order.orderDate.toDate()),
                  style: pw.TextStyle(font: fontRegular))),
          pw.SizedBox(width: 20),
          pw.Expanded(flex: 1, child: pw.Text('')),
          pw.Expanded(flex: 3, child: pw.Text('')),
        ],
      ),
    ]);
  }

  pw.Widget _buildPdfItemsTable(
      NumberFormat currencyFormat, pw.Font font, pw.Font fontRegular) {
    final headers = ['ลำดับ', 'รายการ', 'จำนวน', 'หน่วย', 'ราคา/หน่วย', 'รวม'];
    final data = order.items.asMap().entries.map((entry) {
      final item = entry.value;
      final total = item.quantity * item.unitPrice;
      return [
        (entry.key + 1).toString(),
        item.productDescription,
        item.quantity.toStringAsFixed(0),
        item.unit,
        currencyFormat.format(item.unitPrice),
        currencyFormat.format(total),
      ];
    }).toList();

    return pw.Table.fromTextArray(
      headers: headers,
      data: data,
      headerStyle: pw.TextStyle(font: font, fontSize: 10),
      cellStyle: pw.TextStyle(font: fontRegular, fontSize: 10),
      border: pw.TableBorder.all(color: PdfColors.grey400),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellAlignments: {
        0: pw.Alignment.center,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.center,
        4: pw.Alignment.centerRight,
        5: pw.Alignment.centerRight,
      },
      columnWidths: {
        0: const pw.FlexColumnWidth(0.5),
        1: const pw.FlexColumnWidth(3),
        2: const pw.FlexColumnWidth(0.8),
        3: const pw.FlexColumnWidth(0.8),
        4: const pw.FlexColumnWidth(1.2),
        5: const pw.FlexColumnWidth(1.2),
      },
    );
  }

  pw.Widget _buildPdfSummary(NumberFormat currencyFormat, double beforeVat,
      double vat, double total, pw.Font font, pw.Font fontRegular) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.SizedBox(
          width: 250,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              _pdfSummaryRow('ยอดรวม:', currencyFormat.format(beforeVat), fontRegular),
              _pdfSummaryRow('ภาษีมูลค่าเพิ่ม 7%:', currencyFormat.format(vat), fontRegular),
              pw.Divider(color: PdfColors.grey, height: 10),
              _pdfSummaryRow('ยอดรวมทั้งสิ้น:', currencyFormat.format(total), font,
                  isTotal: true),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _pdfSummaryRow(String title, String amount, pw.Font font,
      {bool isTotal = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.0),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(title, style: pw.TextStyle(font: font, fontSize: isTotal ? 12 : 10)),
          pw.Text(amount, style: pw.TextStyle(font: font, fontSize: isTotal ? 12 : 10)),
        ],
      ),
    );
  }

  pw.Widget _buildPdfFooter(pw.Font font, pw.Font fontRegular) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (order.note.isNotEmpty) ...[
          pw.Text('หมายเหตุ:', style: pw.TextStyle(font: font)),
          pw.Text(order.note, style: pw.TextStyle(font: fontRegular)),
          pw.SizedBox(height: 24),
        ],
        pw.Center(
          child: pw.Text(
            'ขอบคุณที่ใช้บริการ',
            style: pw.TextStyle(
                font: fontRegular,
                fontStyle: pw.FontStyle.italic,
                color: PdfColors.grey),
          ),
        ),
      ],
    );
  }
}
