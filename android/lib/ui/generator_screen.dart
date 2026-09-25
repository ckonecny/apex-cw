import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../content/cw_content.dart';
import '../content/char_stats.dart';
import 'char_stats_screen.dart';
import 'echo_trainer_screen.dart';
import 'adaptive_copy_body.dart';
import '../theme/app_colors.dart';
import '../util/keep_screen_on.dart';
import '../l10n/strings.dart';
import '../content/training_profile.dart';
import '../content/charset_content.dart';
import 'widgets/charset_header.dart';
import 'widgets/char_actions_sheet.dart';
import 'widgets/training_settings_sheet.dart';

class GeneratorScreen extends StatefulWidget {
  const GeneratorScreen({super.key});

  @override
  State<GeneratorScreen> createState() => _GeneratorScreenState();
}

class _GeneratorScreenState extends State<GeneratorScreen> {
  static const _genChannel = MethodChannel('at.oe1cko.nextcwtrainer/cw_generator');
  static const _toneChannel = MethodChannel('at.oe1cko.nextcwtrainer/cw_tone');

  String _practiceChars = '';
  int  _wpm        = 20;
  int  _kochLevel  = 5;
  // Character set + content (docs/training/P7), stored in the Hören profile.
  CharsetChoice _choice = const CharsetChoice(CharSet.koch, ContentKind.random);
  bool get _koch => _choice.set == CharSet.koch;
  int  _outputCase = 0;   // 0=lower, 1=UPPER — display only, content stays uppercase internally
  int  _wordLengthMax  = 0;
  int  _groupLength    = 5;
  int  _randomOption   = 0;
  int  _abbrevLengthMax = 0;
  int  _maxWords        = 0;
  int  _interCharSpace = 28;
  int  _interWordSpace = 40;
  int    _kochSeq         = 0;
  String _customKochChars = 'esno0tqr5ucd9al8ix1myj7h4gvkfz3b.6/w2p?';
  int    _licwCarouselStart = 0;
  List<String> get _activeKochChars =>
      kochSequenceChars(_kochSeq, _customKochChars, licwCarouselStart: _licwCarouselStart);

  // While a block is running, the pre-start controls are hidden and the back
  // button returns to the idle phase instead of leaving the screen.
  // _adaptiveActive mirrors AdaptiveCopyBody's own idle-vs-active phase via
  // onActiveChanged, since that state lives inside the child widget.
  final _adaptiveController = AdaptiveCopyController();
  bool _adaptiveActive = false;
  bool get _practiceActive => _adaptiveActive;

  @override
  void initState() {
    super.initState();
    KeepScreenOn.enable();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    final pf = await TrainingProfile.open(TrainingProfile.hear);
    if (mounted) setState(() {
      _wpm            = pf.getInt('wpm')            ?? 20;
      _kochLevel      = pf.getInt('kochLevel')      ?? 5;
      _choice         = CharsetChoice.load(pf);
      _practiceChars  = pf.getString('practiceChars') ?? '';
      _outputCase     = (p.getInt('outputCase')     ?? 0).clamp(0, 1);
      _wordLengthMax  = pf.getInt('wordLengthMax')  ?? 0;
      _groupLength    = pf.getInt('groupLength')    ?? 5;
      _randomOption   = (pf.getInt('randomOption')  ?? 0).clamp(0, 9);
      _abbrevLengthMax = (pf.getInt('abbrevLengthMax') ?? 0).clamp(0, 5);
      _maxWords        = pf.getInt('maxWords')        ?? 0;
      _interCharSpace = (pf.getInt('interCharSpace') ?? 28).clamp(3, 45);
      _interWordSpace = (pf.getInt('interWordSpace') ?? 40).clamp(6, 105);
      _kochSeq         = (p.getInt('kochSeq') ?? 0).clamp(0, 4);
      _customKochChars = (p.getString('customKochChars') ?? '').isNotEmpty
          ? p.getString('customKochChars')!
          : 'esno0tqr5ucd9al8ix1myj7h4gvkfz3b.6/w2p?';
      _licwCarouselStart = (p.getInt('licwCarouselStart') ?? 0).clamp(0, 13);
      _kochLevel = _kochLevel.clamp(2, _activeKochChars.length);
    });
    _genChannel.invokeMethod('setKochChars', _activeKochChars);
    await _restorePracticeCharsAndBoost();
    // Sidetone pitch/envelope: left at whatever another screen last set otherwise.
    final pitch = p.getInt('pitch') ?? 600;
    final toneSoftness = (p.getInt('toneSoftness') ?? 4).clamp(0, 8);
    await _toneChannel.invokeMethod('setFreq', pitch);
    await _toneChannel.invokeMethod('setEnvelopeMs', (toneSoftness + 1).toDouble());
  }

