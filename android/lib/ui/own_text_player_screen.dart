// Own texts (issue #8): the player. Plays a pasted text word by word through
// the shared CW generator. The screen shows the text unchanged; only the
// audio is flattened (owntexts/text_passage.dart).
//
// Settings live in their own profile (own.*), pushed to the shared generator
// on entry and on every change (rule 2). The tempo can be changed while the
// text plays: the generator reads wpm and spacing per element. Progress is
// saved per text; opening one that was started asks Continue / Restart.
import 'widgets/interference_button.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../content/training_profile.dart';
import '../l10n/strings.dart';
import '../owntexts/own_text_store.dart';
import '../owntexts/text_passage.dart';
import '../theme/app_colors.dart';
import '../util/interference_profile.dart';
import '../util/keep_screen_on.dart';
import 'widgets/app_ui.dart';
import 'widgets/char_playback_overlay.dart' show cwGenEvents;
import 'widgets/pinch_zoom_text.dart';
import 'widgets/setting_rows.dart';

part 'own_text_player_views.dart';

/// Settings of the own-texts profile.
class OwnTextSettings {
  int wpm = 20, interChar = 3, interWord = 7;
  int show = 1; // 0 always, 1 after playing, 2 only on tap

  static Future<OwnTextSettings> load() async {
    final p = await SharedPreferences.getInstance();
    final s = OwnTextSettings();
    if (p.getInt('own.wpm') == null) {
      // First visit: start from the Hören profile's speed and spacing.
      final hear = await TrainingProfile.open(TrainingProfile.hear);
      await p.setInt('own.wpm', TrainingProfile.clampWpm(hear.getInt('wpm')));
      await p.setInt('own.interCharSpace', (hear.getInt('interCharSpace') ?? 3).clamp(3, 45));
      await p.setInt('own.interWordSpace', (hear.getInt('interWordSpace') ?? 7).clamp(6, 105));
    }
    s.wpm = TrainingProfile.clampWpm(p.getInt('own.wpm'));
    s.interChar = (p.getInt('own.interCharSpace') ?? 3).clamp(3, 45);
    s.interWord = (p.getInt('own.interWordSpace') ?? 7).clamp(s.interChar < 6 ? 6 : s.interChar, 105);
    s.show = (p.getInt('own.show') ?? 1).clamp(0, 2);
    return s;
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('own.wpm', wpm);
    await p.setInt('own.interCharSpace', interChar);
    await p.setInt('own.interWordSpace', interWord);
    await p.setInt('own.show', show);
  }
}

/// One paragraph (a non-empty line) of the text: its words and where each
/// starts in the paragraph's string, for tap and follow.
class _Para {
  final int line;
  final bool gapBefore;
  final List<int> words = [];
  final List<int> starts = [];
  _Para(this.line, this.gapBefore);
}

class OwnTextPlayerScreen extends StatefulWidget {
  final OwnTextInfo info;
  final OwnTextStore store;
  const OwnTextPlayerScreen({super.key, required this.info, required this.store});

  @override
  State<OwnTextPlayerScreen> createState() => _OwnTextPlayerScreenState();
}

class _OwnTextPlayerScreenState extends State<OwnTextPlayerScreen> {
  // setState for the view extension in own_text_player_views.dart.
  void _update(VoidCallback fn) => setState(fn);

  static const _genChannel = MethodChannel('at.oe1cko.nextcwtrainer/cw_generator');
  static const _toneChannel = MethodChannel('at.oe1cko.nextcwtrainer/cw_tone');

  late OwnTextSettings _s;
  TextPassage? _p;
  final List<_Para> _paras = [];
  final Map<int, _Para> _paraOf = {}; // word → its paragraph
  final Map<int, GlobalKey> _paraKeys = {};
  String? _error;

