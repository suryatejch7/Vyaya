// Indian money formatting: thousands, lakhs, crores.
// Run: flutter test test/money_format_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:expensetracker/services/money_format.dart';

void main() {
  test('Indian grouping', () {
    expect(formatAmount(999, 0), '999');
    expect(formatAmount(1234, 0), '1,234');
    expect(formatAmount(123456, 0), '1,23,456');
    expect(formatAmount(12345678, 0), '1,23,45,678');
    expect(formatAmount(123456789.5), '12,34,56,789.50');
    expect(formatAmount(1234.567, 2), '1,234.57');
  });

  test('short chart labels in Indian units', () {
    expect(compactAmount(950), '950');
    expect(compactAmount(1500), '1.5K');
    expect(compactAmount(12000), '12K');
    expect(compactAmount(250000), '2.5L');
    expect(compactAmount(1200000), '12L');
    expect(compactAmount(15000000), '1.5Cr');
    expect(compactAmount(0), '0');
    // Rounding up moves to the next unit instead of "1000" or "100K".
    expect(compactAmount(999.6), '1K');
    expect(compactAmount(99960), '1L');
    expect(compactAmount(9960000), '1Cr');
    expect(compactAmount(-2500), '-2.5K');
  });
}
