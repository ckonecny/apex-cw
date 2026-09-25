import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../content/cw_content.dart';
import '../../content/training_profile.dart';
import '../../l10n/strings.dart';
import '../../theme/app_colors.dart';
import 'setting_rows.dart';

/// Parts of the per-training settings a screen can show, see
/// docs/training/P3-einstellungen-in-screens.md.
enum TrainingSection { content, spacing, wordSelection, generatorFlow, echoFlow, adaptive, kochSequence }

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
  static const _randomOptionLabels = [
    'All Chars', 'Alpha', 'Numerals', 'Interpunct.', 'Pro Signs',
    'Alpha + Num', 'Num+Interp.', 'Interp+ProSn', 'Alph+Num+Int', 'Num+Int+ProS',
  ];

  TrainingProfile? _prof;
  SharedPreferences? _p;

  // Same defaults as the settings screen and the training screens.
  String _practiceChars = '';
  int _boostLevel = 0;
  int _interCharSpace = 28;
  int _interWordSpace = 40;
  int _randomOption = 0;
  int _groupLength = 5;
  int _wordLengthMax = 0;
  int _abbrevLengthMax = 0;
  int _maxWords = 0;
  // Global (not per-profile) generator flow prefs, as in Settings before.
  int _genDisplay = 1;
  bool _stopAfterItem = false;
  bool _eachWordTwice = false;
  // Echo flow prefs (global keys, as in Settings before).
  int _echoThinkTime = 8;
  int _echoRepeats = 3;
  int _echoDisplay = 1;
  int _echoAnswerWpmMax = 0;
  bool _adaptiveSpeed = false;
  int _echoSpeedMax = 35;
  int _toneShift = 1;
  // Koch sequence (global keys, as in Settings before). 0=M32, 1=LCWO,
  // 2=CW Academy, 3=LICW, 4=Custom.
  int _kochSeq = 0;
  String _customKochChars = 'esno0tqr5ucd9al8ix1myj7h4gvkfz3b.6/w2p?';
  int _licwCarouselStart = 0;
  static const _kochSeqLabels = ['M32', 'LCWO', 'CW Academy', 'LICW', 'Custom'];
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
      _p = p;
      final pc = prof.getString('practiceChars');
      _practiceChars = (pc == null || pc.isEmpty) ? '' : pc;
      _boostLevel = (prof.getInt('boostLevel') ?? 0).clamp(0, 2);
      _interCharSpace = (prof.getInt('interCharSpace') ?? 28).clamp(3, 45);
      _interWordSpace = (prof.getInt('interWordSpace') ?? 40).clamp(6, 105);
      _randomOption = (prof.getInt('randomOption') ?? 0).clamp(0, _randomOptionLabels.length - 1);
      _groupLength = (prof.getInt('groupLength') ?? 5).clamp(2, 8);
      _wordLengthMax = (prof.getInt('wordLengthMax') ?? 0).clamp(0, 8);
      _abbrevLengthMax = (prof.getInt('abbrevLengthMax') ?? 0).clamp(0, 5);
      _maxWords = (prof.getInt('maxWords') ?? 0).clamp(0, 250);
      _genDisplay = (p.getInt('genDisplayMode') ?? 1).clamp(0, 2);
      _stopAfterItem = p.getBool('stopAfterItem') ?? false;
      _eachWordTwice = p.getBool('eachWordTwice') ?? false;
      _echoThinkTime = p.getInt('echoThinkTime') ?? 8;
      _echoRepeats = (p.getInt('echoRepeats') ?? 3).clamp(0, 7);
      _echoDisplay = (p.getInt('echoDisplayMode') ?? 1).clamp(1, 3);
      _echoAnswerWpmMax = (p.getInt('echoAnswerWpmMax') ?? 0).clamp(0, 50);
      _adaptiveSpeed = p.getBool('adaptiveSpeed') ?? false;
      _echoSpeedMax = p.getInt('echoSpeedMax') ?? 35;
      _toneShift = (p.getInt('toneShift') ?? 1).clamp(0, 2);
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
      SettingsSectionHeader('Practice Set'),
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
          hint: 'e.g. QXZJ...',
        ),
        const SettingsDivider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SegmentRow(
              label: 'Boost Practice',
              options: const ['Off', 'Moderate', 'Strong'],
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
      _hint(Strings.t('settings_spacing_desc')),
      SettingsCard(children: [
        // InterWord Spc may never drop below InterChar Spc (see the note in
        // the Settings screen this was moved from).
        LabeledSlider(
            label: 'Interchar Spc', value: _interCharSpace.toDouble(),
            min: 3, max: 45, divisions: 42, display: '$_interCharSpace dits',
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
            label: 'InterWord Spc', value: _interWordSpace.toDouble(),
            min: 6, max: 105, divisions: 99, display: '$_interWordSpace dits',
            onChanged: (v) {
              setState(() => _interWordSpace = v.round().clamp(_interCharSpace, 105));
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
      SettingsSectionHeader('Koch Sequence'),
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

  List<Widget> _generatorFlow() {
    return [
      SettingsSectionHeader('CW Generator'),
      const SizedBox(height: 12),
      SettingsCard(children: [
        SegmentRow(
          label: 'CW Gen Displ',
          options: [Strings.t('opt_off'), Strings.t('opt_by_char'), Strings.t('opt_by_word')],
          selected: _genDisplay,
          onChanged: (v) {
            setState(() => _genDisplay = v);
            _p?.setInt('genDisplayMode', v);
          },
        ),
        const SettingsDivider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ToggleRow(
                label: 'Stop<Next>Rep', value: _stopAfterItem,
                onChanged: (v) {
                  setState(() => _stopAfterItem = v);
                  _p?.setBool('stopAfterItem', v);
                }),
            _hint(Strings.t('settings_stop_next_rep_desc')),
          ]),
        ),
        const SettingsDivider(),
        ToggleRow(
            label: Strings.t('settings_each_word_twice'), value: _eachWordTwice,
            onChanged: (v) {
              setState(() => _eachWordTwice = v);
              _p?.setBool('eachWordTwice', v);
            }),
      ]),
      const SizedBox(height: 24),
    ];
  }

  List<Widget> _wordSelection() {
    return [
      SettingsSectionHeader(Strings.t('settings_word_selection')),
      const SizedBox(height: 12),
      SettingsCard(children: [
        SegmentRow(
          label: 'Random Groups',
          options: _randomOptionLabels,
          selected: _randomOption,
          onChanged: (v) {
            setState(() => _randomOption = v);
            _setInt('randomOption', v);
          },
        ),
        const SettingsDivider(),
        LabeledSlider(
            label: Strings.t('settings_group_length'), value: _groupLength.toDouble(),
            min: 2, max: 8, divisions: 6, display: '$_groupLength',
            onChanged: (v) {
              setState(() => _groupLength = v.round());
              _setInt('groupLength', _groupLength);
            }),
        const SettingsDivider(),
        LabeledSlider(
            label: Strings.t('settings_max_word_length'), value: _wordLengthMax.toDouble(),
            min: 0, max: 8, divisions: 8,
            display: _wordLengthMax == 0 ? Strings.t('opt_all') : '$_wordLengthMax',
            onChanged: (v) {
              setState(() => _wordLengthMax = v.round());
              _setInt('wordLengthMax', _wordLengthMax);
            }),
        const SettingsDivider(),
        LabeledSlider(
            label: Strings.t('settings_max_abbrev_length'), value: _abbrevLengthMax.toDouble(),
            min: 0, max: 5, divisions: 5,
            display: _abbrevLengthMax == 0 ? Strings.t('opt_all') : '${_abbrevLengthMax + 1}',
            onChanged: (v) {
              setState(() => _abbrevLengthMax = v.round());
              _setInt('abbrevLengthMax', _abbrevLengthMax);
            }),
        const SettingsDivider(),
        LabeledSlider(
            label: 'Max # of Words', value: _maxWords.toDouble(),
            min: 0, max: 250, divisions: 50,
            display: _maxWords == 0 ? Strings.t('opt_unlimited') : '$_maxWords',
            onChanged: (v) {
              setState(() => _maxWords = (v / 5).round() * 5);
              _setInt('maxWords', _maxWords);
            }),
      ]),
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
            display: _echoRepeats == 7 ? 'Forever' : '$_echoRepeats ×',
            onChanged: (v) {
              setState(() => _echoRepeats = v.round());
              _p?.setInt('echoRepeats', _echoRepeats);
            }),
        const SettingsDivider(),
        SegmentRow(
          label: 'Echo Prompt',
          options: [Strings.t('opt_sound'), Strings.t('opt_display'), Strings.t('opt_both')],
          selected: _echoDisplay - 1,
          onChanged: (v) {
            setState(() => _echoDisplay = v + 1);
            _p?.setInt('echoDisplayMode', _echoDisplay);
          },
        ),
        const SettingsDivider(),
        LabeledSlider(
            label: Strings.t('settings_answer_wpm'), value: _echoAnswerWpmMax.toDouble(),
            min: 0, max: 50, divisions: 50,
            display: _echoAnswerWpmMax == 0
                ? Strings.t('settings_answer_wpm_same') : '$_echoAnswerWpmMax WPM',
            onChanged: (v) {
              setState(() => _echoAnswerWpmMax = v < 5 ? 0 : v.round());
              _p?.setInt('echoAnswerWpmMax', _echoAnswerWpmMax);
            }),
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 16, right: 16),
          child: Text(Strings.t('settings_answer_wpm_help'),
              style: TextStyle(fontSize: 12, color: c.textMuted)),
        ),
        const SettingsDivider(),
        ToggleRow(
            label: 'Adaptive Speed', value: _adaptiveSpeed,
            onChanged: (v) {
              setState(() => _adaptiveSpeed = v);
              _p?.setBool('adaptiveSpeed', v);
            }),
        if (_adaptiveSpeed) ...[
          const SettingsDivider(),
          LabeledSlider(
              label: Strings.t('settings_max_speed'), value: _echoSpeedMax.toDouble(),
              min: 10, max: 50, divisions: 40, display: '$_echoSpeedMax WPM',
              onChanged: (v) {
                setState(() => _echoSpeedMax = v.round());
                _p?.setInt('echoSpeedMax', _echoSpeedMax);
              }),
        ],
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
            TrainingSection.wordSelection => _wordSelection(),
            TrainingSection.generatorFlow => _generatorFlow(),
            TrainingSection.echoFlow => _echoFlow(),
            TrainingSection.adaptive => _adaptive(),
            TrainingSection.kochSequence => _kochSequence(),
          },
      ],
    );
  }
}
