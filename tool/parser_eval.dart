// Runs Vyaya's real SMS/notification parser and category matcher over test
// datasets and writes categorised reports you can open in Excel.
//
// From the project folder:
//   dart run tool/parser_eval.dart                 (reads tool/parser_eval/data)
//   dart run tool/parser_eval.dart path\to\folder  (reads another folder)
//
// Put files in the data folder; each is recognised by its columns:
//   * spam/scam/ham CSV (a text column + a label column) -> nothing logged
//   * category CSV   (columns Transaction_Text, Label) -> category checks
//   * labelled CSV   (columns text, expected_direction, ...) -> full scoring
//   * any other CSV with a text column (sms/message/msg/text/body/...)
//                                                   -> unlabelled review
//   * SMS Backup & Restore XML (*.xml)             -> unlabelled review
//
// Reports go to tool/parser_eval/out/<file name>/ (one CSV per outcome plus
// summary.md), and tool/parser_eval/out/SUMMARY.md covers every file.
// Both folders are git-ignored: your own SMS never gets committed.

import 'dart:convert';
import 'dart:io';

import 'package:expensetracker/services/capture/merchant_categorizer.dart';
import 'package:expensetracker/services/capture/transaction_parser.dart';

/// Vyaya's default categories (what a fresh install has).
const _categories = [
  'Food',
  'Transport',
  'Shopping',
  'Entertainment',
  'Health',
  'Bills',
  'Education',
  'Other',
];

/// Kaggle "Indian Banking Transaction Text" labels -> Vyaya category.
/// Investment has no default category in Vyaya, so it's reported apart.
const _categoryMap = {
  'food': 'Food',
  'travel': 'Transport',
  'shopping': 'Shopping',
  'emi': 'Bills',
};

/// A DLT-style sender, so the "personal phone number = scam" rule doesn't
/// hide parser behaviour on datasets that have no sender.
const _defaultSender = 'AD-TESTBK';

final _moneyLike = RegExp(r'(?:₹|\brs\.?|\binr)\s*[0-9]', caseSensitive: false);

void main(List<String> args) {
  final dataDir = Directory(args.isNotEmpty ? args.first : 'tool/parser_eval/data');
  final outDir = Directory('tool/parser_eval/out');
  if (!dataDir.existsSync()) {
    dataDir.createSync(recursive: true);
    stdout.writeln('Created ${dataDir.path}. Put your CSV / XML files in it and run again.');
    return;
  }
  final files = dataDir
      .listSync()
      .whereType<File>()
      .where((f) {
        final n = f.path.toLowerCase();
        return n.endsWith('.csv') || n.endsWith('.xml');
      })
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) {
    stdout.writeln('No .csv or .xml files in ${dataDir.path}.');
    return;
  }
  outDir.createSync(recursive: true);

  final overall = StringBuffer('# Parser evaluation\n\n');
  overall.writeln('Run: ${DateTime.now()}\n');
  for (final file in files) {
    final name = _baseName(file.path);
    stdout.writeln('Processing $name ...');
    final report = Report(name);
    try {
      if (file.path.toLowerCase().endsWith('.xml')) {
        _runXml(file, report);
      } else {
        _runCsv(file, report);
      }
    } catch (e, st) {
      report.note('FAILED to process: $e\n$st');
    }
    final summary = report.write(Directory('${outDir.path}/$name'));
    overall.writeln(summary);
    stdout.writeln('  -> ${outDir.path}/$name/');
  }
  File('${outDir.path}/SUMMARY.md').writeAsStringSync(overall.toString());
  stdout.writeln('\nDone. Open ${outDir.path}/SUMMARY.md');
}

// ======================================================================
// Datasets
// ======================================================================

