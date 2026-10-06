// Exam simulation (issue #42, docs/DECISIONS.md "Exam simulation"): the
// receive part of the voluntary Morse exams (Austria, Germany). The text plays
// once without pause or replay while the user copies it into a text field;
// after a short correction time the copy is graded like an examiner would
// (content/exam_grading.dart) and stored in content/exam_log.dart.
//
// The shared native generator gets this screen's speed and spacing before every
// playback (rule 2). Sending (keyer) follows in a later version.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../content/exam_grading.dart';
import '../content/exam_log.dart';
import '../content/exam_profile.dart';
import '../content/exam_texts.dart';
import '../l10n/exam_strings.dart';
import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import '../util/keep_screen_on.dart';
import '../util/practice_clock.dart';
import 'exam_picker.dart';
import 'exam_send_screen.dart';
import 'widgets/app_ui.dart';
import 'widgets/char_playback_overlay.dart' show cwGenEvents;

enum _Phase { setup, listen, correct, result }

const _leadInSeconds = 3;
const _correctSeconds = 30;
const _profileKey = 'exam.profile';
const _customKey = 'exam.custom';
const _resultsKey = 'exam.results';

class ExamScreen extends StatefulWidget {
  const ExamScreen({super.key});

  @override
  State<ExamScreen> createState() => _ExamScreenState();
}

class _ExamScreenState extends State<ExamScreen> {
  static const _genChannel = MethodChannel('at.oe1cko.nextcwtrainer/cw_generator');
  static const _toneChannel = MethodChannel('at.oe1cko.nextcwtrainer/cw_tone');

  ExamProfile _profile = examAt12;
  ExamProfile _custom = ExamProfile.custom();
  List<ExamResult> _results = [];
  bool _ready = false;

  _Phase _phase = _Phase.setup;
  int _attempt = 1; // attempt of the part, 1-based; a failed part may be retried
  String _played = '';
  final _typed = TextEditingController();
  ExamGrade? _grade;

  int _gen = 0; // bumped to cancel a running playback
  int _leadIn = 0; // seconds until the text starts, 0 = playing
  int _correctLeft = 0;
  Timer? _timer;
  Completer<void>? _doneWait;
  StreamSubscription? _genSub;

  @override
  void initState() {
    super.initState();
    KeepScreenOn.enable();
    PracticeClock.instance.enter('exam');
    _init();
  }

