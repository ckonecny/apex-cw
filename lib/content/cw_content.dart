// Koch character order and content helpers (mirrors CwGenerator.kt).
//
// Koch Sequence: the M32/LCWO/CW Academy/LICW orders below are the exact
// "plain" (45-char) portion of MorsePreferences.h's morserinoKochChars/
// lcwoKochChars/cwacKochChars/licwAllKochChars — verified against the
// upstream firmware source, not reconstructed from memory. The firmware
// appends 6 more prosign codes (K,S,N,A,E,B → <sk> <as> <kn> ... ) after
// these 45; the app doesn't support prosigns as individually orderable
// Koch characters yet, so those 6 are left out here (tracked in the
// portation canvas).
const kochSeqM32 = [
  'M','K','R','S','U','A','P','T','L','O','W','I','.',
  'N','J','E','F','0','Y','V',',','G','5','/','Q','9',
  'Z','H','3','8','B','?','4','2','7','C','1','D','6','X','-','=','+','@',':',
];
const kochSeqLcwo = [
  'K','M','U','R','E','S','N','A','P','T','L','W','I','.','J','Z','=','F',
  'O','Y',',','V','G','5','/','Q','9','2','H','3','8','B','?','4','7','C',
  '1','D','6','0','X','-','+','@',':',
];
const kochSeqCwAcademy = [
  'T','E','A','N','O','I','S','1','4','R','H','D','L','2','5','U','C','M',
  'W','3','6','?','F','Y',',','P','G','Q','7','9','/','B','V','+','K','J',
  '8','0','=','X','Z','.','-','@',':',
];
// Full LICW curriculum source (MorsePreferences.h's licwAllKochChars), the
// basis for the carousel rotation below. Uppercase K/A/S/N/E/B here are
// prosign codes (<sk> <ka> <kn> ...), not the letters — same convention as
// CWchars in m32_v6.ino.
const _licwAllKochChars = 'reatinpgslcdhofuwbkmy59,qxv73?+K=16.zj/28B40-ASNE@:';

// LICW Carousel "Entry Point" (posCarouselStart, 0-13): ports
// Koch::setupLICWkochChars() exactly — start<6 rotates an 18-char "BC1"
// window, start>=6 rotates the full 44-char "BC2" window. The 6 prosign
// markers embedded in _licwAllKochChars are dropped (this app doesn't support
// prosigns as individually orderable Koch characters yet — see the portation
// canvas), and "-@:" (never covered by any carousel window; MorsePreferences.
// cpp caps the rotation at 44 chars) is appended for parity with kochSeqLicw
// so levels above the carousel's own range still have somewhere to grow.
List<String> licwCarouselChars(int start) {
  const prosigns = {'K', 'A', 'S', 'N', 'E', 'B'};
  final s = start.clamp(0, 13);
  final buf = StringBuffer();
  if (s < 6) {
    final segLen = 18 - 3 * s;
    buf.write(_licwAllKochChars.substring(3 * s, 3 * s + segLen));
    if (s > 0) buf.write(_licwAllKochChars.substring(0, 3 * s));
  } else {
    buf.write(_licwAllKochChars.substring(0, 18));
    final segLen = 44 - 3 * s;
    buf.write(_licwAllKochChars.substring(3 * s, 3 * s + segLen));
    if (s > 6) buf.write(_licwAllKochChars.substring(18, 18 + (3 * s - 18)));
  }
  final rotated = buf.toString().split('').where((c) => !prosigns.contains(c)).join();
  return (rotated.toUpperCase() + '-@:').split('');
}

// seq: 0=M32, 1=LCWO, 2=CW Academy, 3=LICW, 4=Custom (matches M32 "Koch Sequence")
// licwCarouselStart: "LICW Carousel" entry point (0-13), only meaningful for seq=3.
List<String> kochSequenceChars(int seq, String customChars, {int licwCarouselStart = 0}) {
  switch (seq) {
    case 1: return kochSeqLcwo;
    case 2: return kochSeqCwAcademy;
    case 3: return licwCarouselChars(licwCarouselStart);
    case 4:
      final seen = <String>{};
      final out = <String>[];
      for (final c in customChars.toUpperCase().split('')) {
        if (c.trim().isEmpty) continue;
        if (seen.add(c)) out.add(c);
      }
      return out.isEmpty ? kochSeqM32 : out;
    default: return kochSeqM32;
  }
}

// Backward-compatible default (M32 native order) for call sites that don't
// yet carry a Koch Sequence preference of their own.
const kochChars = kochSeqM32;

// Returns the active character set for a given Koch level (2-based).
List<String> kochActiveChars(int level, [List<String>? sequence]) {
  final seq = sequence ?? kochChars;
  return seq.take(level.clamp(2, seq.length)).toList();
}

// Human-readable mode names (index matches CwGenerator.Mode enum in Kotlin).
const genModeNames = ['Zufallszeichen', 'Wörter', 'Rufzeichen', 'Gemischt', 'Practice Set', 'Abkürzungen'];

// Practice Set: parses a user-entered string into an ordered, de-duplicated
// char list — same rule as Koch's Custom Chars (order doesn't matter here,
// but duplicates would just skew nothing usefully).
List<String> parsePracticeChars(String input) {
  final seen = <String>{};
  final out = <String>[];
  for (final c in input.toUpperCase().split('')) {
    if (c.trim().isEmpty) continue;
    if (seen.add(c)) out.add(c);
  }
  return out;
}
