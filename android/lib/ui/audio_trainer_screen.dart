// Audio trainer (issue #139): think the characters, then hear the spelling
// words. The app plays one group in Morse, nothing is typed, and after a
// pause a voice names every character in the order sent; then the next group. No grading and no
// statistics; the practice time still counts for the daily goal.
//
// The flow itself is AudioTrainerEngine (content/audio_trainer_engine.dart);
// this screen pushes its config to the shared native engine (rule 2), feeds
// the engine with the native generator and the voice samples, and shows the
// phase. Character set, Koch level and spacing live in the `audio` profile,
// seeded from the Hören profile on first use.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../content/audio_trainer_engine.dart';
import '../content/charset_content.dart';
import '../content/cw_content.dart';
import '../content/training_profile.dart';
import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import '../util/char_color.dart';
import '../util/keep_screen_on.dart';
import '../util/own_text_playback.dart';
import '../util/practice_clock.dart';
import '../util/interference_profile.dart';
import 'widgets/app_ui.dart';
import 'widgets/interference_button.dart';
import 'widgets/char_playback_overlay.dart' show cwGenEvents;
import 'widgets/charset_header.dart';
import 'widgets/setting_rows.dart';
import 'widgets/tempo_spacing_section.dart';
import 'widgets/training_settings_sheet.dart';

const _genChannel = MethodChannel('at.oe1cko.nextcwtrainer/cw_generator');
const _toneChannel = MethodChannel('at.oe1cko.nextcwtrainer/cw_tone');

class AudioTrainerScreen extends StatefulWidget {
  const AudioTrainerScreen({super.key});

  @override
  State<AudioTrainerScreen> createState() => _AudioTrainerScreenState();
}

class _AudioTrainerScreenState extends State<AudioTrainerScreen> {
  late TrainingProfile _pf;
  bool _loaded = false;

  // Character set and spacing (profile `audio`).
  int _wpm = 20, _interChar = 3, _interWord = 7, _kochLevel = 5;
  CharsetChoice _choice = const CharsetChoice(CharSet.koch, ContentKind.random);
  String _practiceChars = '';
  int _wordLengthMin = 0, _wordLengthMax = 0, _wordLanguage = 0;
  int _abbrevLengthMin = 0, _abbrevLengthMax = 0, _randomOption = 0;
  int _kochSeq = 0, _licwCarouselStart = 0;
  String _customKochChars = 'esno0tqr5ucd9al8ix1myj7h4gvkfz3b.6/w2p?';

  // Own settings.
  int _groupMin = 1, _groupMax = 1, _think = 4, _rest = 3, _voice = 0;
  // What introduces a prosign's meaning (profile `atProsign`, index of ProsignIntro).
  int _prosign = 0;
  // Groups per block (profile `maxWords`, as in Hören; stored 0 = the default 10,
  // 51 = endless, which is 0 here).
  int _maxGroups = 10;
  // Voice volume in percent (profile `atVolume`).
  int _voiceVolume = 70;
  int _outputCase = 1;

  AudioTrainerEngine? _engine;
  // Shown after a block ends on its own ("Block finished") until the next start.
  AudioTrainerState _last = const AudioTrainerState();
  bool _starting = false;
  bool _failed = false;
  StreamSubscription<String>? _mediaSub;

  List<String> get _activeKochChars => kochSequenceChars(
    _kochSeq,
    _customKochChars,
    licwCarouselStart: _licwCarouselStart,
  );

  @override
  void initState() {
    super.initState();
    KeepScreenOn.enable();
    PracticeClock.instance.enter('audio');
    // Headset, lock screen and notification buttons (#140).
    _mediaSub = OwnTextPlayback.commands.listen(
      _onMediaCommand,
      onError: (_) {},
    );
    OwnTextPlayback.ensureNotificationPermission();
    _load();
  }