  @override
  void dispose() {
    _cancelRun();
    _typed.dispose();
    _genSub?.cancel();
    KeepScreenOn.disable();
    PracticeClock.instance.leave();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString(_customKey);
      if (raw != null) _custom = ExamProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // A broken value: keep the default custom profile.
    }
    final saved = prefs.getString(_profileKey);
    _profile = saved == ExamProfile.customFamily ? _custom : examProfileById(saved);
    _results = examParseResults(prefs.getString(_resultsKey));
    _genSub = cwGenEvents.listen((raw) {
      if (raw is Map && raw['type'] == 'done') {
        final w = _doneWait;
        if (w != null && !w.isCompleted) w.complete();
      }
    });
    if (mounted) setState(() => _ready = true);
  }

  /// Everything the shared native engine needs for this screen.
  Future<void> _pushAudio() async {
    final prefs = await SharedPreferences.getInstance();
    await _toneChannel.invokeMethod('setFreq', prefs.getInt('pitch') ?? 600);
    await _toneChannel.invokeMethod('setEnvelopeMs',
        ((prefs.getInt('toneSoftness') ?? 4).clamp(0, 8) + 1).toDouble());
    await _genChannel.invokeMethod('setWpm', _profile.charWpm);
    await _genChannel.invokeMethod('setInterCharSpace', _profile.interChar);
    await _genChannel.invokeMethod('setInterWordSpace', _profile.interWord);
  }

  void _cancelRun() {
    _gen++;
    _timer?.cancel();
    _timer = null;
    final w = _doneWait;
    if (w != null && !w.isCompleted) w.complete();
    PracticeClock.instance.audioPlaying = false;
    _genChannel.invokeMethod('stopOne');
  }

  // ---- flow ----

  Future<void> _selectProfile(ExamProfile p) async {
    setState(() => _profile = p);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey, p.family == ExamProfile.customFamily ? ExamProfile.customFamily : p.id);
  }

  Future<void> _customChanged(ExamProfile p) async {
    setState(() {
      _custom = p;
      _profile = p;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customKey, jsonEncode(p.toJson()));
    await prefs.setString(_profileKey, ExamProfile.customFamily);
  }

  /// Starts the receive part. [retry]: the next attempt after a failed one;
  /// otherwise a fresh exam (attempt 1).
  Future<void> _start({bool retry = false}) async {
    _attempt = retry ? _attempt + 1 : 1;
    _cancelRun();
    final gen = _gen;
    _played = examText(_profile);
    _typed.clear();
    setState(() {
      _phase = _Phase.listen;
      _leadIn = _leadInSeconds;
    });
    while (_leadIn > 0) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (gen != _gen || !mounted) return;
      setState(() => _leadIn--);
    }
    await _pushAudio();
    if (gen != _gen || !mounted) return;
    PracticeClock.instance.audioPlaying = true;
    PracticeClock.instance.touch();
    _doneWait = Completer<void>();
    await _genChannel.invokeMethod('playOne', _played);
    await _doneWait!.future;
    PracticeClock.instance.audioPlaying = false;
    if (gen != _gen || !mounted) return;
    _startCorrection(gen);
  }

  void _startCorrection(int gen) {
    setState(() {
      _phase = _Phase.correct;
      _correctLeft = _correctSeconds;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (gen != _gen || !mounted) return t.cancel();
      if (_correctLeft <= 1) {
        t.cancel();
        _finish();
      } else {
        setState(() => _correctLeft--);
      }
    });
  }

  Future<void> _finish() async {
    _cancelRun();
    final g = gradeExamReceive(_played, _typed.text, _profile.errorLimit);
    final weak = g.weakChars.take(8).map((e) => e.key).join();
    final r = ExamResult(DateTime.now().millisecondsSinceEpoch, _profile.id, 'rx',
        g.errors, _profile.errorLimit, weak);
    _results.add(r);
    setState(() {
      _grade = g;
      _phase = _Phase.result;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_resultsKey, examEncodeResults(_results));
  }

  /// The send part has its own screen; its results are in the same list.
  Future<void> _openSend() async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => ExamSendScreen(profile: _profile)));
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _results = examParseResults(prefs.getString(_resultsKey));
      _phase = _Phase.setup;
    });
  }

  void _toSetup() {
    _cancelRun();
    setState(() => _phase = _Phase.setup);
  }

  // ---- views ----

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: Strings.lang,
      builder: (context, _, _) => PopScope(
        canPop: _phase == _Phase.setup,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _toSetup();
        },
        child: Scaffold(
          backgroundColor: c.background,
          appBar: AppBar(
            backgroundColor: c.background,
            title: appBarTitle(c, ExamStrings.t('ex_title')),
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: c.textMuted),
              onPressed: () => _phase == _Phase.setup ? Navigator.pop(context) : _toSetup(),
            ),
          ),
          body: !_ready
              ? const SizedBox.shrink()
              : switch (_phase) {
                  _Phase.setup => _setupView(c),
                  _Phase.listen || _Phase.correct => _copyView(c),
                  _Phase.result => _resultView(c),
                },
        ),
      ),
    );
  }

  Widget _setupView(AppColors c) {
    final p = _profile;
    final recent = [for (final r in _results) if (r.profile == p.id) r];
    if (recent.length > 5) recent.removeRange(0, recent.length - 5);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        AppCaption(ExamStrings.t('ex_choose')),
        const SizedBox(height: 8),
        ExamPicker(selected: p, custom: _custom, onSelect: _selectProfile,
            onCustomChanged: _customChanged),
        const SizedBox(height: 8),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              ExamStrings.f('ex_rules', [
                p.minutes,
                p.errorLimit,
                p.wpm,
                p.farnsworth ? ExamStrings.f('ex_farns', [p.charWpm]) : '',
              ]),
              style: TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.textPrimary),
            ),
            if (p.hasSend) ...[
              const SizedBox(height: 6),
              Text(
                ExamStrings.f('ex_send_rules', [
                  p.minutes,
                  p.errorLimit,
                  p.wpm,
                  (p.wpm * kExamSendMinSpeed).toStringAsFixed(1),
                  (kExamSendMinText * 100).round(),
                ]),
                style: TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.textPrimary),
              ),
            ],
            const SizedBox(height: 8),
            Text(ExamStrings.t(_charsKey(p)),
                style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.textMuted)),
            const SizedBox(height: 8),
            Text(ExamStrings.t('ex_src_${p.family}'),
                style: TextStyle(fontFamily: 'CwMono', fontSize: 11, color: c.textFaint)),
            if (!p.hasSend) ...[
              const SizedBox(height: 8),
              Text(ExamStrings.t('ex_receive_only'),
                  style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.textMuted)),
            ],
            if (p.retries > 0) ...[
              const SizedBox(height: 8),
              Text(ExamStrings.f('ex_retries', [p.retries]),
                  style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.textMuted)),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        AppButton(label: ExamStrings.t('ex_start'), icon: Icons.play_arrow_rounded,
            color: c.accent, onTap: _start),
        const SizedBox(height: 8),
        if (p.hasSend) ...[
          AppButton(label: ExamStrings.t('ex_send_open'), icon: Icons.touch_app_outlined,
              color: c.warning, onTap: _openSend),
        ],
        const SizedBox(height: 6),
        Text(ExamStrings.t('ex_start_hint'),
            style: TextStyle(fontFamily: 'CwMono', fontSize: 11, color: c.textMuted)),
        const SizedBox(height: 16),
        AppCaption(ExamStrings.t('ex_history')),
        const SizedBox(height: 8),
        if (recent.isEmpty)
          Text(ExamStrings.t('ex_no_history'),
              style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.textMuted))
        else
          for (final r in recent.reversed)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Icon(r.passed ? Icons.check_circle_outline : Icons.cancel_outlined,
                    size: 18, color: r.passed ? c.accent : c.danger),
                const SizedBox(width: 8),
                Expanded(child: Text(
                    '${_date(r.time)} · ${ExamStrings.t('ex_part_${r.part}')} · '
                    '${ExamStrings.f('ex_errors', [r.errors, r.limit])}'
                    '${r.wpm > 0 ? ' · ${r.wpm} WPM' : ''}',
                    style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.textPrimary))),
              ]),
            ),
        for (final part in p.hasSend ? const ['rx', 'tx'] : const ['rx']) ...[
          const SizedBox(height: 8),
          Builder(builder: (_) {
            final ready = examReady(_results, p.id, part);
            final name = ExamStrings.t('ex_part_$part');
            return Text(ExamStrings.f(ready == true ? 'ex_ready' : 'ex_not_ready', [name]),
                style: TextStyle(fontFamily: 'CwMono', fontSize: 12,
                    color: ready == true ? c.accent : c.textMuted));
          }),
        ],
        const SizedBox(height: 16),
        Text(ExamStrings.t('ex_disclaimer'),
            style: TextStyle(fontFamily: 'CwMono', fontSize: 11, color: c.textFaint)),
      ],
    );
  }

  String _charsKey(ExamProfile p) => switch (p.kind) {
        ExamKind.figures => 'ex_chars_fig',
        ExamKind.groups => 'ex_chars_grp',
        ExamKind.plain when p.lang == 'en' =>
          p.prosigns ? 'ex_chars_en_ar' : (p.punctuation ? 'ex_chars_en_punct' : 'ex_chars_en'),
        ExamKind.plain => p.prosigns ? 'ex_chars_de' : (p.punctuation ? 'ex_chars_punct' : 'ex_chars_plain'),
      };

  String _date(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}. ${two(d.hour)}:${two(d.minute)}';
  }

  Widget _copyView(AppColors c) {
    final correcting = _phase == _Phase.correct;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          correcting
              ? ExamStrings.f('ex_correct', [_correctLeft])
              : (_leadIn > 0 ? '$_leadIn' : ExamStrings.t('ex_listening')),
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'CwMono', fontSize: 16, color: c.accent),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: TextField(
            controller: _typed,
            autofocus: true,
            expands: true,
            maxLines: null,
            minLines: null,
            textAlignVertical: TextAlignVertical.top,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword,
            style: TextStyle(fontFamily: 'CwMono', fontSize: 18, color: c.textPrimary),
            decoration: InputDecoration(
              hintText: ExamStrings.t('ex_type_hint'),
              filled: true,
              fillColor: c.surface,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
            onChanged: (_) => PracticeClock.instance.touch(),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: AppButton(label: ExamStrings.t('ex_abort'), primary: false,
              color: c.textMuted, onTap: _toSetup)),
          if (correcting) ...[
            const SizedBox(width: 12),
            Expanded(child: AppButton(label: ExamStrings.t('ex_done_btn'),
                color: c.accent, onTap: _finish)),
          ],
        ]),
      ]),
    );
  }

  Widget _resultView(AppColors c) {
    final g = _grade!;
    final color = g.passed ? c.accent : c.danger;
    final weak = g.weakChars;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        AppCard(
          borderColor: color,
          child: Column(children: [
            Text(ExamStrings.t(g.passed ? 'ex_passed' : 'ex_failed'),
                style: TextStyle(fontFamily: 'CwMono', fontSize: 22, color: color)),
            const SizedBox(height: 6),
            Text(ExamStrings.f('ex_errors', [g.errors, g.limit]),
                style: TextStyle(fontFamily: 'CwMono', fontSize: 14, color: c.textPrimary)),
            if (_profile.retries > 0) ...[
              const SizedBox(height: 6),
              Text(
                  !g.passed && _attempt > _profile.retries
                      ? ExamStrings.t('ex_exhausted')
                      : ExamStrings.f('ex_attempt', [_attempt, _profile.retries + 1]),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.textMuted)),
            ],
            const SizedBox(height: 6),
            Text(
              weak.isEmpty
                  ? ExamStrings.t('ex_none_weak')
                  : ExamStrings.f('ex_weak', [weak.take(8).map((e) => e.key).join(' ')]),
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.textMuted),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        AppCaption(ExamStrings.t('ex_played')),
        const SizedBox(height: 6),
        AppCard(child: _diffText(c, g)),
        const SizedBox(height: 12),
        AppCaption(ExamStrings.t('ex_yours')),
        const SizedBox(height: 6),
        AppCard(
          child: Text(_typed.text.trim().isEmpty ? '–' : _typed.text.toUpperCase(),
              style: TextStyle(fontFamily: 'CwMono', fontSize: 14, color: c.textPrimary)),
        ),
        const SizedBox(height: 16),
        if (!g.passed && _attempt <= _profile.retries)
          AppButton(label: ExamStrings.f('ex_retry', [_profile.retries + 1 - _attempt]),
              icon: Icons.refresh_rounded, color: c.accent, onTap: () => _start(retry: true))
        else
          AppButton(label: ExamStrings.t(g.passed ? 'ex_again' : 'ex_new_exam'),
              icon: Icons.refresh_rounded, color: c.accent, onTap: _start),
        const SizedBox(height: 8),
        if (_profile.hasSend) ...[
          AppButton(label: ExamStrings.t('ex_to_send'), icon: Icons.touch_app_outlined,
              color: c.warning, primary: false, onTap: _openSend),
          const SizedBox(height: 8),
        ],
        AppButton(label: ExamStrings.t('ex_back'), primary: false,
            color: c.textMuted, onTap: _toSetup),
      ],
    );
  }

  /// The sent text without spaces, wrongly copied characters in red.
  Widget _diffText(AppColors c, ExamGrade g) {
    return Text.rich(TextSpan(
      children: [
        for (var i = 0; i < g.played.length; i++)
          TextSpan(
            text: g.played[i],
            style: TextStyle(color: g.ok[i] ? c.textPrimary : c.danger,
                fontWeight: g.ok[i] ? FontWeight.normal : FontWeight.bold),
          ),
      ],
      style: const TextStyle(fontFamily: 'CwMono', fontSize: 14, letterSpacing: 1),
    ));
  }
}
