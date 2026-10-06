// Exam simulation, send part (issue #42, docs/DECISIONS.md "Exam simulation"):
// the candidate keys the shown text within the exam time with paddle or
// straight key. The keying is decoded like in the CW keyer (<err> deletes the
// last character); the decoded text is graded by content/exam_grading.dart
// (errors, how much of the text was reached, estimated speed) and stored in
// content/exam_log.dart as part 'tx'.
//
// The shared native keyer gets this screen's speed, mode and word gap on entry
// (rule 2) and is stopped on leaving.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../content/exam_grading.dart';
import '../content/exam_log.dart';
import '../content/exam_profile.dart';
import '../content/exam_texts.dart';
import '../keyer/morse_decoder.dart';
import '../l10n/exam_strings.dart';
import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import '../util/keep_screen_on.dart';
import '../util/practice_clock.dart';
import 'widgets/app_ui.dart';
import 'widgets/paddle_widgets.dart';
import 'widgets/slider_row.dart';

enum _Phase { ready, keying, result }

const _leadInSeconds = 3;
const _resultsKey = 'exam.results';
const _maxSendWpm = 40;

class ExamSendScreen extends StatefulWidget {
  final ExamProfile profile;
  const ExamSendScreen({super.key, this.profile = examAt12});

  @override
  State<ExamSendScreen> createState() => _ExamSendScreenState();
}

class _ExamSendScreenState extends State<ExamSendScreen> {
  static const _toneChannel = MethodChannel('at.oe1cko.nextcwtrainer/cw_tone');
  static const _keyerChannel = MethodChannel('at.oe1cko.nextcwtrainer/cw_keyer');
  static const _symbolStream = EventChannel('at.oe1cko.nextcwtrainer/cw_symbols');

  ExamProfile get _p => widget.profile;

  bool _ready = false;
  int _keyerMode = 0; // 0..3 paddle modes, 4 straight key
  late int _sendWpm = _p.charWpm; // paddle keyer speed, at least the exam speed
  _Phase _phase = _Phase.ready;
  int _attempt = 1; // attempt of the part, 1-based; a failed part may be retried
  String _target = '';
  String _keyed = '';
  ExamSendGrade? _grade;
  late final MorseDecoder _decoder;

  int _leadIn = 0;
  int _secondsLeft = 0;
  int _gen = 0; // bumped to cancel a running attempt
  Timer? _timer;
  StreamSubscription? _symbolSub;
  DateTime? _first, _last; // first and last element keyed
  bool _touchDit = false, _touchDah = false;

  @override
  void initState() {
    super.initState();
    KeepScreenOn.enable();
    PracticeClock.instance.enter('exam');
    _decoder = MorseDecoder(onChar: _onChar);
    _target = examText(_p);
    _init();
  }

  @override
  void dispose() {
    _cancelRun();
    KeepScreenOn.disable();
    PracticeClock.instance.leave();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _keyerMode = (prefs.getInt('keyerMode') ?? 0).clamp(0, 4);
    _sendWpm = (prefs.getInt('exam.sendWpm.${_p.id}') ?? _p.charWpm).clamp(_p.wpm, _maxSendWpm);
    if (mounted) setState(() => _ready = true);
  }

