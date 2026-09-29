/// Turns a payment notification / bank SMS into a structured transaction.
///
/// Pipeline: reject noise (OTP, promos, scams, failed, reminders, requests)
/// -> amount -> direction -> merchant -> account digits -> reference -> date.
/// Pure Dart with no Flutter imports, so it's unit-testable
/// (see test/transaction_parser_test.dart). Patterns were built against real
/// Indian bank / UPI message formats (HDFC, SBI, ICICI, Axis, Kotak, BoB,
/// PNB, Canara, IDFC, Union, Federal, Citi, SBI Card) and payment-app
/// notifications (PhonePe, Google Pay, Paytm).
library;

class ParsedTransaction {
  final double amount;
  final bool isDebit;
  final String? merchant;
  final String? last4;
  final List<String> allLast4;
  final String? reference;
  final DateTime occurredAt;
  final double confidence;

  /// 'link', 'reversal', 'transfer', 'atm', 'card-bill'
  final Set<String> flags;

  const ParsedTransaction({
    required this.amount,
    required this.isDebit,
    required this.merchant,
    required this.last4,
    required this.allLast4,
    required this.reference,
    required this.occurredAt,
    required this.confidence,
    required this.flags,
  });
}

class ParseResult {
  final ParsedTransaction? transaction;
  final String? rejectReason;
  const ParseResult._(this.transaction, this.rejectReason);
  factory ParseResult.ok(ParsedTransaction t) => ParseResult._(t, null);
  factory ParseResult.reject(String reason) => ParseResult._(null, reason);
  bool get isOk => transaction != null;
}

class TransactionParser {
  TransactionParser._();

  static const _cur = r"(?:rs[.:]?|inr[.:]?|₹)";
  static const _num = r"([0-9][0-9,]*(?:\.[0-9]{1,2})?)";
  static const _amt = r"[0-9][0-9,]*(?:\.[0-9]{1,2})?";
  static const _name = r"([A-Za-z0-9][A-Za-z0-9&.'\-_ ]{1,45})";

  static RegExp _ci(String p) => RegExp(p, caseSensitive: false);

