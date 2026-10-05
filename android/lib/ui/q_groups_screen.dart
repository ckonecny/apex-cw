// Q-groups mode (issue #41, docs/DECISIONS.md "Q-groups mode"): hear a Q-group
// in Morse and pick its meaning from four options. Content and questions come
// from content/q_groups_engine.dart; the hit rate of a round goes into the
// same log format as head copy (content/head_copy_log.dart, own key), and the
// time counts for the daily goal through the practice clock.
//
// The settings have their own profile (qg.*), pushed to the shared generator
// before every playback (rule 2). The group stays hidden until it is answered.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../content/head_copy_log.dart';
import '../content/q_groups_data.dart';
import '../content/q_groups_engine.dart';
import '../content/training_profile.dart';
import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import '../util/interference_profile.dart';
import '../util/keep_screen_on.dart';
import '../util/practice_clock.dart';
import 'q_groups_sheet_screen.dart';
import 'widgets/app_ui.dart';
import 'widgets/char_playback_overlay.dart' show cwGenEvents;
import 'widgets/interference_button.dart';
import 'widgets/setting_rows.dart';

part 'q_groups_views.dart';

/// Settings of the Q-groups profile.
class QgSettings {
  int lang = 0; // content language: 0 German, 1 English
  int level = 1; // groups of level <= this
  int count = 10; // questions per round
  int wpm = 20, interChar = 3, interWord = 7;

  static const counts = [5, 10];

  static Future<QgSettings> load() async {
    final p = await SharedPreferences.getInstance();
    if (p.getInt('qg.wpm') == null) {
      // First visit: start from the Hören profile's speed and spacing.
      final hear = await TrainingProfile.open(TrainingProfile.hear);
      await p.setInt('qg.wpm', TrainingProfile.clampWpm(hear.getInt('wpm')));
      await p.setInt('qg.interCharSpace', (hear.getInt('interCharSpace') ?? 3).clamp(3, 45));
      await p.setInt('qg.interWordSpace', (hear.getInt('interWordSpace') ?? 7).clamp(6, 105));
    }
    final s = QgSettings();
    s.lang = (p.getInt('qg.lang') ?? Strings.lang.value).clamp(0, 1);
    s.level = (p.getInt('qg.level') ?? 1).clamp(1, qgLevels);
    final n = p.getInt('qg.count') ?? 10;
    s.count = counts.contains(n) ? n : 10;
    s.wpm = TrainingProfile.clampWpm(p.getInt('qg.wpm'));
    s.interChar = (p.getInt('qg.interCharSpace') ?? 3).clamp(3, 45);
    s.interWord = (p.getInt('qg.interWordSpace') ?? 7).clamp(s.interChar < 6 ? 6 : s.interChar, 105);
    return s;
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('qg.lang', lang);
    await p.setInt('qg.level', level);
    await p.setInt('qg.count', count);
    await p.setInt('qg.wpm', wpm);
    await p.setInt('qg.interCharSpace', interChar);
    await p.setInt('qg.interWordSpace', interWord);
  }
}

enum _Phase { setup, ask, result }

class QGroupsScreen extends StatefulWidget {
  const QGroupsScreen({super.key});

  @override
  State<QGroupsScreen> createState() => _QGroupsScreenState();
}

class _QGroupsScreenState extends State<QGroupsScreen> {
  // setState for the view extension in q_groups_views.dart.
  void _update(VoidCallback fn) => setState(fn);

  static const _genChannel = MethodChannel('at.oe1cko.nextcwtrainer/cw_generator');
  static const _toneChannel = MethodChannel('at.oe1cko.nextcwtrainer/cw_tone');
  static const _resultsKey = 'qg.results';

  QgSettings _s = QgSettings();
  List<HcResult> _results = [];
  bool _ready = false;

  _Phase _phase = _Phase.setup;
  QgRound? _round;
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
  int _playingIdx = -1; // question playing now (result list)
  Completer<void>? _doneWait;
  StreamSubscription? _genSub;

  @override
  void initState() {
    super.initState();
    KeepScreenOn.enable();
    PracticeClock.instance.enter('qgroups');
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
    _s = await QgSettings.load();
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

  /// Plays the Q-group of question [index] (default: the one being asked).
  Future<void> _playQuestion([int? index]) async {
    final r = _round;
    if (r == null) return;
    final i = index ?? _q;
    _stopAudio();
    final gen = _playGen;
    setState(() {
      _playing = true;
      _playingIdx = i;
    });
    InterferenceProfile.requestAmbient(this);
    await _pushAudio();
    if (gen != _playGen || !mounted) return;
    _doneWait = Completer<void>();
    await _genChannel.invokeMethod('playOne', r.questions[i].cwText);
    await _doneWait!.future;
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
      _round = QGroupsEngine().newRound(_s.level, _s.count, _s.lang == 0 ? 'de' : 'en');
      _q = 0;
      _picked = null;
      _answers.clear();
      _last = null;
      _playingIdx = -1;
      _phase = _Phase.ask;
    });
    _playQuestion();
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
      _playQuestion();
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

  void _openSheet() => Navigator.push(
      context, MaterialPageRoute(builder: (_) => QGroupsSheetScreen(lang: _s.lang, level: _s.level)));

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
            title: appBarTitle(c, Strings.t('qg_title')),
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
