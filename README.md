# Vyaya

*Vyaya* - Sanskrit for "expenditure", which is mainly what this app keeps an eye on.

Vyaya is a personal expense tracker for Android, built with Flutter. I made it because every expense app I tried either wanted my bank login, pushed a subscription, or took five taps to log a ₹20 chai. Vyaya is the opposite: everything stays on your phone, logging is quick, and if you pay with PhonePe or any other UPI it will automaticaly log your payments for you.

It's built around a simple idea: **you log the money that comes in, you log the money that goes out, and the app tells you what's left.**

---

## What it does

### Logging money
- **Add an expense by hand:** payee, amount, purpose, category, date, account and notes. Tap the **+** button on the home screen.
- **Auto-detect payments:** reads bank SMS and payment-app notifications (GPay, PhonePe, Paytm…) on your phone and turns them into entries for you. See [Auto-detect](#auto-detect-payments) below.
- **Log income:** pocket money, salary, refunds, anything coming in. Income is shown in green throughout the app.
- **Edit or delete anything:** tap an entry to edit it. Every change shows a small round **undo** bubble for 5 seconds; tap it to see what changed and undo it (one at a time, or all at once).
- **Select several at once:** long-press an entry, tap more, then use the nav bar to **Edit** (change category, account or date for all of them) or **Delete**. Both can be undone.
- **Amounts in Indian format:** rupees only, grouped as thousands, lakhs and crores (₹1,23,45,678). Charts use K / L / Cr.

### Knowing where you stand
- **The top card on the home screen** shows what you've spent this month, your income, and how much is **left** (income − spent), with a progress bar.
- **Browse past months:** use the ◀ ▶ arrows next to "This Month's Spending". The card, category summary and activity list all switch to that month.
- **Category summary:** a scrollable row showing where the month's money went.
- **Credit card view:** switch "Recent Activity" to "Credit Card" to see only card spending for the month.
- **Analytics:** day, week, month or year views with a category pie chart, spending trend, month-by-month comparison and a few plain-English insights. For example: "Food is your highest spending category this month".

### Things that happen on their own
- **Recurring entries:** set up things that repeat every month once, like pocket money on the 1st or Spotify on the 5th, and Vyaya logs them automatically when their day comes. You can pause, edit or delete them anytime. If you don't open the app for a while, it catches up with anything you missed.
- **Month-end leftover:** when a month ends with money left over, Vyaya does one of two things (Settings → Optional features):
  - **Save it** (default): logs it as an expense in a **"Saved"** category on the month's last day, so it shows how much you actually saved.
  - **Carry it over:** adds it as income on the 1st of the next month ("Carried over from …").

  Either entry updates itself if you later add or edit something in that month, and stays deleted if you delete it. Its date is fixed, and a month's own carried-over income never counts towards that month.
- **Notifications:** choose exactly which ones you get in **Settings → Notifications**: spending more than your income, a category going over its limit, early warnings at 80%, large payments, "new payment detected", bill reminders, a weekly summary, a monthly recap and a daily reminder (skipped on days you've already logged something). One switch turns them all off, and there's a test button.

### Money with friends
- **Lent & Borrowed:** keep track of "I paid for dinner, Rahul owes me ₹300" or "Borrowed ₹500 from Priya". You see a running balance per person, "You'll get" and "You owe" totals, and you tick entries off as they're settled. None of it counts towards your spending.

### Categories
- It comes with 8 default categories: Food, Transport, Shopping, Entertainment, Health, Bills, Education and Other. You can add your own with an emoji and a colour.
- **Every category is deletable, defaults included.** Long-press to select several at once.
- If a category you're deleting already has expenses in it, Vyaya warns you and lets you **move those expenses to another category** first, or keep them as they are. Any you keep then show up under "Other".
- **Optional per-category monthly limits,** with a warning when you cross one.

### Your data
- **Everything is stored on your phone.** There's no account, no server and no sync. Nothing leaves your device unless you share it.
- **Backup & Restore:** exports a single JSON file with everything (expenses, income, categories, accounts, recurring entries, lent/borrowed, detected payments and your "always ignore" rules) that you can save to Drive or wherever you like. Restoring asks first, checks the file isn't damaged before touching anything, and puts your old data back if it fails.
- **Delete data by date:** Settings → Delete data by date removes expenses, income and/or detected payments in a period you pick, with an extra confirmation.
- **If stored data can't be opened at start-up,** the app shows a screen with *Try again*, *Save a copy of my data* and *Restore backup* instead of a blank spinner. A single unreadable entry is skipped (not deleted), and month-end entries are left alone until it's fixed.
- **Export to CSV:** a spreadsheet of all expenses and income, handy for Excel or Google Sheets. It's export-only and can't be imported back.
- **Automatic safety copy:** the app also keeps a copy of your data in its own storage, used to recover if the app's settings storage gets wiped. It stays on the phone only (Android's cloud backup is turned off, since Vyaya is fully offline), so **uninstalling the app or clearing its storage deletes it too**. Before reinstalling or changing phones, use Settings → Back up and keep the file somewhere safe.

---

## Auto-detect payments

Turn it on in **Settings → Auto-detect Payments** by giving Vyaya notification access, SMS permission, or both. Everything is read on the phone; nothing is uploaded.

- **Review list (Detected payments):** found payments wait here. Swipe or tap to add or dismiss, pick the category, or use **Add all** / **Dismiss all**. **Add automatically** skips the review for confident live payments (never for imports, transfers, card-bill payments, refunds or messages with links).
- **One payment, one entry:** the app alert and the bank SMS for the same payment are merged, repeats of the same message are folded in, and two real payments of the same amount stay separate (different reference numbers, payees or card digits). A payment you already typed in by hand is marked "already logged" instead (one manual entry matches only one payment).
- **Always ignore:** mute a payee or a sender so it's never shown again; rules can be removed anytime.
- **Import past bank SMS:** pick a start date; everything since then is read and waits for review.
- **Nothing missed:** if Android stopped the app (battery savers), SMS that arrived meanwhile are read from the inbox the next time you open it (up to 30 days back). Payments you removed don't come back this way, only through a manual import.
- **Remove:** clears items from the lists (the expenses they created stay).

### How it decides what to log

Bank SMS in India are messy: every bank writes them differently, half of them end with an ad, and scammers copy the exact format of real alerts. So before anything gets logged, each message goes through a few checks, all on your phone:

1. **Throw out the noise.** OTPs (only when there's an actual code in the message), ads and offers ("FREE", "bonus", "cash points", "T&C apply", stock tips), payment requests, failed payments and reminders for bills that aren't paid yet ("due on", "will be auto-debited", "due hai", "kal tak", "will be disconnected").
2. **Catch scams.** Disguised spelling ("Y0UR L0AN", "Rs 56,6OO"), job offers ("daily salary", wa.me links), fake "credited by mistake, please refund", fake reward/refund links, anything asking you to share your PIN or OTP, "call this mobile number to block", and dodgy web addresses (.top, .online, tinyurl…). Real banks give 1800 toll-free numbers, scammers give mobile numbers, so a message with a toll-free number isn't flagged just for having a number in it.
3. **Read the payment.** The amount (skipping balances and card limits), whether money went out or came in, the payee, the last digits of the account or card, the reference number and the date. It understands formats like `Dr. INR 70`, `Received! INR 2,000`, `Rs.1100credited`, "X has received Rs 21 from your A/c" (that's money *you* sent) and the fancy styled letters some banks use.
4. **Don't count the same money twice.** A credit card company saying "we received your payment" isn't logged, because the card spending itself is already there.
5. **Suggest a category** from what you picked for that payee before, or from a keyword list (Swiggy → Food, Big Bazaar / kirana / groceries → Food, Uber → Transport, and so on).

It works in English, Hinglish and romanised regional messages (Hindi, Marathi, Tamil, Telugu, Bengali and others).

### How it's been tested

The parser has been checked against **30,000+ messages** so far, and every mistake found was fixed and turned into a test:

| What | Messages | Result |
|---|---:|---|
| Unit tests (`test/transaction_parser_test.dart`) | 231 | All passing |
| Hand-collected real bank / UPI message formats (development + holdout set) | 126 | All correct |
| Sample messages from two open-source Indian SMS parser projects | 365 | 356 handled correctly; the other 9 are edge cases handled differently on purpose (e.g. deposit interest is logged as income) |
| Indian spam & ham SMS dataset | 2,267 | 0 spam logged |
| Scam & ham SMS in 14 Indian languages | 14,000 | 0 scams logged, 105 real transactions logged |
| Audited scam / safe SMS set (English + regional) | 1,580 | 0 scams logged, 70 real transactions logged |
| Indian test suite (spam, scam, ham) | 1,400 | 0 spam/scams logged, 7 real transactions logged |
| Bank statement narrations (category check) | 11,000 | 0 wrong categories; about 21% are "Investment", which Vyaya has no category for |

**About 19,250 spam, scam and genuine SMS: not a single spam or scam got logged, while the real transactions in them still did.**

New scam wordings and new bank formats will keep turning up, so it'll never be perfect. If a message gets logged when it shouldn't (or gets missed), open an issue with the message, with your personal details removed.

You can run the same checks yourself: put the CSVs in `tool/parser_eval/data/` and run `dart run tool/parser_eval.dart`. There's a short guide in `tool/parser_eval/README.md`.

---

## Finding your way around

On first launch a short intro (3 pages, skippable) explains the offline storage, lets you turn on auto-detect, and shows the main gestures. Here's the full cheat sheet:

| Where | Do this | What happens |
|---|---|---|
| Nav bar | Tap **Home** / **Categories** | Switch tabs (you can also swipe sideways on the bar) |
| Nav bar | Tap **Search** | Search through your expenses |
| Nav bar | **Swipe up** (or long-press Search) | Opens **Analytics, Recurring, Lent & Borrowed, Settings** |
| Home | Tap **+** | Add expense, add income |
| Home | ◀ ▶ next to the month | Look at previous months |
| Home | Tap "Recent Activity" | Switch to the credit card view |
| Any entry | Tap / ⋮ menu / long-press | Edit / delete / select several |
| While selecting | Nav bar **Edit** / **Delete** | Change category, account or date for all / delete all |
| Undo bubble | Tap it | Shows what changed, with UNDO (and "Undo all" for several) |
| Home | Tap the detected-payments banner | Review auto-detected payments |
| Settings → Categories | Long-press a category | Select several to delete |

The little line on top of the nav bar is there to remind you that it swipes up.

---
<!-- 
## Getting the PhonePe scanner to work well

The scanner only reads the part of the screenshot that holds the payee name and the amount, so it needs to know where that is on *your* phone's screen:

1. Open PhonePe, go to **History**, open any transaction and take a screenshot.
2. In Vyaya, open **Settings → PhonePe Scanning → Crop Calibration** and adjust the crop until only the name and amount are inside it.
3. From then on, share any PhonePe transaction screenshot to Vyaya and it will fill in the details for you.

It's not perfect. In my testing it gets both fields right roughly 7 times out of 10, and it always lets you check and fix things before saving. It's built for PhonePe's layout, so screenshots from other apps won't parse properly yet.

--- -->

## Automating with MacroDroid / Tasker

Vyaya accepts an Android intent, so automation apps can log expenses for you:

- **Action:** `com.vyaya.ADD_EXPENSE`
- **Extras:** `amount`, `payee` (or `title`), `category`, `notes`, and `auto`
- By default, the add-expense screen opens pre-filled for you to confirm. With `auto=true` it saves straight away, but only after you turn on **Settings → Optional features → Automation apps can save directly** (any installed app can send this intent, so it's off by default). Expenses added this way don't change the remembered category for a payee.

For example, a MacroDroid macro that triggers on a UPI "Paid ₹…" notification can pull out the amount and send it straight to Vyaya.

---

## Building it yourself

**You'll need:**
- Flutter (Dart SDK ^3.9)
- Android SDK
- **JDK 21.** Newer versions of Android Studio bundle Java 25, which this project's Gradle version doesn't support yet. If your build fails with *"Unsupported class file major version 69"*, install JDK 21 and point Flutter at it:

  ```bash
  flutter config --jdk-dir="C:\Program Files\Eclipse Adoptium\jdk-21.x.x-hotspot"
  ```

**Build:**
```bash
flutter pub get
flutter build apk --release
```

**Test:**
```bash
flutter test
```
Tests cover the SMS parser (231 cases), duplicate detection (`capture_dedupe_test`), money logic such as savings, carry-over, recurring, lent/borrowed and batch delete (`expense_provider_test`), storage (`local_store_test`), Indian number formatting (`money_format_test`), payee categories, settings, smart notifications and the undo bar.

The APK ends up in `build/app/outputs/flutter-apk/app-release.apk`.

**Build setup:** Gradle 8.14.3, Android Gradle Plugin 8.11.1, Kotlin 2.2.20. `receive_sharing_intent` is pinned to 1.8.1, because 1.9.0 needs AGP 9 and compile SDK 37.

**Signing:** release builds read **`android/app/key.properties`** (the build looks in `android/app/`, not `android/`; `storeFile` is relative to `android/app/` too). See `key.properties.example`. If the file is missing, the build silently falls back to the **debug key**, and an APK signed that way can't be updated by one signed with your real key, so check it's there before publishing.

---

## Under the hood

- **Flutter + Provider** for the UI and app state
- **SharedPreferences** for storage (`LocalStore`), with writes batched every 300 ms. App data keys start with `ls_` (these go into backups); `device_` keys belong to this phone only.
- **`packages/vyaya_capture`**, a small built-in plugin (Kotlin) that reads notifications and SMS into a queue the app drains, so nothing is lost while the app is closed
- **intl** for Indian number formatting
<!-- - **Google ML Kit** text recognition for OCR, with image pre-processing (cropping and clean-up) and text normalisation before the fields are pulled out -->
- **flutter_local_notifications** for alerts
- **receive_sharing_intent** for the share-to-app flow
- **Hand-drawn charts** made with `CustomPainter`, with no charting library

```
lib/
├── models/      Expense, Income, categories, recurring entries, lent/borrowed
├── providers/   ExpenseProvider (the hub) + managers for expenses, income, budgets…
├── services/    storage, payment detection (capture/), backup/export, notifications, intents, OCR (unused)
├── screens/     home, categories, analytics, settings, recurring, lent & borrowed…
└── widgets/     cards, glass nav bar, category summary, charts
```

---

## Known limitations

<!-- - Only PhonePe screenshots can be scanned automatically for now. -->
- Automatic entries (recurring and month-end savings) are created when you open or return to the app, not in the background. If you don't open it on the 1st, they appear the next time you do, with the correct dates.
- Auto-detect only knows Indian bank / UPI message formats in English and romanised Indian languages (Hinglish etc.); messages in native scripts aren't read.
- Distributing on the Play Store would need Google's approval for the SMS permission; GitHub / F-Droid builds don't.
- It's Android only, and India only (rupees).

<!-- ## What's next

- **Auto-logging from payment notifications:** reading UPI "Paid ₹X to Y" notifications directly, which could replace screenshot scanning altogether
- Moving the build to Gradle 9 / AGP 9 / Kotlin 2.3 before Flutter drops support for the current versions -->
---

## Feedback

This is a personal project that I actually use every day, so it's actively maintained, but it'll have rough edges. If something breaks or you have an idea, open an issue. Bug reports are genuinely appreciated.
