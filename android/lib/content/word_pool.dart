import 'package:flutter/services.dart';

/// The bundled frequency word lists (assets/words/{en,de}.txt), read on the
/// Dart side only to tell the user roughly how many different words a
/// practice can draw from. The native generator reads the same files for the
/// actual draw (`CwGenerator.randomWord`), so the filters here mirror it.
class WordPool {
  final List<String> words;
  const WordPool(this.words);

  static final _cache = <int, WordPool>{};
  static final _loading = <int, Future<WordPool>>{};

  /// Already loaded list, or null (use [load] first).
  static WordPool? peek(int language) => _cache[language];

  static Future<WordPool> load(int language) {
    final lang = language == 1 ? 1 : 0;
    return _loading[lang] ??= _read(lang);
  }

  static Future<WordPool> _read(int lang) async {
    try {
      final text = await rootBundle.loadString('assets/words/${lang == 1 ? 'de' : 'en'}.txt');
      final pool = WordPool(parse(text));
      return _cache[lang] = pool;
    } catch (_) {
      return _cache[lang] = const WordPool([]);
    }
  }

  /// "word weight" lines to lowercase words.
  static List<String> parse(String text) => [
        for (final line in text.split('\n'))
          if (line.trim().isNotEmpty) line.trim().split(' ').first.toLowerCase(),
      ];

  /// Number of different words that fit: length within [minLen]..[maxLen]
  /// (0 = no limit) and, for a Koch lesson, made only of [allowedChars]
  /// (same rule as `CwGenerator.kochQualifies`). null = all characters.
  int count({int minLen = 0, int maxLen = 0, Set<String>? allowedChars}) {
    var n = 0;
    for (final w in words) {
      if (w.length < minLen || (maxLen > 0 && w.length > maxLen)) continue;
      if (allowedChars != null && !w.split('').every(allowedChars.contains)) continue;
      n++;
    }
    return n;
  }

  /// A rounded size for display: exact below 10, then steps of 5, 10 or 100.
  static int roughly(int n) {
    if (n < 10) return n;
    if (n < 100) return (n / 5).round() * 5;
    if (n < 1000) return (n / 10).round() * 10;
    return (n / 100).round() * 100;
  }
}
