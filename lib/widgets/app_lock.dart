import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/app_prefs.dart';

/// Optional PIN lock (Settings → Optional features). Everything stays on the
/// phone: the PIN and a one-time recovery code are stored only as salted
/// SHA-256 hashes.
class AppLock {
  AppLock._();

  static const pinLength = 4;

  static String _hash(String salt, String secret) =>
      sha256.convert(utf8.encode('$salt:$secret')).toString();

  static String _salt() {
    final r = Random.secure();
    return base64Url.encode(List<int>.generate(12, (_) => r.nextInt(256)));
  }

  /// Stored as "salt|pinHash|recoveryHash".
  static Future<void> enable(String pin, String recoveryCode) {
    final s = _salt();
    return AppPrefs.instance.setPinHash(
        '$s|${_hash(s, pin)}|${_hash(s, recoveryCode.toUpperCase())}');
  }

  static Future<void> disable() => AppPrefs.instance.setPinHash(null);

  static List<String>? get _parts {
    final v = AppPrefs.instance.pinHash;
    if (v == null) return null;
    final p = v.split('|');
    return p.length == 3 ? p : null;
  }

  static bool checkPin(String pin) {
    final p = _parts;
    return p != null && _hash(p[0], pin) == p[1];
  }

  static bool checkRecovery(String code) {
    final p = _parts;
    return p != null &&
        _hash(p[0], code.trim().toUpperCase().replaceAll(' ', '')) == p[2];
  }

  /// 8 characters without look-alikes (no 0/O, 1/I).
  static String newRecoveryCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(8, (_) => chars[r.nextInt(chars.length)]).join();
  }
}

/// The app's navigator (set on MaterialApp) so the lock can block Back.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Covers the app with the lock screen on launch and when coming back after
/// more than 30 seconds away. Sits above the navigator (in MaterialApp's
/// builder), so every screen is covered.
class LockGate extends StatefulWidget {
  final Widget child;
  const LockGate({super.key, required this.child});

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  static const _grace = Duration(seconds: 30);
  bool _locked = false;
  DateTime? _awaySince;

