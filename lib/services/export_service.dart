import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/expense_models.dart';
import '../providers/expense_provider.dart';
import 'supabase_service.dart';

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
          await ExpenseSupabaseService.getExpenses(userId: provider.userId);
      final incomes =
          await ExpenseSupabaseService.getIncomes(userId: provider.userId);

      final file = await _generateCsv(
        expenses: expenses,
        incomes: incomes,
        currency: provider.currency,
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
  }) async {
    final buf = StringBuffer();

    // --- Expenses ---
    // Note: the form's "Payee" field is stored as Expense.description and its
    // "Purpose" field as Expense.payee — the columns below map accordingly.
    buf.writeln('EXPENSES');
    buf.writeln(
      'Date,Payee,Amount,Category,Purpose,Payment App,Notes',
    );
    for (final e in expenses) {
      buf.writeln(
        '${_fmtDate(e.date)},'
        '"${_esc(e.description)}",'
        '${e.amount},'
        '"${_esc(e.category)}",'
        '"${_esc(e.payee ?? '')}",'
        '"${_esc(e.paymentApp ?? '')}",'
        '"${_esc(e.notes ?? '')}"',
      );
    }

    buf.writeln();

    // --- Income ---
    buf.writeln('INCOME');
    buf.writeln('Date,Title,Amount,Source,Notes');
    for (final i in incomes) {
      buf.writeln(
        '${_fmtDate(i.date)},'
        '"${_esc(i.title)}",'
        '${i.amount},'
        '"${_esc(i.source)}",'
        '"${_esc(i.notes ?? '')}"',
      );
    }

    buf.writeln();

    // --- Summary ---
    buf.writeln('SUMMARY');
    final totalExp = expenses.fold(0.0, (s, e) => s + e.amount);
    final totalInc = incomes.fold(0.0, (s, i) => s + i.amount);
    buf.writeln('Total Expenses,$currency${totalExp.toStringAsFixed(2)}');
    buf.writeln('Total Income,$currency${totalInc.toStringAsFixed(2)}');
    buf.writeln(
      'Net Balance,$currency${(totalInc - totalExp).toStringAsFixed(2)}',
    );
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

  // Escape double quotes for CSV
  static String _esc(String s) => s.replaceAll('"', '""');
}
