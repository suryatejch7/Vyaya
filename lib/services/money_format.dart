import 'package:intl/intl.dart';

// Vyaya is for India only: amounts are always rupees, grouped the Indian
// way (thousands, lakhs, crores), e.g. ₹1,23,45,678.

final Map<int, NumberFormat> _formats = {};

/// Indian digit grouping: 123456789.5 -> "12,34,56,789.50".
String formatAmount(double v, [int decimals = 2]) {
  final f = _formats.putIfAbsent(
      decimals,
      () => NumberFormat(
          decimals > 0 ? '#,##,##0.${'0' * decimals}' : '#,##,##0', 'en_IN'));
  return f.format(v);
}

/// Short form for chart labels, in Indian units: 950, 12K, 2.5L, 1.2Cr.
String compactAmount(double v) {
  final a = v.abs();
  final sign = v < 0 ? '-' : '';
  String short(double x) {
    final s = x < 10 ? x.toStringAsFixed(1) : x.toStringAsFixed(0);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  // Switched a little early, so rounding never shows "100K" or "1000".
  if (a >= 9950000) return '$sign${short(a / 10000000)}Cr';
  if (a >= 99500) return '$sign${short(a / 100000)}L';
  if (a >= 999.5) return '$sign${short(a / 1000)}K';
  return '$sign${a.toStringAsFixed(0)}';
}
