// Screen builders of the adaptive copy trainer (idle, sending, typing,
// revealed, result). Split out of adaptive_copy_body.dart; same library.
part of 'adaptive_copy_body.dart';

extension _AdaptiveCopyViews on _AdaptiveCopyBodyState {
  // Idle/start screen. _weakChars is already populated here (loaded in
  // initState from lifetime stats, not just after a block) so the panel —
  // and the boost it drives on the very first block — is visible right
  // away, not only from the second block onward.
  Widget _buildIdle(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _buildSpacingControl(context, scale: 1.2),
              if (_weakChars.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildWeakCharsSection(context, scale: 1.2),
              ],
            ]),
          ),
        ),
      );
    });
  }

  // Weak-character chips, tappable to include/exclude from the boosted
  // draw — shared between the idle/start screen (boosts the next block
  // about to start) and the result screen (boosts the block after that
  // one), see docs/ADAPTIVE-COPY.md.
  // scale bumps text size for the result screen ("der komplette text beim
  // resultat screen könnte ruhig größer sein") without also growing this
  // section where it's reused on the idle screen.
  Widget _buildWeakCharsSection(BuildContext context, {double scale = 1}) {
    final c = AppColors.of(context);
    return SizedBox(width: double.infinity, child: AppCard(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(Strings.t('ac_weak_chars'), textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11 * scale, color: c.textMuted)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center,
        children: _weakChars.entries.map((e) {
          final included = !_excludedBoostChars.contains(e.key);
          return InkWell(
            onTap: () => _update(() {
              if (included) {
                _excludedBoostChars.add(e.key);
              } else {
                _excludedBoostChars.remove(e.key);
              }
            }),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: included ? c.warning.withValues(alpha: 0.15) : c.surfaceAlt,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: included ? c.warning.withValues(alpha: 0.5) : c.border),
              ),
              child: Text('${_displayChar(e.key)}  ${(e.value * 100).round()}%',
                  style: TextStyle(fontFamily: 'CwMono', fontSize: 13 * scale,
                      color: included ? c.warning : c.textMuted,
                      decoration: included ? null : TextDecoration.lineThrough)),
            ),
          );
        }).toList(),
      ),
    ])));
  }

  // Manual spacing control, requested to be visible at every summary and at
  // the start ("bitte bei jeder zusammenfassung und auch zu beginn den
  // block zum anpassen der pausen einblenden") — separate from the engine's
  // own accept/reject spacing suggestion on the result screen: this one
  // always shows and lets the user nudge the pause directly, any time.
  // Bounds match the Settings sliders (interCharSpace/interWordSpace), not
  // _startInterCharSpace/_startInterWordSpace — those only cap how far the
  // *engine* is allowed to auto-widen, not a manual override.
  void _adjustSpacing(int delta) {
    final ic = (widget.interCharSpace + delta).clamp(3, 45);
    final iw = (widget.interWordSpace + delta).clamp(6, 105);
    if (ic == widget.interCharSpace && iw == widget.interWordSpace) return;
    widget.onSpacingChanged?.call(ic, iw);
  }

  Widget _buildSpacingControl(BuildContext context, {double scale = 1}) {
    final c = AppColors.of(context);
    return SizedBox(width: double.infinity, child: AppCard(child: Row(children: [
      Expanded(child: Text(Strings.t('ac_spacing_control_title'),
          style: TextStyle(fontSize: 11 * scale, color: c.textMuted))),
      _TapTarget(onTap: () => _adjustSpacing(-1),
          child: Icon(Icons.remove, size: 20, color: c.accent)),
      SizedBox(
        width: 60 * scale,
        child: Text('${widget.interCharSpace}/${widget.interWordSpace}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15 * scale,
                fontWeight: FontWeight.bold, color: c.textPrimary)),
      ),
      _TapTarget(onTap: () => _adjustSpacing(1),
          child: Icon(Icons.add, size: 20, color: c.accent)),
    ])));
  }

  Widget _buildHeader(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(Strings.t('ac_block_label').replaceFirst('{n}', '$_blockNumber'),
            style: TextStyle(fontSize: 12,
                fontWeight: FontWeight.bold, color: c.textMuted)),
        Text('${widget.contentModeLabels[widget.contentModeIndex]}${widget.kochLesson ? ' · KOCH ${widget.kochLevel}' : ''}',
            style: TextStyle(fontSize: 12, color: c.textMuted)),
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
            Text(_preparing ? Strings.t('get_ready') : Strings.t('ac_listening'),
                style: TextStyle(fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: _preparing ? c.warning : c.textPrimary)),
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
                Strings.t(_playsGroups ? 'ac_group_of' : 'ac_word_of')
                    .replaceFirst('{n}', '${(_currentGroupIndex + 1).clamp(1, _blockSize)}')
                    .replaceFirst('{total}', '$_blockSize'),
                style: TextStyle(fontSize: 13, color: c.textMuted)),
            const SizedBox(height: 6),
            Text('$_activeWpm WPM',
                style: TextStyle(fontSize: 12, color: c.textDisabled)),
            if (_awaitingChoice) ...[
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(children: [
                  Expanded(child: _SecondaryButton(
                      label: Strings.t('repeat_upper'), onTap: () => _choose(true))),
                  const SizedBox(width: 12),
                  Expanded(child: _PrimaryButton(
                      label: Strings.t('next_upper'), onTap: () => _choose(false))),
                ]),
              ),
              const SizedBox(height: 6),
              Text(Strings.t('ac_paddle_hint'),
                  style: TextStyle(fontSize: 10, color: c.textMuted)),
            ],
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

  // Typing mode screen: progress, the answer line, and the keyboard.
  Widget _buildTyping(BuildContext context) {
    final c = AppColors.of(context);
    final i = _currentGroupIndex;
    final mono = TextStyle(fontSize: 13, color: c.textMuted);
    final attempts = i < _typedAttempts.length ? _typedAttempts[i] : const <String?>[];
    // The fixed heights below keep the layout from jumping between states;
    // they grow with the system font size so the text still fits.
    final f = textScaleOf(context);

    Widget center;
    if (_preparing) {
      center = Text(Strings.t('get_ready'),
          style: TextStyle(fontSize: 26,
              fontWeight: FontWeight.bold, color: c.warning));
    } else {
      final solution = _typeState == _TypeState.solution;
      final correct = _typeState == _TypeState.correct;
      final wrong = _typeState == _TypeState.wrong;
      // Answer line: the typed text with a cursor; the word itself once
      // it is right (green) or given up (wrong chars of attempt 1 in red).
      Widget answer;
      if (correct || solution) {
        answer = Row(mainAxisSize: MainAxisSize.min, children: [
          for (var k = 0; k < _shownWord.length; k++)
            Text(_displayChar(_shownWord[k]), style: TextStyle(fontFamily: 'CwMono',
                fontSize: 36, fontWeight: FontWeight.bold, letterSpacing: 4,
                color: correct ? c.accent
                    : _wrongPositions.contains('$i:$k') ? c.danger : c.textPrimary)),
          const SizedBox(width: 2),
        ]);
      } else {
        final shown = wrong && attempts.isNotEmpty ? (attempts.last ?? '') : _input;
        answer = Row(mainAxisSize: MainAxisSize.min, children: [
          Text(shown.split('').map(_displayChar).join(),
              style: TextStyle(fontFamily: 'CwMono', fontSize: 36,
                  fontWeight: FontWeight.bold, letterSpacing: 4,
                  color: wrong ? c.danger : c.textPrimary,
                  decoration: wrong ? TextDecoration.lineThrough : null)),
          Container(width: 2, height: 34 * f, color: wrong ? Colors.transparent : c.accent),
        ]);
      }
      String? badge;
      Color badgeColor = c.danger;
      if (correct) {
        badge = Strings.t('echo_status_correct');
        badgeColor = c.accent;
      } else if (solution) {
        badge = Strings.t('ac_type_solution');
      } else if (wrong) {
        badge = Strings.t('echo_status_wrong');
      } else if (_attemptNo > 1) {
        badge = '✗ ${Strings.t('echo_attempt')
            .replaceFirst('{n}', '$_attemptNo').replaceFirst('{max}', '$_typeAttempts')}';
      }
      center = Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: List.generate(_blockSize, (k) {
          final done = k < _outcomes.length;
          final color = !done
              ? (k == i ? c.accent : c.border)
              : _outcomes[k] == 0 ? c.accent : _outcomes[k] == 1 ? c.warning : c.danger;
          // Fixed 16x16 cell: the current dot is bigger, and when it turns
          // into a result dot the row must not shrink — everything below
          // would jump (user feedback 2026-09-27).
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: SizedBox(width: 16, height: 16, child: Center(
              child: Icon(k == i && !done ? Icons.radio_button_checked : Icons.circle,
                  size: k == i && !done ? 16 : 10, color: color))),
          );
        })),
        const SizedBox(height: 10),
        Text('${Strings.t(_playsGroups ? 'ac_group_of' : 'ac_word_of')
            .replaceFirst('{n}', '${i + 1}').replaceFirst('{total}', '$_blockSize')} · $_activeWpm WPM',
            style: mono),
        const SizedBox(height: 14),
        SizedBox(height: 28 * f, child: badge == null ? null : Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: badgeColor.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(14)),
          child: Text(badge, style: TextStyle(fontSize: 13, color: badgeColor)),
        )),
        const SizedBox(height: 6),
        // Earlier attempts of this word, struck through — no hint where the
        // error was. In the solution state: every attempt, numbered.
        // Fixed height in every state, sized for the solution's numbered
        // list (one 18 px line per allowed attempt), so the answer line
        // below stays put when the solution appears.
        SizedBox(height: (_typeAttempts * 18 < 22 ? 22 : _typeAttempts * 18.0) * f,
            child: Align(alignment: Alignment.bottomCenter, child: solution
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                for (var a = 0; a < attempts.length; a++)
                  SizedBox(height: 18 * f, child: Text('${a + 1}.  ${attempts[a] == null ? '— ${Strings.t('ac_type_passed')}'
                      : attempts[a]!.split('').map(_displayChar).join()}', style: mono.copyWith(fontFamily: 'CwMono'))),
              ])
            : Text([
                for (final a in attempts.take(wrong ? attempts.length - 1 : attempts.length))
                  (a ?? '').split('').map(_displayChar).join()
              ].join('   '),
                style: TextStyle(fontFamily: 'CwMono', fontSize: 16, color: c.textFaint,
                    decoration: TextDecoration.lineThrough, letterSpacing: 2)))),
        const SizedBox(height: 4),
        // Long groups/words shrink to fit instead of overflowing sideways.
        SizedBox(height: 48 * f, child: Center(
            child: FittedBox(fit: BoxFit.scaleDown, child: answer))),
        Container(width: 200, height: 2, color: correct ? c.accent
            : (wrong || solution) ? c.danger : c.border),
        const SizedBox(height: 10),
        SizedBox(height: 18 * f, child: _playing
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.graphic_eq, size: 16, color: c.accent),
                const SizedBox(width: 6),
                Text(Strings.t(_submitRequested ? 'ac_type_check_after' : 'ac_type_playing'),
                    style: TextStyle(fontSize: 12, color: c.accent)),
              ])
            : null),
      ]);
    }
    final canType = !_preparing &&
        (_typeState == _TypeState.input || _typeState == _TypeState.correct);
    return Column(children: [
      _buildHeader(context),
      Expanded(child: Center(child: SingleChildScrollView(child: center))),
      CwKeyboard(
        active: _keyboardChars,
        onKey: _onKey,
        onBackspace: _onBackspace,
        onSubmit: _onSubmit,
        onPass: _onPass,
        enabled: canType,
        submitFaded: _playing,
        haptic: _typeHaptic,
        outputCase: _outputCase,
        passLabel: Strings.t('ac_type_pass'),
        submitLabel: '⏎ ${Strings.t('ac_type_check')}',
      ),
    ]);
  }

  // Combines the old separate "sent" and "marking" screens: the word tiles
  // double as the error-marking overview (tap a word to drill into its
  // characters), so there's a single flow instead of two screens plus a
  // "mark errors" hand-off button.
  Widget _buildRevealed(BuildContext context) {
    if (_markingWordIndex != null) {
      return _buildWordMarking(context, _markingWordIndex!);
    }
    final c = AppColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(Strings.t('ac_sent_title'),
              style: TextStyle(fontSize: 18,
                  fontWeight: FontWeight.bold, color: c.textPrimary)),
          Text(Strings.t(_typing ? 'ac_sent_desc_typed' : 'ac_sent_desc'),
              style: TextStyle(fontSize: 12, color: c.textMuted)),
        ]),
      ),
      Expanded(
        child: LayoutBuilder(builder: (context, constraints) {
          // Centered when the tiles fit; otherwise scrollable, with a
          // visible scrollbar and bottom fade so it's clear there's more.
          // Tiles grow with the font size, but never below two columns.
          final tileWidth = (150 * textScaleOf(context))
              .clamp(0.0, (constraints.maxWidth - 32 - 20) / 2);
          return ScrollHint(
            center: true,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              alignment: WrapAlignment.center,
              runAlignment: WrapAlignment.center,
              spacing: 20,
              runSpacing: 16,
              children: List.generate(_sentGroups.length,
                  (i) => _buildRevealedTile(context, i, tileWidth)),
            ),
          );
        }),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: _PrimaryButton(
          label: Strings.t('ac_done_errors').replaceFirst('{n}', '${_wrongPositions.length}'),
          onTap: _finishBlock,
        ),
      ),
    ]);
  }

  // One sent group on the "revealed" screen — a fixed-width card so groups
  // wrap into as many columns as fit, instead of a single left-stuck
  // column with the rest of the middle area left empty. Characters are
  // colored by type (letter/digit/other) so mixed-content groups are
  // easier to scan. Tapping the tile opens the per-word marking screen;
  // any characters already marked wrong in it show red right here too.
  Widget _buildRevealedTile(BuildContext context, int i, double width) {
    final c = AppColors.of(context);
    final group = _sentGroups[i];
    final hasError =
        Iterable.generate(group.length).any((k) => _wrongPositions.contains('$i:$k'));
    return InkWell(
      onTap: () => _update(() => _markingWordIndex = i),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: hasError ? c.danger.withValues(alpha: 0.13) : c.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: hasError ? c.danger : c.border),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${i + 1}',
              style: TextStyle(fontSize: 11, color: c.textDisabled)),
          const SizedBox(height: 2),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            children: List.generate(group.length, (k) {
              final wrong = _wrongPositions.contains('$i:$k');
              return Text(_displayChar(group[k]),
                  style: TextStyle(fontFamily: 'CwMono', fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: wrong ? c.danger : charTypeColor(group[k], c)));
            }),
          ),
          // Typing mode: what was typed, attempt by attempt.
          if (_typing && i < _typedAttempts.length) ...[
            const SizedBox(height: 2),
            Text([
              for (final a in _typedAttempts[i])
                a == null ? '— ${Strings.t('ac_type_passed')}' : a.split('').map(_displayChar).join()
            ].join(' · '),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: c.textMuted)),
          ],
        ]),
      ),
    );
  }

  // Per-word drill-down: only this word's characters, large tap targets,
  // so marking errors doesn't mean hunting a small target among every
  // character of every word on screen at once.
  Widget _buildWordMarking(BuildContext context, int wordIndex) {
    final c = AppColors.of(context);
    final group = _sentGroups[wordIndex];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(Strings.t(_playsGroups ? 'ac_group_title' : 'ac_word_title').replaceFirst('{n}', '${wordIndex + 1}'),
              style: TextStyle(fontSize: 18,
                  fontWeight: FontWeight.bold, color: c.textPrimary)),
          Text(Strings.t('ac_mark_desc'),
              style: TextStyle(fontSize: 12, color: c.textMuted)),
        ]),
      ),
      Expanded(
        child: Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: List.generate(group.length, (i) {
              final wrong = _wrongPositions.contains('$wordIndex:$i');
              return InkWell(
                onTap: () => _toggleWrong(wordIndex, i),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 56, height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: wrong ? c.danger.withValues(alpha: 0.18) : c.surfaceAlt,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: wrong ? c.danger : c.border),
                  ),
                  child: Text(_displayChar(group[i]), style: TextStyle(fontFamily: 'CwMono',
                      fontSize: 24, fontWeight: FontWeight.bold,
                      color: wrong ? c.danger : charTypeColor(group[i], c))),
                ),
              );
            }),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: _SecondaryButton(
          label: Strings.t('ac_back'),
          onTap: () => _update(() => _markingWordIndex = null),
        ),
      ),
    ]);
  }

  Widget _buildResult(BuildContext context) {
    final c = AppColors.of(context);
    final pct = _resultTotal == 0 ? 100 : (_resultCorrect * 100 ~/ _resultTotal);
    final weak = _weakChars;
    return Column(children: [
      _buildHeader(context),
      Expanded(
        child: ScrollHint(
          center: true,
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(width: double.infinity, child: BreakHintCard()),
            ),
            Text('$pct %', style: TextStyle(fontFamily: 'DMSans', fontSize: 52,
                fontVariations: const [FontVariation('wght', 600)],
                color: pct >= 90 ? c.accent : pct >= 70 ? c.warning : c.danger)),
            Text(Strings.t('ac_correct_of')
                    .replaceFirst('{c}', '$_resultCorrect').replaceFirst('{t}', '$_resultTotal'),
                style: TextStyle(fontSize: 16, color: c.textMuted)),
            if (_trend != null) ...[
              const SizedBox(height: 10),
              Text(Strings.t('trend_line')
                      .replaceFirst('{pct}', '${_trend!.percent}')
                      .replaceFirst('{arrow}', _trend!.arrow),
                  style: TextStyle(fontSize: 13, color: c.textMuted)),
            ],
            const SizedBox(height: 20),
            _buildSpacingControl(context, scale: 1.2),
            if (weak.isNotEmpty) ...[
              const SizedBox(height: 20),
              _buildWeakCharsSection(context, scale: 1.2),
            ],
            if (_buildUnlockOutlook(context) case final outlook?) ...[
              const SizedBox(height: 20),
              outlook,
            ],
            if (_hasSuggestions) ...[
              const SizedBox(height: 20),
              Text(Strings.t('ac_suggestions_title'),
                  style: TextStyle(fontSize: 13, color: c.textMuted)),
              const SizedBox(height: 8),
              ..._buildSuggestionRows(context),
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

  // Motivation: what is still missing before the next Koch character
  // unlocks (mirrors AdaptiveCopyEngine.shouldUnlockNextChar: every active
  // char needs enough attempts AND accuracy >= high threshold).
  Widget? _buildUnlockOutlook(BuildContext context) {
    if (!widget.kochLesson ||
        widget.kochLevel >= widget.activeKochChars.length ||
        _unlockedThisBlock) {
      return null;
    }
    final c = AppColors.of(context);
    final th = _engine!.thresholds;
    final chars = kochActiveChars(widget.kochLevel, widget.activeKochChars);
    if (chars.isEmpty) return null;
    final needAttempts = <String, int>{};
    final lowAcc = <String, int>{};
    var doneAttempts = 0, wantAttempts = 0;
    for (final ch in chars) {
      final st = _charStats.stats[ch] ?? CharStat();
      final acc = 1 - st.emaErrorRate;
      if (st.attempts < th.unlockOccurrences) {
        doneAttempts += st.attempts;
        wantAttempts += th.unlockOccurrences;
        needAttempts[ch] = th.unlockOccurrences - st.attempts;
      } else if (acc < th.highThreshold) {
        lowAcc[ch] = (acc * 100).round();
      }
    }
    // Bar = repetitions still owed, summed over the chars that lack them;
    // if only accuracy is missing, it shows accuracy vs. threshold.
    double progress;
    if (wantAttempts > 0) {
      progress = doneAttempts / wantAttempts;
    } else {
      final worst = lowAcc.values.fold<int>(100, (m, v) => v < m ? v : m);
      progress = (worst / 100 / th.highThreshold).clamp(0.0, 1.0);
    }
    final next = _displayChar(widget.activeKochChars[widget.kochLevel]);
    // One chip per character, so an entry never breaks across lines; most
    // repetitions owed / lowest accuracy first, capped so a bad block
    // doesn't turn the card into a wall.
    const maxChips = 10;
    Widget chips(List<String> items) {
      final shown = items.take(maxChips).toList();
      return Wrap(spacing: 6, runSpacing: 6, children: [
        for (final t in shown) Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
          child: Text(t, style: TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.textPrimary)),
        ),
        if (items.length > maxChips) Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(Strings.t('ac_outlook_more').replaceFirst('{n}', '${items.length - maxChips}'),
              style: TextStyle(fontSize: 13, color: c.textMuted)),
        ),
      ]);
    }
    final sections = <(String, List<String>)>[];
    if (needAttempts.isNotEmpty) {
      final e = needAttempts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      sections.add((Strings.t('ac_outlook_attempts'),
          [for (final x in e) '${_displayChar(x.key)} ${x.value}']));
    }
    if (lowAcc.isNotEmpty) {
      final e = lowAcc.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
      sections.add((Strings.t('ac_outlook_accuracy')
          .replaceFirst('{pct}', '${(th.highThreshold * 100).round()}'),
          [for (final x in e) '${_displayChar(x.key)} ${x.value} %']));
    }
    final mono = TextStyle(fontSize: 13, color: c.textMuted);
    return SizedBox(
      width: double.infinity,
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(Strings.t('ac_outlook_title').replaceFirst('{ch}', next),
              style: TextStyle(fontSize: 14,
                  fontWeight: FontWeight.bold, color: c.textPrimary)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: c.background,
              valueColor: AlwaysStoppedAnimation(c.accent),
            ),
          ),
          for (final (label, items) in sections) ...[
            const SizedBox(height: 10),
            Text(label, style: mono),
            const SizedBox(height: 6),
            chips(items),
          ],
        ]),
      ),
    );
  }

  // Result screen sits in a mainAxisSize.min Center column, so rows here
  // get loose (not stretched) width constraints — size explicitly instead
  // of relying on Expanded, which would need a bounded incoming width.
  List<Widget> _buildSuggestionRows(BuildContext context) {
    final rowWidth = MediaQuery.of(context).size.width - 32;
    final rows = <Widget>[];
    // Unlock goes first and stands out (star icon, bolder styling) — it's a
    // bigger deal than a tempo/spacing nudge, and names the actual character
    // so it's clear what's being proposed, not just that "something" unlocked.
    if (_unlockedThisBlock) {
      final nextChar = widget.kochLevel < widget.activeKochChars.length
          ? widget.activeKochChars[widget.kochLevel]
          : null;
      rows.add(SuggestionRow(
        width: rowWidth,
        accepted: _acceptUnlock,
        onToggle: (v) => _update(() => _acceptUnlock = v),
        label: nextChar == null
            ? Strings.t('ac_char_unlocked')
            : '${Strings.t('ac_char_unlocked')}: "${_displayChar(nextChar)}"',
        highlight: true,
        // Lets the user hear the brand-new character right here, without
        // leaving Adaptive Copy for the separate Learn New Chr screen — user
        // feedback 2026-09-22: they want to stay "im Lern-Flow". Plays
        // in-place over the same channels _startBlock() already uses.
        onPreview: nextChar == null || _previewingNewChar ? null : () => _previewNewChar(nextChar),
      ));
    }
    if (_pendingWpm != null) {
      rows.add(SuggestionRow(
        width: rowWidth,
        accepted: _acceptCharSpeed,
        onToggle: (v) => _update(() => _acceptCharSpeed = v),
        label: '${Strings.t('ac_char_speed_up')}: $_wpmBefore→${_acceptCharSpeed ? _pendingWpm : _wpmBefore}',
        onDecrement: _acceptCharSpeed ? () => _stepPendingWpm(-1) : null,
        onIncrement: _acceptCharSpeed ? () => _stepPendingWpm(1) : null,
      ));
    }
    if (_pendingInterChar != null) {
      final spacingWpm = (_acceptCharSpeed && _pendingWpm != null) ? _pendingWpm! : (_wpmBefore ?? widget.wpm);
      final label = _lastDecision!.spacingStep == TempoStep.up
          ? Strings.t('ac_spacing_up')
          : Strings.t('ac_spacing_down');
      rows.add(SuggestionRow(
        width: rowWidth,
        accepted: _acceptSpacing,
        onToggle: (v) => _update(() => _acceptSpacing = v),
        label: '$label: $_interCharBefore→${_acceptSpacing ? _pendingInterChar : _interCharBefore} '
            '(${ditsToSeconds(_acceptSpacing ? _pendingInterChar! : _interCharBefore!, spacingWpm)})'
            '${_typing ? '' : ' / '
            '$_interWordBefore→${_acceptSpacing ? _pendingInterWord : _interWordBefore} '
            '(${ditsToSeconds(_acceptSpacing ? _pendingInterWord! : _interWordBefore!, spacingWpm)})'}',
        onDecrement: _acceptSpacing ? () => _stepPendingSpacing(-1) : null,
        onIncrement: _acceptSpacing ? () => _stepPendingSpacing(1) : null,
      ));
    }
    return rows;
  }
}