  @override
  void dispose() {
    _mediaSub?.cancel();
    OwnTextPlayback.stop();
    _engine?.stop();
    InterferenceProfile.releaseAmbient(this);
    PracticeClock.instance.audioPlaying = false;
    KeepScreenOn.disable();
    PracticeClock.instance.leave();
    super.dispose();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    _pf = await TrainingProfile.open(TrainingProfile.audio);
    if (p.getInt('audio.kochSeq') == null) {
      // First visit: the Koch sequence starts as Hören's, then is its own.
      await p.setInt('audio.kochSeq', (p.getInt('kochSeq') ?? 0).clamp(0, 4));
      final ck = p.getString('customKochChars');
      if (ck != null && ck.isNotEmpty) {
        await p.setString('audio.customKochChars', ck);
      }
      await p.setInt(
        'audio.licwCarouselStart',
        (p.getInt('licwCarouselStart') ?? 0).clamp(0, 13),
      );
    }
    if (_pf.getInt('wpm') == null) {
      // First visit: start from the Hören profile.
      final hear = await TrainingProfile.open(TrainingProfile.hear);
      for (final f in const [
        'wpm',
        'kochLevel',
        'charset',
        'content',
        'randomOption',
        'wordLengthMax',
        'wordLengthMin',
        'wordLanguage',
        'abbrevLengthMax',
        'abbrevLengthMin',
        'interCharSpace',
        'interWordSpace',
        'boostLevel',
      ]) {
        final v = hear.getInt(f);
        if (v != null) await _pf.setInt(f, v);
      }
      final pc = hear.getString('practiceChars');
      if (pc != null && pc.isNotEmpty) await _pf.setString('practiceChars', pc);
      if (_pf.getInt('wpm') == null) await _pf.setInt('wpm', 20);
    }
    if (!mounted) return;
    setState(() {
      _wpm = TrainingProfile.clampWpm(_pf.getInt('wpm'));
      _kochLevel = _pf.getInt('kochLevel') ?? 5;
      _choice = CharsetChoice.load(_pf);
      _practiceChars = _pf.getString('practiceChars') ?? '';
      _wordLengthMax = _pf.getInt('wordLengthMax') ?? 0;
      _wordLengthMin = (_pf.getInt('wordLengthMin') ?? 0).clamp(0, 8);
      _wordLanguage = (_pf.getInt('wordLanguage') ?? 0).clamp(0, 1);
      _abbrevLengthMin = (_pf.getInt('abbrevLengthMin') ?? 0).clamp(0, 6);
      _abbrevLengthMax = (_pf.getInt('abbrevLengthMax') ?? 0).clamp(0, 5);
      _randomOption = (_pf.getInt('randomOption') ?? 0).clamp(0, 9);
      _interChar = (_pf.getInt('interCharSpace') ?? 28).clamp(3, 45);
      _interWord = (_pf.getInt('interWordSpace') ?? 40).clamp(6, 105);
      _groupMin = (_pf.getInt('groupLength') ?? 1).clamp(1, 8);
      _groupMax = (_pf.getInt('groupLengthMax') ?? _groupMin).clamp(
        _groupMin,
        8,
      );
      final mw = _pf.getInt('maxWords') ?? 0;
      _maxGroups = mw == 0 ? 10 : (mw > 50 ? 0 : mw.clamp(1, 50));
      _think = (_pf.getInt('atThink') ?? 4).clamp(1, 15);
      _rest = (_pf.getInt('atRest') ?? 3).clamp(1, 10);
      _voiceVolume = (_pf.getInt('atVolume') ?? 70).clamp(10, 100);
      _prosign = (_pf.getInt('atProsign') ?? 0).clamp(
        0,
        ProsignIntro.values.length - 1,
      );
      _voice = (_pf.getInt('atVoice') ?? 0).clamp(
        0,
        audioTrainerVoices.length - 1,
      );
      _outputCase = (p.getInt('outputCase') ?? 0).clamp(0, 1);
      _kochSeq = (p.getInt('audio.kochSeq') ?? 0).clamp(0, 4);
      final custom = p.getString('audio.customKochChars') ?? '';
      if (custom.isNotEmpty) _customKochChars = custom;
      _licwCarouselStart = (p.getInt('audio.licwCarouselStart') ?? 0).clamp(
        0,
        13,
      );
      _kochLevel = _kochLevel.clamp(2, _activeKochChars.length);
      _loaded = true;
    });
    await _pushEngineConfig();
    _applyConfig();
  }

  Future<void> _save() async {
    await _pf.setInt('wpm', _wpm);
    await _pf.setInt('kochLevel', _kochLevel);
    await _choice.save(_pf);
    await _pf.setInt('interCharSpace', _interChar);
    await _pf.setInt('interWordSpace', _interWord);
    await _pf.setInt('groupLength', _groupMin);
    await _pf.setInt('groupLengthMax', _groupMax);
    await _pf.setInt('atThink', _think);
    await _pf.setInt('atRest', _rest);
    await _pf.setInt('atVoice', _voice);
  }

