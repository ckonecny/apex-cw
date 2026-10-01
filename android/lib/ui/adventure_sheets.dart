// Sheets and pages around the text adventure screen: speed & spacing,
// settings, command overview, saved games, restart confirmation.
import 'package:flutter/material.dart';

import '../adventure/adventure_store.dart';
import '../adventure/cw_text.dart';
import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import 'adventure_screen.dart' show AdventureSettings;
import 'widgets/app_ui.dart';
import 'widgets/setting_rows.dart';

TextStyle _mono(double size, Color color, {bool bold = false}) => TextStyle(
    fontFamily: 'CwMono', fontSize: size, color: color,
    fontWeight: bold ? FontWeight.bold : FontWeight.normal);

Widget _grab(AppColors c) => Center(child: Container(
    width: 36, height: 4, margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2))));

Widget _hint(AppColors c, String text) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 8),
    child: Text(text, style: _mono(11, c.textFaint)));

/// One ⊖ value ⊕ row.
Widget _stepper(AppColors c, String label, String value, String? sub,
    VoidCallback? onMinus, VoidCallback? onPlus) {
  return Row(children: [
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: _mono(13, c.textPrimary)),
      if (sub != null) Text(sub, style: _mono(11, c.textFaint)),
    ])),
    IconButton(icon: const Icon(Icons.remove_circle_outline), color: c.accent,
        onPressed: onMinus),
    SizedBox(width: 70, child: FittedBox(fit: BoxFit.scaleDown, child: Text(value,
        textAlign: TextAlign.center, maxLines: 1, style: _mono(14, c.accent, bold: true)))),
    IconButton(icon: const Icon(Icons.add_circle_outline), color: c.accent,
        onPressed: onPlus),
  ]);
}

/// Speed and spacing, the same ranges and coupling as the Geben ⚙ sheet:
/// listening 10–60 WPM, keying "like listening" or 10–60, character
/// spacing 3–45, word spacing 6–105 and never below the character spacing.
List<Widget> _tempoRows(AppColors c, AdventureSettings s, void Function(VoidCallback) change) {
  return [
    _stepper(c, Strings.t('adv_hear'), '${s.wpm} WPM', null,
        s.wpm > 10 ? () => change(() => s.wpm--) : null,
        s.wpm < 60 ? () => change(() => s.wpm++) : null),
    if (s.straightWpm != null)
      _stepper(c, Strings.t('adv_give'), '${s.straightWpm} WPM',
          Strings.t('adv_give_measured'), null, null)
    else
    _stepper(c, Strings.t('adv_give'),
        s.giveWpm == 0 ? Strings.t('adv_give_like') : '${s.giveWpm} WPM',
        s.giveWpm == 0 ? '${s.wpm} WPM' : null,
        s.giveWpm > 0 ? () => change(() => s.giveWpm = s.giveWpm == 10 ? 0 : s.giveWpm - 1) : null,
        s.giveWpm < 60 ? () => change(() => s.giveWpm = s.giveWpm == 0 ? 10 : s.giveWpm + 1) : null),
    Divider(color: c.border, height: 1),
    _stepper(c, Strings.t('settings_char_spacing'), '${s.interChar}',
        'Dits · ${ditsToSeconds(s.interChar, s.wpm)}',
        s.interChar > 3 ? () => change(() => s.interChar--) : null,
        s.interChar < 45
            ? () => change(() {
                  s.interChar++;
                  if (s.interWord < s.interChar) s.interWord = s.interChar;
                })
            : null),
    _stepper(c, Strings.t('settings_word_spacing'), '${s.interWord}',
        'Dits · ${ditsToSeconds(s.interWord, s.wpm)}',
        s.interWord > 6 && s.interWord > s.interChar ? () => change(() => s.interWord--) : null,
        s.interWord < 105 ? () => change(() => s.interWord++) : null),
    _hint(c, Strings.t('adv_spacing_desc')),
  ];
}

