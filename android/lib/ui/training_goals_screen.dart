// Training goals (DECISIONS.md "Training goals"): per training a target per
// lever and the order to reach them, worked through one after the other.
// This screen only stores goals and order; the values themselves stay in the
// training's own settings.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../content/charset_content.dart';
import '../content/cw_content.dart' show kochSequenceChars;
import '../content/echo_suggestions.dart' show kGiveWpmCap;
import '../content/training_goals.dart';
import '../content/training_profile.dart';
import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import 'widgets/app_ui.dart';
import 'widgets/goal_suggestion_card.dart';

/// The current values of a training, read from its profile (the same
/// defaults as the training screens).
Future<GoalValues> loadGoalValues(String kind) async {
  final p = await SharedPreferences.getInstance();
  final pf = await TrainingProfile.open(kind);
  final choice = CharsetChoice.load(pf);
  final seq = kochSequenceChars(
    (p.getInt('kochSeq') ?? 0).clamp(0, 4),
    (p.getString('customKochChars') ?? '').isNotEmpty
        ? p.getString('customKochChars')!
        : 'esno0tqr5ucd9al8ix1myj7h4gvkfz3b.6/w2p?',
    licwCarouselStart: (p.getInt('licwCarouselStart') ?? 0).clamp(0, 13),
  );
  final echo = kind == TrainingProfile.echo;
  return GoalValues(
    koch: choice.set == CharSet.koch,
    kochLevel: (pf.getInt('kochLevel') ?? 5).clamp(2, seq.length),
    kochTotal: seq.length,
    interChar: (pf.getInt('interCharSpace') ?? 28).clamp(3, 45),
    interWord: (pf.getInt('interWordSpace') ?? 40).clamp(6, 105),
    groups: const {0, 4}.contains(choice.engine.mode),
    groupLength: pf.getInt('groupLength') ?? 5,
    wpm: TrainingProfile.clampWpm(pf.getInt('wpm')),
    giveCap: echo ? kGiveWpmCap(p.getInt('echoAnswerWpmMax') ?? 0) : 0,
    typing: !echo && (pf.getInt('copyMode') ?? 0) == 1,
    straightKey: echo && (p.getInt('keyerMode') ?? 0) == 4,
  );
}

/// Entry from the start page and the achievements page: both trainings side
/// by side. From a training's own settings the editor sits inside the sheet.
class TrainingGoalsScreen extends StatelessWidget {
  final String initialKind;
  const TrainingGoalsScreen({
    super.key,
    this.initialKind = TrainingProfile.hear,
  });

  static const _kinds = [TrainingProfile.hear, TrainingProfile.echo];

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return DefaultTabController(
      length: 2,
      initialIndex: _kinds.indexOf(initialKind).clamp(0, 1),
      child: Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(
          backgroundColor: c.background,
          title: appBarTitle(c, Strings.t('tg_title')),
          bottom: TabBar(
            labelColor: c.accent,
            unselectedLabelColor: c.textMuted,
            indicatorColor: c.accent,
            tabs: [
              Tab(text: Strings.t('block_hear')),
              Tab(text: Strings.t('block_give')),
            ],
          ),
        ),
        body: TabBarView(
          children: [for (final k in _kinds) GoalOrderEditor(kind: k)],
        ),
      ),
    );
  }
}

/// Goals and their order of one training. [embedded]: inside another scroll
/// view (the settings sheet), without the intro header.
class GoalOrderEditor extends StatefulWidget {
  final String kind;
  final bool embedded;
  const GoalOrderEditor({super.key, required this.kind, this.embedded = false});

  @override
  State<GoalOrderEditor> createState() => _GoalOrderEditorState();
}

class _GoalOrderEditorState extends State<GoalOrderEditor> {
  List<LeverGoal>? _order;
  GoalValues? _values;
  GoalStore? _store;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = await GoalStore.open(widget.kind);
    final values = await loadGoalValues(widget.kind);
    if (!mounted) return;
    setState(() {
      _store = store;
      _order = store.order;
      _values = values;
    });
  }

  Future<void> _save(List<LeverGoal> order) async {
    setState(() => _order = order);
    await _store!.setOrder(order);
  }

  Future<void> _edit(int index) async {
    final g = _order![index];
    final v = _values!;
    final result = await showDialog<_GoalEdit>(
      context: context,
      builder: (_) => _GoalDialog(kind: widget.kind, goal: g, values: v),
    );
    if (result == null) return;
    final order = [..._order!];
    order[index] = LeverGoal(
      g.lever,
      target: result.target,
      // The start of a goal is the value when it was first set.
      start: result.target == null
          ? null
          : (g.target == null ? v.valueOf(g.lever) : g.start),
    );
    await _save(order);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final kind = widget.kind;
    final order = _order;
    final v = _values;
    if (order == null || v == null) return const SizedBox.shrink();
    final active = activeGoal(order, v);
    var pos = 0;
    final positions = [for (final g in order) g.target == null ? null : ++pos];
    return ReorderableListView(
      shrinkWrap: widget.embedded,
      physics: widget.embedded ? const NeverScrollableScrollPhysics() : null,
      padding: widget.embedded
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(16, 12, 16, 24),
      buildDefaultDragHandles: false,
      header: Padding(
        padding: EdgeInsets.fromLTRB(widget.embedded ? 0 : 4, 0, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!widget.embedded) ...[
              Text(
                Strings.t('tg_intro'),
                style: TextStyle(fontSize: 13, color: c.textPrimary),
              ),
              const SizedBox(height: 6),
            ],
            Text(
              Strings.t('tg_order_hint'),
              style: TextStyle(fontSize: 12, color: c.textFaint),
            ),
          ],
        ),
      ),
      onReorderItem: (from, to) {
        final list = [...order];
        list.insert(to, list.removeAt(from));
        _save(list);
      },
      children: [
        for (final (i, g) in order.indexed)
          _GoalRow(
            key: ValueKey('${kind}_${g.lever.name}'),
            index: i,
            kind: kind,
            goal: g,
            values: v,
            position: positions[i],
            active: identical(g, active),
            onTap: () => _edit(i),
          ),
      ],
    );
  }
}

