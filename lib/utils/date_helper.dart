// lib/utils/date_helper.dart

import 'package:intl/intl.dart';

class DateHelper {
  // This new function handles both ISO String format (e.g., "2025-07-26T00:00:00.000Z")
  // and Excel's numeric format.
  static String formatDateToThai(String dateString) {
    if (dateString.isEmpty) return '-';
    DateTime? dateTime;

    try {
      // First, try parsing as an ISO 8601 string, which is common from databases.
      dateTime = DateTime.parse(dateString);
    } catch (e) {
      // If it fails, try parsing as a double (Excel date).
      try {
        final excelDate = double.parse(dateString);
        // Excel's epoch starts on 1900-01-01. We convert it to Dart's epoch (1970-01-01).
        dateTime = DateTime.fromMillisecondsSinceEpoch(
            ((excelDate - 25569) * 86400000).round());
      } catch (e) {
        // If both parsing methods fail, return the original string.
        return dateString;
      }
    }

    // Format to "dd MMM yyyy" in Thai locale (e.g., 26 ก.ค. 2568)
    // The year is converted to Buddhist Era (BE) by adding 543.
    final thaiYear = dateTime.year + 543;
    final formatter = DateFormat('dd MMM', 'th_TH');
    return '${formatter.format(dateTime)} $thaiYear';
  }

  // The old function is kept for compatibility if needed elsewhere, but the new one is recommended.
  static String formatExcelDate(String excelDateString) {
    try {
      final excelDate = double.parse(excelDateString);
      final dateTime = DateTime.fromMillisecondsSinceEpoch(
          ((excelDate - 25569) * 86400000).round());
      return DateFormat('dd/MM/yyyy').format(dateTime);
    } catch (e) {
      return excelDateString;
    }
  }
}
