/// Suggests a category for a payment.
///
/// Order: 1) the category you picked for that payee before (learned rules),
/// 2) the payee's name against a list of well-known Indian brands, their
/// company names ("BUNDL TECHNOLOGIES" = Swiggy) and shop words ("… MEDICALS"),
/// 3) words in the message (electricity, EMI, fees…), 4) "Other".
///
/// A match gives a [CategoryGroup] (Food, Fitness…), which is then mapped to
/// one of YOUR categories by name ("Gym Stuff" counts for Fitness). When you
/// have none, [CategoryGuess.category] is null and the app can offer to
/// create one. The keyword lists are documented in
/// tool/category_keywords.txt.
library;

/// A kind of spending a payee can belong to.
class CategoryGroup {
  final String key;

  /// Shown in "Looks like …" and used as the name when creating it.
  final String name;
  final String icon;
  final int color;

  /// Words that make one of your categories count for this group. Up to 4
  /// letters must be a whole word of the name ("fun" isn't "Funds"); longer
  /// ones can start a word ("grocer" -> "Groceries").
  final List<String> matches;

  /// Id of the built-in category for this group, so a renamed "Food" still
  /// counts.
  final String? defaultId;

  /// Group to use when you have no category for this one.
  final String? fallback;

  /// Offer to create [name] when nothing fits.
  final bool offerCreate;

  const CategoryGroup({
    required this.key,
    required this.name,
    required this.icon,
    required this.color,
    required this.matches,
    this.defaultId,
    this.fallback,
    this.offerCreate = true,
  });
}

/// What [MerchantCategorizer.guess] found.
class CategoryGuess {
  /// One of your categories, or null when nothing fits.
  final String? category;

  /// What the payee looks like (Food, Fitness…), if anything.
  final CategoryGroup? group;

  /// True when [category] is your own earlier choice for this payee.
  final bool fromRule;

  const CategoryGuess(this.category, this.group, {this.fromRule = false});
}

class _Keyword {
  final String group;
  final String spaced; // "burger king"
  final String squashed; // "burgerking"
  const _Keyword(this.group, this.spaced, this.squashed);
}

class MerchantCategorizer {
  MerchantCategorizer._();

  static const List<CategoryGroup> groups = [
    CategoryGroup(
        key: 'food', name: 'Food', icon: '🍔', color: 0xFFFF9800,
        matches: ['food', 'foods', 'dining', 'eating', 'restaurant', 'meal', 'meals'],
        defaultId: 'food'),
    CategoryGroup(
        key: 'groceries', name: 'Groceries', icon: '🛒', color: 0xFF8BC34A,
        matches: ['grocer', 'kirana', 'provision'],
        fallback: 'food', offerCreate: false),
    CategoryGroup(
        key: 'transport', name: 'Transport', icon: '🚗', color: 0xFF2196F3,
        matches: ['transport', 'travel', 'commute', 'fuel', 'petrol', 'cab', 'cabs', 'trip', 'trips'],
        defaultId: 'transport'),
    CategoryGroup(
        key: 'shopping', name: 'Shopping', icon: '🛍️', color: 0xFFE91E63,
        matches: ['shopping', 'clothes', 'clothing', 'electronic', 'fashion'],
        defaultId: 'shopping'),
    CategoryGroup(
        key: 'entertainment', name: 'Entertainment', icon: '🎬', color: 0xFF9C27B0,
        matches: ['entertainment', 'fun', 'movie', 'leisure', 'ott', 'party', 'parties'],
        defaultId: 'entertainment'),
    CategoryGroup(
        key: 'health', name: 'Health', icon: '💊', color: 0xFFF44336,
        matches: ['health', 'medical', 'medicine', 'pharma', 'doctor', 'hospital'],
        defaultId: 'health'),
    CategoryGroup(
        key: 'fitness', name: 'Gym', icon: '🏋️', color: 0xFF009688,
        matches: ['gym', 'gyms', 'fitness', 'workout', 'sport', 'exercise', 'protein', 'supplement']),
    CategoryGroup(
        key: 'bills', name: 'Bills', icon: '🧾', color: 0xFFFFC107,
        matches: ['bill', 'bills', 'utilit', 'rent', 'recharge'],
        defaultId: 'bills'),
    CategoryGroup(
        key: 'education', name: 'Education', icon: '📚', color: 0xFF3F51B5,
        matches: ['education', 'study', 'studies', 'college', 'school', 'book', 'books', 'course'],
        defaultId: 'education'),
    CategoryGroup(
        key: 'personalCare', name: 'Personal Care', icon: '💇', color: 0xFFFF4081,
        matches: ['personal care', 'self care', 'grooming', 'beauty', 'salon']),
    CategoryGroup(
        key: 'subscriptions', name: 'Subscriptions', icon: '📱', color: 0xFF607D8B,
        matches: ['subscription', 'apps', 'software'],
        fallback: 'bills', offerCreate: false),
    CategoryGroup(
        key: 'investments', name: 'Investments', icon: '📈', color: 0xFF4CAF50,
        matches: ['invest', 'sip', 'sips', 'stock', 'mutual', 'trading']),
    CategoryGroup(
        key: 'pets', name: 'Pets', icon: '🐾', color: 0xFF795548,
        matches: ['pet', 'pets', 'dog', 'dogs', 'cat', 'cats']),
    CategoryGroup(
        key: 'donations', name: 'Donations', icon: '🙏', color: 0xFFFF5722,
        matches: ['donation', 'charity', 'temple']),
  ];

