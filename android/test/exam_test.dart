import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:next_cw_trainer/content/exam_grading.dart';
import 'package:next_cw_trainer/content/exam_log.dart';
import 'package:next_cw_trainer/content/exam_profile.dart';
import 'package:next_cw_trainer/content/exam_texts.dart';
import 'package:next_cw_trainer/content/exam_texts_en.dart';

void main() {
  test('Farnsworth 5/9 stretches the gaps so a PARIS word takes 12 s', () {
    final p = examProfileById('de5f');
    expect(p.charWpm, 9);
    expect(p.interChar, 9);
    expect(p.interWord, 22);
    final dit = 1.2 / p.charWpm;
    final word = (50 + 4 * (p.interChar - 3) + (p.interWord - 7)) * dit;
    // 4 inter-character gaps and the word gap grow; ~12 s per word.
    expect(word, closeTo(12, 0.6));
  });

  test('standard profiles keep the standard spacing', () {
    expect(examAt12.interChar, 3);
    expect(examAt12.interWord, 7);
    expect(examProfileById('de12').farnsworth, isFalse);
  });

  test('text lasts the exam time and has only allowed characters', () {
    for (final p in examProfiles.where((p) => p.kind == ExamKind.plain)) {
      final t = examText(p, Random(1)).replaceAll(' +', '');
      final u = morseUnits(t);
      expect(u, greaterThanOrEqualTo(p.targetUnits), reason: p.id);
      // At most one word over.
      expect(u, lessThan(p.targetUnits + 120), reason: p.id);
      final full = examText(p, Random(1));
      final allowed = p.punctuation ? RegExp(r'^[A-Z0-9 .,?=/+]+$') : RegExp(r'^[A-Z0-9 ]+$');
      expect(allowed.hasMatch(full), isTrue, reason: '${p.id}: $full');
      expect(full.endsWith('+'), p.prosigns);
    }
  });

  test('pool: at least 100 sentences, only allowed characters', () {
    final pool = examSentencePool;
    expect(pool.length, greaterThanOrEqualTo(100));
    expect(pool.toSet().length, pool.length);
    for (final t in pool) {
      expect(RegExp(r'^[A-Za-z0-9 ,.]+$').hasMatch(t), isTrue, reason: t);
    }
  });

  test('texts vary: none of the sentences of the run before, many different ones', () {
    for (final p in [examAt12, examDe5]) {
      final rng = Random(7);
      final pool = examSentencePool.map((s) => s.toUpperCase().replaceAll(RegExp('[.,]'), '')).toList();
      var before = <String>{};
      final seen = <String>{};
      for (var i = 0; i < 30; i++) {
        final t = examText(p, rng).replaceAll(RegExp('[.,=?/+]'), '');
        final now = {for (final s in pool) if (t.contains(s)) s};
        expect(now.intersection(before), isEmpty, reason: '${p.id} run $i');
        seen.addAll(now);
        before = now;
      }
      // 5 WPM texts are only one or two sentences, a third of them generated.
      expect(seen.length, greaterThan(p.wpm == 5 ? 15 : 30), reason: p.id);
    }
  });

  test('QSO lines are generated, texts do not repeat', () {
    final rng = Random(3);
    final texts = {for (var i = 0; i < 30; i++) examText(examAt12, rng)};
    expect(texts.length, 30);
  });

  test('errors count substitutions, omissions and extras; spaces are ignored', () {
    expect(examErrors('CQ DE OE1', 'cqdeoe1'), 0);
    expect(examErrors('CQ DE', 'CQ DX'), 1);
    expect(examErrors('CQ DE', 'CQ D'), 1);
    expect(examErrors('CQ DE', 'CQ DEE'), 1);
    expect(examErrors('CQ DE', ''), 4);
  });

  test('grade passes up to the limit and names the wrong characters', () {
    final g = gradeExamReceive('HELLO WORLD', 'HELLO WARLD', 1);
    expect(g.errors, 1);
    expect(g.passed, isTrue);
    expect(g.weakChars.single.key, 'O');
    expect(gradeExamReceive('HELLO WORLD', 'HALLO WARLD', 1).passed, isFalse);
  });

  test('results round trip and the forecast needs three passes in a row', () {
    final list = [
      for (var i = 0; i < 3; i++) ExamResult(i, 'at12', 'rx', 2, 3, ''),
    ];
    expect(examParseResults(examEncodeResults(list)).length, 3);
    expect(examReady(list, 'at12', 'rx'), isTrue);
    expect(examReady(list, 'de12', 'rx'), isNull);
    expect(examReady([...list, const ExamResult(9, 'at12', 'rx', 5, 3, '')], 'at12', 'rx'), isFalse);
    expect(examParseResults('garbage'), isEmpty);
  });

  group('send grading', () {
    // A real 12 WPM exam text: about 180 characters for 3 minutes.
    final text = examText(examAt12, Random(1));
    final threeMin = 3 * 60000;

    test('clean keying of the whole text at speed passes', () {
      final g = gradeExamSend(text, text, threeMin, examAt12);
      expect(g.errors, 0);
      expect(g.reached, g.total);
      expect(g.wpm, closeTo(12, 0.8));
      expect(g.passed, isTrue);
    });

    test('stopping early compares with the beginning only', () {
      final g = gradeExamSend(text, text.substring(0, 20), 20000, examAt12);
      expect(g.errors, 0);
      expect(g.reached, lessThan(g.total * kExamSendMinText));
      expect(g.passed, isFalse);
      // Most of the text keyed is enough.
      final most = text.substring(0, (text.length * 0.9).round());
      expect(gradeExamSend(text, most, threeMin, examAt12).enoughText, isTrue);
    });

    test('errors are counted and named, too many fail', () {
      final two = text.replaceFirst(text[0], '#').replaceFirst(text[3], '#');
      final g = gradeExamSend(text, two, threeMin, examAt12);
      expect(g.errors, lessThanOrEqualTo(2));
      expect(g.errors, greaterThan(0));
      expect(g.weakChars, isNotEmpty);
      final many = text.replaceAll(RegExp('[AEIOU]'), '#');
      final h = gradeExamSend(text, many, threeMin, examAt12);
      expect(h.errors, greaterThan(examAt12.errorLimit));
      expect(h.passed, isFalse);
    });

    test('too slow fails; speed follows the PARIS count', () {
      final g = gradeExamSend(text, text, 2 * threeMin, examAt12);
      expect(g.wpm, closeTo(6, 1));
      expect(g.fastEnough, isFalse);
      expect(g.passed, isFalse);
      expect(gradeExamSend(text, '', 0, examAt12).wpm, 0);
    });

    test('the verdict of a send result is stored', () {
      const r = ExamResult(1, 'at12', 'tx', 1, 3, '', wpm: 10, verdict: false);
      final back = examParseResults(examEncodeResults([r])).single;
      expect(back.passed, isFalse);
      expect(back.wpm, 10);
      expect(const ExamResult(1, 'at12', 'rx', 1, 3, '').passed, isTrue);
    });
  });

  group('profiles', () {
    test('ids are unique and every family has presets', () {
      final ids = examProfiles.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final f in examFamilies) {
        expect(examFamilyProfiles(f), isNotEmpty, reason: f);
      }
      expect(examFamilyProfiles('us').every((p) => !p.hasSend), isTrue);
      expect(examFamilyProfiles('uk').where((p) => p.kind == ExamKind.figures).length, 7);
    });

    test('figure and letter groups: five characters each, about the exam time', () {
      for (final p in examProfiles.where((p) => p.kind == ExamKind.figures)) {
        final groups = examText(p, Random(2)).split(' ');
        expect(groups.length, p.targetGroups);
        expect(groups.every((g) => RegExp(r'^[0-9]{5}$').hasMatch(g)), isTrue);
        // The part lasts about [minutes] at [wpm] (a PARIS word is 50 units).
        final units = morseUnits(groups.join(' '));
        expect(units / 50 / p.wpm, closeTo(p.minutes.toDouble(), p.minutes * 0.35 + 0.15), reason: p.id);
      }
      final mixed = ExamProfile.custom(kind: ExamKind.groups);
      final t = examText(mixed, Random(3));
      expect(t.split(' ').every((g) => RegExp(r'^[A-Z0-9]{5}$').hasMatch(g)), isTrue);
      expect(morseUnits(t) / 50 / mixed.wpm, closeTo(mixed.minutes.toDouble(), 0.7));
    });

    test('morse units: PARIS is 50', () {
      expect(morseUnits('PARIS'), 31 + 12);
      expect(morseUnits('PARIS PARIS'), 31 * 2 + 12 * 2 + 3 * 2 + 7 - 3 * 2 + 3 * 2 - 3 * 2 + 0);
    });

    test('custom profile: clamped, json round trip, id carries the settings', () {
      final p = ExamProfile.custom(wpm: 99, charWpm: 3, minutes: 0, errorLimit: 50,
          kind: ExamKind.figures, punctuation: true, prosigns: true);
      expect(p.wpm, ExamProfile.customMaxWpm);
      expect(p.charWpm, ExamProfile.customMaxWpm);
      expect(p.minutes, 1);
      expect(p.errorLimit, 20);
      expect(ExamProfile.custom(retries: 9).retries, 5);
      expect(p.punctuation, isFalse); // plain text only
      final q = ExamProfile.fromJson(p.toJson());
      expect(q.id, p.id);
      expect(p.copyWith(errorLimit: 2).id, isNot(p.id));
      final r = ExamProfile.custom(retries: 2);
      expect(ExamProfile.fromJson(r.toJson()).retries, 2);
      expect(r.copyWith(retries: 1).id, isNot(r.id));
      expect(ExamProfile.custom(wpm: 8, charWpm: 12).farnsworth, isTrue);
    });
  });

  group('text language', () {
    String norm(String t) => t.toUpperCase().replaceAll(RegExp('[.,]'), '');

    test('English pool is big enough and clean', () {
      expect(examSentencesEn.length, greaterThanOrEqualTo(100));
      expect(examSentencesEn.toSet().length, examSentencesEn.length);
      for (final t in examSentencesEn) {
        expect(RegExp(r'^[A-Za-z0-9 ,.]+$').hasMatch(t), isTrue, reason: t);
      }
    });

    test('exams outside Austria and Germany never use German text', () {
      final german = examSentencePool.map(norm).toList();
      final english = examSentencesEn.map(norm).toList();
      for (final p in examProfiles.where((p) => p.kind == ExamKind.plain)) {
        expect(p.lang, ['at', 'de'].contains(p.family) ? 'de' : 'en', reason: p.id);
        final rng = Random(5);
        for (var i = 0; i < 20; i++) {
          final t = norm(examText(p, rng));
          final wrong = p.lang == 'en' ? german : english;
          expect(wrong.any(t.contains), isFalse, reason: '${p.id}: $t');
          // Generated lines too: no German words.
          expect(RegExp(r'\b(ICH|UND|DER|DIE|DAS|HALLO|MEIN|RAPPORT|DEIN|FUER|WATT UND)\b').hasMatch(t),
              p.lang == 'de' ? anything : isFalse, reason: '${p.id}: $t');
        }
      }
    });

    test('QSO lines use call signs of the country', () {
      final rng = Random(9);
      final uk = {for (var i = 0; i < 40; i++) examTemplateEn('uk', rng)};
      expect(uk.any((t) => RegExp(r'\b(G|M|2E)\d[A-Z]{2,3}\b').hasMatch(t)), isTrue);
      expect(uk.any((t) => RegExp(r'\b(ZL|VU|W|K|N)\d[A-Z]{2,3}\b').hasMatch(t)), isFalse);
      final nz = {for (var i = 0; i < 40; i++) examTemplateEn('nz', rng)};
      expect(nz.any((t) => RegExp(r'\bZL\d[A-Z]{2,3}\b').hasMatch(t)), isTrue);
    });

    test('custom profile: language is kept and part of the id', () {
      final en = ExamProfile.custom(lang: 'en');
      expect(en.lang, 'en');
      expect(ExamProfile.fromJson(en.toJson()).lang, 'en');
      expect(en.id, isNot(ExamProfile.custom().id));
      expect(ExamProfile.custom(lang: 'xx').lang, 'de');
    });
  });
}