  /// The shared native engine keeps whatever another screen left (rule 2).
  Future<void> _pushEngineConfig() async {
    final p = await SharedPreferences.getInstance();
    final boost = (_pf.getInt('boostLevel') ?? 0).clamp(0, 2);
    await _genChannel.invokeMethod('setWpm', _wpm);
    await _genChannel.invokeMethod('setInterCharSpace', _interChar);
    await _genChannel.invokeMethod('setInterWordSpace', _interWord);
    await _genChannel.invokeMethod('setKochChars', _activeKochChars);
    await _genChannel.invokeMethod(
      'setPracticeChars',
      effectivePracticeChars(_choice.set, _practiceChars),
    );
    await _genChannel.invokeMethod('setBoostLevel', boost);
    await _toneChannel.invokeMethod('setVoiceVolume', _voiceVolume / 100);
    await _toneChannel.invokeMethod('setFreq', p.getInt('pitch') ?? 600);
    await _toneChannel.invokeMethod(
      'setEnvelopeMs',
      ((p.getInt('toneSoftness') ?? 4).clamp(0, 8) + 1).toDouble(),
    );
  }

  void _applyConfig() {
    _engine?.config = AudioTrainerConfig(
      thinkPause: Duration(seconds: _think),
      groupPause: Duration(seconds: _rest),
      maxGroups: _maxGroups,
      prosignIntro: ProsignIntro.values[_prosign],
    );
  }

  /// A setting changed: save it and, while running, push it for the next block.
  Future<void> _changed(VoidCallback fn) async {
    setState(fn);
    await _save();
    await _pushEngineConfig();
    _applyConfig();
  }

  Future<String> _nextContent() async {
    final e = _choice.engine;
    final r = await _genChannel.invokeMethod('getNextContent', {
      'mode': e.mode,
      'kochLevel': _kochLevel,
      'kochActive': e.kochActive,
      'groupLength': _groupMin,
      'groupLengthMax': _groupMax,
      'wordLengthMin': _wordLengthMin,
      'wordLanguage': _wordLanguage,
      'abbrevLengthMin': _abbrevLengthMin,
      if (e.usesRandomOption) 'randomOption': _randomOption,
      'wordLengthMax': _wordLengthMax,
      'abbrevLengthMax': _abbrevLengthMax,
    });
    return (r as String?) ?? '';
  }

  Future<void> _playMorse(String text) async {
    final done = Completer<void>();
    final sub = cwGenEvents.listen((raw) {
      if ((raw as Map)['type'] == 'done' && !done.isCompleted) done.complete();
    });
    try {
      await _genChannel.invokeMethod('playOne', text);
      await done.future;
    } finally {
      await sub.cancel();
    }
  }

