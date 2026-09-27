import '../../models/expense_models.dart';
import '../../services/supabase_service.dart';

class IncomeDataManager {
  final List<Income> _incomes = [];

  List<Income> get incomes => _incomes;

  /// Newest income date first; same date -> most recently logged first.
  static int byDateDesc(Income a, Income b) {
    final c = b.date.compareTo(a.date);
    return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
  }

  Future<void> loadIncomes(int userId) async {
    try {
      final incomes = await ExpenseSupabaseService.getIncomes(userId: userId);
      final sortedIncomes = List<Income>.from(incomes);
      sortedIncomes.sort(byDateDesc);

      if (sortedIncomes.isNotEmpty || _incomes.isEmpty) {
        _incomes.clear();
        _incomes.addAll(sortedIncomes);
      }
    } catch (e) {
    }
  }

  Future<void> addIncome(Income income, int userId) async {
    final incomeId = await ExpenseSupabaseService.addIncome(income, userId);
    final incomeWithId = income.copyWith(id: incomeId);

    final existingIndex = _incomes.indexWhere((i) => i.id == incomeId);
    if (existingIndex == -1) {
      _incomes.add(incomeWithId);
      _incomes.sort(byDateDesc);
    }
  }

  Future<void> updateIncome(Income income, int userId) async {
    await ExpenseSupabaseService.updateIncome(income, userId);
    final index = _incomes.indexWhere((i) => i.id == income.id);
    if (index != -1) {
      _incomes[index] = income;
      _incomes.sort(byDateDesc);
    }
  }

  Future<void> deleteIncome(String incomeId, int userId) async {
    await ExpenseSupabaseService.deleteIncome(incomeId, userId);
    _incomes.removeWhere((income) => income.id == incomeId);
  }

  void clear() {
    _incomes.clear();
  }
}
