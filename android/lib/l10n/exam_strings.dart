// Texts of the exam simulation (issue #42), kept apart from strings.dart.
// key: [Deutsch, English]; the language is the app's (Strings.lang).
import '../content/exam_profile.dart';
import 'strings.dart';

class ExamStrings {
  static String t(String key) => _map[key]?[Strings.lang.value] ?? key;

  /// Display name of a profile, e.g. "Germany · 5 WPM Farnsworth".
  static String label(ExamProfile p) {
    if (p.family == ExamProfile.customFamily) return t('ex_fam_custom');
    return '${t('ex_fam_${p.family}')} · ${variant(p)}';
  }

  /// The part of the name after the country: speed, Farnsworth, figures.
  static String variant(ExamProfile p) {
    var v = p.farnsworth ? f('ex_variant_farns', [p.wpm]) : '${p.wpm} WPM';
    if (p.kind == ExamKind.figures) v += ' · ${t('ex_variant_fig')}';
    return v;
  }

  /// Replaces {0}, {1}, ... in the text of [key].
  static String f(String key, List<Object> args) {
    var s = t(key);
    for (var i = 0; i < args.length; i++) {
      s = s.replaceAll('{$i}', '${args[i]}');
    }
    return s;
  }

  static const Map<String, List<String>> _map = {
    'ex_title': ['Prüfungssimulation', 'Exam simulation'],
    'ex_subtitle': ['Freiwillige Morseprüfung üben', 'Practise the voluntary Morse exam'],
    'ex_hint': [
      'Hören wie in der Prüfung: ohne Pause und Wiederholung, danach Auswertung',
      'Receive as in the exam: no pause, no replay, then your result',
    ],
    'ex_choose': ['Prüfung wählen', 'Choose exam'],
    'ex_rules': [
      'Hören: {0} Minuten Text, höchstens {1} Fehler. Tempo {2} WPM{3}.',
      'Receive: {0} minutes of text, at most {1} errors. Speed {2} WPM{3}.',
    ],
    'ex_farns': [', Zeichen mit {0} WPM', ', characters at {0} WPM'],
    'ex_retries': [
      'In der Prüfung ist {0} Wiederholung des Teils erlaubt.',
      '{0} retry of the part is allowed in the exam.',
    ],
    'ex_chars_plain': [
      'Text: Amateurfunk-Klartext ohne Umlaute, mit Ziffern.',
      'Text: amateur-radio plain text without umlauts, with figures.',
    ],
    'ex_chars_punct': [
      'Text: Klartext ohne Umlaute, mit Ziffern und Satzzeichen (. , ? = /).',
      'Text: plain text without umlauts, with figures and punctuation (. , ? = /).',
    ],
    'ex_chars_de': [
      'Text: Klartext ohne Umlaute, mit Ziffern, . , ? = / und AR (als + tippen).',
      'Text: plain text without umlauts, with figures, . , ? = / and AR (type +).',
    ],
    'ex_chars_fig': [
      'Text: Ziffern in Fünfergruppen.',
      'Text: figures in groups of five.',
    ],
    'ex_chars_grp': [
      'Text: Buchstaben und Ziffern in Fünfergruppen.',
      'Text: letters and figures in groups of five.',
    ],
    'ex_fam_at': ['Österreich', 'Austria'],
    'ex_fam_de': ['Deutschland', 'Germany'],
    'ex_fam_uk': ['UK', 'UK'],
    'ex_fam_nz': ['Neuseeland', 'New Zealand'],
    'ex_fam_in': ['Indien', 'India'],
    'ex_fam_us': ['USA', 'USA'],
    'ex_fam_custom': ['Eigenes Profil', 'Custom'],
    'ex_src_at': [
      'Fernmeldebüro: Hören und Geben je 3 Minuten, mindestens 12 WPM. Fehlergrenze nicht veröffentlicht (hier 3).',
      'Austrian telecom authority: receive and send 3 minutes each, at least 12 WPM. Error limit not published (3 used).',
    ],
    'ex_src_de': [
      'BNetzA, freiwillige Zusatzprüfung (Beschreibung nach DK5KE): 5 WPM Farnsworth, 5 oder 12 WPM.',
      'BNetzA voluntary add-on exam (as described by DK5KE): 5 WPM Farnsworth, 5 or 12 WPM.',
    ],
    'ex_src_uk': [
      'RSGB Certificate of Competency: Klartext 3 Minuten (höchstens 4 Fehler) und Ziffern-Fünfergruppen 1 Minute (höchstens 3 Fehler). Tempo 5 bis 30 WPM.',
      'RSGB Certificate of Competency: plain text 3 minutes (at most 4 errors) and figure groups 1 minute (at most 3 errors). 5 to 30 WPM.',
    ],
    'ex_src_nz': [
      'NZART: 5 WPM, 3 Minuten, höchstens 4 Fehler, bis zu 5 Versuche. Beim Geben zählt Lesbarkeit.',
      'NZART: 5 WPM, 3 minutes, at most 4 errors, up to 5 attempts. Sending only has to be readable.',
    ],
    'ex_src_in': [
      'WPC: 5 oder 8 WPM, Hören 1 Minute fehlerfrei, Geben im selben Tempo. Quellen uneinheitlich, bitte prüfen.',
      'WPC: 5 or 8 WPM, receive 1 minute without a mistake, send at the same speed. Sources differ, please check.',
    ],
    'ex_src_us': [
      'ARRL Code Proficiency: 1 Minute fehlerfreie Mitschrift (nur Hören), Stufen bis 40 WPM.',
      'ARRL Code Proficiency: 1 minute of solid copy (receive only), levels up to 40 WPM.',
    ],
    'ex_src_custom': [
      'Eigenes Profil: du legst Tempo, Dauer, Fehlergrenze und Textart selbst fest. Es gilt für Hören und Geben.',
      'Custom profile: you set speed, duration, error limit and kind of text. It applies to receive and send.',
    ],
    'ex_variant_fig': ['Ziffern', 'Figures'],
    'ex_variant_txt': ['Text', 'Text'],
    'ex_variant_farns': ['{0} WPM Farnsworth', '{0} WPM Farnsworth'],
    'ex_receive_only': ['Nur Hören', 'Receive only'],
    'ex_speed': ['Tempo', 'Speed'],
    'ex_family': ['Land', 'Country'],
    'ex_custom_wpm': ['Tempo gesamt', 'Overall speed'],
    'ex_custom_char': ['Zeichentempo', 'Character speed'],
    'ex_custom_minutes': ['Minuten', 'Minutes'],
    'ex_custom_errors': ['Fehler', 'Errors'],
    'ex_custom_retries': ['Wiederholungen', 'Retries'],
    'ex_custom_kind': ['Textart', 'Kind of text'],
    'ex_kind_plain': ['Klartext', 'Plain text'],
    'ex_kind_figures': ['Ziffern', 'Figures'],
    'ex_kind_groups': ['Gruppen', 'Groups'],
    'ex_custom_punct': ['Satzzeichen', 'Punctuation'],
    'ex_custom_ar': ['AR am Ende (als + tippen)', 'AR at the end (type +)'],
    'ex_custom_hint': [
      'Zeichentempo über dem Gesamttempo ergibt Farnsworth-Pausen beim Hören.',
      'A character speed above the overall speed gives Farnsworth pauses when receiving.',
    ],
    'ex_disclaimer': [
      'Richtwerte aus öffentlich zugänglichen Quellen. Die offizielle Prüfung kann abweichen; '
          'in Österreich ist die Fehlergrenze nicht veröffentlicht (hier 3). Beim Geben sind Tempo und '
          'Textmenge Schätzungen der App.',
      'Guide values from public sources. The official exam may differ; '
          'in Austria the error limit is not published (3 is used here). When sending, speed and '
          'amount of text are estimates by the app.',
    ],
    'ex_attempt': ['Versuch {0} von {1}', 'Attempt {0} of {1}'],
    'ex_exhausted': [
      'Keine Wiederholung mehr übrig: Der Teil gilt wie in der Prüfung als nicht bestanden.',
      'No retry left: as in the exam, the part counts as failed.',
    ],
    'ex_retry': ['Wiederholen ({0} übrig)', 'Retry ({0} left)'],
    'ex_new_exam': ['Neue Prüfung', 'New exam'],
    'ex_start': ['Hören starten', 'Start receiving'],
    'ex_send_open': ['Geben starten', 'Start sending'],
    'ex_to_send': ['Weiter zum Geben', 'On to sending'],
    'ex_part_rx': ['Hören', 'Receive'],
    'ex_part_tx': ['Geben', 'Send'],
    'ex_start_hint': [
      'Der Text beginnt 3 Sekunden nach dem Start. Schreibe mit, nichts wird wiederholt.',
      'The text starts 3 seconds after you tap. Copy as you hear it, nothing is repeated.',
    ],
    'ex_type_hint': ['Hier mitschreiben …', 'Copy here …'],
    'ex_listening': ['Es läuft …', 'Playing …'],
    'ex_correct': ['Noch {0} s zum Korrigieren', '{0} s left to correct'],
    'ex_done_btn': ['Fertig', 'Done'],
    'ex_abort': ['Abbrechen', 'Abort'],
    'ex_passed': ['Bestanden', 'Passed'],
    'ex_failed': ['Nicht bestanden', 'Not passed'],
    'ex_errors': ['{0} Fehler (erlaubt: {1})', '{0} errors (allowed: {1})'],
    'ex_weak': ['Falsch aufgenommen: {0}', 'Copied wrong: {0}'],
    'ex_none_weak': ['Keine falschen Zeichen', 'No wrong characters'],
    'ex_played': ['Gesendet', 'Sent'],
    'ex_yours': ['Deine Mitschrift', 'Your copy'],
    'ex_again': ['Nochmal mit neuem Text', 'Again with a new text'],
    'ex_back': ['Zur Auswahl', 'Back to selection'],
    'ex_history': ['Letzte Läufe', 'Recent runs'],
    'ex_no_history': ['Noch kein Lauf', 'No run yet'],
    'ex_ready': [
      '{0}: Die letzten drei Läufe waren bestanden, du wirkst bereit.',
      '{0}: your last three runs passed, you look ready.',
    ],
    'ex_not_ready': [
      '{0}: Bestehe dreimal hintereinander, dann wirkst du bereit.',
      '{0}: pass three times in a row to look ready.',
    ],
    // Send part
    'ex_send_title': ['Prüfung: Geben', 'Exam: sending'],
    'ex_send_rules': [
      'Geben: {0} Minuten, höchstens {1} Fehler, Tempo {2} WPM (mindestens {3} WPM geschätzt), '
          'mindestens {4} % des Textes.',
      'Send: {0} minutes, at most {1} errors, speed {2} WPM (at least {3} WPM estimated), '
          'at least {4} % of the text.',
    ],
    'ex_send_text': ['Text zum Geben', 'Text to send'],
    'ex_send_paddle': [
      'Taste die Zeichen mit dem Paddle. Eine Korrektur (acht Punkte) löscht das letzte Zeichen.',
      'Key the characters with the paddle. A correction (eight dots) deletes the last character.',
    ],
    'ex_send_straight': [
      'Taste die Zeichen mit der Handtaste. Eine Korrektur (acht Punkte) löscht das letzte Zeichen.',
      'Key the characters with the straight key. A correction (eight dots) deletes the last character.',
    ],
    'ex_send_wpm_hint': [
      'Tempo des Keyers: mindestens {0} WPM wie gefordert, schneller darfst du gerne geben.',
      'Keyer speed: at least the required {0} WPM; you are welcome to send faster.',
    ],
    'ex_send_wpm_farns': [
      'Tempo des Keyers: gefordert sind {0} WPM insgesamt. Beim Geben ist das Zeichentempo frei; '
          'vorgeschlagen sind {1} WPM mit natürlichen Pausen dazwischen.',
      'Keyer speed: {0} WPM overall is required. When sending, the character speed is up to you; '
          '{1} WPM with natural pauses in between is suggested.',
    ],
    'ex_send_start': ['Geben starten', 'Start sending'],
    'ex_send_new': ['Anderen Text', 'Another text'],
    'ex_send_reached': [
      '{0} von {1} Zeichen erreicht (nötig: {2} %)',
      '{0} of {1} characters reached ({2} % needed)',
    ],
    'ex_send_speed': ['Tempo etwa {0} WPM (nötig: {1})', 'Speed about {0} WPM ({1} needed)'],
    'ex_send_estimate': [
      'Die App erkennt dein Geben mit dem Dekoder und schätzt das Tempo aus der Zeit vom ersten bis zum letzten Zeichen. '
          'Ein Prüfer beurteilt auch Rhythmus und Lesbarkeit.',
      'The app reads your keying with its decoder and estimates the speed from the time between the first and the last element. '
          'An examiner also judges rhythm and readability.',
    ],
    'ex_send_yours': ['Dein Dekodiertes', 'What was decoded'],
  };
}
