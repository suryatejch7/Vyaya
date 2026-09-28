# Vyaya

*Vyaya* (व्यय) is Sanskrit for "expenditure", which is exactly what this app keeps an eye on.

Vyaya is a personal expense tracker for Android, built with Flutter. I made it because every expense app I tried either wanted my bank login, pushed a subscription, or took five taps to log a ₹20 chai. Vyaya is the opposite: everything stays on your phone (the app has no internet permission at all), logging is quick, and payments can be picked up automatically from your bank SMS and payment-app notifications.

It's built around a simple idea: **you log the money that comes in, you log the money that goes out, and the app tells you what's left.**

**Download:** the latest APK is on the [GitHub Releases](https://github.com/suryatejch7/Vyaya/releases) page. The same link sits at the bottom of the app's Settings screen, next to the version number (current version: **3.1.0**).

---

## What it does

### Logging money
- **Add an expense:** tap the **+** button on the home screen. The screen starts with a big amount field, then Details (payee and purpose), Category, Date & Account, and Notes. Notes is where a detected payment's original bank SMS text is kept.
- **Log income:** pocket money, salary, refunds, anything coming in. It has the same layout with a green amount field, and income is shown in green throughout the app. Income can be saved without a bank account if you haven't added one.
- **Edit or delete anything:** tap an entry to edit it. Deleting shows an **UNDO** pill for a few seconds (swipe it down to dismiss it), in case your thumb slipped.
- **Delete several at once:** long-press an entry to start selecting, tap more, then delete from the nav bar.

### Auto-detecting payments
You can have payments logged without typing anything. Vyaya can read two things:
- **Payment app notifications** from PhonePe, Google Pay, Paytm, BHIM, CRED, Amazon Pay, Navi, MobiKwik and Freecharge ("₹120 paid to Swiggy").
- **Bank SMS**, meaning the debit and credit alerts your bank already sends, including mobile/DTH recharge confirmations. It can also import past messages (last 7 days, 30 days, 3 months or from a date you pick).

Each message is read on your phone and turned into amount, payee, date and account. It also gets a category (Swiggy → Food, Uber → Transport, and so on), and when you correct a payee's category once (on the review screen or later by editing the expense), it remembers. Payments are matched to your bank accounts too; a missing bank is created for you, and you can rename accounts (for example add the last 4 digits) in **Settings → Bank Accounts**.

- **Ask me** (default): new payments land in a review list with Add / Edit / Dismiss, and a banner on the home screen tells you when there's something to look at.
- **Reviewing a long list:** search, filter by date or paid/received, swipe right to add or left to dismiss, long-press to select several, "Always ignore" a payee or sender from a card's ⋮ menu, and remove payments from the list entirely (for example after importing more than you wanted). Dismissed and ignored items have their own history pages, so nothing is lost. Everything can be undone.
- **Add automatically**: payments it's confident about go straight in. Anything unclear still waits for you. That includes no payee, a transfer between your own accounts, a credit card bill payment, a reversal, a message with a link, or imported history. **Add all** on the review list also leaves transfers and card bill payments for you to decide.

It's careful about the common traps:
- **No double logging.** If PhonePe *and* your bank both tell you about the same payment, it's matched using the UPI reference, the time and the payee, and logged once. Anything you already added by hand is spotted too.
- **No double counting card bills.** Your credit card purchases are already logged, so paying the bill isn't counted as spending again. The card's "payment received" message is ignored, and the bank's "debited towards CC payment" (or "paid to CRED") waits for review instead of going straight in.
- **Ignores noise:** OTPs, loan and cashback/promo-code offers, recharge ads, failed or declined payments, autopay reminders and money requests.
- **Ignores scams:** fake "₹25,000 credited, claim here" texts, anything from a personal phone number, lottery and KYC messages.
- **Keeps working when the app is closed.** Messages are queued on the phone and picked up the next time you open Vyaya. You get a small "New payment detected" notification in the meantime.

Set it up in **Settings → Auto-detect Payments**. If Android greys out the Notification access switch (it does that for apps installed outside the Play Store), open **App info → ⋮ → Allow restricted settings** first. On OnePlus and Xiaomi phones, also tap **Keep detection running** so the battery saver doesn't stop it.

### Knowing where you stand
- **The top card on the home screen** shows what you've spent this month, your income, and how much is **left** (income − spent), with a progress bar. If you spend more than you've brought in, it turns red and tells you by how much.
- **Browse past months:** use the ◀ ▶ arrows next to "This Month's Spending". The card, category summary and activity list all switch to that month. For a finished month, the card shows your real spending and what happened to the leftover ("💰 Saved ₹3,000" or "Carried over"), and you can tap it to open Savings.
- **Category summary:** a scrollable row showing where the month's money went. Tap a category to see its entries for the month you're viewing.
- **Credit card view:** switch "Recent Activity" to "Credit Card" to see only card spending for the month.
- **Categories tab:** every category with its total, share and item count. The filter button (bottom right) picks the period (this week, this month, this year, all time or a custom range) and the account. Weeks run **Sunday to Saturday** by default; Monday is an option.
- **Savings:** a separate page (from the Savings card on the Categories tab, from Home, or from Settings). It shows your total saved, this year and your monthly average, how much is left this month so far, and a month-by-month history with income, spending and the share you saved. Swipe a month away to remove its entry (with undo).
- **Analytics:** spending only (month-end "Saved" entries aren't counted as spending). Day, week, month or year views with a category pie chart, spending trend, comparison with earlier periods and a few plain-English insights. For example: "Food is your highest spending category this month".
- **Search:** search by payee, amount, category or note. The filter button next to the search bar sorts results (newest, oldest, highest or lowest amount) and filters by expenses/income, account, one or more categories, date (this week, this month, last 30 days, this year or a custom range) and amount range. You can use the filters without typing anything, to browse for example everything paid from SBI this month. Each active filter shows as a chip you can remove, and a line above the results shows the count and the total spent and received.

### Things that happen on their own
- **Recurring entries:** set up things that repeat weekly, monthly or yearly once, like pocket money on the 1st, a Sunday grocery run or a yearly insurance premium, and Vyaya logs them automatically when their day comes. You can pause, edit or delete them anytime. If you don't open the app for a while, it catches up with anything you missed.
- **Month-end leftover:** when a month ends with money left over, Vyaya does one of two things (you choose in **Settings → Optional features → Month-end savings**):
  - **On (default):** the leftover is logged into a **"Saved"** entry on the last day of the month, and the "Saved" category is created if needed.
  - **Off:** the leftover is carried into the next month as income on the 1st ("Carried over from September").

  Either way it keeps itself up to date: log a forgotten expense from last month and last month's amount adjusts on its own. Switching applies from the current month onward, and earlier months stay as they were. Delete a month's entry if you don't want one, and that month stays without it.
- **Spending alerts:** you get a heads-up when your spending passes your income for the month, or when a category goes over the limit you set for it. They can be turned off in Settings.

### Optional features
**Settings → Optional features** has extras you can turn on if they suit you. All of them are off by default except month-end savings.

| Group | Feature | What it does |
|---|---|---|
| Money | Month-end savings | Leftover goes into "Saved" (on) or carries into next month as income (off) |
| Money | Week starts on | Sunday (default) or Monday, for "this week" everywhere |
| Home | Hide totals on Home | Masks spent, income, left, the category amounts and the card total as ₹••••. Tap the amount to peek |
| Home | Spending pace on Home | "Today ₹X" plus how much you can spend per day for the rest of the month |
| Home | Quick actions | Choose which two of Detected Payments, Lent & Borrowed and Recurring go in the swipe-up menu. The third is listed in Settings |
| Adding entries | Open keyboard on Add | Add Expense / Income start with the amount field focused |
| Adding entries | Remember last category | Add Expense starts with the category and account you used last |
| Adding entries | Late night counts as yesterday | Entries added before 4 AM are dated the previous day |
| Alerts & goals | Monthly savings goal | A target for what's left each month, with progress on the Savings page and a ✓ on months that hit it |
| Alerts & goals | Large payment alert | A notification for any single payment (logged today) at or above your amount. Handy for spotting fraud |
| Privacy | App lock | A 4-digit PIN when the app opens and after 30 seconds away (see below) |
| Notifications | Weekly summary | Sundays at 1 PM: last week's total, number of payments, top category and the change from the week before |
| Notifications | Monthly recap | On the 1st at 10 AM: last month's spending, income and what was saved |
| Notifications | Bill reminders | The day before a recurring expense is due, at 9 AM |
| Notifications | Early warnings | An alert at 80% of your month's income or of a category limit, before you go over |
| Notifications | Daily reminder | A daily nudge at a time you pick to log the day's spending |

A few things to know:
- **App lock:** the PIN is stored only as a salted SHA-256 hash. When you set it, you're shown a one-time 8-character **recovery code**; write it down. Because Vyaya is offline, that code is the only way back in if you forget the PIN ("Forgot?" on the lock screen).
- **Weekly summary and monthly recap:** the numbers are filled in when the notification is scheduled, which happens whenever your data changes, so they're as of the last time you opened the app. If you don't open Vyaya for a while, a plain reminder still arrives. Scheduled notifications can be a few minutes late, because Android batches them to save battery.

### Money with friends
- **Lent & Borrowed:** keep track of "I paid for dinner, Rahul owes me ₹300" or "Borrowed ₹500 from Priya". You see a running balance per person, "You'll get" and "You owe" totals, and you tick entries off as they're settled. When you settle one, you can also log the money that changed hands (income when they pay you back, an expense when you pay them); reopening it removes that entry again. While a settled entry has a recorded payment, it can't be switched between lent and borrowed. Open entries don't count towards your spending.

### Categories
- It comes with 8 default categories: Food, Transport, Shopping, Entertainment, Health, Bills, Education and Other. You can add your own: pick from grouped icons (or type any emoji) and one of 16 colours.
- **Tap a category to edit it:** name, icon, colour and monthly limit. Renaming moves every expense, recurring entry and detected payment to the new name. "Other" and "Saved" keep their names because the app relies on them.
- **Delete any category except "Saved"**, defaults included (it holds your month-end savings). Long-press to select several at once.
- If a category you're deleting is still in use (expenses or recurring entries), Vyaya warns you and lets you **move them to another category** first, or keep them as they are. Moving also updates detected payments and learned payee rules. Anything you keep then shows up under "Other".
- **Optional per-category monthly limits,** with a warning when you cross one (and at 80% if Early warnings is on).
- "Saved" is filled in by the app, so it isn't offered when you pick a category for a new expense.

### Your data
- **Completely offline.** The app has no internet permission, so it can't send anything anywhere. There's no account, no server and no sync. SMS and notifications are read on the device. The only link out is "GitHub Releases" in Settings, which opens your browser.
- **No Google Drive backup.** Android's automatic backup is turned off (phone-to-phone copy too), so your data only leaves the phone when you export or back it up yourself.
- **Backup & Restore:** exports a single JSON file with everything (expenses, income, categories, accounts, recurring entries, lent/borrowed, detected payments and your optional-feature settings) that you can save to Drive or wherever you like, and restore later.
- **Export to CSV:** a spreadsheet of all expenses and income with date, time, account and type, handy for Excel or Google Sheets. The totals leave out the app's own month-end entries (Saved and carried over), which are listed separately. It's export-only and can't be imported back.
- **Local safety copy:** the app also keeps a copy of your data inside its own storage and restores from it if its main data ever gets wiped. It's deleted with the app, so use Back up before uninstalling or switching phones.

---

## Finding your way around

Some features are hidden behind gestures, so here's the cheat sheet:

| Where | Do this | What happens |
|---|---|---|
| Nav bar | Tap **Home** / **Categories** | Switch tabs (you can also swipe sideways on the bar) |
| Nav bar | Tap **Search** | Search, sort and filter your expenses and income |
| Nav bar | **Swipe up** (or long-press Search) | Opens **Analytics**, two shortcuts you choose (default: Detected Payments and Lent & Borrowed) and **Settings** |
| Home | Tap **+** (bottom right, next to the nav bar) | Add expense or add income. Tap outside or press back to close it |
| Home | Tap the "payments detected" banner | Review auto-detected payments |
| Home | ◀ ▶ next to the month | Look at previous months |
| Home | Tap "💰 Saved ₹…" on a past month | Open Savings |
| Home | Tap "Recent Activity" | Switch to the credit card view |
| Categories | Tap the **filter** button (bottom right) | Change the period or account |
| Categories | Tap the **Savings** card | Open Savings |
| Search | Tap the **filter** button next to the search bar | Sort and filter results |
| Any entry | Tap / ⋮ menu / long-press | Edit / delete (with undo) / select several |
| Settings → Categories | Tap a category | Edit its name, icon, colour and limit |
| Settings → Categories | Long-press a category | Select several to delete |
| Settings | **Optional features** | All the extras listed above |

The little line on top of the nav bar is there to remind you that it swipes up.

---

## Re-enabling screenshot scanning

Scanning PhonePe screenshots with Google ML Kit OCR is switched off, because ML Kit adds the internet permission and sends Google usage data. The code is commented out, not deleted, so it can come back (the app will then use the internet):

1. `pubspec.yaml`: uncomment `google_mlkit_text_recognition`, `image_picker`, `receive_sharing_intent` and `image`, then run `flutter pub get`. (`receive_sharing_intent` is pinned to 1.8.1, because 1.9.0 needs AGP 9 and compile SDK 37.)
2. `android/app/build.gradle` and `android/app/proguard-rules.pro`: uncomment the ML Kit, EXIF, camera and receive_sharing_intent lines.
3. `android/app/src/main/AndroidManifest.xml`: uncomment the camera/storage permissions and the two "share image" intent filters. Delete `android/app/src/release/AndroidManifest.xml` (it strips the internet permission that ML Kit needs).
4. Uncomment these files (select everything below the header, press Ctrl+/): `lib/services/primary_ocr_service.dart`, `image_preprocessing_service.dart`, `field_extraction_service.dart`, `text_normalization_service.dart`, `transaction_processing_service.dart`, `sharing_intent_service.dart`, `lib/models/transaction_ocr_models.dart`, `lib/screens/transaction_scanner_screen.dart`, `crop_calibration_screen.dart`.
5. Uncomment the lines marked "screenshot scanning" in `main_screen.dart`, `settings_screen.dart` and `add_expense_screen.dart`.

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

The APK ends up in `build/app/outputs/flutter-apk/app-release.apk`.

**Tests:**
```bash
flutter test
```
- `transaction_parser_test.dart`: 173 cases of real-format bank, UPI, recharge, promo and scam messages.
- `recurring_entry_test.dart`: weekly, monthly and yearly schedules.
- `app_prefs_test.dart`: week start, quick actions, reminders and the late-night rule.
- `smart_notifications_test.dart`: weekly summary timing and text.
- `widget_test.dart`: the undo pill.

**Build setup:** Gradle 8.14.3, Android Gradle Plugin 8.11.1, Kotlin 2.2.20.

**Signing:** release builds use `android/key.properties` if it exists (see `key.properties.example`), and fall back to the debug key if it doesn't.

---

## Under the hood

- **Flutter + Provider** for the UI and app state
- **SharedPreferences** for storage, through `LocalStore` (`lib/services/local_store.dart`) and `AppPrefs` (optional features). It's all on the device.
- **flutter_local_notifications + timezone** for alerts, the daily reminder and scheduled summaries (India time)
- **crypto** for hashing the app-lock PIN; **url_launcher** only to open the GitHub Releases link in your browser
- **Hand-drawn charts** made with `CustomPainter`, with no charting library

```
packages/
└── vyaya_capture/  native Android part of auto-detection (notification
                    listener, SMS receiver, on-device queue)
lib/
├── models/      Expense, Income, categories, recurring entries, lent/borrowed
├── providers/   ExpenseProvider (the hub) + managers for expenses, income, budgets…
├── services/    storage, optional-feature prefs, backup/export, notifications
│                and scheduled summaries, intents, capture/ (SMS & notification
│                parser, categoriser)
├── screens/     home, categories, savings, search, analytics, settings,
│                recurring, lent & borrowed, detected payments…
└── widgets/     cards, glass nav bar, category summary, undo pill, app lock
```

---

## Known limitations

- Auto-detection understands the common Indian bank and UPI formats. A message it can't fully read still shows up for review with the original text, rather than being dropped.
- Automatic entries (recurring and month-end savings) are created when you open or return to the app, not in the background. If you don't open it on the 1st, they appear the next time you do, with the correct dates.
- The month-end amounts ("Saved" and "Carried over") are managed by the app: edit one by hand and it goes back to that month's real leftover, so change that month's entries instead. Deleting one is respected (that month stays without it).
- Weekly summary, monthly recap and bill reminder texts reflect your data as of the last time you opened the app.
- It's Android only, and rupees only.

## What's next

- Moving the build to Gradle 9 / AGP 9 / Kotlin 2.3 before Flutter drops support for the current versions

---

## Feedback

This is a personal project that I actually use every day, so it's actively maintained, but it'll have rough edges. If something breaks or you have an idea, open an issue. Bug reports are genuinely appreciated.
