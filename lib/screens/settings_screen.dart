import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/expense_provider.dart';
import '../providers/user_provider.dart';
import '../providers/capture_provider.dart';
import 'detected_payments_screen.dart';
import '../models/expense_models.dart';
import '../services/notification_service.dart';
import '../services/local_store.dart';
import '../services/export_service.dart';
import '../services/backup_service.dart';
// import 'crop_calibration_screen.dart'; // screenshot scanning off (offline build)
import 'recurring_screen.dart';
import 'lent_borrowed_screen.dart';
import 'savings_screen.dart';
import '../services/app_prefs.dart';
import '../widgets/app_lock.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

/// Settings is a hub page; heavier sections open as their own pages that
/// reuse the same state class (so dialogs/helpers are shared).
enum SettingsPage { home, categories, accounts, autoDetect, optionalFeatures }

class SettingsScreen extends StatefulWidget {
  final SettingsPage page;
  const SettingsScreen({super.key, this.page = SettingsPage.home});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _categoryNameController = TextEditingController();
  final TextEditingController _categoryBudgetController = TextEditingController();

  bool _isEditingName = false;
  bool _isAddingCategory = false;

  // Multi-select delete for categories (long-press to enter)
  final Set<String> _selectedCategoryIds = {};
  bool get _isCategorySelectionMode => _selectedCategoryIds.isNotEmpty;

  void _toggleCategorySelection(String id) {
    setState(() {
      if (!_selectedCategoryIds.remove(id)) _selectedCategoryIds.add(id);
    });
  }

  void _clearCategorySelection() {
    setState(_selectedCategoryIds.clear);
  }

  @override
  void initState() {
    super.initState();
    _loadUserData();
    AppPrefs.instance.addListener(_onPrefsChanged);
  }

