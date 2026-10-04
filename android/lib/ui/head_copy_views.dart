part of 'head_copy_screen.dart';

extension _HeadCopyViews on _HeadCopyScreenState {
  Widget _body(AppColors c) => switch (_phase) {
        _Phase.setup => _setupView(c),
        _Phase.listen => _listenView(c),
        _Phase.ask => _askView(c),
        _Phase.result => _resultView(c),
      };

  TextStyle _mono(Color color, double size, {bool bold = false}) =>
      TextStyle(fontFamily: 'CwMono', fontSize: size, color: color, fontWeight: bold ? FontWeight.bold : null);

  String _fill(String key, Map<String, Object> values) {
    var s = Strings.t(key);
    values.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    return s;
  }

  // ---- setup ----

  Widget _setupView(AppColors c) {
    final rate = hcRecentRate(_results);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        AppCard(child: Text(Strings.t('hc_rules'), style: _mono(c.textMuted, 12))),
        const SizedBox(height: 12),
        SettingsCard(children: [
          SegmentRow(
            label: Strings.t('hc_lang_label'),
            options: [Strings.t('hc_lang_de'), Strings.t('hc_lang_en')],
            selected: _s.lang,
            onChanged: (i) => _update(() => _s.lang = i),
          ),
          const SettingsDivider(),
          SegmentRow(
            label: Strings.t('hc_level_label'),
            options: [Strings.t('hc_level_1'), Strings.t('hc_level_2'), Strings.t('hc_level_3')],
            selected: _s.level - 1,
            onChanged: (i) => _update(() => _s.level = i + 1),
          ),
          const SettingsDivider(),
          LabeledSlider(
            label: Strings.t('hc_speed'),
            display: '${_s.wpm} WPM',
            value: _s.wpm.toDouble(),
            min: TrainingProfile.minWpm.toDouble(),
            max: 40,
            divisions: 40 - TrainingProfile.minWpm,
            onChanged: (v) => _update(() => _s.wpm = v.round()),
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
      ],
    );
  }

  // ---- listening ----

  Widget _listenView(AppColors c) {
    final r = _round!;
    final status = _playing && _playingIdx >= 0
        ? _fill('hc_listen_n', {'n': _playingIdx + 1, 'm': r.sentences.length})
        : Strings.t('hc_replay');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(children: [
        Expanded(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(_playing ? Icons.graphic_eq_rounded : Icons.headphones_rounded, size: 72, color: c.accent),
              const SizedBox(height: 16),
              Text(_playing ? Strings.t('hc_listening') : '', style: _mono(c.textPrimary, 18)),
              const SizedBox(height: 6),
              Text(_playing ? status : '', style: _mono(c.textMuted, 13)),
            ]),
          ),
        ),
        AppButton(
          label: _playing ? Strings.t('stop') : Strings.t('hc_replay'),
          icon: _playing ? Icons.stop_rounded : Icons.replay_rounded,
          color: c.info,
          primary: false,
          onTap: _playing ? _stop : _playRound,
        ),
        const SizedBox(height: 10),
        AppButton(label: Strings.t('hc_to_questions'), icon: Icons.quiz_outlined, color: c.accent, onTap: _toQuestions),
      ]),
    );
  }

  // ---- questions ----

  String _sentenceLabel(int index) =>
      _round!.sentences.length > 1 ? '${_fill('hc_sentence_n', {'n': index + 1})} ' : '';

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
            onPressed: _playing ? _stop : _playRound,
          ),
        ]),
        AppCard(
          child: Text('${_sentenceLabel(q.sentence)}${q.prompt}', style: _mono(c.textPrimary, 17)),
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

  Widget _optionTile(AppColors c, HcQuestion q, int i) {
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
        AppCaption(Strings.t('hc_sentences')),
        const SizedBox(height: 6),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < r.sentences.length; i++)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                child: Text(
                  '${_sentenceLabel(i)}${r.sentences[i].text}',
                  style: _mono(_playingIdx == i ? c.accent : c.textPrimary, 15, bold: _playingIdx == i),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        AppButton(
          label: _playing ? Strings.t('stop') : Strings.t('hc_play_follow'),
          icon: _playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
          color: c.info,
          primary: false,
          onTap: _playing ? _stop : _playRound,
        ),
        const SizedBox(height: 12),
        AppCaption(Strings.t('hc_answers')),
        const SizedBox(height: 6),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < r.questions.length; i++) _answerRow(c, r.questions[i], _answers[i], i == 0),
          ]),
        ),
        const SizedBox(height: 16),
        AppButton(label: Strings.t('hc_new_round'), icon: Icons.refresh_rounded, color: c.accent, onTap: _startRound),
        const SizedBox(height: 10),
        AppButton(label: Strings.t('hc_title'), icon: Icons.tune_rounded, color: c.textMuted, primary: false, onTap: _toSetup),
      ],
    );
  }

  Widget _answerRow(AppColors c, HcQuestion q, int answer, bool first) {
    final ok = answer == q.correct;
    final color = ok ? c.accent : c.danger;
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(ok ? Icons.check_rounded : Icons.close_rounded, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_sentenceLabel(q.sentence)}${q.prompt}', style: _mono(c.textMuted, 12)),
            Text(q.answer, style: _mono(c.textPrimary, 14)),
            if (!ok) Text(q.options[answer], style: _mono(c.danger, 12)),
          ]),
        ),
      ]),
    );
  }
}