  // ---------------- rejection filters ----------------
  static final _otp = _ci(
      r"\b(?:otp|one[\s-]?time\s*password|verification\s*code|security\s*code)\b\W{0,15}(?:is\W{0,5})?\d{4,8}\b|\b\d{4,8}\b\W{0,15}is\s+(?:your|the)\s+(?:otp|one[\s-]?time|verification|security)\b");
  static final _promo = _ci(
      r"\b(use\s*(?:the\s*)?(?:promo\s*|coupon\s*)?code|promo\s*code|coupon\s*code|pay\s*(?:now|instantly|today)\s*[:\-]|valid\s*for\s*(?:a\s*)?limited|get\s+(?:assured\s+)?(?:up\s*to|upto|flat|extra)\s*(?:₹|rs\.?|inr)|(?:up\s*to|upto)\s*(?:₹|rs\.?|inr)\s*[\d,]+\s*(?:cashback|off|discount|reward)|pre[\s-]?approved|pre[\s-]?qualified|apply\s*now|avail\s*now|claim\s*now|click\s*(here|link|to)|congratulations|good\s*news|hurry|limited\s*(period\s*)?offer|offer\s*valid|lucky\s*draw|coupon|voucher|flat\s*\d+\s*%|\d+\s*%\s*(?:off|cashback|discount)|cashback\s*(upto|up\s*to|of\s*up\s*to|worth|waiting)|reward\s*points\s*worth|eligible\s*for|instant\s*(personal\s*)?loan|loan\s*(of|upto|up\s*to)|limit\s*(has\s*been\s*)?enhanced|enhanced\s*to|upgrade|get\s*(₹|rs\.?|inr)\s*\d+|(?:make|do)\s+your\s+(?:1st|first)\b|and\s+get\b|other\s+benefits|on\s+select\b|on\s*your\s*(first|next)\b|free\b(?!\s+(?:txn|transactions?|atm|withdrawals?))|bonus\b|cash\s*points|t\s*&\s*cs?\b(?!a)|tnc|download\s+(?:now|the\s+app|our\s+app|app|today)\b|join\s+(?:now|today)|sign\s*up|switch\s+to|awaits?\b|avail\s+(?:the|this|it|your|our|an?)\b|(?:ready\s+to|can)\s+be\s+credited|prizes?\b|entry\s+fees?|to\s+activate|enjoy\s+unlimited|only\s+today|today\s+only|flat\s*(?:rs|₹|inr)\.?\s*\d|code\s*:|(?:&|and)\s+get\b|(?:biggest|mega|festive|special|exclusive|best|great|amazing)\s+(?:[a-z]+\s+){0,2}offers?|offers?\s+(?:lapses|ends|expires|valid|on)\b|lapses\b|purchase\s+price|latest\s+price|target\s+price|stop[\s-]?loss|recommended\s+stock)");
  static final _scam = _ci(
      r"\b(kyc|lottery|kbc|won\s*(rs|₹)|claim\s*your|registration\s*fee|processing\s*fee|tax\s*fee|activation\s*fee|clearance\s*fee|security\s*deposit|to\s*release\s*funds|to\s*receive\s*(the\s*)?money|approve\s*the\s*transfer|verify\s*your\s*bank|confirm\s*bank\s*details|update\s*(your\s*)?bank|upi\s*pin|work\s*(from\s*home|part[\s-]?time)|apk|\.exe|whatsapp|police|defaulter|blackmail|recorded\s*your|hacked|freeze\s*your|scratch\s*card|wa\.me|recruit\w*|daily\s+salary|by\s+mistake|refund\s+the\s+amount|wrongly\s+credited|return\s+the\s+(?:amount|money)|(?:waiting\s+)?to\s+be\s+claimed|verify\s+your\s+account|before\s+it\s+expires|enter\s+your\s+(?:card|bank|upi|atm)|card\s+details|pending\s+refund|link\s+par|complaint\s+kar\w*|joining\s+(?:amount|fee)|deposit\s+kar\w*|bina\s+documents?|without\s+documents?|zero\s+documentation|loan\s+ghya|kamao|(?:reverse|cancel)\s+(?:this\s+|the\s+)?(?:transaction|txn|payment)|cancel\s+(?:now|immediately|karne|kara|karo|pannunga|korte|cheyandi))\b|\d[,.]?[o]{2,}\b|\b(?:t0|n0w|n0|y0ur|y0u|l0an|0n)\b|\.(?:online|top|xyz|site|click|live|shop|buzz|icu|cfd|sbs|rest|lol)\b|\b(?:expiring\s+today|redeem\s+(?:cash|now|your|it)|security\s+code\s+sent|tinyurl|block\s+aai\w*|cut\s+zale)\b|(?<!\bnot\s|n't\s|\bdont\s|\bnever\s)\bshare\s+(?:your\s+|the\s+)?(?:[a-z]+\s+){0,3}?(?:pin|otp|cvv)\b|\botp\s+(?:required|taka|anuppi\w*|bhej\w*|daal\w*|share\s+kar\w*)|\bor\s+your\s+(?:card|account|a\/c)\s+will\s+be\s+block|(?:https?:\/\/|www\.)\S*(?:refund|otp|kyc|verify|reward|claim)");
  static final _failed = _ci(
      r"\b(failed|declined|unsuccessful|could\s*not\s*be\s*(processed|completed)|is\s*pending|payment\s*pending|insufficient\s*(funds|balance))\b");
  static final _future = _ci(
      r"\b(will\s*be\s*(?:auto[\s-]?)?(?:debit(?:ed)?|deduct(?:ed)?|charg(?:ed)?)|scheduled\s*(for|on)|mandate\s*(created|registered|request)|autopay\s*(reminder|setup|set\s*up)|upcoming|reminder|statement\s*(is\s*ready|generated|for)|next\s+emi|ho\s+jaye?ga|ho\s+jaega|hoga|hoil|avvalsundi|aagum|not\s+paid|unpaid|non[\s-]?payment|disconnect\w*|will\s+be\s+cut|power\s+cut|suspend\w*)\b");
  // "Due" only means a bill reminder when no money came in (a refund
  // message can mention the card's revised total due).
  static final _due = _ci(
      r"\b(is\s*due|due\s*(on|date|by|hai|he|aahe|ahe|undi|ide)|minimum\s*(amount\s*)?due|total\s*due|kal\s+tak)\b|\bdue\s*(?:है|हे|आहे|ఉంది|உள்ளது)");
  static final _moneyIn = _ci(r"\b(refund(ed)?|reversed|credited|received)\b");
  // "Call 98XXXXXXXX to block/cancel": banks give toll-free 1800/1860
  // numbers, scammers give mobiles.
  static final _scamCall = _ci(
      r"\bcall\b[^.\d]{0,40}?(?:\+?91[\s-]?)?[6-9]\d{9}\b|(?:\+?91[\s-]?)?\b[6-9]\d{9}\b[^.\d]{0,25}?\bcall\b");
  static final _bankHelpline = _ci(
      r"\b1[89]\d0[\s-]?\d{3,4}[\s-]?\d{0,4}\b|\bf(?:or)?wd\b|\bforward\s+(?:this\s+)?sms\b");
  static final _request = _ci(
      r"\b(requested\s*(money|₹|rs|inr)|has\s*requested|collect\s*request|payment\s*request|request\s*(of|for)\s*(₹|rs|inr)|is\s*requesting)\b");
  static final _movement = _ci(
      r"\b(recharged?\b(?=[^.]{0,80}?\b(?:successful(?:ly)?|done|completed|success)\b)|successfully\s+recharged|debited|debit|credited|credit|spent|paid|withdrawn|withdrawal|purchase|deducted|sent|transferred|transfer|received|refund|refunded|deposited|deposit|transaction|txn|used\s*(for|at)|payment\s*of|reversed|reversal|cashback|salary|interest|thank\s*you\s*for\s*using|dr(?=\.?\s+from)|cr(?=\.?\s+to)|dr\.?(?=\s*(?:inr|rs|₹))|cr\.?(?=\s*(?:inr|rs|₹))|cr\.(?=\s)|dr\.(?=\s)|redeemed|payment\s+successful|cleared\s+with\s+your|initiated|processed\s+successfully)(?:(?<=\w)(?!\w)|(?<!\w))");

