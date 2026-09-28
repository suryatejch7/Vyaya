import 'package:flutter/material.dart';

class Expense {
  final String? id;
  final double amount;
  final String description;
  final String category;
  final DateTime date;
  final String? payee;
  final String? paymentApp;
  final String? transactionId;
  final String? notes;
  final String? accountId;
  final DateTime createdAt;
  final DateTime updatedAt;

  Expense({
    this.id,
    required this.amount,
    required this.description,
    required this.category,
    required this.date,
    this.payee,
    this.paymentApp,
    this.transactionId,
    this.notes,
    this.accountId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Expense.fromJson(Map<String, dynamic> data) {
    return Expense(
      id: data['id']?.toString(),
      amount: (data['amount'] as num).toDouble(),
      description: data['description'] ?? '',
      category: data['category'] ?? 'Other',
      date: DateTime.parse(data['date']),
      payee: data['payee'],
      paymentApp: data['payment_app'],
      transactionId: data['transaction_id'],
      notes: data['notes'],
      accountId: data['account_id'],
      createdAt: DateTime.parse(data['created_at']),
      updatedAt: DateTime.parse(data['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'amount': amount,
      'description': description,
      'category': category,
      'date': date.toIso8601String(),
      'payee': payee,
      'payment_app': paymentApp,
      'transaction_id': transactionId,
      'notes': notes,
      'account_id': accountId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Expense copyWith({
    String? id,
    double? amount,
    String? description,
    String? category,
    DateTime? date,
    String? payee,
    String? paymentApp,
    String? transactionId,
    String? notes,
    String? accountId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Expense(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      description: description ?? this.description,
      category: category ?? this.category,
      date: date ?? this.date,
      payee: payee ?? this.payee,
      paymentApp: paymentApp ?? this.paymentApp,
      transactionId: transactionId ?? this.transactionId,
      notes: notes ?? this.notes,
      accountId: accountId ?? this.accountId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class Income {
  final String? id;
  final double amount;
  final String title;
  final String source;
  final DateTime date;
  final String? notes;
  final String? accountId;

  /// Marks an entry the app made itself, e.g. "auto-carry-2026-09" for
  /// September's leftover carried into October. Null for your own entries.
  final String? tag;
  final DateTime createdAt;
  final DateTime updatedAt;

  Income({
    this.id,
    required this.amount,
    required this.title,
    required this.source,
    required this.date,
    this.notes,
    this.accountId,
    this.tag,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Income.fromJson(Map<String, dynamic> data) {
    return Income(
      id: data['id']?.toString(),
      amount: (data['amount'] as num).toDouble(),
      title: data['title'] ?? '',
      source: data['source'] ?? '',
      date: DateTime.parse(data['date']),
      notes: data['notes'],
      accountId: data['account_id'],
      tag: data['tag'],
      createdAt: DateTime.parse(data['created_at']),
      updatedAt: DateTime.parse(data['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'amount': amount,
      'title': title,
      'source': source,
      'date': date.toIso8601String(),
      'notes': notes,
      'account_id': accountId,
      if (tag != null) 'tag': tag,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Income copyWith({
    String? id,
    double? amount,
    String? title,
    String? source,
    DateTime? date,
    String? notes,
    String? accountId,
    String? tag,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Income(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      title: title ?? this.title,
      source: source ?? this.source,
      date: date ?? this.date,
      notes: notes ?? this.notes,
      accountId: accountId ?? this.accountId,
      tag: tag ?? this.tag,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class ExpenseCategory {
  final String id;
  final String name;
  final String icon;
  final Color color;
  final bool isDefault;

  ExpenseCategory({
    required this.id,
    required this.name,
    required this.icon,
    Color? color,
    this.isDefault = false,
    String? colorHex,
  }) : color = colorHex != null ? _parseColorFromHex(colorHex) : (color ?? Colors.grey);

  static Color _parseColorFromHex(String hexColor) {
    String cleanHex = hexColor.replaceAll('#', '');
    if (cleanHex.length == 6) {
      cleanHex = 'FF$cleanHex';
    }
    return Color(int.parse(cleanHex, radix: 16));
  }

  String get displayName => name;

  factory ExpenseCategory.fromJson(Map<String, dynamic> data) {
    return ExpenseCategory(
      id: data['id'],
      name: data['name'],
      icon: data['icon'],
      color: Color(data['color']),
      isDefault: data['is_default'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'icon': icon,
      'color': color.toARGB32(),
      'is_default': isDefault,
    };
  }

  static List<ExpenseCategory> getDefaultCategories() {
    return [
      ExpenseCategory(
        id: 'food',
        name: 'Food',
        icon: '🍕',
        color: Colors.orange,
        isDefault: true,
      ),
      ExpenseCategory(
        id: 'transport',
        name: 'Transport',
        icon: '🚗',
        color: Colors.blue,
        isDefault: true,
      ),
      ExpenseCategory(
        id: 'shopping',
        name: 'Shopping',
        icon: '🛍️',
        color: Colors.purple,
        isDefault: true,
      ),
      ExpenseCategory(
        id: 'entertainment',
        name: 'Entertainment',
        icon: '🎬',
        color: Colors.cyan,
        isDefault: true,
      ),
      ExpenseCategory(
        id: 'health',
        name: 'Health',
        icon: '🏥',
        color: Colors.green,
        isDefault: true,
      ),
      ExpenseCategory(
        id: 'bills',
        name: 'Bills',
        icon: '📄',
        color: Colors.amber,
        isDefault: true,
      ),
      ExpenseCategory(
        id: 'education',
        name: 'Education',
        icon: '📚',
        color: Colors.indigo,
        isDefault: true,
      ),
      ExpenseCategory(
        id: 'other',
        name: 'Other',
        icon: '📦',
        color: Colors.grey,
        isDefault: true,
      ),
    ];
  }
}

enum AccountType {
  savings,
  current,
  creditCard;

  String get label {
    switch (this) {
      case AccountType.savings:
        return 'Savings';
      case AccountType.current:
        return 'Current';
      case AccountType.creditCard:
        return 'Credit Card';
    }
  }

  static AccountType fromString(String? value) {
    switch (value) {
      case 'current':
        return AccountType.current;
      case 'creditCard':
      case 'credit_card':
        return AccountType.creditCard;
      default:
        return AccountType.savings;
    }
  }
}

class BankAccount {
  final String id;
  final String name;
  final bool isDefault;
  final AccountType type;

  BankAccount({
    required this.id,
    required this.name,
    this.isDefault = false,
    this.type = AccountType.savings,
  });

  bool get isCreditCard => type == AccountType.creditCard;

  factory BankAccount.fromJson(Map<String, dynamic> data) {
    return BankAccount(
      id: data['id'] as String,
      name: data['name'] as String,
      isDefault: data['is_default'] as bool? ?? false,
      type: AccountType.fromString(data['type'] as String?),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'is_default': isDefault,
      'type': type.name,
    };
  }

  BankAccount copyWith({
    String? id,
    String? name,
    bool? isDefault,
    AccountType? type,
  }) {
    return BankAccount(
      id: id ?? this.id,
      name: name ?? this.name,
      isDefault: isDefault ?? this.isDefault,
      type: type ?? this.type,
    );
  }
}
