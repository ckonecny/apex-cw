// Profile picker of the exam simulation (issue #42): country chips, the speed
// variants of the chosen country (and text/figures where the exam has both),
// and the editor of the user-defined profile.
import 'package:flutter/material.dart';

import '../content/exam_profile.dart';
import '../l10n/exam_strings.dart';
import '../theme/app_colors.dart';
import 'widgets/app_ui.dart';
import 'widgets/slider_row.dart';

class ExamPicker extends StatelessWidget {
  final ExamProfile selected;

  /// The user-defined profile (shown and edited when its chip is chosen).
  final ExamProfile custom;
  final ValueChanged<ExamProfile> onSelect;
  final ValueChanged<ExamProfile> onCustomChanged;

  const ExamPicker({
    super.key,
    required this.selected,
    required this.custom,
    required this.onSelect,
    required this.onCustomChanged,
  });

  Widget _chip(BuildContext context, String label, bool on, VoidCallback onTap) {
    final c = AppColors.of(context);
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 13,
          color: on ? c.accent : c.textPrimary)),
      selected: on,
      showCheckmark: false,
      selectedColor: c.accent.withValues(alpha: 0.15),
      backgroundColor: c.surface,
      side: BorderSide(color: on ? c.accent : c.border),
      onSelected: (_) => onTap(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fam = selected.family;
    final isCustom = fam == ExamProfile.customFamily;
    final variants = isCustom ? <ExamProfile>[] : examFamilyProfiles(fam);
    // Speed variants once per speed; the figures twin is picked separately.
    final speeds = [for (final p in variants) if (p.kind != ExamKind.figures) p];
    final hasFigures = variants.any((p) => p.kind == ExamKind.figures);
    final figures = selected.kind == ExamKind.figures;
    ExamProfile pick(ExamProfile base, bool fig) => fig
        ? variants.firstWhere((p) => p.wpm == base.wpm && p.kind == ExamKind.figures, orElse: () => base)
        : base;
    final base = isCustom
        ? selected
        : variants.firstWhere((p) => p.wpm == selected.wpm && p.farnsworth == selected.farnsworth && p.kind != ExamKind.figures,
            orElse: () => speeds.first);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AppCaption(ExamStrings.t('ex_family')),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (final f in examFamilies)
          _chip(context, ExamStrings.t('ex_fam_$f'), f == fam,
              () => onSelect(examFamilyProfiles(f).first)),
        _chip(context, ExamStrings.t('ex_fam_custom'), isCustom, () => onSelect(custom)),
      ]),
      if (!isCustom) ...[
        const SizedBox(height: 12),
        AppCaption(ExamStrings.t('ex_speed')),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final p in speeds)
            _chip(
              context,
              p.farnsworth ? ExamStrings.f('ex_variant_farns', [p.wpm]) : '${p.wpm} WPM',
              p.id == base.id,
              () => onSelect(pick(p, figures)),
            ),
        ]),
        if (hasFigures) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            _chip(context, ExamStrings.t('ex_variant_txt'), !figures, () => onSelect(pick(base, false))),
            _chip(context, ExamStrings.t('ex_variant_fig'), figures, () => onSelect(pick(base, true))),
          ]),
        ],
      ] else
        _CustomEditor(profile: custom, onChanged: onCustomChanged),
    ]);
  }
}

class _CustomEditor extends StatelessWidget {
  final ExamProfile profile;
  final ValueChanged<ExamProfile> onChanged;
  const _CustomEditor({required this.profile, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final p = profile;
    Widget slider(String key, int value, int min, int max, ValueChanged<int> set, {double w = 96}) =>
        SliderRow(
          label: ExamStrings.t(key), labelWidth: w, value: value.toDouble(),
          min: min.toDouble(), max: max.toDouble(), divisions: max - min,
          onChanged: min == max ? null : (d) => set(d.round()),
        );
    Widget kindChip(ExamKind k, String key) => ChoiceChip(
          label: Text(ExamStrings.t(key),
              style: TextStyle(fontSize: 13,
                  color: p.kind == k ? c.accent : c.textPrimary)),
          selected: p.kind == k,
          showCheckmark: false,
          selectedColor: c.accent.withValues(alpha: 0.15),
          backgroundColor: c.surface,
          side: BorderSide(color: p.kind == k ? c.accent : c.border),
          onSelected: (_) => onChanged(p.copyWith(kind: k)),
        );
    Widget sw(String key, bool v, ValueChanged<bool> set) => Row(children: [
          Expanded(child: Text(ExamStrings.t(key),
              style: TextStyle(fontSize: 13, color: c.textPrimary))),
          Switch(value: v, onChanged: set),
        ]);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          slider('ex_custom_wpm', p.wpm, 5, ExamProfile.customMaxWpm,
              (v) => onChanged(p.copyWith(wpm: v, charWpm: p.charWpm < v ? v : p.charWpm))),
          slider('ex_custom_char', p.charWpm, p.wpm, ExamProfile.customMaxWpm,
              (v) => onChanged(p.copyWith(charWpm: v))),
          slider('ex_custom_minutes', p.minutes, 1, 10, (v) => onChanged(p.copyWith(minutes: v))),
          slider('ex_custom_errors', p.errorLimit, 0, 10, (v) => onChanged(p.copyWith(errorLimit: v))),
          slider('ex_custom_retries', p.retries, 0, 5, (v) => onChanged(p.copyWith(retries: v))),
          const SizedBox(height: 8),
          AppCaption(ExamStrings.t('ex_custom_kind')),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 4, children: [
            kindChip(ExamKind.plain, 'ex_kind_plain'),
            kindChip(ExamKind.figures, 'ex_kind_figures'),
            kindChip(ExamKind.groups, 'ex_kind_groups'),
          ]),
          if (p.kind == ExamKind.plain) ...[
            const SizedBox(height: 8),
            AppCaption(ExamStrings.t('ex_custom_lang')),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final (code, key) in const [('de', 'ex_lang_de'), ('en', 'ex_lang_en')])
                ChoiceChip(
                  label: Text(ExamStrings.t(key),
                      style: TextStyle(fontSize: 13,
                          color: p.lang == code ? c.accent : c.textPrimary)),
                  selected: p.lang == code,
                  showCheckmark: false,
                  selectedColor: c.accent.withValues(alpha: 0.15),
                  backgroundColor: c.surface,
                  side: BorderSide(color: p.lang == code ? c.accent : c.border),
                  onSelected: (_) => onChanged(p.copyWith(lang: code)),
                ),
            ]),
            sw('ex_custom_punct', p.punctuation, (v) => onChanged(p.copyWith(punctuation: v))),
            sw('ex_custom_ar', p.prosigns, (v) => onChanged(p.copyWith(prosigns: v))),
          ],
          const SizedBox(height: 6),
          Text(ExamStrings.t('ex_custom_hint'),
              style: TextStyle(fontSize: 11, color: c.textFaint)),
        ]),
      ),
    );
  }
}
