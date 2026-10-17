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
  final wordGap = typing ? 7 : interWord;
  return (50 * wpm / (31 + 4 * interChar + wordGap)).round();
}
