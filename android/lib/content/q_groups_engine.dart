import 'dart:math';

import 'q_groups_data.dart';

// Q-groups mode (issue #41): builds a round of multiple-choice questions, one
// Q-group heard per question, four meanings to pick from. UI-free and driven
// by an injectable Random, so every rule is unit-testable
// (DECISIONS.md "Q-groups mode").
//
// A round at level L draws from all groups of level <= L; the wrong options
// come from the same pool, in the same form (question next to question), and
// never from the right one's cluster. Level 1 plays the bare group; higher
// levels add a value to the groups that take one ("QTH WIEN").

const qgOptionCount = 4;

class QgQuestion {
  final QGroup group;
  /// True for the question form ("QRZ?").
  final bool isQuestion;
  /// What the CW engine plays.
  final String cwText;
  final List<String> options;
  final int correct;
  const QgQuestion(this.group, this.isQuestion, this.cwText, this.options, this.correct);

  String get answer => options[correct];
}

class QgRound {
  final List<QgQuestion> questions;
  const QgRound(this.questions);
}

class QGroupsEngine {
  final List<QGroup> groups;
  final Random _rng;

  /// Chance for the question form where a group has one.
  final double questionChance;

  QGroupsEngine({List<QGroup>? groups, Random? rng, this.questionChance = 0.5})
      : groups = groups ?? qGroups,
        _rng = rng ?? Random();

  /// [count] questions at [level] (1..[qgLevels]) in content language [lang].
  QgRound newRound(int level, int count, String lang) {
    final l = level.clamp(1, qgLevels);
    final pool = groups.where((g) => g.level <= l).toList();
    final order = <QGroup>[];
    while (order.length < count) {
      final batch = [...pool]..shuffle(_rng);
      // No group twice in a row where the shuffle seams join.
      if (order.isNotEmpty && batch.length > 1 && batch.first.code == order.last.code) {
        batch.add(batch.removeAt(0));
      }
      order.addAll(batch);
    }
    return QgRound([for (final g in order.take(count)) _question(g, pool, l, lang)]);
  }

  QgQuestion _question(QGroup g, List<QGroup> pool, int level, String lang) {
    final asQuestion = g.text(lang).question != null && _rng.nextDouble() < questionChance;
    String? meaning(QGroup o) => asQuestion ? o.text(lang).question : o.text(lang).statement;
    final correct = meaning(g)!;
    final wrong = <String>{
      for (final o in pool)
        if (o.cluster != g.cluster && meaning(o) != null && meaning(o) != correct) meaning(o)!
    }.toList()
      ..shuffle(_rng);
    final options = [correct, ...wrong.take(qgOptionCount - 1)]..shuffle(_rng);
    return QgQuestion(g, asQuestion, _cw(g, asQuestion, level), options, options.indexOf(correct));
  }

  String _cw(QGroup g, bool asQuestion, int level) {
    if (asQuestion) return '${g.code}?';
    final tails = qgTails[g.code];
    if (level < 2 || tails == null) return g.code;
    return '${g.code} ${tails[_rng.nextInt(tails.length)]}';
  }
}