  Future<void> _start() async {
    if (_starting || _engine != null) return;
    setState(() {
      _starting = true;
      _failed = false;
    });
    await _pushEngineConfig();
    final ok = await _toneChannel.invokeMethod<bool>(
      'loadVoice',
      audioTrainerVoices[_voice],
    );
    if (!mounted) return;
    if (ok != true) {
      setState(() => _starting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(Strings.t('at_voice_error'))));
      return;
    }
    final engine = AudioTrainerEngine(
      nextContent: _nextContent,
      playMorse: _playMorse,
      stopMorse: () => _genChannel.invokeMethod('stopOne'),
      playVoice: (t) =>
          _toneChannel.invokeMethod('playVoiceChar', voiceSampleKey(t)),
      stopVoice: () => _toneChannel.invokeMethod('stopVoice'),
    );
    _engine = engine;
    _last = const AudioTrainerState();
    _applyConfig();
    engine.state.addListener(_onEngineState);
    setState(() => _starting = false);
    PracticeClock.instance.audioPlaying = true;
    _syncBackground();
    // The noise stands while the trainer runs (the voice is not affected).
    InterferenceProfile.requestAmbient(this);
    try {
      await engine.run();
    } on StateError {
      _failed = true;
    } finally {
      engine.state.removeListener(_onEngineState);
      if (engine.state.value.finished) _last = engine.state.value;
      InterferenceProfile.releaseAmbient(this);
      PracticeClock.instance.audioPlaying = false;
      _engine = null;
      _bgSent = false;
      OwnTextPlayback.stop();
      if (mounted) setState(() {});
    }
  }

  bool _bgPlaying = false;
  String _bgSubtitle = '';

  /// Tells the foreground service whether the trainer is playing, so the
  /// notification shows the right button and the session stays alive (#140).
  void _syncBackground() {
    final e = _engine;
    if (e == null) return;
    final playing = !e.state.value.paused;
    final sub = '$_wpm WPM · ${Strings.t('at_bg_gap')} $_interChar';
    if (playing == _bgPlaying && sub == _bgSubtitle && _bgSent) return;
    _bgPlaying = playing;
    _bgSubtitle = sub;
    _bgSent = true;
    OwnTextPlayback.update(
      title: Strings.t('at_title'),
      playing: playing,
      labelPrefix: 'at_bg',
      channelId: 'audio_trainer_playback',
      subtitle: sub,
      tune: true,
    );
  }

  bool _bgSent = false;

  void _onMediaCommand(String cmd) {
    final e = _engine;
    if (e == null || !mounted) return;
    switch (cmd) {
      case 'play':
        e.resume();
      case 'pause':
        e.pause();
      case 'next':
        e.skipGroup();
      case 'prev':
        e.repeatGroup();
      // Lock-screen tempo/spacing buttons (#152): saved like the screen's own
      // controls; the generator takes them from the next group on.
      case 'tempo_down' || 'tempo_up':
        final w = TrainingProfile.clampWpm(_wpm + (cmd == 'tempo_up' ? 1 : -1));
        if (w != _wpm) _changed(() => _wpm = w).then((_) => _syncBackground());
      case 'gap_down' || 'gap_up':
        final (ic, iw) =
            stepCharSpacing(_interChar, _interWord, cmd == 'gap_up' ? 1 : -1);
        if (ic != _interChar) {
          _changed(() {
            _interChar = ic;
            _interWord = iw;
          }).then((_) => _syncBackground());
        }
    }
  }

  void _onEngineState() {
    // Keeps the practice clock alive across the long silent pauses.
    PracticeClock.instance.touch();
    _syncBackground();
    if (mounted) setState(() {});
  }

  Future<void> _stop() async => _engine?.stop();

  // Group/word/abbreviation length, Koch sequence, think and group pauses and
  // the voice live in the settings sheet, like the other trainings' options.
  Future<void> _openSettings() async {
    await showTrainingSettingsSheet(
      context,
      profile: TrainingProfile.audio,
      sections: [
        if (_choice.set == CharSet.koch) TrainingSection.kochSequence,
        TrainingSection.wordSelection,
        TrainingSection.audioFlow,
      ],
    );
    if (mounted) await _load();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  String _phaseText(AudioTrainerState s) => s.finished
      ? Strings.t('at_phase_finished')
      : Strings.t(switch (s.phase) {
          AudioTrainerPhase.idle => 'at_phase_idle',
          AudioTrainerPhase.morse => 'at_phase_morse',
          AudioTrainerPhase.think => 'at_phase_think',
          AudioTrainerPhase.solution => 'at_phase_solution',
          AudioTrainerPhase.rest => 'at_phase_rest',
        });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final engine = _engine;
    final running = engine != null;
    final s = engine?.state.value ?? _last;
    return ValueListenableBuilder<int>(
      valueListenable: Strings.lang,
      builder: (context, _, _) => PopScope(
        // While running, back stops and returns to the start view (as in
        // Hören) instead of leaving the screen.
        canPop: !running,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _engine?.stop();
        },
        child: Scaffold(
          backgroundColor: c.background,
          appBar: AppBar(
            backgroundColor: c.background,
            title: appBarTitle(
              c,
              Strings.t('at_title'),
              compact: Strings.t('at_title'),
            ),
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: c.textMuted),
              onPressed: () => Navigator.maybePop(context),
            ),
            actions: [
              const InterferenceButton(),
              if (!running)
                IconButton(
                  tooltip: Strings.t('settings_title'),
                  icon: Icon(Icons.settings, color: c.textMuted),
                  onPressed: _loaded ? _openSettings : null,
                ),
            ],
          ),
          body: !_loaded
              ? const SizedBox.shrink()
              : running
              ? _runningView(c, s)
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        children: [
                          CharsetHeader(
                            choice: _choice,
                            onChanged: (v) => _changed(() => _choice = v),
                            kochLevel: _kochLevel,
                            kochSequence: _activeKochChars,
                            onKochLevelChanged: (v) => _changed(
                              () => _kochLevel = v.clamp(
                                2,
                                _activeKochChars.length,
                              ),
                            ),
                            outputCase: _outputCase,
                            practiceChars: _practiceChars,
                            onPracticeCharsChanged: (v) async {
                              setState(() => _practiceChars = v);
                              await _pf.setString('practiceChars', v);
                              await _pushEngineConfig();
                            },
                            wordLanguage: _wordLanguage,
                            wordLengthMin: _wordLengthMin,
                            wordLengthMax: _wordLengthMax,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            Strings.t('at_intro'),
                            style: TextStyle(
                              fontSize: 13,
                              color: c.textMuted,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _status(c, s),
                          const SizedBox(height: 12),
                          SettingsCard(
                            children: [
                              TempoSpacingSection(
                                wpm: _wpm,
                                interChar: _interChar,
                                interWord: _interWord,
                                compact: true,
                                showUndo: false,
                                // One group at a time: there is no word gap to set.
                                showWordGap: false,
                                onWpm: (v) => _changed(() => _wpm = v),
                                onSpacing: (ic, iw) => _changed(() {
                                  _interChar = ic;
                                  _interWord = iw;
                                }),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Start / Pause / Stop stay at the bottom, out of the scrolling.
                    ColoredBox(
                      color: c.background,
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                          child: _startButton(),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _status(AppColors c, AudioTrainerState s) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          Text(
            _phaseText(s),
            style: TextStyle(
              fontSize: 18,
              color: c.textPrimary,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            Strings.t(_maxGroups == 0 ? 'at_groups_count' : 'at_groups_done')
                .replaceFirst('{n}', '${s.groupsDone}')
                .replaceFirst('{max}', '$_maxGroups'),
            style: TextStyle(fontSize: 12, color: c.textMuted),
          ),
          if (_failed) ...[
            const SizedBox(height: 8),
            Text(
              Strings.t('at_error'),
              style: TextStyle(fontSize: 12, color: c.danger),
            ),
          ],
        ],
      ),
    );
  }

  /// Same running view as Hören: block header, big phase text, progress dots,
  /// group count and tempo, Pause / Stop at the bottom. The setup area is gone
  /// while running; the solution has a reserved slot, so nothing jumps.
  Widget _runningView(AppColors c, AudioTrainerState s) {
    final endless = _maxGroups == 0;
    final current = endless
        ? s.groupsDone + 1
        : (s.groupsDone + 1).clamp(1, _maxGroups);
    final solution = s.phase == AudioTrainerPhase.solution;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  Strings.t('at_title').toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: c.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  '${contentLabel(_choice.content)}'
                  '${_choice.set == CharSet.koch ? ' · KOCH $_kochLevel' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c.textMuted),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _phaseText(s),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (!endless)
                    Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        for (var i = 0; i < _maxGroups; i++)
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              i == s.groupsDone
                                  ? Icons.radio_button_checked
                                  : Icons.circle,
                              size: i == s.groupsDone ? 16 : 10,
                              color:
                                  i < s.groupsDone ||
                                      (i == s.groupsDone &&
                                          s.phase != AudioTrainerPhase.morse &&
                                          s.phase != AudioTrainerPhase.idle)
                                  ? c.accent
                                  : c.border,
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  Text(
                    endless
                        ? Strings.t('at_groups_count')
                              .replaceFirst('{n}', '$current')
                        : Strings.t('ac_group_of')
                              .replaceFirst('{n}', '$current')
                              .replaceFirst('{total}', '$_maxGroups'),
                    style: TextStyle(fontSize: 13, color: c.textMuted),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$_wpm WPM',
                    style: TextStyle(fontSize: 12, color: c.textDisabled),
                  ),
                  const SizedBox(height: 24),
                  // Reserved height: the solution appears without moving the rest.
                  SizedBox(
                    height: 44,
                    child: !solution
                        ? null
                        : FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  for (final (i, t)
                                      in audioTrainerTokens(s.group).indexed)
                                    TextSpan(
                                      // Display case from the global
                                      // setting, as in the other trainings.
                                      text: _outputCase == 1
                                          ? t
                                          : t.toLowerCase(),
                                      // Type colors as everywhere else;
                                      // the char being spoken stays full
                                      // and bold, the others are dimmed.
                                      style: TextStyle(
                                        color: i == s.solutionChar
                                            ? charTypeColor(t, c)
                                            : charTypeColor(t, c)
                                                  .withValues(alpha: 0.5),
                                        fontWeight: i == s.solutionChar
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                ],
                              ),
                              style: const TextStyle(
                                fontSize: 28,
                                fontFamily: 'AnonymousPro',
                                letterSpacing: 4,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: Strings.t(s.paused ? 'at_resume' : 'at_pause'),
                    color: c.info,
                    primary: false,
                    onTap: () =>
                        s.paused ? _engine?.resume() : _engine?.pause(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    label: Strings.t('at_stop'),
                    color: c.info,
                    onTap: _stop,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _startButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _starting ? null : _start,
        icon: const Icon(Icons.play_arrow),
        label: Text(Strings.t('at_start')),
      ),
    );
  }
}
