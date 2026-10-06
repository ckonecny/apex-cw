import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../content/daily_goal.dart';
import '../l10n/strings.dart';
import '../util/practice_clock.dart';
import '../theme/app_colors.dart';

String goalStreakText(int n) => n <= 0
    ? Strings.t('goal_streak_none')
    : n == 1
        ? Strings.t('goal_streak_one')
        : Strings.t('goal_streak_n').replaceFirst('{n}', '$n');

String goalSubtitle(GoalStatus g) {
  if (g.met) return Strings.t('goal_done');
  final wait = g.nextIn;
  // Spaced goal: while sessions are still missing, say when the next one counts
  // (and, while the time goal is still open, how many minutes are left).
  if (wait != null) {
    final m = (wait.inSeconds / 60).ceil();
    final timeLeft = g.minutesLeft > 0 && g.todaySeconds > 0;
    final key = timeLeft
        ? (m == 0 ? 'goal_left_now' : 'goal_left_wait')
        : (m == 0 ? 'goal_sess_now' : 'goal_sess_wait');
    return Strings.t(key).replaceFirst('{m}', '$m').replaceFirst('{n}', '${g.minutesLeft}');
  }
  return g.todaySeconds == 0 && g.streak == 0
      ? Strings.t('goal_hint').replaceFirst('{n}', '${g.goalSeconds ~/ 60}')
      : Strings.t('goal_left').replaceFirst('{n}', '${g.minutesLeft}');
}

/// Progress ring (partial progress shown as an arc, a check when met).
class GoalRing extends StatelessWidget {
  final GoalStatus status;
  final double size;
  final bool label;
  const GoalRing({super.key, required this.status, this.size = 72, this.label = true});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final color = status.met ? c.accent : c.info;
    return SizedBox(
      width: size, height: size,
      child: Stack(alignment: Alignment.center, children: [
        CustomPaint(size: Size.square(size), painter: _RingPainter(
            status.progress, color, c.border, size * 0.1)),
        if (label)
          MediaQuery.withNoTextScaling(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              status.met
                  ? Icon(Icons.check, color: c.accent, size: size * 0.3)
                  : Text('${status.sessionsGoal > 0 ? status.sessionsDone : status.minutesToday}', style: TextStyle(
                      fontSize: size * 0.27, color: c.textPrimary)),
              Text(Strings.t('goal_of_min').replaceFirst('{n}',
                  '${status.sessionsGoal > 0 ? status.sessionsGoal : status.goalSeconds ~/ 60}'),
                  style: TextStyle(fontSize: size * 0.14, color: c.textMuted)),
            ],
          )),
      ]),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress, stroke;
  final Color color, track;
  _RingPainter(this.progress, this.color, this.track, this.stroke);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    final base = Paint()..style = PaintingStyle.stroke..strokeWidth = stroke..color = track;
    canvas.drawArc(rect, 0, 2 * math.pi, false, base);
    if (progress > 0) {
      final arc = Paint()..style = PaintingStyle.stroke..strokeWidth = stroke
        ..strokeCap = StrokeCap.round..color = color;
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress, false, arc);
    }
  }

  @override
  bool shouldRepaint(_RingPainter o) =>
      o.progress != progress || o.color != color || o.track != track;
}

class _WeekDots extends StatelessWidget {
  final GoalStatus status;
  const _WeekDots(this.status);

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final names = Strings.t('goal_weekdays').split(',');
    return Row(children: [
      for (var i = 0; i < 7; i++) ...[
        Column(mainAxisSize: MainAxisSize.min, children: [
          _dot(c, status.week[i]),
          const SizedBox(height: 2),
          Text(names[i], style: TextStyle(fontSize: 10,
              color: i == status.todayIndex ? c.textPrimary : c.textMuted)),
        ]),
        if (i < 6) const SizedBox(width: 10),
      ],
    ]);
  }

  Widget _dot(AppColors c, DotState s) {
    final filled = s == DotState.met || s == DotState.todayMet;
    final color = switch (s) {
      DotState.met || DotState.todayMet => c.accent,
      DotState.today => c.info,
      DotState.frozen => c.textMuted,
      _ => c.border,
    };
    return Container(
      width: 12, height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? color : Colors.transparent,
        border: Border.all(color: color, width: 1.5),
      ),
      // A frozen (grace) day: a dash through the ring.
      child: s == DotState.frozen
          ? Center(child: Container(width: 6, height: 1.5, color: color))
          : null,
    );
  }
}

/// Home-screen card: ring, streak, week. [compact] is the one-line variant
/// for tight screens.
class DailyGoalCard extends StatelessWidget {
  final GoalStatus status;
  final bool compact;
  /// Null = not tappable (no chevron), e.g. on the page the card leads to.
  final VoidCallback? onTap;
  const DailyGoalCard({super.key, required this.status, required this.compact, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final fire = Icon(Icons.local_fire_department,
        size: 18, color: status.streak > 0 ? c.warning : c.textFaint);
    final streak = Row(children: [
      fire,
      const SizedBox(width: 4),
      Expanded(child: Text(goalStreakText(status.streak), maxLines: 1,
          overflow: TextOverflow.ellipsis, style: TextStyle(
              fontSize: compact ? 14 : 15, color: c.textPrimary))),
    ]);
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: compact ? 6 : 12),
          child: Row(children: [
            GoalRing(status: status, size: compact ? 44 : 72, label: !compact),
            const SizedBox(width: 14),
            Expanded(child: compact
                ? Column(mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                    streak,
                    Text('${status.sessionsGoal > 0 ? '${status.sessionsDone}/${status.sessionsGoal} · ' : ''}'
                        '${status.minutesToday} / ${status.goalSeconds ~/ 60} min',
                        style: TextStyle(fontSize: 12, color: c.textMuted)),
                  ])
                : Column(mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                    streak,
                    const SizedBox(height: 2),
                    Text(goalSubtitle(status), maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.textMuted)),
                    const SizedBox(height: 8),
                    _WeekDots(status),
                  ])),
            if (onTap != null) Icon(Icons.chevron_right, color: c.textFaint),
          ]),
        ),
      ),
    );
  }
}

/// [DailyGoalCard] that recomputes its status on a timer, so the countdown to
/// the next counted session ticks down without leaving the screen.
class LiveGoalCard extends StatefulWidget {
  final DailyGoalSettings settings;
  final bool compact;
  final VoidCallback? onTap;
  const LiveGoalCard({super.key, required this.settings, required this.compact, this.onTap});

  @override
  State<LiveGoalCard> createState() => _LiveGoalCardState();
}

class _LiveGoalCardState extends State<LiveGoalCard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DailyGoalCard(
      status: goalStatus(PracticeClock.instance.log, widget.settings, DateTime.now()),
      compact: widget.compact, onTap: widget.onTap);
}