  static CategoryGroup? groupByKey(String key) {
    for (final g in groups) {
      if (g.key == key) return g;
    }
    return null;
  }

  // Brands, company names and apps, matched against the payee (and against
  // the whole message only when there's no payee).
  static const Map<String, List<String>> _brandWords = {
    'food': [
      'swiggy', 'zomato', 'dunzo', 'domino', 'pizza', 'mcdonald', 'kfc',
      'burger', 'subway', 'starbucks', 'coffee', 'tea', 'food', 'haldiram',
      'barbeque', 'eatery', 'kitchen', 'ccd', 'swiggy dineout', 'zomato gold',
      'eatsure', 'eat sure', 'box8', 'faasos', 'behrouz biryani', 'ovenstory',
      'magicpin', 'eatfit', 'fresh menu', 'freshmenu', 'rebel foods', 'thrive',
      'dineout', 'eazydiner', 'zomato district', 'dominos', 'domino\'s',
      'pizza hut', 'la pinoz', 'lapinoz', 'oven story', 'mojo pizza',
      'burger king', 'burgerking', 'mcdonalds', 'mcd', 'wendy\'s', 'wendys',
      'jumboking', 'burger singh', 'taco bell', 'kfc india', 'popeyes',
      'wow momo', 'wowmomo', 'momo', 'faaso\'s', 'biryani by kilo',
      'biryani blues', 'paradise biryani', 'behrouz', 'meghana foods',
      'nandos', 'nando\'s', 'cafe coffee day', 'third wave coffee',
      'blue tokai', 'tim hortons', 'costa coffee', 'barista', 'chaayos',
      'chai point', 'chai sutta bar', 'tea post', 'mad over donuts',
      'krispy kreme', 'baskin robbins', 'naturals ice cream', 'cream stone',
      'havmor', 'amul parlour', 'keventers', 'theobroma', 'the belgian waffle',
      'belgian waffle', 'wafflesome', 'hocco', 'ibaco', 'dunkin',
      'bikanervala', 'haldirams', 'anand sweets', 'karachi bakery', 'brijwasi',
      'agarwal sweets', 'chitale', 'barbeque nation', 'absolute barbecues',
      'ab\'s', 'mainland china', 'social', 'hard rock cafe', 'punjab grill',
      'saravana bhavan', 'a2b', 'adyar ananda bhavan', 'sagar ratna', 'vaango',
      'mtr', 'rameshwaram cafe', 'the rameshwaram cafe', 'cafe niloufer',
      'niloufer', 'bawarchi', 'shah ghouse', 'pista house', 'bar', 'pub',
      'brewery', 'foodcourt', 'zomato order', 'swiggy order', 'dosa', 'idli',
      'thali', 'meals', 'lunch', 'dinner', 'breakfast', 'snacks', 'pani puri',
      'chaat', 'shawarma', 'rolls', 'sandwich', 'bakes', 'patisserie',
      'bundl technologies', 'swiggy limited', 'swiggy ltd', 'eternal limited',
      'eternal ltd', 'zomato limited', 'zomato ltd', 'zomato media',
      'jubilant foodworks', 'restaurant brands asia', 'burger king india',
      'hardcastle restaurants', 'westlife foodworld',
      'connaught plaza restaurants', 'devyani international', 'sapphire foods',
      'tata starbucks', 'coffee day global', 'coffee day enterprises',
      'barbeque nation hospitality', 'hungerbox', 'mealful', 'wow momo foods',
      'sunshine teahouse', 'mountain trail foods', 'eazydine', 'pluxee',
      'sodexo', 'zeta meal',
    ],
    'groceries': [
      'instamart', 'blinkit', 'zepto', 'bigbasket', 'grocery', 'groceries',
      'vegetable', 'big bazaar', 'bigbazaar', 'more retail', 'spencer',
      'star bazaar', 'jiomart', 'nature basket', 'ratnadeep',
      'swiggy instamart', 'amazon fresh', 'flipkart minutes',
      'flipkart supermart', 'bb now', 'bbnow', 'bb daily', 'bbdaily',
      'milkbasket', 'country delight', 'dmart ready', 'jiomart express',
      'zepto cafe', 'dunzo daily', 'kpn fresh', 'fresh to home', 'freshtohome',
      'licious', 'tendercuts', 'meatigo', 'zappfresh', 'pluckk', 'otipy',
      'sabzi', 'fruit', 'hypermarket', 'spar', 'spar hypermarket',
      'more supermarket', 'reliance fresh', 'reliance smart', 'smart bazaar',
      'reliance smart bazaar', 'heritage fresh', 'lulu hypermarket',
      'nilgiris', 'foodworld', 'easyday', '24seven', 'natures basket', 'amul',
      'aavin', 'mother dairy', 'akshayakalpa', 'grocer', 'departmental store',
      'kirana store', 'blink commerce', 'grofers india',
      'kiranakart technologies', 'zepto private limited', 'zepto pvt',
      'innovative retail concepts', 'supermarket grocery supplies',
      'avenue supermarts', 'avenue e-commerce', 'delightful gourmet',
      'freshtohome foods', 'dmart', 'vijetha supermarkets', 'nandini milk',
      'nandini parlour', 'heritage foods',
    ],
    'transport': [
      'uber', 'ola', 'rapido', 'irctc', 'metro', 'railway', 'redbus',
      'abhibus', 'petrol', 'hpcl', 'iocl', 'bpcl', 'indian oil', 'fastag',
      'cab', 'namma yatri', 'yulu', 'indigo', 'air india', 'akasa', 'spicejet',
      'makemytrip', 'goibibo', 'cleartrip', 'ixigo', 'bus', 'toll',
      'uber india', 'ola cabs', 'olacabs', 'rapido bike', 'bluesmart',
      'blu smart', 'meru', 'megacabs', 'savaari', 'quick ride', 'quickride',
      'bounce', 'vogo', 'zoomcar', 'revv', 'drivezy', 'auto rickshaw',
      'autorickshaw', 'taxi', 'hp petrol', 'hindustan petroleum',
      'bharat petroleum', 'iocl fuel', 'indianoil', 'nayara', 'essar',
      'reliance petrol', 'jio-bp', 'jio bp', 'shell petrol', 'shell fuel',
      'petrol bunk', 'fuel station', 'cng', 'ev charging',
      'tata power ez charge', 'statiq', 'chargezone', 'ather grid', 'netc',
      'nhai', 'fastag recharge', 'paytm fastag', 'irctc eticket', 'uts',
      'indian railways', 'confirmtkt', 'trainman', 'railyatri', 'bmrcl',
      'namma metro', 'dmrc', 'delhi metro', 'mumbai metro', 'hyderabad metro',
      'l&t metro', 'chennai metro', 'kochi metro', 'bmtc', 'best bus', 'ksrtc',
      'tsrtc', 'apsrtc', 'msrtc', 'gsrtc', 'upsrtc', 'zingbus', 'intrcity',
      'flixbus', 'chalo', 'vistara', 'air india express', 'akasa air',
      'spice jet', 'go first', 'alliance air', 'easemytrip', 'yatra',
      'happyfares', 'airasia', 'emirates', 'qatar airways', 'lufthansa', 'oyo',
      'oyo rooms', 'treebo', 'fabhotels', 'fab hotels', 'zostel', 'airbnb',
      'booking.com', 'agoda', 'trivago', 'taj hotels', 'marriott', 'ibis',
      'lemon tree', 'ginger hotels', 'thomas cook', 'sotc', 'veena world',
      'airport', 'lounge', 'ani technologies', 'roppen transportation',
      'uber india systems', 'indian railway catering', 'interglobe aviation',
      'makemytrip india', 'ibibo group', 'yatra online', 'le travenues',
      'indian oil corporation',
    ],
    'shopping': [
      'amazon', 'flipkart', 'myntra', 'ajio', 'meesho', 'nykaa', 'tata cliq',
      'croma', 'reliance', 'decathlon', 'lifestyle', 'westside', 'zara',
      'ikea', 'lenskart', 'trends', 'pantaloons', 'max fashion', 'vijay sales',
      'amazon.in', 'amazon pay', 'amzn', 'flipkart internet', 'snapdeal',
      'shopsy', 'jiomart digital', 'tata neu', 'tatacliq', 'firstcry',
      'hopscotch', 'pepperfry', 'urban ladder', 'wakefit', 'sleepyhead',
      'duroflex', 'home centre', 'homecentre', 'hometown', 'nykaa fashion',
      'the souled store', 'souled store', 'bewakoof', 'snitch', 'h&m',
      'uniqlo', 'marks & spencer', 'marks and spencer', 'm&s', 'levis',
      'levi\'s', 'puma', 'adidas', 'nike', 'reebok', 'skechers', 'bata',
      'metro shoes', 'mochi', 'woodland', 'red tape', 'campus shoes',
      'allen solly', 'van heusen', 'peter england', 'louis philippe',
      'raymond', 'fabindia', 'biba', 'w for woman', 'global desi', 'manyavar',
      'mufti', 'jack & jones', 'vero moda', 'forever 21', 'shoppers stop',
      'v-mart', 'vmart', 'style union', 'zudio', 'trends footwear',
      'caratlane', 'tanishq', 'kalyan jewellers', 'malabar gold', 'bluestone',
      'giva', 'reliance digital', 'apple store', 'apple india',
      'imagine store', 'samsung', 'oneplus', 'xiaomi', 'mi store', 'realme',
      'vivo', 'oppo', 'boat', 'noise', 'fire-boltt', 'sony center', 'poorvika',
      'sangeetha mobiles', 'bajaj electronics', 'girias', 'unicorn store',
      'amazon basics', 'dell', 'hp store', 'lenovo', 'asus', 'ikea india',
      'daiso', 'miniso', 'archies', 'ferns n petals', 'fnp', 'igp', 'bigsmall',
      'hamleys', 'stationery shop', 'asian paints', 'amazon seller services',
      'amazon pay india', 'amazon retail', 'instakart', 'myntra designs',
      'fashnear technologies', 'fsn e-commerce', 'nykaa e-retail',
      'trent limited', 'lenskart solutions', 'infiniti retail',
    ],
    'entertainment': [
      'netflix', 'spotify', 'hotstar', 'jiocinema', 'prime video', 'youtube',
      'sonyliv', 'zee5', 'bookmyshow', 'pvr', 'inox', 'cinepolis', 'steam',
      'playstation', 'xbox', 'apple music', 'gaana', 'wynk', 'district',
      'disney+ hotstar', 'disney hotstar', 'jiohotstar', 'youtube premium',
      'amazon prime', 'prime membership', 'apple tv', 'mubi', 'aha', 'sun nxt',
      'sunnxt', 'hoichoi', 'alt balaji', 'altbalaji', 'voot', 'erosnow',
      'eros now', 'mx player', 'lionsgate play', 'discovery+', 'crunchyroll',
      'audible', 'kuku fm', 'pocket fm', 'storytel', 'jiosaavn', 'saavn',
      'apple one', 'bms', 'paytm insider', 'insider.in', 'district by zomato',
      'ticketnew', 'pvr inox', 'carnival cinemas', 'miraj cinemas',
      'movietime', 'cinema', 'movie', 'multiplex', 'concert', 'gaming',
      'epic games', 'google play games', 'riot games', 'valorant', 'pubg',
      'bgmi', 'garena', 'free fire', 'dream11', 'my11circle', 'mpl', 'winzo',
      'rummy', 'smaaash', 'timezone', 'wonderla', 'imagica', 'snow world',
      'bowling', 'go karting', 'big tree entertainment', 'pvr limited',
      'netflix entertainment services india', 'spotify india',
      'novi digital entertainment', 'jiostar', 'sporta technologies',
    ],
    'health': [
      'apollo', 'pharmeasy', '1mg', 'netmeds', 'medplus', 'diagnostic',
      'practo', 'doctor', 'apollo pharmacy', 'apollo 247', 'apollo hospitals',
      'tata 1mg', 'truemeds', 'frank ross', 'wellness forever',
      'guardian pharmacy', 'noble plus', 'davaindia', 'jan aushadhi',
      'medicines', 'drug house', 'fortis', 'manipal hospitals',
      'max healthcare', 'narayana health', 'care hospitals',
      'rainbow hospitals', 'cloudnine', 'motherhood', 'aiims',
      'dr lal pathlabs', 'lal pathlabs', 'thyrocare', 'metropolis',
      'srl diagnostics', 'redcliffe', 'healthians', 'orange health',
      'tata health', 'mfine', 'tata aig health', 'star health', 'niva bupa',
      'care health', 'vision express', 'titan eye plus', 'eye hospital',
      'physiotherapy', 'lab test', 'scan centre', 'x-ray', 'mri',
      'api holdings', 'axelia solutions', 'tata 1mg healthcare',
      'netmeds marketplace', 'vitalic health', 'apollo healthco',
      'apollo 24/7', 'aster hospital', 'aster clinic', 'kims hospital',
      'yashoda hospital',
    ],
    'fitness': [
      'cult', 'healthkart', 'cult.fit', 'cultfit', 'curefit', 'gold\'s gym',
      'golds gym', 'anytime fitness', 'snap fitness', 'talwalkars',
      'fitness first', 'crunch fitness', 'f45', 'multifit', 'fitternity',
      'fittr', 'healthifyme', 'healthify', 'hrx', 'strava', 'nike training',
      'zumba', 'crossfit', 'fitness centre', 'fitness center', 'swimming pool',
      'badminton court', 'playo', 'hudle', 'box cricket', 'nutrabay',
      'muscleblaze', 'muscle blaze', 'optimum nutrition', 'myprotein',
      'my protein', 'gnc', 'as-it-is', 'asitis', 'avvatar', 'big muscles',
      'bigmuscles', 'nakpro', 'the whole truth', 'wellcore', 'fast&up',
      'fast and up', 'oziva', 'true basics', 'amway', 'herbalife', 'protein',
      'whey', 'creatine', 'supplement', 'supplements', 'decathlon sports',
      'sportsuncle', 'sg cricket', 'nivia', 'cosco', 'yonex',
      'curefit healthcare', 'bright lifecare', 'nutrabay retail',
    ],
    'bills': [
      'airtel', 'jio', 'vodafone', 'bsnl', 'act fibernet', 'bescom', 'bses',
      'tata power', 'adani', 'msedcl', 'kseb', 'water', 'gas', 'indane',
      'bharat gas', 'dth', 'tata play', 'rent', 'insurance', 'lic', 'emi',
      'bill', 'postpaid', 'vi', 'vodafone idea', 'airtel xstream',
      'airtel broadband', 'jiofiber', 'jio fiber', 'airfiber', 'hathway',
      'excitel', 'you broadband', 'spectra', 'tikona', 'railwire',
      'alliance broadband', 'asianet', 'bsnl ftth', 'mtnl', 'dish tv', 'd2h',
      'sun direct', 'tataplay', 'videocon d2h', 'airtel dth', 'prepaid',
      'mobile recharge', 'tneb', 'tangedco', 'tsspdcl', 'tsnpdcl', 'apspdcl',
      'apepdcl', 'cesc', 'wbsedcl', 'mahavitaran', 'mseb', 'best electricity',
      'torrent power', 'reliance energy', 'adani electricity',
      'tata power ddl', 'bses rajdhani', 'bses yamuna', 'uppcl', 'pspcl',
      'jvvnl', 'avvnl', 'jdvvnl', 'hescom', 'gescom', 'mescom', 'cescom',
      'kptcl', 'tnpdcl', 'bwssb', 'hmwssb', 'djb', 'delhi jal board', 'mgl',
      'mahanagar gas', 'igl', 'indraprastha gas', 'adani gas', 'gujarat gas',
      'hp gas', 'bharatgas', 'indane gas', 'piped gas', 'lpg', 'cylinder',
      'nobroker', 'nestaway', 'housing.com', 'magicbricks',
      'society maintenance', 'mygate', 'nobrokerhood', 'apartment', 'pg rent',
      'hostel fees', 'house rent', 'rent payment', 'cred rent', 'policybazaar',
      'acko', 'digit insurance', 'go digit', 'icici lombard', 'hdfc ergo',
      'bajaj allianz', 'tata aig', 'sbi life', 'hdfc life', 'max life',
      'lic premium', 'loan emi', 'home loan', 'car loan', 'bike loan',
      'personal loan', 'bajaj finserv', 'bajaj finance', 'home credit',
      'tata capital', 'muthoot', 'manappuram', 'property tax', 'income tax',
      'gst payment', 'challan', 'traffic fine', 'parivahan', 'passport seva',
      'bbmp', 'ghmc', 'municipal', 'water tax', 'bescom bill', 'bharti airtel',
      'bharti hexacom', 'reliance jio infocomm', 'tata play limited',
    ],
    'education': [
      'udemy', 'coursera', 'byju', 'unacademy', 'vedantu', 'upgrad', 'fees',
      'exam', 'books', 'course', 'byju\'s', 'byjus', 'physics wallah',
      'allen career', 'fiitjee', 'resonance', 'toppr', 'doubtnut', 'testbook',
      'adda247', 'gradeup', 'simplilearn', 'great learning', 'scaler',
      'newton school', 'masai school', 'coding ninjas', 'geeksforgeeks',
      'leetcode', 'codechef', 'interviewbit', 'educative', 'pluralsight',
      'linkedin learning', 'skillshare', 'edx', 'khan academy', 'duolingo',
      'cuemath', 'whitehat jr', 'brainly', 'chegg', 'kindle', 'amazon kindle',
      'sapna book house', 'crossword', 'oxford bookstore', 'higginbotham',
      'pustak', 'exam fee', 'application fee', 'semester fee', 'hostel fee',
      'nptel', 'ielts', 'toefl', 'gre', 'gmat', 'aakash institute',
      'aakash educational',
    ],
    'personalCare': [
      'urban company', 'urbanclap', 'parlor', 'lakme salon', 'naturals salon',
      'green trends', 'jawed habib', 'toni&guy', 'toni and guy',
      'enrich salon', 'looks salon', 'bodycraft', 'yes madam', 'purplle',
      'mamaearth', 'sugar cosmetics', 'plum', 'minimalist', 'the derma co',
      'wow skin science', 'beardo', 'bombay shaving company',
      'the man company', 'ustraa', 'forest essentials', 'kama ayurveda',
      'body shop', 'bath & body works', 'sephora', 'myglamm', 'tira',
      'urbanclap technologies',
    ],
    'subscriptions': [
      'google one', 'google play', 'google storage', 'google workspace',
      'youtube membership', 'apple.com/bill', 'apple icloud', 'icloud',
      'itunes', 'app store', 'microsoft', 'microsoft 365', 'office 365',
      'xbox game pass', 'adobe', 'canva', 'chatgpt', 'openai', 'claude',
      'anthropic', 'notion', 'dropbox', 'zoom', 'linkedin premium', 'tinder',
      'bumble', 'hinge', 'truecaller', 'expressvpn', 'nordvpn', 'github',
      'jetbrains', 'figma', 'google india digital', 'apple services',
      'apple media services', 'telegram premium', 'telegram', 'google cloud',
    ],
    'investments': [
      'zerodha', 'zerodha coin', 'zerodha kite', 'groww', 'upstox',
      'angel one', 'angelone', 'angel broking', '5paisa', 'paytm money',
      'indmoney', 'ind money', 'kuvera', 'et money', 'etmoney', 'smallcase',
      'dhan app', 'fyers', 'motilal oswal', 'icici direct', 'icicidirect',
      'hdfc securities', 'kotak securities', 'sharekhan', 'sbi mf',
      'sbi mutual fund', 'hdfc mutual fund', 'icici prudential mf',
      'axis mutual fund', 'nippon india mf', 'mirae asset', 'parag parikh',
      'ppfas', 'quant mf', 'uti mf', 'bse star mf', 'mf utilities', 'cams',
      'kfintech', 'nps', 'national pension', 'ppf', 'sukanya samriddhi',
      'recurring deposit', 'fixed deposit', 'sip', 'mutual fund',
      'digital gold', 'safegold', 'mmtc-pamp', 'augmont', 'jar app', 'gullak',
      'stable money', 'wint wealth', 'grip invest', 'goldenpi',
      'zerodha broking', 'nextbillion technology', 'groww invest',
      'rksv securities', 'angel one limited',
    ],
    'pets': [
      'supertails', 'heads up for tails', 'hutf', 'zigly', 'wiggles', 'drools',
      'pedigree', 'royal canin', 'whiskas', 'petsy', 'pet shop', 'pet store',
      'pet clinic', 'vet', 'veterinary', 'pet hospital', 'dog food',
      'cat food',
    ],
    'donations': [
      'giveindia', 'give india', 'ketto', 'milaap', 'impact guru',
      'donatekart', 'cry india', 'akshaya patra', 'helpage', 'goonj',
      'smile foundation', 'unicef', 'temple', 'mandir', 'gurudwara', 'church',
      'mosque', 'masjid', 'donation', 'charity', 'hundi',
    ],
  };

