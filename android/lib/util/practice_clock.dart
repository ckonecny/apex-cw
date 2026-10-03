import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../content/practice_log.dart';

/// Measures active practice time (issue #30, docs/DECISIONS.md "Practice log").
///
/// Time counts only while a training screen is open ([enter]/[leave], next to
/// the KeepScreenOn calls), the app is in the foreground, and the user is
/// active: a touch / key within [idleCap], or audio playing ([audioPlaying],
/// for listening on paper). It ticks once a second, only while a training
/// screen is open. A session ends after [sessionGap] without credited time.
class PracticeClock with WidgetsBindingObserver {
  PracticeClock({DateTime Function()? now, this.idleCap = const Duration(seconds: 20),
      this.sessionGap = const Duration(minutes: 5), this.autoTick = true})
      : _now = now ?? DateTime.now;

  static final PracticeClock instance = PracticeClock();

  final DateTime Function() _now;
  final Duration idleCap;
  final Duration sessionGap;
  // Tests drive tick() themselves.
  final bool autoTick;

  final PracticeLog log = PracticeLog();
  SharedPreferences? _prefs;

  final List<String> _modes = [];
  Timer? _timer;
  bool _foreground = true;
  DateTime? _lastTick;
  DateTime? _lastActivity;
  DateTime? _lastCredit;
  PracticeSession? _session;
  int _carryMs = 0;
  int _unsavedMs = 0;
  bool audioPlaying = false;

  /// Loads the log and starts listening for touches. Call once from main().
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await log.load(_prefs!);
    WidgetsBinding.instance.addObserver(this);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  /// For tests: use [p] without registering bindings.
  Future<void> initForTest(SharedPreferences p) async {
    _prefs = p;
    await log.load(p);
  }

  void _onPointer(PointerEvent e) {
    if (e is PointerDownEvent || e is PointerMoveEvent) touch();
  }

  /// The user did something (touch, key press, paddle).
  void touch() => _lastActivity = _now();

  bool get inTraining => _modes.isNotEmpty;

  void enter(String mode) {
    _modes.add(mode);
    _lastTick = _now();
    touch();
    if (autoTick) _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  void leave() {
    if (_modes.isEmpty) return;
    tick();
    _modes.removeLast();
    audioPlaying = false;
    if (_modes.isEmpty) {
      _timer?.cancel();
      _timer = null;
      _lastTick = null;
      _flush();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    if (fg == _foreground) return;
    if (!fg) tick();
    _foreground = fg;
    _lastTick = _now();
    if (!fg) _flush();
  }

  /// One step of the clock (called every second by the timer; public for tests).
  void tick() {
    final now = _now();
    final last = _lastTick;
    _lastTick = now;
    if (last == null || _modes.isEmpty || !_foreground || !log.enabled) return;
    // A step is at most 2 s: a stalled timer (device asleep) must not credit
    // the whole gap.
    var elapsed = now.difference(last).inMilliseconds.clamp(0, 2000);
    final act = _lastActivity;
    final active = audioPlaying || (act != null && now.difference(act) <= idleCap);
    if (!active || elapsed == 0) return;

    final cr = _lastCredit;
    var s = _session;
    if (s == null || cr == null || now.difference(cr) > sessionGap) {
      s = _session = PracticeSession(now.millisecondsSinceEpoch, _modes.last);
      log.sessions.add(s);
      _carryMs = 0;
      log.days.putIfAbsent(practiceDayKey(now), () => PracticeDay()).sessions++;
    }
    _lastCredit = now;

    final day = log.days.putIfAbsent(practiceDayKey(now), () => PracticeDay());
    _carryMs += elapsed;
    final whole = _carryMs ~/ 1000;
    if (whole > 0) {
      _carryMs -= whole * 1000;
      final wasLong = s.seconds >= kLongSessionSeconds;
      s.seconds += whole;
      day.seconds += whole;
      if (!wasLong && s.seconds >= kLongSessionSeconds) day.longSessions++;
    }
    _unsavedMs += elapsed;
    if (_unsavedMs >= 30000) _flush();
  }

  /// Logs a milestone for today (no-op while the feature is off).
  void milestone(String kind, int value, {bool onlyIfHigher = false}) {
    if (!log.enabled) return;
    if (log.addMilestone(practiceDayKey(_now()), kind, value, onlyIfHigher: onlyIfHigher)) {
      _flush();
    }
  }

  void _flush() {
    _unsavedMs = 0;
    final p = _prefs;
    if (p != null) log.save(p);
  }

  /// For tests / settings: persist now.
  Future<void> flush() async {
    _unsavedMs = 0;
    final p = _prefs;
    if (p != null) await log.save(p);
  }
}
