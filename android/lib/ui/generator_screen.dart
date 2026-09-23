import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../keyer/morse_decoder.dart';
import '../content/cw_content.dart';
import '../content/char_stats.dart';
import 'echo_trainer_screen.dart';
import 'adaptive_copy_body.dart';
import '../theme/app_colors.dart';
import '../util/keep_screen_on.dart';
import '../util/char_color.dart';
import 'widgets/pinch_zoom_text.dart';
import '../l10n/strings.dart';

class GeneratorScreen extends StatefulWidget {
  final bool kochMode;  // true = Koch Trainer, false = CW Generator
  const GeneratorScreen({super.key, this.kochMode = false});

  @override
  State<GeneratorScreen> createState() => _GeneratorScreenState();
}

class _GeneratorScreenState extends State<GeneratorScreen> {
  static const _genChannel = MethodChannel('at.oe1cko.nextcwtrainer/cw_generator');
  static const _genEvents  = EventChannel('at.oe1cko.nextcwtrainer/cw_gen_events');
  static const _toneChannel = MethodChannel('at.oe1cko.nextcwtrainer/cw_tone');

  StreamSubscription? _sub;

  bool _running = false;
  bool _waiting = false;   // paused after a word, waiting for dit(repeat)/dah(next) — stopAfterItem
  int  _wpm        = 20;
  int  _kochLevel  = 5;
  int  _modeIndex  = 0;
  // Koch Trainer's own content selector: position -> CwGenerator.Mode ordinal.
  // Matches the real device's Koch-nested Generator submenu (Random/CW Abbrevs/
  // English Words/Mixed — no Call Signs, no File Player).
  static const _kochModeOrdinals = [0, 5, 1, 3];
  static List<String> get _kochModeLabels =>
      [Strings.t('mode_random'), Strings.t('mode_abbrevs'), Strings.t('mode_words'), Strings.t('mode_mixed')];
  int  _kochModeIndex = 0;
  // Classic (0) vs Adaptiv (1) flow — orthogonal to the content-mode choice
  // above, Koch Trainer only for now (see docs/ADAPTIVE-COPY.md). Random/
  // Abbrevs/Words/Mixed selection above stays shared between both flows.
  int  _flow = 0;
  int  _outputCase = 0;   // 0=lower, 1=UPPER — display only, content stays uppercase internally
  String _displayChar(String ch) => _outputCase == 1 ? ch.toUpperCase() : ch.toLowerCase();
  // 0=Display off, 1=Char by char, 2=Word by word (matches M32 "CW Gen Displ")
  int  _genDisplay     = 1;
  bool _stopAfterItem  = false;
  bool _eachWordTwice  = false;
  int  _wordLengthMax  = 0;
  int  _groupLength    = 5;
  int  _randomOption   = 0;   // "Random Groups" — ignored in Koch mode (kochActive)
  int  _abbrevLengthMax = 0;
  int  _maxWords        = 0;
  int  _callLengthOpt   = 0;
  int  _callRegionOpt   = 0;
  bool _callCommonOnly  = true;
  int  _interCharSpace = 28;
  int  _interWordSpace = 40;

  // Farnsworth text speed implied by char speed + spacing — same formula
  // and status-line format as AdaptiveCopyBody's result screen (minus the
  // Trend/EMA figure, which only exists once the adaptive engine has scored
  // a block; nothing has been sent yet on this start screen).
  int get _effectiveTextWpm {
    final unitsPerWord = 31 + 4 * _interCharSpace + _interWordSpace;
    return (50 * _wpm / unitsPerWord).round();
  }
  int    _kochSeq         = 0;
  String _customKochChars = 'esno0tqr5ucd9al8ix1myj7h4gvkfz3b.6/w2p?';
  int    _licwCarouselStart = 0;
  List<String> get _activeKochChars =>
      kochSequenceChars(_kochSeq, _customKochChars, licwCarouselStart: _licwCarouselStart);

  // Display log: reveals chars/words only once they've actually finished
  // playing — matches the real device (dispGeneratedChar() fires at KEY_UP,
  // and DISPLAY_BY_WORD only prints a word once it's fully sent).
  // Bold spans are the per-session start ("vvv<ka>") and end ("+") markers —
  // matches frameWordForDisplay in m32_v6.ino, which bolds only those two.
  final List<_LogSpan> _log = [];
  String _pendingWord = '';   // word currently being sent (word-by-word mode)
  final ScrollController _logScroll = ScrollController();
  // Auto-scroll to new content unless the user has scrolled up to review
  // earlier history — re-arms once they scroll back to the bottom themselves.
  bool _stickToBottom = true;

