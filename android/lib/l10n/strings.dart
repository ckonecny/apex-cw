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
    'home_generator_subtitle': ['Zufallszeichen · Wörter · Rufzeichen', 'Random Chars · Words · Callsigns'],
    'home_wifitrx_subtitle':   ['CW über UDP · cq.morserino.info', 'CW over UDP · cq.morserino.info'],
    'home_echo_subtitle':      ['Anhören · Nachsenden · Auswertung', 'Listen · Echo Back · Evaluation'],

    // ── Common ───────────────────────────────────────────────────────────
    'cancel': ['Abbrechen', 'Cancel'],
    'opt_off': ['Aus', 'Off'],
    'opt_all': ['alle', 'all'],
    'opt_unlimited': ['unbegrenzt', 'unlimited'],
    'opt_unlim_short': ['Unbegr.', 'Unlim.'],
    'opt_by_char': ['Zeichenweise', 'By Character'],
    'opt_by_word': ['Wortweise', 'By Word'],
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
    'settings_default_wpm': ['Standard-WPM', 'Default WPM'],
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
    'settings_spacing_desc': ['Abstand in Dit-Längen, wie am Morserino (normal = 3 / 7)', 'Spacing in dit lengths, as on the Morserino (normal = 3 / 7)'],
    'settings_audio_output': ['Audioausgabe', 'Audio Output'],
    'settings_audio_output_desc': ['Wird automatisch erkannt, wenn USB- oder Bluetooth-Geräte an-/abgesteckt werden.', 'Detected automatically as USB or Bluetooth devices connect and disconnect.'],
    'settings_audio_output_active': ['Aktiv: {val}', 'Active: {val}'],
    'opt_audio_auto': ['Automatisch', 'Automatic'],
    'opt_audio_speaker': ['Lautsprecher', 'Speaker'],
    'opt_audio_wired': ['Kabel/USB', 'Wired/USB'],
    'opt_audio_bluetooth': ['Bluetooth', 'Bluetooth'],
    'settings_stop_next_rep_desc': ['Pausiert nach jedem Wort: Dit = wiederholen, Dah = nächstes Wort', 'Pauses after each word: Dit = repeat, Dah = next word'],
    'settings_each_word_twice': ['Jedes Wort 2×', 'Each Word 2×'],
    'settings_group_length': ['Gruppen-Länge', 'Group Length'],
    'settings_max_word_length': ['Max. Wortlänge', 'Max Word Length'],
    'settings_max_abbrev_length': ['Max. Abkürzungslänge', 'Max Abbreviation Length'],
    'settings_common_prefixes_only': ['Nur gängige Präfixe', 'Common prefixes only'],
    'settings_think_time': ['Denkzeit', 'Think Time'],
    'settings_repeats': ['Wiederholungen', 'Repeats'],
    'settings_max_speed': ['Max. Speed', 'Max Speed'],
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
    'settings_level_includes_chars': ['Level {level} umfasst {n} Zeichen:', 'Level {level} includes {n} characters:'],
    'settings_char_hint_default': ['z.B. KMRSUAPTLO...', 'e.g. KMRSUAPTLO...'],

    // ── Content mode names (CW Generator / Echo Trainer / Koch Trainer) ────
    'mode_random': ['Zufall', 'Random'],
    'mode_words': ['Wörter', 'Words'],
    'mode_callsigns': ['Rufzeichen', 'Callsigns'],
    'mode_mixed': ['Gemischt', 'Mixed'],
    'mode_abbrevs': ['Abkürzungen', 'Abbrevs'],

    // ── CW Generator / Koch Trainer screen ───────────────────────────────
    'gen_new_char_title': ['Neu: {ch}', 'New: {ch}'],
    'gen_preview_char_title': ['Vorhören: {ch}', 'Preview: {ch}'],
    'gen_learn_new': ['Neu lernen', 'Learn New'],
    'gen_preview': ['Vorhören', 'Preview'],
    'gen_practice_echo': ['Echo üben', 'Practice Echo'],
    'repeat_upper': ['WIEDERHOLEN', 'REPEAT'],
    'next_upper': ['WEITER', 'NEXT'],
    'press_start': ['▶ START drücken', '▶ Press START'],
    'gen_preview_chars_title': ['Zeichen vorhören', 'Preview Characters'],
    'gen_preview_chars_desc': ['Ganze Kurs-Sequenz — auch noch nicht gelernte Zeichen', 'Whole course sequence — including not-yet-learned characters'],
    'get_ready': ['Bereit machen …', 'Get ready …'],
    'gen_boost_hint': [
      'Tippen zum Aus-/Einschließen — bevorzugt abgefragt ab dem Start',
      'Tap to include/exclude — practiced more from Start'],
    'gen_status_line': [
      'WPM {wpm} (eff. {ewpm}) · Abstand {ic}/{iw}',
      'WPM {wpm} (eff. {ewpm}) · Spacing {ic}/{iw}'],

    // ── Echo Trainer screen ──────────────────────────────────────────────
    'echo_trainer_title': ['Echo Trainer', 'Echo Trainer'],
    'echo_status_idle': ['Drücke START', 'Press START'],
    'echo_status_playing': ['Anhören …', 'Listening …'],
    'echo_status_receiving': ['Senden …', 'Sending …'],
    'echo_status_correct': ['✓ Richtig!', '✓ Correct!'],
    'echo_status_wrong': ['✗ Falsch', '✗ Wrong'],

    // ── Adaptive Copy mode (Koch Trainer "Adaptiv" flow) ─────────────────
    'flow_classic': ['Classic', 'Classic'],
    'flow_adaptiv': ['Adaptiv', 'Adaptive'],
    'ac_block_label': ['BLOCK {n}', 'BLOCK {n}'],
    'ac_idle_hint': ['Zuhören und auf Papier mitschreiben.', 'Listen and copy on paper.'],
    'ac_start_block': ['Block starten', 'Start Block'],
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
    'ac_done_errors': ['Fertig · {n} Fehler', 'Done · {n} errors'],
    'ac_result_title': ['Ergebnis', 'Result'],
    'ac_correct_of': ['{c} von {t} richtig', '{c} of {t} correct'],
    'ac_weak_chars': ['SCHWACHE ZEICHEN', 'WEAK CHARACTERS'],
    'ac_boost_hint': [
      'Tippen zum Aus-/Einschließen — öfter abfragen im nächsten Block',
      'Tap to include/exclude — practiced more in the next block'],
    'ac_finish': ['Beenden', 'Finish'],
    'ac_next_block': ['Nächster Block', 'Next Block'],
    'ac_spacing_up': ['Abstand verkürzt', 'Spacing tightened'],
    'ac_spacing_down': ['Abstand verlängert', 'Spacing widened'],
    'ac_char_speed_up': ['Zeichentempo erhöht', 'Char speed increased'],
    'ac_char_unlocked': ['Neues Zeichen freigeschaltet', 'New character unlocked'],
    'ac_suggestions_title': ['VORSCHLÄGE · ANTIPPEN ZUM ÄNDERN', 'SUGGESTIONS · TAP TO TOGGLE'],
    'ac_status_line': [
      'WPM {wpm} (eff. {ewpm}) · Abstand {ic}/{iw} · Trend {ema}% {trend}',
      'WPM {wpm} (eff. {ewpm}) · Spacing {ic}/{iw} · Trend {ema}% {trend}'],
    'ac_spacing_control_title': ['ABSTAND ANPASSEN', 'ADJUST SPACING'],
    'ac_spacing_control_hint': [
      'Zeichen/Wort (dits) — größer = mehr Pause',
      'Char/word (dits) — higher = more pause'],

    // ── Adaptive Mode settings ───────────────────────────────────────────
    'settings_koch_sequence_desc': [
      'Gilt für alle Trainings, die die Koch-Methode nutzen (auch Echo und Adaptiv).',
      'Applies to every training that uses the Koch method (Echo and Adaptive too).'],
    'settings_char_stats': ['Zeichenstatistik', 'Character statistics'],
    'settings_adaptive_mode': ['Adaptiver Modus', 'Adaptive Mode'],
    'settings_adaptive_mode_desc': [
      'Schwellenwerte, die steuern, wie Adaptiv Copy Tempo/Abstand anpasst und wann das nächste Koch-Zeichen freigeschaltet wird.',
      'Thresholds controlling how Adaptive Copy adjusts tempo/spacing and when the next Koch character unlocks.'],
    'settings_adaptive_threshold_range': ['Erfolgsschwelle niedrig/hoch', 'Success Threshold Low/High'],
    'settings_adaptive_ema_alpha': ['EMA-Glättung', 'EMA Smoothing'],
    'settings_adaptive_unlock_occurrences': ['Vorkommen für Freischaltung', 'Occurrences for Unlock'],
    'settings_reset_char_stats': ['Zeichenstatistik zurücksetzen', 'Reset Character Statistics'],
    'settings_reset_char_stats_confirm_title': ['Wirklich zurücksetzen?', 'Really reset?'],
    'settings_reset_char_stats_confirm_body': [
      'Löscht die gesamte gelernte Zeichenstatistik (Fehlerrate, Übungsgewicht) für alle Zeichen, unwiderruflich. Betrifft Adaptiv Copy (schwache Zeichen, Freischaltung) und den Echo Trainer ("Adapt. Zufall").',
      'Deletes all learned per-character statistics (error rate, practice weight) for every character, permanently. Affects Adaptive Copy (weak characters, unlocking) and Echo Trainer ("Adapt. Random").'],
    'settings_reset_char_stats_done': ['Zeichenstatistik zurückgesetzt.', 'Character statistics reset.'],
    'settings_view_char_stats': ['Zeichen-Statistik anzeigen', 'View Character Statistics'],

    // ── Character statistics screen ──────────────────────────────────────
    'char_stats_title': ['Zeichen-Statistik', 'Character Statistics'],
    'char_stats_desc': [
      'Übungsstand jedes aktiven Koch-Zeichens. Alle Zeichen müssen die Freischalt-Schwelle erreichen, bevor das nächste Zeichen freigeschaltet wird — nicht nur das zuletzt gelernte.',
      'Practice status of every active Koch character. All of them must clear the unlock threshold before the next character unlocks — not just the most recently learned one.'],
    'char_stats_ready_summary': ['{ready} von {total} Zeichen bereit', '{ready} of {total} characters ready'],
    'char_stats_attempts': ['{n}/{floor} Versuche', '{n}/{floor} attempts'],
    'char_stats_empty': ['Noch keine aktiven Zeichen.', 'No active characters yet.'],
  };
}