  // Per-training settings (docs/training/P3). The sheet only saves; reloading
  // re-reads the profile and pushes practice set/boost to the shared native
  // generator (rule 2). Spacing, wpm etc. are pushed when a block starts.
  Future<void> _openSettingsSheet() async {
    await showTrainingSettingsSheet(context,
        profile: TrainingProfile.hear,
        sections: [
          // Koch-specific and global: lives only in the Koch Trainer's sheet.
          if (_koch) TrainingSection.kochSequence,
          TrainingSection.content,
          TrainingSection.spacing,
          TrainingSection.wordSelection,
          TrainingSection.adaptive,
        ]);
    if (mounted) await _loadPrefs();
  }

  Future<void> _savePrefs() async {
    final pf = await TrainingProfile.open(TrainingProfile.hear);
    await pf.setInt('wpm',       _wpm);
    await pf.setInt('kochLevel', _kochLevel);
    await _choice.save(pf);
    // Changed via AdaptiveCopyBody's onSpacingChanged; persisted so the
    // settings sheet reflects the adapted value too.
    await pf.setInt('interCharSpace', _interCharSpace);
    await pf.setInt('interWordSpace', _interWordSpace);
  }

  @override
  void dispose() {
    KeepScreenOn.disable();
    // The adaptive block pushes practiceChars/boostLevel to the shared
    // generator (CLAUDE.md rule 2). Restore the profile's own values on the
    // way out.
    _restorePracticeCharsAndBoost();
    super.dispose();
  }

  Future<void> _restorePracticeCharsAndBoost() async {
    final pf = await TrainingProfile.open(TrainingProfile.hear);
    final practiceChars = parsePracticeChars(pf.getString('practiceChars') ?? '');
    final boostLevel = (pf.getInt('boostLevel') ?? 0).clamp(0, 2);
    await _genChannel.invokeMethod('setPracticeChars', practiceChars);
    await _genChannel.invokeMethod('setBoostLevel', boostLevel);
  }

  // Back button while a block is active: return to the idle phase instead of
  // leaving the screen (see PopScope in build()).
  void _exitPracticeToSetup() {
    if (_adaptiveActive) _adaptiveController.resetToIdle();
  }