Future<void> showAdventureTempoSheet(BuildContext context, AdventureSettings s,
    {required Future<void> Function() onChanged, required VoidCallback onAgain}) {
  final c = AppColors.of(context);
  return showModalBottomSheet(
    context: context,
    backgroundColor: c.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
      void change(VoidCallback f) {
        setSt(f);
        onChanged();
      }
      return SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
          _grab(c),
          Text(Strings.t('adv_tempo'), style: _mono(16, c.textPrimary, bold: true)),
          const SizedBox(height: 6),
          ..._tempoRows(c, s, change),
          AppButton(label: Strings.t('adv_again'), color: c.accent, icon: Icons.replay, onTap: onAgain),
        ]),
      ));
    }),
  );
}

Future<void> showAdventureSettingsSheet(BuildContext context, AdventureSettings s,
    {required Future<void> Function() onChanged}) {
  final c = AppColors.of(context);
  return showModalBottomSheet(
    context: context,
    backgroundColor: c.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
      void change(VoidCallback f) {
        setSt(f);
        onChanged();
      }
      Widget segment(String label, List<String> opts, int sel, ValueChanged<int> on) =>
          SegmentRow(label: label, options: opts, selected: sel, onChanged: on);
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: EdgeInsets.fromLTRB(18, 10, 18, 18 + MediaQuery.of(ctx).padding.bottom),
          children: [
            _grab(c),
            Text(Strings.t('adv_settings'), style: _mono(16, c.textPrimary, bold: true)),
            const SizedBox(height: 14),
            SettingsSectionHeader(Strings.t('adv_tempo').toUpperCase()),
            ..._tempoRows(c, s, change),
            const SizedBox(height: 8),
            SettingsSectionHeader(Strings.t('adv_input').toUpperCase()),
            segment('', [Strings.t('adv_input_paddle'), Strings.t('adv_input_keyboard')],
                s.input, (i) => change(() => s.input = i)),
            _hint(c, Strings.t('adv_input_desc')),
            SettingsSectionHeader(Strings.t('adv_send_with').toUpperCase()),
            segment('', ['<AR>', Strings.t('adv_send_k'), Strings.t('adv_send_btn')],
                s.send, (i) => change(() => s.send = i)),
            _hint(c, Strings.t('adv_send_desc')),
            SettingsSectionHeader(Strings.t('adv_cw_scope').toUpperCase()),
            segment('', [Strings.t('adv_scope_all'), Strings.t('adv_scope_first'), Strings.t('adv_scope_short')],
                s.scope.index, (i) => change(() => s.scope = CwScope.values[i])),
            _hint(c, Strings.t('adv_scope_desc')),
            SettingsSectionHeader(Strings.t('adv_show').toUpperCase()),
            segment('', [Strings.t('adv_show_always'), Strings.t('adv_show_after'), Strings.t('adv_show_tap')],
                s.show, (i) => change(() => s.show = i)),
            _hint(c, Strings.t('adv_show_desc')),
            SettingsSectionHeader(Strings.t('adv_verbosity').toUpperCase()),
            segment('', [Strings.t('adv_verb_brief'), Strings.t('adv_verb_super'), Strings.t('adv_verb_verbose')],
                s.verbosity, (i) => change(() => s.verbosity = i)),
            _hint(c, Strings.t('adv_verb_desc')),
            SettingsSectionHeader(Strings.t('adv_map').toUpperCase()),
            ToggleRow(label: Strings.t('adv_map_warn'), value: s.mapWarn,
                onChanged: (v) => change(() => s.mapWarn = v)),
            _hint(c, Strings.t('adv_map_warn_desc')),
          ],
        ),
      );
    }),
  );
}

