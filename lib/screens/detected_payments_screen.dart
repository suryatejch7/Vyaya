import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/expense_models.dart';
import '../providers/capture_provider.dart';
import '../providers/expense_provider.dart';
import '../services/capture/capture_models.dart';
import '../services/capture/merchant_categorizer.dart';
import 'add_expense_screen.dart';
import '../widgets/undo_bar.dart';
import '../widgets/undo_snackbar.dart';

/// Review list for payments picked up from bank SMS / payment apps.
///
/// Layout, top to bottom:
/// - a sliding row of "buckets" (All, Check these, suggested kinds like
///   "Gym?", Income, then your categories, biggest first) with counts;
/// - sort, amount and date chips;
/// - compact two-line cards under day headers (tap to open, swipe right to
///   add, left to dismiss, long-press to select);
/// - a bar at the bottom with the totals and Add all / Dismiss all.
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

  /// True while Add all / Dismiss all runs, so a second tap can't start the
  /// same batch again.
  bool _busy = false;

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

  void _setFilter(_Filter f) {
    final listChanged = f.bucket != _filter.bucket ||
        f.sort != _filter.sort ||
        f.minAmount != _filter.minAmount ||
        f.maxAmount != _filter.maxAmount ||
        f.range != _filter.range ||
        f.direction != _filter.direction;
    setState(() => _filter = f);
    // A new view starts at the top, not somewhere in the middle.
    if (listChanged && _scroll.hasClients) _scroll.jumpTo(0);
  }

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
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final done = await cap.dismissAll(only: ids.toList());
      // The undo still shows if you left the screen while it ran.
      if (mounted) setState(_selected.clear);
      showUndo(
          'Dismissed ${_payments(done.length)}', () => cap.restoreMany(done));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addMany(CaptureProvider cap, Iterable<String> ids,
      {required bool skipFlagged}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await cap.acceptAll(only: ids.toList(), skipFlagged: skipFlagged);
      if (mounted) setState(_selected.clear);
      final left = r.skipped == 0
          ? ''
          : ' · ${r.skipped} transfer/card bill left to review';
      showUndo(
          'Added ${_payments(r.added)}$left', () => cap.unacceptMany(r.ids));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// "Remove from list": clears payments from this list for good (not just
  /// dismissed), e.g. after importing a month when you only wanted a week.
  Future<void> _openRemoveSheet(CaptureProvider cap,
      List<DetectedTransaction> shown, bool filtered) async {
    final history = [...cap.added, ...cap.duplicates];
    final choice = await showModalBottomSheet<_Clear>(
      context: context,
      backgroundColor: const Color(0xFF121212),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => _RemoveSheet(
        shown: filtered ? shown.length : 0,
        waiting: cap.pending.length,
        dismissed: cap.dismissed.length,
        history: history.length,
        everything: cap.pending.length +
            cap.added.length +
            cap.dismissed.length +
            cap.duplicates.length,
      ),
    );
    if (choice == null) return;
    final removed = switch (choice) {
      _Clear.shown => await cap.removeItems(ids: shown.map((i) => i.id)),
      _Clear.waiting => await cap.removeItems(),
      _Clear.dismissed =>
        await cap.removeItems(ids: cap.dismissed.map((i) => i.id)),
      _Clear.history => await cap.removeItems(ids: history.map((i) => i.id)),
      _Clear.everything => await cap.removeItems(everything: true),
    };
    if (!mounted) return;
    setState(_selected.clear);
    if (removed.isEmpty) return;
    showUndo('Removed ${_payments(removed.length)}', () => cap.putBack(removed));
  }

  void _toggle(String id) => setState(() {
        if (!_selected.remove(id)) _selected.add(id);
      });

  /// Selects every payment of one day (or clears them if all were picked).
  void _toggleMany(List<String> ids) => setState(() {
        if (ids.every(_selected.contains)) {
          _selected.removeAll(ids);
        } else {
          _selected.addAll(ids);
        }
      });

  // ------------------------------------------------- category suggestions

  /// "Create Gym" from the banner: makes the category, moves every payment
  /// like it there and switches the view to it.
  Future<void> _createSuggested(CaptureProvider cap, CategoryGroup g) async {
    final name = await cap.createCategoryForGroup(g);
    if (!mounted) return;
    _setFilter(_filter.withBucket(name));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('"$name" category created'),
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _stopSuggesting(CaptureProvider cap, CategoryGroup g) async {
    final stop = await _confirmStopSuggesting(context, g);
    if (stop != true) return;
    await cap.dismissGroup(g);
    if (mounted) _setFilter(_filter.withBucket(null));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CaptureProvider>(
      builder: (context, cap, child) {
        final ep = context.read<ExpenseProvider>();
        final currency = ep.currency;
        final allPending = cap.pending;
        final duplicates = cap.duplicates;
        final added = cap.added;
        final dismissed = cap.dismissed;
        final filtered = _filter.active;
        final primary = Theme.of(context).colorScheme.primary;

        // Drop selections that are no longer waiting for review.
        final pendingIds = {for (final i in allPending) i.id};
        _selected.removeWhere((id) => !pendingIds.contains(id));

        // Everything that passes search / amount / date, before the bucket
        // is applied, so each bucket chip can show its own count.
        String? hintKey(DetectedTransaction i) =>
            cap.newCategoryHint(i)?.key;
        final base = [
          for (final i in allPending)
            if (!_hiding.contains(i.id) && _filter.matches(i)) i
        ];
        final buckets = _Buckets.count(base, cap.newCategoryHint);
        final pending = _filter.sortList([
          for (final i in base)
            if (_filter.matchesBucket(i, hintKey)) i
        ]);

        // A bucket that just emptied (all added, say) falls back to All.
        final bucket = _filter.bucket;
        // Other filters narrowing it to nothing don't count: only a bucket
        // with no waiting payments at all is left.
        if (bucket != null &&
            !allPending.any((i) =>
                !_hiding.contains(i.id) && _filter.matchesBucket(i, hintKey))) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _filter.bucket == bucket) {
              _setFilter(_filter.withBucket(null));
            }
          });
        }

        // Cards, under a header per day (date sorts) or per payee (payee
        // sort); amount sorts are one plain list.
        // Group key: the day (a DateTime) or the payee; null = no headers.
        final Object? Function(DetectedTransaction) groupOf =
            switch (_filter.sort) {
          _Sort.newest || _Sort.oldest => (DetectedTransaction i) {
              final d = i.occurredAt;
              return DateTime(d.year, d.month, d.day);
            },
          _Sort.payee => (DetectedTransaction i) => _payeeKey(i),
          _ => (DetectedTransaction _) => null,
        };
        final byDate =
            _filter.sort == _Sort.newest || _filter.sort == _Sort.oldest;
        final rows = <Widget>[];
        var start = 0;
        while (start < pending.length) {
          final g = groupOf(pending[start]);
          var end = start + 1;
          while (end < pending.length && g != null &&
              groupOf(pending[end]) == g) {
            end++;
          }
          final groupItems = pending.sublist(start, end);
          if (g != null) {
            final ids = [for (final i in groupItems) i.id];
            rows.add(_GroupHeader(
              key: ValueKey('group-$g'),
              label: g is DateTime ? _dayLabel(g) : groupItems.first.title,
              items: groupItems,
              currency: currency,
              allSelected: _selecting && ids.every(_selected.contains),
              onSelect: () => _toggleMany(ids),
            ));
          }
          for (final item in groupItems) {
            rows.add(_card(cap, item, showDay: !byDate));
          }
          start = end;
        }

        final allShownSelected =
            pending.isNotEmpty && pending.every((i) => _selected.contains(i.id));
        final hintGroup = bucket != null && bucket.startsWith(_Buckets.hint)
            ? buckets.groups[bucket.substring(_Buckets.hint.length)]
            : null;

        // Above the cards: notices, the suggestion banner, empty states.
        final top = <Widget>[
          if (!cap.isEnabled)
            const _InfoCard(
              icon: Icons.info_outline,
              text:
                  'Auto-detection is off. Turn it on in Settings → Auto-detect Payments.',
            ),
          if (hintGroup != null && pending.isNotEmpty)
            _SuggestionBanner(
              group: hintGroup,
              count: pending.length,
              onCreate: () => _createSuggested(cap, hintGroup),
              onStop: () => _stopSuggesting(cap, hintGroup),
            ),
          if (pending.length > 1 && !_selecting && !filtered)
            const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 2),
              child: Text(
                'Tap a payment for details. Swipe right to add, left to dismiss. Long-press to select several.',
                style: TextStyle(color: Colors.grey, fontSize: 11),
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
              _setFilter(_Filter(sort: _filter.sort));
            })
        ];
        final shownRows = pending.isEmpty ? const <Widget>[] : rows;
        // Lets a card keep its state (open details…) when cards above it
        // come and go.
        final rowIndex = <Key, int>{
          for (var j = 0; j < shownRows.length; j++)
            if (shownRows[j].key != null) shownRows[j].key!: j,
        };
        final bottom = <Widget>[
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
                      color: Colors.white, fontWeight: FontWeight.w600)),
              subtitle: const Text('Payees and senders that never show up here',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const MuteRulesScreen())),
            ),
        ];

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
                ],
              )
            : _searchAppBar(
                title: 'Detected Payments',
                searching: _searching,
                controller: _search,
                hint: 'Search payee, amount, bank…',
                onOpen: () => setState(() => _searching = true),
                onClose: _closeSearch,
                onChanged: (q) => setState(
                    () => _filter = _filter.copyWith(query: q)),
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

        // Totals for the bottom bar: the selection, or everything shown.
        final barItems = _selecting
            ? [for (final i in allPending) if (_selected.contains(i.id)) i]
            : pending;

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
            // UndoLift keeps the undo bar above this bar instead of on it.
            bottomNavigationBar: barItems.isEmpty
                ? null
                : UndoLift(
                    height: 36 + MediaQuery.of(context).padding.bottom,
                    child: _BottomBar(
                    items: barItems,
                    currency: currency,
                    selecting: _selecting,
                    filtered: filtered,
                    total: allPending.length,
                    busy: _busy,
                    primary: primary,
                    onDismiss: () => _dismissMany(
                        cap,
                        _selecting
                            ? _selected.toList()
                            : pending.map((i) => i.id)),
                    // Add all skips transfers and card bills; a hand-picked
                    // selection adds exactly what you picked.
                    onAdd: () => _selecting
                        ? _addMany(cap, _selected.toList(), skipFlagged: false)
                        : _addMany(cap, pending.map((i) => i.id),
                            skipFlagged: true),
                    ),
                  ),
            body: Column(
              children: [
                // Pinned, so you can switch views from deep in the list.
                if (allPending.isNotEmpty) ...[
                  _BucketBar(
                    buckets: buckets,
                    selected: _filter.bucket,
                    categories: ep.categories,
                    onChanged: (b) => _setFilter(_filter.withBucket(b)),
                  ),
                  _FilterBar(
                    filter: _filter,
                    currency: currency,
                    showDirection: false,
                    onChanged: _setFilter,
                  ),
                ],
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: cap.sync,
                    // Built lazily: only the cards on screen are built, so
                    // hundreds of payments scroll smoothly.
                    child: ListView.builder(
                      controller: _scroll,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 72),
                      itemCount: top.length + shownRows.length + bottom.length,
                      findChildIndexCallback: (key) {
                        final j = rowIndex[key];
                        return j == null ? null : top.length + j;
                      },
                      itemBuilder: (context, i) {
                        if (i < top.length) return top[i];
                        i -= top.length;
                        if (i < shownRows.length) return shownRows[i];
                        return bottom[i - shownRows.length];
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Keyed so a card's state (open details, etc.) stays with its payment
  // when others are added or dismissed.
  Widget _card(CaptureProvider cap, DetectedTransaction item,
          {required bool showDay}) =>
      _DetectedCard(
        key: ValueKey(item.id),
        item: item,
        showDay: showDay,
        selecting: _selecting,
        selected: _selected.contains(item.id),
        onToggle: () => _toggle(item.id),
        onAdd: () => _addOne(cap, item),
        onDismiss: () => _dismissOne(cap, item),
        onIgnore: (rule) => _ignore(cap, rule),
      );
}

/// Shared "Stop suggesting Gym?" question.
Future<bool?> _confirmStopSuggesting(BuildContext context, CategoryGroup g) =>
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: Text('Stop suggesting ${g.name}?',
            style: const TextStyle(color: Colors.white)),
        content: const Text(
          'Payments like this will stay in Other, or whatever you pick. '
          'You can turn suggestions back on in Optional features.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Stop suggesting')),
        ],
      ),
    );

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

