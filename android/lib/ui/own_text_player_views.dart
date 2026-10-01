// Text, tempo strip, controls and settings sheet of the own-texts player.
// Split out of own_text_player_screen.dart; same library.
part of 'own_text_player_screen.dart';

extension _OwnTextPlayerViews on _OwnTextPlayerScreenState {
  Widget _body(AppColors c) {
    final p = _p!;
    return Column(children: [
      _tempoStrip(c),
      Expanded(child: PinchZoomFontSize(
        prefsKey: 'ownTextFont',
        initialSize: 16,
        minSize: 12,
        maxSize: 36,
        builder: (context, size) => _textArea(c, size),
      )),
      LinearProgressIndicator(
        value: p.words.isEmpty ? 0 : _pos / p.words.length,
        minHeight: 3,
        color: c.accent,
        backgroundColor: c.border,
      ),
      _controls(c),
    ]);
  }

  Widget _tempoStrip(AppColors c) {
    void set(int v) {
      _s.wpm = v.clamp(TrainingProfile.minWpm, 60);
      _onSettingsChanged();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline), color: c.accent,
          tooltip: Strings.t('ot_slower'),
          onPressed: _s.wpm > TrainingProfile.minWpm ? () => set(_s.wpm - 1) : null,
        ),
        Expanded(child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: c.accent, inactiveTrackColor: c.border,
            thumbColor: c.accent, overlayColor: c.accent.withValues(alpha: 0.1),
            trackHeight: 3,
          ),
          child: Slider(
            value: _s.wpm.toDouble(),
            min: TrainingProfile.minWpm.toDouble(), max: 60,
            divisions: 60 - TrainingProfile.minWpm,
            onChanged: (v) => set(v.round()),
          ),
        )),
        IconButton(
          icon: const Icon(Icons.add_circle_outline), color: c.accent,
          tooltip: Strings.t('ot_faster'),
          onPressed: _s.wpm < 60 ? () => set(_s.wpm + 1) : null,
        ),
        SizedBox(width: 62, child: Text('${_s.wpm} WPM', textAlign: TextAlign.right,
            style: TextStyle(fontFamily: 'CwMono', fontSize: 12, color: c.accent))),
      ]),
    );
  }

  Widget _textArea(AppColors c, double size) {
    if (!_textShown) {
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GestureDetector(
            onTap: () => _update(() => _revealed = true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.border)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.visibility_outlined, size: 18, color: c.textMuted),
                const SizedBox(width: 8),
                Text(Strings.t('adv_tap_reveal'),
                    style: TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.textMuted)),
              ]),
            ),
          ),
        ),
      );
    }
    final base = TextStyle(fontFamily: 'CwMono', fontSize: size, height: 1.45, color: c.logText);
    return SingleChildScrollView(
      key: _scrollKey,
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final para in _paras) ...[
          if (para.gapBefore) SizedBox(height: size),
          _paragraph(c, para, base),
          SizedBox(height: size * 0.35),
        ],
      ]),
    );
  }

  Widget _paragraph(AppColors c, _Para para, TextStyle base) {
    final p = _p!;
    final spans = <InlineSpan>[];
    for (var k = 0; k < para.words.length; k++) {
      final i = para.words[k];
      final w = p.words[i];
      if (k > 0) spans.add(const TextSpan(text: ' '));
      final hidden = w.cw.isNotEmpty && !_revealed && _s.show == 1 && !_heard.contains(i);
      var st = base;
      if (w.cw.isEmpty) st = st.copyWith(color: c.textMuted);
      if (hidden) {
        st = st.copyWith(color: Colors.transparent,
            decoration: TextDecoration.underline,
            decorationColor: i == _pos ? c.accent : c.textDisabled,
            decorationThickness: 2);
      }
      if (i == _pos) {
        st = st.copyWith(backgroundColor: c.accent.withValues(alpha: _playing ? 0.3 : 0.14));
      }
      spans.add(TextSpan(text: w.display, style: st));
    }
    final key = _paraKeys.putIfAbsent(para.line, () => GlobalKey());
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        final ro = _OwnTextPlayerScreenState._findParagraph(key.currentContext?.findRenderObject());
        if (ro == null) return;
        final offset = ro.getPositionForOffset(d.localPosition).offset;
        var k = 0;
        for (var j = 0; j < para.starts.length; j++) {
          if (para.starts[j] <= offset) k = j;
        }
        _onTapWord(para.words[k]);
      },
      child: Text.rich(TextSpan(children: spans), key: key, style: base),
    );
  }

  Widget _controls(AppColors c) {
    Widget round(IconData icon, String tip, VoidCallback? onTap, {bool big = false}) {
      final d = big ? 64.0 : 48.0;
      return Tooltip(message: tip, child: Material(
        color: big ? c.accent.withValues(alpha: 0.18) : c.surface,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: d, height: d,
              child: Icon(icon, size: big ? 34 : 24, color: big ? c.accent : c.textMuted)),
        ),
      ));
    }
    return SafeArea(top: false, child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(child: AppButton(label: Strings.t('ot_word'), icon: Icons.replay, height: 44,
              color: c.accent, primary: false, onTap: _repeatWord)),
          const SizedBox(width: 8),
          Expanded(child: AppButton(label: Strings.t('ot_sentence'), icon: Icons.replay, height: 44,
              color: c.accent, primary: false, onTap: _repeatSentence)),
          const SizedBox(width: 8),
          Expanded(child: AppButton(label: Strings.t('ot_restart'), icon: Icons.first_page, height: 44,
              color: c.accent, primary: false, onTap: _restartText)),
        ]),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          round(Icons.skip_previous, Strings.t('ot_sentence_back'), _sentenceBack),
          round(Icons.chevron_left, Strings.t('ot_word_back'), _wordBack),
          round(_playing ? Icons.pause : Icons.play_arrow,
              Strings.t(_playing ? 'ot_pause' : 'ot_play'), _togglePlay, big: true),
          round(Icons.chevron_right, Strings.t('ot_word_fwd'), _wordForward),
          round(Icons.skip_next, Strings.t('ot_sentence_fwd'), _sentenceForward),
        ]),
      ]),
    ));
  }

  Future<void> _openSettings() {
    final c = AppColors.of(context);
    return showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        void change(VoidCallback f) {
          setSt(f);
          _onSettingsChanged();
        }
        Widget stepper(String label, String value, String sub, VoidCallback? minus, VoidCallback? plus) =>
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(fontFamily: 'CwMono', fontSize: 13, color: c.textPrimary)),
                Text(sub, style: TextStyle(fontFamily: 'CwMono', fontSize: 11, color: c.textFaint)),
              ])),
              IconButton(icon: const Icon(Icons.remove_circle_outline), color: c.accent, onPressed: minus),
              SizedBox(width: 50, child: Text(value, textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'CwMono', fontSize: 14, color: c.accent,
                      fontWeight: FontWeight.bold))),
              IconButton(icon: const Icon(Icons.add_circle_outline), color: c.accent, onPressed: plus),
            ]);
        final s = _s;
        return SafeArea(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2)))),
            Text(Strings.t('ot_settings'),
                style: TextStyle(fontFamily: 'CwMono', fontSize: 16, color: c.textPrimary,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            SettingsSectionHeader(Strings.t('adv_tempo').toUpperCase()),
            stepper(Strings.t('settings_char_spacing'), '${s.interChar}',
                'Dits · ${ditsToSeconds(s.interChar, s.wpm)}',
                s.interChar > 3 ? () => change(() => s.interChar--) : null,
                s.interChar < 45
                    ? () => change(() {
                          s.interChar++;
                          if (s.interWord < s.interChar) s.interWord = s.interChar;
                        })
                    : null),
            stepper(Strings.t('settings_word_spacing'), '${s.interWord}',
                'Dits · ${ditsToSeconds(s.interWord, s.wpm)}',
                s.interWord > 6 && s.interWord > s.interChar ? () => change(() => s.interWord--) : null,
                s.interWord < 105 ? () => change(() => s.interWord++) : null),
            const SizedBox(height: 8),
            SettingsSectionHeader(Strings.t('adv_show').toUpperCase()),
            SegmentRow(
              label: '',
              options: [Strings.t('adv_show_always'), Strings.t('adv_show_after'), Strings.t('adv_show_tap')],
              selected: s.show,
              onChanged: (i) => change(() {
                s.show = i;
                _revealed = false;
              }),
            ),
            Padding(padding: const EdgeInsets.only(top: 4),
                child: Text(Strings.t('ot_show_desc'),
                    style: TextStyle(fontFamily: 'CwMono', fontSize: 11, color: c.textFaint))),
          ]),
        ));
      }),
    );
  }
}
