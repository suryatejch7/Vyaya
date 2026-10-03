import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/capture_provider.dart';
import '../providers/expense_provider.dart';
import '../services/local_store.dart';

/// First-launch intro: three short pages (offline promise, optional payment
/// auto-detect, where things are). Shown once per install, and never to
/// someone who already has entries.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  static const _key = 'onboarding_done';

  /// Shows the intro if it's due; returns when it's closed.
  static Future<void> showIfNeeded(BuildContext context) async {
    if (LocalStore.getDeviceValue(_key) != null) return;
    final ep = context.read<ExpenseProvider>();
    await LocalStore.setDeviceValue(_key, '1');
    if (ep.expenses.isNotEmpty || ep.incomes.isNotEmpty) return;
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const OnboardingScreen(),
    ));
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;
  static const _count = 3;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == _count - 1) {
      Navigator.of(context).pop();
    } else {
      _pages.nextPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Skip', style: TextStyle(color: Colors.grey)),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  const _Page(
                    icon: Icons.lock_outline_rounded,
                    title: 'Your money stays on your phone',
                    lines: [
                      'No account, no internet, no ads. Nothing leaves this phone unless you share it.',
                      'Uninstalling deletes your data, so use Settings → Back up now and then and keep the file safe.',
                    ],
                  ),
                  _Page(
                    icon: Icons.sms_outlined,
                    title: 'Log payments automatically',
                    lines: const [
                      'Optional. Vyaya can read bank SMS and payment-app alerts (GPay, PhonePe…) on this phone and suggest the expense for you to confirm.',
                    ],
                    extra: _DetectButtons(primary: primary),
                  ),
                  const _Page(
                    icon: Icons.touch_app_outlined,
                    title: 'Finding your way',
                    lines: [
                      'Tap + to add an expense or income.',
                      'Swipe up on the bottom bar for Analytics, Recurring, Lent & Borrowed and Settings.',
                      'Long-press an entry to select several, then edit or delete them together.',
                      'Every change can be undone: tap the small round bubble.',
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Row(
                children: [
                  for (var i = 0; i < _count; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 6),
                      width: i == _page ? 20 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _page ? primary : Colors.white24,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: _next,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 14),
                    ),
                    child: Text(_page == _count - 1 ? 'Start' : 'Next'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> lines;
  final Widget? extra;
  const _Page(
      {required this.icon, required this.title, required this.lines, this.extra});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 24),
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(l,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 16, height: 1.4)),
            ),
          ?extra,
        ],
      ),
    );
  }
}

/// The two permissions auto-detect uses, each optional, with a tick once
/// granted. Can be changed later in Settings → Auto-detect Payments.
class _DetectButtons extends StatelessWidget {
  final Color primary;
  const _DetectButtons({required this.primary});

  @override
  Widget build(BuildContext context) {
    final cap = context.watch<CaptureProvider>();
    Widget button(String label, bool done, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: done ? null : onTap,
              icon: Icon(done ? Icons.check_circle : Icons.add_circle_outline,
                  color: done ? Colors.green : primary),
              label: Text(done ? '$label: allowed' : label,
                  style: const TextStyle(color: Colors.white)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: Colors.white24),
              ),
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        button('Read bank SMS', cap.smsPermission, cap.requestSmsPermission),
        button('Read payment-app alerts', cap.notificationAccess,
            cap.openNotificationAccess),
        const SizedBox(height: 12),
        const Text(
          'If Android says the setting is restricted: open App info → ⋮ → Allow restricted settings, then try again. You can change all this later in Settings → Auto-detect Payments.',
          style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.4),
        ),
      ],
    );
  }
}
