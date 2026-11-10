import 'dart:math';

/// Text speed ("eff.") implied by the character speed and the gaps.
///
/// A standard word (PARIS) is 50 dits: 31 for the characters themselves,
/// 4 inter-character gaps and 1 inter-word gap. With the normal gaps
/// (3 / 7 dits) the result equals [wpm].
///
/// [typing] (Hören on the on-screen keyboard): the app waits for the user
/// after every word, so the inter-word gap has no effect. Only the
/// inter-character gap counts; the word gap is taken at its normal 7 dits, so
/// the value is [wpm] again once the character gap is 3 (DECISIONS.md
/// "Word gap in typing mode").
int effectiveWpm(int wpm, int interChar, int interWord, {bool typing = false}) {
  final wordGap = typing ? 7 : playedWordSpaceDits(interChar, interWord);
  return (50 * wpm / (31 + 4 * interChar + wordGap)).round();
}

/// Shortest word gap that is actually played. The firmware plays
/// max(InterWord Spc, Interchar Spc + 4) dits (updateTimings(), m32_v6.ino),
/// so a smaller setting would show one value and play another; the app
/// doesn't offer it (DECISIONS.md "Word gap: no setting below the played
/// minimum"). Keyer and WiFi Trx count the word gap on their own and keep
/// the firmware's 6..105.
int minWordSpaceDits(int interChar) => interChar + 4;

/// The word gap that is played for these settings, in dits.
int playedWordSpaceDits(int interChar, int interWord) =>
    max(interWord, minWordSpaceDits(interChar));
