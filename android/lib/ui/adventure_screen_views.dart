// Body, transcript, controls and end panel of the adventure screen. Split out of adventure_screen.dart; same library.
part of 'adventure_screen.dart';

extension _AdventureViews on _AdventureScreenState {
  Widget _body(AppColors c) {
    final z = _z!;
    final st = z.status;
    final ended = z.state == ZState.quit;
    return Column(children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(color: c.surfaceAlt,
            border: Border.symmetric(horizontal: BorderSide(color: c.border))),
        child: Row(children: [
          Expanded(child: Text(st.room, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.logText))),
          Text('Score ${st.score} · Moves ${st.moves}',
              style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.logText)),
        ]),
      ),
      Expanded(child: _transcript(c)),
      // Short screens: the ⏱ icon still opens the speed sheet.
      if (!_compact) _tempoStrip(c),
      _controls(c),
      if (ended) _endPanel(c) else ..._inputArea(c),
    ]);
  }

  Widget _transcript(AppColors c) {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      itemCount: _log.length,
      itemBuilder: (context, i) {
        final e = _log[i];
        final style = TextStyle(fontFamily: 'CwMono', fontSize: 14, height: 1.4, color: c.logText);
        Widget child;
        if (e.kind == LogEntry.command) {
          child = Text('> ${e.text}', style: style.copyWith(color: c.accent));
        } else if (e.kind == LogEntry.banner) {
          child = Text(e.text, style: style.copyWith(color: c.textFaint, fontSize: 12));
        } else if (e.kind == LogEntry.info) {
          child = Text('— ${e.text} —', style: style.copyWith(color: c.textFaint, fontSize: 12));
        } else if (i == _curEntry && _passage != null) {
          child = _currentAnswer(c, style.copyWith(color: c.textPrimary, fontSize: 15));
        } else {
          child = Text(e.text, style: style);
        }
        return Padding(
            key: i == _curEntry ? _curKey : null,
            padding: const EdgeInsets.only(bottom: 10), child: child);
      },
    );
  }

  Widget _currentAnswer(AppColors c, TextStyle base) {
    final p = _passage!;
    if (_s.show == 2 && !_revealed) {
      return GestureDetector(
        onTap: () => _update(() => _revealed = true),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.border)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.visibility_outlined, size: 18, color: c.textMuted),
            const SizedBox(width: 8),
            Text(Strings.t('adv_tap_reveal'),
                style: TextStyle(fontSize: 13, color: c.textMuted)),
          ]),
        ),
      );
    }
    final cur = _currentWord;
    final spans = <InlineSpan>[];
    var line = 0;
    for (var i = 0; i < p.words.length; i++) {
      final w = p.words[i];
      if (i > 0) {
        if (w.line != line) {
          spans.add(TextSpan(text: '\n' * (w.line - line)));
        } else {
          spans.add(const TextSpan(text: ' '));
        }
      }
      line = w.line;
      final played = w.inScope && w.cw.isNotEmpty;
      final hidden = played && !_revealed && !_heard.contains(i);
      var st = base;
      if (!w.inScope) st = st.copyWith(color: c.textMuted, fontStyle: FontStyle.italic);
      if (hidden) {
        st = st.copyWith(color: Colors.transparent,
            decoration: TextDecoration.underline,
            decorationColor: i == cur ? c.accent : c.textDisabled,
            decorationThickness: 2);
      } else if (i == cur) {
        st = st.copyWith(backgroundColor: c.accent.withValues(alpha: 0.3));
      }
      spans.add(TextSpan(
        text: w.display,
        style: st,
        recognizer: played && !hidden
            ? (TapGestureRecognizer()..onTap = () => _play(from: i, to: i))
            : null,
      ));
    }
    return Text.rich(TextSpan(children: spans), style: base);
  }

  Widget _tempoStrip(AppColors c) {
    Widget item(String l, String v) => Text.rich(TextSpan(children: [
          TextSpan(text: '$l ', style: TextStyle(color: c.textMuted)),
          TextSpan(text: v, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold)),
        ]), style: const TextStyle(fontFamily: 'CwMono', fontSize: 12));
    return GestureDetector(
      onTap: _openTempo,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(10)),
        // Shrinks instead of overflowing at large font sizes.
        child: LayoutBuilder(builder: (context, box) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: box.maxWidth),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              item(Strings.t('adv_hear'), '${_s.wpm}'),
              const SizedBox(width: 12),
              item(Strings.t('adv_give'), '${_s.keyWpm}'),
              const SizedBox(width: 12),
              item(Strings.t('adv_strip_char'), '${_s.interChar}'),
              const SizedBox(width: 12),
              item(Strings.t('adv_strip_word'), '${_s.interWord}'),
            ]),
          ),
        )),
      ),
    );
  }

  Widget _controls(AppColors c) {
    Widget small(IconData icon, String label, VoidCallback? onTap) => Expanded(
          child: Material(
            color: c.surface,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: SizedBox(height: 50, child: Center(child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 20, color: onTap == null ? c.textDisabled : c.textPrimary),
                  Text(label, style: TextStyle(fontSize: 10,
                      color: onTap == null ? c.textDisabled : c.textMuted)),
                ]),
              ))),
            ),
          ),
        );
    final canPlay = _passage?.hasAudio ?? false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(children: [
        Expanded(
          flex: 2,
          child: Material(
            color: canPlay ? c.accent : c.surface,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: canPlay ? _againSentence : null,
              onLongPress: canPlay ? _again : null,
              child: SizedBox(height: 50, child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.replay, color: canPlay ? c.background : c.textDisabled),
                  const SizedBox(width: 8),
                  Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(Strings.t('adv_again'),
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold,
                          color: canPlay ? c.background : c.textDisabled)))),
                ],
              )),
            ),
          ),
        ),
        const SizedBox(width: 6),
        _pausedAt != null
            ? small(Icons.play_arrow, Strings.t('adv_resume'), _resume)
            : small(Icons.pause, Strings.t('adv_pause'), _playing ? _pause : null),
        const SizedBox(width: 6),
        small(_textVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            Strings.t('adv_text'), _passage == null ? null : _toggleText),
        const SizedBox(width: 6),
        small(Icons.undo, Strings.t('adv_undo'), _undo.isEmpty ? null : _undoMove),
      ]),
    );
  }

  List<Widget> _inputArea(AppColors c) {
    final paddle = _s.input == 0;
    final hint = paddle ? Strings.t(const ['adv_key_hint_ar', 'adv_key_hint_k', 'adv_key_hint_btn'][_s.send])
        : Strings.t('adv_keys_hint');
    return [
      Container(
        margin: EdgeInsets.fromLTRB(12, 8, 12, _compact ? 6 : 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        width: double.infinity,
        decoration: BoxDecoration(color: c.surfaceDark, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Text('> ', style: TextStyle(fontFamily: 'CwMono', fontSize: 16, color: c.accent)),
          // The end of the line stays visible while a long command grows.
          Expanded(child: LayoutBuilder(builder: (context, box) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: box.maxWidth),
              child: Text.rich(TextSpan(children: [
                TextSpan(text: _input, style: TextStyle(color: c.textPrimary)),
                if (_elements.isNotEmpty) TextSpan(text: _elements, style: TextStyle(color: c.warning)),
              ]), maxLines: 1, style: const TextStyle(fontFamily: 'CwMono', fontSize: 16)),
            ),
          ))),
        ]),
      ),
      if (!_compact) Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
        child: Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: c.textFaint)),
      ),
      if (paddle) ..._paddleInput(c) else CwKeyboard(
        active: _keyboardKeys,
        outputCase: 1,
        passLabel: '␣',
        submitLabel: '⏎',
        onKey: (k) => _update(() => _input += k),
        onBackspace: () => _update(() {
          if (_input.isNotEmpty) _input = _input.substring(0, _input.length - 1);
        }),
        onPass: () => _update(() {
          if (_input.isNotEmpty && !_input.endsWith(' ')) _input += ' ';
        }),
        onSubmit: _submit,
      ),
    ];
  }

  List<Widget> _paddleInput(AppColors c) {
    Widget btn(IconData icon, String label, VoidCallback? onTap, {Color? color}) => Expanded(
          child: Material(
            color: color ?? c.surface,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onTap,
              child: SizedBox(height: 40, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 18, color: color != null ? c.background : c.textMuted),
                const SizedBox(width: 6),
                Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(label,
                    style: TextStyle(fontSize: 13,
                        fontWeight: color != null ? FontWeight.bold : FontWeight.normal,
                        color: color != null ? c.background : c.textMuted)))),
              ])),
            ),
          ),
        );
    final has = _input.trim().isNotEmpty;
    return [
      Padding(
        padding: EdgeInsets.fromLTRB(12, _compact ? 0 : 2, 12, 8),
        child: Row(children: [
          btn(Icons.backspace_outlined, Strings.t('adv_del_word'), has ? _deleteWord : null),
          const SizedBox(width: 6),
          btn(Icons.clear, Strings.t('adv_clear_line'), has ? () => _update(() => _input = '') : null),
          const SizedBox(width: 6),
          btn(Icons.keyboard_return, Strings.t('adv_send'), has ? _submit : null,
              color: has ? c.accent : null),
        ]),
      ),
      if (_keyerMode == 4)
        StraightKeyPaddle(
            onDown: () => _setTouch(dit: true),
            onUp: () => _setTouch(dit: false))
      else
        IambicPaddles(
          onDitDown: () => _setTouch(dit: true),
          onDitUp: () => _setTouch(dit: false),
          onDahDown: () => _setTouch(dah: true),
          onDahUp: () => _setTouch(dah: false),
        ),
      SizedBox(height: 12 + MediaQuery.of(context).padding.bottom),
    ];
  }

  static final Set<String> _keyboardKeys = {
    ...'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'.split(''),
    '.', ',', '?', '-',
  };

  Widget _endPanel(AppColors c) {
    final st = _z!.status;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(Strings.t('adv_end_title'),
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                color: c.textPrimary)),
        const SizedBox(height: 4),
        Text(Strings.t('adv_end_body').replaceAll('{s}', '${st.score}').replaceAll('{m}', '${st.moves}'),
            style: TextStyle(fontSize: 13, color: c.textMuted)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: AppButton(label: Strings.t('adv_load_save'), color: c.accent, onTap: _openSaves)),
          const SizedBox(width: 8),
          Expanded(child: AppButton(label: Strings.t('adv_undo_menu'), color: c.info,
              onTap: _undo.isEmpty ? null : _undoMove)),
        ]),
        const SizedBox(height: 8),
        AppButton(label: Strings.t('adv_restart'), color: c.danger, onTap: _restart),
      ]),
    );
  }
}
