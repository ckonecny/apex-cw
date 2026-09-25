import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal two-language UI text lookup for the app. No intl/ARB tooling —
/// just a static map keyed by a short id, indexed by the current language.
/// 0=Deutsch (default, matches the app's original single-language text),
/// 1=English. A "full" gen-l10n/ARB setup can replace this later if more
/// languages, plurals, or date/number formatting are ever needed; for two
/// hand-picked languages this avoids the codegen/BuildContext machinery.
class Strings {
  static final ValueNotifier<int> lang = ValueNotifier(0);

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    lang.value = (p.getInt('uiLang') ?? 0).clamp(0, 1);
  }

  static Future<void> set(int index) async {
    lang.value = index.clamp(0, 1);
    final p = await SharedPreferences.getInstance();
    await p.setInt('uiLang', lang.value);
  }

  /// Looks up [key] in the current language; falls back to the key itself
  /// (visibly wrong, easy to spot) if a translation is ever missing.
  static String t(String key) => _map[key]?[lang.value] ?? key;

  // key: [Deutsch, English]
  static const Map<String, List<String>> _map = {
    // ── Home ─────────────────────────────────────────────────────────────
    'home_keyer_subtitle':     ['Morsetaste · Iambic · Touch-Paddle', 'Morse Key · Iambic · Touch Paddle'],
    'home_wifitrx_subtitle':   ['CW über UDP · cq.morserino.info', 'CW over UDP · cq.morserino.info'],

    // ── Common ───────────────────────────────────────────────────────────
    'cancel': ['Abbrechen', 'Cancel'],
    'opt_off': ['Aus', 'Off'],
    'opt_all': ['alle', 'all'],
    'opt_unlim_short': ['Unbegr.', 'Unlim.'],
    'opt_sound': ['Sound', 'Sound'],
    'opt_display': ['Anzeige', 'Display'],
    'opt_both': ['Beides', 'Both'],
    'opt_tone_shift_off': ['Kein Shift', 'No Shift'],
    'opt_tone_shift_up': ['Hoch ½', 'Up ½'],
    'opt_tone_shift_down': ['Runter ½', 'Down ½'],

    // ── Settings screen ──────────────────────────────────────────────────
    'settings_title': ['Einstellungen', 'Settings'],
    'settings_appearance': ['Darstellung', 'Appearance'],
    'theme_system': ['System', 'System'],
    'theme_light': ['Hell', 'Light'],
    'theme_dark': ['Dunkel', 'Dark'],
    'settings_language': ['Sprache', 'Language'],
    'settings_general': ['Allgemein', 'General'],
    'settings_pitch': ['Tonhöhe (Hz)', 'Pitch (Hz)'],
    'settings_tone_softness': ['Ton-Weichheit', 'Tone Softness'],
    'settings_sequence': ['Reihenfolge', 'Sequence'],
    'settings_licw_entry_point': ['LICW Einstiegspunkt', 'LICW Entry Point'],
    'settings_custom_chars_label': ['Eigene Zeichen (Reihenfolge = Lernreihenfolge)', 'Custom Characters (order = learning order)'],
    'settings_unique_chars_detected': ['{n} eindeutige Zeichen erkannt', '{n} unique characters detected'],
    'settings_practice_set_desc': ['Eigene Zeichenauswahl für CW-Gen-Modus "Practice Set" und Boost', 'Custom character selection for CW-Gen mode "Practice Set" and Boost'],
    'settings_characters': ['Zeichen', 'Characters'],
    'settings_boost_practice_desc': ['Practice-Set-Zeichen in Zufallszeichen-Übungen häufiger ziehen', 'Draw Practice Set characters more often in Random Characters exercises'],
    'settings_mode': ['Modus', 'Mode'],
    'settings_confirm_tone': ['Bestätigungston', 'Confirmation Tone'],
    'settings_curtisb_dit': ['CurtisB Dit-Timing', 'CurtisB Dit Timing'],
    'settings_curtisb_dah': ['CurtisB Dah-Timing', 'CurtisB Dah Timing'],
    'settings_tone_shift': ['Ton-Versatz (Echo)', 'Tone Shift (Echo)'],
    'settings_acs': ['Auto-Zeichenabstand', 'AutoChar Spacing'],
    'settings_spacing': ['Abstände', 'Spacing'],
    'settings_word_spacing_desc': ['Pause nach dem letzten Zeichen, ab der ein Leerzeichen gesendet wird, in Dit-Längen (normal = 7). Der Zeichenabstand wirkt beim Tasten nicht, wie am Morserino.', 'Pause after the last element before a space is sent, in dit lengths (normal = 7). Inter-char spacing has no effect when keying, as on the Morserino.'],
    'settings_spacing_desc_echo': ['Gilt für das vorgespielte Wort, nicht für deine Antwort: Abstand in Dit-Längen zwischen den Zeichen bzw. Wörtern beim Abspielen (normal = 3 / 7). Größere Werte verlängern auch die Zeit, in der du mit der Antwort beginnen darfst. Deine Antwort wird mit 7 Dit Wortpause abgeschlossen.', 'Applies to the word played to you, not to your answer: spacing in dit lengths between characters / words during playback (normal = 3 / 7). Larger values also extend the time you have to start answering. Your answer is closed with a 7-dit word gap.'],
    'settings_spacing_desc': ['Abstand in Dit-Längen, wie am Morserino (normal = 3 / 7)', 'Spacing in dit lengths, as on the Morserino (normal = 3 / 7)'],
    'settings_audio_output': ['Audioausgabe', 'Audio Output'],
    'settings_audio_output_desc': ['Wird automatisch erkannt, wenn USB- oder Bluetooth-Geräte an-/abgesteckt werden.', 'Detected automatically as USB or Bluetooth devices connect and disconnect.'],
    'settings_audio_output_active': ['Aktiv: {val}', 'Active: {val}'],
    'opt_audio_auto': ['Automatisch', 'Automatic'],
    'opt_audio_speaker': ['Lautsprecher', 'Speaker'],
    'opt_audio_wired': ['Kabel/USB', 'Wired/USB'],
    'opt_audio_bluetooth': ['Bluetooth', 'Bluetooth'],
    'settings_group_length': ['Gruppen-Länge (Zufall)', 'Group Length (random)'],
    'settings_max_word_length': ['Max. Wortlänge (nur Wörter)', 'Max Word Length (words only)'],
    'settings_max_abbrev_length': ['Max. Abkürzungslänge (nur Abkürzungen)', 'Max Abbreviation Length (abbreviations only)'],
    'settings_common_prefixes_only': ['Nur gängige Präfixe', 'Common prefixes only'],
    'settings_think_time': ['Denkzeit', 'Think Time'],
    'block_word_of': ['Wort {n} / {t}', 'Word {n} / {t}'],
    'home_section_practice': ['Üben', 'Practice'],
    'home_section_free': ['Frei', 'Free'],
    'home_hear_hint': ['Wörter und Zeichengruppen hören, danach aufdecken', 'Listen to words and groups, then reveal'],
    'home_give_hint': ['Gehörtes mit dem Paddle nachsenden, mit Auswertung', 'Send back what you heard on the paddle, with scoring'],
    'home_keyer_hint': ['Freies Tasten mit Mithörton', 'Free keying with sidetone'],
    'home_wifitrx_hint': ['CW live mit anderen Stationen funken', 'Talk CW live with other stations'],
    'block_hear': ['Hören', 'Listen'],
    'block_give': ['Geben', 'Send'],
    'block_lesson': ['Lektion', 'Lesson'],
    'block_right': ['richtig', 'right'],
    'block_after': ['nach Wiederholung', 'after repeat'],
    'block_wrong': ['falsch', 'wrong'],
    'block_next': ['Nächster Block', 'Next block'],
    'block_end': ['Beenden', 'Finish'],
    'settings_words_per_block': ['Wörter pro Block', 'Words per block'],
    'settings_repeats': ['Wiederholungen', 'Repeats'],
    'settings_profile_hear': ['Hören', 'Listening'],
    'settings_profile_echo': ['Geben (Echo)', 'Sending (Echo)'],
    'settings_word_selection': ['Wortauswahl', 'Word selection'],
    'settings_answer_wpm': ['Gebe-Tempo (max.)', 'Answer speed (max)'],
    'settings_answer_wpm_same': ['wie Hören', 'same as prompt'],
    'settings_answer_wpm_help': ['Deine Antwort wird mit höchstens diesem Tempo erwartet. Vorgespielt wird weiter mit dem normalen Tempo.', 'Your answer is expected at this speed at most. The prompt still plays at the normal speed.'],
    'echo_answer_wpm': ['Geben', 'Answer'],
    'settings_learn_paddle_keys': ['Paddle-Tasten anlernen', 'Learn Paddle Keys'],
    'settings_analyze_key_events': ['Key-Events analysieren', 'Analyze Key Events'],
    'settings_analyze_key_events_desc': ['Adapter einstecken, Analyser starten, dann Tasten drücken.', 'Plug in adapter, start analyzer, then press keys.'],
    'settings_stop_analyzer': ['Analyser stoppen', 'Stop Analyzer'],
    'settings_start_analyzer': ['Analyser starten', 'Start Analyzer'],
    'settings_press_dit_key': ['Dit-Taste drücken …', 'Press Dit key …'],
    'settings_press_dah_key': ['Dah-Taste drücken …', 'Press Dah key …'],
    'settings_saved': ['Gespeichert: {val}', 'Saved: {val}'],
    'settings_char_hint_default': ['z.B. KMRSUAPTLO...', 'e.g. KMRSUAPTLO...'],

    // ── Content mode names (CW Generator / Echo Trainer / Koch Trainer) ────
    'mode_random': ['Zufall', 'Random'],
    'mode_words': ['Wörter', 'Words'],
    'mode_callsigns': ['Rufzeichen', 'Callsigns'],
    'mode_mixed': ['Gemischt', 'Mixed'],
    'mode_abbrevs': ['Abkürzungen', 'Abbrevs'],
    'settings_word_selection_for': ['Gilt für: {set} · {content}', 'Applies to: {set} · {content}'],
    'charset_tap_hint': ['Zeichen antippen: anhören oder per Echo üben', 'Tap a character to listen to it or practise it with echo'],
    'char_listen': ['Anhören', 'Listen'],
    'char_echo_practice': ['Mit Echo üben', 'Practise with echo'],
    'char_echo_title': ['Üben: {ch}', 'Practise: {ch}'],
    'home_hear_subtitle': ['CW Generator · Koch Trainer', 'CW Generator · Koch Trainer'],
    'home_give_subtitle': ['Echo Trainer · Nachsenden · Auswertung', 'Echo Trainer · Echo Back · Evaluation'],
    'charset_koch': ['Koch-Lektion', 'Koch lesson'],
    'charset_all': ['Alle Zeichen', 'All characters'],
    'charset_practice': ['Übungsset', 'Practice set'],

    // ── CW Generator / Koch Trainer screen ───────────────────────────────
    'repeat_upper': ['WIEDERHOLEN', 'REPEAT'],
    'next_upper': ['WEITER', 'NEXT'],
    'echo_idle_hint': ['Das Wort anhören und mit dem Paddle zurückgeben.', 'Listen to the word and key it back with the paddle.'],
    'get_ready': ['Bereit machen …', 'Get ready …'],
    'gen_status_line': [
      'WPM {wpm} (eff. {ewpm}) · Abstand {ic}/{iw}',
      'WPM {wpm} (eff. {ewpm}) · Spacing {ic}/{iw}'],

    // ── Echo Trainer screen ──────────────────────────────────────────────
    'echo_trainer_title': ['Echo Trainer', 'Echo Trainer'],
    'echo_status_idle': ['Drücke START', 'Press START'],
    'pairs_title': ['Häufige Verwechslungen (Soll → Gegeben)', 'Common mix-ups (target → given)'],
  'pairs_block': ['Verwechslungen', 'Mix-ups'],
  'echo_attempt': ['Versuch {n} von {max}', 'Attempt {n} of {max}'],
    'echo_status_playing': ['Anhören …', 'Listening …'],
    'echo_status_receiving': ['Senden …', 'Sending …'],
    'echo_status_correct': ['✓ Richtig!', '✓ Correct!'],
    'echo_status_wrong': ['✗ Falsch', '✗ Wrong'],

    // ── Adaptive Copy mode (Koch Trainer "Adaptiv" flow) ─────────────────
    'ac_block_label': ['BLOCK {n}', 'BLOCK {n}'],
    'ac_idle_hint': ['Zuhören und auf Papier mitschreiben.', 'Listen and copy on paper.'],
    'ac_listening': ['Zuhören', 'Listening'],
    'ac_group_of': ['Gruppe {n} von {total}', 'Group {n} of {total}'],
    'ac_pause': ['Pause', 'Pause'],
    'ac_resume': ['Weiter', 'Resume'],
    'ac_reveal': ['Aufdecken', 'Reveal'],
    'ac_sent_title': ['Gesendet', 'Sent'],
    'ac_sent_desc': ['Vergleiche mit deiner Mitschrift. Tippe ein Wort mit Fehler an.',
        'Compare with what you copied. Tap a word you got wrong.'],
    'ac_word_title': ['Wort {n}', 'Word {n}'],
    'ac_mark_desc': ['Tippe die Zeichen an, die du nicht richtig hattest.', 'Tap the characters you got wrong.'],
    'ac_back': ['Zurück', 'Back'],
    'settings_hear_flow': ['Ablauf', 'Flow'],
    'settings_stop_each': ['Nach jeder Gruppe anhalten', 'Stop after each group'],
    'settings_stop_each_desc': [
      'Nach jeder Gruppe wartet die App. Dit (linkes Paddle) wiederholt die Gruppe, Dah (rechtes Paddle) spielt die nächste. Wie "Stop<Next>Rep" am Morserino.',
      'After each group the app waits. Dit (left paddle) repeats the group, dah (right paddle) plays the next. Like "Stop<Next>Rep" on the Morserino.'],
    'trend_line': ['Trend {pct} % {arrow}', 'Trend {pct} % {arrow}'],
    'ac_paddle_hint': ['Paddle: Dit = wiederholen, Dah = weiter', 'Paddle: dit = repeat, dah = next'],
    'ac_done_errors': ['Fertig · {n} Fehler', 'Done · {n} errors'],
    'ac_correct_of': ['{c} von {t} richtig', '{c} of {t} correct'],
    'ac_weak_chars': ['SCHWACHE ZEICHEN', 'WEAK CHARACTERS'],
    'ac_boost_hint': [
      'Tippen zum Aus-/Einschließen — öfter abfragen im nächsten Block',
      'Tap to include/exclude — practiced more in the next block'],
    'ac_finish': ['Beenden', 'Finish'],
    'ac_next_block': ['Nächster Block', 'Next Block'],
    'echo_hear_speed_up': ['Hör-Tempo erhöht', 'Listening speed increased'],
    'echo_give_speed_up': ['Gebe-Tempo erhöht', 'Sending speed increased'],
    'ac_spacing_up': ['Abstand verkürzt', 'Spacing tightened'],
    'ac_spacing_down': ['Abstand verlängert', 'Spacing widened'],
    'ac_char_speed_up': ['Zeichentempo erhöht', 'Char speed increased'],
    'ac_char_unlocked': ['Neues Zeichen freigeschaltet', 'New character unlocked'],
    'ac_suggestions_title': ['VORSCHLÄGE · ANTIPPEN ZUM ÄNDERN', 'SUGGESTIONS · TAP TO TOGGLE'],
    'ac_spacing_control_title': ['ABSTAND ANPASSEN', 'ADJUST SPACING'],
    'ac_spacing_control_hint': [
      'Zeichen/Wort (dits) — größer = mehr Pause',
      'Char/word (dits) — higher = more pause'],

    // ── Adaptive Mode settings ───────────────────────────────────────────
    'settings_koch_sequence_desc': [
      'Gilt für alle Trainings, die die Koch-Methode nutzen (auch Echo und Adaptiv).',
      'Applies to every training that uses the Koch method (Echo and Adaptive too).'],
    'settings_adaptive_mode': ['Adaptiver Modus', 'Adaptive Mode'],
    'settings_adaptive_mode_desc': [
      'Schwellenwerte, die steuern, wie Adaptiv Copy Tempo/Abstand anpasst und wann das nächste Koch-Zeichen freigeschaltet wird.',
      'Thresholds controlling how Adaptive Copy adjusts tempo/spacing and when the next Koch character unlocks.'],
    'settings_adaptive_threshold_range': ['Erfolgsschwelle niedrig/hoch', 'Success Threshold Low/High'],
    'settings_adaptive_ema_alpha': ['EMA-Glättung', 'EMA Smoothing'],
    'settings_adaptive_unlock_occurrences': ['Vorkommen für Freischaltung', 'Occurrences for Unlock'],
    'settings_reset_char_stats': ['Zeichenstatistik zurücksetzen', 'Reset Character Statistics'],
    'settings_reset_char_stats_confirm_title': ['Wirklich zurücksetzen?', 'Really reset?'],
    'settings_reset_char_stats_confirm_body_hear': [
      'Löscht die gesamte Hör-Statistik (Fehlerquote und Übungsgewicht je Zeichen) unwiderruflich. Betrifft Adaptive Copy (Schwachzeichen, Freischalten) und die Schwachzeichen im Koch Trainer. Die Geben-Statistik bleibt.',
      'Permanently deletes all hearing statistics (error rate and practice weight per character). Affects Adaptive Copy (weak characters, unlocking) and the Koch Trainer weak characters. Sending statistics stay.'],
    'settings_reset_char_stats_confirm_body_echo': [
      'Löscht die gesamte Geben-Statistik (Fehlerquote und Übungsgewicht je Zeichen) unwiderruflich. Betrifft „Adapt. Rand.“ im Echo Trainer. Die Hör-Statistik bleibt.',
      'Permanently deletes all sending statistics (error rate and practice weight per character). Affects "Adapt. Random" in the Echo Trainer. Hearing statistics stay.'],
    'settings_reset_char_stats_done': ['Zeichenstatistik zurückgesetzt.', 'Character statistics reset.'],

    // ── Character statistics screen ──────────────────────────────────────
    'char_stats_title_hear': ['Statistik Hören', 'Statistics: hearing'],
    'char_stats_title_echo': ['Statistik Geben', 'Statistics: sending'],
    'char_stats_desc_echo': [
      'Wie sicher du jedes aktive Koch-Zeichen gibst. Die Zeichen mit den meisten Fehlern stehen oben und kommen bei „Adapt. Rand.“ öfter dran.',
      'How reliably you send each active Koch character. The characters with the most errors are on top and come up more often in "Adapt. Random".'],
    'char_stats_desc': [
      'Übungsstand jedes aktiven Koch-Zeichens. Alle Zeichen müssen die Freischalt-Schwelle erreichen, bevor das nächste Zeichen freigeschaltet wird — nicht nur das zuletzt gelernte.',
      'Practice status of every active Koch character. All of them must clear the unlock threshold before the next character unlocks — not just the most recently learned one.'],
    'char_stats_ready_summary': ['{ready} von {total} Zeichen bereit', '{ready} of {total} characters ready'],
    'char_stats_attempts': ['{n}/{floor} Versuche', '{n}/{floor} attempts'],
    'char_stats_empty': ['Noch keine aktiven Zeichen.', 'No active characters yet.'],
  };
}