final _money = NumberFormat.decimalPattern('en_IN');
final _moneyPaise = NumberFormat('#,##,##0.00', 'en_IN');

/// ₹1,240 (no paise for whole amounts).
String _fmt(String currency, double v) {
  final whole = v == v.roundToDouble();
  return '$currency${whole ? _money.format(v.round()) : _moneyPaise.format(v)}';
}

/// "42 to review · ₹12,340 out · ₹2,000 in" with Dismiss / Add buttons.
class _BottomBar extends StatelessWidget {
  final List<DetectedTransaction> items;
  final String currency;
  final bool selecting;
  final bool filtered;
  final int total;
  final bool busy;
  final Color primary;
  final VoidCallback onDismiss;
  final VoidCallback onAdd;
  const _BottomBar({
    required this.items,
    required this.currency,
    required this.selecting,
    required this.filtered,
    required this.total,
    required this.busy,
    required this.primary,
    required this.onDismiss,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    var out = 0.0, inc = 0.0;
    for (final i in items) {
      if (i.isDebit) {
        out += i.amount;
      } else {
        inc += i.amount;
      }
    }
    final n = items.length;
    final head = selecting
        ? '$n selected'
        : filtered
            ? '$n of $total shown'
            : '$n to review';
    final sums = [
      if (out > 0) '${_fmt(currency, out)} out',
      if (inc > 0) '${_fmt(currency, inc)} in',
    ].join(' · ');
    final what = selecting ? 'selected' : (filtered ? 'shown' : 'all');

    return Material(
      color: const Color(0xFF0D0D0D),
      child: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFF222222))),
          ),
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(head,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                    if (sums.isNotEmpty)
                      Text(sums,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
              TextButton(
                onPressed: busy ? null : onDismiss,
                style: TextButton.styleFrom(foregroundColor: Colors.grey),
                child: Text(n == 1 ? 'Dismiss' : 'Dismiss $what'),
              ),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: busy ? null : onAdd,
                style: FilledButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.black,
                  visualDensity: VisualDensity.compact,
                ),
                child: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(n == 1 ? 'Add' : 'Add $what'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "6 payments look like 🏋️ Gym" with Create / Stop suggesting. Shown once
/// at the top when that bucket is picked, instead of on every card.
class _SuggestionBanner extends StatelessWidget {
  final CategoryGroup group;
  final int count;
  final VoidCallback onCreate;
  final VoidCallback onStop;
  const _SuggestionBanner({
    required this.group,
    required this.count,
    required this.onCreate,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 6, bottom: 4),
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${count == 1 ? '1 payment looks' : '$count payments look'} like ${group.icon} ${group.name}. You have no category for it yet.',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            Row(
              children: [
                TextButton(
                  onPressed: onCreate,
                  child: Text('Create ${group.name}'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: onStop,
                  style: TextButton.styleFrom(foregroundColor: Colors.grey),
                  child: const Text('Stop suggesting'),
                ),
              ],
            ),
          ],
        ),
      );
}

