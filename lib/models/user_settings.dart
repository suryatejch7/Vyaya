import '../models/expense_models.dart';

export '../models/expense_models.dart' show BankAccount;

class User {
  final int id;
  final String userName;
  final DateTime createdAt;
  final DateTime updatedAt;

  User({
    required this.id,
    required this.userName,
    required this.createdAt,
    required this.updatedAt,
  });

  factory User.fromJson(Map<String, dynamic> data) {
    return User(
      id: data['id'] as int,
      userName: data['user_name'] as String,
      createdAt: DateTime.parse(data['created_at'] as String),
      updatedAt: DateTime.parse(data['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_name': userName,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class UserSettings {
  final int userId;
  final double monthlyBudget;
  final String currency;
  final Map<String, double> categoryBudgets;
  final List<ExpenseCategory> customCategories;
  final List<BankAccount> accounts;
  final double cropTop;
  final double cropBottom;
  final bool isCropCalibrated;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserSettings({
    required this.userId,
    required this.monthlyBudget,
    required this.currency,
    required this.categoryBudgets,
    required this.customCategories,
    this.accounts = const [],
    this.cropTop = 0.17,
    this.cropBottom = 0.21,
    this.isCropCalibrated = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserSettings.fromJson(Map<String, dynamic> data) {
    final categoryBudgetsJson = data['category_budgets'] as Map<String, dynamic>? ?? {};
    final categoryBudgets = <String, double>{};
    categoryBudgetsJson.forEach((key, value) {
      categoryBudgets[key] = (value as num).toDouble();
    });

    final customCategoriesJson = data['custom_categories'] as List<dynamic>? ?? [];
    final customCategories = customCategoriesJson
        .map((item) => ExpenseCategory.fromJson(item as Map<String, dynamic>))
        .toList();

    final accountsJson = data['accounts'] as List<dynamic>? ?? [];
    final accounts = accountsJson
        .map((item) => BankAccount.fromJson(item as Map<String, dynamic>))
        .toList();

    return UserSettings(
      userId: data['user_id'] as int,
      monthlyBudget: (data['monthly_budget'] as num?)?.toDouble() ?? 25000.0,
      currency: data['currency'] ?? '₹',
      categoryBudgets: categoryBudgets,
      customCategories: customCategories,
      accounts: accounts,
      cropTop: (data['crop_top'] as num?)?.toDouble() ?? 0.17,
      cropBottom: (data['crop_bottom'] as num?)?.toDouble() ?? 0.21,
      isCropCalibrated: data['is_crop_calibrated'] as bool? ?? false,
      createdAt: DateTime.parse(data['created_at'] as String),
      updatedAt: DateTime.parse(data['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'monthly_budget': monthlyBudget,
      'currency': currency,
      'category_budgets': categoryBudgets,
      'custom_categories': customCategories.map((cat) => cat.toJson()).toList(),
      'accounts': accounts.map((acc) => acc.toJson()).toList(),
      'crop_top': cropTop,
      'crop_bottom': cropBottom,
      'is_crop_calibrated': isCropCalibrated,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  UserSettings copyWith({
    int? userId,
    double? monthlyBudget,
    String? currency,
    Map<String, double>? categoryBudgets,
    List<ExpenseCategory>? customCategories,
    List<BankAccount>? accounts,
    double? cropTop,
    double? cropBottom,
    bool? isCropCalibrated,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserSettings(
      userId: userId ?? this.userId,
      monthlyBudget: monthlyBudget ?? this.monthlyBudget,
      currency: currency ?? this.currency,
      categoryBudgets: categoryBudgets ?? Map.from(this.categoryBudgets),
      customCategories: customCategories ?? List.from(this.customCategories),
      accounts: accounts ?? List.from(this.accounts),
      cropTop: cropTop ?? this.cropTop,
      cropBottom: cropBottom ?? this.cropBottom,
      isCropCalibrated: isCropCalibrated ?? this.isCropCalibrated,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
