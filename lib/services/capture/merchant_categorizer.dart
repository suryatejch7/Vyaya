/// Suggests a category for a payee: the user's own past choices first, then
/// a keyword list for common Indian merchants. Only returns categories the
/// user actually has.
class MerchantCategorizer {
  MerchantCategorizer._();

  /// Keys match the app's default category names.
  static const Map<String, List<String>> _keywords = {
    'Food': [
      'swiggy', 'zomato', 'instamart', 'blinkit', 'zepto', 'bigbasket',
      'dunzo', 'domino', 'pizza', 'mcdonald', 'kfc', 'burger', 'subway',
      'starbucks', 'cafe', 'coffee', 'chai', 'tea', 'restaurant', 'dhaba',
      'bakery', 'sweets', 'food', 'biryani', 'canteen', 'mess', 'juice',
      'haldiram', 'barbeque', 'eatery', 'kitchen', 'tiffin', 'ccd',
      // groceries
      'grocery', 'groceries', 'kirana', 'vegetable', 'fruits', 'milk',
      'dairy', 'big bazaar', 'bigbazaar', 'more retail', 'spencer',
      'star bazaar', 'jiomart', 'nature basket', 'ratnadeep', 'provision',
    ],
    'Transport': [
      'uber', 'ola', 'rapido', 'irctc', 'metro', 'railway', 'redbus',
      'abhibus', 'petrol', 'fuel', 'hpcl', 'iocl', 'bpcl', 'indian oil',
      'shell', 'fastag', 'parking', 'cab', 'namma yatri', 'yulu', 'indigo',
      'air india', 'akasa', 'spicejet', 'makemytrip', 'goibibo', 'cleartrip',
      'ixigo', 'bus', 'toll',
    ],
    'Shopping': [
      'amazon', 'flipkart', 'myntra', 'ajio', 'meesho', 'nykaa', 'tata cliq',
      'croma', 'reliance', 'dmart', 'decathlon', 'lifestyle', 'westside',
      'zara', 'ikea', 'lenskart', 'store', 'mart', 'mall', 'shop',
      'supermarket', 'trends', 'pantaloons', 'max fashion', 'vijay sales',
    ],
    'Entertainment': [
      'netflix', 'spotify', 'hotstar', 'jiocinema', 'prime video', 'youtube',
      'sonyliv', 'zee5', 'bookmyshow', 'pvr', 'inox', 'cinepolis', 'steam',
      'playstation', 'xbox', 'apple music', 'gaana', 'wynk', 'district',
    ],
    'Health': [
      'apollo', 'pharmeasy', '1mg', 'netmeds', 'medplus', 'pharmacy',
      'chemist', 'medical', 'hospital', 'clinic', 'diagnostic', 'cult',
      'healthkart', 'practo', 'doctor', 'dental',
    ],
    'Bills': [
      'airtel', 'jio', 'vodafone', 'bsnl', 'act fibernet', 'broadband',
      'electricity', 'bescom', 'bses', 'tata power', 'adani', 'msedcl',
      'kseb', 'water', 'gas', 'indane', 'bharat gas', 'recharge', 'dth',
      'tata play', 'rent', 'insurance', 'lic', 'emi', 'bill', 'postpaid',
      'maintenance',
    ],
    'Education': [
      'udemy', 'coursera', 'byju', 'unacademy', 'vedantu', 'upgrad',
      'college', 'university', 'school', 'fees', 'tuition', 'exam', 'books',
      'stationery', 'course', 'academy', 'institute',
    ],
  };

  /// Normalised identity used for learned rules ("SWIGGY" == "Swiggy").
  static String key(String merchant) =>
      merchant.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static bool _matches(String haystack, String keyword) {
    if (keyword.length <= 4) {
      // Short words must stand alone ("tea" shouldn't match "team").
      return RegExp('(^|[^a-z0-9])${RegExp.escape(keyword)}([^a-z0-9]|\$)')
          .hasMatch(haystack);
    }
    return haystack.contains(keyword);
  }

  static String suggest({
    required String? merchant,
    required String rawText,
    required List<String> categoryNames,
    required Map<String, String> learned,
    // Category id -> current name. Default categories keep ids like "food",
    // so a renamed "Food" (now "Meals") still gets the food keywords.
    Map<String, String> aliases = const {},
  }) {
    String? existing(String name) {
      for (final c in categoryNames) {
        if (c.toLowerCase() == name.toLowerCase()) return c;
      }
      final renamed = aliases[name.toLowerCase()];
      if (renamed != null) {
        for (final c in categoryNames) {
          if (c == renamed) return c;
        }
      }
      return null;
    }

    final fallback = existing('Other') ??
        (categoryNames.isNotEmpty ? categoryNames.first : 'Other');

    if (merchant != null) {
      final learnedCat = learned[key(merchant)];
      if (learnedCat != null && existing(learnedCat) != null) {
        return existing(learnedCat)!;
      }
    }

    String? fromText(String text) {
      final t = text.toLowerCase();
      for (final entry in _keywords.entries) {
        final cat = existing(entry.key);
        if (cat == null) continue;
        if (entry.value.any((k) => _matches(t, k))) return cat;
      }
      return null;
    }

    if (merchant != null) {
      final c = fromText(merchant);
      if (c != null) return c;
    }
    // No payee match: look at the whole message ("…towards HOME LOAN EMI").
    return fromText(rawText) ?? fallback;
  }
}