// ------------------------------------------------------------ remove sheet

/// What "Remove from list" can clear.
enum _Clear { shown, waiting, dismissed, history, everything }

/// "Remove from list": a 2×2 grid of tiles (Waiting, Dismissed, History,
/// Everything), each with its count, plus "Remove the N shown" on top when
/// a filter is on. Everything asks for a second tap.
class _RemoveSheet extends StatefulWidget {
  final int shown; // 0 when no filter is on
  final int waiting;
  final int dismissed;
  final int history;
  final int everything;
  const _RemoveSheet({
    required this.shown,
    required this.waiting,
    required this.dismissed,
    required this.history,
    required this.everything,
  });

  @override
  State<_RemoveSheet> createState() => _RemoveSheetState();
}

class _RemoveSheetState extends State<_RemoveSheet>
    with TickerProviderStateMixin {
  // Tiles drift up one after another as the sheet opens.
  late final AnimationController _enter = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 520))
    ..forward();

  // "Tap again" window for Everything; the bar under it runs down.
  late final AnimationController _confirm = AnimationController(
      vsync: this, duration: const Duration(seconds: 3))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _armed = false);
      }
    });
  bool _armed = false;

  late final List<CurvedAnimation> _tileAnims = List.generate(
      4,
      (i) => CurvedAnimation(
            parent: _enter,
            curve:
                Interval(0.1 * i, 0.55 + 0.1 * i, curve: Curves.easeOutCubic),
          ));

  @override
  void dispose() {
    for (final a in _tileAnims) {
      a.dispose();
    }
    _enter.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _pick(_Clear c) {
    HapticFeedback.selectionClick();
    Navigator.pop(context, c);
  }

  void _everything() {
    if (_armed) {
      HapticFeedback.heavyImpact();
      Navigator.pop(context, _Clear.everything);
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _armed = true);
    _confirm.forward(from: 0);
  }

  /// Slide + fade for tile [i] of 4.
  Widget _stagger(int i, Widget child) {
    final a = _tileAnims[i];
    return FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero)
            .animate(a),
        child: child,
      ),
    );
  }

  String _n(int n) => '$n ${n == 1 ? 'payment' : 'payments'}';

  @override
  Widget build(BuildContext context) {
    final w = widget;
    return SafeArea(
      // Scrolls on short screens / landscape instead of overflowing.
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(child: _SheetHandle()),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text('Clean up the list',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 4),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Only this list is cleared. Expenses and income you added stay, and you can undo.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
            const SizedBox(height: 14),
            if (w.shown > 0) ...[
              _PressScale(
                onTap: () => _pick(_Clear.shown),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.filter_alt_rounded,
                          color: Colors.white70, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('Remove the ${_n(w.shown)} shown',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600)),
                      ),
                      const Text('Matches your filters',
                          style: TextStyle(color: Colors.grey, fontSize: 11)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              // Tile height grows with the phone's font size.
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                mainAxisExtent:
                    40 + MediaQuery.textScalerOf(context).scale(100),
              ),
              children: [
                _stagger(
                  0,
                  _ClearTile(
                    icon: Icons.inbox_rounded,
                    color: Colors.lightBlueAccent,
                    title: 'Waiting',
                    subtitle: 'Not added or dismissed yet',
                    count: w.waiting,
                    onTap: () => _pick(_Clear.waiting),
                  ),
                ),
                _stagger(
                  1,
                  _ClearTile(
                    icon: Icons.do_not_disturb_on_rounded,
                    color: Colors.blueGrey.shade200,
                    title: 'Dismissed',
                    subtitle: 'Ones you said no to',
                    count: w.dismissed,
                    onTap: () => _pick(_Clear.dismissed),
                  ),
                ),
                _stagger(
                  2,
                  _ClearTile(
                    icon: Icons.history_rounded,
                    color: Colors.greenAccent,
                    title: 'History',
                    subtitle: 'Added + already logged. Expenses stay',
                    count: w.history,
                    onTap: () => _pick(_Clear.history),
                  ),
                ),
                _stagger(
                  3,
                  _ClearTile(
                    icon: _armed
                        ? Icons.warning_rounded
                        : Icons.delete_sweep_rounded,
                    color: Colors.redAccent,
                    title: _armed ? 'Tap again' : 'Everything',
                    subtitle: _armed
                        ? 'to clear all ${w.everything}'
                        : 'Empties every list here',
                    count: w.everything,
                    filled: _armed,
                    progress: _armed ? _confirm : null,
                    onTap: _everything,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shrinks a little while pressed, like a real button.
class _PressScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _PressScale({required this.child, this.onTap});

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap != null && v != _down) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.95 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      );
}

class _ClearTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final int count;
  final bool filled;
  final Animation<double>? progress; // "tap again" time left
  final VoidCallback onTap;
  const _ClearTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.count,
    required this.onTap,
    this.filled = false,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final empty = count == 0;
    final fg = filled ? Colors.black : Colors.white;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: empty ? 0.35 : 1,
      child: _PressScale(
        onTap: empty ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: filled ? color : color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.30)),
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: filled
                                ? Colors.black.withValues(alpha: 0.15)
                                : color.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(icon,
                              size: 19, color: filled ? Colors.black : color),
                        ),
                        const Spacer(),
                        Text(
                          '$count',
                          style: TextStyle(
                            color: fg,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: fg,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: filled ? Colors.black87 : Colors.grey,
                            fontSize: 11.5)),
                  ],
                ),
              ),
              if (progress != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: AnimatedBuilder(
                    animation: progress!,
                    builder: (context, _) => LinearProgressIndicator(
                      value: 1 - progress!.value,
                      minHeight: 3,
                      color: Colors.black54,
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
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

/// How the list is ordered.
enum _Sort { newest, oldest, highest, lowest, payee }

const _sortLabels = {
  _Sort.newest: ('Newest first', 'Newest', Icons.south_rounded),
  _Sort.oldest: ('Oldest first', 'Oldest', Icons.north_rounded),
  _Sort.highest: ('Highest amount', 'Highest', Icons.trending_up_rounded),
  _Sort.lowest: ('Lowest amount', 'Lowest', Icons.trending_down_rounded),
  _Sort.payee: ('Payee A–Z (grouped)', 'Payee A–Z', Icons.sort_by_alpha_rounded),
};

/// Transfers, card bills, reversals and odd links: worth a second look.
bool _isFlagged(DetectedTransaction i) => i.flags.any(_flagText.containsKey);

/// Search text, date range, paid/received, amount range, bucket and sort,
/// applied to any list of detected payments.
class _Filter {
  final String query;
  final DateTimeRange? range;
  final String? rangeLabel; // "Last 7 days" etc. for presets
  final _Direction direction;
  final double? minAmount; // at least
  final double? maxAmount; // at most

  /// The bucket picked in the top row: a category name, or one of
  /// [_Buckets.check], [_Buckets.income], [_Buckets.hint]+key. Null = All.
  final String? bucket;
  final _Sort sort;

  const _Filter({
    this.query = '',
    this.range,
    this.rangeLabel,
    this.direction = _Direction.all,
    this.minAmount,
    this.maxAmount,
    this.bucket,
    this.sort = _Sort.newest,
  });

  /// Anything narrowing the list (the sort order doesn't).
  bool get active =>
      query.trim().isNotEmpty ||
      range != null ||
      direction != _Direction.all ||
      minAmount != null ||
      maxAmount != null ||
      bucket != null;

  static const Object _keep = Object();

  _Filter _with({
    Object? query = _keep,
    Object? range = _keep,
    Object? rangeLabel = _keep,
    Object? direction = _keep,
    Object? minAmount = _keep,
    Object? maxAmount = _keep,
    Object? bucket = _keep,
    Object? sort = _keep,
  }) =>
      _Filter(
        query: identical(query, _keep) ? this.query : query as String,
        range: identical(range, _keep) ? this.range : range as DateTimeRange?,
        rangeLabel: identical(rangeLabel, _keep)
            ? this.rangeLabel
            : rangeLabel as String?,
        direction: identical(direction, _keep)
            ? this.direction
            : direction as _Direction,
        minAmount:
            identical(minAmount, _keep) ? this.minAmount : minAmount as double?,
        maxAmount:
            identical(maxAmount, _keep) ? this.maxAmount : maxAmount as double?,
        bucket: identical(bucket, _keep) ? this.bucket : bucket as String?,
        sort: identical(sort, _keep) ? this.sort : sort as _Sort,
      );

  _Filter copyWith({String? query, _Direction? direction}) => _with(
        query: query ?? this.query,
        direction: direction ?? this.direction,
      );

  _Filter withRange(DateTimeRange? r, [String? label]) =>
      _with(range: r, rangeLabel: r == null ? null : label);

  _Filter withAmount(double? min, double? max) {
    if (min != null && max != null && min > max) {
      final t = min;
      min = max;
      max = t;
    }
    return _with(minAmount: min, maxAmount: max);
  }

  _Filter withBucket(String? b) => _with(bucket: b);
  _Filter withSort(_Sort s) => _with(sort: s);

  /// Everything except the bucket.
  bool matches(DetectedTransaction i) {
    if (direction == _Direction.paid && !i.isDebit) return false;
    if (direction == _Direction.received && i.isDebit) return false;
    if (minAmount != null && i.amount < minAmount!) return false;
    if (maxAmount != null && i.amount > maxAmount!) return false;
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

  bool matchesBucket(DetectedTransaction i,
      [String? Function(DetectedTransaction)? hintKey]) {
    final b = bucket;
    if (b == null) return true;
    if (b == _Buckets.check) return _isFlagged(i);
    if (b == _Buckets.income) return !i.isDebit;
    if (b.startsWith(_Buckets.hint)) {
      return hintKey?.call(i) == b.substring(_Buckets.hint.length);
    }
    return i.isDebit && i.category == b;
  }

  /// Sorts [items] in place and returns it. Ties go newest first.
  List<DetectedTransaction> sortList(List<DetectedTransaction> items) {
    int newest(DetectedTransaction a, DetectedTransaction b) =>
        b.occurredAt.compareTo(a.occurredAt);
    switch (sort) {
      case _Sort.newest:
        items.sort(newest);
      case _Sort.oldest:
        items.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
      case _Sort.highest:
        items.sort((a, b) {
          final c = b.amount.compareTo(a.amount);
          return c != 0 ? c : newest(a, b);
        });
      case _Sort.lowest:
        items.sort((a, b) {
          final c = a.amount.compareTo(b.amount);
          return c != 0 ? c : newest(a, b);
        });
      case _Sort.payee:
        items.sort((a, b) {
          final c = _payeeKey(a).compareTo(_payeeKey(b));
          return c != 0 ? c : newest(a, b);
        });
    }
    return items;
  }

  List<DetectedTransaction> apply(List<DetectedTransaction> items) => sortList(
      active ? items.where((i) => matches(i) && matchesBucket(i)).toList()
          : List.of(items));
}

/// Groups "SWIGGY", "Swiggy" and "swiggy " together when sorting by payee.
String _payeeKey(DetectedTransaction i) =>
    i.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

/// Counts for the bucket row, worked out from what passes the other filters.
class _Buckets {
  static const check = '@check';
  static const income = '@in';
  static const hint = '@hint:';

  final int total;
  final int checkCount;
  final int incomeCount;

  /// Paid payments per category, biggest first.
  final List<MapEntry<String, int>> categories;

  /// "Gym?"-style suggestions: group key → count, and the groups themselves.
  final List<MapEntry<String, int>> hints;
  final Map<String, CategoryGroup> groups;

  const _Buckets._(this.total, this.checkCount, this.incomeCount,
      this.categories, this.hints, this.groups);

  static _Buckets count(
    List<DetectedTransaction> items,
    CategoryGroup? Function(DetectedTransaction) hintOf,
  ) {
    var check = 0, income = 0;
    final cats = <String, int>{};
    final hints = <String, int>{};
    final groups = <String, CategoryGroup>{};
    for (final i in items) {
      if (_isFlagged(i)) check++;
      if (!i.isDebit) {
        income++;
        continue;
      }
      cats[i.category] = (cats[i.category] ?? 0) + 1;
      final g = hintOf(i);
      if (g != null) {
        hints[g.key] = (hints[g.key] ?? 0) + 1;
        groups[g.key] = g;
      }
    }
    int big(MapEntry<String, int> a, MapEntry<String, int> b) {
      final c = b.value.compareTo(a.value);
      return c != 0 ? c : a.key.compareTo(b.key);
    }

    return _Buckets._(
      items.length,
      check,
      income,
      cats.entries.toList()..sort(big),
      hints.entries.toList()..sort(big),
      groups,
    );
  }
}

/// The sliding row at the top: All · ⚠ Check · 💡 Gym? · 💰 Income ·
/// 🍔 Food · 🛍 Shopping… each with its count. Empty ones are left out
/// (unless it's the one picked).
class _BucketBar extends StatelessWidget {
  final _Buckets buckets;
  final String? selected;
  final List<ExpenseCategory> categories;
  final ValueChanged<String?> onChanged;
  const _BucketBar({
    required this.buckets,
    required this.selected,
    required this.categories,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    String iconOf(String name) {
      for (final c in categories) {
        if (c.name == name) return c.icon;
      }
      return '📦';
    }

    Widget chip(String? key, String label, int count, {Color? tint}) {
      final on = selected == key;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          selected: on,
          showCheckmark: false,
          onSelected: (_) => onChanged(on ? null : key),
          visualDensity: VisualDensity.compact,
          label: Text.rich(TextSpan(children: [
            TextSpan(text: label),
            TextSpan(
              text: '  $count',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: on ? Colors.black54 : Colors.white38,
              ),
            ),
          ])),
          labelStyle: TextStyle(
              color: on ? Colors.black : (tint ?? Colors.white70),
              fontSize: 13),
          selectedColor: primary,
          backgroundColor: tint == null
              ? const Color(0xFF1A1A1A)
              : tint.withValues(alpha: 0.12),
          side: BorderSide.none,
          shape: const StadiumBorder(),
        ),
      );
    }

    final b = buckets;
    final chips = <Widget>[
      chip(null, 'All', b.total),
      if (b.checkCount > 0 || selected == _Buckets.check)
        chip(_Buckets.check, '⚠ Check', b.checkCount, tint: Colors.amber),
      for (final h in b.hints)
        chip('${_Buckets.hint}${h.key}',
            '${b.groups[h.key]!.icon} ${b.groups[h.key]!.name}?', h.value,
            tint: Colors.amber),
      if (b.incomeCount > 0 || selected == _Buckets.income)
        chip(_Buckets.income, '💰 Income', b.incomeCount, tint: Colors.green),
      for (final c in b.categories) chip(c.key, '${iconOf(c.key)} ${c.key}', c.value),
      // The picked category, when other filters left none of it.
      if (selected != null &&
          !selected!.startsWith('@') &&
          !b.categories.any((c) => c.key == selected))
        chip(selected, '${iconOf(selected!)} $selected', 0),
    ];

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: chips,
      ),
    );
  }
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

/// Sort, amount, date (and paid/received) chips.
class _FilterBar extends StatelessWidget {
  final _Filter filter;
  final String currency;
  final bool showDirection;
  final ValueChanged<_Filter> onChanged;
  const _FilterBar({
    required this.filter,
    required this.onChanged,
    this.currency = '₹',
    this.showDirection = true,
  });

  String _dateLabel() {
    final r = filter.range;
    if (r == null) return 'Any date';
    if (filter.rangeLabel != null) return filter.rangeLabel!;
    final f = DateFormat('d MMM');
    return r.start == r.end
        ? f.format(r.start)
        : '${f.format(r.start)} – ${f.format(r.end)}';
  }

  String _amountLabel() {
    final lo = filter.minAmount, hi = filter.maxAmount;
    if (lo != null && hi != null) {
      return '${_fmt(currency, lo)}–${_fmt(currency, hi)}';
    }
    if (lo != null) return 'Over ${_fmt(currency, lo)}';
    if (hi != null) return 'Under ${_fmt(currency, hi)}';
    return 'Any amount';
  }

  Future<void> _pickSort(BuildContext context) async {
    final primary = Theme.of(context).colorScheme.primary;
    final picked = await showModalBottomSheet<_Sort>(
      context: context,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SheetHandle(),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Sort by',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ),
            ),
            for (final s in _Sort.values)
              ListTile(
                leading: Icon(_sortLabels[s]!.$3, color: primary),
                title: Text(_sortLabels[s]!.$1,
                    style: const TextStyle(color: Colors.white)),
                trailing: filter.sort == s
                    ? Icon(Icons.check, color: primary)
                    : null,
                onTap: () => Navigator.pop(context, s),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) onChanged(filter.withSort(picked));
  }

  Future<void> _pickAmount(BuildContext context) async {
    final picked = await showModalBottomSheet<(double?, double?)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => _AmountSheet(
        currency: currency,
        min: filter.minAmount,
        max: filter.maxAmount,
      ),
    );
    if (picked != null) onChanged(filter.withAmount(picked.$1, picked.$2));
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
            const _SheetHandle(),
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
    final primary = Theme.of(context).colorScheme.primary;
    final hasDate = filter.range != null;
    final hasAmount = filter.minAmount != null || filter.maxAmount != null;
    final sorted = filter.sort != _Sort.newest;

    Widget dirChip(String label, _Direction d) => ChoiceChip(
          label: Text(label),
          selected: filter.direction == d,
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          onSelected: (on) =>
              onChanged(filter.copyWith(direction: on ? d : _Direction.all)),
          labelStyle: TextStyle(
              color: filter.direction == d ? Colors.black : Colors.white70),
          selectedColor: primary,
          backgroundColor: const Color(0xFF1A1A1A),
          side: BorderSide.none,
          shape: const StadiumBorder(),
        );

    // A chip that opens a sheet; filled in when it's narrowing the list,
    // with an ✕ to clear it.
    Widget pickChip({
      required IconData icon,
      required String label,
      required bool on,
      required VoidCallback onTap,
      VoidCallback? onClear,
    }) =>
        InputChip(
          avatar: Icon(icon, size: 16, color: on ? Colors.black : Colors.white70),
          label: Text(label),
          selected: on,
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          onPressed: onTap,
          onDeleted: on ? onClear : null,
          deleteIconColor: Colors.black,
          labelStyle: TextStyle(color: on ? Colors.black : Colors.white70),
          selectedColor: primary,
          backgroundColor: const Color(0xFF1A1A1A),
          side: BorderSide.none,
          shape: const StadiumBorder(),
        );

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          pickChip(
            icon: Icons.swap_vert_rounded,
            label: _sortLabels[filter.sort]!.$2,
            on: sorted,
            onTap: () => _pickSort(context),
            onClear: () => onChanged(filter.withSort(_Sort.newest)),
          ),
          const SizedBox(width: 6),
          pickChip(
            icon: Icons.currency_rupee_rounded,
            label: _amountLabel(),
            on: hasAmount,
            onTap: () => _pickAmount(context),
            onClear: () => onChanged(filter.withAmount(null, null)),
          ),
          const SizedBox(width: 6),
          pickChip(
            icon: Icons.calendar_today_rounded,
            label: _dateLabel(),
            on: hasDate,
            onTap: () => _pickDate(context),
            onClear: () => onChanged(filter.withRange(null)),
          ),
          if (showDirection) ...[
            const SizedBox(width: 6),
            dirChip('Paid', _Direction.paid),
            const SizedBox(width: 6),
            dirChip('Received', _Direction.received),
          ],
        ],
      ),
    );
  }
}

