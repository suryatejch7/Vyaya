# Vyaya

*Vyaya* (व्यय) is Sanskrit for "expenditure", which is exactly what this app keeps an eye on.

Vyaya is a personal expense tracker for Android, built with Flutter. I made it because every expense app I tried either wanted my bank login, pushed a subscription, or took five taps to log a ₹20 chai. Vyaya is the opposite: everything stays on your phone, logging is quick, and if you pay with PhonePe you can often skip typing entirely by sharing the payment screenshot.

It's built around a simple idea: **you log the money that comes in, you log the money that goes out, and the app tells you what's left.**

---

## What it does

### Logging money
- **Add an expense by hand:** payee, amount, purpose, category, date, account and notes. Tap the **+** button on the home screen.
- **Scan a PhonePe screenshot:** open a transaction in PhonePe's history, take a screenshot and either **share it to Vyaya** or pick it from the scanner. The app crops it, runs on-device OCR (Google ML Kit) and fills in the payee and amount for you to confirm.
- **Log income:** pocket money, salary, refunds, anything coming in. Income is shown in green throughout the app.
- **Edit or delete anything:** tap an entry to edit it. Deleting shows an **UNDO** button for a few seconds, in case your thumb slipped.
- **Delete several at once:** long-press an entry to start selecting, tap more, then delete from the nav bar.

### Auto-detecting payments
You can have payments logged without typing anything or taking a screenshot. Vyaya can read two things:
- **Payment app notifications** from PhonePe, Google Pay, Paytm, BHIM, CRED, Amazon Pay, Navi, MobiKwik and Freecharge ("₹120 paid to Swiggy").
- **Bank SMS**, meaning the debit and credit alerts your bank already sends. It can also import the last 30 days in one go.

Each message is read on your phone and turned into amount, payee, date and account. It also gets a category (Swiggy → Food, Uber → Transport, and so on), and when you correct a payee's category once, it remembers.

- **Ask me** (default): new payments land in a review list with Add / Edit / Dismiss, and a banner on the home screen tells you when there's something to look at.
- **Add automatically**: payments it's confident about go straight in. Anything unclear still waits for you. That includes no payee, a transfer between your own accounts, a reversal, a message with a link, or imported history.

It's careful about the common traps:
- **No double logging.** If PhonePe *and* your bank both tell you about the same payment, it's matched using the UPI reference, the time and the payee, and logged once. Anything you already added by hand is spotted too.
- **Ignores noise:** OTPs, loan and cashback promos, failed or declined payments, autopay reminders and money requests.
- **Ignores scams:** fake "₹25,000 credited, claim here" texts, anything from a personal phone number, lottery and KYC messages.
- **Keeps working when the app is closed.** Messages are queued on the phone and picked up the next time you open Vyaya. You get a small "New payment detected" notification in the meantime.

Set it up in **Settings → Auto-detect Payments**. If Android greys out the Notification access switch (it does that for apps installed outside the Play Store), open **App info → ⋮ → Allow restricted settings** first. On OnePlus and Xiaomi phones, also tap **Keep detection running** so the battery saver doesn't stop it.

### Knowing where you stand
- **The top card on the home screen** shows what you've spent this month, your income, and how much is **left** (income − spent), with a progress bar. If you spend more than you've brought in, it turns red and tells you by how much.
- **Browse past months:** use the ◀ ▶ arrows next to "This Month's Spending". The card, category summary and activity list all switch to that month.
- **Category summary:** a scrollable row showing where the month's money went.
- **Credit card view:** switch "Recent Activity" to "Credit Card" to see only card spending for the month.
- **Analytics:** day, week, month or year views with a category pie chart, spending trend, month-by-month comparison and a few plain-English insights. For example: "Food is your highest spending category this month".

### Things that happen on their own
- **Recurring entries:** set up things that repeat every month once, like pocket money on the 1st or Spotify on the 5th, and Vyaya logs them automatically when their day comes. You can pause, edit or delete them anytime. If you don't open the app for a while, it catches up with anything you missed.
- **Month-end savings:** when a month ends with money left over, that leftover is logged into a **"Saved"** category on the last day of the month. The category is created for you if it doesn't exist. It also keeps itself up to date: log a forgotten expense from last month and last month's Saved amount adjusts on its own. Over time, this shows you how much you've actually saved each month.
- **Notifications:** you get a heads-up when your spending passes your income for the month, or when a category goes over the limit you set for it. They can be turned off in Settings.

### Money with friends
- **Lent & Borrowed:** keep track of "I paid for dinner, Rahul owes me ₹300" or "Borrowed ₹500 from Priya". You see a running balance per person, "You'll get" and "You owe" totals, and you tick entries off as they're settled. None of it counts towards your spending.

### Categories
- It comes with 8 default categories: Food, Transport, Shopping, Entertainment, Health, Bills, Education and Other. You can add your own with an emoji and a colour.
- **Every category is deletable, defaults included.** Long-press to select several at once.
- If a category you're deleting already has expenses in it, Vyaya warns you and lets you **move those expenses to another category** first, or keep them as they are. Any you keep then show up under "Other".
- **Optional per-category monthly limits,** with a warning when you cross one.