  // ---------------- amount ----------------
  static final _amountPrefixed = _ci(_cur + r"\s*" + _num);
  static final _amountSuffixed =
      _ci(r"\b" + _num + r"\s*(?:rs\.?|inr|₹)(?![a-z])");
  static final _amountBare = _ci(
      r"\b(?:debited|credited)\s+(?:by|for|with)\s+([0-9][0-9,]*(?:\.[0-9]{1,2})?)\b");
  static final _movedWord = _ci(r"\b(debited|credited|deducted)\b");
  static final _balanceBefore = _ci(
      r"(bal|balance|lmt|limit(?!ed)|available|avl|avbl|outstanding|o\/s|total\s*due)[^0-9]{0,18}$");

  // ---------------- direction ----------------
  static final _creditWords = _ci(
      r"\b(paid\s*you|sent\s*you|you\s*(have\s*)?received|received\s*(₹|rs|inr|from|money)|money\s*received|credited|refund(ed)?|reversed|reversal|deposited|cashback|salary|interest\s*(credited|of)|dividend|credit\s+of|(?:upi|neft|imps|rtgs)\s+credit|credit\s*:|received\s*!|received\s+in(?:to)?|cr\.?(?=\s*(?:inr|rs|₹))|cr\.(?=\s+to))(?:(?<=\w)(?!\w)|(?<!\w))");
  static final _debitWords = _ci(
      r"\b(recharged?\b(?=[^.]{0,80}?\b(?:successful(?:ly)?|done|completed|success)\b)|successfully\s+recharged|debited|debit|spent|paid|withdrawn|withdrawal|purchase|deducted|sent|transferred|used\s*(for|at)|payment\s*of|charged|emi|thank\s*you\s*for\s*using|(?:txn|transaction)\s+of|dr(?=\.?\s+from)|dr\.?(?=\s*(?:inr|rs|₹))|dr\.(?=\s)|txn\s+(?:rs|inr|₹)|(?:txn|transaction)\s+initiated|transaction\s+for\s+(?:rs|inr|₹)|redeemed|payment\s+successful|cleared\s+with\s+your)(?:(?<=\w)(?!\w)|(?<!\w))");
  static final _moneyBack = _ci(r"\b(reversed|refunded|credited\s*back)\b");
  // Money you sent that the payee "has received" / "credited to the
  // beneficiary" is a debit.
  static final _outgoingReceived = _ci(
      r"\bhas\s+received\b.{0,40}?\bfrom\s+your\s+(?:a\/c|ac|acct|account)\b|\bcredited\s+to\s+(?:the\s+)?beneficiary\b");

  // ---------------- account digits / reference ----------------
  static final _last4Masked = _ci(r"(?:x{2,}|\*{2,}|•{2,})\s*(\d{3,4})\b");
  static final _last4Labelled = _ci(
      r"\b(?:a\/c|ac|acct|account|card)\b[^0-9a-z]{0,6}(?:no\.?|number|ending(?:\s*(?:in|with))?)?[^0-9a-z]{0,4}[x*•]*(\d{4})\b");
  static final _referencePatterns = [
    _ci(r"\b(?:upi|imps|neft|rtgs)\s*[\/\-:]\s*(?:(?:dr|cr|p2a|p2m)\s*[\/\-:]\s*)?(\d{6,})"),
    _ci(r"\b(?:upi\s*)?ref(?:erence)?\.?\s*(?:no\.?|number|id)?\s*[:\-]?\s*([A-Za-z0-9]{6,})"),
    _ci(r"\brrn\s*[:\-]?\s*([A-Za-z0-9]{6,})"),
    _ci(r"\butr\s*(?:no\.?)?\s*[:\-]?\s*([A-Za-z0-9]{6,})"),
    _ci(r"\b(?:txn|transaction)\s*(?:id|no\.?|ref)\s*[:\-]?\s*([A-Za-z0-9]{6,})"),
    _ci(r"\bupi\s*[:\-]\s*(\d{6,})"),
  ];
  static final _twelveDigits = RegExp(r"\b(\d{12})\b");
  static final _hasFourDigits = RegExp(r"\d{4,}");