void _runCsv(File file, Report report) {
  final rows = _parseCsv(_read(file));
  if (rows.isEmpty) {
    report.note('Empty file.');
    return;
  }
  final header = rows.first.map((h) => h.trim().toLowerCase()).toList();
  final body = rows.skip(1).toList();
  int col(List<String> names) {
    for (final n in names) {
      final i = header.indexOf(n);
      if (i != -1) return i;
    }
    return -1;
  }

  String cell(List<String> row, int i) => (i >= 0 && i < row.length) ? row[i] : '';

  // 1) Labelled (your own format) -> full scoring.
  final text = col(['text', 'message', 'msg', 'sms', 'body']);
  final expDir = col(['expected_direction']);
  if (text != -1 && expDir != -1) {
    report.kind = 'Labelled messages (full scoring)';
    final src = col(['source']);
    final snd = col(['sender']);
    final expAmt = col(['expected_amount']);
    final expPayee = col(['expected_payee']);
    for (final row in body) {
      _scoreLabelled(
        report,
        text: cell(row, text),
        source: cell(row, src).isEmpty ? 'sms' : cell(row, src).trim(),
        sender: cell(row, snd).isEmpty ? _defaultSender : cell(row, snd).trim(),
        expectedDirection: cell(row, expDir).trim().toLowerCase(),
        expectedAmount: double.tryParse(cell(row, expAmt).replaceAll(',', '')),
        expectedPayee: cell(row, expPayee).trim(),
      );
    }
    return;
  }

  final label = col(['label', 'labels', 'class', 'category', 'target',
      'is_spam', 'spam', 'type', 'verdict']);

  // 2) Category dataset (statement narrations, not real SMS).
  final tt = col(['transaction_text']);
  if (tt != -1 && label != -1) {
    _runCategories(report, body, tt, label, cell);
    return;
  }

  // 3) Spam / scam / ham sets: none of these should be logged as payments.
  //    (A "ham" row can be a genuine bank alert; the label column shows it.)
  final msg = col(['msg', 'message', 'text', 'sms', 'body', 'content',
      'sms_text', 'message_text']);
  if (msg != -1 && label != -1) {
    report.kind = 'Spam/scam/ham (nothing should be logged)';
    for (final row in body) {
      final m = cell(row, msg);
      if (m.trim().isEmpty) continue;
      final r = TransactionParser.parse(m, source: 'sms', sender: _defaultSender);
      final t = r.transaction;
      if (t != null) {
        report.add('counted_as_payment', {
          'label': cell(row, label),
          'amount': _fmt(t.amount),
          'direction': t.isDebit ? 'debit' : 'credit',
          'payee': t.merchant ?? '',
          'flags': t.flags.join(' '),
          'confidence': t.confidence.toStringAsFixed(2),
          'text': m,
        });
      } else {
        report.add('ignored_correctly', {
          'label': cell(row, label),
          'reason': r.rejectReason ?? '',
          'text': m,
        });
      }
    }
    report.noteByLabel('counted_as_payment');
    return;
  }

  // 4) Unknown CSV with a text column -> unlabelled review.
  final anyText = col([
    'sms', 'message', 'msg', 'text', 'body', 'content', 'description',
    'sms_text', 'message_text', 'transaction_text', 'narration',
  ]);
  if (anyText == -1) {
    report.note('No text column found. Columns: ${rows.first.join(', ')}');
    return;
  }
  report.kind = 'Unlabelled messages (review what would be logged)';
  final snd = col(['sender', 'address', 'from']);
  for (final row in body) {
    _review(report,
        text: cell(row, anyText),
        source: 'sms',
        sender: cell(row, snd).isEmpty ? _defaultSender : cell(row, snd));
  }
}

/// SMS Backup & Restore export: <sms address=".." body=".." date="ms" type="1"/>
void _runXml(File file, Report report) {
  report.kind = 'Your SMS (review what would be logged)';
  final xml = _read(file);
  final smsTag = RegExp(r'<sms\s([^>]*?)/?>', dotAll: true);
  final attr = RegExp(r'(\w+)="([^"]*)"');
  var skippedSent = 0;
  for (final m in smsTag.allMatches(xml)) {
    final a = <String, String>{};
    for (final x in attr.allMatches(m.group(1)!)) {
      a[x.group(1)!] = _xmlUnescape(x.group(2)!);
    }
    if (a['type'] != null && a['type'] != '1') {
      skippedSent++; // only messages you received
      continue;
    }
    final ms = int.tryParse(a['date'] ?? '');
    _review(report,
        text: a['body'] ?? '',
        source: 'sms',
        sender: a['address'] ?? '',
        postedAt: ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms));
  }
  if (skippedSent > 0) report.note('Skipped $skippedSent sent/draft messages.');
}