### Your data
- **Everything is stored on your phone.** There's no account, no server and no sync. SMS and notifications are read on the device, and nothing leaves it unless you share it.
- **Backup & Restore:** exports a single JSON file with everything (expenses, income, categories, accounts, recurring entries, lent/borrowed) that you can save to Drive or wherever you like, and restore later.
- **Export to CSV:** a spreadsheet of all expenses and income, handy for Excel or Google Sheets. It's export-only and can't be imported back.
- **Automatic safety copy:** the app also keeps a copy of your data that's included in Android's own backup, so a reinstall can bring your data back even if you forgot to make a backup yourself.

---

## Finding your way around

Some features are hidden behind gestures, so here's the cheat sheet:

| Where | Do this | What happens |
|---|---|---|
| Nav bar | Tap **Home** / **Categories** | Switch tabs (you can also swipe sideways on the bar) |
| Nav bar | Tap **Search** | Search through your expenses |
| Nav bar | **Swipe up** (or long-press Search) | Opens **Analytics, Recurring, Lent & Borrowed, Settings** |
| Home | Tap **+** | Add expense, add income, or scan a screenshot |
| Home | Tap the "payments detected" banner | Review auto-detected payments |
| Home | ◀ ▶ next to the month | Look at previous months |
| Home | Tap "Recent Activity" | Switch to the credit card view |
| Any entry | Tap / ⋮ menu / long-press | Edit / delete (with undo) / select several |
| Settings → Categories | Long-press a category | Select several to delete |
| Settings → PhonePe Scanning | Crop Calibration | Set up screenshot scanning for your phone |

The little line on top of the nav bar is there to remind you that it swipes up.

---

## Getting the PhonePe scanner to work well

The scanner only reads the part of the screenshot that holds the payee name and the amount, so it needs to know where that is on *your* phone's screen:

1. Open PhonePe, go to **History**, open any transaction and take a screenshot.
2. In Vyaya, open **Settings → PhonePe Scanning → Crop Calibration** and adjust the crop until only the name and amount are inside it.
3. From then on, share any PhonePe transaction screenshot to Vyaya and it will fill in the details for you.

It's not perfect. In my testing it gets both fields right roughly 7 times out of 10, and it always lets you check and fix things before saving. It's built for PhonePe's layout, so screenshots from other apps won't parse properly yet.

---

## Automating with MacroDroid / Tasker

Vyaya accepts an Android intent, so automation apps can log expenses for you:

- **Action:** `com.vyaya.ADD_EXPENSE`
- **Extras:** `amount`, `payee` (or `title`), `category`, `notes`, and `auto`
- By default, the add-expense screen opens pre-filled for you to confirm. With `auto=true` it saves straight away.

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

**Tests** (the payment parser is checked against 126 real-format bank and UPI messages, including scams):
```bash
flutter test test/transaction_parser_test.dart
```

The APK ends up in `build/app/outputs/flutter-apk/app-release.apk`.

**Build setup:** Gradle 8.14.3, Android Gradle Plugin 8.11.1, Kotlin 2.2.20. `receive_sharing_intent` is pinned to 1.8.1, because 1.9.0 needs AGP 9 and compile SDK 37.

**Signing:** release builds use `android/key.properties` if it exists (see `key.properties.example`), and fall back to the debug key if it doesn't.

---

## Under the hood

- **Flutter + Provider** for the UI and app state
- **SharedPreferences** for storage. It's all local; the class is still called `ExpenseSupabaseService` from back when the app used Supabase.
- **Google ML Kit** text recognition for OCR, with image pre-processing (cropping and clean-up) and text normalisation before the fields are pulled out
- **flutter_local_notifications** for alerts
- **receive_sharing_intent** for the share-to-app flow
- **Hand-drawn charts** made with `CustomPainter`, with no charting library

```
packages/
└── vyaya_capture/  native Android part of auto-detection (notification
                    listener, SMS receiver, on-device queue)
lib/
├── models/      Expense, Income, categories, recurring entries, lent/borrowed
├── providers/   ExpenseProvider (the hub) + managers for expenses, income, budgets…
├── services/    storage, OCR pipeline, backup/export, notifications, intents,
│                capture/ (SMS & notification parser, categoriser)
├── screens/     home, categories, analytics, settings, recurring, lent & borrowed…
└── widgets/     cards, glass nav bar, category summary, charts
```

---

## Known limitations

- Screenshot scanning only understands PhonePe's layout. For other apps, use auto-detection.
- Auto-detection understands the common Indian bank and UPI formats. A message it can't fully read still shows up for review with the original text, rather than being dropped.
- Automatic entries (recurring and month-end savings) are created when you open or return to the app, not in the background. If you don't open it on the 1st, they appear the next time you do, with the correct dates.
- The "Saved from …" entries are managed by the app. If you delete or edit one by hand, it goes back to the correct amount, so change that month's real entries instead.
- It's Android only, and rupees only.

## What's next

- Moving the build to Gradle 9 / AGP 9 / Kotlin 2.3 before Flutter drops support for the current versions

---

## Feedback

This is a personal project that I actually use every day, so it's actively maintained, but it'll have rough edges. If something breaks or you have an idea, open an issue. Bug reports are genuinely appreciated.