  // Words in local shop names ("SRI LAKSHMI MEDICALS"); payee only.
  static const Map<String, List<String>> _shopWords = {
    'food': [
      'cafe', 'chai', 'restaurant', 'dhaba', 'bakery', 'sweets', 'biryani',
      'canteen', 'mess', 'juice', 'tiffin', 'udupi', 'hotel', 'food court',
      'bhavan', 'bhojanalaya', 'darshini', 'tiffins', 'caterers', 'bakers',
      'sweet house', 'juice centre', 'tea stall', 'fast food', 'foods',
      'ice cream', 'pan shop',
    ],
    'groceries': [
      'kirana', 'fruits', 'milk', 'dairy', 'provision', 'vegetables', 'eggs',
      'meat', 'chicken', 'mutton', 'fish', 'supermarket', 'general store',
      'super market', 'provisions', 'general stores', 'departmental',
    ],
    'transport': [
      'fuel', 'parking', 'petrol pump', 'filling station', 'service station',
      'petroleum', 'fuels', 'automobiles', 'toll plaza', 'car wash', 'tyres',
      'garage', 'motors service',
    ],
    'shopping': [
      'hardware', 'paints', 'textiles', 'garments', 'fashions', 'footwear',
      'shoes', 'jewellers', 'jewellery', 'watches', 'gifts', 'toys',
      'electronics', 'mobiles', 'mobile shop', 'computers', 'electricals',
      'furniture', 'optical', 'xerox', 'photocopy', 'book depot',
    ],
    'health': [
      'pharmacy', 'chemist', 'medical', 'hospital', 'clinic', 'dental',
      'medicals', 'eye care', 'physio', 'medical store', 'pharma', 'druggist',
      'nursing home', 'diagnostics', 'path lab', 'labs', 'opticals',
    ],
    'fitness': [
      'yoga', 'gym', 'sports club', 'turf', 'fitness', 'sports academy',
    ],
    'bills': [
      'broadband', 'electricity', 'recharge', 'maintenance', 'water board',
      'gas agency', 'cable tv', 'cable network', 'society',
    ],
    'education': [
      'college', 'university', 'school', 'tuition', 'stationery', 'academy',
      'institute', 'library', 'coaching', 'classes',
    ],
    'personalCare': [
      'salon', 'parlour', 'barber', 'spa', 'saloon', 'beauty parlour',
      'unisex',
    ],
  };