/// "Show payments of": quick ranges plus your own at-least / at-most.
/// Pops (min, max); (null, null) means any amount.
class _AmountSheet extends StatefulWidget {
  final String currency;
  final double? min;
  final double? max;
  const _AmountSheet({required this.currency, this.min, this.max});

  @override
  State<_AmountSheet> createState() => _AmountSheetState();
}

class _AmountSheetState extends State<_AmountSheet> {
  late final _min = TextEditingController(text: _text(widget.min));
  late final _max = TextEditingController(text: _text(widget.max));

  static String _text(double? v) => v == null
      ? ''
      : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString());

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  double? _read(TextEditingController c) {
    final v = double.tryParse(c.text.replaceAll(',', '').trim());
    return (v == null || v < 0) ? null : v;
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final c = widget.currency;
    final presets = <(String, double?, double?)>[
      ('Under ${c}100', null, 100.0),
      ('${c}100–${c}1,000', 100.0, 1000.0),
      ('Over ${c}1,000', 1000.0, null),
      ('Over ${c}5,000', 5000.0, null),
    ];

    InputDecoration box(String label) => InputDecoration(
          labelText: label,
          prefixText: c,
          isDense: true,
          border: const OutlineInputBorder(),
        );

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: _SheetHandle()),
              const SizedBox(height: 16),
              const Text('Show payments of',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (label, lo, hi) in presets)
                    ActionChip(
                      label: Text(label),
                      backgroundColor: (widget.min == lo && widget.max == hi)
                          ? primary.withValues(alpha: 0.25)
                          : const Color(0xFF1A1A1A),
                      side: BorderSide.none,
                      shape: const StadiumBorder(),
                      labelStyle: const TextStyle(color: Colors.white),
                      onPressed: () => Navigator.pop(context, (lo, hi)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Or your own',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _min,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Colors.white),
                      decoration: box('At least'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _max,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Colors.white),
                      decoration: box('At most'),
                      onSubmitted: (_) => Navigator.pop(
                          context, (_read(_min), _read(_max))),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, (null, null)),
                    style: TextButton.styleFrom(foregroundColor: Colors.grey),
                    child: const Text('Any amount'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, (_read(_min), _read(_max))),
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _dayLabel(DateTime day) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  return diff == 0
      ? 'Today'
      : diff == 1
          ? 'Yesterday'
          : DateFormat(day.year == now.year ? 'EEE, d MMM' : 'd MMM yyyy')
              .format(day);
}