  // ---------------- merchant ----------------
  static final _merchantStrategies = [
    // payment-app phrasing (title — text)
    _ci(r"^" + _name + r"\s+[—\-:]\s+(?:has\s+)?(?:paid|sent)\s+you\b"),
    _ci(_name + r"\s+(?:has\s+)?(?:paid|sent)\s+you\b"),
    _ci(r"(?:paid|sent|payment\s+of|transferred)\s+" + _cur + r"\s*" + _amt +
        r"\s+(?:successfully\s+)?to\s+" + _name),
    _ci(_cur + r"\s*" + _amt +
        r"\s+(?:paid|sent|transferred)\s+(?:successfully\s+)?to\s+" + _name),
    _ci(r"received\s+" + _cur + r"\s*" + _amt + r"\s+from\s+" + _name),
    _ci(_cur + r"\s*" + _amt + r"\s+received\s+from\s+" + _name),
    // bank formats
    _ci(r"\b(?:upi|imps|neft)[\/\-](?:(?:dr|cr|p2a|p2m)[\/\-])?\d{3,}[\/\-]([A-Za-z][A-Za-z0-9&.' \-]{1,40})"),
    _ci(r"\binfo\b\s*[:\-]?\s*(?!upi|imps|neft)([A-Za-z][A-Za-z0-9&.' \-]{2,40})"),
    _ci(r"\b(?:to\s+)?vpa\s*[:\-]?\s*([a-z0-9._\-]{2,})@[a-z]+"),
    _ci(r"\b(?:payee|beneficiary|merchant|remitter|sender|biller)\s*[:\-]\s*([A-Za-z0-9][A-Za-z0-9&.' \-]{1,40})"),
    _ci(r";\s*([A-Za-z][A-Za-z0-9&.' \-]{1,40}?)\s+credited\b"),
    _ci(r"\btrf\s+to\s+([A-Za-z0-9][A-Za-z0-9&.' \-]{1,40})"),
    // mobile / DTH recharges: "Your Jio number … recharged", "Recharge … for Airtel"
    _ci(r"\b(jio|airtel(?:\s*dth)?|vodafone\s*idea|vodafone|vi|bsnl|tata\s*play|dish\s*tv|d2h|sun\s*direct)\b(?=[^.]{0,60}\brecharg)"),
    _ci(r"\brecharg\w*\b[^.]{0,40}?\b(jio|airtel(?:\s*dth)?|vodafone\s*idea|vodafone|vi|bsnl|tata\s*play|dish\s*tv|d2h|sun\s*direct)\b"),
    // merchant receipts: "Thank you for shopping at DMart", "…for choosing Croma"
    _ci(r"\bthanks?\s*(?:you\s*)?for\s+(?:shopping|dining|choosing|visiting|ordering)\s+(?:at\s+|with\s+|from\s+)?([A-Za-z0-9][A-Za-z0-9&.' \-]{1,40})"),
  ];
  static final _preposition =
      _ci(r"\b(at|to|towards|from|by|for)\s+([A-Za-z0-9][A-Za-z0-9&.'\-_ ]{1,45})");
  static final _dateThenCaps = RegExp(
      r"\b\d{1,2}[-\/][A-Za-z0-9]{2,3}[-\/]\d{2,4}\s+([A-Z][A-Z0-9&\-']+(?:\s+[A-Z][A-Z0-9&\-']+)*)");
  static final _vpaAny = _ci(
      r"\b([a-z0-9._\-]{3,})@(ybl|ibl|axl|okaxis|okhdfcbank|oksbi|okicici|paytm|upi|icici|hdfcbank|sbi|axisbank|kotak|yesbank|apl|fbl|freecharge|airtel|jio|idfcbank|pingpay|ptyes|ptaxis|pthdfc|ptsbi|waaxis|wahdfcbank|wasbi|naviaxis|superyes|timecosmos|rbl|aubank|federal|indus)\b");

