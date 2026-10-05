// Block progress, result, idle and practice views of the Hören/Geben echo trainer. Split out of echo_trainer_screen.dart; same library.
part of 'echo_trainer_screen.dart';

extension _EchoViews on _EchoTrainerScreenState {
  Widget _buildBlockProgress(AppColors c) {
    final n = (_blockResults.length + 1).clamp(1, _blockSize);
    final dots = List.generate(_blockSize, (i) {
      if (i >= _blockResults.length) return '·';
      return switch (_blockResults[i].outcome) {
        WordOutcome.first => '●',
        WordOutcome.afterRepeat => '◐',
        WordOutcome.failed => '○',
      };
    }).join(' ');
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(children: [
        Text(Strings.t(_choice.content == ContentKind.random ? 'block_group_of' : 'block_word_of').replaceFirst('{n}', '$n').replaceFirst('{t}', '$_blockSize'),
            style: TextStyle(fontFamily: 'CwMono', fontSize: 14, color: c.textMuted)),
        const SizedBox(height: 2),
        Text(dots, style: TextStyle(fontFamily: 'CwMono', fontSize: 16, color: c.textPrimary)),
      ]),
    );
  }

  Widget _buildBlockResult(AppColors c) {
    final first = _blockResults.where((r) => r.outcome == WordOutcome.first).length;
    final again = _blockResults.where((r) => r.outcome == WordOutcome.afterRepeat).length;
    final failed = _blockResults.where((r) => r.outcome == WordOutcome.failed).length;
    final total = _blockResults.length;
    final pct = total == 0 ? 0 : first * 100 ~/ total;
    final status = [
      if (_koch) '${Strings.t('block_lesson')} $_kochLevel',
      if (_trend != null)
        Strings.t('trend_line')
            .replaceFirst('{pct}', '${_trend!.percent}')
            .replaceFirst('{arrow}', _trend!.arrow),
    ].join(' · ');
    String cs(String t) => _outputCase == 1 ? t.toUpperCase() : t.toLowerCase();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const BreakHintCard(),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('$pct %',
              style: TextStyle(fontFamily: 'SpaceGrotesk', fontSize: 52,
                  fontVariations: const [FontVariation('wght', 600)],
                  color: pct >= 90 ? c.accent : pct >= 70 ? c.warning : c.danger)),
          const SizedBox(width: 20),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('● ${Strings.t('block_right')} $first',
                style: TextStyle(fontFamily: 'CwMono', fontSize: 14, color: c.accent)),
            Text('◐ ${Strings.t('block_after')} $again',
                style: TextStyle(fontFamily: 'CwMono', fontSize: 14, color: c.warning)),
            Text('○ ${Strings.t('block_wrong')} $failed',
                style: TextStyle(fontFamily: 'CwMono', fontSize: 14, color: c.danger)),
          ]),
        ]),
        const SizedBox(height: 6),
        if (status.isNotEmpty)
          Text(status, textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.textMuted)),
        if (_blockPairs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
                '${Strings.t('pairs_block')}: ${_blockPairs.map((x) => cs(x.replaceFirst('>', ' → '))).join(', ')}',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.warning)),
          ),
        _buildTempoControls(c),
        const SizedBox(height: 4),
        Expanded(child: PinchZoomFontSize(
          prefsKey: 'echoResultFontSize',
          initialSize: 20,
          minSize: 12,
          maxSize: 40,
          builder: (context, fontSize) => Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: ListView(children: [
              ..._buildSuggestionRows(c, MediaQuery.of(context).size.width - 56, cs),
              for (final r in _blockResults)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(switch (r.outcome) {
                      WordOutcome.first => '● ',
                      WordOutcome.afterRepeat => '◐ ',
                      WordOutcome.failed => '○ ',
                    }, style: TextStyle(fontFamily: 'CwMono', fontSize: fontSize,
                        color: switch (r.outcome) {
                          WordOutcome.first => c.accent,
                          WordOutcome.afterRepeat => c.warning,
                          WordOutcome.failed => c.danger,
                        })),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(cs(r.target), style: TextStyle(fontFamily: 'CwMono',
                          fontSize: fontSize, fontWeight: FontWeight.bold, color: c.textPrimary)),
                      if (r.outcome != WordOutcome.first || r.firstWrongIndex >= 0)
                        RichText(text: TextSpan(children: [
                          for (var i = 0; i < r.firstAttempt.length; i++)
                            TextSpan(text: cs(r.firstAttempt[i]), style: TextStyle(
                                fontFamily: 'CwMono', fontSize: fontSize * 0.85,
                                color: i == r.firstWrongIndex ? c.danger : c.textMuted,
                                fontWeight: i == r.firstWrongIndex ? FontWeight.bold : FontWeight.normal)),
                          if (r.firstWrongIndex >= r.firstAttempt.length)
                            TextSpan(text: r.firstAttempt.isEmpty ? '–' : '_', style: TextStyle(
                                fontFamily: 'CwMono', fontSize: fontSize * 0.85,
                                color: c.danger, fontWeight: FontWeight.bold)),
                        ])),
                    ])),
                  ]),
                ),
            ]),
          ),
        )),
        const SizedBox(height: 12),
        AppButton(
          height: 56,
          label: Strings.t('block_next'),
          color: c.accent,
          onTap: () async {
            await _applyAccepted(boost: true);
            if (mounted) _update(() {});
            await _startSession();
          },
        ),
        const SizedBox(height: 8),
        AppButton(
          height: 56,
          primary: false,
          label: Strings.t('block_end'),
          color: c.accent,
          onTap: () async {
            await _applyAccepted(boost: false);
            if (mounted) _update(() => _showResult = false);
          },
        ),
      ]),
    );
  }

  // Idle: nothing but empty space, like the Hören start view; the tempo is
  // on the sliders below.
  Widget _buildIdle(AppColors c) => const SizedBox.shrink();

  // Running: the current word centred — the prompt (if shown), what the
  // operator keyed so far, and the verdict. Same one-thing-at-a-time layout
  // as the Hören block view instead of a scrolling transcript.
  Widget _buildPracticeView(AppColors c, double fontSize) {
    String cs(String t) => _outputCase == 1 ? t.toUpperCase() : t.toLowerCase();
    final showTarget = _targetVisible || _revealVisible;
    final verdict = switch (_state) {
      _State.correct => ('OK', c.accent),
      _State.wrong => ('ERR', c.danger),
      _ => ('', c.textPrimary),
    };
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Retry indicator: only for a word that did not pass on the first try.
          Text(_repeats > 1 && _state != _State.idle
                  ? Strings.t('echo_attempt')
                      .replaceFirst('{n}', '$_repeats')
                      .replaceFirst('{max}', _echoRepeats == 7 ? '∞' : '${_echoRepeats + 1}')
                  : ' ',
              style: TextStyle(fontFamily: 'CwMono', fontSize: 16,
                  fontWeight: FontWeight.bold, color: c.warning)),
          const SizedBox(height: 8),
          Text(showTarget ? cs(_target) : ' ', textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'CwMono', fontSize: fontSize,
                  fontWeight: FontWeight.bold, height: 1.3,
                  color: _revealVisible ? c.warning : c.accent)),
          const SizedBox(height: 12),
          Text(_attempt.isEmpty ? ' ' : cs(_attempt), textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'CwMono', fontSize: fontSize * 0.8,
                  height: 1.3, color: c.textPrimary)),
          const SizedBox(height: 12),
          Text(verdict.$1.isEmpty ? ' ' : verdict.$1,
              style: TextStyle(fontFamily: 'CwMono', fontSize: fontSize * 0.6,
                  fontWeight: FontWeight.bold, color: verdict.$2)),
        ]),
      ),
    );
  }
}
