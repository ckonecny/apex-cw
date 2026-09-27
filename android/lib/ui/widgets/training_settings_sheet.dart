import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../content/cw_content.dart';
import '../../content/echo_suggestions.dart';
import '../../content/training_profile.dart';
import '../../content/charset_content.dart';
import 'charset_header.dart';
import '../../l10n/strings.dart';
import '../../theme/app_colors.dart';
import 'setting_rows.dart';

/// Parts of the per-training settings a screen can show, see
/// docs/training/P3-einstellungen-in-screens.md.
enum TrainingSection { content, spacing, wordSpacing, wordSelection, echoFlow, hearFlow, adaptive, kochSequence }

/// Opens the settings sheet for one training profile ([TrainingProfile.hear]
/// or [TrainingProfile.echo]). Every change is saved immediately; the screen
/// must reload its values and push them to the native engine once the returned
/// future completes (CLAUDE.md rule 2).
Future<void> showTrainingSettingsSheet(BuildContext context,
    {required String profile, required List<TrainingSection> sections}) {
  final c = AppColors.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: c.background,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (ctx, scroll) =>
          _TrainingSettingsBody(profile: profile, sections: sections, scroll: scroll),
    ),
  );
}

class _TrainingSettingsBody extends StatefulWidget {
  final String profile;
  final List<TrainingSection> sections;
  final ScrollController scroll;
  const _TrainingSettingsBody(
      {required this.profile, required this.sections, required this.scroll});

  @override
  State<_TrainingSettingsBody> createState() => _TrainingSettingsBodyState();
}

class _TrainingSettingsBodyState extends State<_TrainingSettingsBody> {
  // Same order as the firmware's Random Groups options.
  static const _randomOptionKeys = [
    'rnd_all', 'rnd_alpha', 'rnd_num', 'rnd_punct', 'rnd_prosigns',
    'rnd_alpha_num', 'rnd_num_punct', 'rnd_punct_pro', 'rnd_alpha_num_punct', 'rnd_num_punct_pro',
  ];

  TrainingProfile? _prof;
  CharsetChoice _choice = const CharsetChoice(CharSet.koch, ContentKind.random);
  SharedPreferences? _p;