/// "TODAY   5 · ₹1,240 · +₹500  ☐" above a day's (or a payee's) payments.
/// The box selects them all.
class _GroupHeader extends StatelessWidget {
  final String label;
  final List<DetectedTransaction> items;
  final String currency;
  final bool allSelected;
  final VoidCallback onSelect;
  const _GroupHeader({
    super.key,
    required this.label,
    required this.items,
    required this.currency,
    required this.allSelected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    var out = 0.0, inc = 0.0;
    for (final i in items) {
      if (i.isDebit) {
        out += i.amount;
      } else {
        inc += i.amount;
      }
    }
    const grey = TextStyle(color: Colors.grey, fontSize: 12);
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Text('${items.length}', style: grey),
          if (out > 0) Text(' · ${_fmt(currency, out)}', style: grey),
          if (inc > 0)
            Text(' · +${_fmt(currency, inc)}',
                style: grey.copyWith(color: Colors.green)),
          IconButton(
            tooltip: allSelected ? 'Unselect these' : 'Select these',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: onSelect,
            icon: Icon(
              allSelected
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              color: allSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.white24,
            ),
          ),
        ],
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
  final time = _timeFormat.format(d);
  if (diff == 0) return 'Today, $time';
  if (diff == 1) return 'Yesterday, $time';
  return _dayTimeFormat.format(d);
}

// Made once, not for every card on every rebuild.
final _timeFormat = DateFormat('h:mm a');
final _dayTimeFormat = DateFormat('d MMM, h:mm a');

// No longer used: the bottom bar shows the count now.
// class _SectionHeader extends StatelessWidget {
//   final String title;
//   final int count;
//   final int? of; // total when a filter is narrowing the list
//   const _SectionHeader(this.title, this.count, {this.of});
//
//   @override
//   Widget build(BuildContext context) => Padding(
//         padding: const EdgeInsets.only(top: 8, bottom: 8),
//         child: Text(
//           of != null
//               ? '$title $count of $of'
//               : count > 0
//                   ? '$title ($count)'
//                   : title,
//           style: const TextStyle(
//             color: Colors.white,
//             fontSize: 18,
//             fontWeight: FontWeight.bold,
//           ),
//         ),
//       );
// }

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

/// One payment waiting for review. Closed it's two short lines:
///   [🍔]  Swiggy                         ₹245
///         Food ▾ · HDFC ••1234 · 2:15 PM
/// Tap opens the details (notes, the message, Edit / Dismiss / Add). Tap the
/// icon to change the category straight away.
class _DetectedCard extends StatefulWidget {
  final DetectedTransaction item;
  final bool showDay; // false under a day header: the time is enough
  final bool selecting;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onAdd;
  final VoidCallback onDismiss;
  final ValueChanged<MuteRule> onIgnore;
  const _DetectedCard({
    super.key,
    required this.item,
    required this.showDay,
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
  bool _open = false;

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
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('Category for ${widget.item.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ),
              // "Saved" holds month-end savings; it isn't picked by hand.
              for (final c in ep.categories.where(
                  (c) => c.name != ExpenseProvider.savedCategoryName))
                ListTile(
                  leading: Text(c.icon, style: const TextStyle(fontSize: 22)),
                  title:
                      Text(c.name, style: const TextStyle(color: Colors.white)),
                  trailing: c.name == widget.item.category
                      ? const Icon(Icons.check, color: Colors.green)
                      : null,
                  onTap: () => Navigator.pop(context, c.name),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) await cap.setCategory(widget.item.id, picked);
  }

  /// "Create Gym": makes the suggested category and moves this payment
  /// (and others like it) into it.
  Future<void> _createSuggested(CategoryGroup group) async {
    final cap = context.read<CaptureProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final name = await cap.createCategoryForGroup(group);
    messenger.showSnackBar(SnackBar(
      content: Text('"$name" category created'),
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _dismissSuggestion(CategoryGroup group) async {
    final cap = context.read<CaptureProvider>();
    final stop = await _confirmStopSuggesting(context, group);
    if (stop == true) await cap.dismissGroup(group);
  }

  /// "Looks like Gym  [Create Gym] [Pick…] ✕" in the open card.
  Widget _suggestionRow(CategoryGroup group) => Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.fromLTRB(10, 4, 4, 0),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lightbulb_outline,
                    size: 16, color: Colors.amber),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Looks like ${group.icon} ${group.name}. You have no category for it yet.',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ),
                IconButton(
                  tooltip: 'Stop suggesting',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                  onPressed: () => _dismissSuggestion(group),
                ),
              ],
            ),
            Wrap(
              spacing: 4,
              children: [
                TextButton(
                  onPressed: () => _createSuggested(group),
                  child: Text('Create ${group.name}'),
                ),
                TextButton(
                  onPressed: _pickCategory,
                  child: const Text('Pick…'),
                ),
              ],
            ),
          ],
        ),
      );

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
    // Rebuild only when what a card shows changes (categories or currency),
    // not on every expense added elsewhere.
    context.select<ExpenseProvider, int>((p) => Object.hash(
        p.currency,
        Object.hashAll(
            p.categories.map((c) => Object.hash(c.name, c.icon, c.color)))));
    final ep = context.read<ExpenseProvider>();
    final cap = context.read<CaptureProvider>();
    final currency = ep.currency;
    final category = _category(ep.categories, item.category);
    final color = item.isDebit ? category.color : Colors.green;
    final suggestion = cap.newCategoryHint(item);
    final flagged = _isFlagged(item);
    final notes = <String>[
      for (final f in item.flags)
        if (_flagText.containsKey(f)) _flagText[f]!,
      if (item.fromImport) 'From SMS import',
    ];