  // True while a start/end marker is being played via playOne() — the 'done'
  // event it produces must not be mistaken for the main generator finishing.
  bool _awaitingSignal = false;
  Completer<void>? _signalDone;

  // Decoder (for keyer mode — not used in generator mode directly)
  late final MorseDecoder _decoder;
  String _decodedText = '';

  // Koch Trainer start-screen "weak characters" panel — lets the user see
  // and deselect which lifetime-weak characters get boosted once Start is
  // pressed, same tap-to-exclude idea as Adaptive Copy's result screen
  // (docs/ADAPTIVE-COPY.md). Classic mode itself never records attempts —
  // this only reads history from Adaptive Copy / Echo Trainer sessions, so
  // it's loaded once at screen entry.
  final CharStatsStore _charStats = CharStatsStore();
  Map<String, double> _kochWeakChars = {};
  final Set<String> _excludedKochBoostChars = {};

  // Setup-screen declutter (docs/STATUS.md backlog): while a block/session
  // is actively running, hide the pre-start controls that won't be touched
  // mid-practice (content mode, Learn New/Preview/Practice Echo, Classic/
  // Adaptiv toggle) and repurpose the back button to return here instead of
  // leaving the screen. _adaptiveActive mirrors AdaptiveCopyBody's own
  // idle-vs-active phase via onActiveChanged, since that state lives inside
  // the child widget.
  final _adaptiveController = AdaptiveCopyController();
  bool _adaptiveActive = false;
  bool get _practiceActive => _running || (widget.kochMode && _flow == 1 && _adaptiveActive);
  // Brief pause after pressing Start, before the first content actually
  // plays, so the user can get ready.
  bool _preparing = false;