  static final _junkTail = _ci(
      r"\s*\b(avl|avlbl|avbl|available|bal|balance|lmt|limit|ref|refno|rrn|utr|info|not\s*you|if\s*not|call|sms|upi|imps|neft|txn|a\/c|acct|on|dated|date|via|using|with|thru|through|inr|rs|card|ac|value|is|has|was|of|from|for|to|at|successful(ly)?|done|completed|towards)\b.*$");
  static final _stopStart = _ci(
      r"^(inform|queries|query|us\b|paying|stop\b|the\s+recent|shopping|dining|using|visiting|choosing|banking|being|making|payment|transaction|txn|transfer|purchase|order|amount|money|fund|funds|the\s+payment|online|pos\b|a\/c|ac\b|acct|account|your|you\b|the\s+(?:a\/c|account)|card|debit\s*card|credit\s*card|upi\b|vpa\b|bank\b|a\s|an\s|self\b|beneficiary\b|mobile|number|registered|linked|wallet\b|savings|current|loan\b|x{2,}|\*{2,}|\d|https?\b|www\b|timely\b|prompt\b|staying\b|confirm\b|next\b|this\b|assistance\b|non[\s-]|block\b|further\b|details\b|immediate|urgent\b|bill\s+no\b|mistake\b|be\s+claimed|be\s+credited|the\s+end\b|withdrawal\b|smart\s+savers|any\b|(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+\d)");
  static final _bankName = _ci(
      r"^(hdfc|sbi|state\s*bank|icici|axis|kotak|pnb|punjab|bob|bank\s*of|canara|union|indian\s*bank|idbi|yes\s*bank|indusind|idfc|federal|rbl|au\s*small|paytm\s*(payments\s*)?bank|airtel\s*payments|citi|hsbc|standard\s*chartered|uco|iob|central\s*bank)\b");
  static final _qrJunk = _ci(r"^(paytmqr|bharatpe|q\d{5,}|gpay-\d+|pay\d{6,}|\d)");
  static final _bankTail = _ci(
      r"\s+(?:-\s*)?(?:axis|hdfc|sbi|icici|kotak|pnb|bob|canara|union|idfc(?:\s*first)?|federal|yes|indusind|rbl|au|idbi|uco|iob|citi|hsbc)(?:\s+bank)?\s*$");
  static final _legalSuffix = _ci(
      r"\s+(com|pvt\.?|private|ltd\.?|limited|llp|inc\.?|india|technologies|tech|solutions|services|retail|payments)(\s+(pvt\.?|private|ltd\.?|limited|india))*\s*$");

  // ---------------- flags ----------------
  static final _link = _ci(
      r"https?:\/\/|www\.|bit\.ly|\b(?:[a-z0-9-]+\.)+[a-z]{2,}\/[\w\-.\/?=&%]+");
  static final _reversal = _ci(r"\b(revers(ed|al))\b");
  static final _debitedWord = _ci(r"\bdebited\b");
  static final _creditedWord = _ci(r"\bcredited\b");
  static final _withdrawal = _ci(r"\b(withdrawn|withdrawal)\b");
  static final _atm = _ci(r"\batm\b");
  static final _rechargeWord = _ci(r"\brecharg");
  static final _fastag = _ci(r"fastag");

  // Credit card bill payments. The card's "payment received" message isn't
  // income, and the bank's "debited towards CC payment" isn't new spending:
  // the card purchases themselves are already logged.
  static const _cardRef =
      r"\b(?:towards|on|to|for|in|against)\s+(?:your\s+|the\s+)?(?:[a-z]+\s+){0,4}?card\b";
  static final _cardBillReceived = _ci(
      r"\bpayment\b.{0,80}?\b(?:received|credited|realised|realized)\b.{0,40}?" +
          _cardRef +
          r"|\b(?:received|credited)\b.{0,20}?\bpayment\b.{0,60}?" +
          _cardRef +
          r"|\bthank\s*you\s*for\s*(?:your\s*|the\s*)?payment\b.{0,60}?" +
          _cardRef +
          r"|\b(?:payment|repayment)\b.{0,60}?\bfor\s+(?:your\s+|the\s+)?(?:[a-z]+\s+){0,5}?credit\s*card\b.{0,60}?\b(?:received|credited)\b"
          r"|\b(?:received|credited)\b.{0,40}?\bto\s+your\s+(?:[a-z]+\s+){0,4}?credit\s*card\b"
          r"|\bcredited\s+to\s+your\s+card\s+account\b");
  static final _ccBill = _ci(
      r"\b(cc|credit\s*card)\s*(bill|dues|payment|pymt|pmt)\b|\b(to|towards)\s+cred(\s*club)?\b|\b(payment|paid|bill)\b.{0,40}?\b(towards|for)\s+(your\s+|the\s+)?((?!using|via|with|through|from|at)[a-z]+\s+){0,3}?credit\s*card\b");
  static final _notBill = _ci(r"\b(refund(ed)?|revers(ed|al)|cashback)\b");
  static final _receivedWord = _ci(r"\b(received|credited)\b");
  static final _outgoingWord =
      _ci(r"\b(debited|deducted|paid|sent|spent|withdrawn)\b");