  // Checked in the message when the payee matched nothing.
  static const Map<String, List<String>> _messageWords = {
    'bills': [
      'electricity', 'electricity bill', 'power bill', 'water bill',
      'gas bill', 'broadband', 'recharge', 'postpaid', 'prepaid', 'dth', 'emi',
      'loan emi', 'insurance', 'premium', 'rent', 'maintenance', 'society',
    ],
    'education': [
      'fees', 'fee', 'tuition', 'school', 'college',
    ],
    'transport': [
      'fastag', 'toll', 'fuel', 'petrol', 'diesel',
    ],
    'health': [
      'pharmacy', 'medicine', 'medicines', 'hospital',
    ],
  };

  // Company names banks print instead of the brand (the parser may have cut
  // "Technologies" / "Limited" off). Matched at the start of the payee with
  // spaces ignored; used to see two reports as the same shop and to
  // categorise the company like its brand.
  static const Map<String, String> _companyBrands = {
    'bundl': 'swiggy', 'swiggylimited': 'swiggy', 'instamart': 'swiggy',
    'eternal': 'zomato', 'zomatomedia': 'zomato', 'zomatolimited': 'zomato',
    'blinkcommerce': 'blinkit', 'grofers': 'blinkit',
    'kiranakart': 'zepto', 'zeptoprivate': 'zepto', 'zeptopvt': 'zepto',
    'innovativeretail': 'bigbasket', 'supermarketgrocery': 'bigbasket',
    'avenuesupermarts': 'dmart', 'avenueecommerce': 'dmart',
    'anitechnologies': 'ola', 'olacabs': 'ola', 'roppen': 'rapido',
    'uberindia': 'uber', 'indianrailwaycatering': 'irctc',
    'interglobe': 'indigo', 'ibibo': 'goibibo', 'letravenues': 'ixigo',
    'oravel': 'oyo', 'amazonseller': 'amazon', 'amazonpay': 'amazon',
    'amazonretail': 'amazon', 'amzn': 'amazon',
    'flipkartinternet': 'flipkart', 'instakart': 'flipkart',
    'myntradesigns': 'myntra', 'fashnear': 'meesho',
    'fsnecommerce': 'nykaa', 'nykaaeretail': 'nykaa', 'trentlimited': 'westside',
    'apiholdings': 'pharmeasy', 'axelia': 'pharmeasy', 'tata1mg': '1mg',
    'curefit': 'cult', 'brightlifecare': 'healthkart',
    'bigtreeentertainment': 'bookmyshow', 'novidigital': 'hotstar',
    'jiostar': 'hotstar', 'sportatech': 'dream11',
    'bhartiairtel': 'airtel', 'bhartihexacom': 'airtel',
    'reliancejio': 'jio', 'vodafoneidea': 'vi', 'urbanclap': 'urban company',
    'zerodhabroking': 'zerodha', 'nextbillion': 'groww', 'rksv': 'upstox',
    'jubilantfood': 'dominos', 'restaurantbrands': 'burger king',
    'hardcastle': 'mcdonalds', 'westlifefood': 'mcdonalds',
    'connaughtplaza': 'mcdonalds', 'tatastarbucks': 'starbucks',
    'coffeeday': 'ccd', 'googleindia': 'google play',
    'appleservices': 'app store', 'applemedia': 'app store',
  };

