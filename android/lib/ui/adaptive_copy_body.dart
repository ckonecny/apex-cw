// Adaptive Copy Mode — listen-and-copy-on-paper flow: send a block of
// groups, reveal, tap errors, show a result. See docs/ADAPTIVE-COPY.md.
//
// This is the UI-skeleton stage: tempo/spacing are fixed (whatever the
// shared WPM/spacing settings are), no auto-adaptation between blocks yet —
// that's `adaptive_copy_engine.dart`, still to come. Character stats ARE
// already recorded via the shared CharStatsStore so nothing has to be
// migrated later.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../content/char_stats.dart';
import '../theme/app_colors.dart';
import '../l10n/strings.dart';

enum _Phase { idle, sending, revealed, marking, result }

class AdaptiveCopyBody extends StatefulWidget {
  final int kochLevel;
  final List<String> activeKochChars;
  // Content mode within the Koch-nested selector (Random/Abbrevs/Words/Mixed
  // — see GeneratorScreen._kochModeOrdinals/_kochModeLabels, shared with the
  // Classic flow, not duplicated here).
  final int contentModeIndex;
  final List<int> contentModeOrdinals;
  final List<String> contentModeLabels;
  final int wpm;
  final int groupLength;
  final int maxWords;
  final int abbrevLengthMax;
  final int interCharSpace;
  final int interWordSpace;

  const AdaptiveCopyBody({
    super.key,
    required this.kochLevel,
    required this.activeKochChars,
    required this.contentModeIndex,
    required this.contentModeOrdinals,
    required this.contentModeLabels,
    required this.wpm,
    required this.groupLength,
    required this.maxWords,
    required this.abbrevLengthMax,
    required this.interCharSpace,
    required this.interWordSpace,
  });

  @override
  State<AdaptiveCopyBody> createState() => _AdaptiveCopyBodyState();
}

class _AdaptiveCopyBodyState extends State<AdaptiveCopyBody> {
  static const _genChannel = MethodChannel('at.oe1wkl.morserino_mobile/cw_generator');
  static const _genEvents = EventChannel('at.oe1wkl.morserino_mobile/cw_gen_events');
  static const _toneChannel = MethodChannel('at.oe1wkl.morserino_mobile/cw_tone');

  final CharStatsStore _charStats = CharStatsStore();

  _Phase _phase = _Phase.idle;
  int _blockNumber = 1;
  List<String> _sentGroups = [];
  int _currentGroupIndex = 0;
  // "$groupIndex:$charIndex" keys of characters tapped as wrong.
  final Set<String> _wrongPositions = {};
  int _resultCorrect = 0;
  int _resultTotal = 0;

  bool _paused = false;
  Completer<void>? _pauseGate;
  bool _sessionActive = false;
  Completer<void>? _doneCompleter;
  StreamSubscription? _genSub;

  @override
  void dispose() {
    _sessionActive = false;
    _genSub?.cancel();
    _genChannel.invokeMethod('stop');
    super.dispose();
  }

  int _ditMs() => (1200 / widget.wpm).round();

  int get _blockSize => widget.maxWords > 0 ? widget.maxWords : 5;

  Future<String> _fetchGroup() async {
    final ordinal = widget.contentModeOrdinals[widget.contentModeIndex];
    final result = await _genChannel.invokeMethod('getNextContent', {
      'mode': ordinal,
      'kochLevel': widget.kochLevel,
      'kochActive': true,
      if (ordinal == 0) 'groupLength': widget.groupLength,
      // Sent unconditionally for the non-Random modes, same as
      // echo_trainer_screen.dart's kochMode branch — harmless for modes
      // that don't consume it.
      if (ordinal != 0) 'abbrevLengthMax': widget.abbrevLengthMax,
    });
    return ((result as String?) ?? '').toUpperCase();
  }

  void _onGenEvent(dynamic raw) {
    final ev = raw as Map;
    if (ev['type'] == 'done') _doneCompleter?.complete();
  }

