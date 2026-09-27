import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/expense_provider.dart';
import '../providers/user_provider.dart';
import '../providers/capture_provider.dart';
import 'detected_payments_screen.dart';
import '../models/expense_models.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import '../services/export_service.dart';
import '../services/backup_service.dart';
import 'crop_calibration_screen.dart';
import 'recurring_screen.dart';
import 'package:file_picker/file_picker.dart';

/// Settings is a hub page; heavier sections open as their own pages that
/// reuse the same state class (so dialogs/helpers are shared).
enum SettingsPage { home, categories, accounts, autoDetect }

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
  }


  @override
  void dispose() {
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
  Widget _plainCard({required Widget child}) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D0D),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
        ),
        child: child,
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
  Widget _group(List<Widget> rows) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D0D),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
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
          final activeRecurring =
              expenseProvider.recurringEntries.where((r) => r.active).length;
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
                  icon: Icons.repeat_rounded,
                  color: Colors.teal,
                  title: 'Recurring',
                  subtitle: activeRecurring == 0
                      ? 'Monthly income and bills'
                      : '$activeRecurring active',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const RecurringScreen()),
                  ),
                ),
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
                _row(
                  icon: Icons.crop_free_rounded,
                  color: Colors.deepOrange,
                  title: 'PhonePe Screenshot Scanning',
                  subtitle: 'Crop calibration',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const CropCalibrationScreen()),
                  ),
                ),
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
              Center(
                child: Text(
                  'Vyaya v2.1.2',
                  style: TextStyle(color: Colors.grey[700], fontSize: 12),
                ),
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
                                  : null,
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
                                            onTap: () => _showExpenseCategoryBudgetDialog(category),
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

  void _showAddCategoryDialog() {
    _categoryNameController.clear();
    String selectedIcon = '📦';
    Color selectedColor = Colors.blue;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          title: const Text(
            'Add Category',
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Category Name Input
                TextField(
                  controller: _categoryNameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
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
                const SizedBox(height: 20),

                // Icon Selection (simplified)
                const Text(
                  'Choose Icon',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ['📦', '🍽️', '🚗', '🛒', '🎬', '💡', '🏥', '📚', '💳', '🎯'].map((icon) {
                    final isSelected = icon == selectedIcon;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          selectedIcon = icon;
                        });
                      },
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: isSelected ? selectedColor.withValues(alpha: 0.3) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected ? selectedColor : Colors.grey.withValues(alpha: 0.3),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            icon,
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),

                // Color Selection (simplified)
                const Text(
                  'Choose Color',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Colors.blue,
                    Colors.green,
                    Colors.cyan,
                    Colors.orange,
                    Colors.purple,
                    Colors.pink,
                    Colors.teal,
                    Colors.amber,
                  ].map((color) {
                    final isSelected = color == selectedColor;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          selectedColor = color;
                        });
                      },
                      child: Container(
                        width: isSelected ? 50 : 40,
                        height: isSelected ? 50 : 40,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? Colors.white : Colors.transparent,
                            width: 3,
                          ),
                          boxShadow: isSelected ? [
                            BoxShadow(
                              color: color.withValues(alpha: 0.5),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ] : null,
                        ),
                        child: isSelected
                          ? const Icon(Icons.check, color: Colors.white, size: 20)
                          : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: _isAddingCategory ? null : () async {
                if (_categoryNameController.text.isNotEmpty) {
                  setState(() {
                    _isAddingCategory = true;
                  });

                  try {
                    final newCategory = ExpenseCategory(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      name: _categoryNameController.text,
                      icon: selectedIcon,
                      colorHex: '#${(selectedColor.r * 255.0).round().toRadixString(16).padLeft(2, '0')}${(selectedColor.g * 255.0).round().toRadixString(16).padLeft(2, '0')}${(selectedColor.b * 255.0).round().toRadixString(16).padLeft(2, '0')}',
                      isDefault: false,
                    );

                    final navigator = Navigator.of(context);
                    final scaffoldMessenger = ScaffoldMessenger.of(context);
                    final theme = Theme.of(context);
                    
                    await context.read<ExpenseProvider>().addCustomCategory(newCategory);
                    // No need for force refresh - addCustomCategory already handles local updates
                    navigator.pop();

                    if (mounted) {
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text('Category "${_categoryNameController.text}" added successfully!'),
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
                : const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _showExpenseCategoryBudgetDialog(ExpenseCategory category) {
    final provider = context.read<ExpenseProvider>();
    _categoryBudgetController.text = provider.getCustomCategoryBudget(category.id).toString();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: Text(
          'Set Budget for ${category.name}',
          style: const TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: _categoryBudgetController,
          style: const TextStyle(color: Colors.white),
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Budget Amount (₹) - Enter 0 for unlimited',
            labelStyle: const TextStyle(color: Colors.grey),
            prefixText: '₹ ',
            prefixStyle: const TextStyle(color: Colors.white),
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
        actions: [
          TextButton(
            onPressed: () {
              final navigator = Navigator.of(context);
              navigator.pop();
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              final theme = Theme.of(context);
              
              final budget = double.tryParse(_categoryBudgetController.text) ?? 0;
              await provider.setCustomCategoryBudget(category.id, budget);
              // No need for force refresh - setCustomCategoryBudget already handles local updates
              navigator.pop();
              if (mounted) {
                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      budget > 0
                          ? 'Budget set to ₹${budget.toStringAsFixed(0)} for ${category.name}'
                          : 'Budget removed for ${category.name}',
                    ),
                    backgroundColor: theme.colorScheme.primary,
                    duration: const Duration(seconds: 1),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
            child: const Text('Set Budget'),
          ),
        ],
      ),
    );
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
    try {
      await provider.removeCustomCategories(
        targets.map((c) => c.id).toSet(),
        reassign: reassign,
      );
      if (!mounted) return;
      _clearCategorySelection();
      final moved = reassign.keys.fold<int>(0, (s, k) => s + (counts[k] ?? 0));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Deleted $label'
            '${moved > 0 ? ' · moved $moved ${moved == 1 ? 'expense' : 'expenses'}' : ''}',
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
                  title: const Text('Import last 30 days of bank SMS',
                      style: TextStyle(color: Colors.white)),
                  subtitle: const Text(
                      'Imported payments always wait for your review',
                      style: TextStyle(color: Colors.grey)),
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    messenger.showSnackBar(
                        const SnackBar(content: Text('Importing…')));
                    final n = await cap.importRecentSms();
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
              return Container(
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
                          onPressed: () => _showDeleteAccountDialog(account),
                          icon: const Icon(
                            Icons.delete,
                            color: Colors.red,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  void _showAddAccountDialog() {
    final accountNameController = TextEditingController();
    AccountType selectedType = AccountType.savings;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          title: const Text(
            'Add Account',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: accountNameController,
                style: const TextStyle(color: Colors.white),
                autofocus: true,
                decoration: InputDecoration(
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
                children: AccountType.values.map((type) {
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
                if (name.isEmpty) return;

                final navigator = Navigator.of(context);
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                final provider = context.read<ExpenseProvider>();

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
              child: const Text('Add'),
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

              await ExpenseSupabaseService.resetAllData();
              expenseProvider.clearUserData();
              await userProvider.clearUser();

              // Start fresh right away (same as a first launch) instead of
              // leaving an empty app until the next restart.
              await userProvider.registerUser('LocalUser');
              await userProvider.initializeExpenseProvider(expenseProvider);
              await captureProvider.reload();

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

  void _showDeleteAccountDialog(BankAccount account) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text(
          'Delete Account',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to delete "${account.name}"?',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              final provider = context.read<ExpenseProvider>();

              await provider.removeAccount(account.id);
              navigator.pop();

              if (mounted) {
                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text('Account "${account.name}" deleted!'),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 1),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
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
      title: const Text('Expenses already logged',
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
                    ? '"${widget.affected.first.name}" has $total logged ${total == 1 ? 'expense' : 'expenses'}. Delete anyway?'
                    : 'These categories have $total logged expenses. Delete anyway?',
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
                        '${cat.name} · ${widget.counts[cat.name]} ${widget.counts[cat.name] == 1 ? 'expense' : 'expenses'}',
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
                    labelText: 'Move expenses to',
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
