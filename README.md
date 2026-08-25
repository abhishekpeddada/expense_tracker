# Expense Tracker

A Flutter (Android) expense tracker that acts as your **default SMS app**:
every bank/UPI/credit-card SMS is parsed into a transaction, you categorize it
from a notification, and dashboards show where your money goes.

## How it works

1. The app holds Android's `ROLE_SMS` (default SMS app), so it receives every
   incoming SMS — and also functions as a real messaging app (Messages tab).
2. A pure-Dart parser (`lib/parsing/sms_parser.dart`) detects debit/credit
   messages from Indian banks, extracts amount, account/card tail, merchant,
   and whether it was a **credit card** spend.
3. Detected transactions are stored locally (drift/SQLite) as *uncategorized*
   and a persistent notification asks "what was this for?" with category
   actions.
4. Optional **Google Sign-In** syncs everything to Firebase (Firestore).
   Skipped login = local-only, no sync.
5. Dashboard tab: monthly spend, credit-card spend, category breakdown, and
   (later) AI-generated spending summaries.

## Status / roadmap

- [x] App shell: Dashboard / Transactions / Messages tabs
- [x] Local DB (drift): transactions + SMS store
- [x] SMS transaction parser + unit tests (`flutter test`)
- [x] In-app categorization sheet, category breakdown pie chart
- [ ] Native default-SMS-app layer (Kotlin, `RoleManager.ROLE_SMS`, receive/send)
- [ ] Persistent categorization notification with quick actions
- [ ] Firebase: Google Sign-In + Firestore sync (local-first)
- [ ] AI monthly spending summary
- [ ] Send SMS / conversation threads in Messages tab

## Dev

```sh
flutter pub get
dart run build_runner build   # regenerate drift code after schema changes
flutter analyze && flutter test
flutter run                   # needs an Android device/emulator
```

> **Note:** the default-SMS-app concept is Android-only — iOS does not allow
> third-party SMS access.
