import 'dart:math';

import 'head_copy_data.dart';

// Comprehension mode (issue #7): builds a round of 1-3 unrelated sentences
// from building blocks and the multiple-choice questions about them. UI-free
// and driven by an injectable Random, so every rule is unit-testable.
//
// Questions go slot by slot in sentence order (who, what, where, when). A
// question names the correct answers of the slots before it, never a later
// one, so a wrong answer does not spoil the follow-up and nothing is given
// away. Level 1 asks every slot; levels 2 and 3 ask "who" plus one other slot
// per sentence (DECISIONS.md "Head copy / comprehension").

enum HcSlot { who, what, where, when }

const hcOptionCount = 4;

class HcSentence {
  final String who;
  final bool plural;
  final HcActivity activity;
  final HcPlace place;
  final String? time;
  final bool timeFirst;
  final String text;
  const HcSentence(this.who, this.plural, this.activity, this.place, this.time, this.timeFirst, this.text);

  /// What the CW engine plays: no full stop, umlauts spelled out.
  String get cwText => hcCwText(text);
}

class HcQuestion {
  /// Index of the sentence this question is about.
  final int sentence;
  final HcSlot slot;
  final String prompt;
  final List<String> options;
  final int correct;
  const HcQuestion(this.sentence, this.slot, this.prompt, this.options, this.correct);

  String get answer => options[correct];
}

class HcRound {
  final List<HcSentence> sentences;
  final List<HcQuestion> questions;
  const HcRound(this.sentences, this.questions);
}

const _umlauts = {'ä': 'ae', 'ö': 'oe', 'ü': 'ue', 'Ä': 'Ae', 'Ö': 'Oe', 'Ü': 'Ue', 'ß': 'ss'};

String hcCwText(String text) {
  final sb = StringBuffer();
  for (final c in text.split('')) {
    sb.write(_umlauts[c] ?? c);
  }
  var out = sb.toString();
  if (out.endsWith('.')) out = out.substring(0, out.length - 1);
  return out;
}

class HeadCopyEngine {
  final HcContent content;
  final Random _rng;

  /// Chance that a sentence has a time block.
  final double timeChance;
  /// Chance that a pair ("Anna und Max") is the subject.
  final double pairChance;

  HeadCopyEngine(this.content, {Random? rng, this.timeChance = 0.6, this.pairChance = 0.2}) : _rng = rng ?? Random();

  /// A round of [level] sentences (1..3).
  HcRound newRound(int level) {
    final n = level.clamp(1, 3);
    final usedWho = <String>{}; // single names already in the round
    final usedVerbs = <String>{};
    final sentences = <HcSentence>[];
    for (var i = 0; i < n; i++) {
      sentences.add(_sentence(usedWho, usedVerbs, n > 1));
    }
    final questions = <HcQuestion>[];
    for (var i = 0; i < n; i++) {
      final s = sentences[i];
      final slots = n == 1
          ? [HcSlot.who, HcSlot.what, HcSlot.where, if (s.time != null) HcSlot.when]
          : [
              HcSlot.who,
              [HcSlot.what, HcSlot.where, if (s.time != null) HcSlot.when][_rng.nextInt(s.time != null ? 3 : 2)],
            ];
      for (final slot in slots) {
        questions.add(_question(i, s, slot));
      }
    }
    return HcRound(sentences, questions);
  }

  T _pick<T>(List<T> list) => list[_rng.nextInt(list.length)];

  /// The single names inside [who] ("Eva und Tom" -> Eva, Tom).
  Set<String> _members(String who) {
    final words = who.split(' ').toSet();
    return content.names.where(words.contains).toSet();
  }

  bool _overlaps(String a, String b) => _members(a).intersection(_members(b)).isNotEmpty;

  HcSentence _sentence(Set<String> usedWho, Set<String> usedVerbs, bool allowTimeFirst) {
    final usePair = _rng.nextDouble() < pairChance;
    final whoPool = [
      for (final w in usePair ? content.pairs : content.names)
        if (_members(w).intersection(usedWho).isEmpty) w
    ];
    final who = _pick(whoPool.isEmpty ? content.names : whoPool);
    usedWho.addAll(_members(who));
    final plural = content.pairs.contains(who);

    final actPool = content.activities.where((a) => !usedVerbs.contains(a.verbSg)).toList();
    final activity = _pick(actPool.isEmpty ? content.activities : actPool);
    usedVerbs.add(activity.verbSg);

    // Tag first, then a place of that tag: cities fit almost everything and
    // would otherwise crowd out the specific places.
    final tag = _pick(activity.tags.toList());
    final place = _pick(content.places.where((p) => p.tag == tag).toList());

    final time = _rng.nextDouble() < timeChance ? _pick(content.times) : null;
    final timeFirst = allowTimeFirst && time != null && _rng.nextBool();
    final text = content.phrases.sentence(who, plural, activity, place.text, time, timeFirst);
    return HcSentence(who, plural, activity, place, time, timeFirst, text);
  }

