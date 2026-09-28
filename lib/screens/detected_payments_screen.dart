import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/expense_models.dart';
import '../providers/capture_provider.dart';
import '../providers/expense_provider.dart';
import '../services/capture/capture_models.dart';
import 'add_expense_screen.dart';
import '../widgets/undo_snackbar.dart';

/// Review list for payments picked up from bank SMS / payment apps.
class DetectedPaymentsScreen extends StatefulWidget {
  const DetectedPaymentsScreen({super.key});

  @override
  State<DetectedPaymentsScreen> createState() => _DetectedPaymentsScreenState();
}

class _DetectedPaymentsScreenState extends State<DetectedPaymentsScreen> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  bool _showToTop = false;
  bool _searching = false;
  _Filter _filter = const _Filter();

  /// Long-press selection (ids of pending payments).
  final Set<String> _selected = {};
  bool get _selecting => _selected.isNotEmpty;

  /// Cards just swiped away. A dismissed Dismissible must leave the tree in
  /// the same frame, before the provider has finished saving.
  final Set<String> _hiding = {};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      // Show the jump-to-top button once you're about two screens down.
      final show = _scroll.offset > 1200;
      if (show != _showToTop) setState(() => _showToTop = show);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _setFilter(_Filter f) => setState(() => _filter = f);

  void _closeSearch() {
    _search.clear();
    setState(() {
      _searching = false;
      _filter = _filter.copyWith(query: '');
    });
  }

  String _payments(int n) => '$n ${n == 1 ? 'payment' : 'payments'}';

  // ------------------------------------------------------------ single item

  Future<void> _addOne(CaptureProvider cap, DetectedTransaction item) async {
    setState(() => _hiding.add(item.id));
    await cap.accept(item.id, category: item.isDebit ? item.category : null);
    if (mounted) setState(() => _hiding.remove(item.id));
    showUndo('Added "${item.title}"', () => cap.unaccept(item.id));
  }

  Future<void> _dismissOne(CaptureProvider cap, DetectedTransaction item) async {
    setState(() => _hiding.add(item.id));
    await cap.dismiss(item.id);
    if (mounted) setState(() => _hiding.remove(item.id));
    showUndo('Dismissed "${item.title}"', () => cap.restore(item.id));
  }

  Future<void> _ignore(CaptureProvider cap, MuteRule rule) async {
    final hidden = await cap.addMute(rule);
    showUndo(
      hidden.isEmpty
          ? 'Ignoring ${rule.label}'
          : 'Ignoring ${rule.label} · ${_payments(hidden.length)} hidden',
      () async {
        await cap.removeMute(rule);
        await cap.restoreMany(hidden);
      },
    );
  }

  // ------------------------------------------------------------ many items

  Future<void> _dismissMany(CaptureProvider cap, Iterable<String> ids) async {
    final done = await cap.dismissAll(only: ids);
    // The undo still shows if you left the screen while it ran.
    if (mounted) setState(_selected.clear);
    showUndo('Dismissed ${_payments(done.length)}', () => cap.restoreMany(done));
  }

  Future<void> _addMany(CaptureProvider cap, Iterable<String> ids,
      {required bool skipFlagged}) async {
    final r = await cap.acceptAll(only: ids, skipFlagged: skipFlagged);
    if (mounted) setState(_selected.clear);
    final left = r.skipped == 0
        ? ''
        : ' · ${r.skipped} transfer/card bill left to review';
    showUndo('Added ${_payments(r.added)}$left', () => cap.unacceptMany(r.ids));
  }

  /// "Remove from list": clears payments for good (not just dismissed), e.g.
  /// after importing a month when you only wanted a week.
  Future<void> _openRemoveSheet(CaptureProvider cap,
      List<DetectedTransaction> shown, bool filtered) async {
    final pendingCount = cap.pending.length;
    final total = cap.pending.length +
        cap.added.length +
        cap.dismissed.length +
        cap.duplicates.length;
    final choice = await showModalBottomSheet<String>(
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
                child: Text('Remove from list',
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
                    'Removed payments are gone from here, not just dismissed. Expenses and income you already added stay. Importing that period again brings them back.',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              ),
            ),
            if (filtered && shown.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.filter_alt_outlined,
                    color: Colors.white70),
                title: Text('Remove the ${_payments(shown.length)} shown',
                    style: const TextStyle(color: Colors.white)),
                subtitle: const Text('Only what matches your search and filters',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
                onTap: () => Navigator.pop(context, 'shown'),
              ),
            if (pendingCount > 0)
              ListTile(
                leading: const Icon(Icons.inbox_outlined, color: Colors.white70),
                title: Text('Remove all waiting for review ($pendingCount)',
                    style: const TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, 'pending'),
              ),
            ListTile(
              leading:
                  const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
              title: Text('Clear everything ($total)',
                  style: const TextStyle(color: Colors.redAccent)),
              subtitle: const Text(
                  'Also empties Added, Dismissed and Possibly already logged',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              onTap: () => Navigator.pop(context, 'all'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null) return;
    final removed = switch (choice) {
      'shown' => await cap.removeItems(ids: shown.map((i) => i.id)),
      'pending' => await cap.removeItems(),
      _ => await cap.removeItems(everything: true),
    };
    if (!mounted) return;
    setState(_selected.clear);
    if (removed.isEmpty) return;
    showUndo('Removed ${_payments(removed.length)}', () => cap.putBack(removed));
  }

  void _toggle(String id) => setState(() {
        if (!_selected.remove(id)) _selected.add(id);
      });

  @override
  Widget build(BuildContext context) {
    return Consumer<CaptureProvider>(
      builder: (context, cap, child) {
        final allPending = cap.pending;
        final pending = _filter
            .apply(allPending)
            .where((i) => !_hiding.contains(i.id))
            .toList()
          ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
        final duplicates = cap.duplicates;
        final added = cap.added;
        final dismissed = cap.dismissed;
        final filtered = _filter.active;
        final primary = Theme.of(context).colorScheme.primary;

        // Drop selections that are no longer waiting for review.
        _selected.removeWhere((id) => !allPending.any((i) => i.id == id));

        // Pending cards grouped under day headers (Today, Yesterday, 12 Sep).
        final rows = <Widget>[];
        DateTime? lastDay;
        for (final item in pending) {
          final d = item.occurredAt;
          final day = DateTime(d.year, d.month, d.day);
          if (day != lastDay) {
            rows.add(_DayHeader(key: ValueKey('day-$day'), day: day));
            lastDay = day;
          }
          // Keyed so a card's state (open message, etc.) stays with its
          // payment when others are added or dismissed.
          rows.add(_DetectedCard(
            key: ValueKey(item.id),
            item: item,
            selecting: _selecting,
            selected: _selected.contains(item.id),
            onToggle: () => _toggle(item.id),
            onAdd: () => _addOne(cap, item),
            onDismiss: () => _dismissOne(cap, item),
            onIgnore: (rule) => _ignore(cap, rule),
          ));
        }

        final allShownSelected =
            pending.isNotEmpty && pending.every((i) => _selected.contains(i.id));

        final PreferredSizeWidget appBar = _selecting
            ? AppBar(
                backgroundColor: const Color(0xFF0D0D0D),
                foregroundColor: Colors.white,
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Cancel selection',
                  onPressed: () => setState(_selected.clear),
                ),
                title: Text('${_selected.length} selected'),
                actions: [
                  IconButton(
                    icon: Icon(allShownSelected
                        ? Icons.deselect_rounded
                        : Icons.select_all_rounded),
                    tooltip: allShownSelected ? 'Select none' : 'Select all shown',
                    onPressed: () => setState(() {
                      if (allShownSelected) {
                        _selected.clear();
                      } else {
                        _selected.addAll(pending.map((i) => i.id));
                      }
                    }),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                    tooltip: 'Dismiss selected',
                    onPressed: () => _dismissMany(cap, _selected.toList()),
                  ),
                  IconButton(
                    icon: Icon(Icons.check_circle_rounded, color: primary),
                    tooltip: 'Add selected',
                    onPressed: () =>
                        _addMany(cap, _selected.toList(), skipFlagged: false),
                  ),
                ],
              )
            : _searchAppBar(
                title: 'Detected Payments',
                searching: _searching,
                controller: _search,
                hint: 'Search payee, amount, bank…',
                onOpen: () => setState(() => _searching = true),
                onClose: _closeSearch,
                onChanged: (q) => _setFilter(_filter.copyWith(query: q)),
                actions: [
                  if (!_searching &&
                      (allPending.isNotEmpty ||
                          duplicates.isNotEmpty ||
                          added.isNotEmpty ||
                          dismissed.isNotEmpty))
                    IconButton(
                      icon: const Icon(Icons.delete_sweep_outlined),
                      tooltip: 'Remove from list',
                      onPressed: () => _openRemoveSheet(cap, pending, filtered),
                    ),
                ],
              );

        return PopScope(
          // Back leaves selection mode first.
          canPop: !_selecting,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _selecting) setState(_selected.clear);
          },
          child: Scaffold(
            floatingActionButton: AnimatedScale(
              scale: _showToTop ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: FloatingActionButton.small(
                heroTag: 'detected-to-top',
                tooltip: 'Back to top',
                onPressed: () => _scroll.animateTo(0,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic),
                child: const Icon(Icons.keyboard_arrow_up_rounded),
              ),
            ),
            backgroundColor: Colors.black,
            appBar: appBar,
            body: RefreshIndicator(
              onRefresh: cap.sync,
              child: ListView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                children: [
                  if (!cap.isEnabled)
                    const _InfoCard(
                      icon: Icons.info_outline,
                      text:
                          'Auto-detection is off. Turn it on in Settings → Auto-detect Payments.',
                    ),
                  if (allPending.isNotEmpty)
                    _FilterBar(filter: _filter, onChanged: _setFilter),
                  Row(
                    children: [
                      Expanded(
                        child: _SectionHeader(
                          filtered ? 'Showing' : 'To review',
                          pending.length,
                          of: filtered ? allPending.length : null,
                        ),
                      ),
                      if (pending.length > 1 && !_selecting) ...[
                        TextButton(
                          onPressed: () =>
                              _dismissMany(cap, pending.map((i) => i.id)),
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.grey,
                              visualDensity: VisualDensity.compact),
                          child:
                              Text(filtered ? 'Dismiss shown' : 'Dismiss all'),
                        ),
                        TextButton(
                          onPressed: () => _addMany(
                              cap, pending.map((i) => i.id),
                              skipFlagged: true),
                          style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact),
                          child: Text(filtered ? 'Add shown' : 'Add all'),
                        ),
                      ],
                    ],
                  ),
                  if (pending.length > 1 && !_selecting && !filtered)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: Text(
                        'Swipe right to add, left to dismiss. Long-press to select several.',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ),
                  if (allPending.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 28),
                      child: Center(
                        child: Text(
                          'All caught up. New payments will show up here.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  else if (pending.isEmpty)
                    _NoMatches(onClear: () {
                      _search.clear();
                      _setFilter(const _Filter());
                    })
                  else
                    ...rows,
                  if (duplicates.isNotEmpty ||
                      added.isNotEmpty ||
                      dismissed.isNotEmpty ||
                      cap.muteRules.isNotEmpty)
                    const SizedBox(height: 12),
                  if (duplicates.isNotEmpty)
                    _HistoryLink(
                      icon: Icons.content_copy_rounded,
                      title: 'Possibly already logged',
                      count: duplicates.length,
                      subtitle: 'Matched something you added yourself',
                      kind: _History.duplicates,
                    ),
                  if (added.isNotEmpty)
                    _HistoryLink(
                      icon: Icons.check_circle_outline_rounded,
                      title: 'Added from detection',
                      count: added.length,
                      subtitle: 'What went into your expenses and income',
                      kind: _History.added,
                    ),
                  if (dismissed.isNotEmpty)
                    _HistoryLink(
                      icon: Icons.remove_circle_outline_rounded,
                      title: 'Dismissed',
                      count: dismissed.length,
                      subtitle: 'Restore any you dismissed by mistake',
                      kind: _History.dismissed,
                    ),
                  if (cap.muteRules.isNotEmpty)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.notifications_off_outlined,
                          color: Colors.grey),
                      title: Text('Ignored (${cap.muteRules.length})',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                      subtitle: const Text(
                          'Payees and senders that never show up here',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                      trailing:
                          const Icon(Icons.chevron_right, color: Colors.grey),
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const MuteRulesScreen())),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------ ignore rules

/// Lists "Always ignore" rules so they can be removed again.
class MuteRulesScreen extends StatelessWidget {
  const MuteRulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CaptureProvider>(
      builder: (context, cap, child) {
        final rules = cap.muteRules;
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: const Text('Ignored'),
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          body: rules.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Nothing is ignored. Use ⋮ on a detected payment to always ignore its payee or sender.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'New messages matching these are skipped. Remove a rule to see them again (only new messages; past ones stay in Dismissed).',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ),
                    for (final r in rules)
                      ListTile(
                        key: ValueKey('${r.type}:${r.value}'),
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          r.isPayee
                              ? Icons.storefront_outlined
                              : Icons.sms_outlined,
                          color: Colors.grey,
                        ),
                        title: Text(r.label,
                            style: const TextStyle(color: Colors.white)),
                        subtitle: Text(r.isPayee ? 'Payee' : 'Sender',
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12)),
                        trailing: TextButton(
                          onPressed: () {
                            cap.removeMute(r);
                            showUndo('No longer ignoring ${r.label}',
                                () => cap.addMute(r));
                          },
                          child: const Text('Remove'),
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }
}

// ------------------------------------------------------------------ filters

enum _Direction { all, paid, received }

/// Search text + date range + paid/received, applied to any list of
/// detected payments.
class _Filter {
  final String query;
  final DateTimeRange? range;
  final String? rangeLabel; // "Last 7 days" etc. for presets
  final _Direction direction;

  const _Filter({
    this.query = '',
    this.range,
    this.rangeLabel,
    this.direction = _Direction.all,
  });

  bool get active =>
      query.trim().isNotEmpty || range != null || direction != _Direction.all;

  _Filter copyWith({String? query, _Direction? direction}) => _Filter(
        query: query ?? this.query,
        range: range,
        rangeLabel: rangeLabel,
        direction: direction ?? this.direction,
      );

  _Filter withRange(DateTimeRange? r, [String? label]) => _Filter(
        query: query,
        range: r,
        rangeLabel: r == null ? null : label,
        direction: direction,
      );

  bool matches(DetectedTransaction i) {
    if (direction == _Direction.paid && !i.isDebit) return false;
    if (direction == _Direction.received && i.isDebit) return false;
    if (range != null) {
      final s = range!.start;
      final e = range!.end;
      final from = DateTime(s.year, s.month, s.day);
      final to = DateTime(e.year, e.month, e.day + 1); // end day inclusive
      if (i.occurredAt.isBefore(from) || !i.occurredAt.isBefore(to)) {
        return false;
      }
    }
    final tokens = query
        .toLowerCase()
        .replaceAll(RegExp(r'[₹,]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty && t != 'rs' && t != 'rs.');
    if (tokens.isEmpty) return true;
    final haystack = [
      i.title,
      i.appLabel,
      i.category,
      i.last4 ?? '',
      i.amount.toStringAsFixed(0),
      i.amount.toStringAsFixed(2),
      i.rawText,
    ].join(' ').toLowerCase();
    return tokens.every(haystack.contains);
  }

  List<DetectedTransaction> apply(List<DetectedTransaction> items) =>
      active ? items.where(matches).toList() : List.of(items);
}

/// App bar with a search icon that turns the title into a search field.
PreferredSizeWidget _searchAppBar({
  required String title,
  required bool searching,
  required TextEditingController controller,
  required String hint,
  required VoidCallback onOpen,
  required VoidCallback onClose,
  required ValueChanged<String> onChanged,
  List<Widget> actions = const [],
}) {
  return AppBar(
    backgroundColor: Colors.black,
    foregroundColor: Colors.white,
    titleSpacing: searching ? 0 : null,
    leading: searching
        ? IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Close search',
            onPressed: onClose,
          )
        : null,
    title: searching
        ? TextField(
            controller: controller,
            autofocus: true,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: InputDecoration(
              hintText: hint,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          )
        : Text(title),
    actions: [
      if (searching)
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => value.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Clear',
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
        )
      else
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: 'Search',
          onPressed: onOpen,
        ),
      ...actions,
    ],
  );
}

/// Date + paid/received chips under the app bar.
class _FilterBar extends StatelessWidget {
  final _Filter filter;
  final ValueChanged<_Filter> onChanged;
  const _FilterBar({required this.filter, required this.onChanged});

  String _dateLabel() {
    final r = filter.range;
    if (r == null) return 'Any date';
    if (filter.rangeLabel != null) return filter.rangeLabel!;
    final f = DateFormat('d MMM');
    return r.start == r.end
        ? f.format(r.start)
        : '${f.format(r.start)} – ${f.format(r.end)}';
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTimeRange days(int n) =>
        DateTimeRange(start: today.subtract(Duration(days: n - 1)), end: today);
    final thisMonth =
        DateTimeRange(start: DateTime(now.year, now.month), end: today);
    final lastMonth = DateTimeRange(
      start: DateTime(now.year, now.month - 1),
      end: DateTime(now.year, now.month, 0),
    );
    final presets = <(String, IconData, DateTimeRange)>[
      ('Today', Icons.today_rounded, days(1)),
      ('Last 7 days', Icons.date_range_rounded, days(7)),
      ('This month', Icons.calendar_view_month_rounded, thisMonth),
      ('Last month', Icons.history_rounded, lastMonth),
    ];

    final primary = Theme.of(context).colorScheme.primary;
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
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Show payments from',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ),
            ),
            for (final (label, icon, range) in presets)
              ListTile(
                leading: Icon(icon, color: primary),
                title: Text(label, style: const TextStyle(color: Colors.white)),
                trailing: filter.rangeLabel == label
                    ? Icon(Icons.check, color: primary)
                    : null,
                onTap: () => Navigator.pop(context, (label, range)),
              ),
            ListTile(
              leading: Icon(Icons.edit_calendar_rounded, color: primary),
              title: const Text('Pick dates…',
                  style: TextStyle(color: Colors.white)),
              trailing: filter.range != null && filter.rangeLabel == null
                  ? Icon(Icons.check, color: primary)
                  : null,
              onTap: () => Navigator.pop(context, 'custom'),
            ),
            if (filter.range != null)
              ListTile(
                leading: const Icon(Icons.clear_rounded, color: Colors.grey),
                title: const Text('Any date',
                    style: TextStyle(color: Colors.grey)),
                onTap: () => Navigator.pop(context, 'clear'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == 'clear') {
      onChanged(filter.withRange(null));
    } else if (choice == 'custom') {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 5),
        lastDate: today,
        initialDateRange: filter.range,
        helpText: 'Show payments between',
        builder: (context, child) => Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  surface: const Color(0xFF121212),
                  onSurface: Colors.white,
                ),
          ),
          child: child!,
        ),
      );
      if (picked != null) onChanged(filter.withRange(picked));
    } else if (choice is (String, DateTimeRange)) {
      onChanged(filter.withRange(choice.$2, choice.$1));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasDate = filter.range != null;
    Widget dirChip(String label, _Direction d) => ChoiceChip(
          label: Text(label),
          selected: filter.direction == d,
          showCheckmark: false,
          onSelected: (on) =>
              onChanged(filter.copyWith(direction: on ? d : _Direction.all)),
          labelStyle: TextStyle(
              color: filter.direction == d ? Colors.black : Colors.white70),
          selectedColor: Theme.of(context).colorScheme.primary,
          backgroundColor: const Color(0xFF1A1A1A),
          side: BorderSide.none,
          shape: const StadiumBorder(),
        );

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          InputChip(
            avatar: Icon(Icons.calendar_today_rounded,
                size: 16,
                color: hasDate ? Colors.black : Colors.white70),
            label: Text(_dateLabel()),
            selected: hasDate,
            showCheckmark: false,
            onPressed: () => _pickDate(context),
            onDeleted: hasDate ? () => onChanged(filter.withRange(null)) : null,
            deleteIconColor: Colors.black,
            labelStyle:
                TextStyle(color: hasDate ? Colors.black : Colors.white70),
            selectedColor: Theme.of(context).colorScheme.primary,
            backgroundColor: const Color(0xFF1A1A1A),
            side: BorderSide.none,
            shape: const StadiumBorder(),
          ),
          const SizedBox(width: 8),
          dirChip('Paid', _Direction.paid),
          const SizedBox(width: 8),
          dirChip('Received', _Direction.received),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  final DateTime day;
  const _DayHeader({super.key, required this.day});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    final label = diff == 0
        ? 'Today'
        : diff == 1
            ? 'Yesterday'
            : DateFormat(day.year == now.year ? 'EEE, d MMM' : 'd MMM yyyy')
                .format(day);
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6, left: 2),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: Colors.grey,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  final VoidCallback onClear;
  const _NoMatches({required this.onClear});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(
          children: [
            const Icon(Icons.search_off_rounded, color: Colors.grey, size: 40),
            const SizedBox(height: 8),
            const Text('No payments match',
                style: TextStyle(color: Colors.grey)),
            TextButton(onPressed: onClear, child: const Text('Clear filters')),
          ],
        ),
      );
}

