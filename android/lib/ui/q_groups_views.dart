part of 'q_groups_screen.dart';

extension _QGroupsViews on _QGroupsScreenState {
  Widget _body(AppColors c) => switch (_phase) {
        _Phase.setup => _setupView(c),
        _Phase.ask => _askView(c),
        _Phase.result => _resultView(c),
      };

  TextStyle _mono(Color color, double size, {bool bold = false}) =>
      TextStyle(fontSize: size, color: color, fontWeight: bold ? FontWeight.bold : null);

  TextStyle _morse(Color color, double size, {bool bold = false}) =>
      TextStyle(fontFamily: 'CwMono', fontSize: size, color: color, fontWeight: bold ? FontWeight.bold : null);

  String _fill(String key, Map<String, Object> values) {
    var s = Strings.t(key);
    values.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    return s;
  }

  int _groupsUpTo(int level) => qGroups.where((g) => g.level <= level).length;

  // ---- setup ----

  Widget _setupView(AppColors c) {
    final rate = hcRecentRate(_results);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        AppCard(child: Text(Strings.t('qg_rules'), style: _mono(c.textMuted, 12))),
        const SizedBox(height: 12),
        SettingsCard(children: [
          SegmentRow(
            label: Strings.t('qg_lang_label'),
            options: [Strings.t('hc_lang_de'), Strings.t('hc_lang_en')],
            selected: _s.lang,
            onChanged: (i) => _update(() => _s.lang = i),
          ),
          const SettingsDivider(),
          SegmentRow(
            label: Strings.t('qg_level_label'),
            options: [for (var l = 1; l <= qgLevels; l++) '$l'],
            selected: _s.level - 1,
            onChanged: (i) => _update(() => _s.level = i + 1),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(_fill('qg_level_desc_${_s.level}', {'n': _groupsUpTo(_s.level)}),
                style: _mono(c.textFaint, 11)),
          ),
          const SettingsDivider(),
          SegmentRow(
            label: Strings.t('qg_count_label'),
            options: [for (final n in QgSettings.counts) '$n'],
            selected: QgSettings.counts.indexOf(_s.count),
            onChanged: (i) => _update(() => _s.count = QgSettings.counts[i]),
          ),
          const SettingsDivider(),
          TempoSpacingSection(
            wpm: _s.wpm,
            interChar: _s.interChar,
            interWord: _s.interWord,
            onWpm: (v) => _update(() => _s.wpm = v),
            onSpacing: (ic, iw) => _update(() {
              _s.interChar = ic;
              _s.interWord = iw;
            }),
          ),
        ]),
        const SizedBox(height: 12),
        Text(
          rate == null ? Strings.t('hc_no_rounds') : _fill('hc_recent', {'p': (rate * 100).round()}),
          style: _mono(c.textFaint, 12),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        AppButton(label: Strings.t('hc_start'), icon: Icons.play_arrow_rounded, color: c.accent, onTap: _startRound),
        const SizedBox(height: 10),
        AppButton(
            label: Strings.t('qg_sheet'),
            icon: Icons.menu_book_outlined,
            color: c.info,
            primary: false,
            onTap: _openSheet),
      ],
    );
  }

  // ---- questions ----

  Widget _askView(AppColors c) {
    final r = _round!;
    final q = r.questions[_q];
    final last = _q == r.questions.length - 1;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(children: [
          Expanded(
            child: Text(_fill('hc_question_n', {'n': _q + 1, 'm': r.questions.length}),
                style: _mono(c.textFaint, 12)),
          ),
          IconButton(
            tooltip: _playing ? Strings.t('stop') : Strings.t('hc_replay'),
            icon: Icon(_playing ? Icons.stop_circle_outlined : Icons.replay_rounded, color: c.info),
            onPressed: _playing ? _stop : _playQuestion,
          ),
        ]),
        AppCard(
          child: Column(children: [
            Icon(_playing ? Icons.graphic_eq_rounded : Icons.headphones_rounded, size: 40, color: c.accent),
            const SizedBox(height: 8),
            // The group stays hidden until it is answered.
            Text(_picked == null ? '?' : q.cwText,
                style: _morse(_picked == null ? c.textFaint : c.textPrimary, 26, bold: true)),
            const SizedBox(height: 4),
            Text(Strings.t('qg_prompt'), style: _mono(c.textMuted, 13)),
          ]),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < q.options.length; i++) ...[
          _optionTile(c, q, i),
          const SizedBox(height: 8),
        ],
        if (_picked != null) ...[
          const SizedBox(height: 4),
          AppButton(
            label: Strings.t(last ? 'hc_finish' : 'hc_next'),
            icon: last ? Icons.flag_outlined : Icons.arrow_forward_rounded,
            color: c.accent,
            onTap: _next,
          ),
        ],
      ],
    );
  }

  Widget _optionTile(AppColors c, QgQuestion q, int i) {
    final picked = _picked;
    final isRight = i == q.correct;
    final isWrongPick = picked == i && !isRight;
    final Color color = picked == null
        ? c.textPrimary
        : isRight
            ? c.accent
            : isWrongPick
                ? c.danger
                : c.textFaint;
    return Material(
      color: picked != null && (isRight || isWrongPick) ? color.withValues(alpha: 0.15) : c.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: picked == null ? () => _pick(i) : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: picked != null && (isRight || isWrongPick) ? color : c.border, width: 0.8),
          ),
          child: Row(children: [
            Expanded(child: Text(q.options[i], style: _mono(color, 15))),
            if (picked != null && isRight) Icon(Icons.check_rounded, color: color),
            if (isWrongPick) Icon(Icons.close_rounded, color: color),
          ]),
        ),
      ),
    );
  }

  // ---- result ----

  Widget _resultView(AppColors c) {
    final r = _round!;
    final res = _last!;
    final percent = (res.rate * 100).round();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        AppCard(
          child: Column(children: [
            Text(Strings.t('hc_result_title').toUpperCase(), style: _mono(c.textFaint, 12)),
            const SizedBox(height: 6),
            Text('$percent %', style: _mono(percent >= 70 ? c.accent : c.warning, 40, bold: true)),
            Text(_fill('hc_result_rate', {'r': res.right, 'n': res.total, 'p': percent}),
                style: _mono(c.textMuted, 13)),
          ]),
        ),
        const SizedBox(height: 12),
        AppCaption(Strings.t('qg_answers_tap')),
        const SizedBox(height: 6),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < r.questions.length; i++) _answerRow(c, r.questions[i], _answers[i], i),
          ]),
        ),
        const SizedBox(height: 16),
        AppButton(label: Strings.t('hc_new_round'), icon: Icons.refresh_rounded, color: c.accent, onTap: _startRound),
        const SizedBox(height: 10),
        AppButton(
            label: Strings.t('qg_sheet'),
            icon: Icons.menu_book_outlined,
            color: c.info,
            primary: false,
            onTap: _openSheet),
        const SizedBox(height: 10),
        AppButton(label: Strings.t('qg_title'), icon: Icons.tune_rounded, color: c.textMuted, primary: false, onTap: _toSetup),
      ],
    );
  }

  /// One answered question; tapping it plays the group again.
  Widget _answerRow(AppColors c, QgQuestion q, int answer, int index) {
    final ok = answer == q.correct;
    final color = ok ? c.accent : c.danger;
    final playing = _playingIdx == index;
    return InkWell(
      onTap: () => playing ? _stop() : _playQuestion(index),
      child: Padding(
        padding: EdgeInsets.only(top: index == 0 ? 0 : 10, bottom: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(ok ? Icons.check_rounded : Icons.close_rounded, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(q.cwText, style: _morse(playing ? c.accent : c.textPrimary, 15, bold: true)),
              Text(q.answer, style: _mono(c.textMuted, 13)),
              if (!ok) Text(q.options[answer], style: _mono(c.danger, 12)),
            ]),
          ),
          Icon(playing ? Icons.stop_rounded : Icons.play_arrow_rounded, color: c.info, size: 22),
        ]),
      ),
    );
  }
}
