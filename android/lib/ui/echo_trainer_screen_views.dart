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

  // Same result page as Listen's: percentage, "x of y correct", trend, the
  // proposal cards and the suggestions; no list of the single words.
  Widget _buildBlockResult(AppColors c) {
    final first = _blockResults.where((r) => r.outcome == WordOutcome.first).length;
    final total = _blockResults.length;
    final pct = total == 0 ? 100 : first * 100 ~/ total;
    String cs(String t) => _outputCase == 1 ? t.toUpperCase() : t.toLowerCase();
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
      child: Column(children: [
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
        Expanded(
          child: ScrollHint(
            center: true,
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(width: double.infinity, child: BreakHintCard()),
              ),
              Text('$pct %',
                  style: TextStyle(fontFamily: 'DMSans', fontSize: 52,
                      fontVariations: const [FontVariation('wght', 600)],
                      color: pct >= 90 ? c.accent : pct >= 70 ? c.warning : c.danger)),
              Text(Strings.t('ac_correct_of').replaceFirst('{c}', '$first').replaceFirst('{t}', '$total'),
                  style: TextStyle(fontSize: 16, color: c.textMuted)),
              if (_trend != null) ...[
                const SizedBox(height: 10),
                Text(Strings.t('trend_line')
                        .replaceFirst('{pct}', '${_trend!.percent}')
                        .replaceFirst('{arrow}', _trend!.arrow),
                    style: TextStyle(fontSize: 13, color: c.textMuted)),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(children: _buildSuggestionRows(c, MediaQuery.of(context).size.width - 40, cs)),
              ),
            ]),
          ),
        ),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(children: [
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
        ])),
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
    String cs(String t) => _outputCase == 1 ? t.toUpperCase() : t.toLowerCase();
    final weak = _startWeakChars();
    final mixups = _startMixups();
    // Full cards while they fit above the tempo card, else one row + sheet (#109).
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: FitOrCompact(
            availableHeight: box.maxHeight,
            below: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: _controlsCard(),
            ),
            builder: (compact) => Column(children: [
              const KeyAdapterHint(),
              if (weak.isNotEmpty || mixups.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: compact
                      ? BoostSummaryRow(
                          chars: [
                            for (final ch in weak.keys)
                              if (!_excludedBoost.contains(ch)) cs(ch),
                          ],
                          pairs: mixups.where((m) => !_excludedMixups.contains(m.pair)).length,
                          onTap: () => showBoostSheet(context,
                              cards: (refresh) => _proposalCards(c, weak, mixups,
                                  includeOutlook: false, onChanged: refresh)),
                        )
                      : Column(children: _proposalCards(c, weak, mixups)),
                ),
            ]),
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