String _when(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  final time = DateFormat('h:mm a').format(d);
  if (diff == 0) return 'Today, $time';
  if (diff == 1) return 'Yesterday, $time';
  return DateFormat('d MMM, h:mm a').format(d);
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final int? of; // total when a filter is narrowing the list
  const _SectionHeader(this.title, this.count, {this.of});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Text(
          of != null
              ? '$title $count of $of'
              : count > 0
                  ? '$title ($count)'
                  : title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoCard({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.blue, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, style: const TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      );
}

const _flagText = {
  'transfer': 'Looks like a transfer between your own accounts',
  'card-bill':
      'Credit card bill payment. Your card purchases are probably logged already, so adding this would count them twice',
  'reversal': 'Reversal of an earlier payment',
  'link': 'Message contains a link, so check it\'s genuine',
};

class _DetectedCard extends StatefulWidget {
  final DetectedTransaction item;
  final bool selecting;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onAdd;
  final VoidCallback onDismiss;
  final ValueChanged<MuteRule> onIgnore;
  const _DetectedCard({
    super.key,
    required this.item,
    required this.selecting,
    required this.selected,
    required this.onToggle,
    required this.onAdd,
    required this.onDismiss,
    required this.onIgnore,
  });

  @override
  State<_DetectedCard> createState() => _DetectedCardState();
}

class _DetectedCardState extends State<_DetectedCard> {
  bool _showRaw = false;

  ExpenseCategory _category(List<ExpenseCategory> categories, String name) =>
      categories.firstWhere(
        (c) => c.name == name,
        orElse: () => ExpenseCategory(
          id: name,
          name: name,
          icon: '📦',
          colorHex: '#747D8C',
        ),
      );

  Future<void> _pickCategory() async {
    final ep = context.read<ExpenseProvider>();
    final cap = context.read<CaptureProvider>();
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            for (final c in ep.categories)
              ListTile(
                leading: Text(c.icon, style: const TextStyle(fontSize: 22)),
                title: Text(c.name, style: const TextStyle(color: Colors.white)),
                trailing: c.name == widget.item.category
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () => Navigator.pop(context, c.name),
              ),
          ],
        ),
      ),
    );
    if (picked != null) await cap.setCategory(widget.item.id, picked);
  }

  Future<void> _editAndAdd() async {
    final cap = context.read<CaptureProvider>();
    final navigator = Navigator.of(context);
    final item = widget.item;
    final account = await cap.accountFor(item.id);
    final saved = await navigator.push<bool>(
      MaterialPageRoute(
        builder: (context) => AddExpenseScreen(
          prefilledAmount: item.amount,
          prefilledPayee: item.merchant,
          prefilledPaymentApp: item.appLabel,
          prefilledTransactionId: 'cap-${item.id}',
          prefilledCategory: item.category,
          prefilledNotes: 'Auto-detected from ${item.appLabel}',
          prefilledDate: item.occurredAt,
          prefilledAccountId: account.id,
        ),
      ),
    );
    if (saved == true) await cap.markAddedFromEditor(item.id);
    // The bank account made just for this edit goes away again if the edit
    // was cancelled or saved against a different account.
    if (account.created && account.id != null) {
      await cap.discardAccountIfUnused(account.id!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final ep = context.watch<ExpenseProvider>();
    final cap = context.read<CaptureProvider>();
    final currency = ep.currency;
    final category = _category(ep.categories, item.category);
    final color = item.isDebit ? category.color : Colors.green;
    final notes = <String>[
      for (final f in item.flags)
        if (_flagText.containsKey(f)) _flagText[f]!,
      if (item.fromImport) 'From SMS import',
    ];

    final primary = Theme.of(context).colorScheme.primary;
    final selected = widget.selected;
    final payeeRule = cap.payeeRuleFor(item);
    final senderRule = cap.senderRuleFor(item);

    Widget card = Card(
        margin: EdgeInsets.zero,
        color: selected ? primary.withValues(alpha: 0.10) : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: selected
              ? BorderSide(color: primary, width: 1.5)
              : BorderSide.none,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: selected
                          ? primary
                          : color.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: selected
                          ? const Icon(Icons.check_rounded,
                              color: Colors.black, size: 22)
                          : item.isDebit
                              ? Text(category.icon,
                                  style: const TextStyle(fontSize: 20))
                              : const Icon(Icons.arrow_downward_rounded,
                                  color: Colors.green, size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${item.appLabel}${item.last4 != null ? ' ••${item.last4}' : ''} · ${_when(item.occurredAt)}',
                          style:
                              const TextStyle(fontSize: 12, color: Colors.grey),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${item.isDebit ? '' : '+'}$currency${item.amount.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: item.isDebit ? Colors.white : Colors.green,
                    ),
                  ),
                ],
              ),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final n in notes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            size: 14, color: Colors.amber),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(n,
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.amber)),
                        ),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  if (item.isDebit)
                    ActionChip(
                      avatar: Text(category.icon),
                      label: Text(category.name),
                      onPressed: _pickCategory,
                    )
                  else
                    const Chip(label: Text('Income')),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() => _showRaw = !_showRaw),
                    child: Text(_showRaw ? 'Hide message' : 'Message'),
                  ),
                  if (payeeRule != null || senderRule != null)
                    PopupMenuButton<MuteRule>(
                      tooltip: 'More',
                      icon: const Icon(Icons.more_vert,
                          color: Colors.grey, size: 20),
                      color: const Color(0xFF1E1E1E),
                      onSelected: widget.onIgnore,
                      itemBuilder: (context) => [
                        if (payeeRule != null)
                          PopupMenuItem(
                            value: payeeRule,
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.storefront_outlined),
                              title: Text('Always ignore ${payeeRule.label}'),
                              subtitle: const Text('Payments to or from them'),
                            ),
                          ),
                        if (senderRule != null)
                          PopupMenuItem(
                            value: senderRule,
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.sms_outlined),
                              title: Text('Always ignore ${senderRule.label}'),
                              subtitle:
                                  const Text('Every message from this sender'),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
              if (_showRaw)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    item.rawText,
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: widget.onDismiss,
                    child: const Text('Dismiss',
                        style: TextStyle(color: Colors.grey)),
                  ),
                  if (item.isDebit) ...[
                    const SizedBox(width: 4),
                    OutlinedButton(
                      onPressed: _editAndAdd,
                      child: const Text('Edit'),
                    ),
                  ],
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: widget.onAdd,
                    icon: const Icon(Icons.check, size: 18),
                    label: Text(item.isDebit ? 'Add' : 'Add income'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

    // In selection mode a tap anywhere on the card toggles it.
    if (widget.selecting) {
      card = Stack(
        children: [
          card,
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: widget.onToggle,
              ),
            ),
          ),
        ],
      );
    } else {
      // Swipe right to add, left to dismiss (both undoable).
      card = Dismissible(
        key: ValueKey('swipe-${item.id}'),
        background: _swipeBackground(
          alignment: Alignment.centerLeft,
          color: Colors.green,
          icon: Icons.check_rounded,
          label: item.isDebit ? 'Add' : 'Add income',
        ),
        secondaryBackground: _swipeBackground(
          alignment: Alignment.centerRight,
          color: const Color(0xFF3A3A3A),
          icon: Icons.close_rounded,
          label: 'Dismiss',
        ),
        onDismissed: (direction) => direction == DismissDirection.startToEnd
            ? widget.onAdd()
            : widget.onDismiss(),
        child: card,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onLongPress: widget.selecting
            ? null
            : () {
                HapticFeedback.selectionClick();
                widget.onToggle();
              },
        child: card,
      ),
    );
  }

  Widget _swipeBackground({
    required Alignment alignment,
    required Color color,
    required IconData icon,
    required String label,
  }) {
    final atStart = alignment == Alignment.centerLeft;
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!atStart)
            Text(label,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          if (!atStart) const SizedBox(width: 8),
          Icon(icon, color: Colors.white),
          if (atStart) const SizedBox(width: 8),
          if (atStart)
            Text(label,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

enum _History { duplicates, added, dismissed }

/// A row that opens one of the history lists on its own page, so restoring
/// several items doesn't collapse the list or shift the page under you.
class _HistoryLink extends StatelessWidget {
  final IconData icon;
  final String title;
  final int count;
  final String subtitle;
  final _History kind;
  const _HistoryLink({
    required this.icon,
    required this.title,
    required this.count,
    required this.subtitle,
    required this.kind,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: Colors.grey),
        title: Text('$title ($count)',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            style: const TextStyle(color: Colors.grey, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => _HistoryScreen(kind: kind))),
      );
}

class _HistoryScreen extends StatefulWidget {
  final _History kind;
  const _HistoryScreen({required this.kind});

  @override
  State<_HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<_HistoryScreen> {
  final _search = TextEditingController();
  bool _searching = false;
  _Filter _filter = const _Filter();

  _History get kind => widget.kind;

  String get _title => switch (kind) {
        _History.duplicates => 'Possibly already logged',
        _History.added => 'Added from detection',
        _History.dismissed => 'Dismissed',
      };

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _closeSearch() {
    _search.clear();
    setState(() {
      _searching = false;
      _filter = _filter.copyWith(query: '');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CaptureProvider>(
      builder: (context, cap, child) {
        final all = switch (kind) {
          _History.duplicates => cap.duplicates,
          _History.added => cap.added,
          _History.dismissed => cap.dismissed,
        };
        final items = _filter.apply(all)
          ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
        final filtered = _filter.active;
        final showNote = kind == _History.duplicates;

        return Scaffold(
          backgroundColor: Colors.black,
          appBar: _searchAppBar(
            title: '$_title (${all.length})',
            searching: _searching,
            controller: _search,
            hint: 'Search payee, amount, bank…',
            onOpen: () => setState(() => _searching = true),
            onClose: _closeSearch,
            onChanged: (q) => setState(() => _filter = _filter.copyWith(query: q)),
            actions: [
              if (kind == _History.dismissed && items.length > 1 && !_searching)
                TextButton(
                  onPressed: () {
                    final ids = items.map((i) => i.id).toList();
                    cap.restoreMany(ids);
                    showUndo(
                      'Moved ${ids.length} back to review',
                      () => cap.dismissMany(ids),
                    );
                  },
                  child: Text(filtered ? 'Restore shown' : 'Restore all'),
                ),
            ],
          ),
          body: all.isEmpty
              ? const Center(
                  child: Text('Nothing here',
                      style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  itemCount: items.isEmpty ? 2 : items.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _FilterBar(
                            filter: _filter,
                            onChanged: (f) => setState(() => _filter = f),
                          ),
                          if (filtered)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                'Showing ${items.length} of ${all.length}',
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 12),
                              ),
                            ),
                          if (showNote)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: Text(
                                'These matched an entry you added yourself, so they weren\'t added again.',
                                style:
                                    TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                            ),
                        ],
                      );
                    }
                    if (items.isEmpty) {
                      return _NoMatches(onClear: () {
                        _search.clear();
                        setState(() => _filter = const _Filter());
                      });
                    }
                    final item = items[index - 1];
                    return switch (kind) {
                      _History.dismissed => _CompactRow(
                          key: ValueKey(item.id),
                          item: item,
                          actionLabel: 'Restore',
                          onAction: () {
                            cap.restore(item.id);
                            showUndo('Moved back to review',
                                () => cap.dismiss(item.id));
                          },
                        ),
                      _History.duplicates => _CompactRow(
                          key: ValueKey(item.id),
                          item: item,
                          actionLabel: 'Add anyway',
                          onAction: () => cap.restore(item.id),
                        ),
                      _History.added =>
                        _CompactRow(key: ValueKey(item.id), item: item),
                    };
                  },
                ),
        );
      },
    );
  }
}

class _CompactRow extends StatelessWidget {
  final DetectedTransaction item;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _CompactRow(
      {super.key, required this.item, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    final currency = context.read<ExpenseProvider>().currency;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        item.title,
        style: const TextStyle(color: Colors.white),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${item.appLabel} · ${_when(item.occurredAt)}',
        style: const TextStyle(color: Colors.grey, fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${item.isDebit ? '' : '+'}$currency${item.amount.toStringAsFixed(0)}',
            style: TextStyle(
                color: item.isDebit ? Colors.white : Colors.green,
                fontWeight: FontWeight.w600),
          ),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}
