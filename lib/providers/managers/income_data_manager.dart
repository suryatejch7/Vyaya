import '../../models/expense_models.dart';
import '../../services/local_store.dart';

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
      final incomes = await LocalStore.getIncomes(userId: userId);
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
    final incomeId = await LocalStore.addIncome(income, userId);
    final incomeWithId = income.copyWith(id: incomeId);

    final existingIndex = _incomes.indexWhere((i) => i.id == incomeId);
    if (existingIndex == -1) {
      _incomes.insert(_insertAt(incomeWithId), incomeWithId);
    }
  }

  /// First index whose income sorts after [i] (binary search; the list is
  /// kept in order).
  int _insertAt(Income i) {
    var lo = 0, hi = _incomes.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (byDateDesc(_incomes[mid], i) <= 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Adds several at once (undo of a big delete): one write, one sort.
  Future<void> addMany(List<Income> items, int userId) async {
    if (items.isEmpty) return;
    final ids = await LocalStore.addIncomes(items, userId);
    for (var k = 0; k < items.length; k++) {
      _incomes.add(items[k].copyWith(id: ids[k]));
    }
    _incomes.sort(byDateDesc);
  }

  /// Deletes several at once: one pass over the list.
  Future<void> deleteMany(Set<String> ids, int userId) async {
    if (ids.isEmpty) return;
    await LocalStore.deleteIncomes(ids, userId);
    _incomes.removeWhere((i) => ids.contains(i.id));
  }

  Future<void> updateIncome(Income income, int userId) async {
    await LocalStore.updateIncome(income, userId);
    final index = _incomes.indexWhere((i) => i.id == income.id);
    if (index != -1) {
      _incomes[index] = income;
      _incomes.sort(byDateDesc);
    }
  }

  Future<void> deleteIncome(String incomeId, int userId) async {
    await LocalStore.deleteIncome(incomeId, userId);
    _incomes.removeWhere((income) => income.id == incomeId);
  }

  void clear() {
    _incomes.clear();
  }
}
