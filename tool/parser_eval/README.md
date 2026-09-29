# Parser evaluation

Runs Vyaya's real message parser (`lib/services/capture/transaction_parser.dart`)
and category matcher over test datasets, and sorts every message into a report
by what happened. The `data/` and `out/` folders are git-ignored.

## Run

```powershell
flutter pub get                      # once, so package imports resolve
dart run tool/parser_eval.dart       # reads tool/parser_eval/data
```

Reports: `tool/parser_eval/out/SUMMARY.md`, plus one folder per input file
with a CSV per outcome.

## Input files (recognised by their columns)

| File | Columns | What's checked |
|---|---|---|
| Spam / scam / ham sets (Kaggle India Spam, Hugging Face scam sets, UCI) | a text column (`Msg`, `message`, `text`, `sms`…) plus a label column (`Label`, `class`, `category`…) | Nothing should be logged; results split by label |
| Kaggle Indian Banking Transaction Text | `Transaction_Text`, `Label` | Category (Food, Travel→Transport, Shopping, EMI→Bills) |
| Your own labelled CSV | `text`, `expected_direction`, optional `source`, `sender`, `expected_amount`, `expected_payee` | Full scoring |
| Any CSV with a text column | `sms` / `message` / `msg` / `text` / `body` / … | Unlabelled review |
| SMS Backup & Restore export | `*.xml` | Unlabelled review (received messages only) |

`expected_direction` is `debit`, `credit` or `none` (should be ignored).
`source` is `sms` (default) or `notification`.

## Outcome files

| File | Meaning |
|---|---|
| `counted_as_payment.csv` | Spam/ham message that Vyaya would log (mistake) |
| `false_positive.csv` | Labelled "none" but logged (mistake) |
| `missed_payment.csv` | Real payment that was ignored, with the reason (mistake) |
| `wrong_direction.csv` | Paid read as received or the reverse (mistake) |
| `wrong_amount.csv` | Wrong amount (mistake) |
| `wrong_payee.csv` | Payee doesn't contain the expected name (mistake) |
| `category_wrong.csv` | Category doesn't match the label (mistake) |
| `would_log.csv` | Unlabelled: what Vyaya would log, to check by eye |
| `ignored_mentions_money.csv` | Unlabelled: mentions ₹ but ignored, with reason (possible misses) |
| `category_not_in_app.csv` | Label with no Vyaya category (e.g. Investment) |
| `correct.csv`, `category_correct.csv`, `ignored_correctly.csv` | Right answers |

## Turning your own SMS into a labelled set

1. Run once with your XML export.
2. Copy rows from `would_log.csv` and `ignored_mentions_money.csv` into a new
   CSV with columns `text,expected_direction,expected_amount,expected_payee`
   and fill in the right answers.
3. Save it in `data/` (e.g. `my_labelled.csv`) and run again. Every future
   parser change can be checked against it.
