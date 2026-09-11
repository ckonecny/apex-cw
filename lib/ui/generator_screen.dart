import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../keyer/morse_decoder.dart';
import '../content/cw_content.dart';
import 'echo_trainer_screen.dart';
import '../theme/app_colors.dart';
import '../util/keep_screen_on.dart';
import 'widgets/pinch_zoom_text.dart';

class GeneratorScreen extends StatefulWidget {
  final bool kochMode;  // true = Koch Trainer, false = CW Generator
  const GeneratorScreen({super.key, this.kochMode = false});

  @override
  State<GeneratorScreen> createState() => _GeneratorScreenState();
}

class _GeneratorScreenState extends State<GeneratorScreen> {
  static const _genChannel = MethodChannel('at.oe1wkl.morserino_mobile/cw_generator');
  static const _genEvents  = EventChannel('at.oe1wkl.morserino_mobile/cw_gen_events');
  static const _toneChannel = MethodChannel('at.oe1wkl.morserino_mobile/cw_tone');

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
  static const _kochModeLabels = ['Zufall', 'Abkürzungen', 'Wörter', 'Gemischt'];
  int  _kochModeIndex = 0;
  int  _outputCase = 0;   // 0=lower, 1=UPPER — display only, content stays uppercase internally
  // 0=Display off, 1=Char by char, 2=Word by word (matches M32 "CW Gen Displ")
  int  _genDisplay     = 1;
  bool _stopAfterItem  = false;
  bool _eachWordTwice  = false;
  int  _wordLengthMax  = 0;
  int  _groupLength    = 5;
  int  _abbrevLengthMax = 0;
  int  _maxWords        = 0;
  int  _callLengthOpt   = 0;
  int  _callRegionOpt   = 0;
  bool _callCommonOnly  = true;
  int  _interCharSpace = 3;
  int  _interWordSpace = 7;
  int    _kochSeq         = 0;
  String _customKochChars = '';
  List<String> get _activeKochChars => kochSequenceChars(_kochSeq, _customKochChars);

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
      _outputCase     = (p.getInt('outputCase')     ?? 0).clamp(0, 1);
      _stopAfterItem  = p.getBool('stopAfterItem') ?? false;
      _eachWordTwice  = p.getBool('eachWordTwice') ?? false;
      _wordLengthMax  = p.getInt('wordLengthMax')  ?? 0;
      _groupLength    = p.getInt('groupLength')    ?? 5;
      _abbrevLengthMax = (p.getInt('abbrevLengthMax') ?? 0).clamp(0, 5);
      _maxWords        = p.getInt('maxWords')        ?? 0;
      _callLengthOpt   = (p.getInt('callLengthOpt') ?? 0).clamp(0, 4);
      _callRegionOpt   = (p.getInt('callRegionOpt') ?? 0).clamp(0, 7);
      _callCommonOnly  = p.getBool('callCommonOnly') ?? true;
      _interCharSpace = (p.getInt('interCharSpace') ?? 3).clamp(3, 45);
      _interWordSpace = (p.getInt('interWordSpace') ?? 7).clamp(6, 105);
      _kochSeq         = (p.getInt('kochSeq') ?? 0).clamp(0, 4);
      _customKochChars = p.getString('customKochChars') ?? '';
      _kochLevel = _kochLevel.clamp(2, _activeKochChars.length);
    });
    _genChannel.invokeMethod('setKochChars', _activeKochChars);
    final p2 = await SharedPreferences.getInstance();
    final practiceChars = parsePracticeChars(p2.getString('practiceChars') ?? '');
    final boostLevel    = (p2.getInt('boostLevel') ?? 0).clamp(0, 2);
    await _genChannel.invokeMethod('setPracticeChars', practiceChars);
    await _genChannel.invokeMethod('setBoostLevel', boostLevel);
  }

  Future<void> _savePrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('wpm',       _wpm);
    await p.setInt('kochLevel', _kochLevel);
    await p.setInt('kochModeIndex', _kochModeIndex);
  }

  @override
  void dispose() {
    KeepScreenOn.disable();
    _stop();
    _logScroll.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_running) return;   // guard against a double-tap racing two sessions
    _sub = _genEvents.receiveBroadcastStream().listen(_onEvent);
    // Keep the scrolling log across Start presses — like the real device, a new
    // sequence just continues underneath what was already practiced, it doesn't
    // wipe it. Only navigating away (dispose) or truncation (_appendText's cap)
    // clears it.
    if (mounted) setState(() { _running = true; _waiting = false; _pendingWord = ''; });

    // Starting signal, sent at the start of every fresh session (m32_v6.ino:
    // clearText = "vvvA"; frameWordForDisplay = true). Audio: V V V <KA>. The
    // ON-SCREEN text is NOT the raw "vvvA" — dispGeneratedChar() runs every
    // character through cleanUpProSigns() before display (m32_v6.ino:2686),
    // which expands the single-char prosign code 'A' to "<ka>" (see the table
    // in cleanUpProSigns() and the "vvv<ka>" opener mentioned in its own
    // comment at m32_v6.ino:2707) — so the real device shows "vvv<ka>".
    await _playSignal('VVVKA');
    if (!mounted || !_running) return;   // stopped while the start signal played
    setState(() {
      if (_log.isNotEmpty) _appendText(' ');   // gap from the previous session's last char
      _appendText('vvv<ka>', bold: true);
    });

    await _genChannel.invokeMethod('start', {
      'wpm':            _wpm,
      'kochLevel':      _kochLevel,
      'mode':           widget.kochMode ? _kochModeOrdinals[_kochModeIndex] : _modeIndex,
      'kochActive':     widget.kochMode,
      'interCharSpace': _interCharSpace,
      'interWordSpace': _interWordSpace,
      'eachWordTwice':  _eachWordTwice,
      'groupLength':    _groupLength,
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
    if (mounted) setState(() { _running = false; _waiting = false; });
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
    await _playSignal('+');
    if (mounted) setState(() {
      if (_log.isNotEmpty) _appendText(' ');   // gap from the last generated char
      _appendText('+', bold: true);
    });
  }

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
      fixedTarget: newest, title: 'Neu: $newest',
    )));
  }

  Future<void> _openPreviewChar() async {
    final c = AppColors.of(context);
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: c.surface,
      builder: (_) => _PreviewCharSheet(sequence: _activeKochChars, currentLevel: _kochLevel),
    );
    if (picked != null && mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => EchoTrainerScreen(
        fixedTarget: picked, title: 'Vorhören: $picked',
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
      // generator — swallow it; the marker text is appended explicitly.
      if (type == 'done') _signalDone?.complete();
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
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.surface,
        title: Text(title,
            style: TextStyle(fontFamily: 'CwMono', fontSize: 16,
                color: c.textPrimary)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.textMuted),
          onPressed: () { _stop(); Navigator.pop(context); },
        ),
      ),
      body: Column(
        children: [
          // ── Sent text display ──────────────────────────────────────────
          Expanded(
            child: PinchZoomFontSize(
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

          // ── Controls ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
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

          if (widget.kochMode) _KochCharsRow(level: _kochLevel, sequence: _activeKochChars),

          // ── Koch Trainer: Learn New Chr / Preview Char ──────────────────
          if (widget.kochMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(children: [
                Expanded(child: _KochToolButton(
                  icon: Icons.fiber_new, label: 'Neu lernen',
                  onTap: _openLearnNewChar,
                )),
                const SizedBox(width: 12),
                Expanded(child: _KochToolButton(
                  icon: Icons.hearing, label: 'Vorhören',
                  onTap: _openPreviewChar,
                )),
              ]),
            ),

          // ── Repeat / Next paddle choice (Stop<Next>Rep, mirrors real M32) ──
          // Reserved space stays fixed whenever the mode is on, so the text
          // display above doesn't jump in size when the buttons enable/disable.
          if (_stopAfterItem)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(children: [
                Expanded(child: _ChoiceButton(
                  label: '◀ WIEDERHOLEN', sub: 'Dit',
                  color: c.warning,
                  enabled: _waiting,
                  onTap: () => _choosePaddle(true),
                )),
                const SizedBox(width: 12),
                Expanded(child: _ChoiceButton(
                  label: 'WEITER ▶', sub: 'Dah',
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
                child: Text(_running ? '■  STOP' : '▶  START',
                    style: const TextStyle(fontFamily: 'CwMono', fontSize: 18,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
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

    // 1 = Char by char, 2 = Word by word: both reveal into the same scrolling
    // log, just at different granularity/timing (handled in _onEvent) — never
    // highlighted or shown while still being sent.
    if (_log.isEmpty) {
      return Align(alignment: Alignment.bottomLeft, child: Text('▶ START drücken',
          style: TextStyle(fontFamily: 'CwMono', fontSize: 20,
              color: c.textDisabled, fontStyle: FontStyle.italic)));
    }
    // Output Case ("posOutputCase") is display-only — content stays uppercase
    // internally, the transform is applied here at render time. The start/end
    // markers get a distinct color (not just bold) so they stand out from the
    // practiced content, which frameWordForDisplay's bold-only weight on the
    // real device's OLED/TFT can't do on our screen's richer palette.
    return Scrollbar(
      controller: _logScroll,
      child: SingleChildScrollView(
        controller: _logScroll,
        padding: const EdgeInsets.only(bottom: 2),
        child: RichText(
          text: TextSpan(children: _log.map((span) {
            final text = _outputCase == 1 ? span.text.toUpperCase() : span.text.toLowerCase();
            return TextSpan(text: text, style: TextStyle(
                fontFamily: 'CwMono', fontSize: fontSize, height: 1.5,
                color: span.bold ? c.warning : c.accent,
                fontWeight: span.bold ? FontWeight.bold : FontWeight.normal));
          }).toList()),
        ),
      ),
    );
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
  const _PreviewCharSheet({required this.sequence, required this.currentLevel});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Zeichen vorhören',
              style: TextStyle(fontFamily: 'CwMono', fontSize: 15,
                  fontWeight: FontWeight.bold, color: c.textPrimary)),
          const SizedBox(height: 4),
          Text('Ganze Kurs-Sequenz — auch noch nicht gelernte Zeichen',
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
                    child: Text(sequence[i], style: TextStyle(fontFamily: 'CwMono',
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
  const _KochCharsRow({required this.level, required this.sequence});

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
        children: active.map((ch) => Text(ch,
            style: TextStyle(
                fontFamily: 'CwMono', fontSize: 13,
                color: c.accent))).toList(),
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

class _ModeSelector extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;
  final List<String> labels;
  const _ModeSelector({required this.selected, required this.onChanged,
      this.labels = genModeNames});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(builder: (context, constraints) {
        const perRow = 3;
        const gap = 6.0;
        final itemWidth = (constraints.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap, runSpacing: gap,
          children: List.generate(labels.length, (i) {
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
                child: Text(labels[i],
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