  /// Everything the shared native keyer and tone need for this screen.
  Future<void> _pushConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await _toneChannel.invokeMethod('setFreq', prefs.getInt('pitch') ?? 600);
    await _toneChannel.invokeMethod('setVolume', 0.7);
    await _toneChannel.invokeMethod('setEnvelopeMs',
        ((prefs.getInt('toneSoftness') ?? 4).clamp(0, 8) + 1).toDouble());
    await _keyerChannel.invokeMethod('setWpm', _sendWpm);
    await _keyerChannel.invokeMethod('setMode', _keyerMode);
    await _keyerChannel.invokeMethod('setCurtisBTiming', {
      'dit': (prefs.getInt('curtisBDitTiming') ?? 75).clamp(0, 100),
      'dah': (prefs.getInt('curtisBDahTiming') ?? 45).clamp(0, 100),
    });
    await _keyerChannel.invokeMethod('setAcs', (prefs.getInt('acs') ?? 0).clamp(0, 3));
    // Standard word gap (the native side takes the spacing and subtracts 1).
    await _keyerChannel.invokeMethod('setInterWordSpace', 7);
  }

  void _cancelRun() {
    _gen++;
    _timer?.cancel();
    _timer = null;
    _symbolSub?.cancel();
    _symbolSub = null;
    _keyerChannel.invokeMethod('setInputs', {'dit': false, 'dah': false});
    _keyerChannel.invokeMethod('stop');
  }

  // ---- flow ----

  void _onChar(String ch) {
    if (_phase != _Phase.keying || !mounted) return;
    setState(() {
      if (ch == MorseDecoder.err) {
        // <err>: deletes the last character, like a correction on paper.
        if (_keyed.isNotEmpty) _keyed = _keyed.substring(0, _keyed.length - 1);
      } else if (ch == ' ') {
        if (_keyed.isNotEmpty && !_keyed.endsWith(' ')) _keyed += ' ';
      } else {
        _keyed += ch;
      }
    });
  }

  Future<void> _start() async {
    _cancelRun();
    final gen = _gen;
    _keyed = '';
    _first = _last = null;
    _decoder.reset();
    setState(() {
      _phase = _Phase.keying;
      _leadIn = _leadInSeconds;
      _secondsLeft = _p.minutes * 60;
    });
    await _pushConfig();
    while (_leadIn > 0) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (gen != _gen || !mounted) return;
      setState(() => _leadIn--);
    }
    _symbolSub = _symbolStream.receiveBroadcastStream().listen((sym) {
      PracticeClock.instance.touch();
      if (sym == '·' || sym == '—') {
        final now = DateTime.now();
        _first ??= now;
        _last = now;
      }
      _decoder.add(sym as String);
    });
    await _keyerChannel.invokeMethod('start');
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (gen != _gen || !mounted) return t.cancel();
      if (_secondsLeft <= 1) {
        t.cancel();
        _finish();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  Future<void> _finish() async {
    if (_phase != _Phase.keying) return;
    _decoder.flush();
    final first = _first, last = _last;
    final elapsed = first == null || last == null ? 0 : last.difference(first).inMilliseconds;
    _cancelRun();
    final g = gradeExamSend(_target, _keyed, elapsed, _p);
    setState(() {
      _grade = g;
      _phase = _Phase.result;
    });
    final prefs = await SharedPreferences.getInstance();
    final all = examParseResults(prefs.getString(_resultsKey));
    all.add(ExamResult(DateTime.now().millisecondsSinceEpoch, _p.id, 'tx', g.errors, g.limit,
        g.weakChars.take(8).map((e) => e.key).join(),
        wpm: g.wpm.round(), verdict: g.passed));
    await prefs.setString(_resultsKey, examEncodeResults(all));
  }

  void _toReady() {
    _cancelRun();
    setState(() => _phase = _Phase.ready);
  }

  void _again() {
    final failed = !(_grade?.passed ?? true);
    _attempt = failed && _attempt <= _p.retries ? _attempt + 1 : 1;
    _target = examText(_p);
    _toReady();
  }

  Future<void> _setSendWpm(double v) async {
    setState(() => _sendWpm = v.round());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('exam.sendWpm.${_p.id}', _sendWpm);
  }

  void _setInputs({bool? dit, bool? dah}) {
    if (dit != null) _touchDit = dit;
    if (dah != null) _touchDah = dah;
    _keyerChannel.invokeMethod('setInputs', {'dit': _touchDit, 'dah': _touchDah});
  }

  // ---- views ----

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: Strings.lang,
      builder: (context, _, _) => PopScope(
        canPop: _phase == _Phase.ready,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _toReady();
        },
        child: Scaffold(
          backgroundColor: c.background,
          appBar: AppBar(
            backgroundColor: c.background,
            title: appBarTitle(c, ExamStrings.t('ex_send_title')),
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: c.textMuted),
              onPressed: () => _phase == _Phase.ready ? Navigator.pop(context) : _toReady(),
            ),
          ),
          body: !_ready
              ? const SizedBox.shrink()
              : switch (_phase) {
                  _Phase.ready => _readyView(c),
                  _Phase.keying => _keyingView(c),
                  _Phase.result => _resultView(c),
                },
        ),
      ),
    );
  }

  String _clock(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  Widget _readyView(AppColors c) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text(ExamStrings.label(_p),
            style: TextStyle(fontFamily: 'CwMono', fontSize: 15, color: c.textPrimary)),
        const SizedBox(height: 6),
        Text(
          ExamStrings.f('ex_send_rules', [
            _p.minutes,
            _p.errorLimit,
            _p.wpm,
            (_p.wpm * kExamSendMinSpeed).toStringAsFixed(1),
            (kExamSendMinText * 100).round(),
          ]),
          style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.textMuted),
        ),
        const SizedBox(height: 12),
        AppCaption(ExamStrings.t('ex_send_text')),
        const SizedBox(height: 6),
        AppCard(
          child: Text(_target,
              style: TextStyle(fontFamily: 'CwMono', fontSize: 16, height: 1.5, color: c.textPrimary)),
        ),
        const SizedBox(height: 12),
        Text(ExamStrings.t(_keyerMode == 4 ? 'ex_send_straight' : 'ex_send_paddle'),
            style: TextStyle(fontFamily: 'CwMono', fontSize: 11, color: c.textMuted)),
        // Straight key: the speed is the operator's own, nothing to set.
        if (_keyerMode != 4) ...[
          const SizedBox(height: 8),
          AppCard(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
            child: SliderRow(
              label: 'WPM', value: _sendWpm.toDouble(), min: _p.wpm.toDouble(),
              max: _maxSendWpm.toDouble(), divisions: _maxSendWpm - _p.wpm,
              showTicks: true, onChanged: _setSendWpm),
          ),
          const SizedBox(height: 4),
          Text(ExamStrings.f(_p.farnsworth ? 'ex_send_wpm_farns' : 'ex_send_wpm_hint',
                  [_p.wpm, _p.charWpm]),
              style: TextStyle(fontFamily: 'CwMono', fontSize: 11, color: c.textFaint)),
        ],
        const SizedBox(height: 12),
        AppButton(label: ExamStrings.t('ex_send_start'), icon: Icons.play_arrow_rounded,
            color: c.accent, onTap: _start),
        const SizedBox(height: 8),
        AppButton(label: ExamStrings.t('ex_send_new'), primary: false,
            color: c.textMuted, onTap: () => setState(() => _target = examText(_p))),
      ],
    );
  }

  Widget _keyingView(AppColors c) {
    final counting = _leadIn > 0;
    // The text keyed so far (without spaces) is highlighted in the shown text.
    final done = _keyed.replaceAll(' ', '').length;
    var seen = 0;
    final spans = <TextSpan>[];
    for (final ch in _target.split('')) {
      final isChar = ch.trim().isNotEmpty;
      final keyed = isChar && seen < done;
      if (isChar) seen++;
      spans.add(TextSpan(text: ch, style: TextStyle(color: keyed ? c.accent : c.textPrimary)));
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Text(counting ? '$_leadIn' : _clock(_secondsLeft),
            style: TextStyle(fontFamily: 'CwMono', fontSize: 20, color: c.accent)),
      ),
      Expanded(
        flex: 3,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(16)),
          child: SingleChildScrollView(
            child: Text.rich(TextSpan(children: spans),
                style: const TextStyle(fontFamily: 'CwMono', fontSize: 16, height: 1.5)),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Expanded(
        flex: 2,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(16)),
          child: SingleChildScrollView(
            reverse: true,
            child: Text(_keyed.isEmpty ? '·' : _keyed,
                style: TextStyle(fontFamily: 'CwMono', fontSize: 18, height: 1.4, color: c.accent)),
          ),
        ),
      ),
      const SizedBox(height: 8),
      if (!counting)
        if (_keyerMode == 4)
          StraightKeyPaddle(onDown: () => _setInputs(dit: true), onUp: () => _setInputs(dit: false))
        else
          IambicPaddles(
              onDitDown: () => _setInputs(dit: true), onDitUp: () => _setInputs(dit: false),
              onDahDown: () => _setInputs(dah: true), onDahUp: () => _setInputs(dah: false)),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(children: [
          Expanded(child: AppButton(label: ExamStrings.t('ex_abort'), primary: false,
              color: c.textMuted, onTap: _toReady)),
          const SizedBox(width: 12),
          Expanded(child: AppButton(label: ExamStrings.t('ex_done_btn'), color: c.accent,
              onTap: counting ? null : _finish)),
        ]),
      ),
    ]);
  }

  Widget _resultView(AppColors c) {
    final g = _grade!;
    final color = g.passed ? c.accent : c.danger;
    final weak = g.weakChars;
    Widget line(bool ok, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(ok ? Icons.check_circle_outline : Icons.cancel_outlined,
                size: 18, color: ok ? c.accent : c.danger),
            const SizedBox(width: 8),
            Expanded(child: Text(text,
                style: TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.textPrimary))),
          ]),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        AppCard(
          borderColor: color,
          child: Column(children: [
            Text(ExamStrings.t(g.passed ? 'ex_passed' : 'ex_failed'),
                style: TextStyle(fontFamily: 'CwMono', fontSize: 22, color: color)),
            if (_p.retries > 0) ...[
              const SizedBox(height: 6),
              Text(
                  !g.passed && _attempt > _p.retries
                      ? ExamStrings.t('ex_exhausted')
                      : ExamStrings.f('ex_attempt', [_attempt, _p.retries + 1]),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.textMuted)),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                line(g.errors <= g.limit,
                    ExamStrings.f('ex_errors', [g.errors, g.limit])),
                line(g.enoughText,
                    ExamStrings.f('ex_send_reached', [g.reached, g.total, (kExamSendMinText * 100).round()])),
                line(g.fastEnough,
                    ExamStrings.f('ex_send_speed', [g.wpm.toStringAsFixed(1), g.minWpm.toStringAsFixed(1)])),
              ]),
            ),
            if (weak.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(ExamStrings.f('ex_weak', [weak.take(8).map((e) => e.key).join(' ')]),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.textMuted)),
            ],
          ]),
        ),
        const SizedBox(height: 8),
        Text(ExamStrings.t('ex_send_estimate'),
            style: TextStyle(fontFamily: 'CwMono', fontSize: 11, color: c.textFaint)),
        const SizedBox(height: 16),
        AppCaption(ExamStrings.t('ex_send_text')),
        const SizedBox(height: 6),
        AppCard(
          child: Text.rich(
            TextSpan(children: [
              for (var i = 0; i < g.played.length; i++)
                TextSpan(
                  text: g.played[i],
                  style: TextStyle(color: g.ok[i] ? c.textPrimary : c.danger,
                      fontWeight: g.ok[i] ? FontWeight.normal : FontWeight.bold),
                ),
            ]),
            style: const TextStyle(fontFamily: 'CwMono', fontSize: 14, letterSpacing: 1),
          ),
        ),
        const SizedBox(height: 12),
        AppCaption(ExamStrings.t('ex_send_yours')),
        const SizedBox(height: 6),
        AppCard(
          child: Text(_keyed.trim().isEmpty ? '–' : _keyed,
              style: TextStyle(fontFamily: 'CwMono', fontSize: 14, color: c.textPrimary)),
        ),
        const SizedBox(height: 16),
        if (!g.passed && _attempt <= _p.retries)
          AppButton(label: ExamStrings.f('ex_retry', [_p.retries + 1 - _attempt]),
              icon: Icons.refresh_rounded, color: c.accent, onTap: _again)
        else
          AppButton(label: ExamStrings.t(g.passed ? 'ex_again' : 'ex_new_exam'),
              icon: Icons.refresh_rounded, color: c.accent, onTap: _again),
        const SizedBox(height: 8),
        AppButton(label: ExamStrings.t('ex_back'), primary: false,
            color: c.textMuted, onTap: () => Navigator.pop(context)),
      ],
    );
  }
}