  // Transfers between your own accounts ("to Self", "own a/c").
  static final _selfTransfer =
      _ci(r"\bself\b|\bown\s*(a\/c|ac|acct|account)\b");
  static final _transferToAc = _ci(
      r"\b(transferred|trf|sent)\b.{0,40}?\bto\s+(your\s+)?(a\/c|ac|acct|account)\b");

  /// True for SMS senders that are personal phone numbers (scams). Real bank
  /// SMS come from alphanumeric DLT headers like "VM-HDFCBK".
  static bool isPersonalNumber(String? sender) {
    if (sender == null) return false;
    final clean = sender.replaceAll(RegExp(r"[\s\-]"), '');
    return RegExp(r"^\+?\d{7,15}$").hasMatch(clean);
  }

  static ParseResult parse(
    String body, {
    String source = 'sms', // 'sms' | 'notification'
    String? sender,
    DateTime? postedAt,
  }) {
    final posted = postedAt ?? DateTime.now();
    final text = _normalize(body).replaceAll(RegExp(r"[ \s]+"), ' ').trim();

    if (text.isEmpty) return ParseResult.reject('empty');
    if (source == 'sms' && isPersonalNumber(sender)) {
      return ParseResult.reject('personal-number');
    }
    if (_otp.hasMatch(text)) return ParseResult.reject('otp');
    if (_scam.hasMatch(text)) return ParseResult.reject('scam');
    if (_promo.hasMatch(text)) return ParseResult.reject('promo');
    if (_request.hasMatch(text)) return ParseResult.reject('request');
    if (_failed.hasMatch(text)) return ParseResult.reject('failed');
    if (_future.hasMatch(text)) return ParseResult.reject('future');
    if (_due.hasMatch(text) && !_moneyIn.hasMatch(text)) {
      return ParseResult.reject('future');
    }
    if (_scamCall.hasMatch(text) && !_bankHelpline.hasMatch(text)) {
      return ParseResult.reject('scam');
    }
    if (!_movement.hasMatch(text)) return ParseResult.reject('no-movement');

    if (_cardBillReceived.hasMatch(text) && !_notBill.hasMatch(text)) {
      return ParseResult.reject('card-bill');
    }

    final amount = _extractAmount(text);
    if (amount == null) return ParseResult.reject('no-amount');

    // Money coming back overrides a nearby "debited"
    // ("…debited earlier has been reversed and credited back").
    final bool? isDebit = _moneyBack.hasMatch(text)
        ? false
        : _outgoingReceived.hasMatch(text)
            ? true
            : _extractIsDebit(text, amount.$2);
    if (isDebit == null) return ParseResult.reject('no-direction');

    final allLast4 = _extractAllLast4(text);
    var merchant = _extractMerchant(text);
    // A recharge with no operator name still gets a readable title.
    if (merchant == null && isDebit && _rechargeWord.hasMatch(text)) {
      merchant = _fastag.hasMatch(text) ? 'FASTag' : 'Mobile recharge';
    }

    // Card bill: the card-side "payment received" is dropped; the bank-side
    // debit is kept but flagged so it's never auto-added.
    final cardBill = _ccBill.hasMatch(text) && !_notBill.hasMatch(text);
    final cardSide = !isDebit ||
        (_receivedWord.hasMatch(text) && !_outgoingWord.hasMatch(text));
    if (cardBill && cardSide) return ParseResult.reject('card-bill');

    final flags = <String>{};
    if (cardBill) flags.add('card-bill');
    if (_link.hasMatch(text)) flags.add('link');
    if (_reversal.hasMatch(text)) flags.add('reversal');
    if ((allLast4.length >= 2 &&
            _debitedWord.hasMatch(text) &&
            _creditedWord.hasMatch(text)) ||
        _selfTransfer.hasMatch(text) ||
        (allLast4.length >= 2 && _transferToAc.hasMatch(text))) {
      flags.add('transfer');
    }
    if (_withdrawal.hasMatch(text) && _atm.hasMatch(text)) flags.add('atm');

    var confidence = 0.5;
    if (merchant != null) confidence += 0.3;
    if (allLast4.isNotEmpty || source == 'notification') confidence += 0.2;

    return ParseResult.ok(ParsedTransaction(
      amount: amount.$1,
      isDebit: isDebit,
      merchant: merchant,
      last4: allLast4.isEmpty ? null : allLast4.first,
      allLast4: allLast4,
      reference: _extractReference(text),
      occurredAt: _extractDate(text, posted),
      confidence: confidence > 1 ? 1 : confidence,
      flags: flags,
    ));
  }

