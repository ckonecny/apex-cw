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
  };

  final void Function(String char) onChar;

  String _buf = '';

  MorseDecoder({required this.onChar});

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
    final ch = table[_buf] ?? '?';
    onChar(ch);
    _buf = '';
  }

  void reset() { _buf = ''; }
}