    final primary = Theme.of(context).colorScheme.primary;
    final selected = widget.selected;
    final open = _open && !widget.selecting;

    final where = [
      '${item.appLabel}${item.last4 != null ? ' ••${item.last4}' : ''}',
      widget.showDay ? _when(item.occurredAt) : _timeFormat.format(item.occurredAt),
    ].join(' · ');

    // ---- the two lines everyone sees
    final summary = Row(
      children: [
        // Tap the icon to change the category without opening the card.
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: widget.selecting
              ? widget.onToggle
              : item.isDebit
                  ? _pickCategory
                  : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: selected ? primary : color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: selected
                  ? const Icon(Icons.check_rounded,
                      color: Colors.black, size: 22)
                  : item.isDebit
                      ? Text(category.icon,
                          style: const TextStyle(fontSize: 19))
                      : const Icon(Icons.arrow_downward_rounded,
                          color: Colors.green, size: 20),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (flagged) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.warning_amber_rounded,
                        size: 14, color: Colors.amber),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: item.isDebit ? '${category.name} ▾' : 'Income',
                    style: TextStyle(
                        color: item.isDebit
                            ? Color.lerp(color, Colors.white, 0.35)
                            : Colors.green,
                        fontWeight: FontWeight.w600),
                  ),
                  if (suggestion != null)
                    TextSpan(
                      text: ' · ${suggestion.name}?',
                      style: const TextStyle(color: Colors.amber),
                    ),
                  TextSpan(text: ' · $where'),
                ]),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${item.isDebit ? '' : '+'}${_fmt(currency, item.amount)}',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: item.isDebit ? Colors.white : Colors.green,
          ),
        ),
      ],
    );

    Widget card = Material(
      color: selected
          ? primary.withValues(alpha: 0.10)
          : const Color(0xFF141414),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: selected
            ? BorderSide(color: primary, width: 1.5)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.selecting
            ? widget.onToggle
            : () => setState(() => _open = !_open),
        onLongPress: widget.selecting
            ? null
            : () {
                HapticFeedback.selectionClick();
                widget.onToggle();
              },
        child: AnimatedSize(
          duration: const Duration(milliseconds: 160),
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.fromLTRB(10, 9, 12, open ? 4 : 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                summary,
                if (open) ..._details(item, category, notes, suggestion, cap),
              ],
            ),
          ),
        ),
      ),
    );

    if (!widget.selecting) {
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
      padding: const EdgeInsets.only(top: 6),
      child: card,
    );
  }

  /// What an open card adds under the two lines.
  List<Widget> _details(
    DetectedTransaction item,
    ExpenseCategory category,
    List<String> notes,
    CategoryGroup? suggestion,
    CaptureProvider cap,
  ) {
    final payeeRule = cap.payeeRuleFor(item);
    final senderRule = cap.senderRuleFor(item);
    return [
      const SizedBox(height: 8),
      for (final n in notes)
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 14, color: Colors.amber),
              const SizedBox(width: 6),
              Expanded(
                child: Text(n,
                    style: const TextStyle(fontSize: 12, color: Colors.amber)),
              ),
            ],
          ),
        ),
      if (suggestion != null) _suggestionRow(suggestion),
      // The message itself, so you can check what was read from it.
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        margin: const EdgeInsets.only(top: 6),
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
        children: [
          if (item.isDebit)
            ActionChip(
              avatar: Text(category.icon),
              label: Text(category.name),
              visualDensity: VisualDensity.compact,
              onPressed: _pickCategory,
            ),
          const Spacer(),
          if (payeeRule != null || senderRule != null)
            PopupMenuButton<MuteRule>(
              tooltip: 'More',
              icon: const Icon(Icons.more_vert, color: Colors.grey, size: 20),
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
                      subtitle: const Text('Every message from this sender'),
                    ),
                  ),
              ],
            ),
        ],
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: widget.onDismiss,
            child: const Text('Dismiss', style: TextStyle(color: Colors.grey)),
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
    ];
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
        borderRadius: BorderRadius.circular(14),
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
        // Sorted by the sort chip (newest first unless changed).
        final items = _filter.apply(all);
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
                            currency: context.read<ExpenseProvider>().currency,
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