  @override
  void initState() {
    super.initState();
    KeepScreenOn.enable();
    _decoder = MorseDecoder(onChar: (ch) {
      if (mounted) setState(() => _decodedText = (_decodedText + ch).take(120));
    });
    _logScroll.addListener(() {
      if (!_logScroll.hasClients) return;
      _stickToBottom = _logScroll.position.pixels >= _logScroll.position.maxScrollExtent - 4;
    });
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) setState(() {
      _wpm            = p.getInt('wpm')            ?? 20;
      _kochLevel      = p.getInt('kochLevel')      ?? 5;
      _genDisplay     = (p.getInt('genDisplayMode') ?? 1).clamp(0, 2);
      _kochModeIndex  = (p.getInt('kochModeIndex')  ?? 0).clamp(0, _kochModeLabels.length - 1);
      _flow           = (p.getInt('kochFlow')       ?? 0).clamp(0, 1);
      _outputCase     = (p.getInt('outputCase')     ?? 0).clamp(0, 1);
      _stopAfterItem  = p.getBool('stopAfterItem') ?? false;
      _eachWordTwice  = p.getBool('eachWordTwice') ?? false;
      _wordLengthMax  = p.getInt('wordLengthMax')  ?? 0;
      _groupLength    = p.getInt('groupLength')    ?? 5;
      _randomOption   = (p.getInt('randomOption')  ?? 0).clamp(0, 9);
      _abbrevLengthMax = (p.getInt('abbrevLengthMax') ?? 0).clamp(0, 5);
      _maxWords        = p.getInt('maxWords')        ?? 0;
      _callLengthOpt   = (p.getInt('callLengthOpt') ?? 0).clamp(0, 4);
      _callRegionOpt   = (p.getInt('callRegionOpt') ?? 0).clamp(0, 7);
      _callCommonOnly  = p.getBool('callCommonOnly') ?? true;
      _interCharSpace = (p.getInt('interCharSpace') ?? 28).clamp(3, 45);
      _interWordSpace = (p.getInt('interWordSpace') ?? 40).clamp(6, 105);
      _kochSeq         = (p.getInt('kochSeq') ?? 0).clamp(0, 4);
      _customKochChars = (p.getString('customKochChars') ?? '').isNotEmpty
          ? p.getString('customKochChars')!
          : 'esno0tqr5ucd9al8ix1myj7h4gvkfz3b.6/w2p?';
      _licwCarouselStart = (p.getInt('licwCarouselStart') ?? 0).clamp(0, 13);
      _kochLevel = _kochLevel.clamp(2, _activeKochChars.length);
    });
    _genChannel.invokeMethod('setKochChars', _activeKochChars);
    final p2 = await SharedPreferences.getInstance();
    final practiceChars = parsePracticeChars(p2.getString('practiceChars') ?? '');
    final boostLevel    = (p2.getInt('boostLevel') ?? 0).clamp(0, 2);
    await _genChannel.invokeMethod('setPracticeChars', practiceChars);
    await _genChannel.invokeMethod('setBoostLevel', boostLevel);
    // Sidetone pitch/envelope: this screen never set these before, so they
    // were left at whatever the CW Keyer screen (or nothing) last configured.
    final pitch = p2.getInt('pitch') ?? 600;
    final toneSoftness = (p2.getInt('toneSoftness') ?? 4).clamp(0, 8);
    await _toneChannel.invokeMethod('setFreq', pitch);
    await _toneChannel.invokeMethod('setEnvelopeMs', (toneSoftness + 1).toDouble());
    await _loadKochWeakChars();
  }

  Future<void> _loadKochWeakChars() async {
    if (!widget.kochMode) return;
    final p = await SharedPreferences.getInstance();
    await _charStats.load(p);
    if (!mounted) return;
    setState(() {
      _kochWeakChars = weakCharsLifetime(_charStats, kochActiveChars(_kochLevel, _activeKochChars));
      _excludedKochBoostChars.removeWhere((ch) => !_kochWeakChars.containsKey(ch));
    });
  }

  Future<void> _savePrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('wpm',       _wpm);
    await p.setInt('kochLevel', _kochLevel);
    await p.setInt('kochModeIndex', _kochModeIndex);
    await p.setInt('kochFlow', _flow);
    // Only ever change here via AdaptiveCopyBody's onSpacingChanged, but
    // still worth persisting so the Settings screen reflects the adapted
    // value too (interCharSpace/interWordSpace are shared, global keys).
    await p.setInt('interCharSpace', _interCharSpace);
    await p.setInt('interWordSpace', _interWordSpace);
  }

  @override
  void dispose() {
    KeepScreenOn.disable();
    _stop();
    _logScroll.dispose();
    // The Koch weak-chars panel pushes practiceChars/boostLevel to the
    // shared generator singleton on Start (CLAUDE.md rule: nothing re-syncs
    // this automatically). Restore the Settings-persisted values on the way
    // out so leaving this screen doesn't leave Echo Trainer's "Adapt. Rand."
    // boosting our leftover weak-char set.
    _restorePracticeCharsAndBoost();
    super.dispose();
  }

  Future<void> _restorePracticeCharsAndBoost() async {
    final p = await SharedPreferences.getInstance();
    final practiceChars = parsePracticeChars(p.getString('practiceChars') ?? '');
    final boostLevel = (p.getInt('boostLevel') ?? 0).clamp(0, 2);
    await _genChannel.invokeMethod('setPracticeChars', practiceChars);
    await _genChannel.invokeMethod('setBoostLevel', boostLevel);
  }

  Future<void> _start() async {
    if (_running) return;   // guard against a double-tap racing two sessions
    _sub = _genEvents.receiveBroadcastStream().listen(_onEvent);
    // Keep the scrolling log across Start presses — like the real device, a new
    // sequence just continues underneath what was already practiced, it doesn't
    // wipe it. Only navigating away (dispose) or truncation (_appendText's cap)
    // clears it.
    if (mounted) setState(() { _running = true; _waiting = false; _pendingWord = ''; _preparing = true; });

    if (widget.kochMode) {
      // Weak-char boost from the start-screen panel, minus whatever the
      // user tapped out — reuses the same practiceChars/boostLevel
      // mechanism as CW Generator's "Practice Set" + Boost.
      final boostChars = _kochWeakChars.keys
          .where((ch) => !_excludedKochBoostChars.contains(ch))
          .toList();
      await _genChannel.invokeMethod('setPracticeChars', boostChars);
      await _genChannel.invokeMethod('setBoostLevel', boostChars.isEmpty ? 0 : 2);
    }

    // Brief pause so the user can get ready before anything actually plays.
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted || !_running) return;
    setState(() => _preparing = false);

    // Sync playback speed/spacing BEFORE the marker plays — otherwise it
    // plays with whatever the native generator was left at (its own
    // defaults, on the very first session this app run) instead of the
    // currently configured values, since only the 'start' call further below
    // would otherwise update them.
    await _genChannel.invokeMethod('setWpm', _wpm);
    await _genChannel.invokeMethod('setInterCharSpace', _interCharSpace);
    await _genChannel.invokeMethod('setInterWordSpace', _interWordSpace);
    if (mounted && _log.isNotEmpty) setState(() => _appendText(' '));   // gap from the previous session's last char

    // Starting signal, sent at the start of every fresh session (m32_v6.ino:
    // clearText = "vvvA"; frameWordForDisplay = true). Audio: V V V <KA>. The
    // ON-SCREEN text is NOT the raw "vvvA" — dispGeneratedChar() runs every
    // character through cleanUpProSigns() before display (m32_v6.ino:2686),
    // which expands the single-char prosign code 'A' to "<ka>" (see the table
    // in cleanUpProSigns() and the "vvv<ka>" opener mentioned in its own
    // comment at m32_v6.ino:2707) — so the real device shows "vvv<ka>",
    // revealed character-by-character as it plays (same as regular content —
    // _onEvent appends each 'char' event live while _awaitingSignal), not
    // all at once after the whole marker finishes.
    await _playSignal('VVVKA');
    if (!mounted || !_running) return;   // stopped while the start signal played

    // The real device leaves a full InterWord-Space gap between the marker
    // and the first generated word. playOne() plays the marker with
    // trailingGap=false (so Echo Trainer doesn't force an artificial wait
    // before the operator can answer), which otherwise leaves zero gap here.
    await Future.delayed(Duration(milliseconds: _ditMs() * _interWordSpace));
    if (!mounted || !_running) return;

    await _genChannel.invokeMethod('start', {
      'wpm':            _wpm,
      'kochLevel':      _kochLevel,
      'mode':           widget.kochMode ? _kochModeOrdinals[_kochModeIndex] : _modeIndex,
      'kochActive':     widget.kochMode,
      'interCharSpace': _interCharSpace,
      'interWordSpace': _interWordSpace,
      'eachWordTwice':  _eachWordTwice,
      'groupLength':    _groupLength,
      'randomOption':   _randomOption,
      'wordLengthMax':  _wordLengthMax,
      'stopAfterItem':  _stopAfterItem,
      'abbrevLengthMax': _abbrevLengthMax,
      'maxWords':        _maxWords,
      'callLengthOpt':   _callLengthOpt,
      'callRegionOpt':   _callRegionOpt,
      'callCommonOnly':  _callCommonOnly,
    });
  }

  Future<void> _stop() async {
    await _genChannel.invokeMethod('stop');
    _sub?.cancel();
    _sub = null;
    if (_awaitingSignal) {
      _awaitingSignal = false;
      _signalDone?.complete();
    }
    if (mounted) setState(() { _running = false; _waiting = false; _preparing = false; });
  }

  /// Plays a marker string (start "VVVKA" / end "+") via the native playOne()
  /// and waits for its genuine completion — the method-channel call itself
  /// returns immediately since Kotlin just spawns a playback thread.
  Future<void> _playSignal(String morse) async {
    final completer = Completer<void>();
    _signalDone = completer;
    _awaitingSignal = true;
    await _genChannel.invokeMethod('playOne', morse);
    await completer.future;
    _awaitingSignal = false;
  }

  /// End signal, sent when "Max # of Words" is reached (m32_v6.ino: "+",
  /// i.e. <ar>, with frameWordForDisplay = true) — not sent on manual Stop.
  Future<void> _playEndSignal() async {
    if (mounted && _log.isNotEmpty) setState(() => _appendText(' '));   // gap from the last generated char
    await _playSignal('+');   // its 'char' event appends the '+' itself, see _onEvent
  }

  // Back button while a block/session is active: return to this screen's
  // own setup/start state rather than leaving the screen (see PopScope in
  // build()). Classic and the non-Koch generator just stop the running
  // session (there's no separate "setup screen" for them — it's the same
  // screen with controls shown again); the Adaptiv flow has its own idle
  // phase, reset via the controller.
  Future<void> _exitPracticeToSetup() async {
    if (_running) {
      await _stop();
    } else if (widget.kochMode && _flow == 1 && _adaptiveActive) {
      _adaptiveController.resetToIdle();
    }
  }

  int _ditMs() => (1200 / _wpm).round();

  Future<void> _choosePaddle(bool repeat) async {
    await _genChannel.invokeMethod('choosePaddle', repeat);
    if (mounted) setState(() => _waiting = false);
  }

  // ── Koch Trainer: Learn New Chr / Preview Char (mirrors real device: both
  // drill one fixed character repeatedly via the Echo Trainer engine — see
  // Koch::getNewChar()/getKochChar()) ─────────────────────────────────────

  void _openLearnNewChar() {
    final newest = _activeKochChars[(_kochLevel - 1).clamp(0, _activeKochChars.length - 1)];
    Navigator.push(context, MaterialPageRoute(builder: (_) => EchoTrainerScreen(
      fixedTarget: newest, title: Strings.t('gen_new_char_title').replaceFirst('{ch}', newest),
    )));
  }

  // Koch Trainer's own Echo Trainer branch (MorseMenu.cpp: "Koch Trainer >
  // Echo Trainer" — Random/CW Abbrevs/English Words/Mixed/Adapt. Rand.,
  // distinct from the standalone top-level "Echo Trainer").
  void _openKochEcho() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const EchoTrainerScreen(
      kochMode: true, title: 'Koch Trainer: Echo',
    )));
  }

  Future<void> _openPreviewChar() async {
    final c = AppColors.of(context);
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: c.surface,
      builder: (_) => _PreviewCharSheet(sequence: _activeKochChars, currentLevel: _kochLevel, outputCase: _outputCase),
    );
    if (picked != null && mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => EchoTrainerScreen(
        fixedTarget: picked, title: Strings.t('gen_preview_char_title').replaceFirst('{ch}', picked),
      )));
    }
  }

  // No length cap: the log is scrollable now, and the user wants the whole
  // session's practice history reachable by scrolling back — it only clears
  // on dispose (navigating away), same as before.
  void _appendText(String text, {bool bold = false}) {
    if (text.isEmpty) return;
    if (_log.isNotEmpty && _log.last.bold == bold) {
      _log.last.text += text;
    } else {
      _log.add(_LogSpan(text, bold: bold));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_stickToBottom || !_logScroll.hasClients) return;
      _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
    });
  }

  void _onEvent(dynamic raw) {
    final ev = raw as Map;
    final type  = ev['type'] as String;
    final value = ev['value'] as String;
    if (_awaitingSignal) {
      // This event belongs to a start/end marker's playOne(), not the main
      // generator. Reveal each character as it plays — same char-by-char
      // timing as regular content — translating the KA prosign token to its
      // display form; 'word'/'waiting' carry no display text of their own
      // and are swallowed, and 'done' resolves the marker's completer.
      if (type == 'char' && mounted) {
        setState(() => _appendText(value == 'KA' ? '<ka>' : value.toLowerCase(), bold: true));
      } else if (type == 'done') {
        _signalDone?.complete();
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      switch (type) {
        case 'word':
          // A new word is starting — the PREVIOUS one (if any) just finished.
          if (_genDisplay == 2 && _pendingWord.isNotEmpty) _appendText(_pendingWord);
          if (_genDisplay == 1 && _log.isNotEmpty) _appendText(' ');
          _pendingWord = value;
          _waiting = false;
        case 'char':
          // Fires only after the character has actually finished playing.
          if (_genDisplay == 1) _appendText(value);
        case 'waiting':
          _waiting = true;
        case 'done':
          if (_genDisplay == 2 && _pendingWord.isNotEmpty) {
            _appendText(_pendingWord);
            _pendingWord = '';
          }
          _running = false;
          _waiting = false;
          if (value == 'maxWords') _playEndSignal();
      }
    });
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final title = widget.kochMode ? 'Koch Trainer' : 'CW Generator';
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
      ),
      body: Column(
        children: [
          // ── Classic / Adaptiv flow toggle (Koch Trainer only for now —
          // see docs/ADAPTIVE-COPY.md) — orthogonal to the content-mode
          // selector below, not a replacement for it. Hidden while a
          // block/session is running — it won't be changed mid-practice
          // anyway (docs/STATUS.md "Koch Trainer setup-screen decluttering").
          if (widget.kochMode && !_practiceActive)
            _FlowToggle(
              selected: _flow,
              onChanged: (f) {
                if (_running) _stop();
                setState(() => _flow = f);
                _savePrefs();
              },
            ),

          // ── Practice area: Classic's sent-text log, or the Adaptiv
          // send→reveal→mark→result flow ──────────────────────────────────
          // Keyed: siblings above/below (FlowToggle, Koch tool buttons row)
          // appear/disappear together with _practiceActive, which shifts
          // this Expanded's position in the Column's children list. Without
          // a stable key, Flutter's list-diffing can't match it to its old
          // Element in that case and remounts it from scratch — silently
          // resetting AdaptiveCopyBody's _phase back to idle mid-block (the
          // "must press Start Block twice" bug).
          Expanded(
            key: const ValueKey('koch_practice_area'),
            child: (widget.kochMode && _flow == 1)
                ? AdaptiveCopyBody(
                    kochLevel: _kochLevel,
                    activeKochChars: _activeKochChars,
                    contentModeIndex: _kochModeIndex,
                    contentModeOrdinals: _kochModeOrdinals,
                    contentModeLabels: _kochModeLabels,
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
                  )
                : PinchZoomFontSize(
                    prefsKey: 'genLogFontSize',
                    builder: (context, fontSize) => Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: c.border),
                      ),
                      child: _buildTextDisplay(fontSize),
                    ),
                  ),
          ),

          // ── Controls (shared by Classic and Adaptiv) ─────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(children: [
              _SliderRow(
                label: 'WPM', value: _wpm.toDouble(),
                min: 5, max: 60, divisions: 55,
                onChanged: (v) {
                  setState(() => _wpm = v.round());
                  _savePrefs();
                  if (_running) {
                    _stop().then((_) => _start());
                  }
                },
              ),
              if (widget.kochMode)
                _SliderRow(
                  label: 'KOCH', value: _kochLevel.toDouble(),
                  min: 2, max: _activeKochChars.length.toDouble(),
                  divisions: _activeKochChars.length - 2,
                  onChanged: (v) { setState(() => _kochLevel = v.round()); _savePrefs(); },
                ),
              // Content mode selector — won't be changed mid-practice, so
              // hidden while a block/session is running (see _FlowToggle
              // comment above).
              if (!_practiceActive)
                if (widget.kochMode)
                  _ModeSelector(
                    selected: _kochModeIndex,
                    labels: _kochModeLabels,
                    onChanged: (i) { setState(() => _kochModeIndex = i); _savePrefs(); },
                  )
                else
                  _ModeSelector(
                    selected: _modeIndex,
                    onChanged: (i) => setState(() => _modeIndex = i),
                  ),
            ]),
          ),

          if (widget.kochMode)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _KochCharsRow(level: _kochLevel, sequence: _activeKochChars, outputCase: _outputCase),
            ),

          // ── Koch Trainer: Learn New Chr / Preview Char ──────────────────
          if (widget.kochMode && !_practiceActive)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(children: [
                Expanded(child: _KochToolButton(
                  icon: Icons.fiber_new, label: Strings.t('gen_learn_new'),
                  onTap: _openLearnNewChar,
                )),
                const SizedBox(width: 12),
                Expanded(child: _KochToolButton(
                  icon: Icons.hearing, label: Strings.t('gen_preview'),
                  onTap: _openPreviewChar,
                )),
                const SizedBox(width: 12),
                Expanded(child: _KochToolButton(
                  icon: Icons.repeat, label: Strings.t('gen_practice_echo'),
                  onTap: _openKochEcho,
                )),
              ]),
            ),

          // ── Repeat / Next paddle choice (Stop<Next>Rep, mirrors real M32) ──
          // Reserved space stays fixed whenever the mode is on, so the text
          // display above doesn't jump in size when the buttons enable/disable.
          // Classic-only: the Adaptiv flow has its own buttons per phase.
          if (!(widget.kochMode && _flow == 1)) ...[
            if (_stopAfterItem)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(children: [
                  Expanded(child: _ChoiceButton(
                    label: '◀ ${Strings.t('repeat_upper')}', sub: 'Dit',
                    color: c.warning,
                    enabled: _waiting,
                    onTap: () => _choosePaddle(true),
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: _ChoiceButton(
                    label: '${Strings.t('next_upper')} ▶', sub: 'Dah',
                    color: c.info,
                    enabled: _waiting,
                    onTap: () => _choosePaddle(false),
                  )),
                ]),
              ),

            // ── Start / Stop button ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _running
                        ? c.danger.withOpacity(0.2)
                        : c.accent.withOpacity(0.2),
                    foregroundColor: _running
                        ? c.danger
                        : c.accent,
                    side: BorderSide(
                      color: _running ? c.danger : c.accent,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _running ? _stop : _start,
                  child: Text(
                      _running ? (_preparing ? Strings.t('get_ready') : '■  STOP') : '▶  START',
                      style: const TextStyle(fontFamily: 'CwMono', fontSize: 18,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ],
      ),
      ),
      ),
    );
  }

  Widget _buildTextDisplay(double fontSize) {
    final c = AppColors.of(context);
    // 0 = Display off
    if (_genDisplay == 0 && _running) {
      return Align(alignment: Alignment.center, child: Text('· · · · ·',
          style: TextStyle(fontFamily: 'CwMono', fontSize: 32,
              color: c.textDisabled, letterSpacing: 8)));
    }

    // Koch Trainer's start screen: nothing sent yet this session, so the
    // (empty) output log isn't useful here — show the weak-characters
    // panel instead, letting the user steer the boost before pressing
    // Start (docs/STATUS.md "Koch Trainer setup-screen decluttering").
    if (widget.kochMode && !_running && _log.isEmpty) {
      return _buildKochWeakCharsPanel(c);
    }

    // 1 = Char by char, 2 = Word by word: both reveal into the same scrolling
    // log, just at different granularity/timing (handled in _onEvent) — never
    // highlighted or shown while still being sent.
    if (_log.isEmpty) {
      return Align(alignment: Alignment.bottomLeft, child: Text(Strings.t('press_start'),
          style: TextStyle(fontFamily: 'CwMono', fontSize: 20,
              color: c.textDisabled, fontStyle: FontStyle.italic)));
    }
    // Output Case ("posOutputCase") is display-only — content stays uppercase
    // internally, the transform is applied here at render time. The start/end
    // markers get a distinct color (not just bold) so they stand out from the
    // practiced content; regular characters are colored by type (letter/
    // digit/other) so mixed content is easier to scan.
    return Scrollbar(
      controller: _logScroll,
      child: SingleChildScrollView(
        controller: _logScroll,
        padding: const EdgeInsets.only(bottom: 2),
        child: RichText(
          text: TextSpan(children: _log.expand((span) {
            final text = _outputCase == 1 ? span.text.toUpperCase() : span.text.toLowerCase();
            if (span.bold) {
              return [TextSpan(text: text, style: TextStyle(
                  fontFamily: 'CwMono', fontSize: fontSize, height: 1.5,
                  color: c.warning, fontWeight: FontWeight.bold))];
            }
            return text.split('').map((ch) => TextSpan(text: ch, style: TextStyle(
                fontFamily: 'CwMono', fontSize: fontSize, height: 1.5,
                color: charTypeColor(ch, c))));
          }).toList()),
        ),
      ),
    );
  }

  // Tap-to-exclude weak-characters panel shown on the Koch Trainer's start
  // screen in place of the (empty) output log — mirrors AdaptiveCopyBody's
  // result-screen chips (docs/ADAPTIVE-COPY.md).
  Widget _buildKochWeakCharsPanel(AppColors c) {
    if (_kochWeakChars.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(Strings.t('press_start'),
              style: TextStyle(fontFamily: 'CwMono', fontSize: 20,
                  color: c.textMuted, fontStyle: FontStyle.italic)),
          const SizedBox(height: 10),
          _buildGenStatusLine(c),
        ]),
      );
    }
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _buildGenStatusLine(c),
        const SizedBox(height: 16),
        Text(Strings.t('ac_weak_chars'),
            style: TextStyle(fontFamily: 'CwMono', fontSize: 14,
                fontWeight: FontWeight.bold, color: c.textMuted)),
        const SizedBox(height: 2),
        Text(Strings.t('gen_boost_hint'),
            style: TextStyle(fontFamily: 'CwMono', fontSize: 13,
                color: c.textMuted, fontStyle: FontStyle.italic),
            textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center,
          children: _kochWeakChars.entries.map((e) {
            final included = !_excludedKochBoostChars.contains(e.key);
            return InkWell(
              onTap: () => setState(() {
                if (included) {
                  _excludedKochBoostChars.add(e.key);
                } else {
                  _excludedKochBoostChars.remove(e.key);
                }
              }),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: included ? c.danger.withOpacity(0.1) : c.surfaceAlt,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: included ? c.danger.withOpacity(0.4) : c.border),
                ),
                child: Text('${_displayChar(e.key)}  ${(e.value * 100).round()}%',
                    style: TextStyle(fontFamily: 'CwMono', fontSize: 16,
                        color: included ? c.danger : c.textMuted,
                        decoration: included ? null : TextDecoration.lineThrough)),
              ),
            );
          }).toList(),
        ),
      ]),
    );
  }

  // Same status-line format as AdaptiveCopyBody's result screen (see
  // gen_status_line), shown here too so WPM/spacing read the same way
  // whether you're looking at the start screen or a finished block.
  Widget _buildGenStatusLine(AppColors c) {
    return Text(Strings.t('gen_status_line')
            .replaceFirst('{wpm}', '$_wpm')
            .replaceFirst('{ewpm}', '$_effectiveTextWpm')
            .replaceFirst('{ic}', '$_interCharSpace')
            .replaceFirst('{iw}', '$_interWordSpace'),
        style: TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.textMuted));
  }
}