Future<void> showAdventureCommandsSheet(BuildContext context, int part) {
  final c = AppColors.of(context);
  Widget section(String title) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: Text(Strings.t(title), style: _mono(11, c.accent).copyWith(letterSpacing: 1.2)));
  Widget row(String cmd, String descKey) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 118, child: Text(cmd, style: _mono(13, c.textPrimary, bold: true))),
        Expanded(child: Text(Strings.t(descKey), style: _mono(12, c.textMuted))),
      ]));
  return showModalBottomSheet(
    context: context,
    backgroundColor: c.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        padding: EdgeInsets.fromLTRB(18, 10, 18, 18 + MediaQuery.of(ctx).padding.bottom),
        children: [
          _grab(c),
          Text(Strings.t('adv_commands'), style: _mono(16, c.textPrimary, bold: true)),
          section('adv_cmd_go'),
          row('N S E W', 'adv_cmd_nsew'),
          row('NE NW SE SW', 'adv_cmd_diag'),
          row('U D IN OUT', 'adv_cmd_ud'),
          section('adv_cmd_short'),
          row('L', 'adv_cmd_l'),
          row('I', 'adv_cmd_i'),
          row('Z', 'adv_cmd_z'),
          row('G', 'adv_cmd_g'),
          row('OOPS …', 'adv_cmd_oops'),
          section('adv_cmd_things'),
          row('TAKE / DROP', 'adv_cmd_take'),
          row('EXAMINE, READ', 'adv_cmd_examine'),
          row('OPEN, CLOSE, PUT … IN …', 'adv_cmd_open'),
          row('TURN ON LAMP', 'adv_cmd_light'),
          row('ATTACK … WITH …', 'adv_cmd_attack'),
          row('… THEN …', 'adv_cmd_then'),
          section('adv_cmd_game'),
          row('SCORE, DIAGNOSE', 'adv_cmd_score'),
          row('BRIEF, SUPERBRIEF, VERBOSE', 'adv_cmd_verbose'),
          row('SAVE, RESTORE', 'adv_cmd_save'),
          row('RESTART, QUIT', 'adv_cmd_restart'),
          section('adv_play'),
          row(Strings.t('adv_play_tap'), 'adv_play_tap_d'),
          row(Strings.t('adv_play_hold'), 'adv_play_hold_d'),
          row(Strings.t('adv_play_pause'), 'adv_play_pause_d'),
          row(Strings.t('adv_play_word'), 'adv_play_word_d'),
          row(Strings.t('adv_play_eye'), 'adv_play_eye_d'),
          section('adv_cmd_app'),
          row('<AR>', 'adv_cmd_ar'),
          row('K', 'adv_cmd_k'),
          row('<ERR>', 'adv_cmd_err'),
          row('?', 'adv_cmd_q'),
          const SizedBox(height: 12),
          Text(Strings.t('adv_cmd_six'), style: _mono(12, c.textFaint)),
          section('adv_rules'),
          Text(Strings.t('adv_rules_$part'), style: _mono(12, c.textMuted)),
          const SizedBox(height: 8),
          Text(Strings.t('adv_rules_common'), style: _mono(12, c.textMuted)),
        ],
      ),
    ),
  );
}

/// Asks before a restart; offers to save first. Returns true to restart.
Future<bool?> confirmRestart(BuildContext context, {Future<void> Function()? onSaveFirst}) {
  final c = AppColors.of(context);
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: c.surface,
      title: Text(Strings.t('adv_new_title'), style: _mono(17, c.textPrimary, bold: true)),
      content: Text(Strings.t('adv_new_body'), style: _mono(13, c.textMuted)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: Text(Strings.t('cancel'), style: _mono(13, c.textMuted))),
        if (onSaveFirst != null)
          TextButton(
              onPressed: () async {
                await onSaveFirst();
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: Text(Strings.t('adv_save_first'), style: _mono(13, c.accent))),
        TextButton(onPressed: () => Navigator.pop(ctx, true),
            child: Text(Strings.t('adv_restart'), style: _mono(13, c.danger, bold: true))),
      ],
    ),
  );
}

String _fmtTime(DateTime t) {
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final hm = '${two(t.hour)}:${two(t.minute)}';
  if (t.year == now.year && t.month == now.month && t.day == now.day) return hm;
  return '${two(t.day)}.${two(t.month)}. $hm';
}

/// Saved games of one adventure. Pops with the chosen id ('auto' or a slot
/// id); without [pickOnly] also with 'save' or 'restart'.
class AdventureSavesScreen extends StatefulWidget {
  final AdventureStore store;
  final bool pickOnly;
  final String? title;
  const AdventureSavesScreen({super.key, required this.store, required this.pickOnly, this.title});