  static String? _companyBrand(String squashed) {
    for (final e in _companyBrands.entries) {
      if (squashed.startsWith(e.key)) return e.value;
    }
    return null;
  }

  /// Same value for two names of one shop: "BUNDL TECHNOLOGIES", "Bundl"
  /// and "Swiggy" all give "swiggy". Other names give their letters only.
  static String brandKey(String name) {
    final squashed = _normalizePayee(name).replaceAll(' ', '');
    return _companyBrand(squashed) ?? squashed;
  }

  static List<_Keyword> _compile(List<Map<String, List<String>>> maps,
      {int minLength = 0}) {
    final out = <_Keyword>[];
    for (final map in maps) {
      map.forEach((group, words) {
        for (final w in words) {
          final spaced = w
              .toLowerCase()
              .replaceAll("'", '')
              .replaceAll(_nonAlnum, ' ')
              .trim();
          final squashed = spaced.replaceAll(' ', '');
          if (squashed.length < minLength || squashed.isEmpty) continue;
          out.add(_Keyword(group, spaced, squashed));
        }
      });
    }
    return out;
  }

  static final _nonAlnum = RegExp(r'[^a-z0-9]+');
  static final List<_Keyword> _payeeKeywords =
      _compile([_brandWords, _shopWords]);
  static final List<_Keyword> _messageBrandKeywords =
      _compile([_brandWords], minLength: 5);
  static final List<_Keyword> _messageKeywords = _compile([_messageWords]);