  void _onPrefsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppPrefs.instance.removeListener(_onPrefsChanged);
    _nameController.dispose();
    _categoryNameController.dispose();
    _categoryBudgetController.dispose();
    super.dispose();
  }

  void _loadUserData() {
    final provider = context.read<ExpenseProvider>();
    _nameController.text = provider.userName;
  }

  /// Saves the name. Returns true on success, false on failure, or null if
  /// nothing changed (empty or same name) — in every case the editor closes.
  Future<bool?> _saveUserName() async {
    final newName = _nameController.text.trim();
    final userProvider = context.read<UserProvider>();
    final expenseProvider = context.read<ExpenseProvider>();

    if (newName.isEmpty || newName == userProvider.userName) {
      _nameController.text = userProvider.userName;
      setState(() => _isEditingName = false);
      return null;
    }

    // UserProvider persists it; ExpenseProvider keeps its own copy of the
    // name, so sync that too or other screens keep showing the old one.
    final ok = await userProvider.updateUserName(newName);
    if (ok) expenseProvider.updateLocalUserName(newName);

    if (mounted) setState(() => _isEditingName = false);
    return ok;
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.page) {
      case SettingsPage.categories:
        return _buildCategoriesPage();
      case SettingsPage.accounts:
        return _subPage(
          'Bank Accounts',
          Consumer<ExpenseProvider>(
            builder: (context, ep, child) => _buildAccountsSection(ep),
          ),
        );
      case SettingsPage.autoDetect:
        return _subPage('Auto-detect Payments', _buildAutoDetectSection());
      case SettingsPage.optionalFeatures:
        return _subPage(
          'Optional features',
          Consumer<ExpenseProvider>(
            builder: (context, ep, child) => _buildOptionalFeatures(ep),
          ),
        );
      case SettingsPage.home:
        return _buildHome();
    }
  }

  // ==================== LAYOUT HELPERS ====================

  PreferredSizeWidget _appBar(String title) => AppBar(
        title: Text(
          title,
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      );

  Widget _subPage(String title, Widget child) => Scaffold(
        backgroundColor: Colors.black,
        appBar: _appBar(title),
        body: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 8, bottom: 32),
          child: child,
        ),
      );

  void _open(SettingsPage page) => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => SettingsScreen(page: page)),
      );

  /// Card without a title (profile header).
  Widget _plainCard({required Widget child}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Material(
          color: const Color(0xFF0D0D0D),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      );

  Widget _groupLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
        child: Text(
          text,
          style: TextStyle(
            color: Colors.grey[500],
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.1,
          ),
        ),
      );

  /// Rounded group of rows with thin dividers between them.
  // A Material (not a decorated Container) so the ListTiles inside paint
  // their ink splashes on it.
  Widget _group(List<Widget> rows) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Material(
        color: const Color(0xFF0D0D0D),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  indent: 64,
                  color: Colors.grey.withValues(alpha: 0.15),
                ),
              rows[i],
            ],
          ],
        ),
        ),
      );

  Widget _tileIcon(IconData icon, Color color) => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      );

  Widget _row({
    required IconData icon,
    required Color color,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    Widget? trailing,
    bool chevron = true,
    Color titleColor = Colors.white,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: _tileIcon(icon, color),
      title: Text(title,
          style: TextStyle(color: titleColor, fontWeight: FontWeight.w500)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle,
              style: const TextStyle(color: Colors.grey, fontSize: 12.5)),
      trailing: trailing ??
          (chevron ? const Icon(Icons.chevron_right, color: Colors.grey) : null),
    );
  }

  Widget _badge(int n) => Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.amber,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text('$n',
            style: const TextStyle(
                color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
      );

  // ==================== HOME (hub) ====================

  Widget _buildHome() {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _appBar('Settings'),
      body: Consumer3<UserProvider, ExpenseProvider, CaptureProvider>(
        builder: (context, userProvider, expenseProvider, cap, child) {
          final accounts = expenseProvider.accounts;
          final defaultAccount = expenseProvider.defaultAccount;
          final prefs = AppPrefs.instance;
          final catCount = expenseProvider.categories.length;

          return ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 40),
            children: [
              _buildProfileCard(userProvider, expenseProvider),

              _groupLabel('MONEY'),
              _group([
                _row(
                  icon: Icons.category_rounded,
                  color: Colors.orange,
                  title: 'Categories',
                  subtitle:
                      '$catCount ${catCount == 1 ? 'category' : 'categories'} · limits and deleting',
                  onTap: () => _open(SettingsPage.categories),
                ),
                _row(
                  icon: Icons.account_balance_rounded,
                  color: Colors.blue,
                  title: 'Bank Accounts',
                  subtitle: accounts.isEmpty
                      ? 'None added'
                      : '${accounts.length} ${accounts.length == 1 ? 'account' : 'accounts'}${defaultAccount != null ? ' · ${defaultAccount.name} default' : ''}',
                  onTap: () => _open(SettingsPage.accounts),
                ),
                _row(
                  icon: Icons.savings_outlined,
                  color: const Color(0xFF26A69A),
                  title: 'Savings',
                  subtitle: expenseProvider.monthEndSavingsEnabled
                      ? 'Month-end leftovers, month by month'
                      : 'Leftovers carried into the next month',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const SavingsScreen()),
                  ),
                ),
                // Whichever shortcut isn't in the quick actions sheet.
                _shortcutRow(prefs.shortcutInSettings, expenseProvider, cap),
              ]),

              _groupLabel('AUTOMATION'),
              _group([
                _row(
                  icon: Icons.bolt_rounded,
                  color: Colors.amber,
                  title: 'Auto-detect Payments',
                  subtitle: !cap.isEnabled
                      ? 'Off · log payments from SMS and payment apps'
                      : cap.autoMode
                          ? 'On · adds automatically'
                          : 'On · asks before adding',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (cap.pendingCount > 0) _badge(cap.pendingCount),
                      const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                  onTap: () => _open(SettingsPage.autoDetect),
                ),
                // Screenshot scanning is disabled (offline build).
                // _row(
                //   icon: Icons.crop_free_rounded,
                //   color: Colors.deepOrange,
                //   title: 'PhonePe Screenshot Scanning',
                //   subtitle: 'Crop calibration',
                //   onTap: () => Navigator.push(
                //     context,
                //     MaterialPageRoute(
                //         builder: (context) => const CropCalibrationScreen()),
                //   ),
                // ),
              ]),

              _groupLabel('NOTIFICATIONS'),
              _group([
                FutureBuilder<bool>(
                  future: NotificationService.areNotificationsEnabled(),
                  builder: (context, snapshot) {
                    final on = snapshot.data ?? true;
                    return _row(
                      icon: Icons.notifications_rounded,
                      color: Colors.purpleAccent,
                      title: 'Spending alerts',
                      subtitle: 'When spending passes your income or a category limit',
                      onTap: () async {
                        await NotificationService.setNotificationsEnabled(!on);
                        setState(() {});
                      },
                      trailing: Switch(
                        value: on,
                        onChanged: (value) async {
                          await NotificationService.setNotificationsEnabled(
                              value);
                          setState(() {});
                        },
                      ),
                    );
                  },
                ),
                _row(
                  icon: Icons.notification_add_outlined,
                  color: Colors.grey,
                  title: 'Send test notification',
                  chevron: false,
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await NotificationService.checkIncomeExceeded(26000, 25000);
                    messenger.showSnackBar(const SnackBar(
                      content: Text('Test notification sent'),
                      duration: Duration(seconds: 1),
                    ));
                  },
                ),
              ]),

              _groupLabel('PREFERENCES'),
              _group([
                _row(
                  icon: Icons.tune_rounded,
                  color: Colors.purpleAccent,
                  title: 'Optional features',
                  subtitle: _optionalSummary(expenseProvider),
                  onTap: () => _open(SettingsPage.optionalFeatures),
                ),
              ]),

              _groupLabel('DATA'),
              _group([
                _row(
                  icon: Icons.table_view_rounded,
                  color: Colors.green,
                  title: 'Export to spreadsheet',
                  subtitle: 'All expenses and income as a CSV file',
                  chevron: false,
                  onTap: () => ExportService.exportAndShare(context),
                ),
                _row(
                  icon: Icons.backup_rounded,
                  color: Colors.lightBlue,
                  title: 'Back up',
                  subtitle: 'Save everything to a file you can restore later',
                  chevron: false,
                  onTap: () => BackupService.createAndShareBackup(context),
                ),
                _row(
                  icon: Icons.restore_rounded,
                  color: Colors.indigoAccent,
                  title: 'Restore from backup',
                  subtitle: 'Replaces current data with a backup file',
                  chevron: false,
                  onTap: _pickAndRestoreBackup,
                ),
              ]),
              const SizedBox(height: 16),
              _group([
                _row(
                  icon: Icons.delete_forever_rounded,
                  color: Colors.redAccent,
                  title: 'Reset all data',
                  titleColor: Colors.redAccent,
                  chevron: false,
                  onTap: () =>
                      _showResetDataDialog(userProvider, expenseProvider),
                ),
              ]),

              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Vyaya v${AppPrefs.appVersion}  ·  ',
                    style: TextStyle(color: Colors.grey[700], fontSize: 12),
                  ),
                  InkWell(
                    onTap: _openReleases,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 2, vertical: 6),
                      child: Text(
                        'GitHub Releases',
                        style: TextStyle(
                          color: Colors.lightBlue[300],
                          fontSize: 12,
                          decoration: TextDecoration.underline,
                          decorationColor: Colors.lightBlue[300],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProfileCard(
      UserProvider userProvider, ExpenseProvider expenseProvider) {
    return _plainCard(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            child: Text(
                              userProvider.userName.isNotEmpty
                                  ? userProvider.userName[0].toUpperCase()
                                  : 'U',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _isEditingName
                                ? Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _nameController,
                                          style: const TextStyle(color: Colors.white),
                                          decoration: const InputDecoration(hintText: 'User Name'),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      ElevatedButton(
                                        onPressed: () async {
                                          final scaffoldMessenger = ScaffoldMessenger.of(context);
                                          final theme = Theme.of(context);
                                          final result = await _saveUserName();
                                          if (!mounted || result == null) return;
                                          scaffoldMessenger.showSnackBar(
                                            SnackBar(
                                              content: Text(result
                                                  ? 'Name updated successfully!'
                                                  : 'Failed to update name'),
                                              backgroundColor: result
                                                  ? theme.colorScheme.primary
                                                  : Colors.red,
                                              duration: const Duration(seconds: 1),
                                            ),
                                          );
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Theme.of(context).colorScheme.primary,
                                          foregroundColor: Colors.white,
                                          minimumSize: const Size(80, 40),
                                        ),
                                        child: const Text('Update Name'),
                                      ),
                                    ],
                                  )
                                : GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _isEditingName = true;
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2A2A2A),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.grey.withValues(alpha: 0.3),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                      Text(
                                        userProvider.userName.isEmpty ? 'Tap to set name' : userProvider.userName,
                                        style: TextStyle(
                                          color: userProvider.userName.isEmpty ? Colors.grey : Colors.white,
                                          fontSize: 16,
                                        ),
                                      ),
                                          Icon(
                                            Icons.edit,
                                            color: Colors.grey.withValues(alpha: 0.7),
                                            size: 16,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
  }

  // ==================== CATEGORIES PAGE ====================

  Widget _buildCategoriesPage() {
    // Back button leaves category selection mode before leaving the page.
    return PopScope(
      canPop: !_isCategorySelectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isCategorySelectionMode) _clearCategorySelection();
      },
      child: _subPage(
        'Categories',
        Consumer<ExpenseProvider>(
          builder: (context, expenseProvider, child) =>
              _buildCategoriesSection(expenseProvider),
        ),
      ),
    );
  }

  Widget _buildCategoriesSection(ExpenseProvider expenseProvider) {
    return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D0D0D),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.grey.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header with title and add button (or selection bar)
                      if (_isCategorySelectionMode)
                        _buildCategorySelectionBar(expenseProvider)
                      else
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Categories',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (expenseProvider.customCategories.isEmpty)
                            ElevatedButton.icon(
                              onPressed: _showAddCategoryDialog,
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Add Category'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(context).colorScheme.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Show empty state if no categories
                      if (expenseProvider.customCategories.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A2A2A),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.grey.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.category_outlined,
                                size: 48,
                                color: Colors.grey.withValues(alpha: 0.6),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No categories yet',
                                style: TextStyle(
                                  color: Colors.grey.withValues(alpha: 0.8),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Add your first category to organize your expenses',
                                style: TextStyle(
                                  color: Colors.grey.withValues(alpha: 0.6),
                                  fontSize: 14,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      else ...[
                        // Add Category Button (when categories exist)
                        ElevatedButton.icon(
                          onPressed: _showAddCategoryDialog,
                          icon: const Icon(Icons.add),
                          label: const Text('Add Category'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Custom Categories Grid (2 columns)
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 1.1,
                          ),
                          itemCount: expenseProvider.customCategories.length,
                          itemBuilder: (context, index) {
                            final category = expenseProvider.customCategories[index];
                            final budget = expenseProvider.getCustomCategoryBudget(category.id);
                            final spent = expenseProvider.getCustomCategoryExpenses(category.id);
                            final isOverBudget = budget > 0 && spent > budget;
                            final isSelected = _selectedCategoryIds.contains(category.id);

                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onLongPress: () => _toggleCategorySelection(category.id),
                              onTap: _isCategorySelectionMode
                                  ? () => _toggleCategorySelection(category.id)
                                  : () => _showAddCategoryDialog(
                                      editing: category),
                              child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.red.withValues(alpha: 0.12)
                                    : const Color(0xFF2A2A2A),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected
                                      ? Colors.redAccent
                                      : isOverBudget
                                          ? Colors.red.withValues(alpha: 0.5)
                                          : category.color.withValues(alpha: 0.3),
                                  width: isSelected || isOverBudget ? 2 : 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Top row: icon + actions
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: category.color.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Center(
                                          child: Text(
                                            category.icon,
                                            style: const TextStyle(fontSize: 20),
                                          ),
                                        ),
                                      ),
                                      if (_isCategorySelectionMode)
                                        Icon(
                                          isSelected
                                              ? Icons.check_circle
                                              : Icons.radio_button_unchecked,
                                          color: isSelected ? Colors.redAccent : Colors.grey,
                                          size: 22,
                                        )
                                      else
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          GestureDetector(
                                            onTap: () => _showAddCategoryDialog(
                                                editing: category),
                                            child: const Icon(Icons.edit, color: Colors.grey, size: 18),
                                          ),
                                          const SizedBox(width: 8),
                                          GestureDetector(
                                            onTap: () => _startCategoryDelete(expenseProvider, [category]),
                                            child: Icon(Icons.delete, color: Colors.grey.withValues(alpha: 0.7), size: 18),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  // Category name
                                  Text(
                                    category.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const Spacer(),
                                  // Budget info
                                  Text(
                                    budget > 0
                                        ? '₹${spent.toStringAsFixed(0)} / ₹${budget.toStringAsFixed(0)}'
                                        : '₹${spent.toStringAsFixed(0)} spent',
                                    style: TextStyle(
                                      color: isOverBudget ? Colors.red : Colors.grey,
                                      fontSize: 12,
                                      fontWeight: isOverBudget ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                  if (budget > 0) ...[
                                    const SizedBox(height: 6),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: (spent / budget).clamp(0.0, 1.0),
                                        minHeight: 4,
                                        backgroundColor: Colors.grey.withValues(alpha: 0.3),
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          isOverBudget ? Colors.red : category.color,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                );
  }

  /// Add a category, or edit [editing] (name, icon, colour, monthly limit).
  void _showAddCategoryDialog({ExpenseCategory? editing}) {
    final provider = context.read<ExpenseProvider>();
    final isEdit = editing != null;
    _categoryNameController.text = editing?.name ?? '';
    String selectedIcon = editing?.icon ?? '📦';
    Color selectedColor = editing?.color ?? _categoryColors[8];
    // Open the icon group that holds the current icon.
    String group = _categoryEmojiGroups.entries
            .where((e) => e.value.contains(selectedIcon))
            .map((e) => e.key)
            .firstOrNull ??
        _categoryEmojiGroups.keys.first;
    final inGroups =
        _categoryEmojiGroups.values.any((g) => g.contains(selectedIcon));
    final customIcon =
        TextEditingController(text: isEdit && !inGroups ? selectedIcon : '');
    // Keep a colour picked before the palette existed selectable.
    final colors = [
      if (isEdit &&
          !_categoryColors.any((c) => c.toARGB32() == selectedColor.toARGB32()))
        selectedColor,
      ..._categoryColors,
    ];
    // "Other" catches expenses whose category was deleted and "Saved" is
    // managed by month-end savings, so their names stay fixed.
    final nameLocked = editing != null &&
        (editing.name == 'Other' ||
            editing.name == ExpenseProvider.savedCategoryName);
    final existingLimit =
        editing != null ? provider.getCustomCategoryBudget(editing.id) : 0.0;
    final limitController = TextEditingController(
        text: existingLimit > 0 ? existingLimit.toStringAsFixed(0) : '');
    String? nameError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Padding(
          // Lift the sheet above the keyboard.
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  isEdit ? 'Edit Category' : 'New Category',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
                // Room above the first field so its floating label isn't cut.
                const SizedBox(height: 18),
                // Category Name Input
                TextField(
                  controller: _categoryNameController,
                  enabled: !nameLocked,
                  textCapitalization: TextCapitalization.words,
                  style: TextStyle(
                      color: nameLocked ? Colors.grey : Colors.white),
                  onChanged: (_) {
                    if (nameError != null) setState(() => nameError = null);
                  },
                  decoration: InputDecoration(
                    errorText: nameError,
                    helperText: nameLocked
                        ? 'This category\'s name is used by the app, so it can\'t change'
                        : isEdit
                            ? 'Renaming updates every expense in it'
                            : null,
                    helperMaxLines: 2,
                    helperStyle:
                        const TextStyle(color: Colors.grey, fontSize: 11),
                    labelText: 'Category Name',
                    labelStyle: const TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.grey.withValues(alpha: 0.5),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Live preview on the left, monthly limit beside it.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: selectedColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: selectedColor, width: 1.5),
                      ),
                      child: Center(
                        child: Text(selectedIcon,
                            style: const TextStyle(fontSize: 28)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: limitController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Monthly limit',
                          labelStyle: const TextStyle(color: Colors.grey),
                          hintText: 'Optional',
                          hintStyle: const TextStyle(color: Colors.grey),
                          prefixText: '₹ ',
                          helperText: 'Alerts you when a month goes over it',
                          helperMaxLines: 2,
                          helperStyle:
                              const TextStyle(color: Colors.grey, fontSize: 11),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: Colors.grey.withValues(alpha: 0.5)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Title on the left, icon groups scrolling beside it.
                Row(
                  children: [
                    const Text(
                      'Choose Icon',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ScrollArrowsRow(
                        height: 36,
                        fadeColor: const Color(0xFF1A1A1A),
                        initialIndex:
                            _categoryEmojiGroups.keys.toList().indexOf(group),
                        children: [
                      for (final g in _categoryEmojiGroups.keys)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(g),
                            selected: g == group,
                            showCheckmark: false,
                            onSelected: (_) => setState(() => group = g),
                            labelStyle: TextStyle(
                              fontSize: 12,
                              color: g == group ? Colors.black : Colors.white70,
                            ),
                            selectedColor:
                                Theme.of(context).colorScheme.primary,
                            backgroundColor: const Color(0xFF2A2A2A),
                            side: BorderSide.none,
                            shape: const StadiumBorder(),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _categoryEmojiGroups[group]!.map((icon) {
                    final isSelected = icon == selectedIcon;
                    return GestureDetector(
                      onTap: () => setState(() {
                        selectedIcon = icon;
                        customIcon.clear();
                      }),
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? selectedColor.withValues(alpha: 0.3)
                              : Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? selectedColor
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Text(icon,
                              style: const TextStyle(fontSize: 22)),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                // Any emoji from the keyboard, shown in the same tile.
                TextField(
                  controller: customIcon,
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Or type any emoji',
                    hintStyle:
                        const TextStyle(color: Colors.grey, fontSize: 14),
                    prefixIcon: const Icon(Icons.emoji_emotions_outlined,
                        color: Colors.grey, size: 20),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: Colors.grey.withValues(alpha: 0.5)),
                    ),
                  ),
                  onChanged: (value) {
                    final emoji = _singleEmoji(value);
                    if (emoji == null) return;
                    setState(() => selectedIcon = emoji);
                    if (customIcon.text != emoji) {
                      customIcon.value = TextEditingValue(
                        text: emoji,
                        selection:
                            TextSelection.collapsed(offset: emoji.length),
                      );
                    }
                  },
                ),
                const SizedBox(height: 20),

                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Choose Color',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: colors.map((color) {
                    final isSelected =
                        color.toARGB32() == selectedColor.toARGB32();
                    return GestureDetector(
                      onTap: () => setState(() => selectedColor = color),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? Colors.white
                                : Colors.transparent,
                            width: 3,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: color.withValues(alpha: 0.5),
                                    blurRadius: 10,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                        child: isSelected
                            ? const Icon(Icons.check,
                                color: Colors.white, size: 18)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
              onPressed: _isAddingCategory ? null : () async {
                if (editing != null) {
                  final navigator = Navigator.of(context);
                  final messenger = ScaffoldMessenger.of(context);
                  final capture = context.read<CaptureProvider>();
                  final oldName = editing.name;
                  final name = _categoryNameController.text.trim();
                  if (name.isEmpty) {
                    setState(() => nameError = 'Enter a name');
                    return;
                  }
                  if (name.toLowerCase() != oldName.toLowerCase() &&
                      provider.categories.any((c) =>
                          c.id != editing.id &&
                          c.name.toLowerCase() == name.toLowerCase())) {
                    setState(() => nameError = 'You already have "$name"');
                    return;
                  }
                  setState(() => _isAddingCategory = true);
                  try {
                    await provider.updateCategory(
                      editing.id,
                      name: name,
                      icon: selectedIcon,
                      color: selectedColor,
                    );
                    if (name != oldName) {
                      await capture.renameCategory(oldName, name);
                    }
                    final limit = double.tryParse(
                            limitController.text.replaceAll(',', '')) ??
                        0;
                    if (limit != existingLimit) {
                      await provider.setCustomCategoryBudget(
                          editing.id, limit < 0 ? 0 : limit);
                    }
                    navigator.pop();
                    messenger.showSnackBar(SnackBar(
                      content: Text('Saved "$name"'),
                      duration: const Duration(seconds: 1),
                    ));
                  } catch (e) {
                    messenger.showSnackBar(
                        SnackBar(content: Text('Couldn\'t save: $e')));
                  } finally {
                    setState(() => _isAddingCategory = false);
                  }
                  return;
                }
                final newName = _categoryNameController.text.trim();
                if (newName.isEmpty) {
                  setState(() => nameError = 'Enter a name');
                  return;
                }
                if (provider.categories.any(
                    (c) => c.name.toLowerCase() == newName.toLowerCase())) {
                  setState(() => nameError = 'You already have "$newName"');
                  return;
                }
                {
                  setState(() {
                    _isAddingCategory = true;
                  });

                  try {
                    final newCategory = ExpenseCategory(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      name: newName,
                      icon: selectedIcon,
                      colorHex: '#${(selectedColor.r * 255.0).round().toRadixString(16).padLeft(2, '0')}${(selectedColor.g * 255.0).round().toRadixString(16).padLeft(2, '0')}${(selectedColor.b * 255.0).round().toRadixString(16).padLeft(2, '0')}',
                      isDefault: false,
                    );

                    final navigator = Navigator.of(context);
                    final scaffoldMessenger = ScaffoldMessenger.of(context);
                    final theme = Theme.of(context);
                    
                    await provider.addCustomCategory(newCategory);
                    final limit = double.tryParse(
                            limitController.text.replaceAll(',', '')) ??
                        0;
                    if (limit > 0) {
                      await provider.setCustomCategoryBudget(
                          newCategory.id, limit);
                    }
                    navigator.pop();

                    if (mounted) {
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text('Category "$newName" added'),
                          backgroundColor: theme.colorScheme.primary,
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  } finally {
                    setState(() {
                      _isAddingCategory = false;
                    });
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _isAddingCategory 
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(isEdit ? 'Save' : 'Add'),
            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // customIcon / limitController aren't disposed here on purpose: the
    // sheet's future completes when it starts closing, while its text
    // fields are still on screen, and disposing then crashes the frame.
    // They're local and get garbage-collected with the dialog.
  }

  Widget _buildCategorySelectionBar(ExpenseProvider provider) {
    final total = provider.customCategories.length;
    final allSelected = _selectedCategoryIds.length == total;
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          tooltip: 'Cancel',
          onPressed: _clearCategorySelection,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '${_selectedCategoryIds.length} selected',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        TextButton(
          onPressed: () => setState(() {
            if (allSelected) {
              _selectedCategoryIds.clear();
            } else {
              _selectedCategoryIds
                  .addAll(provider.customCategories.map((c) => c.id));
            }
          }),
          child: Text(allSelected ? 'Deselect all' : 'Select all'),
        ),
        IconButton(
          icon: const Icon(Icons.delete, color: Colors.redAccent),
          tooltip: 'Delete selected',
          onPressed: () => _startCategoryDelete(
            provider,
            provider.customCategories
                .where((c) => _selectedCategoryIds.contains(c.id))
                .toList(),
          ),
        ),
      ],
    );
  }

  /// Delete flow shared by the single delete icon and multi-select:
  /// 1) confirm, 2) if any category has logged expenses, confirm again with
  /// per-category "Move to" options, 3) delete (+ reassign).
  Future<void> _startCategoryDelete(
      ExpenseProvider provider, List<ExpenseCategory> targets) async {
    // "Saved" holds the month-end savings; the app keeps it.
    if (targets.any((c) => c.name == ExpenseProvider.savedCategoryName)) {
      targets = targets
          .where((c) => c.name != ExpenseProvider.savedCategoryName)
          .toList();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('"Saved" holds your month-end savings, so it stays')));
    }
    if (targets.isEmpty) return;
    final label = targets.length == 1
        ? '"${targets.first.name}"'
        : '${targets.length} categories';
    final defaultCount = targets.where((c) => c.isDefault).length;

    // Step 1: basic confirmation
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: Text('Delete $label?',
            style: const TextStyle(color: Colors.white)),
        content: Text(
          '${targets.length > 1 ? '${targets.map((c) => c.name).join(', ')}\n\n' : ''}'
          '${defaultCount > 0 ? 'Includes $defaultCount default ${defaultCount == 1 ? 'category' : 'categories'}.\n\n' : ''}'
          'This cannot be undone.',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Step 2: check logged expenses (full storage)
    final counts =
        await provider.getExpenseCountsForCategories(targets.map((c) => c.name));
    if (!mounted) return;

    Map<String, String> reassign = const {};
    if (counts.isNotEmpty) {
      final targetIds = targets.map((c) => c.id).toSet();
      final remaining = provider.customCategories
          .where((c) => !targetIds.contains(c.id))
          .toList();
      final affected = targets.where((c) => counts.containsKey(c.name)).toList();

      final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (ctx) => _LoggedExpensesDialog(
          affected: affected,
          counts: counts,
          remaining: remaining,
        ),
      );
      if (result == null || !mounted) return; // cancelled
      reassign = result;
    }

    // Step 3: delete
    final messenger = ScaffoldMessenger.of(context);
    final capture = context.read<CaptureProvider>();
    try {
      await provider.removeCustomCategories(
        targets.map((c) => c.id).toSet(),
        reassign: reassign,
      );
      // Detected payments and learned payee rules follow the move too.
      for (final e in reassign.entries) {
        await capture.renameCategory(e.key, e.value);
      }
      if (!mounted) return;
      _clearCategorySelection();
      final moved = reassign.keys.fold<int>(0, (s, k) => s + (counts[k] ?? 0));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Deleted $label'
            '${moved > 0 ? ' · moved $moved ${moved == 1 ? 'entry' : 'entries'}' : ''}',
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    }
  }

  // ==================== AUTO-DETECT PAYMENTS ====================

  Widget _buildAutoDetectSection() {
    return Consumer<CaptureProvider>(
      builder: (context, cap, child) {
        Widget sourceRow({
          required IconData icon,
          required Color color,
          required String title,
          required String subtitle,
          required bool on,
          required VoidCallback onTap,
        }) {
          return ListTile(
            contentPadding: EdgeInsets.zero,
            onTap: onTap,
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color),
            ),
            title: Text(title, style: const TextStyle(color: Colors.white)),
            subtitle: Text(subtitle, style: const TextStyle(color: Colors.grey)),
            trailing: on
                ? Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('On',
                        style: TextStyle(
                            color: Colors.green, fontWeight: FontWeight.bold)),
                  )
                : const Text('Turn on',
                    style: TextStyle(
                        color: Colors.blueAccent, fontWeight: FontWeight.bold)),
          );
        }

        return _plainCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Log payments automatically from payment app notifications and bank SMS. Everything is read and stored only on your phone.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 8),
              sourceRow(
                icon: Icons.notifications_active_outlined,
                color: Colors.purple,
                title: 'Payment app notifications',
                subtitle: 'PhonePe, Google Pay, Paytm, BHIM, CRED…',
                on: cap.notificationAccess,
                onTap: cap.openNotificationAccess,
              ),
              sourceRow(
                icon: Icons.sms_outlined,
                color: Colors.blue,
                title: 'Bank SMS',
                subtitle: 'Debit and credit alerts from your bank',
                on: cap.smsPermission,
                onTap: () async {
                  if (cap.smsPermission) {
                    await cap.openAppDetails(); // turn off from App info
                    return;
                  }
                  final messenger = ScaffoldMessenger.of(context);
                  final ok = await cap.requestSmsPermission();
                  if (!ok) {
                    messenger.showSnackBar(const SnackBar(
                      content: Text(
                          'SMS permission not granted. If Android blocks it, open App info → ⋮ → Allow restricted settings.'),
                    ));
                  }
                },
              ),
              if (cap.smsPermission)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history, color: Colors.grey),
                  title: const Text('Import past bank SMS',
                      style: TextStyle(color: Colors.white)),
                  subtitle: const Text(
                      'Pick how far back. Imported payments always wait for your review',
                      style: TextStyle(color: Colors.grey)),
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final since = await _pickImportStart();
                    if (since == null) return;
                    messenger.showSnackBar(
                        const SnackBar(content: Text('Importing…')));
                    final n = await cap.importSmsSince(since);
                    messenger.hideCurrentSnackBar();
                    messenger.showSnackBar(SnackBar(
                      content: Text(n == 0
                          ? 'No new payments found'
                          : 'Found $n payment${n == 1 ? '' : 's'}, see Detected payments'),
                    ));
                  },
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Add automatically',
                    style: TextStyle(color: Colors.white)),
                subtitle: Text(
                  cap.autoMode
                      ? 'Clear matches are logged right away; anything unclear waits for review'
                      : 'Every detected payment waits for you to review',
                  style: const TextStyle(color: Colors.grey),
                ),
                value: cap.autoMode,
                onChanged: cap.setAutoMode,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.fact_check_outlined,
                    color: Colors.amber),
                title: const Text('Detected payments',
                    style: TextStyle(color: Colors.white)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (cap.pendingCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('${cap.pendingCount}',
                            style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold)),
                      ),
                    const Icon(Icons.chevron_right, color: Colors.grey),
                  ],
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const DetectedPaymentsScreen()),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading:
                    const Icon(Icons.battery_saver_outlined, color: Colors.grey),
                title: const Text('Keep detection running',
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                    'Exclude Vyaya from battery optimisation. Recommended on OnePlus, Xiaomi and similar phones.',
                    style: TextStyle(color: Colors.grey)),
                onTap: cap.requestBatteryExemption,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.help_outline, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Switch greyed out in Notification access? Open App info → ⋮ → "Allow restricted settings", then try again.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: cap.openAppDetails,
                    child: const Text('App info'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ==================== ACCOUNTS SECTION ====================

  Widget _buildAccountsSection(ExpenseProvider expenseProvider) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with title and add button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Bank Accounts',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _showAddAccountDialog,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Show empty state if no accounts
          if (expenseProvider.accounts.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.grey.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.account_balance_outlined,
                    size: 48,
                    color: Colors.grey.withValues(alpha: 0.6),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No accounts yet',
                    style: TextStyle(
                      color: Colors.grey.withValues(alpha: 0.8),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add your bank accounts to track which account you spend from',
                    style: TextStyle(
                      color: Colors.grey.withValues(alpha: 0.6),
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            // Accounts List
            ...expenseProvider.accounts.map((account) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showAddAccountDialog(editing: account),
                child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: account.isDefault
                        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)
                        : Colors.grey.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            account.isCreditCard
                                ? Icons.credit_card
                                : Icons.account_balance,
                            color: account.isDefault
                                ? Theme.of(context).colorScheme.primary
                                : (account.isCreditCard
                                      ? Colors.orange
                                      : Colors.grey),
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  account.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 16,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  account.type.label,
                                  style: TextStyle(
                                    color: account.isCreditCard
                                        ? Colors.orange.withValues(alpha: 0.8)
                                        : Colors.grey.withValues(alpha: 0.8),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (account.isDefault) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Default',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        if (!account.isDefault)
                          IconButton(
                            onPressed: () => _setDefaultAccount(account.id),
                            icon: const Icon(
                              Icons.star_border,
                              color: Colors.grey,
                              size: 20,
                            ),
                            tooltip: 'Set as default',
                          ),
                        IconButton(
                          onPressed: () =>
                              _showAddAccountDialog(editing: account),
                          icon: const Icon(
                            Icons.edit,
                            color: Colors.grey,
                            size: 20,
                          ),
                          tooltip: 'Edit',
                        ),
                        IconButton(
                          onPressed: () => _showDeleteAccountDialog(account),
                          icon: const Icon(
                            Icons.delete,
                            color: Colors.red,
                            size: 20,
                          ),
                          tooltip: 'Delete',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              );
            }),
        ],
      ),
    );
  }

  /// Add an account, or rename / retype [editing].
  void _showAddAccountDialog({BankAccount? editing}) {
    final accountNameController =
        TextEditingController(text: editing?.name ?? '');
    AccountType selectedType = editing?.type ?? AccountType.savings;
    String? nameError;
    // "Current" isn't offered any more; keep it only for an account that
    // already uses it.
    final types = AccountType.values
        .where((t) => t != AccountType.current || editing?.type == t)
        .toList();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          title: Text(
            editing != null ? 'Edit Account' : 'Add Account',
            style: const TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: accountNameController,
                style: const TextStyle(color: Colors.white),
                autofocus: editing == null,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) {
                  if (nameError != null) {
                    setDialogState(() => nameError = null);
                  }
                },
                decoration: InputDecoration(
                  errorText: nameError,
                  helperText:
                      'Tip: add the last 4 digits (e.g. "ICICI 1234") so auto-detect can tell your accounts apart',
                  helperMaxLines: 2,
                  helperStyle:
                      const TextStyle(color: Colors.grey, fontSize: 11),
                  hintText: 'e.g., SBI, HDFC, Axis',
                  hintStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: const Color(0xFF1A1A1A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: Icon(
                    selectedType == AccountType.creditCard
                        ? Icons.credit_card
                        : Icons.account_balance,
                    color: Colors.grey,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Account type selector
              Row(
                children: types.map((type) {
                  final isSelected = selectedType == type;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setDialogState(() {
                          selectedType = type;
                        });
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? (type == AccountType.creditCard
                                    ? Colors.orange.withValues(alpha: 0.2)
                                    : Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.2))
                              : const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? (type == AccountType.creditCard
                                      ? Colors.orange
                                      : Theme.of(context).colorScheme.primary)
                                : Colors.grey.withValues(alpha: 0.3),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              type == AccountType.creditCard
                                  ? Icons.credit_card
                                  : Icons.account_balance,
                              color: isSelected
                                  ? (type == AccountType.creditCard
                                        ? Colors.orange
                                        : Theme.of(context)
                                            .colorScheme
                                            .primary)
                                  : Colors.grey,
                              size: 18,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              type.label,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.grey[400],
                                fontSize: 11,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = accountNameController.text.trim();
                final navigator = Navigator.of(context);
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                final provider = context.read<ExpenseProvider>();
                if (name.isEmpty) {
                  setDialogState(() => nameError = 'Enter a name');
                  return;
                }
                if (provider.accounts.any((a) =>
                    a.id != editing?.id &&
                    a.name.toLowerCase() == name.toLowerCase())) {
                  setDialogState(() => nameError = 'You already have "$name"');
                  return;
                }
                if (editing != null) {
                  await provider.updateAccount(
                      editing.copyWith(name: name, type: selectedType));
                  navigator.pop();
                  scaffoldMessenger.showSnackBar(SnackBar(
                    content: Text('Saved "$name"'),
                    duration: const Duration(seconds: 1),
                  ));
                  return;
                }

                final newAccount = BankAccount(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: name,
                  isDefault: provider.accounts.isEmpty,
                  type: selectedType,
                );

                await provider.addAccount(newAccount);
                navigator.pop();

                if (mounted) {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text(
                          '${selectedType.label} "$name" added successfully!'),
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      duration: const Duration(seconds: 1),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
              ),
              child: Text(editing != null ? 'Save' : 'Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setDefaultAccount(String accountId) async {
    final provider = context.read<ExpenseProvider>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    await provider.setDefaultAccount(accountId);

    if (mounted) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: const Text('Default account updated!'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  // ==================== DATA MANAGEMENT SECTION ====================

  Future<void> _pickAndRestoreBackup() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;

    if (!mounted) return;

    // Confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text(
          'Restore Backup?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will replace ALL current data with the data from the backup file.\n\nYour current data will be lost. Continue?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
            child: const Text('Restore',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await BackupService.restoreFromFile(context, path);
  }

  void _showResetDataDialog(
    UserProvider userProvider,
    ExpenseProvider expenseProvider,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text(
          'Reset All Data?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will permanently delete ALL your data including expenses, income, categories, and settings.\n\nThis action cannot be undone. Consider exporting your data first.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);

              final captureProvider = context.read<CaptureProvider>();
              final navigator = Navigator.of(context);

              await LocalStore.resetAllData();
              expenseProvider.clearUserData();
              await userProvider.clearUser();

              // Start fresh right away (same as a first launch) instead of
              // leaving an empty app until the next restart.
              await userProvider.registerUser('LocalUser');
              await userProvider.initializeExpenseProvider(expenseProvider);
              await captureProvider.reload();
              // Optional features were wiped too: cancel the reminder.
              await AppPrefs.instance.reloadAfterDataChange(
                  NotificationService.syncDailyReminder);

              if (mounted) {
                navigator.popUntil((route) => route.isFirst);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reset Everything',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// Month-end savings switch: on puts each month's leftover into "Saved",
  /// off carries it into the next month as income. Applies from this month.
  Future<void> _toggleMonthEndSavings(ExpenseProvider provider, bool on) async {
    final messenger = ScaffoldMessenger.of(context);
    await provider.setMonthEndSavings(on);
    messenger.showSnackBar(SnackBar(
      content: Text(on
          ? 'From this month, the leftover goes into "Saved"'
          : 'From this month, the leftover carries into next month as income'),
    ));
  }

  // ==================== OPTIONAL FEATURES (page) ====================

  /// "3 on · Month-end savings" style summary for the hub row.
  String _optionalSummary(ExpenseProvider ep) {
    final p = AppPrefs.instance;
    final on = [
      p.hideHomeTotals,
      p.showSpendingPace,
      p.reminderMinutes != null,
      p.autoFocusAmount,
      p.rememberLastUsed,
      p.lateNightIsYesterday,
      p.savingsGoal != null,
      p.largePaymentAlert != null,
      p.weeklySummary,
      p.monthlyRecap,
      p.billReminders,
      p.earlyWarnings,
      p.appLockEnabled,
    ].where((v) => v).length;
    final savings = ep.monthEndSavingsEnabled ? 'Saving leftover' : 'Carrying leftover';
    return '$savings · ${on == 0 ? 'extras off' : '$on extra${on == 1 ? '' : 's'} on'}';
  }

  Widget _buildOptionalFeatures(ExpenseProvider expenseProvider) {
    final prefs = AppPrefs.instance;
    final reminder = prefs.reminderMinutes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
              _groupLabel('MONEY'),
              _group([
                _row(
                  icon: Icons.savings_outlined,
                  color: Colors.green,
                  title: 'Month-end savings',
                  subtitle: expenseProvider.monthEndSavingsEnabled
                      ? 'Leftover each month goes into "Saved"'
                      : 'Off · leftover carries into next month as income',
                  chevron: false,
                  onTap: () => _toggleMonthEndSavings(
                      expenseProvider, !expenseProvider.monthEndSavingsEnabled),
                  trailing: Switch(
                    value: expenseProvider.monthEndSavingsEnabled,
                    onChanged: (v) => _toggleMonthEndSavings(expenseProvider, v),
                  ),
                ),
                _row(
                  icon: Icons.date_range_rounded,
                  color: Colors.lightBlue,
                  title: 'Week starts on',
                  subtitle: prefs.weekStartsMonday
                      ? 'Weeks run Monday to Sunday'
                      : 'Weeks run Sunday to Saturday',
                  chevron: false,
                  onTap: () =>
                      prefs.setWeekStartsMonday(!prefs.weekStartsMonday),
                  trailing: _pill(prefs.weekStartsMonday ? 'Monday' : 'Sunday'),
                ),
              ]),

              _groupLabel('HOME'),
              _group([
                _row(
                  icon: Icons.visibility_off_outlined,
                  color: Colors.blueGrey,
                  title: 'Hide totals on Home',
                  subtitle: 'Mask spent, income and left · tap the amount to peek',
                  chevron: false,
                  onTap: () => prefs.setHideHomeTotals(!prefs.hideHomeTotals),
                  trailing: Switch(
                    value: prefs.hideHomeTotals,
                    onChanged: prefs.setHideHomeTotals,
                  ),
                ),
                _row(
                  icon: Icons.trending_down_rounded,
                  color: Colors.greenAccent,
                  title: 'Spending pace on Home',
                  subtitle: 'Today\'s spend and how much you can spend per day',
                  chevron: false,
                  onTap: () =>
                      prefs.setShowSpendingPace(!prefs.showSpendingPace),
                  trailing: Switch(
                    value: prefs.showSpendingPace,
                    onChanged: prefs.setShowSpendingPace,
                  ),
                ),
                _row(
                  icon: Icons.swipe_up_rounded,
                  color: Colors.purpleAccent,
                  title: 'Quick actions',
                  subtitle:
                      'Swipe up on the nav bar · ${prefs.shortcutsInSheet.map(_shortcutName).join(' & ')}',
                  onTap: _showQuickActionsPicker,
                ),
              ]),

              _groupLabel('ADDING ENTRIES'),
              _group([
                _row(
                  icon: Icons.keyboard_outlined,
                  color: Colors.tealAccent,
                  title: 'Open keyboard on Add',
                  subtitle: 'Add Expense / Income starts on the amount',
                  chevron: false,
                  onTap: () => prefs.setAutoFocusAmount(!prefs.autoFocusAmount),
                  trailing: Switch(
                    value: prefs.autoFocusAmount,
                    onChanged: prefs.setAutoFocusAmount,
                  ),
                ),
                _row(
                  icon: Icons.history_rounded,
                  color: Colors.orange,
                  title: 'Remember last category',
                  subtitle: 'Add Expense starts with the category and account you used last',
                  chevron: false,
                  onTap: () =>
                      prefs.setRememberLastUsed(!prefs.rememberLastUsed),
                  trailing: Switch(
                    value: prefs.rememberLastUsed,
                    onChanged: prefs.setRememberLastUsed,
                  ),
                ),
                _row(
                  icon: Icons.bedtime_outlined,
                  color: Colors.indigoAccent,
                  title: 'Late night counts as yesterday',
                  subtitle: 'Entries added before ${AppPrefs.lateNightCutoffHour} AM are dated the previous day',
                  chevron: false,
                  onTap: () => prefs
                      .setLateNightIsYesterday(!prefs.lateNightIsYesterday),
                  trailing: Switch(
                    value: prefs.lateNightIsYesterday,
                    onChanged: prefs.setLateNightIsYesterday,
                  ),
                ),
              ]),

              _groupLabel('ALERTS & GOALS'),
              _group([
                _row(
                  icon: Icons.flag_outlined,
                  color: Colors.tealAccent,
                  title: 'Monthly savings goal',
                  subtitle: prefs.savingsGoal == null
                      ? 'Track how much you want left each month'
                      : '₹${prefs.savingsGoal!.toStringAsFixed(0)} a month · shown in Savings',
                  onTap: () => _editAmountPref(
                    title: 'Monthly savings goal',
                    hint: 'How much you want left at month end',
                    current: prefs.savingsGoal,
                    onSave: prefs.setSavingsGoal,
                  ),
                ),
                _row(
                  icon: Icons.warning_amber_rounded,
                  color: Colors.deepOrangeAccent,
                  title: 'Large payment alert',
                  subtitle: prefs.largePaymentAlert == null
                      ? 'Get notified about big payments (helps spot fraud)'
                      : 'For payments of ₹${prefs.largePaymentAlert!.toStringAsFixed(0)} or more · tap to change',
                  chevron: false,
                  onTap: () => _editAmountPref(
                    title: 'Large payment alert',
                    hint: 'Notify me for payments of at least',
                    current: prefs.largePaymentAlert ?? 5000,
                    onSave: prefs.setLargePaymentAlert,
                  ),
                  trailing: Switch(
                    value: prefs.largePaymentAlert != null,
                    onChanged: (on) => on
                        ? _editAmountPref(
                            title: 'Large payment alert',
                            hint: 'Notify me for payments of at least',
                            current: 5000,
                            onSave: prefs.setLargePaymentAlert,
                          )
                        : prefs.setLargePaymentAlert(null),
                  ),
                ),
              ]),

              _groupLabel('PRIVACY'),
              _group([
                _row(
                  icon: Icons.lock_outline_rounded,
                  color: Colors.lightBlueAccent,
                  title: 'App lock',
                  subtitle: prefs.appLockEnabled
                      ? 'PIN on opening and after 30 s away · tap to change PIN'
                      : 'Ask for a PIN when Vyaya opens',
                  chevron: false,
                  onTap: prefs.appLockEnabled
                      ? _changePin
                      : () => _setAppLock(true),
                  trailing: Switch(
                    value: prefs.appLockEnabled,
                    onChanged: _setAppLock,
                  ),
                ),
              ]),

              _groupLabel('NOTIFICATIONS & SUMMARIES'),
              _group([
                _row(
                  icon: Icons.calendar_view_week_rounded,
                  color: Colors.lightGreen,
                  title: 'Weekly summary',
                  subtitle: 'Sundays at 1 PM: last week\'s spending, top category, vs the week before',
                  chevron: false,
                  onTap: () => prefs.setWeeklySummary(!prefs.weeklySummary),
                  trailing: Switch(
                    value: prefs.weeklySummary,
                    onChanged: prefs.setWeeklySummary,
                  ),
                ),
                _row(
                  icon: Icons.insights_rounded,
                  color: Colors.purpleAccent,
                  title: 'Monthly recap',
                  subtitle: 'On the 1st at 10 AM: spent, income and what was saved',
                  chevron: false,
                  onTap: () => prefs.setMonthlyRecap(!prefs.monthlyRecap),
                  trailing: Switch(
                    value: prefs.monthlyRecap,
                    onChanged: prefs.setMonthlyRecap,
                  ),
                ),
                _row(
                  icon: Icons.event_note_rounded,
                  color: Colors.amber,
                  title: 'Bill reminders',
                  subtitle: 'The day before a recurring expense (rent, subscriptions…)',
                  chevron: false,
                  onTap: () => prefs.setBillReminders(!prefs.billReminders),
                  trailing: Switch(
                    value: prefs.billReminders,
                    onChanged: prefs.setBillReminders,
                  ),
                ),
                _row(
                  icon: Icons.speed_rounded,
                  color: Colors.orangeAccent,
                  title: 'Early warnings',
                  subtitle: 'Alert at 80% of your income or a category limit, before you go over',
                  chevron: false,
                  onTap: () => prefs.setEarlyWarnings(!prefs.earlyWarnings),
                  trailing: Switch(
                    value: prefs.earlyWarnings,
                    onChanged: prefs.setEarlyWarnings,
                  ),
                ),
                _row(
                  icon: Icons.alarm_rounded,
                  color: Colors.orangeAccent,
                  title: 'Daily reminder',
                  subtitle: reminder == null
                      ? 'A nudge to log the day\'s spending'
                      : 'Every day at ${_formatMinutes(reminder)} · tap to change',
                  chevron: false,
                  onTap: () => reminder == null
                      ? _setReminder(true)
                      : _pickReminderTime(reminder),
                  trailing: Switch(
                    value: reminder != null,
                    onChanged: _setReminder,
                  ),
                ),
              ]),
      ],
    );
  }

  // ==================== OPTIONAL FEATURES ====================

  static String _shortcutName(QuickShortcut s) => switch (s) {
        QuickShortcut.detected => 'Detected Payments',
        QuickShortcut.lentBorrowed => 'Lent & Borrowed',
        QuickShortcut.recurring => 'Recurring',
      };

  static IconData _shortcutIcon(QuickShortcut s) => switch (s) {
        QuickShortcut.detected => Icons.bolt_rounded,
        QuickShortcut.lentBorrowed => Icons.handshake_outlined,
        QuickShortcut.recurring => Icons.repeat_rounded,
      };

  static Color _shortcutColor(QuickShortcut s) => switch (s) {
        QuickShortcut.detected => Colors.teal,
        QuickShortcut.lentBorrowed => Colors.amber,
        QuickShortcut.recurring => Colors.cyan,
      };

  /// Settings row for the shortcut that's not in the quick actions sheet.
  Widget _shortcutRow(
      QuickShortcut s, ExpenseProvider ep, CaptureProvider cap) {
    final Widget screen;
    final String subtitle;
    Widget? trailing;
    switch (s) {
      case QuickShortcut.recurring:
        final active = ep.recurringEntries.where((r) => r.active).length;
        screen = const RecurringScreen();
        subtitle = active == 0
            ? 'Weekly, monthly or yearly income and bills'
            : '$active active';
      case QuickShortcut.detected:
        screen = const DetectedPaymentsScreen();
        subtitle = 'From bank SMS & payment apps';
        if (cap.pendingCount > 0) {
          trailing = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _badge(cap.pendingCount),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          );
        }
      case QuickShortcut.lentBorrowed:
        screen = const LentBorrowedScreen();
        subtitle = 'Money with friends';
    }
    return _row(
      icon: _shortcutIcon(s),
      color: _shortcutColor(s),
      title: _shortcutName(s),
      subtitle: subtitle,
      trailing: trailing,
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (context) => screen)),
    );
  }

  Widget _pill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.lightBlue.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text,
            style: const TextStyle(
                color: Colors.lightBlue,
                fontSize: 12.5,
                fontWeight: FontWeight.w600)),
      );

  /// Picks which of the three shortcuts stays in Settings; the other two go
  /// in the swipe-up sheet between Analytics and Settings.
  void _showQuickActionsPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => ListenableBuilder(
        listenable: AppPrefs.instance,
        builder: (context, _) {
          final inSettings = AppPrefs.instance.shortcutInSettings;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[700],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Quick actions',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(
                    'Swiping up on the nav bar shows Analytics, two shortcuts and Settings. Choose the one to keep in Settings instead.',
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  for (final s in QuickShortcut.values)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      onTap: () => AppPrefs.instance.setShortcutInSettings(s),
                      leading: _tileIcon(_shortcutIcon(s), _shortcutColor(s)),
                      title: Text(_shortcutName(s),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500)),
                      subtitle: Text(
                          s == inSettings ? 'In Settings' : 'In quick actions',
                          style: TextStyle(
                              color: s == inSettings
                                  ? Colors.grey
                                  : Colors.greenAccent,
                              fontSize: 12.5)),
                      trailing: Icon(
                        s == inSettings
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: s == inSettings
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// App lock switch: on runs the PIN setup; off asks for the PIN first.
  Future<void> _setAppLock(bool on) async {
    final navigator = Navigator.of(context);
    if (on) {
      await navigator.push<bool>(MaterialPageRoute(
          builder: (context) => const AppLockSetupScreen()));
      return;
    }
    final ok = await _confirmPin();
    if (ok) await AppLock.disable();
  }

  Future<void> _changePin() async {
    if (!await _confirmPin() || !mounted) return;
    await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (context) => const AppLockSetupScreen()));
  }

  /// Full-screen PIN check; true if the right PIN was entered.
  Future<bool> _confirmPin() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (ctx) => PinScreen(
        mode: PinMode.verify,
        onCancel: () => Navigator.pop(ctx, false),
        onDone: (_) => Navigator.pop(ctx, true),
      ),
    ));
    return ok == true;
  }

  /// Small dialog to set (or clear) an amount-based optional feature.
  Future<void> _editAmountPref({
    required String title,
    required String hint,
    required double? current,
    required Future<void> Function(double?) onSave,
  }) async {
    final controller = TextEditingController(
        text: current == null ? '' : current.toStringAsFixed(0));
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(labelText: hint, prefixText: '₹ '),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, '__off__'),
            child: const Text('Turn off',
                style: TextStyle(color: Colors.redAccent)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return; // cancelled
    if (result == '__off__') {
      await onSave(null);
      return;
    }
    final v = double.tryParse(result.trim());
    await onSave(v == null || v <= 0 ? null : v);
  }

  static String _formatMinutes(int minutes) {
    final h = minutes ~/ 60, m = minutes % 60;
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
  }

  /// Daily reminder switch. Turning it on asks for a time (9:00 PM default).
  Future<void> _setReminder(bool on) async {
    if (!on) {
      await AppPrefs.instance.setReminderMinutes(null);
      await NotificationService.syncDailyReminder(null);
      return;
    }
    await _pickReminderTime(21 * 60);
  }

  Future<void> _pickReminderTime(int current) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
      helpText: 'Remind me every day at',
    );
    if (picked == null) return;
    final minutes = picked.hour * 60 + picked.minute;
    await AppPrefs.instance.setReminderMinutes(minutes);
    await NotificationService.syncDailyReminder(minutes);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Reminder set for ${_formatMinutes(minutes)} daily')));
    }
  }

  /// Opens the GitHub Releases page in the browser. Vyaya itself makes no
  /// network request; the browser app loads the page.
  Future<void> _openReleases() async {
    final messenger = ScaffoldMessenger.of(context);
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse(AppPrefs.releasesUrl),
          mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok) {
      messenger.showSnackBar(const SnackBar(
          content: Text('No browser found to open GitHub Releases')));
    }
  }

  /// Asks how far back to import bank SMS. Returns the start date, or null.
  Future<DateTime?> _pickImportStart() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final primary = Theme.of(context).colorScheme.primary;
    final options = <(String, IconData, DateTime)>[
      ('Last 7 days', Icons.date_range_rounded,
          today.subtract(const Duration(days: 6))),
      ('Last 30 days', Icons.calendar_view_month_rounded,
          today.subtract(const Duration(days: 29))),
      ('Last 3 months', Icons.history_rounded,
          DateTime(now.year, now.month - 3, now.day)),
    ];
    final choice = await showModalBottomSheet<Object>(
      context: context,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Import bank SMS from',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    'Payments already in your list are skipped, so importing again is safe.',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              ),
            ),
            for (final (label, icon, since) in options)
              ListTile(
                leading: Icon(icon, color: primary),
                title: Text(label, style: const TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, since),
              ),
            ListTile(
              leading: Icon(Icons.edit_calendar_rounded, color: primary),
              title: const Text('From a date…',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, 'custom'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice is DateTime) return choice;
    if (choice == 'custom' && mounted) {
      return showDatePicker(
        context: context,
        initialDate: today.subtract(const Duration(days: 29)),
        firstDate: DateTime(now.year - 5),
        lastDate: today,
        helpText: 'Import SMS received since',
      );
    }
    return null;
  }

  /// Deletes a bank account. If transactions (or recurring entries) use it,
  /// asks where to move them first so they aren't left pointing at an
  /// account that no longer exists.
  Future<void> _showDeleteAccountDialog(BankAccount account) async {
    final provider = context.read<ExpenseProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final used = provider.accountUsageCount(account.id);
    final others =
        provider.accounts.where((a) => a.id != account.id).toList();

    final choice = await showDialog<({String? moveTo})>(
      context: context,
      builder: (context) => _DeleteAccountDialog(
        account: account,
        usedCount: used,
        others: others,
      ),
    );
    if (choice == null) return; // cancelled

    try {
      await provider.removeAccount(account.id, moveTo: choice.moveTo);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Couldn\'t delete account: $e')),
      );
      return;
    }

    final target = choice.moveTo == null
        ? null
        : others.where((a) => a.id == choice.moveTo).firstOrNull?.name;
    messenger.showSnackBar(
      SnackBar(
        content: Text(used > 0 && target != null
            ? '"${account.name}" deleted · $used moved to $target'
            : '"${account.name}" deleted'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

/// Second confirmation: lists categories that already have logged expenses,
/// each with a "Move to" dropdown. Pops a map of oldName -> newName for the
/// categories the user chose to move (empty map = keep all as-is), or null
/// if cancelled.
class _LoggedExpensesDialog extends StatefulWidget {
  final List<ExpenseCategory> affected;
  final Map<String, int> counts;
  final List<ExpenseCategory> remaining;

  const _LoggedExpensesDialog({
    required this.affected,
    required this.counts,
    required this.remaining,
  });

  @override
  State<_LoggedExpensesDialog> createState() => _LoggedExpensesDialogState();
}

class _LoggedExpensesDialogState extends State<_LoggedExpensesDialog> {
  static const _keep = '__keep__';
  // oldName -> target name; _keep = don't move
  final Map<String, String> _moveTo = {};

  @override
  Widget build(BuildContext context) {
    final total = widget.counts.values.fold<int>(0, (a, b) => a + b);
    final single = widget.affected.length == 1;

    return AlertDialog(
      backgroundColor: const Color(0xFF2A2A2A),
      title: const Text('Entries already logged',
          style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                single
                    ? '"${widget.affected.first.name}" has $total logged ${total == 1 ? 'entry' : 'entries'} (expenses and recurring). Delete anyway?'
                    : 'These categories have $total logged entries (expenses and recurring). Delete anyway?',
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
              for (final cat in widget.affected) ...[
                Row(
                  children: [
                    Text(cat.icon, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${cat.name} · ${widget.counts[cat.name]} ${widget.counts[cat.name] == 1 ? 'entry' : 'entries'}',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _moveTo[cat.name] ?? _keep,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF1E1E1E),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Move entries to',
                    labelStyle: TextStyle(color: Colors.grey.shade400),
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: _keep,
                      child: Text('Keep as-is (don\'t move)'),
                    ),
                    for (final r in widget.remaining)
                      DropdownMenuItem<String>(
                        value: r.name,
                        child: Text('${r.icon}  ${r.name}'),
                      ),
                  ],
                  onChanged: (v) => setState(() => _moveTo[cat.name] = v ?? _keep),
                ),
                const SizedBox(height: 14),
              ],
              if (widget.remaining.isEmpty)
                Text(
                  'No other categories left to move expenses into.',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () {
            final mapping = <String, String>{
              for (final e in _moveTo.entries)
                if (e.value != _keep) e.key: e.value,
            };
            Navigator.of(context).pop(mapping);
          },
          child: Text(_moveTo.values.any((v) => v != _keep)
              ? 'Move & delete'
              : 'Delete'),
        ),
      ],
    );
  }
}

/// Confirms deleting a bank account. When it has transactions, lets you
/// pick another account to move them to (or leave them unassigned).
/// Pops (moveTo: id-or-null), or null when cancelled.
class _DeleteAccountDialog extends StatefulWidget {
  final BankAccount account;
  final int usedCount;
  final List<BankAccount> others;

  const _DeleteAccountDialog({
    required this.account,
    required this.usedCount,
    required this.others,
  });

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  static const _none = '__none__';
  late String _moveTo = widget.others.isEmpty
      ? _none
      : (widget.others.where((a) => a.isDefault).firstOrNull ??
              widget.others.first)
          .id;

  @override
  Widget build(BuildContext context) {
    final n = widget.usedCount;
    final hasEntries = n > 0;

    return AlertDialog(
      backgroundColor: const Color(0xFF2A2A2A),
      title: const Text('Delete Account', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hasEntries
                  ? '"${widget.account.name}" is used by $n ${n == 1 ? 'entry' : 'entries'} (transactions and recurring).'
                  : 'Are you sure you want to delete "${widget.account.name}"?',
              style: const TextStyle(color: Colors.white),
            ),
            if (hasEntries) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _moveTo,
                isExpanded: true,
                dropdownColor: const Color(0xFF1E1E1E),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Move them to',
                  labelStyle: TextStyle(color: Colors.grey.shade400),
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                items: [
                  for (final a in widget.others)
                    DropdownMenuItem<String>(
                      value: a.id,
                      child: Text(a.isDefault ? '${a.name} (default)' : a.name),
                    ),
                  const DropdownMenuItem<String>(
                    value: _none,
                    child: Text('No account (leave unassigned)'),
                  ),
                ],
                onChanged: (v) => setState(() => _moveTo = v ?? _none),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.of(context)
              .pop((moveTo: _moveTo == _none ? null : _moveTo)),
          child: Text(hasEntries && _moveTo != _none ? 'Move & delete' : 'Delete'),
        ),
      ],
    );
  }
}

/// Icons offered when creating a category, grouped. Emoji are used as the
/// category icon everywhere (cards, charts, pickers), so any emoji works.
const Map<String, List<String>> _categoryEmojiGroups = {
  'Popular': ['📦', '🍽️', '🛒', '🚗', '🏠', '💡', '🎬', '🏥', '📚', '💳', '🎁', '✈️', '👕', '📱', '💰', '🎯'],
  'Food': ['🍔', '🍕', '🍛', '🍜', '🍣', '🥗', '🍩', '☕', '🍵', '🧃', '🍺', '🍷', '🥛', '🍎', '🥦', '🧁'],
  'Travel': ['🚗', '🛵', '🚕', '🚌', '🚇', '🚆', '✈️', '⛽', '🅿️', '🚲', '🛺', '🗺️', '🏨', '🧳', '⛱️', '🚢'],
  'Home': ['🏠', '🛋️', '🧹', '🧺', '🔌', '💡', '🚿', '🔧', '🪴', '🐶', '🐱', '👶', '🧸', '🛏️', '📦', '🔑'],
  'Health': ['🏋️', '💪', '🧘', '🏃', '🚴', '⚽', '🏏', '🏸', '🏊', '💊', '🏥', '🩺', '🦷', '👓', '💆', '🧴'],
  'Fun': ['🎬', '🎮', '🎵', '🎧', '🎤', '🎨', '📷', '🎟️', '🎳', '🎲', '📺', '🍿', '🎉', '🎂', '🎁', '🏖️'],
  'Work & study': ['💼', '💻', '🖥️', '📚', '✏️', '🎓', '🏫', '📝', '📎', '🖨️', '📡', '☁️', '📞', '🧾', '🗂️', '⌨️'],
  'Money': ['💰', '💳', '🏦', '💵', '🪙', '📈', '📉', '🧾', '💸', '🤝', '🏧', '🛡️', '📊', '🎗️', '🙏', '⭐'],
  'Shopping': ['🛒', '🛍️', '👕', '👗', '👟', '👜', '💄', '💍', '⌚', '🕶️', '🧢', '📱', '🎧', '🧴', '🪒', '🧦'],
};

/// Category colours, picked to stay distinct from each other on black.
const List<Color> _categoryColors = [
  Color(0xFFEF5350), // red
  Color(0xFFFF7043), // deep orange
  Color(0xFFFFA726), // orange
  Color(0xFFFFD54F), // yellow
  Color(0xFFC0CA33), // lime
  Color(0xFF66BB6A), // green
  Color(0xFF26A69A), // teal
  Color(0xFF26C6DA), // cyan
  Color(0xFF42A5F5), // blue
  Color(0xFF5C6BC0), // indigo
  Color(0xFF9575CD), // lavender
  Color(0xFFBA68C8), // purple
  Color(0xFFF06292), // pink
  Color(0xFFA1887F), // brown
  Color(0xFF90A4AE), // blue grey
  Color(0xFFE0E0E0), // silver
];

/// The last emoji/symbol typed, or null for plain letters, digits or spaces
/// (those wouldn't look like an icon).
String? _singleEmoji(String input) {
  final chars = input.characters.where((c) => c.trim().isNotEmpty).toList();
  if (chars.isEmpty) return null;
  final last = chars.last;
  if (RegExp(r'^[A-Za-z0-9\p{P}]+$', unicode: true).hasMatch(last)) return null;
  return last;
}

/// A horizontally scrolling row with small arrows at the edges that show
/// when there's more to scroll that way (tap one to scroll a step).
class _ScrollArrowsRow extends StatefulWidget {
  final List<Widget> children;
  final double height;
  final Color fadeColor;
  final int initialIndex;

  const _ScrollArrowsRow({
    required this.children,
    required this.height,
    required this.fadeColor,
    this.initialIndex = 0,
  });

  @override
  State<_ScrollArrowsRow> createState() => _ScrollArrowsRowState();
}

class _ScrollArrowsRowState extends State<_ScrollArrowsRow> {
  final _controller = ScrollController();
  late final List<GlobalKey> _keys =
      List.generate(widget.children.length, (_) => GlobalKey());
  bool _canLeft = false;
  bool _canRight = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_update);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Bring the selected chip into view (e.g. when editing a category
      // whose icon is in a later group).
      final i = widget.initialIndex;
      final ctx = (i > 0 && i < _keys.length) ? _keys[i].currentContext : null;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            alignment: 0.5, duration: Duration.zero);
      }
      _update();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _update() {
    if (!_controller.hasClients) return;
    final p = _controller.position;
    final left = p.pixels > 1;
    final right = p.pixels < p.maxScrollExtent - 1;
    if (left != _canLeft || right != _canRight) {
      setState(() {
        _canLeft = left;
        _canRight = right;
      });
    }
  }

  void _step(double direction) {
    if (!_controller.hasClients) return;
    final p = _controller.position;
    final target = (p.pixels + direction * p.viewportDimension * 0.6)
        .clamp(0.0, p.maxScrollExtent);
    _controller.animateTo(target,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  Widget _arrow({required bool left}) => Positioned(
        left: left ? 0 : null,
        right: left ? null : 0,
        top: 0,
        bottom: 0,
        child: GestureDetector(
          onTap: () => _step(left ? -1 : 1),
          child: Container(
            width: 28,
            alignment: left ? Alignment.centerLeft : Alignment.centerRight,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: left ? Alignment.centerLeft : Alignment.centerRight,
                end: left ? Alignment.centerRight : Alignment.centerLeft,
                colors: [
                  widget.fadeColor,
                  widget.fadeColor.withValues(alpha: 0),
                ],
              ),
            ),
            child: Icon(
              left ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
              size: 18,
              color: Colors.white70,
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: NotificationListener<ScrollMetricsNotification>(
        // Re-check when the content size changes (first layout, rotation).
        onNotification: (_) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _update());
          return false;
        },
        child: Stack(
          children: [
            ListView(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              children: [
                for (var i = 0; i < widget.children.length; i++)
                  KeyedSubtree(key: _keys[i], child: widget.children[i]),
              ],
            ),
            if (_canLeft) _arrow(left: true),
            if (_canRight) _arrow(left: false),
          ],
        ),
      ),
    );
  }
}
