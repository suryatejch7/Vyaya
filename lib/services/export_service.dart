import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/expense_models.dart';
import '../providers/expense_provider.dart';
import 'local_store.dart';

/// Service for exporting expense and income data to CSV.
class ExportService {
  /// Generates a CSV file with all expenses and income, then opens
  /// the platform share sheet so the user can save / send it.
  static Future<void> exportAndShare(BuildContext context) async {
    final provider = Provider.of<ExpenseProvider>(context, listen: false);

    try {
      // Read from storage, not provider.expenses: the provider only holds the
      // pages loaded so far, so older expenses would be missing.
      final expenses =
          await LocalStore.getExpenses(userId: provider.userId);
      final incomes =
          await LocalStore.getIncomes(userId: provider.userId);

      final file = await _generateCsv(
        expenses: expenses,
        incomes: incomes,
        currency: provider.currency,
        accountName: provider.getAccountName,
      );

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Vyaya Export',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Builds a CSV file containing expenses, income, and a summary section.
  static Future<File> _generateCsv({
    required List<Expense> expenses,
    required List<Income> incomes,
    required String currency,
    required String Function(String?) accountName,
  }) async {
    final buf = StringBuffer();

    // --- Expenses ---
    // Note: the form's "Payee" field is stored as Expense.description and its
    // "Purpose" field as Expense.payee — the columns below map accordingly.
    buf.writeln('EXPENSES');
    buf.writeln(
      'Date,Time,Payee,Amount,Category,Purpose,Account,Payment App,Type,Notes',
    );
    for (final e in expenses) {
      final auto = ExpenseProvider.isAutoSavedEntry(e);
      buf.writeln(
        '${_fmtDate(e.date)},'
        '${_fmtTime(e.date)},'
        '"${_esc(e.description)}",'
        '${e.amount},'
        '"${_esc(e.category)}",'
        '"${_esc(e.payee ?? '')}",'
        '"${_esc(accountName(e.accountId))}",'
        '"${_esc(e.paymentApp ?? '')}",'
        '${auto ? 'Month-end savings' : 'Expense'},'
        '"${_esc(e.notes ?? '')}"',
      );
    }

    buf.writeln();

    // --- Income ---
    buf.writeln('INCOME');
    buf.writeln('Date,Time,Title,Amount,Source,Account,Type,Notes');
    for (final i in incomes) {
      final carry = ExpenseProvider.isCarryForwardEntry(i);
      buf.writeln(
        '${_fmtDate(i.date)},'
        '${_fmtTime(i.date)},'
        '"${_esc(i.title)}",'
        '${i.amount},'
        '"${_esc(i.source)}",'
        '"${_esc(accountName(i.accountId))}",'
        '${carry ? 'Carried over' : 'Income'},'
        '"${_esc(i.notes ?? '')}"',
      );
    }

    buf.writeln();

    // --- Summary ---
    // Totals leave out the app's own month-end entries: a "Saved" entry
    // isn't spending, and a carried-over leftover is income already
    // counted in the month it came from. They're listed separately.
    buf.writeln('SUMMARY');
    final saved = expenses.where(ExpenseProvider.isAutoSavedEntry);
    final carried = incomes.where(ExpenseProvider.isCarryForwardEntry);
    final totalExp = expenses
        .where((e) => !ExpenseProvider.isAutoSavedEntry(e))
        .fold(0.0, (s, e) => s + e.amount);
    final totalInc = incomes
        .where((i) => !ExpenseProvider.isCarryForwardEntry(i))
        .fold(0.0, (s, i) => s + i.amount);
    buf.writeln('Total Expenses,$currency${totalExp.toStringAsFixed(2)}');
    buf.writeln('Total Income,$currency${totalInc.toStringAsFixed(2)}');
    buf.writeln(
      'Net Balance,$currency${(totalInc - totalExp).toStringAsFixed(2)}',
    );
    if (saved.isNotEmpty) {
      buf.writeln(
          'Moved to Saved (not counted),$currency${saved.fold(0.0, (s, e) => s + e.amount).toStringAsFixed(2)}');
    }
    if (carried.isNotEmpty) {
      buf.writeln(
          'Carried over (not counted),$currency${carried.fold(0.0, (s, i) => s + i.amount).toStringAsFixed(2)}');
    }
    buf.writeln('Expenses Count,${expenses.length}');
    buf.writeln('Income Count,${incomes.length}');
    buf.writeln('Export Date,${DateTime.now().toIso8601String()}');

    // Write to file
    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final file = File('${dir.path}/expense_tracker_export_$ts.csv');
    await file.writeAsString(buf.toString());
    return file;
  }

  // Format date as YYYY-MM-DD
  static String _fmtDate(DateTime d) => d.toIso8601String().split('T').first;

  // Time as HH:MM (24-hour)
  static String _fmtTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  // Escape double quotes for CSV
  static String _esc(String s) => s.replaceAll('"', '""');
}
