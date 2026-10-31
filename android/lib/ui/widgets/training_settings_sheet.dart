import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../content/cw_content.dart';
import '../../content/echo_suggestions.dart';
import '../../content/audio_trainer_engine.dart' show audioTrainerVoices, ProsignIntro;
import '../../content/training_profile.dart';
import '../../content/charset_content.dart';
import 'charset_header.dart';
import 'decoder_chars_setting.dart';
import '../../l10n/strings.dart';
import '../../theme/app_colors.dart';
import 'setting_rows.dart';

import '../../content/training_goals.dart';
import '../training_goals_screen.dart';

/// Parts of the per-training settings a screen can show, see
/// docs/archive/training/P3-einstellungen-in-screens.md.
enum TrainingSection {
  content,
  spacing,
  wordSpacing,
  wordSelection,
  echoFlow,
  hearFlow,
  goals,
  kochSequence,
  decoderChars,
  audioFlow,
}

/// Opens the settings sheet for one training profile ([TrainingProfile.hear]
/// or [TrainingProfile.echo]). Every change is saved immediately; the screen
/// must reload its values and push them to the native engine once the returned
/// future completes (CLAUDE.md rule 2).
Future<void> showTrainingSettingsSheet(BuildContext context,
    {required String profile,
    required List<TrainingSection> sections,
    // Scrolls straight to this section when it is part of [sections] (long
    // press on a chip of the training screen).
    TrainingSection? jumpTo}) {
  final c = AppColors.of(context);
  return showModalBottomSheet<void>(
    context: context,
    clipBehavior: Clip.antiAlias,
    isScrollControlled: true,
    backgroundColor: c.background,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (ctx, scroll) =>
          _TrainingSettingsBody(
              profile: profile, sections: sections, scroll: scroll, jumpTo: jumpTo),
    ),
  );
}

class _TrainingSettingsBody extends StatefulWidget {
  final String profile;
  final List<TrainingSection> sections;
  final ScrollController scroll;
  final TrainingSection? jumpTo;
  const _TrainingSettingsBody(
      {required this.profile, required this.sections, required this.scroll, this.jumpTo});

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
  final _sectionKeys = {for (final s in TrainingSection.values) s: GlobalKey()};
  bool _jumped = false;
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
  int _groupLengthMax = 5;
  int _wordLengthMax = 0;
  int _wordLengthMin = 0;
  int _wordLanguage = 0;
  int _abbrevLengthMin = 0;
  int _abbrevLengthMax = 0;
  int _maxWords = 0;
  bool _stopEach = false;
  // Hören typing mode (hear profile).
  int _typeAttempts = 2;
  bool _typeLearn = false;
  bool _typeHaptic = true;
  // Call sign options (global keys: one value for Listen and Send, formerly in
  // the global settings).
  int _callLengthOpt = 0;
  int _callRegionOpt = 0;
  bool _callCommonOnly = true;
  // Echo flow prefs (global keys, as in Settings before).
  int _echoThinkTime = 8;
  int _echoRepeats = 3;
  int _echoDisplay = 1;
  int _echoAnswerWpmMax = 0;
  int _toneShift = 1;
  // Koch sequence (global keys, as in Settings before). 0=M32, 1=LCWO,
  // 2=CW Academy, 3=LICW, 4=Custom.
  /// The Koch sequence keys are global prefs; the audio trainer keeps its own
  /// copy (`audio.kochSeq`, ...) so it never changes Hören's sequence.
  bool get _audio => widget.profile == TrainingProfile.audio;
  /// Right end of the block-size slider: 50, or 51 = endless in the audio trainer.
  int get _blockMax => _audio ? 51 : 50;

  String _kk(String k) => widget.profile == TrainingProfile.audio ? 'audio.$k' : k;

  // Audio trainer flow (#139): think pause and pause between groups in
  // seconds, voice index.
  int _atThink = 4, _atRest = 3, _atVoice = 0, _atVolume = 70, _atProsign = 0;

