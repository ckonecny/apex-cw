// Decodes a stream of '·', '—', ' ', '  ' symbols into characters.
// Feed symbols one by one via [add]; the [onChar] callback fires with the
// decoded character at a character boundary (' '), and additionally with
// ' ' itself at a word boundary ('  ', a double space) — the two are sent
// as distinct symbols because plain keying only pauses briefly between
// letters of the same word, so the visible word-gap needs its own signal
// rather than turning into a space after every single letter.

class MorseDecoder {
  static const table = {
    '.-':    'A', '-...': 'B', '-.-.': 'C', '-..':  'D',
    '.':     'E', '..-.': 'F', '--.':  'G', '....': 'H',
    '..':    'I', '.---': 'J', '-.-':  'K', '.-..': 'L',
    '--':    'M', '-.':   'N', '---':  'O', '.--.': 'P',
    '--.-':  'Q', '.-.':  'R', '...':  'S', '-':    'T',
    '..-':   'U', '...-': 'V', '.--':  'W', '-..-': 'X',
    '-.--':  'Y', '--..': 'Z',
    '-----': '0', '.----': '1', '..---': '2', '...--': '3',
    '....-': '4', '.....': '5', '-....': '6', '--...': '7',
    '---..': '8', '----.': '9',
    '.-.-.-': '.', '--..--': ',', '..--..': '?', '-..-.': '/',
    '-....-': '-', '-...-': '=', '.-.-.': '+', '.--.-.': '@', '---...': ':',
    // Prosigns — verified against the real device's pool[] bit patterns
    // (m32_v6.ino), same table as CwGenerator.kt's morseTable: <KA> and <KN>
    // are commonly confused but are different codes.
    '...-.-': 'SK', '-.--.': 'KN', '-.-.-': 'KA', '.-...':  'AS',
    '...-.': 'VE', '-...-.-': 'BK',
    // The rest of the firmware's decoder tree (CWtree in MorseDecoder.h):
    // German ä ö ü and "ch" (the generator's pool[] has them too), and the
    // punctuation the tree decodes but the generator cannot send. Decode
    // only: Own Text still flattens ä→AE etc., as the firmware's player does
    // (utf8umlaut in m32_v6.ino), and the engine has no codes for them.
    '.-.-': 'Ä', '---.': 'Ö', '..--': 'Ü', '----': 'CH',
    '-.-.-.': ';', '-.-.--': '!', '.-..-.': '"', '.----.': "'",
  };

  /// Decoded error sign (`<err>`, 7+ dits): "delete what I just sent".
  static const err = 'ERR';

  final void Function(String char) onChar;

  /// What an undecodable pattern yields. '*' like the firmware (tree node 63,
  /// "all unidentified characters"), so it is not mistaken for a keyed "?"
  /// (issue #37).
  final String unknown;

  String _buf = '';

  MorseDecoder({required this.onChar, this.unknown = '*'});

  void add(String symbol) {
    switch (symbol) {
      case '·': _buf += '.'; break;
      case '—': _buf += '-'; break;
      case '  ':
        _flush();
        onChar(' ');   // word gap: decode the last letter, then a visible space
        break;
      case ' ':
        _flush();      // character gap: decode the last letter, no visible space
        break;
    }
  }

  // Call after a character-gap pause to flush a partial buffer.
  void flush() => _flush();

  void _flush() {
    if (_buf.isEmpty) return;
    // Seven or more dits are the <err> prosign, as in the firmware's
    // decoder tree (MorseDecoder.h nodes 65/66 loop on further dits).
    final ch = RegExp(r'^\.{7,}$').hasMatch(_buf) ? err : (table[_buf] ?? unknown);
    onChar(ch);
    _buf = '';
  }

  void reset() { _buf = ''; }
}