// ======================================================================
// Scoring
// ======================================================================

void _review(Report report,
    {required String text,
    required String source,
    required String sender,
    DateTime? postedAt}) {
  if (text.trim().isEmpty) return;
  final r = TransactionParser.parse(text,
      source: source, sender: sender, postedAt: postedAt);
  final t = r.transaction;
  if (t != null) {
    report.add('would_log', {
      'sender': sender,
      'date': postedAt?.toIso8601String() ?? '',
      'amount': _fmt(t.amount),
      'direction': t.isDebit ? 'debit' : 'credit',
      'payee': t.merchant ?? '',
      'category': _category(t.merchant, text),
      'account': t.last4 ?? '',
      'reference': t.reference ?? '',
      'flags': t.flags.join(' '),
      'confidence': t.confidence.toStringAsFixed(2),
      'text': text,
    });
  } else if (_moneyLike.hasMatch(text)) {
    // Mentions an amount but was ignored: either correctly (OTP, promo...)
    // or a missed payment. Worth a skim.
    report.add('ignored_mentions_money', {
      'sender': sender,
      'date': postedAt?.toIso8601String() ?? '',
      'reason': r.rejectReason ?? '',
      'text': text,
    });
  } else {
    report.count('ignored_no_money');
  }
}

void _scoreLabelled(
  Report report, {
  required String text,
  required String source,
  required String sender,
  required String expectedDirection, // debit | credit | none
  required double? expectedAmount,
  required String expectedPayee,
}) {
  if (text.trim().isEmpty) return;
  final r = TransactionParser.parse(text, source: source, sender: sender);
  final t = r.transaction;
  final shouldLog = expectedDirection == 'debit' || expectedDirection == 'credit';
  final data = <String, String>{
    'expected_direction': expectedDirection,
    'expected_amount': expectedAmount == null ? '' : _fmt(expectedAmount),
    'expected_payee': expectedPayee,
    'got_direction': t == null ? '' : (t.isDebit ? 'debit' : 'credit'),
    'got_amount': t == null ? '' : _fmt(t.amount),
    'got_payee': t?.merchant ?? '',
    'reject_reason': r.rejectReason ?? '',
    'flags': t?.flags.join(' ') ?? '',
    'text': text,
  };
  if (!shouldLog) {
    report.add(t == null ? 'ignored_correctly' : 'false_positive', data);
    return;
  }
  if (t == null) {
    report.add('missed_payment', data);
  } else if ((t.isDebit ? 'debit' : 'credit') != expectedDirection) {
    report.add('wrong_direction', data);
  } else if (expectedAmount != null && (t.amount - expectedAmount).abs() > 0.009) {
    report.add('wrong_amount', data);
  } else if (expectedPayee.isNotEmpty &&
      !(t.merchant ?? '').toLowerCase().contains(expectedPayee.toLowerCase())) {
    report.add('wrong_payee', data);
  } else {
    report.add('correct', data);
  }
}

void _runCategories(Report report, List<List<String>> body, int tt, int label,
    String Function(List<String>, int) cell) {
  report.kind = 'Category matching (statement narrations)';
  for (final row in body) {
    final t = cell(row, tt);
    if (t.trim().isEmpty) continue;
    final lab = cell(row, label).trim();
    final merchant = t.split('|').first.trim();
    final got = MerchantCategorizer.suggest(
      merchant: merchant,
      rawText: t,
      categoryNames: _categories,
      learned: const {},
    );
    final expected = _categoryMap[lab.toLowerCase()];
    final data = {
      'label': lab,
      'expected': expected ?? '(no such category in Vyaya)',
      'got': got,
      'payee': merchant,
      'text': t,
    };
    if (expected == null) {
      report.add('category_not_in_app', data);
    } else if (got == expected) {
      report.add('category_correct', data);
    } else {
      report.add('category_wrong', data);
    }
  }
}

String _category(String? merchant, String text) => MerchantCategorizer.suggest(
      merchant: merchant,
      rawText: text,
      categoryNames: _categories,
      learned: const {},
    );

// ======================================================================
// Report
// ======================================================================