  Future<void> _waitIfPaused() async {
    if (!_paused) return;
    _pauseGate = Completer<void>();
    await _pauseGate!.future;
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
    if (!_paused) {
      _pauseGate?.complete();
      _pauseGate = null;
    }
  }

  Future<void> _startBlock() async {
    if (_phase == _Phase.sending) return;
    _sessionActive = true;
    setState(() {
      _phase = _Phase.sending;
      _sentGroups = [];
      _wrongPositions.clear();
      _currentGroupIndex = 0;
      _paused = false;
    });

    final p = await SharedPreferences.getInstance();
    // Sync tempo/spacing/tone before sending — nothing else does this for
    // us (CLAUDE.md rule: shared singleton engine, every screen must push
    // its own config on entry).
    await _genChannel.invokeMethod('setWpm', widget.wpm);
    await _genChannel.invokeMethod('setInterCharSpace', widget.interCharSpace);
    await _genChannel.invokeMethod('setInterWordSpace', widget.interWordSpace);
    final pitch = p.getInt('pitch') ?? 600;
    final toneSoftness = (p.getInt('toneSoftness') ?? 4).clamp(0, 8);
    await _toneChannel.invokeMethod('setFreq', pitch);
    await _toneChannel.invokeMethod('setEnvelopeMs', (toneSoftness + 1).toDouble());

    _genSub?.cancel();
    _genSub = _genEvents.receiveBroadcastStream().listen(_onGenEvent);

    for (var i = 0; i < _blockSize; i++) {
      if (!_sessionActive) return;
      await _waitIfPaused();
      if (!_sessionActive) return;

      final group = await _fetchGroup();
      if (!_sessionActive || !mounted) return;
      setState(() {
        _sentGroups.add(group);
        _currentGroupIndex = i;
      });

      final completer = Completer<void>();
      _doneCompleter = completer;
      await _genChannel.invokeMethod('playOne', group);
      await completer.future;
      if (!_sessionActive) return;

      // playOne() plays with trailingGap=false (see CwGenerator.kt) — same
      // reasoning as the Classic flow's start-marker gap: insert the
      // inter-word gap ourselves between groups.
      await Future.delayed(Duration(milliseconds: _ditMs() * widget.interWordSpace));
    }
    if (!_sessionActive || !mounted) return;
    _revealBlock();
  }

  // "Aufdecken": ends sending early and reveals only what's been sent so
  // far — matches the concept doc's "überspringt den Rest".
  Future<void> _revealNow() async {
    if (_phase != _Phase.sending) return;
    _sessionActive = false;
    _pauseGate?.complete();
    _pauseGate = null;
    await _genChannel.invokeMethod('stop');
    _genSub?.cancel();
    _genSub = null;
    _revealBlock();
  }

  void _revealBlock() {
    if (mounted) setState(() => _phase = _Phase.revealed);
  }

  void _markAllCorrect() {
    _wrongPositions.clear();
    _finishBlock();
  }

  void _toggleWrong(int groupIndex, int charIndex) {
    final key = '$groupIndex:$charIndex';
    setState(() {
      if (!_wrongPositions.remove(key)) _wrongPositions.add(key);
    });
  }

  Future<void> _finishBlock() async {
    final p = await SharedPreferences.getInstance();
    await _charStats.load(p);
    var total = 0, correct = 0;
    for (var g = 0; g < _sentGroups.length; g++) {
      final group = _sentGroups[g];
      for (var i = 0; i < group.length; i++) {
        final wrong = _wrongPositions.contains('$g:$i');
        total++;
        if (!wrong) correct++;
        _charStats.record(group[i], !wrong, block: _blockNumber);
      }
    }
    await _charStats.save(p);
    if (!mounted) return;
    setState(() {
      _resultCorrect = correct;
      _resultTotal = total;
      _phase = _Phase.result;
    });
  }

  Map<String, int> _weakCharsThisBlock() {
    final m = <String, int>{};
    for (final key in _wrongPositions) {
      final parts = key.split(':');
      final g = int.parse(parts[0]);
      final i = int.parse(parts[1]);
      final ch = _sentGroups[g][i];
      m[ch] = (m[ch] ?? 0) + 1;
    }
    return m;
  }

