// Run: flutter test test/merchant_categorizer_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:expensetracker/services/capture/merchant_categorizer.dart';

const _defaults = [
  'Food', 'Transport', 'Shopping', 'Entertainment', 'Health', 'Bills',
  'Education', 'Other',
];

String? _group(String? payee, [String? message]) =>
    MerchantCategorizer.groupFor(merchant: payee, rawText: message)?.key;

String _suggest(String? payee,
        {String message = '',
        List<String> categories = _defaults,
        Map<String, String> learned = const {}}) =>
    MerchantCategorizer.suggest(
      merchant: payee,
      rawText: message,
      categoryNames: categories,
      learned: learned,
    );

void main() {
  group('payee names', () {
    final cases = <String, String?>{
      'BURGERKING': 'food',
      'Burger King': 'food',
      'swiggy.stores@axb': 'food',
      'PAYU*SWIGGY': 'food',
      'BUNDL TECHNOLOGIES PVT LTD': 'food',
      'Eternal Limited': 'food',
      'SWIGGY INSTAMART': 'groceries', // longer name wins over "swiggy"
      'RAZ*ZEPTO': 'groceries',
      "D'Mart Store": 'groceries',
      'amazon fresh': 'groceries',
      'Amazon': 'shopping',
      'Nykaa': 'shopping',
      'JIOMART': 'groceries',
      'Jio': 'bills',
      'Olacabs': 'transport',
      'RAJU FILLING STATION': 'transport',
      'NUTRABAY': 'fitness',
      'MuscleBlaze': 'fitness',
      'POWERHOUSE GYM': 'fitness',
      'SRI LAKSHMI MEDICALS': 'health',
      'Ramesh Medical Store': 'health',
      'AMMA TIFFIN CENTRE': 'food',
      'Urban Company': 'personalCare',
      'Zerodha': 'investments',
      'Supertails': 'pets',
      'Google Play': 'subscriptions',
      // Not guessed: people, vague shop names, look-alikes, bare handles.
      'Rahul Kumar': null,
      'SRI RAM ENTERPRISES': null,
      'Coca Cola': null, // not "ola"
      'uberoi': null, // not "uber"
      'Q12345678@ybl': null,
      'paytmqr281005050101@paytm': null,
      // First names that start like a keyword aren't shops.
      'Bhavana Reddy': null, // not "bhavan"
      'Aakash Verma': null,
      'Nandini': null,
      // Company names, also after the parser cut "Technologies"/"Limited".
      'Bundl': 'food',
      'Eternal': 'food',
      'Ani Technologies': 'transport',
      'Kiranakart': 'groceries',
      'Zomatoonline': 'food', // UPI handle
    };
    cases.forEach((payee, want) {
      test('$payee -> $want', () => expect(_group(payee), want));
    });
  });

  group('same shop, different names', () {
    test('company and brand give the same key', () {
      expect(MerchantCategorizer.brandKey('BUNDL TECHNOLOGIES'), 'swiggy');
      expect(MerchantCategorizer.brandKey('Bundl'), 'swiggy');
      expect(MerchantCategorizer.brandKey('Swiggy'), 'swiggy');
      expect(MerchantCategorizer.brandKey('Eternal Limited'), 'zomato');
    });
    test('two different food shops are not the same shop', () {
      expect(MerchantCategorizer.brandKey('Chaayos'),
          isNot(MerchantCategorizer.brandKey('Swiggy')));
    });
  });

  group('message words', () {
    test('bill in the message when there is no payee', () {
      expect(_group(null, 'Rs 1200 debited towards electricity bill'),
          'bills');
    });
    test('brand in the message when there is no payee', () {
      expect(_group(null, 'Rs 250 paid to Swiggy via UPI'), 'food');
    });
    test('a payments bank name is not the payee', () {
      expect(_group('Rahul', 'Rs 500 sent from Airtel Payments Bank to Rahul'),
          isNull);
    });
  });

  group('your categories', () {
    test('Swiggy goes to Food', () => expect(_suggest('Swiggy'), 'Food'));

    test('groceries use Food when there is no Groceries category', () {
      expect(_suggest('Blinkit'), 'Food');
      expect(_suggest('Blinkit', categories: [..._defaults, 'Groceries']),
          'Groceries');
    });

    test('Nutrabay stays in Other without a gym-type category', () {
      expect(_suggest('Nutrabay'), 'Other');
      final g = MerchantCategorizer.guess(
        merchant: 'Nutrabay',
        rawText: '',
        categoryNames: _defaults,
        learned: const {},
      );
      expect(g.category, isNull);
      expect(g.group?.name, 'Gym');
      expect(g.group?.offerCreate, isTrue);
    });

    test('any category with a gym-type name counts', () {
      expect(_suggest('Nutrabay', categories: [..._defaults, 'Gym Stuff']),
          'Gym Stuff');
      expect(_suggest('cult.fit', categories: [..._defaults, 'Fitness']),
          'Fitness');
    });

    test('short words must be whole words ("Funds" is not "fun")', () {
      expect(
          _suggest('Netflix',
              categories: ['Funds', 'Fun', 'Other']),
          'Fun');
    });

    test('a learned "Saved" is ignored', () {
      expect(_suggest('Rahul', learned: {'rahul': 'Saved'},
              categories: [..._defaults, 'Saved']),
          'Other');
    });

    test('your own choice beats the list', () {
      expect(_suggest('Zomato', learned: {'zomato': 'Entertainment'}),
          'Entertainment');
    });

    test('Saved never counts', () {
      expect(
          MerchantCategorizer.categoryFor(
              MerchantCategorizer.groupByKey('investments')!,
              ['Saved', 'Other']),
          isNull);
    });
  });
}