class Report {
  final String name;
  String kind = '';
  final Map<String, List<Map<String, String>>> _buckets = {};
  final Map<String, int> _counts = {};
  final List<String> _notes = [];

  Report(this.name);

  void add(String bucket, Map<String, String> row) =>
      _buckets.putIfAbsent(bucket, () => []).add(row);
  void count(String bucket) => _counts[bucket] = (_counts[bucket] ?? 0) + 1;
  void note(String s) => _notes.add(s);

  /// Adds a note splitting [bucket] by its 'label' column (spam / ham ...).
  void noteByLabel(String bucket) {
    final rows = _buckets[bucket];
    if (rows == null || rows.isEmpty) return;
    final by = <String, int>{};
    for (final r in rows) {
      final l = (r['label'] ?? '').isEmpty ? '(no label)' : r['label']!;
      by[l] = (by[l] ?? 0) + 1;
    }
    note('$bucket by label: ${by.entries.map((e) => '${e.key} ${e.value}').join(', ')}');
  }

  /// Mistake buckets first, so they're easy to find.
  static const _order = [
    'counted_as_payment',
    'false_positive',
    'missed_payment',
    'wrong_direction',
    'wrong_amount',
    'wrong_payee',
    'category_wrong',
    'would_log',
    'ignored_mentions_money',
    'category_not_in_app',
    'correct',
    'category_correct',
    'ignored_correctly',
  ];

  String write(Directory dir) {
    dir.createSync(recursive: true);
    final names = {..._order.where(_buckets.containsKey), ..._buckets.keys};
    final total = _buckets.values.fold<int>(0, (s, l) => s + l.length) +
        _counts.values.fold<int>(0, (s, n) => s + n);
    final md = StringBuffer('## $name\n\n');
    if (kind.isNotEmpty) md.writeln('Type: $kind  \n');
    md.writeln('Messages: $total\n');
    md.writeln('| Outcome | Count | Share |');
    md.writeln('|---|---:|---:|');
    for (final b in names) {
      final rows = _buckets[b]!;
      _writeCsv(File('${dir.path}/$b.csv'), rows);
      md.writeln('| $b | ${rows.length} | ${_pct(rows.length, total)} |');
    }
    for (final e in _counts.entries) {
      md.writeln('| ${e.key} | ${e.value} | ${_pct(e.value, total)} |');
    }
    for (final n in _notes) {
      md.writeln('\n> $n');
    }
    md.writeln();
    File('${dir.path}/summary.md').writeAsStringSync(md.toString());
    return md.toString();
  }

  static String _pct(int n, int total) =>
      total == 0 ? '-' : '${(n * 100 / total).toStringAsFixed(1)}%';
}

// ======================================================================
// Helpers
// ======================================================================

String _read(File f) {
  var s = utf8.decode(f.readAsBytesSync(), allowMalformed: true);
  if (s.startsWith('﻿')) s = s.substring(1);
  return s;
}

String _baseName(String path) {
  final n = path.replaceAll('\\', '/').split('/').last;
  final dot = n.lastIndexOf('.');
  return dot > 0 ? n.substring(0, dot) : n;
}

String _fmt(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

/// RFC 4180 CSV: quoted fields, "" escapes, newlines inside quotes.
List<List<String>> _parseCsv(String s) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    if (row.any((c) => c.trim().isNotEmpty)) rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < s.length && s[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == ',') {
      endField();
    } else if (c == '\r' || c == '\n') {
      if (c == '\r' && i + 1 < s.length && s[i + 1] == '\n') i++;
      endRow();
    } else {
      field.write(c);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

void _writeCsv(File f, List<Map<String, String>> rows) {
  if (rows.isEmpty) return;
  final cols = rows.first.keys.toList();
  String esc(String v) => '"${v.replaceAll('"', '""')}"';
  final b = StringBuffer('﻿'); // BOM so Excel reads ₹ correctly
  b.writeln(cols.map(esc).join(','));
  for (final r in rows) {
    b.writeln(cols.map((c) => esc(r[c] ?? '')).join(','));
  }
  f.writeAsStringSync(b.toString());
}

String _xmlUnescape(String s) => s
    .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'),
        (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)))
    .replaceAllMapped(
        RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)))
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&');