  void _finish() {
    if (mounted) setState(() => _phase = _Phase.idle);
  }

  void _nextBlock() {
    _blockNumber++;
    _startBlock();
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return switch (_phase) {
      _Phase.idle => _buildIdle(context),
      _Phase.sending => _buildSending(context),
      _Phase.revealed => _buildRevealed(context),
      _Phase.marking => _buildMarking(context),
      _Phase.result => _buildResult(context),
    };
  }

  Widget _buildIdle(BuildContext context) {
    final c = AppColors.of(context);
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(Strings.t('ac_idle_hint'),
            style: TextStyle(fontFamily: 'CwMono', fontSize: 14,
                color: c.textMuted, fontStyle: FontStyle.italic),
            textAlign: TextAlign.center),
        const SizedBox(height: 20),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: c.accent.withOpacity(0.2),
            foregroundColor: c.accent,
            side: BorderSide(color: c.accent),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _startBlock,
          child: Text('▶  ${Strings.t('ac_start_block')}',
              style: const TextStyle(fontFamily: 'CwMono', fontSize: 16,
                  fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(Strings.t('ac_block_label').replaceFirst('{n}', '$_blockNumber'),
            style: TextStyle(fontFamily: 'CwMono', fontSize: 12,
                fontWeight: FontWeight.bold, color: c.textMuted)),
        Text('${widget.contentModeLabels[widget.contentModeIndex]} · KOCH ${widget.kochLevel}',
            style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.textMuted)),
      ]),
    );
  }

  Widget _buildSending(BuildContext context) {
    final c = AppColors.of(context);
    return Column(children: [
      _buildHeader(context),
      Expanded(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(Strings.t('ac_listening'),
                style: TextStyle(fontFamily: 'CwMono', fontSize: 26,
                    fontWeight: FontWeight.bold, color: c.textPrimary)),
            const SizedBox(height: 20),
            Row(mainAxisSize: MainAxisSize.min,
                children: List.generate(_blockSize, (i) {
              final sent = i < _currentGroupIndex ||
                  (i == _currentGroupIndex && _sentGroups.length > i);
              final current = i == _currentGroupIndex;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  current ? Icons.radio_button_checked : Icons.circle,
                  size: current ? 16 : 10,
                  color: sent ? c.accent : c.border,
                ),
              );
            })),
            const SizedBox(height: 12),
            Text(
                Strings.t('ac_group_of')
                    .replaceFirst('{n}', '${(_currentGroupIndex + 1).clamp(1, _blockSize)}')
                    .replaceFirst('{total}', '$_blockSize'),
                style: TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.textMuted)),
            const SizedBox(height: 6),
            Text('${widget.wpm} WPM',
                style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.textDisabled)),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Row(children: [
          Expanded(child: _SecondaryButton(
            label: _paused ? Strings.t('ac_resume') : Strings.t('ac_pause'),
            onTap: _togglePause,
          )),
          const SizedBox(width: 12),
          Expanded(child: _PrimaryButton(
            label: Strings.t('ac_reveal'),
            onTap: _revealNow,
          )),
        ]),
      ),
    ]);
  }

  Widget _buildRevealed(BuildContext context) {
    final c = AppColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(Strings.t('ac_sent_title'),
              style: TextStyle(fontFamily: 'CwMono', fontSize: 18,
                  fontWeight: FontWeight.bold, color: c.textPrimary)),
          Text(Strings.t('ac_sent_desc'),
              style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.textMuted)),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: _sentGroups.length,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              SizedBox(width: 24, child: Text('${i + 1}',
                  style: TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.textDisabled))),
              Expanded(child: Text(_sentGroups[i].split('').join(' '),
                  style: TextStyle(fontFamily: 'CwMono', fontSize: 22,
                      fontWeight: FontWeight.bold, color: c.textPrimary))),
            ]),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Row(children: [
          Expanded(child: _SecondaryButton(
            label: Strings.t('ac_all_correct'),
            onTap: _markAllCorrect,
          )),
          const SizedBox(width: 12),
          Expanded(child: _PrimaryButton(
            label: Strings.t('ac_mark_errors'),
            onTap: () => setState(() => _phase = _Phase.marking),
          )),
        ]),
      ),
    ]);
  }

  Widget _buildMarking(BuildContext context) {
    final c = AppColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(Strings.t('ac_mark_title'),
              style: TextStyle(fontFamily: 'CwMono', fontSize: 18,
                  fontWeight: FontWeight.bold, color: c.textPrimary)),
          Text(Strings.t('ac_mark_desc'),
              style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.textMuted)),
        ]),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(children: List.generate(_sentGroups.length, (g) {
            final group = _sentGroups[g];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(spacing: 8, runSpacing: 8,
                children: List.generate(group.length, (i) {
                  final wrong = _wrongPositions.contains('$g:$i');
                  return InkWell(
                    onTap: () => _toggleWrong(g, i),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 48, height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: wrong ? c.danger.withOpacity(0.18) : c.surfaceAlt,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: wrong ? c.danger : c.border),
                      ),
                      child: Text(group[i], style: TextStyle(fontFamily: 'CwMono',
                          fontSize: 18, fontWeight: FontWeight.bold,
                          color: wrong ? c.danger : c.textPrimary)),
                    ),
                  );
                }),
              ),
            );
          })),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Row(children: [
          Expanded(child: _SecondaryButton(
            label: Strings.t('ac_back'),
            onTap: () => setState(() => _phase = _Phase.revealed),
          )),
          const SizedBox(width: 12),
          Expanded(child: _PrimaryButton(
            label: Strings.t('ac_done_errors').replaceFirst('{n}', '${_wrongPositions.length}'),
            onTap: _finishBlock,
          )),
        ]),
      ),
    ]);
  }

  Widget _buildResult(BuildContext context) {
    final c = AppColors.of(context);
    final pct = _resultTotal == 0 ? 100 : (_resultCorrect * 100 ~/ _resultTotal);
    final weak = _weakCharsThisBlock();
    return Column(children: [
      _buildHeader(context),
      Expanded(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$pct %', style: TextStyle(fontFamily: 'CwMono', fontSize: 48,
                fontWeight: FontWeight.bold,
                color: pct >= 90 ? c.accent : pct >= 70 ? c.warning : c.danger)),
            Text(Strings.t('ac_correct_of')
                    .replaceFirst('{c}', '$_resultCorrect').replaceFirst('{t}', '$_resultTotal'),
                style: TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.textMuted)),
            if (weak.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(Strings.t('ac_weak_chars'),
                  style: TextStyle(fontFamily: 'CwMono', fontSize: 11, color: c.textDisabled)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center,
                children: weak.entries.map((e) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: c.danger.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: c.danger.withOpacity(0.4)),
                  ),
                  child: Text('${e.key}  ${e.value}',
                      style: TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.danger)),
                )).toList(),
              ),
            ],
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Row(children: [
          Expanded(child: _SecondaryButton(label: Strings.t('ac_finish'), onTap: _finish)),
          const SizedBox(width: 12),
          Expanded(child: _PrimaryButton(label: Strings.t('ac_next_block'), onTap: _nextBlock)),
        ]),
      ),
    ]);
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PrimaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SizedBox(height: 48, child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: c.accent.withOpacity(0.2),
        foregroundColor: c.accent,
        side: BorderSide(color: c.accent),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: onTap,
      child: Text(label, style: const TextStyle(fontFamily: 'CwMono', fontSize: 14,
          fontWeight: FontWeight.bold)),
    ));
  }
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SecondaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SizedBox(height: 48, child: OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.textMuted,
        side: BorderSide(color: c.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: onTap,
      child: Text(label, style: const TextStyle(fontFamily: 'CwMono', fontSize: 14,
          fontWeight: FontWeight.bold)),
    ));
  }
}
