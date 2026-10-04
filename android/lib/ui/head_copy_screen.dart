// Comprehension / head copy (issue #7, docs/DECISIONS.md "Head copy /
// comprehension"): hear one to three short sentences in Morse without writing
// anything down, then answer multiple-choice questions about them. Content and
// questions come from content/head_copy_engine.dart; the hit rate of a round
// goes into content/head_copy_log.dart, and the time counts for the daily goal
// through the practice clock.
//
// The settings have their own profile (hc.*), pushed to the shared generator
// before every playback (rule 2). The text stays hidden until the result.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../content/head_copy_data.dart';
import '../content/head_copy_engine.dart';
import '../content/head_copy_log.dart';
import '../content/training_profile.dart';
import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import '../util/interference_profile.dart';
import '../util/keep_screen_on.dart';
import '../util/practice_clock.dart';
import 'widgets/app_ui.dart';
import 'widgets/char_playback_overlay.dart' show cwGenEvents;
import 'widgets/interference_button.dart';
import 'widgets/setting_rows.dart';

part 'head_copy_views.dart';

const _sentenceGapMs = 1800;

/// Settings of the comprehension profile.
class HcSettings {
  int lang = 0; // content language: 0 German, 1 English
  int level = 1;
  int wpm = 20, interChar = 3, interWord = 7;

  static Future<HcSettings> load() async {
    final p = await SharedPreferences.getInstance();
    if (p.getInt('hc.wpm') == null) {
      // First visit: start from the Hören profile's speed and spacing.
      final hear = await TrainingProfile.open(TrainingProfile.hear);
      await p.setInt('hc.wpm', TrainingProfile.clampWpm(hear.getInt('wpm')));
      await p.setInt('hc.interCharSpace', (hear.getInt('interCharSpace') ?? 3).clamp(3, 45));
      await p.setInt('hc.interWordSpace', (hear.getInt('interWordSpace') ?? 7).clamp(6, 105));
    }
    final s = HcSettings();
    s.lang = (p.getInt('hc.lang') ?? Strings.lang.value).clamp(0, 1);
    s.level = (p.getInt('hc.level') ?? 1).clamp(1, 3);
    s.wpm = TrainingProfile.clampWpm(p.getInt('hc.wpm'));
    s.interChar = (p.getInt('hc.interCharSpace') ?? 3).clamp(3, 45);
    s.interWord = (p.getInt('hc.interWordSpace') ?? 7).clamp(s.interChar < 6 ? 6 : s.interChar, 105);
    return s;
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('hc.lang', lang);
    await p.setInt('hc.level', level);
    await p.setInt('hc.wpm', wpm);
    await p.setInt('hc.interCharSpace', interChar);
    await p.setInt('hc.interWordSpace', interWord);
  }
}

enum _Phase { setup, listen, ask, result }

class HeadCopyScreen extends StatefulWidget {
  const HeadCopyScreen({super.key});

  @override
  State<HeadCopyScreen> createState() => _HeadCopyScreenState();
}

class _HeadCopyScreenState extends State<HeadCopyScreen> {
  // setState for the view extension in head_copy_views.dart.
  void _update(VoidCallback fn) => setState(fn);

  static const _genChannel = MethodChannel('at.oe1cko.nextcwtrainer/cw_generator');
  static const _toneChannel = MethodChannel('at.oe1cko.nextcwtrainer/cw_tone');

  HcSettings _s = HcSettings();
  List<HcResult> _results = [];
  bool _ready = false;

  _Phase _phase = _Phase.setup;
  HcRound? _round;
  int _q = 0; // question being asked
  int? _picked; // option tapped on the current question
  final List<int> _answers = []; // option tapped per question
  HcResult? _last; // result of the finished round

  bool _playingNow = false;
  bool get _playing => _playingNow;
  // Playing counts as practice for the practice clock even without touches.
  set _playing(bool v) {
    _playingNow = v;
    PracticeClock.instance.audioPlaying = v;
    if (v) PracticeClock.instance.touch();
  }

  int _playGen = 0; // bumped to cancel a running playback
  int _playingIdx = -1; // sentence playing now
  Completer<void>? _doneWait;
  StreamSubscription? _genSub;

  @override
  void initState() {
    super.initState();
    KeepScreenOn.enable();
    PracticeClock.instance.enter('headcopy');
    _init();
  }