  // ---------------------------------------------------------------------

  /// Styled Unicode letters (𝗌𝗉𝖾𝗇𝗍 -> spent), non-breaking hyphens, and
  /// "Rs.1100credited" -> "Rs.1100 credited".
  static String _normalize(String body) {
    final out = StringBuffer();
    for (final cp in body.runes) {
      if (cp >= 0x1D400 && cp <= 0x1D6A3) {
        final i = (cp - 0x1D400) % 52;
        out.writeCharCode(i < 26 ? 65 + i : 97 + i - 26);
      } else if (cp >= 0x1D7CE && cp <= 0x1D7FF) {
        out.writeCharCode(48 + (cp - 0x1D7CE) % 10);
      } else if (cp == 0x2010 || cp == 0x2011) {
        out.write('-');
      } else {
        out.writeCharCode(cp);
      }
    }
    return out.toString().replaceAllMapped(
        _stuckMoveWord, (m) => '${m.group(1)} ${m.group(2)}');
  }

  static final _stuckMoveWord = _ci(r"(\d)(credited|debited)");

  static double? _toAmount(String raw) {
    final v = double.tryParse(raw.replaceAll(',', ''));
    if (v == null || !v.isFinite || v <= 0) return null;
    return (v * 100).round() / 100;
  }

  /// (amount, index). Skips numbers that are balances/limits.
  static (double, int)? _extractAmount(String text) {
    for (final re in [_amountPrefixed, _amountSuffixed]) {
      for (final m in re.allMatches(text)) {
        final amt = _toAmount(m.group(1)!);
        if (amt == null) continue;
        final from = m.start - 24 < 0 ? 0 : m.start - 24;
        final before = text.substring(from, m.start);
        final bm = _balanceBefore.firstMatch(before);
        // Skip balances/limits, but not "balance is debited for INR 250".
        if (bm != null &&
            !_movedWord.hasMatch(before.substring(bm.start))) {
          continue;
        }
        return (amt, m.start);
      }
    }
    final bare = _amountBare.firstMatch(text);
    if (bare != null) {
      final a = _toAmount(bare.group(1)!);
      if (a != null) return (a, bare.start);
    }
    return null;
  }

  static int? _nearest(String text, RegExp re, int anchor) {
    int? best;
    for (final m in re.allMatches(text)) {
      final d = (m.start - anchor).abs();
      if (best == null || d < best) best = d;
    }
    return best;
  }

  /// Direction from whichever keyword sits closest to the amount.
  static bool? _extractIsDebit(String text, int amountIndex) {
    final credit = _nearest(text, _creditWords, amountIndex);
    final debit = _nearest(text, _debitWords, amountIndex);
    if (credit == null && debit == null) return null;
    if (credit == null) return true;
    if (debit == null) return false;
    return !(credit <= debit);
  }

  static String _titleCase(String s) => s
      .toLowerCase()
      .replaceAllMapped(RegExp(r"\b[a-z]"), (m) => m.group(0)!.toUpperCase());

  static String? cleanMerchant(String? raw) {
    if (raw == null) return null;
    var v = raw.replaceAll(RegExp(r"\s+"), ' ').trim();
    final cut = v.indexOf(RegExp(r"[.;!?,](\s|$)"));
    if (cut > 0) v = v.substring(0, cut);
    v = v.replaceFirst(RegExp(r"\s+\d{1,2}[-\/]\w{2,3}[-\/]\d{2,4}.*$"), '');
    v = v.replaceFirst(_junkTail, '').trim();
    v = v.replaceFirst(RegExp(r"[\/\-]+[A-Z]{3,4}$"), '').trim(); // ZOMATO/ICIC
    v = v.replaceFirst(_bankTail, '').trim(); // "SWIGGY Axis Bank"
    v = v
        .replaceFirst(RegExp(r"^[^A-Za-z0-9]+"), '')
        .replaceFirst(RegExp(r"[^A-Za-z0-9]+$"), '')
        .trim();
    v = v.replaceFirst(RegExp(r"\s+[A-Za-z]$"), '').trim();
    if (_qrJunk.hasMatch(v)) return null;
    v = v.replaceFirstMapped(
        RegExp(r"^([A-Za-z]{3,})\d{3,}$"), (m) => m.group(1)!); // ZOMATO3214
    v = v.replaceAll(RegExp(r"[._]+"), ' ').trim();
    if (v.length < 2) return null;
    if (RegExp(r"^\d+$").hasMatch(v)) return null;
    if (_stopStart.hasMatch(v) || _bankName.hasMatch(v)) return null;
    final stripped = v.replaceFirst(_legalSuffix, '').trim();
    if (stripped.length >= 2) v = stripped;
    if (v == v.toUpperCase() || v == v.toLowerCase()) v = _titleCase(v);
    return v.length > 40 ? v.substring(0, 40).trim() : v;
  }