  HcQuestion _question(int index, HcSentence s, HcSlot slot) {
    final p = content.phrases;
    final String prompt, correct;
    final List<String> pool;
    var fill = const <String>[];
    switch (slot) {
      case HcSlot.who:
        prompt = p.qWho;
        correct = s.who;
        final same = s.plural ? content.pairs : content.names;
        final other = s.plural ? content.names : content.pairs;
        // Same kind first (pairs next to pairs), the other kind only to fill up.
        // Nobody the right answer also names ("Tom" next to "Eva und Tom").
        pool = [...same.where((w) => !_overlaps(w, correct))];
        fill = [...other.where((w) => !_overlaps(w, correct))];
      case HcSlot.what:
        prompt = p.qWhat(s.who, s.plural);
        correct = p.activityText(s.activity, s.plural);
        pool = [
          for (final a in content.activities)
            if (a.id != s.activity.id) p.activityText(a, s.plural)
        ];
      case HcSlot.where:
        prompt = p.qWhere(s.who, s.plural, s.activity);
        correct = s.place.text;
        pool = [
          for (final pl in content.places)
            if (s.activity.tags.contains(pl.tag) && pl.text != correct) pl.text
        ];
      case HcSlot.when:
        prompt = p.qWhen(s.who, s.plural, s.activity, s.place.text);
        correct = s.time!;
        pool = [
          for (final t in content.times)
            if (t != correct) t
        ];
    }
    final distractors = slot == HcSlot.what ? _pickWhat(pool, s) : _pickDistinct(pool, hcOptionCount - 1);
    if (distractors.length < hcOptionCount - 1) {
      distractors.addAll(_pickDistinct(fill, hcOptionCount - 1 - distractors.length));
    }
    final options = [correct, ...distractors]..shuffle(_rng);
    return HcQuestion(index, slot, prompt, options, options.indexOf(correct));
  }

  List<String> _pickDistinct(List<String> pool, int n) {
    final shuffled = [...pool.toSet()]..shuffle(_rng);
    return shuffled.take(n).toList();
  }

  /// Wrong activities: at most one that shares the verb with the right one
  /// ("repariert das Moped" next to "repariert das Fahrrad").
  List<String> _pickWhat(List<String> pool, HcSentence s) {
    final p = content.phrases;
    final verbOf = <String, String>{
      for (final a in content.activities) p.activityText(a, s.plural): a.verbSg,
    };
    final shuffled = [...pool.toSet()]..shuffle(_rng);
    final out = <String>[];
    var sameVerb = 0;
    for (final t in shuffled) {
      final shares = verbOf[t] == s.activity.verbSg;
      if (shares && sameVerb >= 1) continue;
      if (shares) sameVerb++;
      out.add(t);
      if (out.length == hcOptionCount - 1) break;
    }
    return out;
  }
}

/// Problems with a content set; empty when it is sound. Used by the tests.
List<String> hcValidate(HcContent c) {
  final problems = <String>[];
  final tagsOfPlaces = {for (final p in c.places) p.tag};
  final usedTags = <String>{};
  for (final a in c.activities) {
    usedTags.addAll(a.tags);
    for (final t in a.tags) {
      if (!tagsOfPlaces.contains(t)) problems.add('${a.id}: unknown tag $t');
    }
    final concrete = c.places.where((p) => a.tags.contains(p.tag)).length;
    if (concrete < hcOptionCount) problems.add('${a.id}: only $concrete places');
  }
  for (final t in tagsOfPlaces) {
    if (!usedTags.contains(t)) problems.add('place tag $t is used by no activity');
  }
  if (c.activities.map((a) => a.id).toSet().length != c.activities.length) problems.add('duplicate activity');
  if (c.pairs.length < hcOptionCount - 1) problems.add('too few pairs');
  if (c.names.length < hcOptionCount) problems.add('too few names');
  if (c.times.length < hcOptionCount) problems.add('too few times');
  return problems;
}