  // Same defaults as the settings screen and the training screens.
  String _practiceChars = '';
  int _boostLevel = 0;
  int _interCharSpace = 28;
  int _interWordSpace = 40;
  int _wpm = 20;   // keyer / trx only: shows the word gap in seconds
  int _randomOption = 0;
  int _groupLength = 5;
  int _wordLengthMax = 0;
  int _abbrevLengthMax = 0;
  int _maxWords = 0;
  bool _stopEach = false;
  // Echo flow prefs (global keys, as in Settings before).
  int _echoThinkTime = 8;
  int _echoRepeats = 3;
  int _echoDisplay = 1;
  int _echoAnswerWpmMax = 0;
  int _toneShift = 1;
  bool _confirmTone = true;
  // Koch sequence (global keys, as in Settings before). 0=M32, 1=LCWO,
  // 2=CW Academy, 3=LICW, 4=Custom.
  int _kochSeq = 0;
  String _customKochChars = 'esno0tqr5ucd9al8ix1myj7h4gvkfz3b.6/w2p?';
  int _licwCarouselStart = 0;
  static List<String> get _kochSeqLabels =>
      ['M32', 'LCWO', 'CW Academy', 'LICW', Strings.t('opt_custom')];
  // Adaptive Copy engine thresholds (global keys, as in Settings before).
  int _adaptiveLowPct = 70;
  int _adaptiveHighPct = 90;
  int _adaptiveEmaAlphaPct = 30;
  int _adaptiveUnlockOcc = 20;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prof = await TrainingProfile.open(widget.profile);
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _prof = prof;
      _choice = CharsetChoice.load(prof);
      _p = p;
      final pc = prof.getString('practiceChars');
      _practiceChars = (pc == null || pc.isEmpty) ? '' : pc;
      _boostLevel = (prof.getInt('boostLevel') ?? 0).clamp(0, 2);
      _interCharSpace = (prof.getInt('interCharSpace') ?? 28).clamp(3, 45);
      _interWordSpace = (prof.getInt('interWordSpace') ?? TrainingProfile.defaultInterWord(widget.profile)).clamp(6, 105);
      _wpm = widget.profile == TrainingProfile.trx
          ? (p.getInt('trxWpm') ?? p.getInt('wpm') ?? 20)
          : widget.profile == TrainingProfile.keyer
              ? (p.getInt('wpm') ?? 20)
              : TrainingProfile.clampWpm(prof.getInt('wpm') ?? p.getInt('wpm'));
      _randomOption = (prof.getInt('randomOption') ?? 0).clamp(0, _randomOptionKeys.length - 1);
      _groupLength = (prof.getInt('groupLength') ?? 5).clamp(2, 8);
      _wordLengthMax = (prof.getInt('wordLengthMax') ?? 0).clamp(0, 8);
      _abbrevLengthMax = (prof.getInt('abbrevLengthMax') ?? 0).clamp(0, 5);
      _maxWords = (prof.getInt('maxWords') ?? 0).clamp(0, 250);
      _stopEach = (prof.getInt('stopEach') ?? 0) == 1;
      _echoThinkTime = p.getInt('echoThinkTime') ?? 8;
      _echoRepeats = (p.getInt('echoRepeats') ?? 3).clamp(0, 7);
      _echoDisplay = (p.getInt('echoDisplayMode') ?? 1).clamp(1, 3);
      _echoAnswerWpmMax = kGiveWpmCap(p.getInt('echoAnswerWpmMax') ?? 0).clamp(0, 50);
      _toneShift = (p.getInt('toneShift') ?? 1).clamp(0, 2);
      _confirmTone = p.getBool('confirmTone') ?? true;
      _kochSeq = (p.getInt('kochSeq') ?? 0).clamp(0, 4);
      final ck = p.getString('customKochChars') ?? '';
      if (ck.isNotEmpty) _customKochChars = ck;
      _licwCarouselStart = (p.getInt('licwCarouselStart') ?? 0).clamp(0, 13);
      _adaptiveHighPct = (p.getInt('adaptiveHighThresholdPct') ?? 90).clamp(50, 99);
      _adaptiveLowPct = (p.getInt('adaptiveLowThresholdPct') ?? 70).clamp(30, 95);
      _adaptiveEmaAlphaPct = (p.getInt('adaptiveEmaAlphaPct') ?? 30).clamp(5, 100);
      _adaptiveUnlockOcc = (p.getInt('adaptiveUnlockOccurrences') ?? 20).clamp(5, 50);
    });
  }

  void _setInt(String f, int v) => _prof?.setInt(f, v);

  String _dits(int n) => Strings.t('unit_dits').replaceFirst('{n}', '$n');

  Widget _hint(String text) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text(text,
          style: TextStyle(fontFamily: 'CwMono', fontSize: 11, color: c.textFaint)),
    );
  }

  List<Widget> _content() {
    return [
      SettingsSectionHeader(Strings.t('charset_practice')),
      _hint(Strings.t('settings_practice_set_desc')),
      SettingsCard(children: [
        CharSetField(
          label: Strings.t('settings_characters'),
          initialValue: _practiceChars,
          onChanged: (v) {
            setState(() => _practiceChars = v);
            _prof?.setString('practiceChars', v);
          },
          countLabel: Strings.t('settings_unique_chars_detected')
              .replaceFirst('{n}', '${parsePracticeChars(_practiceChars).length}'),
          hint: Strings.t('settings_example_chars'),
        ),
        const SettingsDivider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SegmentRow(
              label: Strings.t('settings_boost_practice'),
              options: [Strings.t('opt_off'), Strings.t('opt_boost_moderate'),
                  Strings.t('opt_boost_strong')],
              selected: _boostLevel,
              onChanged: (v) {
                setState(() => _boostLevel = v);
                _setInt('boostLevel', v);
              },
            ),
            _hint(Strings.t('settings_boost_practice_desc')),
          ]),
        ),
      ]),
      const SizedBox(height: 24),
    ];
  }

  List<Widget> _spacing() {
    return [
      SettingsSectionHeader(Strings.t('settings_spacing')),
      _hint(Strings.t(widget.profile == TrainingProfile.echo
          ? 'settings_spacing_desc_echo' : 'settings_spacing_desc')),
      SettingsCard(children: [
        // InterWord Spc may never drop below InterChar Spc (see the note in
        // the Settings screen this was moved from).
        LabeledSlider(
            label: Strings.t('settings_char_spacing'), value: _interCharSpace.toDouble(),
            min: 3, max: 45, divisions: 42, display: '${_dits(_interCharSpace)} · ${ditsToSeconds(_interCharSpace, _wpm)} @ $_wpm WPM',
            onChanged: (v) {
              final newChar = v.round();
              setState(() {
                _interCharSpace = newChar;
                if (_interWordSpace < newChar) _interWordSpace = newChar.clamp(6, 105);
              });
              _setInt('interCharSpace', _interCharSpace);
              _setInt('interWordSpace', _interWordSpace);
            }),
        const SettingsDivider(),
        LabeledSlider(
            label: Strings.t('settings_word_spacing'), value: _interWordSpace.toDouble(),
            min: 6, max: 105, divisions: 99, display: '${_dits(_interWordSpace)} · ${ditsToSeconds(_interWordSpace, _wpm)} @ $_wpm WPM',
            onChanged: (v) {
              setState(() => _interWordSpace = v.round().clamp(_interCharSpace, 105));
              _setInt('interWordSpace', _interWordSpace);
            }),
      ]),
      const SizedBox(height: 24),
    ];
  }

  // Keyer and WiFi Trx: only the word gap counts (firmware: interWordTimer =
  // (InterWord Spc - 1) dits after the last element); InterChar Spc is not
  // used when keying.
  List<Widget> _wordSpacing() {
    return [
      SettingsSectionHeader(Strings.t('settings_spacing')),
      _hint(Strings.t('settings_word_spacing_desc')),
      SettingsCard(children: [
        LabeledSlider(
            label: Strings.t('settings_word_spacing'), value: _interWordSpace.toDouble(),
            min: 6, max: 105, divisions: 99,
            display: '${_dits(_interWordSpace)} · ${ditsToSeconds(_interWordSpace, _wpm)} @ $_wpm WPM',
            onChanged: (v) {
              setState(() => _interWordSpace = v.round());
              _setInt('interWordSpace', _interWordSpace);
            }),
      ]),
      const SizedBox(height: 24),
    ];
  }

  List<Widget> _kochSequence() {
    final c = AppColors.of(context);
    final n = kochSequenceChars(_kochSeq, _customKochChars,
        licwCarouselStart: _licwCarouselStart).length;
    return [
      SettingsSectionHeader(Strings.t('settings_koch_sequence')),
      const SizedBox(height: 4),
      Text(Strings.t('settings_koch_sequence_desc'),
          style: TextStyle(fontFamily: 'CwMono', fontSize: 11, color: c.textFaint)),
      const SizedBox(height: 12),
      SettingsCard(children: [
        SegmentRow(
          label: Strings.t('settings_sequence'),
          options: _kochSeqLabels,
          selected: _kochSeq,
          onChanged: (v) {
            setState(() => _kochSeq = v);
            _p?.setInt('kochSeq', v);
          },
        ),
        if (_kochSeq == 3) ...[
          const SettingsDivider(),
          LabeledSlider(
            label: Strings.t('settings_licw_entry_point'),
            value: _licwCarouselStart.toDouble(),
            min: 0, max: 13, divisions: 13,
            display: '$_licwCarouselStart',
            onChanged: (v) {
              setState(() => _licwCarouselStart = v.round());
              _p?.setInt('licwCarouselStart', _licwCarouselStart);
            },
          ),
        ],
        if (_kochSeq == 4) ...[
          const SettingsDivider(),
          CharSetField(
            label: Strings.t('settings_custom_chars_label'),
            initialValue: _customKochChars,
            onChanged: (v) {
              setState(() => _customKochChars = v);
              _p?.setString('customKochChars', v);
            },
            countLabel: Strings.t('settings_unique_chars_detected').replaceFirst('{n}', '$n'),
          ),
        ],
      ]),
      const SizedBox(height: 24),
    ];
  }

  List<Widget> _hearFlow() {
    return [
      SettingsSectionHeader(Strings.t('settings_hear_flow')),
      _hint(Strings.t('settings_stop_each_desc')),
      SettingsCard(children: [
        ToggleRow(
          label: Strings.t(_choice.content == ContentKind.random
              ? 'settings_stop_each' : 'settings_stop_each_word'),
          value: _stopEach,
          onChanged: (v) {
            setState(() => _stopEach = v);
            _setInt('stopEach', v ? 1 : 0);
          },
        ),
      ]),
      const SizedBox(height: 24),
    ];
  }

  List<Widget> _adaptive() {
    final c = AppColors.of(context);
    return [
      SettingsSectionHeader(Strings.t('settings_adaptive_mode')),
      const SizedBox(height: 4),
      Text(Strings.t('settings_adaptive_mode_desc'),
          style: TextStyle(fontFamily: 'CwMono', fontSize: 11, color: c.textFaint)),
      const SizedBox(height: 12),
      SettingsCard(children: [
        LabeledRangeSlider(
          label: Strings.t('settings_adaptive_threshold_range'),
          values: RangeValues(_adaptiveLowPct.toDouble(), _adaptiveHighPct.toDouble()),
          // High capped at 99: 100% is unreachable (see ADAPTIVE-COPY.md).
          min: 30, max: 99, divisions: 69,
          display: '$_adaptiveLowPct% / $_adaptiveHighPct%',
          // Keep a 5-point gap so low/high can never cross or touch.
          onChanged: (v) {
            var low = v.start.round();
            var high = v.end.round();
            if (high - low < 5) {
              if (low != _adaptiveLowPct) {
                high = (low + 5).clamp(35, 99);
              } else {
                low = (high - 5).clamp(30, 94);
              }
            }
            setState(() { _adaptiveLowPct = low; _adaptiveHighPct = high; });
            _p?.setInt('adaptiveLowThresholdPct', low);
            _p?.setInt('adaptiveHighThresholdPct', high);
          },
        ),
        const SettingsDivider(),
        LabeledSlider(
          label: Strings.t('settings_adaptive_ema_alpha'),
          value: _adaptiveEmaAlphaPct.toDouble(),
          min: 5, max: 100, divisions: 19, display: '$_adaptiveEmaAlphaPct%',
          onChanged: (v) {
            setState(() => _adaptiveEmaAlphaPct = v.round());
            _p?.setInt('adaptiveEmaAlphaPct', _adaptiveEmaAlphaPct);
          },
        ),
        const SettingsDivider(),
        LabeledSlider(
          label: Strings.t('settings_adaptive_unlock_occurrences'),
          value: _adaptiveUnlockOcc.toDouble(),
          min: 5, max: 50, divisions: 45, display: '$_adaptiveUnlockOcc',
          onChanged: (v) {
            setState(() => _adaptiveUnlockOcc = v.round());
            _p?.setInt('adaptiveUnlockOccurrences', _adaptiveUnlockOcc);
          },
        ),
      ]),
      const SizedBox(height: 24),
    ];
  }

  List<Widget> _wordSelection() {
    final k = _choice.content;
    // Only what fits the chosen content (docs/training/P7, decision 8).
    final rows = <Widget>[
      if (_choice.engine.usesRandomOption)
        SegmentRow(
          label: Strings.t('settings_random_chars'),
          options: [for (final k in _randomOptionKeys) Strings.t(k)],
          selected: _randomOption,
          onChanged: (v) {
            setState(() => _randomOption = v);
            _setInt('randomOption', v);
          },
        ),
      if (k == ContentKind.random)
        LabeledSlider(
            label: Strings.t('settings_group_length'), value: _groupLength.toDouble(),
            min: 2, max: 8, divisions: 6, display: '$_groupLength',
            onChanged: (v) {
              setState(() => _groupLength = v.round());
              _setInt('groupLength', _groupLength);
            }),
      if (k == ContentKind.words || k == ContentKind.mixed)
        LabeledSlider(
            label: Strings.t('settings_max_word_length'), value: _wordLengthMax.toDouble(),
            min: 0, max: 8, divisions: 8,
            display: _wordLengthMax == 0 ? Strings.t('opt_all') : '$_wordLengthMax',
            onChanged: (v) {
              setState(() => _wordLengthMax = v.round());
              _setInt('wordLengthMax', _wordLengthMax);
            }),
      if (k == ContentKind.abbrevs || k == ContentKind.mixed)
        LabeledSlider(
            label: Strings.t('settings_max_abbrev_length'), value: _abbrevLengthMax.toDouble(),
            min: 0, max: 5, divisions: 5,
            display: _abbrevLengthMax == 0 ? Strings.t('opt_all') : '${_abbrevLengthMax + 1}',
            onChanged: (v) {
              setState(() => _abbrevLengthMax = v.round());
              _setInt('abbrevLengthMax', _abbrevLengthMax);
            }),
    ];
    final cards = <Widget>[
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0) const SettingsDivider(),
        rows[i],
      ],
      if (rows.isNotEmpty) const SettingsDivider(),
      LabeledSlider(
          label: Strings.t(k == ContentKind.random
              ? 'settings_groups_per_block' : 'settings_words_per_block'),
          value: (_maxWords == 0 ? 10 : _maxWords).clamp(1, 50).toDouble(),
          min: 1, max: 50, divisions: 49,
          display: '${_maxWords == 0 ? 10 : _maxWords.clamp(1, 50)}',
          onChanged: (v) {
            setState(() => _maxWords = v.round());
            _setInt('maxWords', _maxWords);
          }),
    ];
    return [
      SettingsSectionHeader(Strings.t('settings_word_selection')),
      _hint(Strings.t('settings_word_selection_for')
          .replaceFirst('{set}', charSetLabel(_choice.set))
          .replaceFirst('{content}', contentLabel(_choice.content))),
      SettingsCard(children: cards),
      const SizedBox(height: 24),
    ];
  }

  List<Widget> _echoFlow() {
    final c = AppColors.of(context);
    return [
      SettingsSectionHeader('Echo Trainer'),
      const SizedBox(height: 12),
      SettingsCard(children: [
        LabeledSlider(
            label: Strings.t('settings_think_time'), value: _echoThinkTime.toDouble(),
            min: 1, max: 20, divisions: 19, display: '${_echoThinkTime}s',
            onChanged: (v) {
              setState(() => _echoThinkTime = v.round());
              _p?.setInt('echoThinkTime', _echoThinkTime);
            }),
        const SettingsDivider(),
        LabeledSlider(
            label: Strings.t('settings_repeats'), value: _echoRepeats.toDouble(),
            min: 0, max: 7, divisions: 7,
            display: _echoRepeats == 7 ? Strings.t('opt_forever') : '$_echoRepeats ×',
            onChanged: (v) {
              setState(() => _echoRepeats = v.round());
              _p?.setInt('echoRepeats', _echoRepeats);
            }),
        const SettingsDivider(),
        SegmentRow(
          label: Strings.t('settings_echo_prompt'),
          options: [Strings.t('opt_sound'), Strings.t('opt_display'), Strings.t('opt_both')],
          selected: _echoDisplay - 1,
          onChanged: (v) {
            setState(() => _echoDisplay = v + 1);
            _p?.setInt('echoDisplayMode', _echoDisplay);
          },
        ),
        const SettingsDivider(),
        LabeledSlider(
            // Leftmost notch (kGiveWpmMin - 1) = "same as Hören".
            label: Strings.t('settings_answer_wpm'),
            value: (_echoAnswerWpmMax == 0 ? kGiveWpmMin - 1 : _echoAnswerWpmMax).toDouble(),
            min: kGiveWpmMin - 1.0, max: 50, divisions: 51 - kGiveWpmMin,
            display: _echoAnswerWpmMax == 0
                ? Strings.t('settings_answer_wpm_same') : '$_echoAnswerWpmMax WPM',
            onChanged: (v) {
              setState(() => _echoAnswerWpmMax = v < kGiveWpmMin ? 0 : v.round());
              _p?.setInt('echoAnswerWpmMax', _echoAnswerWpmMax);
            }),
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 16, right: 16),
          child: Text(Strings.t('settings_answer_wpm_help'),
              style: TextStyle(fontSize: 12, color: c.textMuted)),
        ),
        const SettingsDivider(),
        SegmentRow(
          label: Strings.t('settings_tone_shift'),
          options: [Strings.t('opt_tone_shift_off'), Strings.t('opt_tone_shift_up'),
              Strings.t('opt_tone_shift_down')],
          selected: _toneShift,
          onChanged: (v) {
            setState(() => _toneShift = v);
            _p?.setInt('toneShift', v);
          },
        ),
        const SettingsDivider(),
        ToggleRow(
          label: Strings.t('settings_confirm_tone'),
          value: _confirmTone,
          onChanged: (v) {
            setState(() => _confirmTone = v);
            _p?.setBool('confirmTone', v);
          },
        ),
      ]),
      const SizedBox(height: 24),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    if (_prof == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final title = widget.profile == TrainingProfile.echo
        ? Strings.t('settings_profile_echo')
        : Strings.t('settings_profile_hear');
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Center(
          child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2)),
          ),
        ),
        const SizedBox(height: 12),
        Text(title,
            style: TextStyle(fontFamily: 'CwMono', fontSize: 16, color: c.textPrimary)),
        const SizedBox(height: 16),
        for (final s in widget.sections)
          ...switch (s) {
            TrainingSection.content => _content(),
            TrainingSection.spacing => _spacing(),
            TrainingSection.wordSpacing => _wordSpacing(),
            TrainingSection.wordSelection => _wordSelection(),
            TrainingSection.echoFlow => _echoFlow(),
            TrainingSection.hearFlow => _hearFlow(),
            TrainingSection.adaptive => _adaptive(),
            TrainingSection.kochSequence => _kochSequence(),
          },
      ],
    );
  }
}