  /// The word playing now, or — when stopped — the one to go on from.
  int _pos = 0;
  bool _playing = false;
  bool _revealed = false;
  final Set<int> _heard = {};
  List<int> _order = [];
  int _orderPos = 0, _charInWord = 0;
  /// Last word of a word / sentence replay (it stops there); null = to the end.
  int? _rangeEnd;
  int _sinceSave = 0;
  StreamSubscription? _genSub;
  final _scroll = ScrollController();
  final _scrollKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    KeepScreenOn.enable();
    _init();
  }

  @override
  void dispose() {
    InterferenceProfile.releaseAmbient(this);
    KeepScreenOn.disable();
    _genSub?.cancel();
    if (_playing) _genChannel.invokeMethod('stopOne');
    _save();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      _s = await OwnTextSettings.load();
      final prefs = await SharedPreferences.getInstance();
      await _toneChannel.invokeMethod('setFreq', prefs.getInt('pitch') ?? 600);
      await _toneChannel.invokeMethod('setEnvelopeMs',
          ((prefs.getInt('toneSoftness') ?? 4).clamp(0, 8) + 1).toDouble());
      await _pushSpeed();
      final p = TextPassage.parse(await widget.store.body(widget.info.id));
      _buildParas(p);
      _genSub = cwGenEvents.listen(_onGenEvent);
      final saved = widget.info.pos;
      if (mounted) setState(() => _p = p);
      if (saved > 0 && saved < p.words.length && p.hasAudio) {
        _pos = p.playableFrom(saved);
        _heard.addAll(List.generate(_pos, (i) => i));
        WidgetsBinding.instance.addPostFrameCallback((_) => _askResume());
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _buildParas(TextPassage p) {
    _Para? cur;
    var prevLine = -1;
    var offset = 0;
    for (var i = 0; i < p.words.length; i++) {
      final w = p.words[i];
      if (cur == null || w.line != cur.line) {
        cur = _Para(w.line, prevLine >= 0 && w.line - prevLine > 1);
        _paras.add(cur);
        offset = 0;
      } else {
        offset += 1; // the space between words
      }
      cur.words.add(i);
      cur.starts.add(offset);
      _paraOf[i] = cur;
      offset += w.display.length;
      prevLine = w.line;
    }
  }

  Future<void> _askResume() async {
    if (!mounted) return;
    final p = _p!;
    final percent = (_pos * 100 / p.words.length).round();
    final cont = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(Strings.t('ot_resume_q')),
        content: Text(Strings.t('ot_resume_info')
            .replaceAll('{p}', '$percent')
            .replaceAll('{n}', '$_pos')
            .replaceAll('{m}', '${p.words.length}')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(Strings.t('ot_restart_text'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(Strings.t('ot_continue'))),
        ],
      ),
    );
    if (!mounted) return;
    if (cont == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _follow());
      _play();
    } else {
      setState(() {
        _pos = p.playableFrom(0);
        _heard.clear();
      });
      _save();
    }
  }

  Future<void> _pushSpeed() async {
    await _genChannel.invokeMethod('setWpm', _s.wpm);
    await _genChannel.invokeMethod('setInterCharSpace', _s.interChar);
    await _genChannel.invokeMethod('setInterWordSpace', _s.interWord);
  }

  /// Tempo and spacing apply to the text already playing.
  Future<void> _onSettingsChanged() async {
    await _s.save();
    await _pushSpeed();
    if (mounted) setState(() {});
  }

  void _save() {
    widget.store.setPos(widget.info.id, _pos);
    widget.info.pos = _pos;
    _sinceSave = 0;
  }

  // ---- playback ----

  /// Plays from word [from] (default [_pos]) to [to] (default the end). A
  /// replay that ends before the end leaves the position on the next word.
  Future<void> _play({int? from, int? to}) async {
    final p = _p;
    if (p == null || !p.hasAudio) return;
    final start = p.playableFrom(from ?? _pos);
    await _genChannel.invokeMethod('stopOne');
    final (text, order) = p.audioFrom(start, to);
    if (order.isEmpty) {
      InterferenceProfile.releaseAmbient(this);
      setState(() => _playing = false);
      return;
    }
    // The noise stands while the text is playing, not during a pause.
    InterferenceProfile.requestAmbient(this);
    setState(() {
      _order = order;
      _orderPos = 0;
      _charInWord = 0;
      _rangeEnd = to;
      _playing = true;
      _pos = order.first;
    });
    await _pushSpeed();
    await _genChannel.invokeMethod('playOne', text);
    WidgetsBinding.instance.addPostFrameCallback((_) => _follow());
  }

  void _onGenEvent(dynamic raw) {
    if (!_playing || !mounted) return;
    final p = _p!;
    final m = raw as Map;
    switch (m['type']) {
      case 'char':
        if (_orderPos >= _order.length) return;
        _charInWord++;
        final w = _order[_orderPos];
        if (_charInWord >= p.words[w].tokens) {
          _heard.add(w);
          _orderPos++;
          _charInWord = 0;
          if (_orderPos < _order.length) _pos = _order[_orderPos];
          if (++_sinceSave >= 20) _save();
          WidgetsBinding.instance.addPostFrameCallback((_) => _follow());
        }
        setState(() {});
      case 'done':
        InterferenceProfile.releaseAmbient(this);
        setState(() {
          _heard.addAll(_order);
          _playing = false;
          final end = _rangeEnd;
          final next = end == null ? null : p.played.where((j) => j > end).firstOrNull;
          // The end of the text wraps to the start, as in the firmware.
          _pos = next ?? p.playableFrom(0);
        });
        _save();
    }
  }

  void _togglePlay() => _playing ? _pause() : _play();

  /// Stops and goes on from the beginning of the word being played.
  void _pause() {
    InterferenceProfile.releaseAmbient(this);
    final w = _currentWord;
    setState(() {
      _genChannel.invokeMethod('stopOne');
      _playing = false;
      if (w >= 0) _pos = w;
    });
    _save();
  }

  int get _currentWord => _playing && _orderPos < _order.length ? _order[_orderPos] : -1;

  /// The word the repeat buttons work on: the one playing — or, in the gap
  /// right after a word, that word — else the position.
  int get _refWord {
    if (_playing && _currentWord >= 0) {
      return _charInWord == 0 && _orderPos > 0 ? _order[_orderPos - 1] : _currentWord;
    }
    return _pos;
  }

  void _repeatWord() {
    final w = _refWord;
    _play(from: w, to: _p!.playableFrom(w));
  }

  void _repeatSentence() {
    final p = _p!;
    final w = _refWord;
    _play(from: p.sentenceStart(w), to: p.sentenceEnd(w));
  }

  void _restartText() {
    setState(() => _pos = 0);
    _play(from: 0);
  }

  /// Goes to [target]: keeps playing from there, or just moves the position.
  void _seek(int target) {
    if (_playing) {
      _play(from: target);
    } else {
      setState(() => _pos = target);
      _save();
      WidgetsBinding.instance.addPostFrameCallback((_) => _follow());
    }
  }

  void _wordBack() {
    final p = _p!;
    _seek(p.playableBefore(_refWordForSeek) ?? p.playableFrom(0));
  }

  void _wordForward() {
    final p = _p!;
    final w = _refWordForSeek;
    final next = p.played.where((j) => j > w).firstOrNull;
    if (next != null) _seek(next);
  }

  void _sentenceBack() {
    final p = _p!;
    final w = _refWordForSeek;
    final start = p.sentenceStart(w);
    if (w != start) {
      _seek(start);
    } else {
      final before = p.playableBefore(w);
      _seek(before == null ? start : p.sentenceStart(before));
    }
  }

  void _sentenceForward() {
    final next = _p!.nextSentenceStart(_refWordForSeek);
    if (next != null) _seek(next);
  }

  /// Seek base: the word playing or the position (not the gap special case).
  int get _refWordForSeek => _currentWord >= 0 ? _currentWord : _pos;

  /// Tap on a word: listen from there on.
  void _onTapWord(int i) => _play(from: i);

  void _toggleText() => setState(() {
        if (_textVisible) {
          _revealed = false;
          _heard.clear();
        } else {
          _revealed = true;
        }
      });

  /// Whether the text itself is on screen (not the "tap to show" box).
  bool get _textShown => _s.show != 2 || _revealed;

  /// Whether every word is readable now.
  bool get _textVisible =>
      _revealed || _s.show == 0 || (_p != null && _p!.played.every(_heard.contains));

  // ---- follow ----

  /// Keeps the current word in view: scrolls when it leaves the upper part
  /// of the viewport.
  void _follow() {
    if (!mounted || !_scroll.hasClients || _p == null) return;
    final para = _paraOf[_pos];
    if (para == null) return;
    final ro = _findParagraph(_paraKeys[para.line]?.currentContext?.findRenderObject());
    final scrollBox = _scrollKey.currentContext?.findRenderObject();
    if (ro == null || scrollBox is! RenderBox || !scrollBox.attached) return;
    final k = para.words.indexOf(_pos);
    final start = para.starts[k];
    final boxes = ro.getBoxesForSelection(TextSelection(
        baseOffset: start, extentOffset: start + _p!.words[_pos].display.length));
    if (boxes.isEmpty) return;
    final y = scrollBox.globalToLocal(ro.localToGlobal(boxes.first.toRect().center)).dy;
    final h = scrollBox.size.height;
    if (y < h * 0.12 || y > h * 0.65) {
      final pos = _scroll.position;
      final target = (pos.pixels + y - h * 0.3).clamp(0.0, pos.maxScrollExtent);
      _scroll.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  static RenderParagraph? _findParagraph(RenderObject? ro) {
    if (ro == null) return null;
    if (ro is RenderParagraph) return ro;
    RenderParagraph? found;
    ro.visitChildren((child) => found ??= _findParagraph(child));
    return found;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: Strings.lang,
      builder: (context, _, _) => Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(
          backgroundColor: c.background,
          title: appBarTitle(c, widget.info.title),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: c.textMuted),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            const InterferenceButton(),
            if (_p != null && _s.show != 0)
              IconButton(
                tooltip: Strings.t('ot_toggle_text'),
                icon: Icon(_textVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: c.textMuted),
                onPressed: _toggleText,
              ),
            if (_p != null)
              IconButton(
                tooltip: Strings.t('ot_settings'),
                icon: Icon(Icons.settings_outlined, color: c.textMuted),
                onPressed: _openSettings,
              ),
          ],
        ),
        body: _error != null
            ? Padding(padding: const EdgeInsets.all(16),
                child: Text(_error!, style: TextStyle(color: c.warning)))
            : _p == null
                ? const SizedBox.shrink()
                : _body(c),
      ),
    );
  }
}
