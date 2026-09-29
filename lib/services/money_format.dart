import 'package:intl/intl.dart';

/// Indian digit grouping: 123456789.5 -> "12,34,56,789.50".
String formatAmount(double v, [int decimals = 2]) {
  final pattern = decimals > 0 ? '#,##,##0.${'0' * decimals}' : '#,##,##0';
  return NumberFormat(pattern, 'en_IN').format(v);
}
