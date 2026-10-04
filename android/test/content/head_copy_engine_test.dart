import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/content/head_copy_data.dart';
import 'package:next_cw_trainer/content/head_copy_engine.dart';

void main() {
  for (final content in [deContent, enContent]) {
    group('Head copy ${content.code}', () {
      test('content set is sound', () {
        expect(hcValidate(content), isEmpty);
      });

      test('every sentence fits its place and is well formed', () {
        final engine = HeadCopyEngine(content, rng: Random(1));
        for (var i = 0; i < 3000; i++) {
          final round = engine.newRound(1 + i % 3);
          expect(round.sentences, hasLength(1 + i % 3));
          final whos = <String>{};
          final verbs = <String>{};
          for (final s in round.sentences) {
            expect(s.activity.tags, contains(s.place.tag), reason: s.text);
            expect(s.text, endsWith('.'));
            expect(s.text, isNot(contains('  ')), reason: s.text);
            expect(s.text, isNot(startsWith(' ')));
            expect(s.text, contains(s.who));
            expect(s.text, contains(s.place.text));
            if (s.time != null) expect(s.text.toLowerCase(), contains(s.time!.toLowerCase()));
            expect(s.cwText, isNot(matches(RegExp(r'[äöüÄÖÜß.]'))), reason: s.text);
            for (final n in content.names.where(s.who.split(' ').contains)) {
              expect(whos.add(n), isTrue, reason: 'same person twice');
            }
            expect(verbs.add(s.activity.verbSg), isTrue, reason: 'same verb twice');
          }
        }
      });

      test('questions: four distinct options, one right, none given away', () {
        final engine = HeadCopyEngine(content, rng: Random(2));
        for (var i = 0; i < 3000; i++) {
          final round = engine.newRound(1 + i % 3);
          for (final q in round.questions) {
            final s = round.sentences[q.sentence];
            expect(q.options, hasLength(hcOptionCount), reason: q.prompt);
            expect(q.options.toSet(), hasLength(hcOptionCount), reason: '${q.prompt} ${q.options}');
            expect(q.options[q.correct], isNotEmpty);
            // A question never names a later slot.
            switch (q.slot) {
              case HcSlot.who:
                if (s.activity.rest.isNotEmpty) expect(q.prompt, isNot(contains(s.activity.rest)));
                expect(q.prompt, isNot(contains(s.place.text)));
              case HcSlot.what:
                expect(q.prompt, isNot(contains(s.place.text)));
                expect(q.prompt, contains(s.who));
              case HcSlot.where:
                if (s.time != null) expect(q.prompt, isNot(contains(s.time!)));
                expect(q.prompt, contains(s.who));
              case HcSlot.when:
                expect(q.prompt, contains(s.place.text));
            }
            if (q.slot == HcSlot.who) {
              final right = content.names.where(s.who.split(' ').contains).toSet();
              for (final o in q.options.where((o) => o != q.answer)) {
                expect(content.names.where(o.split(' ').contains).toSet().intersection(right), isEmpty,
                    reason: '$o overlaps ${q.answer}');
              }
            }
            // Wrong places still fit the activity.
            if (q.slot == HcSlot.where) {
              for (final o in q.options) {
                final p = content.places.firstWhere((p) => p.text == o);
                expect(s.activity.tags, contains(p.tag), reason: o);
              }
            }
          }
        }
      });

      test('level 1 asks every slot, levels 2 and 3 who plus one more per sentence', () {
        final engine = HeadCopyEngine(content, rng: Random(3));
        for (var i = 0; i < 500; i++) {
          final one = engine.newRound(1);
          expect(one.questions.map((q) => q.slot).toList(), [
            HcSlot.who,
            HcSlot.what,
            HcSlot.where,
            if (one.sentences.first.time != null) HcSlot.when,
          ]);
          final three = engine.newRound(3);
          expect(three.questions.where((q) => q.slot == HcSlot.who), hasLength(3));
          expect(three.questions.length, inInclusiveRange(6, 6));
        }
      });

      test('at most one wrong activity shares the verb', () {
        final engine = HeadCopyEngine(content, rng: Random(4));
        for (var i = 0; i < 2000; i++) {
          final round = engine.newRound(1);
          final q = round.questions.firstWhere((q) => q.slot == HcSlot.what);
          final s = round.sentences.first;
          final verb = s.plural ? s.activity.verbPl : s.activity.verbSg;
          final sharing = q.options.where((o) => o.startsWith('$verb ') || o == verb).length;
          expect(sharing, lessThanOrEqualTo(2), reason: q.options.toString());
        }
      });
    });
  }

  test('German word order: time, then place before an indefinite object', () {
    HcActivity act(String sg, String pl, String rest) => deContent.activities.firstWhere((a) => a.verbSg == sg && a.rest == rest);
    String de(String who, HcActivity a, String place, String? time, [bool first = false]) =>
        deContent.phrases.sentence(who, false, a, place, time, first);
    expect(de('Nina', act('isst', 'essen', 'eine Birne'), 'zu Hause', 'heute'), 'Nina isst heute zu Hause eine Birne.');
    expect(de('Tom', act('geht', 'gehen', 'schwimmen'), 'in Salzburg', 'am Mittwoch', true),
        'Am Mittwoch geht Tom in Salzburg schwimmen.');
    expect(de('Anna', act('repariert', 'reparieren', 'das Fahrrad'), 'in der Werkstatt', 'heute'),
        'Anna repariert heute das Fahrrad in der Werkstatt.');
    expect(de('Max', act('trinkt', 'trinken', 'Kaffee'), 'im Park', null), 'Max trinkt im Park Kaffee.');
    expect(de('Eva', act('wandert', 'wandern', ''), 'im Wald', 'am Abend'), 'Eva wandert am Abend im Wald.');
    expect(deContent.phrases.qWhen('Tom', false, act('geht', 'gehen', 'schwimmen'), 'in Salzburg'),
        'Wann geht Tom in Salzburg schwimmen?');
  });

  test('cwText spells umlauts out and drops the full stop', () {
    expect(hcCwText('Anna kocht in der Küche.'), 'Anna kocht in der Kueche');
  });
}