  @override
  State<AdventureSavesScreen> createState() => _AdventureSavesScreenState();
}

class _AdventureSavesScreenState extends State<AdventureSavesScreen> {
  SaveInfo? _auto;
  List<SaveInfo> _slots = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final a = await widget.store.autoInfo();
    final s = await widget.store.slots();
    if (mounted) {
      setState(() {
        _auto = a;
        _slots = s;
        _loaded = true;
      });
    }
  }

  Future<void> _edit(SaveInfo s) async {
    final c = AppColors.of(context);
    final ctrl = TextEditingController(text: s.name);
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(s.name, style: _mono(16, c.textPrimary, bold: true)),
        content: TextField(
          controller: ctrl,
          style: _mono(14, c.textPrimary),
          decoration: InputDecoration(labelText: Strings.t('adv_name')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'delete'),
              child: Text(Strings.t('adv_delete'), style: _mono(13, c.danger))),
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: Text(Strings.t('cancel'), style: _mono(13, c.textMuted))),
          TextButton(onPressed: () => Navigator.pop(ctx, 'rename'),
              child: Text(Strings.t('adv_rename'), style: _mono(13, c.accent, bold: true))),
        ],
      ),
    );
    if (action == 'rename' && ctrl.text.trim().isNotEmpty) {
      await widget.store.renameSlot(s.id, ctrl.text.trim());
    } else if (action == 'delete' && mounted) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: c.surface,
          title: Text(Strings.t('adv_delete_q').replaceAll('{n}', s.name),
              style: _mono(15, c.textPrimary, bold: true)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: Text(Strings.t('cancel'), style: _mono(13, c.textMuted))),
            TextButton(onPressed: () => Navigator.pop(ctx, true),
                child: Text(Strings.t('adv_delete'), style: _mono(13, c.danger, bold: true))),
          ],
        ),
      );
      if (ok == true) await widget.store.deleteSlot(s.id);
    }
    ctrl.dispose();
    _reload();
  }

  Widget _tile(AppColors c, SaveInfo s, {required bool auto}) {
    final meta = Strings.t('adv_meta')
        .replaceAll('{s}', '${s.score}')
        .replaceAll('{m}', '${s.moves}')
        .replaceAll('{r}', s.room);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.pop(context, s.id),
          onLongPress: auto ? null : () => _edit(s),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: auto ? Border.all(color: c.accent.withValues(alpha: 0.5)) : null,
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(auto ? Strings.t('adv_auto') : s.name,
                    style: _mono(14, c.textPrimary, bold: true))),
                Text(_fmtTime(s.time), style: _mono(11, c.textMuted)),
              ]),
              const SizedBox(height: 3),
              Text(meta, style: _mono(11, c.textMuted)),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        title: appBarTitle(c, widget.pickOnly && widget.title == null
            ? Strings.t('adv_restore_pick')
            : (widget.title ?? Strings.t('adv_saves'))),
        leading: IconButton(icon: Icon(Icons.arrow_back, color: c.textMuted),
            onPressed: () => Navigator.pop(context)),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (_auto != null) _tile(c, _auto!, auto: true),
                const SizedBox(height: 8),
                AppCaption(Strings.t('adv_your_saves')),
                const SizedBox(height: 8),
                if (_slots.isEmpty)
                  Text(Strings.t('adv_no_saves'), style: _mono(12, c.textFaint))
                else ...[
                  for (final s in _slots) _tile(c, s, auto: false),
                  Text(Strings.t('adv_saves_hint'), style: _mono(11, c.textFaint)),
                ],
                if (!widget.pickOnly) ...[
                  const SizedBox(height: 18),
                  AppButton(label: Strings.t('adv_save_now'), color: c.accent,
                      icon: Icons.save_outlined, onTap: () => Navigator.pop(context, 'save')),
                  const SizedBox(height: 8),
                  AppButton(label: Strings.t('adv_restart'), color: c.danger,
                      icon: Icons.restart_alt, onTap: () => Navigator.pop(context, 'restart')),
                ],
              ],
            ),
    );
  }
}
