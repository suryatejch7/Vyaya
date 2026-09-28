import '../../models/expense_models.dart';
import '../../services/local_store.dart';

class AccountManager {
  final List<BankAccount> _accounts = [];

  List<BankAccount> get accounts => _accounts;

  BankAccount? get defaultAccount {
    if (_accounts.isEmpty) return null;
    return _accounts.firstWhere(
      (acc) => acc.isDefault,
      orElse: () => _accounts.first,
    );
  }

  void initialize(List<BankAccount> accounts) {
    _accounts.clear();
    _accounts.addAll(accounts);
  }

  BankAccount? getAccountById(String accountId) {
    final account = _accounts.firstWhere(
      (acc) => acc.id == accountId,
      orElse: () => BankAccount(id: '', name: ''),
    );
    return account.id.isEmpty ? null : account;
  }

  String getAccountName(String? accountId) {
    if (accountId == null || accountId.isEmpty) return '';
    final account = getAccountById(accountId);
    return account?.name ?? '';
  }

  Future<void> addAccount(BankAccount account, int userId) async {
    final isFirst = _accounts.isEmpty;
    final newAccount = isFirst ? account.copyWith(isDefault: true) : account;

    _accounts.add(newAccount);
    await _saveAccounts(userId);
  }

  Future<void> removeAccount(String accountId, int userId) async {
    final removedAccount = _accounts.firstWhere((acc) => acc.id == accountId);
    final wasDefault = removedAccount.isDefault;
    _accounts.removeWhere((acc) => acc.id == accountId);

    if (wasDefault && _accounts.isNotEmpty) {
      _accounts[0] = _accounts[0].copyWith(isDefault: true);
    }

    await _saveAccounts(userId);
  }

  Future<void> updateAccount(BankAccount account, int userId) async {
    final i = _accounts.indexWhere((a) => a.id == account.id);
    if (i == -1) return;
    _accounts[i] = account;
    await _saveAccounts(userId);
  }

  Future<void> setDefaultAccount(String accountId, int userId) async {
    for (int i = 0; i < _accounts.length; i++) {
      _accounts[i] = _accounts[i].copyWith(
        isDefault: _accounts[i].id == accountId,
      );
    }
    await _saveAccounts(userId);
  }

  Future<void> _saveAccounts(int userId) async {
    await LocalStore.saveAccounts(_accounts, userId: userId);
  }

  void clear() {
    _accounts.clear();
  }
}