  // "PAYU*SWIGGY", "RAZ*ZEPTO", "BILLDESK*TATAPOWER", "UPI-ZOMATO".
  static final _gatewayPrefix = RegExp(
      r'^(?:payu|razorpay|razpay|raz|rzp|billdesk|bdsk|ccavenue|cca|paytm|phonepe|ppe|cashfree|cf|juspay|easebuzz|instamojo|pinelabs|pine labs|pg|ecom|pos|upi|imps|neft)\b[\s*:\-_/.]*');

  // Payments banks send SMS for every payment; their name isn't the payee.
  static final _paymentsBank = RegExp(
      r'\b(?:airtel|jio|paytm|fino|india post|nsdl)\s+payments?\s+bank\b');

  /// Normalised identity used for learned rules ("SWIGGY" == "Swiggy").
  static String key(String merchant) =>
      merchant.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Payee as words: lowercase, UPI handle's "@bank" and gateway prefixes
  /// removed, punctuation turned into spaces.
  static String _normalizePayee(String s) {
    var v = s.toLowerCase().trim();
    final at = v.indexOf('@');
    if (at > 0) v = v.substring(0, at);
    for (var i = 0; i < 3; i++) {
      final n = v.replaceFirst(_gatewayPrefix, '');
      if (n == v) break;
      v = n;
    }
    return v.replaceAll("'", '').replaceAll(_nonAlnum, ' ').trim();
  }

