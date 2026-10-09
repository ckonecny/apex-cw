import 'widgets/interference_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../content/cw_content.dart';
import '../content/char_stats.dart';
import 'char_stats_screen.dart';
import 'char_practice_screen.dart';
import 'adaptive_copy_body.dart';
import '../theme/app_colors.dart';
import 'widgets/app_ui.dart';
import 'widgets/slider_row.dart';
import '../util/keep_screen_on.dart';
import '../util/practice_clock.dart';
import '../l10n/strings.dart';
import '../content/training_profile.dart';
import '../content/charset_content.dart';
import 'widgets/charset_header.dart';
import 'widgets/char_playback_overlay.dart';
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
  // Character set + content (docs/archive/training/P7), stored in the Hören profile.
  CharsetChoice _choice = const CharsetChoice(CharSet.koch, ContentKind.random);
  bool get _koch => _choice.set == CharSet.koch;
  int  _outputCase = 0;   // 0=lower, 1=UPPER — display only, content stays uppercase internally
  int  _wordLengthMax  = 0;
  int  _wordLengthMin  = 0;
  int  _wordLanguage   = 0;
  int  _abbrevLengthMin = 0;
  int  _groupLengthMax = 5;
  bool _stopEach       = false;
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
  // Typing mode keyboard on screen: the WPM slider makes room for it.
  bool _keyboardShown = false;
  // Last used way to copy (0 = paper, 1 = typing): its start button is the
  // highlighted one (DECISIONS.md "Hören: typing mode").
  int _copyMode = 0;

  @override
  void initState() {
    super.initState();
    KeepScreenOn.enable();
    PracticeClock.instance.enter('hear');
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    final pf = await TrainingProfile.open(TrainingProfile.hear);
    if (mounted) {
      setState(() {
      _wpm            = TrainingProfile.clampWpm(pf.getInt('wpm'));
      _kochLevel      = pf.getInt('kochLevel')      ?? 5;
      _choice         = CharsetChoice.load(pf);
      _practiceChars  = pf.getString('practiceChars') ?? '';
      _outputCase     = (p.getInt('outputCase')     ?? 0).clamp(0, 1);
      _wordLengthMax  = pf.getInt('wordLengthMax')  ?? 0;
      _stopEach       = (pf.getInt('stopEach') ?? 0) == 1;
      _copyMode       = (pf.getInt('copyMode') ?? 0).clamp(0, 1);
      _groupLength    = pf.getInt('groupLength')    ?? 5;
      _groupLengthMax = (pf.getInt('groupLengthMax') ?? _groupLength).clamp(_groupLength, 8);
      _wordLengthMin  = (pf.getInt('wordLengthMin') ?? 0).clamp(0, 8);
      _wordLanguage   = (pf.getInt('wordLanguage') ?? 0).clamp(0, 1);
      _abbrevLengthMin = (pf.getInt('abbrevLengthMin') ?? 0).clamp(0, 6);
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
    }
    _genChannel.invokeMethod('setKochChars', _activeKochChars);
    await _restorePracticeCharsAndBoost();
    // Sidetone pitch/envelope: left at whatever another screen last set otherwise.
    final pitch = p.getInt('pitch') ?? 600;
    final toneSoftness = (p.getInt('toneSoftness') ?? 4).clamp(0, 8);
    await _toneChannel.invokeMethod('setFreq', pitch);
    await _toneChannel.invokeMethod('setEnvelopeMs', (toneSoftness + 1).toDouble());
  }

  // Per-training settings (docs/archive/training/P3). The sheet only saves; reloading
  // re-reads the profile and pushes practice set/boost to the shared native
  // generator (rule 2). Spacing, wpm etc. are pushed when a block starts.
  Future<void> _openSettingsSheet({TrainingSection? jumpTo}) async {
    await showTrainingSettingsSheet(context,
        jumpTo: jumpTo,
        profile: TrainingProfile.hear,
        sections: [
          // Koch-specific and global: lives only in the Koch Trainer's sheet.
          if (_koch) TrainingSection.kochSequence,
          TrainingSection.content,
          TrainingSection.spacing,
          TrainingSection.wordSelection,
          TrainingSection.hearFlow,
          TrainingSection.adaptive,
        ]);
    if (mounted) await _loadPrefs();
  }

  // Long press on a chip: select it (as a tap would), then open the settings
  // sheet scrolled to its section.
  Future<void> _selectAndOpenSettings(CharsetChoice c, TrainingSection s) async {
    setState(() => _choice = c);
    await _savePrefs();
    if (mounted) await _openSettingsSheet(jumpTo: s);
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
    PracticeClock.instance.leave();
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

  Future<void> _start(bool typing) async {
    setState(() => _copyMode = typing ? 1 : 0);
    _adaptiveController.start(typing: typing);
    final pf = await TrainingProfile.open(TrainingProfile.hear);
    await pf.setInt('copyMode', _copyMode);
  }

  // Back button while a block is active: return to the idle phase instead of
  // leaving the screen (see PopScope in build()).
  void _exitPracticeToSetup() {
    if (_adaptiveActive) _adaptiveController.resetToIdle();
  }

  // Koch character: tap plays it with the code overlay, long press opens the
  // echo drill (docs/archive/training/P7, decision 6). The drill is the former Learn
  // New Chr / Preview Char (Koch::getNewChar()/getKochChar()).
  Future<void> _onCharTap(String ch) => showCharPlayback(context,
      ch: ch, outputCase: _outputCase,
      play: () => playCharThrice(ch, wpm: _wpm, interWordSpace: _interWordSpace));

  Future<void> _onCharLongPress(String ch) => Navigator.push(context, MaterialPageRoute(
      builder: (_) => CharPracticeScreen(ch: ch)));

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final title = Strings.t('block_hear');
    // Rebuild this whole screen the instant the language changes — see the
    // matching comment in settings_screen.dart's build().
    return ValueListenableBuilder<int>(
      valueListenable: Strings.lang,
      builder: (context, _, _) => PopScope(
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
        backgroundColor: c.background,
        title: appBarTitle(c, title),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.textMuted),
          onPressed: () => Navigator.maybePop(context),
        ),
        actions: [
            const InterferenceButton(),
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
                onKochLongPress: () => _selectAndOpenSettings(
                    _choice.withSet(CharSet.koch), TrainingSection.kochSequence),
                onWordsLongPress: () => _selectAndOpenSettings(
                    _choice.withContent(ContentKind.words), TrainingSection.wordSelection),
                wordLanguage: _wordLanguage,
                wordLengthMin: _wordLengthMin,
                wordLengthMax: _wordLengthMax,
                kochLevel: _kochLevel,
                kochSequence: _activeKochChars,
                onKochLevelChanged: (v) { setState(() => _kochLevel = v); _savePrefs(); },
                outputCase: _outputCase,
                onCharTap: _onCharTap,
                onCharLongPress: _onCharLongPress,
                practiceChars: _practiceChars,
                onPracticeCharsChanged: (v) async {
                  setState(() => _practiceChars = v);
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
              stopEachGroup: _stopEach,
              contentModeIndex: allowedContents(_choice.set).indexOf(_choice.content),
              contentModeOrdinals: [for (final k in allowedContents(_choice.set)) engineSelection(_choice.set, k).mode],
              contentModeLabels: [for (final k in allowedContents(_choice.set)) contentLabel(k)],
              wpm: _wpm,
              groupLength: _groupLength,
              groupLengthMax: _groupLengthMax,
              wordLengthMin: _wordLengthMin,
              wordLanguage: _wordLanguage,
              abbrevLengthMin: _abbrevLengthMin,
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
              practiceChars: _practiceChars,
              onActiveChanged: (v) { if (mounted) setState(() => _adaptiveActive = v); },
              onKeyboardChanged: (v) { if (mounted) setState(() => _keyboardShown = v); },
            ),
          ),

          // ── Controls ──────────────────────────────────────────────────────
          if (!_keyboardShown) Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(children: [
              SliderRow(
                label: 'WPM', value: _wpm.toDouble(),
                min: TrainingProfile.minWpm.toDouble(), max: 60,
                divisions: 60 - TrainingProfile.minWpm,
                valueWidth: 112,
                // Farnsworth text speed implied by wpm + spacing, like the
                // adaptive block's status line used to show it.
                display: '$_wpm (eff. ${(50 * _wpm / (31 + 4 * _interCharSpace + _interWordSpace)).round()})',
                onChanged: (v) {
                  setState(() => _wpm = v.round());
                  _savePrefs();
                },
              ),
            ]),
          ),

          // ── Start (idle only; the running block has its own buttons) ─────
          // Two starts: copy on paper, or type on the on-screen keyboard.
          // The last used one is highlighted.
          if (!_practiceActive)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Expanded(child: AppButton(
                  height: 56,
                  label: Strings.t('ac_start_paper').toUpperCase(),
                  icon: Icons.edit_outlined,
                  color: c.accent,
                  primary: _copyMode == 0,
                  onTap: () => _start(false),
                )),
                const SizedBox(width: 12),
                Expanded(child: AppButton(
                  height: 56,
                  label: Strings.t('ac_start_typing').toUpperCase(),
                  icon: Icons.keyboard_outlined,
                  color: c.accent,
                  primary: _copyMode == 1,
                  onTap: () => _start(true),
                )),
              ]),
            ),
        ],
      ),
      ),
      ),
    );
  }
}

// ── Sub-widgets ──