class _LogSpan {
  String text;
  final bool bold;
  _LogSpan(this.text, {this.bold = false});
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _KochToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _KochToolButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final color = c.warning;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: color)),
        ]),
      ),
    );
  }
}

class _PreviewCharSheet extends StatelessWidget {
  final List<String> sequence;
  final int currentLevel;
  // 0=lower, 1=UPPER — display only, matches the screen's outputCase setting.
  final int outputCase;
  const _PreviewCharSheet({required this.sequence, required this.currentLevel, this.outputCase = 1});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(Strings.t('gen_preview_chars_title'),
              style: TextStyle(fontFamily: 'CwMono', fontSize: 15,
                  fontWeight: FontWeight.bold, color: c.textPrimary)),
          const SizedBox(height: 4),
          Text(Strings.t('gen_preview_chars_desc'),
              style: TextStyle(fontFamily: 'CwMono', fontSize: 11, color: c.textMuted)),
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: SingleChildScrollView(
              child: Wrap(spacing: 8, runSpacing: 8, children: List.generate(sequence.length, (i) {
                final learned = i < currentLevel;
                final color = learned ? c.accent : c.textMutedAlt;
                return InkWell(
                  onTap: () => Navigator.pop(context, sequence[i]),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 40, height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: color.withOpacity(0.4)),
                    ),
                    child: Text(outputCase == 1 ? sequence[i].toUpperCase() : sequence[i].toLowerCase(),
                        style: TextStyle(fontFamily: 'CwMono',
                        fontSize: 15, fontWeight: FontWeight.bold, color: color)),
                  ),
                );
              })),
            ),
          ),
        ]),
      ),
    );
  }
}

