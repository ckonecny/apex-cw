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

    // ── Settings screen ──────────────────────────────────────────────────
    'settings_title': ['Einstellungen', 'Settings'],
    'settings_appearance': ['Darstellung', 'Appearance'],
    'theme_system': ['System', 'System'],
    'theme_light': ['Hell', 'Light'],
    'theme_dark': ['Dunkel', 'Dark'],
    'settings_language': ['Sprache', 'Language'],
    'settings_general': ['Allgemein', 'General'],
    'settings_default_wpm': ['Standard-WPM', 'Default WPM'],
    'settings_default_koch_level': ['Standard Koch-Level', 'Default Koch Level'],
    'settings_pitch': ['Tonhöhe (Hz)', 'Pitch (Hz)'],
    'settings_sequence': ['Reihenfolge', 'Sequence'],
    'settings_licw_entry_point': ['LICW Einstiegspunkt', 'LICW Entry Point'],
    'settings_custom_chars_label': ['Eigene Zeichen (Reihenfolge = Lernreihenfolge)', 'Custom Characters (order = learning order)'],
    'settings_unique_chars_detected': ['{n} eindeutige Zeichen erkannt', '{n} unique characters detected'],
    'settings_practice_set_desc': ['Eigene Zeichenauswahl für CW-Gen-Modus "Practice Set" und Boost', 'Custom character selection for CW-Gen mode "Practice Set" and Boost'],
    'settings_characters': ['Zeichen', 'Characters'],
    'settings_boost_practice_desc': ['Practice-Set-Zeichen in Zufallszeichen-Übungen häufiger ziehen', 'Draw Practice Set characters more often in Random Characters exercises'],
    'settings_mode': ['Modus', 'Mode'],
    'settings_confirm_tone': ['Bestätigungston', 'Confirmation Tone'],
    'settings_spacing': ['Abstände', 'Spacing'],
    'settings_spacing_desc': ['Abstand in Dit-Längen, wie am Morserino (normal = 3 / 7)', 'Spacing in dit lengths, as on the Morserino (normal = 3 / 7)'],
    'settings_stop_next_rep_desc': ['Pausiert nach jedem Wort: Dit = wiederholen, Dah = nächstes Wort', 'Pauses after each word: Dit = repeat, Dah = next word'],
    'settings_each_word_twice': ['Jedes Wort 2×', 'Each Word 2×'],
    'settings_group_length': ['Gruppen-Länge', 'Group Length'],
    'settings_max_word_length': ['Max. Wortlänge', 'Max Word Length'],
    'settings_max_abbrev_length': ['Max. Abkürzungslänge', 'Max Abbreviation Length'],
    'settings_common_prefixes_only': ['Nur gängige Präfixe', 'Common prefixes only'],
    'settings_think_time': ['Denkzeit', 'Think Time'],
    'settings_repeats': ['Wiederholungen', 'Repeats'],
    'settings_max_speed': ['Max. Speed', 'Max Speed'],
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

    // ── Echo Trainer screen ──────────────────────────────────────────────
    'echo_trainer_title': ['Echo Trainer', 'Echo Trainer'],
    'echo_status_idle': ['Drücke START', 'Press START'],
    'echo_status_playing': ['Anhören …', 'Listening …'],
    'echo_status_receiving': ['Senden …', 'Sending …'],
    'echo_status_correct': ['✓ Richtig!', '✓ Correct!'],
    'echo_status_wrong': ['✗ Falsch', '✗ Wrong'],
  };
}
