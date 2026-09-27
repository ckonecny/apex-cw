import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/paddle_widgets.dart';
import '../content/qso_bot.dart';
import '../content/training_profile.dart';
import '../keyer/morse_decoder.dart';
import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import 'widgets/app_ui.dart';
import 'widgets/setting_rows.dart';
import 'widgets/training_settings_sheet.dart';
import '../util/keep_screen_on.dart';

/// QSO Bot: a simulated CW QSO partner (firmware MorseQsoBot, V9.0). Same
/// frontend as WiFi Trx: the bot's overs are RX, your keying is TX. Uses the
/// CW Keyer's word gap, like the firmware (global interWordSpace).
class QsoBotScreen extends StatefulWidget {
  const QsoBotScreen({super.key});

  @override
  State<QsoBotScreen> createState() => _QsoBotScreenState();
}

enum _SegKind { rx, tx, info }

class _Seg {
  final _SegKind kind;
  String text;
  _Seg(this.kind, this.text);
}

class _QsoBotScreenState extends State<QsoBotScreen> with WidgetsBindingObserver {
  static const _toneChannel  = MethodChannel('at.oe1cko.nextcwtrainer/cw_tone');
  static const _keyerChannel = MethodChannel('at.oe1cko.nextcwtrainer/cw_keyer');
  static const _genChannel   = MethodChannel('at.oe1cko.nextcwtrainer/cw_generator');
  static const _symbolStream = EventChannel('at.oe1cko.nextcwtrainer/cw_symbols');
  static const _genEvents    = EventChannel('at.oe1cko.nextcwtrainer/cw_gen_events');

  StreamSubscription? _symSub, _genSub;
  late final MorseDecoder _decoder;
  final _textCtl = TextEditingController();
  final _scroll  = ScrollController();
  final _rnd = Random();

  bool _ready = false;
  int _wpm = 20;
  int _keyerMode = 0;
  int _outputCase = 0;
  int _interWord = 7;
  int _type = 0;            // QsoType index
  int _level = 1;           // QsoLevel index (firmware default Intermediate)
  int _contestType = 0;     // 0 = CQ WW, 1 = WPX/Sprint
  String _myCall = '';
  int _callRegion = 0;
  bool _callCommon = true;
  bool _touchDit = false, _touchDah = false;

  final List<_Seg> _log = [];
  QsoBot? _bot;
  Timer? _tickTimer, _playGuard;
  String _status = '';

  // Bot playback display: one token (letter or <xx>) per played character,
  // like the firmware's emitNextBotChar().
  List<String> _txTokens = [];
  int _txPos = 0;
  bool _botPlaying = false;

  final List<QsoCall> _callPool = [];
  bool _refilling = false;

