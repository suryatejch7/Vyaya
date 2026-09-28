// Generated from the parser's development + holdout corpus: real-format Indian
// bank SMS and payment-app notifications, including scams and promos.
// Run: flutter test test/transaction_parser_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:expensetracker/services/capture/transaction_parser.dart';

String _norm(String? s) =>
    (s ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

void _accept(String text, double amount, bool isDebit, String? merchant,
    {String source = 'sms', String? flag, List<String> absent = const []}) {
  final r = TransactionParser.parse(text,
      source: source, postedAt: DateTime(2026, 8, 16, 10));
  expect(r.isOk, isTrue, reason: 'rejected (${r.rejectReason}): $text');
  final t = r.transaction!;
  expect(t.amount, closeTo(amount, 0.001), reason: text);
  expect(t.isDebit, isDebit, reason: text);
  if (merchant != null) {
    expect(_norm(t.merchant), _norm(merchant), reason: text);
  }
  if (flag != null) expect(t.flags, contains(flag), reason: text);
  for (final f in absent) {
    expect(t.flags, isNot(contains(f)), reason: text);
  }
}

void _reject(String text, {String source = 'sms', String? sender}) {
  final r = TransactionParser.parse(text,
      source: source, sender: sender, postedAt: DateTime(2026, 8, 16, 10));
  expect(r.isOk, isFalse, reason: 'should be rejected: $text');
}

void main() {
  test('#1 debit 450', () => _accept('SBI: Rs.450.00 debited from A/c XX1234 on 16-08-26 for UPI txn to SWIGGY. Ref 612345678901.', 450.0, true, 'Swiggy'));
  test('#2 debit 1250', () => _accept('HDFC Bank: Rs 1,250.00 spent via UPI from A/c XX5678 to AMAZON. UPI Ref No 623456789012.', 1250.0, true, 'Amazon'));
  test('#3 debit 450', () => _accept('Dear Customer, Rs.450.00 has been debited from your HDFC Bank A/c XX4021 to SWIGGY on 14-Aug-2026 via UPI Ref 422891829102. Avl Bal: Rs 25,400.00', 450.0, true, 'Swiggy'));
  test('#4 debit 1200', () => _accept('INR 1,200.00 debited from A/c XX4321 on 12-Aug-25. Info: UPI/523401/ZOMATO. Avl Bal INR 22,300.55', 1200.0, true, 'Zomato'));
  test('#5 debit 500', () => _accept('Rs.500 debited. Info: UPI/DR/523401234567/ZOMATO/ICIC', 500.0, true, 'Zomato'));
  test('#6 debit 500', () => _accept('Rs.500 debited from A/c X8899 on 12/08/25 transfer to BLINKIT Ref 402214 -SBI', 500.0, true, 'Blinkit'));
  test('#7 debit 500', () => _accept('Rs.500.00 debited from a/c **1234 on 15-08-26 to VPA merchant@ybl. UPI Ref 123456789012. Not you? Call 1800-111-222.', 500.0, true, 'Merchant'));
  test('#8 debit 2050', () => _accept('Alert: INR 2,050.00 deducted from A/C XXXXXX5555 on 16/08/26 14:20 via UPI. Payee: Swiggy. Bal: INR 12,000.', 2050.0, true, 'Swiggy'));
  test('#9 debit 180', () => _accept('UPI Alert: Your A/c XX1234 has been debited by Rs 180 for payment to TEA SHOP. Ref 845612349876.', 180.0, true, 'Tea Shop'));
  test('#10 debit 150', () => _accept('Sent Rs. 150.00 from HDFC Bank Acct 9999 to Rahul. UPI Ref 654321. Bal: Rs. 10,500.25.', 150.0, true, 'Rahul'));
  test('#11 debit 120', () => _accept('Sent Rs.120.00 From HDFC Bank A/C *1234 To SWIGGY On 27/09/26 Ref 626491234567 Not You? Call 18002586161/SMS BLOCK UPI to 7308080808', 120.0, true, 'Swiggy'));
  test('#12 debit 120', () => _accept('Dear UPI user A/C X1234 debited by 120.0 on date 27Sep26 trf to SWIGGY Refno 626491234567. If not u? call 1800111109. -SBI', 120.0, true, 'Swiggy'));
  test('#13 debit 120', () => _accept('ICICI Bank Acct XX123 debited for Rs 120.00 on 27-Sep-26; SWIGGY credited. UPI:626491234567. Call 18002662 for dispute. SMS BLOCK 123 to 9215676766', 120.0, true, 'Swiggy'));
  test('#14 debit 120', () => _accept('INR 120.00 debited A/c no. XX1234 27-09-26 12:00:00 UPI/P2M/626491234567/SWIGGY Not you? SMS BLOCKUPI Cust ID to 919951860002 Axis Bank', 120.0, true, 'Swiggy'));
  test('#15 debit 120', () => _accept('Sent Rs.120.00 from Kotak Bank AC X1234 to swiggy@icici on 27-09-26.UPI Ref 626491234567. Not you, https://kotak.com/KBANKT/Fraud', 120.0, true, 'Swiggy'));
  test('#16 debit 650', () => _accept('Transaction successful. Paid Rs.650.00 to SWIGGY using UPI from HDFC A/c XX1234.', 650.0, true, 'Swiggy'));
  test('#17 debit 250', () => _accept('Rs.250 paid to Sharma Sweets and Dhaba via UPI', 250.0, true, 'Sharma Sweets And Dhaba'));
  test('#18 debit 500', () => _accept('SBI: Rs 500 debited from A/c XX1234 via UPI to ZOMATO.', 500.0, true, 'Zomato'));
  test('#19 debit 99.99', () => _accept('Rs.99.99 debited from A/c XX1111 on 12-08-25 to NETFLIX Ref 8812', 99.99, true, 'Netflix'));
  test('#20 debit 1250', () => _accept('Available balance Rs 25,000. Debit of Rs 1,250 towards UPI transaction.', 1250.0, true, null));
  test('#21 debit 349.5', () => _accept('Axis Bank: INR 349.50 debited from A/c XX9876 for UPI payment.', 349.5, true, null));
  test('#22 debit 750', () => _accept('SBI A/c XX1234 debited Rs.750.00. Available balance: Rs.14,350.25.', 750.0, true, null));
  test('#23 debit 500', () => _accept('Rs.500 debited. Your available balance is Rs.10,500.00.', 500.0, true, null));
  test('#24 debit 450', () => _accept('Rs.450.00 spent on HDFC Bank Card x1234 at SWIGGY on 12-08-25. Not you? Call 18002586161', 450.0, true, 'Swiggy'));
  test('#25 debit 2000', () => _accept('Rs.2,000.00 spent on HDFC Bank Card x1234 at HPCL PETROL PUMP on 12-08-25.', 2000.0, true, 'Hpcl Petrol Pump'));
  test('#26 debit 799', () => _accept('ICICI Bank: Your Debit Card XX4321 was used for Rs.799.00 at FLIPKART on 16-Aug-26. Avl Bal Rs.24,560.50.', 799.0, true, 'Flipkart'));
  test('#27 debit 2499', () => _accept('Axis Bank: INR 2,499.00 debited on Debit Card XX7788 at MYNTRA on 16-Aug-26.', 2499.0, true, 'Myntra'));
  test('#28 debit 3450', () => _accept('HDFC Bank Credit Card XX1122: Rs.3,450.00 spent at CROMA on 16-Aug-26.', 3450.0, true, 'Croma'));
  test('#29 debit 12750', () => _accept('Dear Customer, Rs.12,750 spent on Axis Bank Credit Card XX5566 at RELIANCE DIGITAL on 16-Aug-26.', 12750.0, true, 'Reliance Digital'));
  test('#30 debit 1899', () => _accept('INR 1,899.00 spent on ICICI Bank Card ending 4402 on 10-Aug-2026 at AMAZON INDIA. Avl Limit: INR 85,000.00', 1899.0, true, 'Amazon'));
  test('#31 debit 250', () => _accept('Spent Card no. XX5678 INR 250 12-08-25 UBER INDIA Avl Lmt INR 145000', 250.0, true, 'Uber'));
  test('#32 debit 540', () => _accept('Thank you for using your Citi Card 8899 for Rs. 540 at STARBUCKS on 14AUG26. Limit available Rs. 89,000.', 540.0, true, 'Starbucks'));
  test('#33 debit 780', () => _accept('POS purchase of ₹780.00 at RELIANCE SMART with A/c ***2222 on 16-08-2026. Available balance ₹4,321.00', 780.0, true, 'Reliance Smart'));
  test('#34 debit 2000', () => _accept('Fuel purchase: Rs. 2,000.00 debited at HP PUMP with A/c XX6666, Date: 16-08-2026. Avl Bal: Rs. 30,000.00', 2000.0, true, 'Hp Pump'));
  test('#35 debit 1200', () => _accept('Rs.1200.00 spent on your SBI Credit Card ending 9876 at ZOMATO on 27/09/26. Trxn. not done by you? Report at https://sbicard.com/Dispute', 1200.0, true, 'Zomato'));
  test('#36 debit 5000', () => _accept('SBI: Rs.5,000.00 withdrawn from ATM using Debit Card XX8899 on 16-08-26. Avl Bal Rs.18,420.00.', 5000.0, true, null, flag: 'atm'));
  test('#37 debit 5000', () => _accept('Rs.5,000 withdrawn from A/c X8899 at ATM on 12-08-25. Avl Bal Rs.10,000', 5000.0, true, 'Atm', flag: 'atm'));
  test('#38 debit 15500', () => _accept('Alert: EMI of Rs. 15,500.00 for your Home Loan XX1122 has been debited from Savings A/c XX4455 on 05-Aug-2026.', 15500.0, true, null));
  test('#39 debit 1450', () => _accept('Rs 1,450.00 debited from A/c XX5678 for BESCOM electricity bill on 05-Aug-2026 via UPI.', 1450.0, true, 'Bescom Electricity Bill'));
  test('#40 debit 1499', () => _accept('Rs. 1,499.00 has been debited from your A/c XXXXX5555 on 10-08-26 towards JIO FIBER auto-pay. Bal Rs 14,000.', 1499.0, true, 'Jio Fiber Auto-pay'));
  test('#41 debit 500', () => _accept('Kotak Bank: Rs.500.00 debited from A/c XX6789 towards PAYTM wallet recharge.', 500.0, true, 'Paytm Wallet Recharge'));
  test('#42 debit 249', () => _accept('Paid Rs. 249.00 towards Uber ride using Paytm Bank A/c XX9921 on 14-Aug-2026. Txn ID: 8492049182.', 249.0, true, 'Uber Ride'));
  test('#43 debit 295', () => _accept('Dear Customer, Annual maintenance charge of Rs 295.00 has been deducted from A/c XX1234 on 15/08/26. Available balance is Rs 9,500.25.', 295.0, true, null));
  test('#44 debit 1234', () => _accept('Electricity bill payment of ₹1,234.00 made from A/c 2222 to BSES. Txn ID UPI612345012348. Bal ₹9,876', 1234.0, true, 'Bses'));
  test('#45 debit 7500', () => _accept('Kotak Mahindra Bank: Rs 7,500.00 debited from A/c XX3456 through NEFT. Beneficiary: JOHN.', 7500.0, true, 'John'));
  test('#46 credit 2500', () => _accept('ICICI Bank: Rs.2,500.00 credited to A/c XX9012 via UPI from Rahul. UPI Ref 634567890123.', 2500.0, false, 'Rahul'));
  test('#47 credit 75000', () => _accept('HDFC Bank: Rs.75,000.00 credited to A/c XX1234. Salary credit from ABC TECHNOLOGIES LTD.', 75000.0, false, 'Abc'));
  test('#48 credit 85000', () => _accept('Your A/c XX2211 is credited with INR 85,000.00 on 01-Aug-25 by SALARY HEAPTRACE. Avl Bal INR 91,204.10', 85000.0, false, 'Salary Heaptrace'));
  test('#49 credit 1299', () => _accept('Rs.1,299.00 credited to A/c XX1234 on 12-08-25 as refund from AMAZON.', 1299.0, false, 'Amazon'));
  test('#50 credit 350', () => _accept('Refund of INR 350.00 has been credited to your ICICI Bank A/c XX3029 from ZOMATO.', 350.0, false, 'Zomato'));
  test('#51 credit 500', () => _accept('Rs.500 credited. Info: UPI/CR/412345678901/RAHUL', 500.0, false, 'Rahul'));
  test('#52 credit 1500', () => _accept('Dear Customer, Acct XX5678 is credited with INR 1,500.00 on 14-Aug-26 from UPI/user@okaxis. Ref 987654321.', 1500.0, false, null));
  test('#53 credit 1245.6', () => _accept('SBI: Interest of Rs.1,245.60 credited to Savings A/c XX9876.', 1245.6, false, null));
  test('#54 credit 52500', () => _accept('SBI: Your A/c XX7788 is credited with INR 52,500.00 by NEFT. Remitter: XYZ SOLUTIONS PVT LTD.', 52500.0, false, 'Xyz'));
  test('#55 credit 15000', () => _accept('Axis Bank: INR 15,000.00 credited to A/c XX5678 via IMPS. Sender: ANIL KUMAR. Ref 765432198.', 15000.0, false, 'Anil Kumar'));
  test('#56 credit 450', () => _accept('SBI: Rs.450.00 credited to A/c XX1234 as UPI transaction reversal. Ref 612345678901.', 450.0, false, null, flag: 'reversal'));
  test('#57 credit 1500', () => _accept('Rs.1,500 debited earlier has been reversed and credited back to your A/c XX1234.', 1500.0, false, null, flag: 'reversal'));
  test('#58 credit 50', () => _accept('Cashback of Rs 50 credited to your TestBank account for UPI txn 612345012347. Balance Rs 1,250', 50.0, false, null));
  test('#59 credit 10000', () => _accept('Dear Customer, Rs. 10,000.00 credited to your account **9988 on 15/08/2026 via RTGS from MR SHARMA. Available Balance is INR 50,000.', 10000.0, false, 'Mr Sharma'));
  test('#60 debit 30000', () => _accept('Rs.30000 debited from A/c XX1234 credited to A/c XX5678 via UPI', 30000.0, true, null, flag: 'transfer'));
  test('#61 debit 20000', () => _accept('Rs.20000 debited from A/c XX1234 and credited to A/c XX5678 on 20-Aug-25. UPI/523401', 20000.0, true, null, flag: 'transfer'));
  test('#62 debit 450', () => _accept('₹450 paid to Swiggy', 450.0, true, 'Swiggy', source: 'notification'));
  test('#63 debit 450', () => _accept('₹450 paid to Swiggy — Paid with HDFC Bank ••1234', 450.0, true, 'Swiggy', source: 'notification'));
  test('#64 debit 1899', () => _accept('Payment successful — ₹1,899 paid to Amazon Pay', 1899.0, true, 'Amazon Pay', source: 'notification'));
  test('#65 debit 120', () => _accept('Paid ₹120 to Swiggy', 120.0, true, 'Swiggy', source: 'notification'));
  test('#66 debit 75', () => _accept('You paid ₹75 to Ramesh Kumar', 75.0, true, 'Ramesh Kumar', source: 'notification'));
  test('#67 debit 299', () => _accept('Payment of ₹299 to Spotify successful', 299.0, true, 'Spotify', source: 'notification'));
  test('#68 debit 500', () => _accept('Money sent — ₹500 sent to Priya Sharma', 500.0, true, 'Priya Sharma', source: 'notification'));
  test('#69 credit 500', () => _accept('Received ₹500 from Rahul Kumar', 500.0, false, 'Rahul Kumar', source: 'notification'));
  test('#70 credit 2000', () => _accept('Money received — Received ₹2,000 from Dad', 2000.0, false, 'Dad', source: 'notification'));
  test('#71 credit 200', () => _accept('Rahul Kumar — Paid you ₹200', 200.0, false, 'Rahul Kumar', source: 'notification'));
  test('#72 credit 350', () => _accept('Priya sent you ₹350', 350.0, false, 'Priya', source: 'notification'));
  test('#73 credit 1000', () => _accept('₹1,000 received from Amit', 1000.0, false, 'Amit', source: 'notification'));
  test('#74 debit 120', () => _accept('Paid Rs.120 to Chai Point', 120.0, true, 'Chai Point', source: 'notification'));
  test('#75 debit 480', () => _accept('Paid ₹480 to Swiggy via PhonePe on 12-Sep-2026. UTR 425678912345. Thank you for using PhonePe.', 480.0, true, 'Swiggy', source: 'notification'));
  test('#76 credit 499', () => _accept('Refund of ₹499 processed — ₹499 has been credited to your account for your order', 499.0, false, null, source: 'notification'));
  test('#77 rejects', () => _reject('123456 is your OTP for a transaction of Rs.5000 at Amazon. Do not share.'));
  test('#78 rejects', () => _reject('Avl Bal in A/c XX1234 is Rs.22,300.55 as on 12-08-25'));
  test('#79 rejects', () => _reject('Dear Customer, your available balance in A/C XX4021 is INR 35000.00 as on 15-Aug-2026.'));
  test('#80 rejects', () => _reject('Get a pre-approved loan of Rs.5,00,000. Apply now!'));
  test('#81 rejects', () => _reject('Congratulations! You are eligible for an instant personal loan of up to Rs. 5,00,000 with zero documentation. Apply now: https://bit.ly/loan'));
  test('#82 rejects', () => _reject('Good news! Pre-approved personal loan of upto Rs.500000 is credited instantly when you apply on HDFC Bank. Click to avail: https://bit.ly/loan'));
  test('#83 rejects', () => _reject('Dear Customer, your Axis Bank credit card limit has been enhanced to Rs.200000. Avail this exclusive offer now: http://offers.bank.com'));
  test('#84 rejects', () => _reject('Congratulations! You have received a scratch card cashback of Rs 1,999 from Google Pay. Click here to receive the money directly in your UPI a/c: http://gpay-cashback-scam.in'));
  test('#85 rejects', () => _reject('Dear Customer, Your Mobile No. has been selected for KBC Lottery 2026 of ₹25,00,000. To claim your prize pay ₹1500 registration fee to UPI: kbc-prime@okaxis'));
  test('#86 rejects', () => _reject('Dear User, Rs. 25,000.00 has been credited to your bank account. Claim your amount here: http://claim-your-reward.com'));
  test('#87 rejects', () => _reject('Flipkart: Refund of Rs 1,200 initiated to your account. To confirm bank details and receive money, call our WhatsApp Support: 88XXXXXX99'));
  test('#88 rejects', () => _reject('PhonePe Alert: Your wallet has been hacked and Rs 5,000 transferred. Click here to freeze your account and reverse transaction: http://phonepe-secure.com'));
  test('#89 rejects', () => _reject('Rs 2,000 credited to your account. Download the attached APK (statement.pdf.exe) to view transaction details and statement.'));
  test('#90 rejects', () => _reject('I have recorded your private videos. Pay Rs 20,000 to UPI ID: blackmailer@oksbi or I will send them to your family contacts.'));
  test('#91 rejects', () => _reject('Amazon is hiring! Work part-time and earn up to Rs 8,000/day. No experience needed. Contact HR: +919000000000.'));
  test('#92 rejects', () => _reject('EPFO: Your PF amount of Rs 2,50,000 is ready for withdrawal. Pay Rs 500 tax fee to UPI ID: epfo-tax-clearance@oksbi to release funds.'));
  test('#93 rejects', () => _reject('Your UPI transaction of Rs.500 to SWIGGY has failed. Amount will be refunded if debited.'));
  test('#94 rejects', () => _reject('Payment of ₹299 to Spotify failed', source: 'notification'));
  test('#95 rejects', () => _reject('Your credit card payment of Rs 5,400 is due on 05-Oct-26. Minimum amount due Rs 270.'));
  test('#96 rejects', () => _reject('Rs.1,499 will be debited from your A/c XX5555 on 10-Oct-26 towards JIO FIBER as per mandate.'));
  test('#97 rejects', () => _reject('Rahul has requested ₹500 from you on Google Pay', source: 'notification'));
  test('#98 rejects', () => _reject('Rahul is requesting ₹250. Pay now on PhonePe', source: 'notification'));
  test('#99 rejects', () => _reject('Get flat 20% off on your next Swiggy order! Use code SAVE20. Cashback worth Rs 100', source: 'notification'));
  test('#100 rejects', () => _reject('Dear customer, your A/c XX1234 debited Rs 500 for UPI txn to SWIGGY', sender: '+919876543210'));
  test('#101 credit 500', () => _accept('Money Received - INR 500.00 in your HDFC Bank A/c xx1234 on 27-09-26 by A/c linked to VPA rahul@okaxis (UPI Ref No 626491234567).', 500.0, false, 'Rahul'));
  test('#102 debit 120', () => _accept('Rs.120.00 debited from A/c **1234 on 27-09-26 to VPA swiggy.stores@axb (UPI Ref No 626491234567). Not you? Call 18002586161', 120.0, true, 'Swiggy Stores'));
  test('#103 debit 30', () => _accept('Paid ₹30 to Sharma Ji Chaiwala from Paytm Payments Bank', 30.0, true, 'Sharma Ji Chaiwala', source: 'notification'));
  test('#104 debit 200', () => _accept('₹200 sent to Rahul', 200.0, true, 'Rahul', source: 'notification'));
  test('#105 debit 12000', () => _accept('Payment of ₹12,000 towards your HDFC credit card is successful', 12000.0, true, null, source: 'notification', flag: 'card-bill'));
  test('#106 credit 499', () => _accept('Your refund of ₹499.00 has been processed', 499.0, false, null, source: 'notification'));
  test('#107 rejects', () => _reject('Your order of 2 items worth ₹1,299 has been shipped', source: 'notification'));
  test('#108 debit 1500', () => _accept('Your A/c XX1234 is debited for Rs.1,500.00 on 27-09-26 and A/c of RAHUL is credited (UPI Ref no 626491234567)', 1500.0, true, null));
  test('#109 debit 500', () => _accept('Rs.500.00 Dr. from A/C XXXXXX1234 and Cr. to swiggy@axisbank. Ref:626491234567. AvlBal:Rs1000.00(2026:09:27 12:00:00). Not you? Call 18005700-BOB', 500.0, true, 'Swiggy'));
  test('#110 debit 120', () => _accept('Your A/c XX1234 debited INR 120.00 on 27-09-26 18:30:00 through UPI:626491234567, avl bal INR 1000.00 -PNB', 120.0, true, null));
  test('#111 debit 120', () => _accept('An amount of INR 120.00 has been DEBITED to your account XXX123 on 27/09/2026 towards UPI. Total Avail.bal INR 1,000.00 - Canara Bank', 120.0, true, null));
  test('#112 debit 120', () => _accept('Your A/C XXXXXXX1234 has been debited with INR 120.00 on 27/09/2026 12:00 towards UPI/626491234567/SWIGGY. Avl bal INR 1,000.00.', 120.0, true, 'Swiggy'));
  test('#113 debit 120', () => _accept('A/c *1234 Debited for Rs:120.00 on 27-09-2026 12:00:00 by Mob Bk ref no 626491234567 Avl Bal Rs:1000.00', 120.0, true, null));
  test('#114 debit 120', () => _accept('Rs 120.00 debited from your A/c XX1234 to SWIGGY on 27-09-2026 via UPI. Ref no: 626491234567', 120.0, true, 'Swiggy'));
  test('#115 credit 500', () => _accept('INR 500.00 credited to your A/c XX1234 on 27-09-26 from VPA dad@oksbi (UPI Ref 626491234567)', 500.0, false, 'Dad'));
  test('#116 debit 150', () => _accept('Your A/c XX1234 has a debit of Rs.150.00 on 27Sep26', 150.0, true, null));
  test('#117 rejects', () => _reject('Dear Customer, your SBI YONO account will be blocked today. Update PAN: http://sbi-yono-update.in'));
  test('#118 rejects', () => _reject('Get ₹75 cashback on your first electricity bill payment', source: 'notification'));
  test('#119 rejects', () => _reject('You have won ₹10 cashback! Scratch now', source: 'notification'));
  test('#120 credit 10', () => _accept('₹10 cashback received in your wallet', 10.0, false, null, source: 'notification'));
  test('#121 credit 5000', () => _accept('Rs 5000 credited to your a/c XX1234 by a/c linked to mobile 9XXXXXX999 (IMPS Ref no 123456789012)', 5000.0, false, null));
  test('#122 rejects', () => _reject('Your SIP of Rs.5,000 is scheduled for 05-Oct-26. Ensure sufficient balance.'));
  test('#123 rejects', () => _reject('Your electricity bill of Rs 1,234 for BESCOM is generated. Pay by 10-Oct-26 to avoid late fee.'));
  test('#124 debit 999', () => _accept('Dear Customer, Rs.999.00 has been debited from your A/c XX4321 towards NETFLIX COM on 27-09-26. Available balance Rs.5,000', 999.0, true, 'Netflix'));
  test('#125 debit 60', () => _accept('UPI txn of Rs 60 to NAMMA METRO successful. A/c XX1234. Ref 626491234567', 60.0, true, 'Namma Metro'));
  test('#126 debit 350', () => _accept('Rs 350.00 debited via UPI on 27-09-2026 to RAPIDO. A/c XX1234 UPI Ref 626491234567 -Federal Bank', 350.0, true, 'Rapido'));

  // Credit card bill payments and own-account transfers.
  test('#127 card bill payment dropped', () => _reject('Payment of Rs 5,000.00 has been received towards your ICICI Bank Credit Card XX1234 on 14-Aug-26. Thank you.'));
  test('#128 card bill payment dropped', () => _reject('Dear Customer, payment of INR 12,500 received on your HDFC Bank Credit Card ending 4321.'));
  test('#129 card bill payment dropped', () => _reject('We have received payment of Rs.8,000.00 on your SBI Credit Card ending 5566 on 03/09/26.'));
  test('#130 card bill payment dropped', () => _reject('Thank you for your payment of Rs 3,450 towards your Axis Bank Credit Card XX9087.'));
  test('#131 card bill payment dropped', () => _reject('Your payment of Rs 5000 has been credited to your credit card account XX1234.'));
  test('#132 card bill payment dropped', () => _reject('CC payment of Rs 5000 received. Thank you. -SBI Card'));
  test('#133 card bill 5000', () => _accept('Rs.5000.00 debited from A/c XX7788 on 14-08-26 towards CC payment. Avl Bal Rs 20000 -ICICI', 5000.0, true, null, flag: 'card-bill'));
  test('#134 card bill 12000', () => _accept('Rs 12,000 debited from your a/c XX1234 for Credit Card bill payment via BillDesk.', 12000.0, true, null, flag: 'card-bill'));
  test('#135 card bill 5000', () => _accept('Paid Rs 5000 to CRED Club via UPI. UPI Ref 123456789012', 5000.0, true, null, flag: 'card-bill'));
  test('#136 card bill 4500', () => _accept('You paid ₹4,500 to CRED', 4500.0, true, null, flag: 'card-bill'));
  test('#137 not a bill or transfer 500', () => _accept('Payment of Rs 500 to Swiggy successful using ICICI Credit Card XX1234', 500.0, true, 'Swiggy', absent: const ['card-bill', 'transfer']));
  test('#138 not a bill or transfer 3200', () => _accept('INR 3,200.00 spent on ICICI Bank Card XX1234 on 12-Aug-26 at AMAZON.', 3200.0, true, 'Amazon', absent: const ['card-bill', 'transfer']));
  test('#139 not a bill or transfer 500', () => _accept('Refund of Rs 500 has been credited to your credit card XX1234 from Flipkart', 500.0, false, 'Flipkart', absent: const ['card-bill', 'transfer']));
  test('#140 not a bill or transfer 799', () => _accept('Rs 799 debited from HDFC Credit Card XX1234 at NETFLIX on 01-09-26', 799.0, true, 'Netflix', absent: const ['card-bill', 'transfer']));
  test('#141 not a bill or transfer 250', () => _accept('Paid ₹250 to Swiggy via CRED UPI', 250.0, true, 'Swiggy', absent: const ['card-bill', 'transfer']));
  test('#142 own transfer 10000', () => _accept('Rs 10000 transferred from A/c XX1234 to A/c XX5678 (self). Ref 123456789012', 10000.0, true, null, flag: 'transfer'));
  test('#143 own transfer 2000', () => _accept('Rs 2000 sent via IMPS to Self from A/c XX1234. Ref 612345678901', 2000.0, true, null, flag: 'transfer'));
  test('#144 own transfer 5000', () => _accept('Rs 5000 debited from A/c XX1234 and credited to A/c XX5678. UPI Ref 1234', 5000.0, true, null, flag: 'transfer'));
  test('#145 own transfer 3000', () => _accept('Rs 3000 transferred to your own account XX9876 from A/c XX1234', 3000.0, true, null, flag: 'transfer'));
  test('#146 not a bill or transfer 500', () => _accept('Rs 500 debited from A/c XX1234 to VPA rahul@okaxis. UPI Ref 123456789012', 500.0, true, 'Rahul', absent: const ['card-bill', 'transfer']));
  test('#147 not a bill or transfer 150', () => _accept('Sent Rs 150 to Selfie Studio via UPI', 150.0, true, 'Selfie Studio', absent: const ['card-bill', 'transfer']));
  test('#148 not a bill or transfer 2000', () => _accept('Rs 2,000 credited to A/c XX1234 by NEFT from ACME PVT LTD', 2000.0, false, 'Acme', absent: const ['card-bill', 'transfer']));
  test('#149 not a bill or transfer 450', () => _accept('Your A/c XX1234 has been debited by Rs 450 for purchase at DMART using card XX9876', 450.0, true, 'Dmart', absent: const ['card-bill', 'transfer']));
  test('#150 not a bill or transfer 299', () => _accept('Your payment of Rs 299 to Netflix has been posted on your credit card XX1234', 299.0, true, 'Netflix', absent: const ['card-bill', 'transfer']));
  test('#151 not a bill or transfer 500', () => _accept('Thank you for the payment of Rs 500 made on 12-Aug using your credit card at Swiggy', 500.0, true, 'Swiggy', absent: const ['card-bill', 'transfer']));
  test('#152 not a bill or transfer 500', () => _accept('Payment of Rs 500 received from Rahul. Credited to your A/c XX1234', 500.0, false, 'Rahul', absent: const ['card-bill', 'transfer']));
  test('#153 card bill payment dropped', () => _reject('Your payment of Rs.5,000 has been realised towards your Kotak Card. Thank you'));
  test('#154 card bill 12000', () => _accept('Payment of ₹12,000 towards your HDFC credit card is successful', 12000.0, true, null, flag: 'card-bill'));
  test('#155 not a bill or transfer 500', () => _accept('Paid Rs 500 for order using your credit card XX1234', 500.0, true, null, absent: const ['card-bill', 'transfer']));
  test('#156 not a bill or transfer 500', () => _accept('Paid Rs 500 to Swiggy using your credit card', 500.0, true, 'Swiggy', absent: const ['card-bill', 'transfer']));
  test('#157 card bill 8000', () => _accept('Bill payment of Rs 8,000 for your ICICI credit card was successful', 8000.0, true, null, flag: 'card-bill'));
  // Merchant receipts: the store name, not "Shopping".
  test('#158 receipt DMart', () => _accept('Thank you for shopping at DMart. Your bill amount Rs 1,250 paid via UPI.', 1250.0, true, 'DMart'));
  test('#159 card at Big Bazaar', () => _accept('Thank you for using your HDFC Debit Card XX1234 for Rs 540 at Big Bazaar on 12-09-26', 540.0, true, 'Big Bazaar'));
  test('#160 dining', () => _accept('Thanks for dining at Barbeque Nation. Rs 2,400 paid by card XX9911.', 2400.0, true, 'Barbeque Nation'));
  test('#161 choosing', () => _accept('Thank you for choosing Croma. Rs 15,999 debited from A/c XX1234.', 15999.0, true, 'Croma'));
  // Cashback / promo-code offers are ads, not money received.
  test('#162 MobiKwik offer', () => _reject('Make your credit card bill payment today and get up to Rs.200 cashback with MobiKwik! Use Code: FULLPAY. Pay instantly: ct3.io/chSjv -MobiKwik'));
  test('#163 MobiKwik assured', () => _reject('Get assured upto Rs.50 cashback on credit card bill payment today. Use code: SALARYDAYS. Valid for limited time. Pay Now: ct3.io/2b5X3x -MobiKwik'));
  test('#164 recharge offer', () => _reject('Flat Rs.100 off on your next recharge. Use code RECH100. Pay now: amzn.to/x'));
  test('#165 bill offer', () => _reject('Get upto Rs 75 cashback on electricity bill payment. Offer valid till 30 Sep. Pay now: phon.pe/x'));
  test('#166 real cashback kept', () => _accept('Rs 50 cashback credited to your Paytm wallet for your recent payment.', 50.0, false, null));
  test('#167 validity is not a promo', () => _accept('Paid Rs.299 to Jio. Validity up to 28 days.', 299.0, true, 'Jio'));
  test('#168 bare link flagged', () => _accept('Dear Customer, Rs 1,200 debited from A/c XX1234 at AMAZON. Not you? visit hdfcbank.com/fraud', 1200.0, true, 'Amazon', flag: 'link'));
  // Successful mobile / DTH recharges.
  test('#169 recharge, no operator', () => _accept('Recharge of Rs 299 for 98XXXXXX12 successful via PhonePe. Plan valid till 12 Oct 2026.', 299.0, true, 'Mobile recharge'));
  test('#170 Jio recharged', () => _accept('Your Jio number 98XXXXXX12 has been successfully recharged with Rs 239. Validity 28 days.', 239.0, true, 'Jio'));
  test('#171 Airtel recharge', () => _accept('Recharge of ₹199 for Airtel 9876XXXX21 is successful. Txn ID 1234567890', 199.0, true, 'Airtel'));
  test('#172 recharge ad', () => _reject('Recharge now and get Rs 50 cashback. Recharge done in seconds!'));
  test('#173 failed recharge', () => _reject('Recharge failed for Rs 299. Amount will be refunded.'));
}
