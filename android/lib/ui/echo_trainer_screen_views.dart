// Block progress, result, idle and practice views of the Hören/Geben echo trainer. Split out of echo_trainer_screen.dart; same library.
part of 'echo_trainer_screen.dart';

extension _EchoViews on _EchoTrainerScreenState {
  // Same header as Listen's block views: content (+ Koch lesson) on the right,
  // one dot per word coloured by how it went, "Group n / t · WPM" below.
  Widget _buildBlockProgress(AppColors c) {
    final n = (_blockResults.length + 1).clamp(1, _blockSize);
    final cur = _blockResults.length;
    final capped = _answerWpmMax > 0 && _answerWpm < _currentWpm;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          Flexible(
            child: Text('${contentLabel(_choice.content)}${_koch ? ' · KOCH $_kochLevel' : ''}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: c.textMuted)),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      Wrap(alignment: WrapAlignment.center, children: List.generate(_blockSize, (i) {
        final done = i < _blockResults.length;
        final color = !done
            ? (i == cur ? c.accent : c.border)
            : switch (_blockResults[i].outcome) {
                WordOutcome.first => c.accent,
                WordOutcome.afterRepeat => c.warning,
                WordOutcome.failed => c.danger,
              };
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SizedBox(width: 16, height: 16, child: Center(
            child: Icon(i == cur ? Icons.radio_button_checked : Icons.circle,
                size: i == cur ? 16 : 10, color: color))),
        );
      })),
      const SizedBox(height: 10),
      Text('${Strings.t(_choice.content == ContentKind.random ? 'block_group_of' : 'block_word_of').replaceFirst('{n}', '$n').replaceFirst('{t}', '$_blockSize')}'
          ' · $_currentWpm WPM${capped ? ' → $_answerWpm' : ''}',
          style: TextStyle(fontSize: 13, color: c.textMuted)),
    ]);
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
              style: TextStyle(fontFamily: 'DMSans', fontSize: 52,
                  fontVariations: const [FontVariation('wght', 600)],
                  color: pct >= 90 ? c.accent : pct >= 70 ? c.warning : c.danger)),
          const SizedBox(width: 20),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('● ${Strings.t('block_right')} $first',
                style: TextStyle(fontSize: 14, color: c.accent)),
            Text('◐ ${Strings.t('block_after')} $again',
                style: TextStyle(fontSize: 14, color: c.warning)),
            Text('○ ${Strings.t('block_wrong')} $failed',
                style: TextStyle(fontSize: 14, color: c.danger)),
          ]),
        ]),
        const SizedBox(height: 6),
        if (status.isNotEmpty)
          Text(status, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: c.textMuted)),
        if (_blockPairs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
                '${Strings.t('pairs_block')}: ${_blockPairs.map((x) => cs(x.replaceFirst('>', ' → '))).join(', ')}',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.warning)),
          ),
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
        _controlsCard(),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: AppButton(
            height: 56,
            primary: false,
            label: Strings.t('block_end'),
            color: c.accent,
            onTap: () async {
              await _applyAccepted(boost: false);
              if (mounted) _update(() => _showResult = false);
            },
          )),
          const SizedBox(width: 12),
          Expanded(child: AppButton(
            height: 56,
            label: Strings.t('block_next'),
            color: c.accent,
            onTap: () async {
              await _applyAccepted(boost: true);
              if (mounted) _update(() {});
              await _startSession();
            },
          )),
        ]),
      ]),
    );
  }

  // Idle: nothing but empty space, like the Hören start view; the tempo is
  // on the sliders below.
  // Empty start area; carries the one-time tip about a real Morse key (#58).
  // Below it the weak characters and recurring mix-ups of Koch · Random, tappable
  // like on the result page; what stays ticked boosts the first block (#107).
  // The tempo + spacing card sits at the bottom of the scrolling area (above
  // the Start button when there is room) and scrolls on small phones instead
  // of overflowing.
  Widget _buildIdle(AppColors c) {
    final cards = _proposalCards(c, _startWeakChars(), _startMixups());
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Column(children: [
                const KeyAdapterHint(),
                if (cards.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Column(children: cards),
                  ),
              ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: _controlsCard(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Running: the current word centred — the prompt (if shown), what the
  // operator keyed so far, and the verdict. Same one-thing-at-a-time layout
  // as the Hören block view instead of a scrolling transcript.
  Widget _buildPracticeView(AppColors c, double fontSize) {
    String cs(String t) => _outputCase == 1 ? t.toUpperCase() : t.toLowerCase();
    final showTarget = _targetVisible || _revealVisible;
    final f = textScaleOf(context);
    // One status pill in Listen's style (attempt / listening / sending / right / wrong).
    final (badge, badgeColor) = switch (_state) {
      _State.correct => (Strings.t('echo_status_correct'), c.accent),
      _State.wrong => (Strings.t('echo_status_wrong'), c.danger),
      _State.playing => _preparing
          ? (Strings.t('get_ready'), c.warning)
          : (Strings.t('echo_status_playing'), c.warning),
      _State.receiving => _repeats > 1
          ? ('✗ ${Strings.t('echo_attempt').replaceFirst('{n}', '$_repeats').replaceFirst('{max}', _echoRepeats == 7 ? '∞' : '${_echoRepeats + 1}')}', c.danger)
          : (Strings.t('echo_status_receiving'), c.info),
      _State.idle => ('', c.textMuted),
    };
    final underline = switch (_state) {
      _State.correct => c.accent,
      _State.wrong => c.danger,
      _ => c.border,
    };
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            height: 28 * f,
            child: badge.isEmpty
                ? null
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(14)),
                    child: Text(badge, style: TextStyle(fontSize: 13, color: badgeColor)),
                  ),
          ),
          const SizedBox(height: 14),
          Text(showTarget ? cs(_target) : ' ', textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'CwMono', fontSize: fontSize,
                  fontWeight: FontWeight.bold, letterSpacing: 4, height: 1.3,
                  color: _revealVisible ? c.warning : c.accent)),
          const SizedBox(height: 8),
          Text(_attempt.isEmpty ? ' ' : cs(_attempt), textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'CwMono', fontSize: fontSize * 0.8,
                  letterSpacing: 4, height: 1.3,
                  color: _state == _State.wrong ? c.danger : c.textPrimary)),
          const SizedBox(height: 6),
          Container(width: 200, height: 2, color: underline),
        ]),
      ),
    );
  }
}