  static String _normalizeMessage(String s) => s
      .toLowerCase()
      .replaceAll(_paymentsBank, ' ')
      .replaceAll("'", '')
      .replaceAll(_nonAlnum, ' ')
      .trim();

  /// Group of the longest keyword found in [normalized]. Up to 4 letters
  /// must be a whole word ("ola" isn't "cola"). Longer single words must be
  /// a whole word, plus "s"/"es" ("medicals"), or begin a word followed by
  /// 3+ more letters ("zomatoonline" from a UPI handle); so first names
  /// like "Bhavana" don't match "bhavan". From 8 letters they can appear
  /// anywhere. Several-word names match with spaces ignored ("BURGERKING").
  static String? _bestGroup(String normalized, List<_Keyword> keywords) {
    if (normalized.isEmpty) return null;
    final padded = ' $normalized ';
    final words = normalized.split(' ');
    final squashed = normalized.replaceAll(' ', '');
    _Keyword? best;
    for (final k in keywords) {
      final ks = k.squashed;
      if (best != null && ks.length <= best.squashed.length) continue;
      final bool found;
      if (ks.length <= 4) {
        found = padded.contains(' ${k.spaced} ');
      } else if (k.spaced.contains(' ')) {
        found = squashed.contains(ks);
      } else {
        found = words.any((w) =>
                w == ks ||
                w == '${ks}s' ||
                w == '${ks}es' ||
                (w.startsWith(ks) && w.length - ks.length >= 3)) ||
            (ks.length >= 8 && squashed.contains(ks));
      }
      if (found) best = k;
    }
    return best?.group;
  }