  /// Invisible route pushed while locked so Back can't pop the hidden
  /// screens underneath (and lose what was typed).
  Route<void>? _blocker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppPrefs.instance.addListener(_onPrefs);
    if (AppPrefs.instance.appLockEnabled) _lock();
  }

  void _lock() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (mounted) setState(() => _locked = true);
    // The navigator may not exist yet on launch: wait a frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = appNavigatorKey.currentState;
      if (!_locked || _blocker != null || nav == null) return;
      _blocker = PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, a, b) =>
            const PopScope(canPop: false, child: SizedBox.shrink()),
      );
      nav.push(_blocker!);
    });
  }

  void _unlock() {
    final nav = appNavigatorKey.currentState;
    final blocker = _blocker;
    _blocker = null;
    if (nav != null && blocker != null && blocker.isActive) {
      nav.removeRoute(blocker);
    }
    if (mounted) setState(() => _locked = false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppPrefs.instance.removeListener(_onPrefs);
    super.dispose();
  }

  void _onPrefs() {
    // Turning the lock off (or a reset) must never leave the app covered.
    if (!AppPrefs.instance.appLockEnabled && _locked) _unlock();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _awaySince ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final away = _awaySince;
      _awaySince = null;
      if (AppPrefs.instance.appLockEnabled &&
          away != null &&
          DateTime.now().difference(away) > _grace &&
          !_locked) {
        _lock();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Kept in the tree (state preserved) but hidden and inert.
        Offstage(offstage: _locked, child: widget.child),
        if (_locked)
          Positioned.fill(
            // Its own Overlay: the recovery text field needs one, and the
            // app's navigator (which has one) is hidden underneath.
            child: Overlay(
              initialEntries: [
                OverlayEntry(
                  builder: (context) => PinScreen(
                    mode: PinMode.unlock,
                    onDone: (_) => _unlock(),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

enum PinMode { unlock, verify, create }

/// Keypad screen used to unlock, to confirm the current PIN (before turning
/// the lock off or changing it) and to create a new PIN.
class PinScreen extends StatefulWidget {
  final PinMode mode;

  /// Called with the new PIN in [PinMode.create], or '' otherwise.
  final ValueChanged<String> onDone;
  final VoidCallback? onCancel;

  const PinScreen({
    super.key,
    required this.mode,
    required this.onDone,
    this.onCancel,
  });

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen>
    with SingleTickerProviderStateMixin {
  String _entry = '';
  String? _first; // create mode: the PIN typed the first time
  String? _error;
  // After 5 wrong PINs the keypad pauses (30 s, then longer each time).
  int _wrongTries = 0;
  DateTime? _pausedUntil;
  late final AnimationController _shake = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 350));

  @override
  void dispose() {
    _shake.dispose();
    _recoveryController.dispose();
    super.dispose();
  }

  String get _title => switch (widget.mode) {
        PinMode.unlock => 'Vyaya is locked',
        PinMode.verify => 'Enter your PIN',
        PinMode.create => _first == null ? 'Choose a PIN' : 'Confirm your PIN',
      };

  String get _subtitle => switch (widget.mode) {
        PinMode.unlock => 'Enter your ${AppLock.pinLength}-digit PIN',
        PinMode.verify => 'To make changes to the app lock',
        PinMode.create => _first == null
            ? '${AppLock.pinLength} digits you\'ll remember'
            : 'Type the same PIN again',
      };

  void _tap(String d) {
    final until = _pausedUntil;
    if (until != null && DateTime.now().isBefore(until)) {
      final s = until.difference(DateTime.now()).inSeconds + 1;
      setState(() => _error = 'Too many tries. Wait $s s');
      return;
    }
    if (_entry.length >= AppLock.pinLength) return;
    HapticFeedback.selectionClick();
    setState(() {
      _entry += d;
      _error = null;
    });
    if (_entry.length == AppLock.pinLength) {
      Future.delayed(const Duration(milliseconds: 120), _complete);
    }
  }

  void _back() {
    if (_entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  void _fail(String message) {
    HapticFeedback.heavyImpact();
    _shake.forward(from: 0);
    setState(() {
      _entry = '';
      _error = message;
    });
  }

  void _complete() {
    // Backspace in the short pause after the last digit cancels the check.
    if (!mounted || _entry.length != AppLock.pinLength) return;
    switch (widget.mode) {
      case PinMode.unlock:
      case PinMode.verify:
        if (AppLock.checkPin(_entry)) {
          _wrongTries = 0;
          widget.onDone('');
        } else {
          _wrongTries++;
          if (_wrongTries >= 5 && _wrongTries % 5 == 0) {
            final secs = 30 * (_wrongTries ~/ 5);
            _pausedUntil = DateTime.now().add(Duration(seconds: secs));
            _fail('Too many tries. Wait $secs s');
          } else {
            _fail('Wrong PIN, try again');
          }
        }
      case PinMode.create:
        if (_first == null) {
          setState(() {
            _first = _entry;
            _entry = '';
          });
        } else if (_entry == _first) {
          widget.onDone(_entry);
        } else {
          setState(() => _first = null);
          _fail('PINs didn\'t match, start again');
        }
    }
  }

  // "Forgot?" swaps the keypad for a recovery-code field in place (the
  // lock screen sits above the navigator, so no dialogs here).
  bool _recovering = false;
  final _recoveryController = TextEditingController();

  Future<void> _submitRecovery() async {
    if (AppLock.checkRecovery(_recoveryController.text)) {
      await AppLock.disable();
      widget.onDone('');
    } else {
      HapticFeedback.heavyImpact();
      setState(() => _error = 'That recovery code isn\'t right');
    }
  }

  Widget _recoveryPanel(Color accent) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter the 8-character recovery code you saved when you set the PIN. It turns the lock off.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _recoveryController,
              autofocus: true,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(
                  color: Colors.white, fontSize: 22, letterSpacing: 4),
              decoration: InputDecoration(
                hintText: 'XXXX XXXX',
                hintStyle: TextStyle(color: Colors.grey[700]),
                filled: true,
                fillColor: const Color(0xFF1C1C1C),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _submitRecovery(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => setState(() {
                      _recovering = false;
                      _error = null;
                    }),
                    child: const Text('Back to PIN'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.black),
                    onPressed: _submitRecovery,
                    child: const Text('Unlock'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Material(
      color: Colors.black,
      child: SafeArea(
        child: Padding(
          // Room for the keyboard when typing the recovery code.
          padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: LayoutBuilder(
          builder: (context, c) {
            // Keys shrink on short screens so everything fits.
            final key = (c.maxHeight / 9).clamp(52.0, 76.0);
            return Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: widget.onCancel == null
                      ? const SizedBox(height: 48)
                      : IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70),
                          onPressed: widget.onCancel,
                        ),
                ),
                const Spacer(),
                Icon(Icons.lock_outline_rounded, size: 40, color: accent),
                const SizedBox(height: 16),
                Text(_title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(_subtitle,
                    style: TextStyle(color: Colors.grey[500], fontSize: 14)),
                const SizedBox(height: 28),
                AnimatedBuilder(
                  animation: _shake,
                  builder: (context, child) => Transform.translate(
                    offset: Offset(
                        sin(_shake.value * pi * 6) * 10 * (1 - _shake.value),
                        0),
                    child: child,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < AppLock.pinLength; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          margin: const EdgeInsets.symmetric(horizontal: 10),
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i < _entry.length
                                ? (_error != null ? Colors.redAccent : accent)
                                : Colors.transparent,
                            border: Border.all(
                                color: _error != null
                                    ? Colors.redAccent
                                    : Colors.grey[600]!,
                                width: 2),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 36,
                  child: Center(
                    child: Text(_error ?? '',
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 13)),
                  ),
                ),
                const Spacer(),
                if (_recovering) ...[
                  _recoveryPanel(accent),
                  const Spacer(),
                ] else ...[
                for (final row in const [
                  ['1', '2', '3'],
                  ['4', '5', '6'],
                  ['7', '8', '9'],
                ])
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [for (final d in row) _key(d, key)],
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: key + 24,
                      height: key + 12,
                      child: widget.mode == PinMode.unlock
                          ? TextButton(
                              onPressed: () => setState(() {
                                _recovering = true;
                                _error = null;
                                _entry = '';
                              }),
                              child: const Text('Forgot?',
                                  style: TextStyle(fontSize: 13)),
                            )
                          : null,
                    ),
                    _key('0', key),
                    SizedBox(
                      width: key + 24,
                      height: key + 12,
                      child: IconButton(
                        icon: const Icon(Icons.backspace_outlined,
                            color: Colors.white70),
                        onPressed: _back,
                      ),
                    ),
                  ],
                ),
                ],
                const SizedBox(height: 24),
              ],
            );
          },
        ),
        ),
      ),
    );
  }

  Widget _key(String d, double size) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: SizedBox(
          width: size,
          height: size,
          child: Material(
            color: const Color(0xFF1C1C1C),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _tap(d),
              child: Center(
                child: Text(d,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w500)),
              ),
            ),
          ),
        ),
      );
}

/// Full flow to turn the lock on: choose PIN, confirm, then note the
/// recovery code. Pops true when the lock was enabled.
class AppLockSetupScreen extends StatefulWidget {
  const AppLockSetupScreen({super.key});

  @override
  State<AppLockSetupScreen> createState() => _AppLockSetupScreenState();
}

class _AppLockSetupScreenState extends State<AppLockSetupScreen> {
  String? _pin;
  late final String _code = AppLock.newRecoveryCode();

  @override
  Widget build(BuildContext context) {
    if (_pin == null) {
      return PinScreen(
        mode: PinMode.create,
        onCancel: () => Navigator.pop(context, false),
        onDone: (pin) => setState(() => _pin = pin),
      );
    }
    final accent = Theme.of(context).colorScheme.primary;
    final spaced = '${_code.substring(0, 4)} ${_code.substring(4)}';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Recovery code'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Write this down somewhere safe. If you ever forget your PIN, this code is the only way back in: Vyaya is offline, so nobody can reset it for you.',
                style: TextStyle(color: Colors.white70, fontSize: 15),
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 22),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: accent.withValues(alpha: 0.4)),
                ),
                child: Center(
                  child: SelectableText(spaced,
                      style: TextStyle(
                          color: accent,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 4)),
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _code));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Copied. Save it somewhere other than this phone.')));
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy code'),
              ),
              const Spacer(),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  await AppLock.enable(_pin!, _code);
                  navigator.pop(true);
                },
                child: const Text('I\'ve saved it, turn on lock',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