  int _kochSeq = 0;
  String _customKochChars = 'esno0tqr5ucd9al8ix1myj7h4gvkfz3b.6/w2p?';
  int _licwCarouselStart = 0;
  // Shown order of the stored `kochSeq` values (0=Morserino, 1=LCWO,
  // 2=CW Academy, 3=LICW, 4=Custom; the stored numbers never change):
  // Morserino sits before Custom.
  static const _kochSeqOrder = [1, 2, 3, 0, 4];
  static List<String> get _kochSeqLabels => [
        for (final v in _kochSeqOrder)
          ['Morserino', 'LCWO', 'CW Academy', 'LICW', Strings.t('opt_custom')][v],
      ];
  // Adaptive Copy engine thresholds (global keys, as in Settings before).
  int _adaptiveLowPct = 70;
  int _adaptiveHighPct = 90;
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
      _atThink = (prof.getInt('atThink') ?? 4).clamp(1, 15);
      _atRest = (prof.getInt('atRest') ?? 3).clamp(1, 10);
      _atVolume = (prof.getInt('atVolume') ?? 70).clamp(10, 100);
      _atVoice = (prof.getInt('atVoice') ?? 0).clamp(0, audioTrainerVoices.length - 1);
      _atProsign = (prof.getInt('atProsign') ?? 0).clamp(0, ProsignIntro.values.length - 1);
      _groupLength = (prof.getInt('groupLength') ?? 5).clamp(1, 8);
      _groupLengthMax = (prof.getInt('groupLengthMax') ?? _groupLength).clamp(_groupLength, 8);
      _wordLengthMax = (prof.getInt('wordLengthMax') ?? 0).clamp(0, 8);
      _wordLengthMin = (prof.getInt('wordLengthMin') ?? 0).clamp(0, 8);
      _wordLanguage = (prof.getInt('wordLanguage') ?? 0).clamp(0, 1);
      _abbrevLengthMin = (prof.getInt('abbrevLengthMin') ?? 0).clamp(0, 6);
      _abbrevLengthMax = (prof.getInt('abbrevLengthMax') ?? 0).clamp(0, 5);
      _maxWords = (prof.getInt('maxWords') ?? 0).clamp(0, 250);
      _stopEach = (prof.getInt('stopEach') ?? 0) == 1;
      _typeAttempts = (prof.getInt('typeAttempts') ?? 2).clamp(1, 3);
      _typeLearn = (prof.getInt('typeOnWrong') ?? 0) == 1;
      _typeHaptic = (prof.getInt('typeHaptic') ?? 1) == 1;
      _callLengthOpt = (p.getInt('callLengthOpt') ?? 0).clamp(0, 4);
      _callRegionOpt = (p.getInt('callRegionOpt') ?? 0).clamp(0, 7);
      _callCommonOnly = p.getBool('callCommonOnly') ?? true;
      _echoThinkTime = p.getInt('echoThinkTime') ?? 8;
      _echoRepeats = (p.getInt('echoRepeats') ?? 3).clamp(0, 7);
      _echoDisplay = (p.getInt('echoDisplayMode') ?? 1).clamp(1, 3);
      _echoAnswerWpmMax = kGiveWpmCap(p.getInt('echoAnswerWpmMax') ?? 0).clamp(0, 50);
      _toneShift = (p.getInt('toneShift') ?? 1).clamp(0, 2);
      _kochSeq = (p.getInt(_kk('kochSeq')) ?? 0).clamp(0, 4);
      final ck = p.getString(_kk('customKochChars')) ?? '';
      if (ck.isNotEmpty) _customKochChars = ck;
      _licwCarouselStart = (p.getInt(_kk('licwCarouselStart')) ?? 0).clamp(0, 13);
      final rules = goalRules(p, widget.profile);
      _adaptiveHighPct = rules.highPct;
      _adaptiveLowPct = rules.lowPct;
      _adaptiveUnlockOcc = rules.unlockOccurrences;
    });
  }

  void _setInt(String f, int v) => _prof?.setInt(f, v);

  String _dits(int n) => Strings.t('unit_dits').replaceFirst('{n}', '$n');

  Widget _hint(String text) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text(text,
          style: TextStyle(fontSize: 11, color: c.textFaint)),
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
            min: 3, max: 45, divisions: 42, display: '${_dits(_interCharSpace)} · ${ditsToSeconds(_interCharSpace, _wpm)} @\u00A0$_wpm\u00A0WPM',
            onChanged: (v) {
              final newChar = v.round();
              setState(() {
                _interCharSpace = newChar;
                if (widget.profile != TrainingProfile.echo && _interWordSpace < newChar) {
                  _interWordSpace = newChar.clamp(6, 105);
                }
              });
              _setInt('interCharSpace', _interCharSpace);
              _setInt('interWordSpace', _interWordSpace);
            }),
        if (widget.profile != TrainingProfile.echo) ...[
        const SettingsDivider(),
        LabeledSlider(
            label: Strings.t('settings_word_spacing'), value: _interWordSpace.toDouble(),
            min: 6, max: 105, divisions: 99, display: '${_dits(_interWordSpace)} · ${ditsToSeconds(_interWordSpace, _wpm)} @\u00A0$_wpm\u00A0WPM',
            onChanged: (v) {
              setState(() => _interWordSpace = v.round().clamp(_interCharSpace, 105));
              _setInt('interWordSpace', _interWordSpace);
            }),
        ],
      ]),
      // The sheet is shared by paper and typing mode and opened before the
      // mode is chosen, so the word gap stays editable and gets a note.
      if (widget.profile == TrainingProfile.hear)
        _hint(Strings.t('settings_word_spacing_hear_note')),
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
            display: '${_dits(_interWordSpace)} · ${ditsToSeconds(_interWordSpace, _wpm)} @\u00A0$_wpm\u00A0WPM',
            onChanged: (v) {
              setState(() => _interWordSpace = v.round());
              _setInt('interWordSpace', _interWordSpace);
            }),
      ]),
      const SizedBox(height: 24),
    ];
  }

  // CW Keyer only (the CW Decoder has its own sheet): national letters / ITU
  // brackets when decoding, a global operator setting, not a profile value.
  List<Widget> _decoderChars() => [
        SettingsSectionHeader(Strings.t('dec_chars_header')),
        const SettingsCard(children: [DecoderCharsSetting()]),
        const SizedBox(height: 24),
      ];

  List<Widget> _kochSequence() {
    final c = AppColors.of(context);
    final n = kochSequenceChars(_kochSeq, _customKochChars,
        licwCarouselStart: _licwCarouselStart).length;
    return [
      SettingsSectionHeader(Strings.t('settings_koch_sequence')),
      const SizedBox(height: 4),
      Text(Strings.t('settings_koch_sequence_desc'),
          style: TextStyle(fontSize: 11, color: c.textFaint)),
      const SizedBox(height: 12),
      SettingsCard(children: [
        SegmentRow(
          label: Strings.t('settings_sequence'),
          options: _kochSeqLabels,
          selected: _kochSeqOrder.indexOf(_kochSeq),
          onChanged: (i) {
            final v = _kochSeqOrder[i];
            setState(() => _kochSeq = v);
            _p?.setInt(_kk('kochSeq'), v);
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
              _p?.setInt(_kk('licwCarouselStart'), _licwCarouselStart);
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
              _p?.setString(_kk('customKochChars'), v);
            },
            countLabel: Strings.t('settings_unique_chars_detected').replaceFirst('{n}', '$n'),
          ),
        ],
      ]),
      const SizedBox(height: 24),
    ];
  }

  List<Widget> _audioFlow() {
    return [
      SettingsSectionHeader(Strings.t('settings_audio_flow')),
      _hint(Strings.t('settings_audio_flow_desc')),
      SettingsCard(children: [
        LabeledSlider(
          label: Strings.t('at_think_pause'),
          display: Strings.t('at_seconds').replaceFirst('{n}', '$_atThink'),
          value: _atThink.toDouble(), min: 1, max: 15, divisions: 14,
          onChanged: (v) {
            setState(() => _atThink = v.round());
            _setInt('atThink', _atThink);
          },
        ),
        LabeledSlider(
          label: Strings.t('at_rest_pause'),
          display: Strings.t('at_seconds').replaceFirst('{n}', '$_atRest'),
          value: _atRest.toDouble(), min: 1, max: 10, divisions: 9,
          onChanged: (v) {
            setState(() => _atRest = v.round());
            _setInt('atRest', _atRest);
          },
        ),
        const SettingsDivider(),
        SegmentRow(
          label: Strings.t('at_voice'),
          options: [for (final v in audioTrainerVoices) v[0].toUpperCase() + v.substring(1)],
          selected: _atVoice,
          // Loaded at the next start; a running session keeps its voice.
          onChanged: (v) {
            setState(() => _atVoice = v);
            _setInt('atVoice', v);
          },
        ),
        LabeledSlider(
          label: Strings.t('at_voice_volume'),
          display: '$_atVolume %',
          value: _atVolume.toDouble(), min: 10, max: 100, divisions: 18,
          onChanged: (v) {
            setState(() => _atVolume = v.round());
            _setInt('atVolume', _atVolume);
          },
        ),
        const SettingsDivider(),
        SegmentRow(
          label: Strings.t('at_prosign_intro'),
          options: [
            Strings.t('at_prosign_word'),
            Strings.t('at_prosign_bell'),
            Strings.t('at_prosign_harp'),
            Strings.t('at_prosign_gong'),
            Strings.t('at_prosign_off'),
          ],
          selected: _atProsign,
          perRow: 3,
          onChanged: (v) {
            setState(() => _atProsign = v);
            _setInt('atProsign', v);
          },
        ),
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
      const SizedBox(height: 16),
      _hint(Strings.t('settings_type_desc')),
      _hint(Strings.t('settings_type_onwrong_desc')),
      SettingsCard(children: [
        SegmentRow(
          label: Strings.t('settings_type_onwrong'),
          options: [Strings.t('settings_type_onwrong_repeat'),
              Strings.t('settings_type_onwrong_learn')],
          selected: _typeLearn ? 1 : 0,
          onChanged: (v) {
            setState(() => _typeLearn = v == 1);
            _setInt('typeOnWrong', v);
          },
        ),
        const SettingsDivider(),
        Opacity(
          opacity: _typeLearn ? 0.4 : 1,
          child: IgnorePointer(
            ignoring: _typeLearn,
            child: SegmentRow(
              label: Strings.t('settings_type_attempts'),
              options: const ['1', '2', '3'],
              selected: _typeAttempts - 1,
              onChanged: (v) {
                setState(() => _typeAttempts = v + 1);
                _setInt('typeAttempts', _typeAttempts);
              },
            ),
          ),
        ),
        const SettingsDivider(),
        ToggleRow(
          label: Strings.t('settings_type_haptic'),
          value: _typeHaptic,
          onChanged: (v) {
            setState(() => _typeHaptic = v);
            _setInt('typeHaptic', v ? 1 : 0);
          },
        ),
      ]),
      const SizedBox(height: 24),
    ];
  }

  // Thresholds and unlock rule behind the suggestions; global, so they are the
  // same in Hören and Geben.
  List<Widget> _rules() {
    final c = AppColors.of(context);
    return [
      SettingsSectionHeader(Strings.t('tg_rules_title')),
      const SizedBox(height: 4),
      Text(Strings.t('tg_rules_desc'),
          style: TextStyle(fontSize: 11, color: c.textFaint)),
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
            _p?.setInt(goalRuleKey(widget.profile, 'adaptiveLowThresholdPct'), low);
            _p?.setInt(goalRuleKey(widget.profile, 'adaptiveHighThresholdPct'), high);
          },
        ),
        const SettingsDivider(),
        LabeledSlider(
          label: Strings.t('settings_adaptive_unlock_occurrences'),
          value: _adaptiveUnlockOcc.toDouble(),
          min: 5, max: 50, divisions: 45, display: '$_adaptiveUnlockOcc',
          onChanged: (v) {
            setState(() => _adaptiveUnlockOcc = v.round());
            _p?.setInt(goalRuleKey(widget.profile, 'adaptiveUnlockOccurrences'), _adaptiveUnlockOcc);
          },
          ),
        ],
      ),
      const SizedBox(height: 24),
    ];
  }

  // The training goals of this profile, right in its settings: the goals in
  // their order, then the rules that decide when a step is suggested.
  List<Widget> _goals() {
    final c = AppColors.of(context);
    return [
      SettingsSectionHeader(Strings.t('tg_title')),
      const SizedBox(height: 4),
      Text(
        Strings.t('tg_settings_desc'),
        style: TextStyle(fontSize: 11, color: c.textFaint),
      ),
      const SizedBox(height: 12),
      GoalOrderEditor(kind: widget.profile, embedded: true),
      const SizedBox(height: 12),
      ..._rules(),
    ];
  }

  /// "5" when both ends match, else "2–7"; [allAt] shows as "all" (open end).
  String _rangeText(int lo, int hi, {int? allAt}) {
    final h = hi == allAt ? Strings.t('opt_all') : '$hi';
    return lo == hi ? h : '$lo–$h';
  }

  List<Widget> _wordSelection() {
    final k = _choice.content;
    // Only what fits the chosen content (docs/archive/training/P7, decision 8).
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
      if (k == ContentKind.random || k == ContentKind.mixed)
        LabeledRangeSlider(
            label: Strings.t('settings_group_length'),
            values: RangeValues(_groupLength.toDouble(), _groupLengthMax.toDouble()),
            min: 1, max: 8, divisions: 7,
            display: _rangeText(_groupLength, _groupLengthMax),
            onChanged: (v) {
              setState(() {
                _groupLength = v.start.round();
                _groupLengthMax = v.end.round();
              });
              _setInt('groupLength', _groupLength);
              _setInt('groupLengthMax', _groupLengthMax);
            }),
      if (k == ContentKind.words || k == ContentKind.mixed)
        SegmentRow(
          label: Strings.t('settings_word_language'),
          options: [Strings.t('settings_word_language_en'), Strings.t('settings_word_language_de')],
          selected: _wordLanguage,
          onChanged: (v) {
            setState(() => _wordLanguage = v);
            _setInt('wordLanguage', v);
          },
        ),
      // Words: stored 0 = no limit on either side (slider ends 1 and 9).
      if (k == ContentKind.words || k == ContentKind.mixed)
        LabeledRangeSlider(
            label: Strings.t('settings_word_length'),
            values: RangeValues(
                _wordLengthMin == 0 ? 1 : _wordLengthMin.toDouble(),
                _wordLengthMax == 0 ? 9 : _wordLengthMax.toDouble()),
            min: 1, max: 9, divisions: 8,
            display: _rangeText(_wordLengthMin == 0 ? 1 : _wordLengthMin,
                _wordLengthMax == 0 ? 9 : _wordLengthMax, allAt: 9),
            onChanged: (v) {
              setState(() {
                _wordLengthMin = v.start.round() <= 1 ? 0 : v.start.round();
                _wordLengthMax = v.end.round() >= 9 ? 0 : v.end.round();
              });
              _setInt('wordLengthMin', _wordLengthMin);
              _setInt('wordLengthMax', _wordLengthMax);
            }),
      // Abbreviations: slider 2..7, the end 7 = no limit. The stored max keeps
      // the firmware's option encoding (1..5 = length 2..6, 0 = all).
      if (k == ContentKind.abbrevs || k == ContentKind.mixed)
        LabeledRangeSlider(
            label: Strings.t('settings_abbrev_length'),
            values: RangeValues(
                _abbrevLengthMin == 0 ? 2 : _abbrevLengthMin.toDouble(),
                _abbrevLengthMax == 0 ? 7 : _abbrevLengthMax + 1.0),
            min: 2, max: 7, divisions: 5,
            display: _rangeText(_abbrevLengthMin == 0 ? 2 : _abbrevLengthMin,
                _abbrevLengthMax == 0 ? 7 : _abbrevLengthMax + 1, allAt: 7),
            onChanged: (v) {
              setState(() {
                _abbrevLengthMin = v.start.round() <= 2 ? 0 : v.start.round();
                _abbrevLengthMax = v.end.round() >= 7 ? 0 : v.end.round() - 1;
              });
              _setInt('abbrevLengthMin', _abbrevLengthMin);
              _setInt('abbrevLengthMax', _abbrevLengthMax);
            }),
      // Call signs: own content, or inside Mixed with all characters.
      if (k == ContentKind.calls || (k == ContentKind.mixed && _choice.set == CharSet.all)) ...[
        SegmentRow(
          label: Strings.t('settings_call_length'),
          options: [Strings.t('opt_unlim_short'), '3', '4', '5', '6'],
          selected: _callLengthOpt,
          onChanged: (v) {
            setState(() => _callLengthOpt = v);
            _p?.setInt('callLengthOpt', v);
          },
        ),
        SegmentRow(
          label: Strings.t('settings_call_region'),
          options: [Strings.t('opt_all_cap'), 'EU', 'NA', 'SA', 'AF', 'AS', 'OC', 'VK/ZL'],
          selected: _callRegionOpt,
          onChanged: (v) {
            setState(() => _callRegionOpt = v);
            _p?.setInt('callRegionOpt', v);
          },
        ),
        ToggleRow(
          label: Strings.t('settings_common_prefixes_only'),
          value: _callCommonOnly,
          onChanged: (v) {
            setState(() => _callCommonOnly = v);
            _p?.setBool('callCommonOnly', v);
          },
        ),
      ],
    ];
    final cards = <Widget>[
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0) const SettingsDivider(),
        rows[i],
      ],
      if (rows.isNotEmpty) const SettingsDivider(),
      // The audio trainer has one more step at the right end: endless (51).
      LabeledSlider(
          label: Strings.t(k == ContentKind.random
              ? 'settings_groups_per_block' : 'settings_words_per_block'),
          value: (_maxWords == 0 ? 10 : _maxWords).clamp(1, _blockMax).toDouble(),
          min: 1, max: _blockMax.toDouble(), divisions: _blockMax - 1,
          display: _audio && _maxWords > 50
              ? Strings.t('at_endless')
              : '${_maxWords == 0 ? 10 : _maxWords.clamp(1, 50)}',
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
            min: 0, max: 20, divisions: 20, display: '${_echoThinkTime}s',
            onChanged: (v) {
              setState(() => _echoThinkTime = v.round());
              _p?.setInt('echoThinkTime', _echoThinkTime);
            }),
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 16, right: 16),
          child: Text(Strings.t('settings_think_time_help'),
              style: TextStyle(fontSize: 12, color: c.textMuted)),
        ),
        const SettingsDivider(),
        // Not the word gap of the other profiles: never played, it only sets
        // when the answer counts (DECISIONS "Answer pause"). Independent of
        // the character spacing.
        LabeledSlider(
            label: Strings.t('settings_answer_pause'), value: _interWordSpace.toDouble(),
            min: 6, max: 105, divisions: 99,
            display: '${_dits(_interWordSpace)} · ${ditsToSeconds(_interWordSpace, _wpm)} @\u00A0$_wpm\u00A0WPM',
            onChanged: (v) {
              setState(() => _interWordSpace = v.round());
              _setInt('interWordSpace', _interWordSpace);
            }),
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 16, right: 16),
          child: Text(Strings.t('settings_answer_pause_help'),
              style: TextStyle(fontSize: 12, color: c.textMuted)),
        ),
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
    final jump = widget.jumpTo;
    if (jump != null && !_jumped && widget.sections.contains(jump)) {
      _jumped = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _sectionKeys[jump]?.currentContext;
        if (ctx != null && ctx.mounted) {
          Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 250));
        }
      });
    }
    // A plain scroll view (not a lazy ListView) so every section is built and
    // can be scrolled to by key.
    // Own Scaffold: the undo snackbar of the setting rows would otherwise sit
    // behind the modal sheet.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 12),
          // Opened by a long press on a chip (jumpTo): a visible way back (#61).
          if (jump != null)
            Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                color: c.textPrimary,
                tooltip: Strings.t('ac_back'),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              Expanded(child: Text(title,
                  style: TextStyle(fontSize: 16, color: c.textPrimary))),
            ])
          else
            Text(title,
                style: TextStyle(fontSize: 16, color: c.textPrimary)),
          const SizedBox(height: 16),
          for (final s in widget.sections)
            Column(
              key: _sectionKeys[s],
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: switch (s) {
                TrainingSection.content => _content(),
                TrainingSection.spacing => _spacing(),
                TrainingSection.wordSpacing => _wordSpacing(),
                TrainingSection.wordSelection => _wordSelection(),
                TrainingSection.echoFlow => _echoFlow(),
                TrainingSection.hearFlow => _hearFlow(),
                  TrainingSection.goals => _goals(),
                  TrainingSection.kochSequence => _kochSequence(),
                TrainingSection.decoderChars => _decoderChars(),
                TrainingSection.audioFlow => _audioFlow(),
              },
            ),
        ],
      ),
      ),
    );
  }
}