class _KochCharsRow extends StatelessWidget {
  final int level;
  final List<String> sequence;
  // 0=lower, 1=UPPER — display only, matches the screen's outputCase setting.
  final int outputCase;
  const _KochCharsRow({required this.level, required this.sequence, this.outputCase = 1});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final active = kochActiveChars(level, sequence);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 6,
        children: active.map((ch) => Text(outputCase == 1 ? ch.toUpperCase() : ch.toLowerCase(),
            style: TextStyle(
                fontFamily: 'CwMono', fontSize: 13,
                color: charTypeColor(ch, c)))).toList(),
      ),
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  final String label, sub;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;
  const _ChoiceButton({required this.label, required this.sub,
      required this.color, required this.onTap, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final c = enabled ? color : colors.textDisabled;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: c.withOpacity(enabled ? 0.12 : 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.withOpacity(enabled ? 0.5 : 0.25)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(fontFamily: 'CwMono', fontSize: 13,
              fontWeight: FontWeight.bold, color: c)),
          const SizedBox(height: 2),
          Text(sub, style: TextStyle(fontFamily: 'CwMono', fontSize: 10,
              color: c.withOpacity(0.7))),
        ]),
      ),
    );
  }
}

class _FlowToggle extends StatelessWidget {
  final int selected;   // 0=Classic, 1=Adaptiv
  final ValueChanged<int> onChanged;
  const _FlowToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final labels = [Strings.t('flow_classic'), Strings.t('flow_adaptiv')];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(children: List.generate(labels.length, (i) {
        final active = i == selected;
        return Expanded(child: Padding(
          padding: EdgeInsets.only(right: i == 0 ? 6 : 0, left: i == 1 ? 6 : 0),
          child: GestureDetector(
            onTap: () => onChanged(i),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: active ? c.accentPurple.withOpacity(0.15) : c.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: active ? c.accentPurple : c.border),
              ),
              child: Text(labels[i], textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'CwMono', fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: active ? c.accentPurple : c.textMuted)),
            ),
          ),
        ));
      })),
    );
  }
}

class _ModeSelector extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;
  final List<String>? labels;
  const _ModeSelector({required this.selected, required this.onChanged, this.labels});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final effectiveLabels = labels ?? genModeNames();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(builder: (context, constraints) {
        const perRow = 3;
        const gap = 6.0;
        final itemWidth = (constraints.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap, runSpacing: gap,
          children: List.generate(effectiveLabels.length, (i) {
            final active = i == selected;
            return SizedBox(width: itemWidth, child: GestureDetector(
              onTap: () => onChanged(i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: active
                      ? c.accent.withOpacity(0.15)
                      : c.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: active
                        ? c.accent
                        : c.border,
                  ),
                ),
                child: Text(effectiveLabels[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontFamily: 'CwMono', fontSize: 10,
                        color: active
                            ? c.accent
                            : c.textMuted)),
              ),
            ));
          }),
        );
      }),
    );
  }
}

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

extension on String {
  String take(int n) => length <= n ? this : substring(length - n);
}
