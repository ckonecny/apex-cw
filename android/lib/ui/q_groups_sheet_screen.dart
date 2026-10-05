// Cheat sheet for the Q-groups mode (issue #41): every group with its meaning
// as statement and, where it is in use, as question. Opened from the setup and
// result of the mode, never during a question.
import 'package:flutter/material.dart';

import '../content/q_groups_data.dart';
import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import 'widgets/app_ui.dart';
import 'widgets/setting_rows.dart';

class QGroupsSheetScreen extends StatefulWidget {
  /// Language of the meanings (0 German, 1 English) and the level of the mode.
  final int lang, level;
  const QGroupsSheetScreen({super.key, this.lang = 0, this.level = 1});

  @override
  State<QGroupsSheetScreen> createState() => _QGroupsSheetScreenState();
}

class _QGroupsSheetScreenState extends State<QGroupsSheetScreen> {
  bool _all = false;

  TextStyle _mono(Color color, double size, {bool bold = false}) =>
      TextStyle(fontFamily: 'CwMono', fontSize: size, color: color, fontWeight: bold ? FontWeight.bold : null);

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final lang = widget.lang == 0 ? 'de' : 'en';
    final upTo = _all ? qgLevels : widget.level;
    return ValueListenableBuilder<int>(
      valueListenable: Strings.lang,
      builder: (context, _, _) => Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(
          backgroundColor: c.background,
          title: appBarTitle(c, Strings.t('qg_sheet')),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: c.textMuted),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            AppCard(child: Text(Strings.t('qg_sheet_note'), style: _mono(c.textMuted, 12))),
            const SizedBox(height: 12),
            SettingsCard(children: [
              SegmentRow(
                label: Strings.t('qg_sheet_scope'),
                options: [Strings.t('qg_sheet_mine'), Strings.t('qg_sheet_all')],
                selected: _all ? 1 : 0,
                onChanged: (i) => setState(() => _all = i == 1),
              ),
            ]),
            for (var l = 1; l <= upTo; l++) ...[
              const SizedBox(height: 12),
              AppCaption(Strings.t('qg_sheet_level').replaceAll('{n}', '$l')),
              const SizedBox(height: 6),
              AppCard(
                child: Column(children: [
                  for (final g in qGroups.where((g) => g.level == l)) _row(c, g, lang, g.code == _lastOf(l)),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _lastOf(int level) => qGroups.lastWhere((g) => g.level == level).code;

  Widget _row(AppColors c, QGroup g, String lang, bool last) {
    final t = g.text(lang);
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 60, child: Text(g.code, style: _mono(c.accent, 16, bold: true))),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.statement, style: _mono(c.textPrimary, 14)),
            if (t.question != null) Text('? ${t.question}', style: _mono(c.textMuted, 12)),
          ]),
        ),
      ]),
    );
  }
}