  static String? _extractMerchant(String text) {
    for (final re in _merchantStrategies) {
      final m = re.firstMatch(text);
      if (m != null && m.group(1) != null) {
        final c = cleanMerchant(m.group(1));
        if (c != null) return c;
      }
    }
    final vpa = _vpaAny.firstMatch(text);
    if (vpa != null) {
      final c = cleanMerchant(vpa.group(1));
      if (c != null) return c;
    }
    // Try each "at/to/from/…" in turn; after a miss, resume right after the
    // preposition so a later "to SWIGGY" inside the rejected span is found.
    var start = 0;
    while (start < text.length) {
      final it = _preposition.allMatches(text, start).iterator;
      if (!it.moveNext()) break;
      final m = it.current;
      final c = cleanMerchant(m.group(2));
      if (c != null) return c;
      start = m.start + m.group(1)!.length + 1;
    }
    final dc = _dateThenCaps.firstMatch(text);
    if (dc != null) {
      final c = cleanMerchant(dc.group(1));
      if (c != null) return c;
    }
    return null;
  }

  static List<String> _extractAllLast4(String text) {
    final found = <(int, String)>[];
    for (final re in [_last4Masked, _last4Labelled]) {
      for (final m in re.allMatches(text)) {
        final g = m.group(1);
        if (g == null) continue;
        found.add((m.start, g.length > 4 ? g.substring(g.length - 4) : g));
      }
    }
    found.sort((a, b) => a.$1.compareTo(b.$1));
    return <String>{for (final f in found) f.$2}.toList();
  }

  static String? _extractReference(String text) {
    for (final re in _referencePatterns) {
      final m = re.firstMatch(text);
      final g = m?.group(1);
      if (g != null && _hasFourDigits.hasMatch(g)) return g;
    }
    return _twelveDigits.firstMatch(text)?.group(1);
  }

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  /// Date mentioned in the text if it's within 45 days of when the message
  /// arrived; same-day dates keep the real arrival time. A finished payment
  /// can't be dated after the message, so later dates ("valid till 12 Oct",
  /// "next renewal on …") are skipped and the next date is tried.
  static DateTime _extractDate(String text, DateTime posted) {
    final postedDay = DateTime(posted.year, posted.month, posted.day);
    DateTime? build(int d, int mo, int y) {
      if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
      final yy = y < 100 ? 2000 + y : y;
      final c = DateTime(yy, mo, d, 12);
      if (c.difference(posted).inDays.abs() > 45) return null;
      if (DateTime(yy, mo, d).isAfter(postedDay)) return null;
      if (c.year == posted.year &&
          c.month == posted.month &&
          c.day == posted.day) {
        return posted;
      }
      return c;
    }

    for (final m in _isoDate.allMatches(text)) {
      final r = build(int.parse(m.group(3)!), int.parse(m.group(2)!),
          int.parse(m.group(1)!));
      if (r != null) return r;
    }
    for (final m in _namedMonthDate.allMatches(text)) {
      final mo = _months[m.group(2)!.toLowerCase()];
      if (mo == null) continue;
      final r = build(int.parse(m.group(1)!), mo, int.parse(m.group(3)!));
      if (r != null) return r;
    }
    for (final m in _numericDate.allMatches(text)) {
      final r = build(int.parse(m.group(1)!), int.parse(m.group(2)!),
          int.parse(m.group(3)!));
      if (r != null) return r;
    }
    return posted;
  }

  static final _isoDate = RegExp(r"\b(\d{4})-(\d{1,2})-(\d{1,2})\b");
  static final _namedMonthDate =
      RegExp(r"\b(\d{1,2})[-\s]?([A-Za-z]{3})[a-z]*[-\s',]*(\d{2,4})\b");
  static final _numericDate =
      RegExp(r"\b(\d{1,2})[-\/.](\d{1,2})[-\/.](\d{2,4})\b");
}