  @override
  void dispose() {
    _stopAudio();
    InterferenceProfile.releaseAmbient(this);
    KeepScreenOn.disable();
    PracticeClock.instance.leave();
    _genSub?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    _s = await HcSettings.load();
    final prefs = await SharedPreferences.getInstance();
    _results = hcParseResults(prefs.getString(_resultsKey));
    await _pushAudio();
    _genSub = cwGenEvents.listen((raw) {
      if (raw is Map && raw['type'] == 'done') {
        final w = _doneWait;
        if (w != null && !w.isCompleted) w.complete();
      }
    });
    if (mounted) setState(() => _ready = true);
  }

  static const _resultsKey = 'hc.results';

  /// Everything the shared native engine needs for this screen.
  Future<void> _pushAudio() async {
    final prefs = await SharedPreferences.getInstance();
    await _toneChannel.invokeMethod('setFreq', prefs.getInt('pitch') ?? 600);
    await _toneChannel.invokeMethod('setEnvelopeMs',
        ((prefs.getInt('toneSoftness') ?? 4).clamp(0, 8) + 1).toDouble());
    await _genChannel.invokeMethod('setWpm', _s.wpm);
    await _genChannel.invokeMethod('setInterCharSpace', _s.interChar);
    await _genChannel.invokeMethod('setInterWordSpace', _s.interWord);
  }

  HeadCopyEngine get _engine => HeadCopyEngine(_s.lang == 0 ? deContent : enContent);

  // ---- playback ----

  /// Stops a running playback; the caller updates the state.
  void _stopAudio() {
    _playGen++;
    final w = _doneWait;
    if (w != null && !w.isCompleted) w.complete();
    _playingNow = false;
    PracticeClock.instance.audioPlaying = false;
    _genChannel.invokeMethod('stopOne');
    InterferenceProfile.releaseAmbient(this);
  }

  void _stop() {
    _stopAudio();
    setState(() => _playingIdx = -1);
  }

  /// Plays all sentences of the round, with a pause between them.
  Future<void> _playRound() async {
    final r = _round;
    if (r == null) return;
    _stopAudio();
    final gen = _playGen;
    setState(() => _playing = true);
    InterferenceProfile.requestAmbient(this);
    await _pushAudio();
    for (var i = 0; i < r.sentences.length; i++) {
      if (gen != _playGen || !mounted) return;
      setState(() => _playingIdx = i);
      _doneWait = Completer<void>();
      await _genChannel.invokeMethod('playOne', r.sentences[i].cwText);
      await _doneWait!.future;
      if (gen != _playGen || !mounted) return;
      if (i < r.sentences.length - 1) await Future<void>.delayed(const Duration(milliseconds: _sentenceGapMs));
    }
    if (gen != _playGen || !mounted) return;
    InterferenceProfile.releaseAmbient(this);
    setState(() {
      _playing = false;
      _playingIdx = -1;
    });
  }

  // ---- round flow ----

  void _startRound() {
    _stopAudio();
    _s.save();
    setState(() {
      _round = _engine.newRound(_s.level);
      _q = 0;
      _picked = null;
      _answers.clear();
      _last = null;
      _playingIdx = -1;
      _phase = _Phase.listen;
    });
    _playRound();
  }

  void _toQuestions() {
    _stop();
    setState(() => _phase = _Phase.ask);
  }

  void _pick(int option) {
    if (_picked != null) return;
    setState(() {
      _picked = option;
      _answers.add(option);
    });
    PracticeClock.instance.touch();
  }

  Future<void> _next() async {
    final r = _round!;
    if (_q < r.questions.length - 1) {
      setState(() {
        _q++;
        _picked = null;
      });
      return;
    }
    _stop();
    var right = 0;
    for (var i = 0; i < r.questions.length; i++) {
      if (_answers[i] == r.questions[i].correct) right++;
    }
    final res = HcResult(DateTime.now().millisecondsSinceEpoch, _s.level, _s.lang, right, r.questions.length);
    _results.add(res);
    setState(() {
      _last = res;
      _phase = _Phase.result;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_resultsKey, hcEncodeResults(_results));
  }

  void _toSetup() {
    _stop();
    setState(() => _phase = _Phase.setup);
  }

  /// Back button: from a round to the setup, from the setup out.
  bool _handleBack() {
    if (_phase == _Phase.setup) return true;
    _toSetup();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: Strings.lang,
      builder: (context, _, _) => PopScope(
        canPop: _phase == _Phase.setup,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _handleBack();
        },
        child: Scaffold(
          backgroundColor: c.background,
          appBar: AppBar(
            backgroundColor: c.background,
            title: appBarTitle(c, Strings.t('hc_title')),
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: c.textMuted),
              onPressed: () {
                if (_handleBack()) Navigator.pop(context);
              },
            ),
            actions: const [InterferenceButton()],
          ),
          body: !_ready ? const SizedBox.shrink() : _body(c),
        ),
      ),
    );
  }
}