  // Tap on a Koch character: listen to it or practise it with the echo
  // drill (docs/training/P7, decision 6). The drill is the former Learn New
  // Chr / Preview Char (Koch::getNewChar()/getKochChar()).
  Future<void> _onCharTap(String ch) => showCharActionsSheet(context,
      ch: ch, outputCase: _outputCase,
      onListen: () => playCharThrice(ch, wpm: _wpm, interWordSpace: _interWordSpace),
      onEcho: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EchoTrainerScreen(
        fixedTarget: ch, title: Strings.t('char_echo_title').replaceFirst('{ch}', ch.toUpperCase()),
      ))));

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final title = Strings.t('block_hear');
    // Rebuild this whole screen the instant the language changes — see the
    // matching comment in settings_screen.dart's build().
    return ValueListenableBuilder<int>(
      valueListenable: Strings.lang,
      builder: (context, _, __) => PopScope(
      // While a block/session is actively running, the back button returns
      // to this screen's own setup/start state instead of leaving the
      // screen entirely — see _exitPracticeToSetup().
      canPop: !_practiceActive,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _exitPracticeToSetup();
      },
      child: Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.surface,
        title: Text(title,
            style: TextStyle(fontFamily: 'CwMono', fontSize: 16,
                color: c.textPrimary)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.textMuted),
          onPressed: () => Navigator.maybePop(context),
        ),
        actions: [
          if (!_practiceActive)
            IconButton(
              icon: Icon(Icons.bar_chart_outlined, color: c.textMuted),
              tooltip: Strings.t('char_stats_title_hear'),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const CharStatsScreen(track: CharStatsStore.hear))),
            ),
          if (!_practiceActive)
            IconButton(
              icon: Icon(Icons.settings, color: c.textMuted),
              tooltip: Strings.t('settings_title'),
              onPressed: _openSettingsSheet,
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Character set + content (hidden while a block runs) ──────────
          if (!_practiceActive)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: CharsetHeader(
                choice: _choice,
                onChanged: (v) {
                  setState(() => _choice = v);
                  _savePrefs();
                },
                kochLevel: _kochLevel,
                kochSequence: _activeKochChars,
                onKochLevelChanged: (v) { setState(() => _kochLevel = v); _savePrefs(); },
                outputCase: _outputCase,
                onCharTap: _onCharTap,
                practiceChars: _practiceChars,
                onPracticeCharsChanged: (v) async {
                  _practiceChars = v;
                  final pf = await TrainingProfile.open(TrainingProfile.hear);
                  await pf.setString('practiceChars', v);
                },
              ),
            ),

          // ── Practice area: the send→reveal→mark→result block flow ─────────
          // Keyed so its state (phase) survives sibling changes.
          Expanded(
            key: const ValueKey('koch_practice_area'),
            child: AdaptiveCopyBody(
              kochLevel: _kochLevel,
              activeKochChars: _activeKochChars,
              kochLesson: _koch,
              randomOption: _randomOption,
              wordLengthMax: _wordLengthMax,
              contentModeIndex: allowedContents(_choice.set).indexOf(_choice.content),
              contentModeOrdinals: [for (final k in allowedContents(_choice.set)) engineSelection(_choice.set, k).mode],
              contentModeLabels: [for (final k in allowedContents(_choice.set)) contentLabel(k)],
              wpm: _wpm,
              groupLength: _groupLength,
              maxWords: _maxWords,
              abbrevLengthMax: _abbrevLengthMax,
              interCharSpace: _interCharSpace,
              interWordSpace: _interWordSpace,
              onWpmChanged: (v) { setState(() => _wpm = v); _savePrefs(); },
              onKochLevelChanged: (v) {
                setState(() => _kochLevel = v.clamp(2, _activeKochChars.length));
                _savePrefs();
              },
              onSpacingChanged: (ic, iw) {
                setState(() { _interCharSpace = ic; _interWordSpace = iw; });
                _savePrefs();
              },
              controller: _adaptiveController,
              onActiveChanged: (v) { if (mounted) setState(() => _adaptiveActive = v); },
            ),
          ),

          // ── Controls ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(children: [
              _SliderRow(
                label: 'WPM', value: _wpm.toDouble(),
                min: 5, max: 60, divisions: 55,
                onChanged: (v) {
                  setState(() => _wpm = v.round());
                  _savePrefs();
                },
              ),
            ]),
          ),

          // ── Start (idle only; the running block has its own buttons) ─────
          if (!_practiceActive)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.accent.withOpacity(0.2),
                    foregroundColor: c.accent,
                    side: BorderSide(color: c.accent),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _adaptiveController.start,
                  child: const Text('▶  START',
                      style: TextStyle(fontFamily: 'CwMono', fontSize: 18,
                          fontWeight: FontWeight.bold)),
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

// ── Sub-widgets ──

class _SliderRow extends StatelessWidget {
  final String label;
  final double value, min, max;
  final int divisions;
  final ValueChanged<double> onChanged;
  const _SliderRow({required this.label, required this.value, required this.min,
      required this.max, required this.divisions, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Row(
    children: [
      SizedBox(width: 50, child: Text(label,
          style: TextStyle(fontFamily: 'CwMono', fontSize: 11,
              color: c.textMuted))),
      Expanded(child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: c.accent,
          inactiveTrackColor: c.border,
          thumbColor: c.accent,
          overlayColor: c.accent.withOpacity(0.1),
          trackHeight: 3,
        ),
        child: Slider(value: value, min: min, max: max,
            divisions: divisions, onChanged: onChanged),
      )),
      SizedBox(width: 40, child: Text(value.round().toString(),
          textAlign: TextAlign.right,
          style: TextStyle(fontFamily: 'CwMono', fontSize: 12,
              color: c.accent))),
    ],
  );
  }
}