  /// What a payment looks like, from the payee or else the message.
  static CategoryGroup? groupFor({String? merchant, String? rawText}) {
    final hasPayee = merchant != null && merchant.trim().isNotEmpty;
    if (hasPayee) {
      final payee = _normalizePayee(merchant);
      // The name itself first ("Instamart" is Groceries); the company ->
      // brand mapping only when the name alone says nothing ("Bundl").
      final g = _bestGroup(payee, _payeeKeywords) ??
          (() {
            final company = _companyBrand(payee.replaceAll(' ', ''));
            return company == null
                ? null
                : _bestGroup(company, _payeeKeywords);
          })();
      if (g != null) return groupByKey(g);
    }
    if (rawText != null && rawText.trim().isNotEmpty) {
      final text = _normalizeMessage(rawText);
      if (!hasPayee) {
        final g = _bestGroup(text, _messageBrandKeywords);
        if (g != null) return groupByKey(g);
      }
      final g = _bestGroup(text, _messageKeywords);
      if (g != null) return groupByKey(g);
    }
    return null;
  }

  static bool _nameMatches(String categoryName, String match) {
    final n = categoryName.toLowerCase();
    if (match.contains(' ')) return n.contains(match);
    final words = n.split(_nonAlnum);
    return match.length <= 4
        ? words.contains(match)
        : words.any((w) => w.startsWith(match));
  }

  /// Your category for [group], following its fallback (Groceries -> Food);
  /// null when you have none. "Saved" never counts.
  static String? categoryFor(CategoryGroup group, List<String> categoryNames,
      [Map<String, String> aliases = const {}]) {
    final names = categoryNames.where((c) => c != 'Saved').toList();
    for (final m in group.matches) {
      for (final c in names) {
        if (_nameMatches(c, m)) return c;
      }
    }
    final id = group.defaultId;
    if (id != null) {
      final renamed = aliases[id];
      if (renamed != null && names.contains(renamed)) return renamed;
    }
    final fb = group.fallback == null ? null : groupByKey(group.fallback!);
    return fb == null ? null : categoryFor(fb, categoryNames, aliases);
  }

  /// Your earlier choice for the payee, else the group's category.
  static CategoryGuess guess({
    required String? merchant,
    required String rawText,
    required List<String> categoryNames,
    required Map<String, String> learned,
    Map<String, String> aliases = const {},
  }) {
    String? existing(String name) {
      for (final c in categoryNames) {
        if (c.toLowerCase() == name.toLowerCase()) return c;
      }
      return null;
    }

    if (merchant != null) {
      final learnedCat = learned[key(merchant)];
      // "Saved" is only for month-end savings, never a payee's category.
      if (learnedCat != null &&
          learnedCat != 'Saved' &&
          existing(learnedCat) != null) {
        return CategoryGuess(existing(learnedCat), null, fromRule: true);
      }
    }
    final group = groupFor(merchant: merchant, rawText: rawText);
    if (group == null) return const CategoryGuess(null, null);
    return CategoryGuess(categoryFor(group, categoryNames, aliases), group);
  }

  /// "Other" (or your first category) when nothing fits.
  static String fallbackCategory(List<String> categoryNames) {
    for (final c in categoryNames) {
      if (c.toLowerCase() == 'other') return c;
    }
    return categoryNames.isNotEmpty ? categoryNames.first : 'Other';
  }

  static String suggest({
    required String? merchant,
    required String rawText,
    required List<String> categoryNames,
    required Map<String, String> learned,
    // Category id -> current name. Default categories keep ids like "food",
    // so a renamed "Food" (now "Meals") still gets the food keywords.
    Map<String, String> aliases = const {},
  }) =>
      guess(
            merchant: merchant,
            rawText: rawText,
            categoryNames: categoryNames,
            learned: learned,
            aliases: aliases,
          ).category ??
          fallbackCategory(categoryNames);
}
