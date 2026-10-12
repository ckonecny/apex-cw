import 'dart:math';

// Echo Trainer deadlines, as in m32_v6.ino (V9.0). All spacing values are in
// dits; the firmware's interWordSpace is max(InterWord Spc, Interchar Spc + 4)
// (updateTimings()), not the raw preference.

/// Dits of the effective word space.
double effectiveWordSpaceDits(int interChar, int interWord) =>
    max(interWord, interChar + 4).toDouble();

/// Time from the end of the prompt in which the answer must BEGIN:
/// 1400 ms + inter-char + inter-word / 3 (at the prompt speed) + think time
/// (genTimer in generateCW(), SEND_WORD).
int echoStartDeadlineMs({
  required double promptWpm,
  required int interChar,
  required int interWord,
  required int thinkSeconds,
}) {
  final dit = 1200 / promptWpm;
  return (1400 + interChar * dit + effectiveWordSpaceDits(interChar, interWord) * dit / 3)
          .round() +
      thinkSeconds * 1000;
}

/// Silence after the last character, in dits at the answer speed, after
/// which the answer counts as finished: 2 x inter-char + 1 dit +
/// inter-word / 8 (interWordTimer in doPaddleIambic(), echo trainer branch).
int echoAnswerEndDits(int interChar, int interWord) =>
    (2 * interChar + 1 + effectiveWordSpaceDits(interChar, interWord) / 8).round();