  bool get _running => _bot != null && _bot!.phase != QsoPhase.done;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    KeepScreenOn.enable();
    _decoder = MorseDecoder(onChar: _onDecodedChar, unknown: '*');
    _symSub = _symbolStream.receiveBroadcastStream().listen((s) => _decoder.add(s as String));
    _genSub = _genEvents.receiveBroadcastStream().listen(_onGenEvent);
    _init();
  }

  Future<void> _init() async {
    final p = await SharedPreferences.getInstance();
    _keyerMode   = p.getInt('keyerMode') ?? 0;
    _outputCase  = (p.getInt('outputCase') ?? 0).clamp(0, 1);
    _wpm         = (p.getInt('qsoBotWpm') ?? p.getInt('wpm') ?? 20).clamp(5, 60);
    _type        = (p.getInt('qsoBotType') ?? 0).clamp(0, 2);
    _level       = (p.getInt('qsoBotLevel') ?? 1).clamp(0, 2);
    _contestType = (p.getInt('qsoBotContest') ?? 0).clamp(0, 1);
    _myCall      = p.getString('qsoMyCall') ?? '';
    _callRegion  = (p.getInt('callRegionOpt') ?? 0).clamp(0, 7);
    _callCommon  = p.getBool('callCommonOnly') ?? true;
    // The native engine is a shared singleton: push this screen's own config.
    final pitch = p.getInt('pitch') ?? 600;
    final soft  = (p.getInt('toneSoftness') ?? 4).clamp(0, 8);
    await _toneChannel.invokeMethod('setFreq', pitch);
    await _toneChannel.invokeMethod('setVolume', 0.7);
    await _toneChannel.invokeMethod('setEnvelopeMs', (soft + 1).toDouble());
    await _keyerChannel.invokeMethod('setWpm', _wpm);
    await _keyerChannel.invokeMethod('setMode', _keyerMode);
    await _keyerChannel.invokeMethod('setCurtisBTiming', {
      'dit': (p.getInt('curtisBDitTiming') ?? 75).clamp(0, 100),
      'dah': (p.getInt('curtisBDahTiming') ?? 45).clamp(0, 100),
    });
    await _keyerChannel.invokeMethod('setAcs', (p.getInt('acs') ?? 0).clamp(0, 3));
    await _loadWordGap();
    await _keyerChannel.invokeMethod('start');
    _refillCalls();
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _loadWordGap() async {
    final p = await SharedPreferences.getInstance();
    _interWord = (p.getInt('profile.keyer.interWordSpace') ??
        TrainingProfile.defaultInterWord(TrainingProfile.keyer)).clamp(6, 105);
    await _keyerChannel.invokeMethod('setInterWordSpace', _interWord);
    _bot?.interWordDits = _interWord;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _running) _stop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    KeepScreenOn.disable();
    _tickTimer?.cancel();
    _playGuard?.cancel();
    _symSub?.cancel();
    _genSub?.cancel();
    _genChannel.invokeMethod('stop');   // also restarts the keyer …
    _keyerChannel.invokeMethod('stop'); // … which we then stop, like KeyerScreen
    _textCtl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ── Bot callsigns (firmware getRandomCall(0) + continent/CQ zone) ───────

  Future<void> _refillCalls() async {
    if (_refilling) return;
    _refilling = true;
    try {
      while (_callPool.length < 8) {
        final m = await _genChannel.invokeMethod('randomCallInfo', {
          'callLengthOpt': 0,
          'callRegionOpt': _callRegion,
          'callCommonOnly': _callCommon,
        }) as Map;
        _callPool.add(QsoCall(m['call'] as String, m['continent'] as int, m['zone'] as int));
      }
    } catch (_) {
    } finally {
      _refilling = false;
    }
  }

  QsoCall _nextCall() {
    if (_callPool.isNotEmpty) {
      final c = _callPool.removeAt(0);
      _refillCalls();
      return c;
    }
    // Pool empty (native call still pending): plain random EU call.
    const l = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    String r() => l[_rnd.nextInt(26)];
    return QsoCall('D${r()}${_rnd.nextInt(10)}${r()}${r()}${r()}', contEU, 14);
  }

  // ── Session ─────────────────────────────────────────────────────────────

  void _start() {
    _decoder.reset();
    _tickTimer?.cancel();
    final bot = QsoBot(
      type: QsoType.values[_type],
      level: QsoLevel.values[_level],
      contestType: _contestType,
      userCall: _myCall,
      userWpm: _wpm,
      interWordDits: _interWord,
      nextCall: _nextCall,
      play: _playBot,
      stopPlay: _stopBotPlayback,
      info: (t) => _appendInfo(t),
    );
    _bot = bot;
    _appendInfo('${_typeNames[_type]} · ${_levelNames()[_level]}');
    bot.start();
    _tickTimer = Timer.periodic(const Duration(milliseconds: 20), (_) => _tick());
    _updateStatus();
  }

  void _stop() {
    _bot?.abort();
    _finishIfDone();
  }

  void _tick() {
    final bot = _bot;
    if (bot == null) return;
    bot.tick();
    _finishIfDone();
    _updateStatus();
  }

  void _finishIfDone() {
    if (_bot?.phase == QsoPhase.done) {
      _tickTimer?.cancel();
      _tickTimer = null;
      _updateStatus();
    }
  }

  void _updateStatus() {
    final bot = _bot;
    String s;
    if (bot == null) {
      s = Strings.t('qso_idle');
    } else {
      switch (bot.phase) {
        case QsoPhase.opening:
          s = Strings.t('qso_st_opening');
        case QsoPhase.botTx:
          s = Strings.t('qso_st_tx').replaceAll('{w}', '${bot.botWpm}');
        case QsoPhase.expect:
          s = Strings.t('qso_st_expect');
        case QsoPhase.pause:
          s = '…';
        case QsoPhase.done:
          s = Strings.t('qso_st_done');
      }
    }
    if (s != _status && mounted) setState(() => _status = s);
  }

  // ── Bot transmit ────────────────────────────────────────────────────────

  static final _tokenRe = RegExp(r'<[a-zA-Z]{2,3}>|\S|\s');

  void _playBot(String text, int wpm) {
    _txTokens = [for (final m in _tokenRe.allMatches(text)) m.group(0)!];
    _txPos = 0;
    _botPlaying = true;
    _newSeg(_SegKind.rx);
    _emitNextBotChar();
    // Generator config is shared state — push what playback needs each time.
    _genChannel.invokeMethod('setWpm', wpm);
    _genChannel.invokeMethod('setInterCharSpace', 3);
    _genChannel.invokeMethod('setInterWordSpace', 7);
    _genChannel.invokeMethod('playOne', text);
    // Safety net if the engine never reports done (e.g. it was busy).
    _playGuard?.cancel();
    _playGuard = Timer(
        Duration(milliseconds: (1200 * 14 * text.length / wpm).round() + 1500), _onBotDone);
  }

  void _stopBotPlayback() {
    _playGuard?.cancel();
    _botPlaying = false;
    _genChannel.invokeMethod('stop');   // restarts the keyer, which stays on here
  }

  void _emitNextBotChar() {
    var out = '';
    while (_txPos < _txTokens.length && _txTokens[_txPos] == ' ') {
      out += ' ';
      _txPos++;
    }
    if (_txPos < _txTokens.length) out += _txTokens[_txPos++];
    if (out.isNotEmpty) _appendChars(_SegKind.rx, out);
  }

  void _onGenEvent(dynamic raw) {
    if (!_botPlaying || raw is! Map) return;
    if (raw['type'] == 'char') {
      _emitNextBotChar();
    } else if (raw['type'] == 'done') {
      _onBotDone();
    }
  }

  void _onBotDone() {
    if (!_botPlaying) return;
    _playGuard?.cancel();
    _botPlaying = false;
    if (_txPos < _txTokens.length) _appendChars(_SegKind.rx, _txTokens.sublist(_txPos).join());
    _txPos = _txTokens.length;
    _bot?.txDone();
    _finishIfDone();
    _updateStatus();
  }

  // ── Your keying ─────────────────────────────────────────────────────────

  // Decoder output -> firmware encodeProSigns() form for the matcher:
  // letters lowercase, prosigns as their uppercase code (so the letter r and
  // <err> = 'R' stay apart, as on the device).
  static const _prosignCode = {
    'SK': 'K', 'KN': 'N', 'KA': 'A', 'AS': 'S', 'VE': 'E', 'BK': 'B', MorseDecoder.err: 'R',
  };

  void _onDecodedChar(String ch) {
    final code = ch == '*' ? 'U' : (_prosignCode[ch] ?? ch.toLowerCase());
    final shown = ch == ' ' ? ' ' : ch.length > 1 ? '<${ch.toLowerCase()}>' : ch;
    if (ch == ' ') {
      if (_log.isNotEmpty && _log.last.kind == _SegKind.tx && !_log.last.text.endsWith(' ')) {
        _appendChars(_SegKind.tx, ' ');
      }
    } else {
      _appendChars(_SegKind.tx, shown);
    }
    if (_running) {
      _bot!.feed(code);
      _finishIfDone();
      _updateStatus();
    }
  }

  /// Typed text: fed to the bot like keyed words (no audio).
  void _sendText(String text) {
    final t = text.trim().toUpperCase();
    if (!_running || t.isEmpty) return;
    _newSeg(_SegKind.tx);
    _appendChars(_SegKind.tx, t);
    final bot = _bot!;
    for (final m in RegExp(r'<([A-Z]{2,3})>|\S|\s').allMatches(t)) {
      final ps = m.group(1);
      if (ps != null) {
        bot.feed(_prosignCode[ps == 'ERR' ? MorseDecoder.err : ps] ?? '');
      } else {
        bot.feed(m.group(0)!.toLowerCase());
      }
    }
    bot.feed(' ');
    _finishIfDone();
    _updateStatus();
  }

  // ── Log ─────────────────────────────────────────────────────────────────

  void _newSeg(_SegKind kind) {
    if (_log.isNotEmpty && _log.last.kind == kind && _log.last.text.trim().isEmpty) return;
    _log.add(_Seg(kind, ''));
  }

  void _appendChars(_SegKind kind, String text) {
    if (!mounted) return;
    setState(() {
      if (_log.isEmpty || _log.last.kind != kind) _log.add(_Seg(kind, ''));
      _log.last.text += text;
      if (_log.length > 300) _log.removeAt(0);
    });
    _scrollDown();
  }

  void _appendInfo(String text) {
    if (!mounted) return;
    setState(() => _log.add(_Seg(_SegKind.info, text)));
    _scrollDown();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _confirmClearLog() async {
    if (_log.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Strings.t('qso_clear_title')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(Strings.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(Strings.t('qso_clear'))),
        ],
      ),
    );
    if (ok == true) setState(() => _log.clear());
  }

  // ── Settings ────────────────────────────────────────────────────────────

  static const _typeNames = ['SOTA/POTA', 'Standard', 'Contest'];
  List<String> _levelNames() =>
      [Strings.t('qso_lvl_beg'), Strings.t('qso_lvl_int'), Strings.t('qso_lvl_adv')];

  Future<void> _setType(int t) async {
    setState(() => _type = t);
    (await SharedPreferences.getInstance()).setInt('qsoBotType', t);
  }

  Future<void> _setWpm(int w) async {
    setState(() => _wpm = w);
    _bot?.userWpm = w;
    (await SharedPreferences.getInstance()).setInt('qsoBotWpm', w);
    _keyerChannel.invokeMethod('setWpm', w);
  }

  Future<void> _openSettings() async {
    final c = AppColors.of(context);
    final callCtl = TextEditingController(text: _myCall);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.background,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        Future<void> save(void Function(SharedPreferences p) f) async {
          f(await SharedPreferences.getInstance());
          setSheet(() {});
          if (mounted) setState(() {});
        }
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16,
              16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SettingsSectionHeader(Strings.t('qso_settings').toUpperCase()),
              const SizedBox(height: 8),
              SettingsCard(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: TextField(
                    controller: callCtl,
                    autocorrect: false,
                    textCapitalization: TextCapitalization.characters,
                    style: TextStyle(fontFamily: 'CwMono', fontSize: 15, color: c.textPrimary),
                    decoration: InputDecoration(
                      labelText: Strings.t('qso_my_call'),
                      hintText: 'OE1XXX',
                      helperText: Strings.t('qso_my_call_hint'),
                    ),
                    onChanged: (v) {
                      _myCall = v.trim().toUpperCase();
                      save((p) => p.setString('qsoMyCall', _myCall));
                    },
                  ),
                ),
                const SettingsDivider(),
                SegmentRow(
                  label: Strings.t('qso_level'),
                  options: _levelNames(),
                  selected: _level,
                  onChanged: (v) { _level = v; save((p) => p.setInt('qsoBotLevel', v)); },
                ),
                const SettingsDivider(),
                SegmentRow(
                  label: Strings.t('qso_contest_type'),
                  options: const ['CQ WW', 'WPX/Sprint'],
                  selected: _contestType,
                  onChanged: (v) { _contestType = v; save((p) => p.setInt('qsoBotContest', v)); },
                ),
                const SettingsDivider(),
                ListTile(
                  title: Text(Strings.t('qso_word_gap'), style: TextStyle(
                      fontFamily: 'CwMono', fontSize: 13, color: c.textPrimary)),
                  subtitle: Text(Strings.t('qso_word_gap_hint'), style: TextStyle(
                      fontFamily: 'CwMono', fontSize: 11, color: c.textMuted)),
                  trailing: Icon(Icons.chevron_right, color: c.textFaint),
                  onTap: () async {
                    await showTrainingSettingsSheet(context,
                        profile: TrainingProfile.keyer,
                        sections: const [TrainingSection.wordSpacing]);
                    await _loadWordGap();
                  },
                ),
              ]),
              const SizedBox(height: 12),
              Text(Strings.t('qso_rules'), style: TextStyle(
                  fontFamily: 'CwMono', fontSize: 11, color: c.textMuted)),
            ],
          )),
        );
      }),
    );
  }

  // ── Touch paddles ───────────────────────────────────────────────────────

  void _setTouchInputs({bool? dit, bool? dah}) {
    if (dit != null) _touchDit = dit;
    if (dah != null) _touchDah = dah;
    _keyerChannel.invokeMethod('setInputs', {'dit': _touchDit, 'dah': _touchDah});
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  String _case(String s) => _outputCase == 1 ? s.toUpperCase() : s.toLowerCase();

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        title: appBarTitle(c, 'QSO Bot'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.textMuted),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.settings, color: c.textMuted),
            tooltip: Strings.t('settings_title'),
            onPressed: _running ? null : _openSettings,
          ),
        ],
      ),
      body: _ready ? _body(c) : Center(child: CircularProgressIndicator(color: c.accent)),
    );
  }

  Widget _body(AppColors c) {
    final mono = TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.textPrimary);
    final myCall = _myCall.isEmpty ? 'OE1XXX' : _myCall;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          Expanded(child: DropdownButtonFormField<int>(
            key: ValueKey(_type),
            initialValue: _type,
            isExpanded: true,
            isDense: true,
            dropdownColor: c.surface,
            style: TextStyle(fontFamily: 'CwMono', fontSize: 14, color: c.accent),
            decoration: InputDecoration(
              isDense: true, filled: true, fillColor: c.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: c.border)),
            ),
            items: [for (var i = 0; i < _typeNames.length; i++)
              DropdownMenuItem(value: i, child: Text(_typeNames[i], overflow: TextOverflow.ellipsis))],
            onChanged: _running ? null : (v) => _setType(v!),
          )),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _running ? _stop : _start,
            child: Text(Strings.t(_running ? 'stop' : 'start')),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(children: [
          Icon(_running ? Icons.forum : Icons.forum_outlined, size: 16,
              color: _running ? c.accent : c.textMuted),
          const SizedBox(width: 6),
          Expanded(child: Text(_status.isEmpty ? Strings.t('qso_idle') : _status,
              style: TextStyle(fontFamily: 'CwMono', fontSize: 11, color: c.textMuted))),
          Text('${_levelNames()[_level]} · $myCall',
              style: TextStyle(fontFamily: 'CwMono', fontSize: 11, color: c.textFaint)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Text('$_wpm WPM', style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.accent)),
          Expanded(child: Slider(
            value: _wpm.toDouble(), min: 5, max: 60, divisions: 55,
            onChanged: (v) => setState(() => _wpm = v.round()),
            onChangeEnd: (v) => _setWpm(v.round()),
          )),
        ]),
      ),
      Expanded(
        child: GestureDetector(
          onLongPress: _confirmClearLog,
          child: Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.border),
          ),
          child: _log.isEmpty
              ? Center(child: Text(Strings.t('qso_empty'), textAlign: TextAlign.center,
                  style: mono.copyWith(color: c.textFaint, fontSize: 12)))
              : ListView(controller: _scroll, children: [
                  for (final s in _log)
                    if (s.text.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: s.kind == _SegKind.info
                            ? Text('[${s.text}]', style: mono.copyWith(
                                fontSize: 11, color: c.textMuted))
                            : Text.rich(TextSpan(children: [
                                TextSpan(text: s.kind == _SegKind.rx ? 'RX  ' : 'TX  ',
                                    style: mono.copyWith(fontSize: 11,
                                        color: s.kind == _SegKind.rx ? c.info : c.warning)),
                                TextSpan(text: _case(s.text),
                                    style: mono.copyWith(fontSize: 18,
                                        color: s.kind == _SegKind.rx ? c.textPrimary : c.accent)),
                              ])),
                      ),
                ]),
        )),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Expanded(child: TextField(
            controller: _textCtl,
            enabled: _running,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            onSubmitted: (_) { _sendText(_textCtl.text); _textCtl.clear(); },
            style: TextStyle(fontFamily: 'CwMono', fontSize: 14, color: c.textPrimary),
            decoration: InputDecoration(
              isDense: true, filled: true, fillColor: c.surface,
              hintText: Strings.t('qso_type_hint'),
              hintStyle: TextStyle(fontFamily: 'CwMono', color: c.textDisabled),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: c.border)),
            ),
          )),
          IconButton(
            icon: Icon(Icons.send, color: _running ? c.accent : c.textDisabled),
            onPressed: _running
                ? () { _sendText(_textCtl.text); _textCtl.clear(); }
                : null,
          ),
        ]),
      ),
      const SizedBox(height: 8),
      if (_keyerMode == 4)
        StraightKeyPaddle(
            onDown: () => _setTouchInputs(dit: true),
            onUp: () => _setTouchInputs(dit: false))
      else
        IambicPaddles(
          onDitDown: () => _setTouchInputs(dit: true),
          onDitUp:   () => _setTouchInputs(dit: false),
          onDahDown: () => _setTouchInputs(dah: true),
          onDahUp:   () => _setTouchInputs(dah: false),
        ),
      const SizedBox(height: 16),
    ]);
  }
}