class _GoalRow extends StatelessWidget {
  final int index;
  final String kind;
  final LeverGoal goal;
  final GoalValues values;
  final int? position;
  final bool active;
  final VoidCallback onTap;
  const _GoalRow({
    super.key,
    required this.index,
    required this.kind,
    required this.goal,
    required this.values,
    required this.position,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final g = goal;
    final reached = goalReached(g, values);
    final applies = leverApplies(g.lever, values);
    final now = leverValue(g.lever, values.valueOf(g.lever));
    final String detail;
    final String? status;
    if (g.target == null) {
      detail = Strings.t('tg_no_goal');
      status = null;
    } else {
      detail = Strings.t('tg_value_goal')
          .replaceFirst('{v}', now)
          .replaceFirst('{t}', leverValue(g.lever, g.target!));
      status = reached
          ? Strings.t('tg_reached')
          : active
          ? Strings.t('tg_active')
          : !applies
          ? _idleText(g.lever)
          : null;
    }
    final statusColor = reached || active ? c.accent : c.textFaint;
    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: active ? c.accent.withValues(alpha: 0.7) : c.border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(Icons.drag_handle, color: c.textFaint),
                  ),
                ),
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: active || reached ? c.accent : c.border,
                    ),
                  ),
                  child: Text(
                    reached
                        ? '✓'
                        : position == null
                        ? '–'
                        : '$position',
                    style: TextStyle(
                      fontSize: 13,
                      color: active || reached ? c.accent : c.textMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        leverLabel(g.lever, kind),
                        style: TextStyle(
                          fontSize: 14,
                          color: c.textPrimary,
                          fontWeight: active
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      Text(
                        detail,
                        style: TextStyle(fontSize: 12, color: c.textMuted),
                      ),
                      if (status != null)
                        Text(
                          status,
                          style: TextStyle(fontSize: 11, color: statusColor),
                        ),
                    ],
                  ),
                ),
                Icon(Icons.edit_outlined, size: 18, color: c.textFaint),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _idleText(GoalLever l) => switch (l) {
    GoalLever.wpm => Strings.t('tg_idle'),
    _ => Strings.t('tg_idle_${l.name}'),
  };
}

class _GoalEdit {
  final int? target;
  const _GoalEdit(this.target);
}

/// Sets one goal: a value with −/+, "all" for new characters, or no goal.
class _GoalDialog extends StatefulWidget {
  final String kind;
  final LeverGoal goal;
  final GoalValues values;
  const _GoalDialog({
    required this.kind,
    required this.goal,
    required this.values,
  });

  @override
  State<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<_GoalDialog> {
  late int _value;
  late bool _all; // new characters: the whole sequence

  GoalLever get _lever => widget.goal.lever;

  (int, int) get _range {
    final (lo, hi) = goalRange(_lever);
    if (_lever == GoalLever.newChars) {
      final total = widget.values.kochTotal;
      return (lo, total < lo ? lo : total);
    }
    return (lo, hi);
  }

  @override
  void initState() {
    super.initState();
    final t = widget.goal.target;
    final now = widget.values.valueOf(_lever);
    _all = _lever == GoalLever.newChars && (t == null || t == 0);
    // Without a goal yet, start from a sensible next value.
    final (lo, hi) = _range;
    _value =
        (t == null || t == 0
                ? switch (_lever) {
                    GoalLever.charSpacing => 3,
                    GoalLever.wordSpacing => 7,
                    GoalLever.newChars => hi,
                    _ => now + (lowerIsHarder(_lever) ? -1 : 1),
                  }
                : t)
            .clamp(lo, hi);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final (lo, hi) = _range;
    final now = widget.values.valueOf(_lever);
    final shown = _lever == GoalLever.newChars && _all ? 0 : _value;
    return AlertDialog(
      backgroundColor: c.surface,
      title: Text(
        leverLabel(_lever, widget.kind),
        style: TextStyle(color: c.textPrimary),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            Strings.t('tg_now').replaceFirst('{v}', leverValue(_lever, now)),
            style: TextStyle(fontSize: 13, color: c.textMuted),
          ),
          const SizedBox(height: 12),
          if (_lever == GoalLever.newChars)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                Strings.t('opt_all'),
                style: TextStyle(color: c.textPrimary),
              ),
              value: _all,
              activeThumbColor: c.accent,
              onChanged: (v) => setState(() => _all = v),
            ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                color: c.accent,
                onPressed: _all || _value <= lo
                    ? null
                    : () => setState(() => _value--),
              ),
              Expanded(
                child: Text(
                  leverValue(_lever, shown),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: c.accent,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                color: c.accent,
                onPressed: _all || _value >= hi
                    ? null
                    : () => setState(() => _value++),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, const _GoalEdit(null)),
          child: Text(
            Strings.t('tg_clear_goal'),
            style: TextStyle(color: c.textMuted),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            Strings.t('cancel'),
            style: TextStyle(color: c.textMuted),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _GoalEdit(shown)),
          child: Text(
            Strings.t('tg_set_goal'),
            style: TextStyle(color: c.accent),
          ),
        ),
      ],
    );
  }
}
