// Decoder Chars (issue #52): some Morse codes mean different letters in
// different languages, and the ITU brackets exist only in ITU-R M.1677-1.
// The firmware's decodedSymbol() (MorseDecoder.cpp, commit 1013025) swaps the
// decoded symbol per character set; this is the same table, keyed by the
// dit/dah pattern. Standard decodes exactly as before.
//
// Applies to the CW Decoder and the CW Keyer only. Trainers, games and the QSO
// bot always decode Standard, because they compare the keyed text with their
// own (<KN>, AE) — same as the firmware's decoderCharSet().
import 'package:shared_preferences/shared_preferences.dart';

/// Order = stored int (pref [decoderCharsKey]) = option order in the UI.
enum DecoderChars { standard, itu, frEsPt, svFi, daNo }

const decoderCharsKey = 'decoderChars';

// pattern → set → symbol (lower case; the decoders upper-case on demand).
const _subst = <String, Map<DecoderChars, String>>{
  '-.--.':  {DecoderChars.itu: '('},                                  // instead of <KN>
  '-.--.-': {DecoderChars.itu: ')'},
  '..-..':  {DecoderChars.itu: 'é', DecoderChars.frEsPt: 'é'},
  '.-..-':  {DecoderChars.frEsPt: 'è'},
  '-.-..':  {DecoderChars.frEsPt: 'ç'},
  '--.--':  {DecoderChars.frEsPt: 'ñ'},
  '.--.-':  {DecoderChars.frEsPt: 'à', DecoderChars.svFi: 'å', DecoderChars.daNo: 'å'},
  '.-.-':   {DecoderChars.daNo: 'æ'},                                 // instead of ä
  '---.':   {DecoderChars.daNo: 'ø'},                                 // instead of ö
};

/// The symbol for [pattern] ('.' and '-') in [set], or null when the set
/// leaves the standard decoding alone.
String? decoderCharsSymbol(String pattern, DecoderChars set) =>
    set == DecoderChars.standard ? null : _subst[pattern]?[set];

Future<DecoderChars> loadDecoderChars() async {
  final p = await SharedPreferences.getInstance();
  final i = (p.getInt(decoderCharsKey) ?? 0).clamp(0, DecoderChars.values.length - 1);
  return DecoderChars.values[i];
}
