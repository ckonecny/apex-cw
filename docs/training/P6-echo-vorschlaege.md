# Phase 6: Adaptive Vorschläge beim Echo

Status: **abgeschlossen** (Gesamttest des Testplans vom User später) · Stand: 2026-09-25

## Ziel

Nach jedem Block beim Echo Trainer macht die App auf der Ergebnis-Seite
**Vorschläge**, so wie ich es von Adaptive Copy kenne: neues Zeichen
freischalten, Hör-Tempo bzw. Abstand ändern, Gebe-Tempo erhöhen, schwache
Zeichen im nächsten Block verstärkt üben. Jeder Vorschlag hat ein Häkchen
und lässt sich mit ± nachstellen. Mit "Nächster Block" werden die
angehakten übernommen. Die Zeichenstatistik "Geben" wird dafür in allen
Echo-Varianten geführt, nach der Firmware-Gewichtung.

## Grundsatz (User, 2026-09-25): Klassisch entfällt

Der klassische Ablauf wird nicht mehr weiterentwickelt und später überall
entfernt, **Adaptiv wird der Standard** (Echo, Generator, alle
Abschnitte). Für diese Phase heißt das:

- Alles Neue gilt **nur im Blockablauf**. Kein Aufwand im klassischen Ablauf
  (auch nicht für Adaptive Speed, Wort-Zähler, Firmware-Treue dort).
- Das Entfernen selbst ist **nicht** Teil dieser Phase. Es ist als eigener
  Schritt bei Phase 7 vorgemerkt (README), weil dort ohnehin die Screens
  neu geordnet werden. Bis dahin bleibt Klassisch unverändert stehen.

## Nicht in dieser Phase

- Klassisch entfernen, Blockweise zum Standard machen: Phase 7.
- Keine Reaktionszeit, kein Trend, keine Presets, keine
  Verwechslungspaare: Phase 8.
- Keine Änderung an Adaptive Copy / Generator.
- Adaptive Speed (±1 pro Wort) wird nicht angefasst, er fällt mit Klassisch
  weg.
- Kein neuer Start-Bildschirm.

## Entscheidungen

Offen, Empfehlung zuerst:

1. **Wo erscheinen Vorschläge?** Auf der Ergebnis-Seite des Blocks, unter
   der Wortliste, im selben Aussehen wie bei Adaptive Copy
   (`_SuggestionRow`: Häkchen, ±, neues Zeichen mit Stern und "Anhören").
   Nur wenn Blockweise aktiv ist. *Empfehlung.*
2. **Tempo-Sperre bei offenen Koch-Zeichen (Konzept §9 Frage 6):**
   **Ja, wie bei Adaptive Copy.** Solange im Koch-Vorrat noch Zeichen
   freizuschalten sind, gibt es keinen Vorschlag "Hör-Tempo hoch" oder
   "Abstand enger". *Weiter* und *langsamer* bleibt erlaubt. Das
   Gebe-Tempo ist ausgenommen, weil es nie automatisch geändert wird und der
   Vorschlag nur bei Erstversuch-Quote ≥ hoch erscheint. Ohne Koch-Vorrat
   (Zufall, Wörter) gibt es diese Sperre nicht. *Empfehlung.* Alternative:
   keine Sperre beim Echo. Dann steigt das Tempo schon, obwohl noch Zeichen
   fehlen. Das passt schlecht zur Idee, erst den Vorrat zu lernen.
3. **Nach Wiederholung richtig (Konzept §9 Frage 7):** **Zählt nicht als
   Treffer.** Die Erstversuch-Quote für Vorschläge zählt nur ●. ◐ bleibt
   wie in Phase 5 getrennt sichtbar. *Empfehlung.* Grund: einfach,
   strenger als halber Treffer, und die Firmware-Gewichtung bewertet das
   Wort ohnehin nach dem ersten Versuch. Alternative: ◐ als halber
   Treffer. Das macht die Schwellen schwerer vorhersagbar.
4. **Adaptiv-Schwellen (Konzept §9 Frage 8):** **Gemeinsam**, wie
   bisher (`adaptiveLowThresholdPct`, `adaptiveHighThresholdPct`,
   `adaptiveEmaAlphaPct`, `adaptiveUnlockOccurrences`). Keine neue
   Einstellung. Pro Profil kann nachgezogen werden, wenn sich das im Alltag
   als nötig zeigt. *Empfehlung.*
5. **Zeichenstatistik "Geben" in allen Echo-Varianten** (Block-Ablauf, alle
   Inhaltsmodi, auch Wörter und Zufall), nicht mehr nur Koch "Adapt.
   Rand.". Gezählt wird **pro Wort nach dem ersten Versuch**, ein
   Wiederholungsversuch zählt nicht noch einmal. *Empfehlung.* Learn New
   Chr / Preview Char zählen nicht.
6. **Gewichtung (Firmware, siehe unten):** Erstes falsches Zeichen +4,
   Nachbarn links/rechts +2 (nur wenn sie ein anderes Zeichen sind), bei
   richtigem Wort alle Zeichen −1. Ersetzt das heutige +2/−1 pro Zeichen
   der ganzen Gruppe. Obergrenze bleibt 20 (Firmware: Größe des Vorrats).
   *Empfehlung.*
7. **Zählung für Fehlerrate/EMA:** Beim ersten Versuch zählt das erste
   falsche Zeichen als Fehler, die Zeichen **davor** als richtig, die
   **danach** gar nicht (man weiß nicht, ob sie erkannt wurden). Richtiges
   Wort: alle Zeichen richtig. *Empfehlung.* Alternative: das ganze Wort
   gilt als falsch. Das würde unschuldige Zeichen belasten.
8. **Neues Koch-Zeichen (nur Koch-Echo, Profil Geben):** Auslöser wie bei
   Adaptive Copy, aber mit der Spur "Geben": alle aktiven Zeichen über der
   hohen Schwelle mit Mindestanzahl Versuche. Annahme setzt `kochLevel` im
   Profil Geben um +1. Im selben Block, in dem ein Zeichen dazukommt, kein
   Tempo-Anstieg. *Empfehlung, entspricht Konzept.*
9. **Hör-Tempo / Abstand:** Nach jedem Block wird die Erstversuch-Quote in
   die Block-EMA eingerechnet. Zwei Blöcke in Folge ≥ hoch: erst Abstand
   enger (bis zum Zeichentempo), danach Hör-WPM +1. EMA < niedrig: Abstand
   weiter. Gleiche Engine wie Adaptive Copy (`AdaptiveCopyEngine`), eigene
   Zustandsspur pro Profil. *Empfehlung.*
10. **Gebe-Tempo:** Vorschlag +1 nur, wenn Quote ≥ hoch **und** Gebe-Tempo
    kleiner als Hör-Tempo (bei "Gebe-Tempo = wie Hören" entfällt der
    Vorschlag). Nie automatisch, Häkchen standardmäßig **aus**.
    *Empfehlung.*
11. **Schwache Zeichen:** Als antippbare Chips (wie Adaptive Copy,
    `weakCharsLifetime` auf der Spur "Geben"). Angetippte Zeichen werden im
    nächsten Block verstärkt gezogen (Boost, gleiche Mechanik wie
    `boostLevel`). Nur bei Zeichen-Inhalten (Koch, Zufall, Adapt.), nicht
    bei fertigen Wörtern. *Empfehlung.*
12. **Standard-Häkchen:** Neues Zeichen, Tempo/Abstand: **an**, Gebe-Tempo:
    **aus**, wie bei Adaptive Copy. *Empfehlung.*

## Firmware-Referenz

- `reference/Software/src/Version 6 and newer/MorsePreferences.cpp`,
  `Koch::increaseWordProbability` (≈ Z. 3251) und
  `Koch::getFailedCharIndex` (≈ Z. 3266): erstes falsches Zeichen +4,
  linker und rechter Nachbar +2 (nur bei anderem Zeichen), Wort zu kurz
  zählt als falsch ab der ersten fehlenden Stelle. Cap in
  `increaseCharProbability`: Länge des Zeichenvorrats.
- Verringern bei richtigem Wort: `Koch::decreaseWordProbability` /
  `decreaseCharProbability` (≈ Z. 3291–3305): −1 pro Zeichen, Minimum 1.
  Aufruf in `m32_v6.ino` EVAL_FEEDBACK (≈ Z. 3185/3197) bei **jedem**
  Versuch. Die App bucht bewusst nur den ersten Versuch (Entscheidung 5).
- Die Vorschlagslogik (Tempo, Abstand, Freischalten, Schwache Zeichen) hat
  **keine** Firmware-Entsprechung. Sie kommt aus Adaptive Copy.

## Ist-Zustand App

- `android/lib/ui/echo_trainer_screen.dart`:
  `_recordWord` (≈ Z. 614) hält pro Wort `WordResult` fest, mit
  `firstWrongIndex`. `_applyAdaptiveFeedback` (≈ Z. 308) schreibt nur in
  Koch-Modus 4 ("Adapt. Rand."), pro Zeichen der Gruppe, +2/−1.
  `_buildBlockResult` (≈ Z. 880) zeigt Prozent, Zahlen, Wortliste, Buttons
  "Nächster Block" / "Beenden".
- `android/lib/content/char_stats.dart`: `CharStatsStore.record(char,
  correct)` = Versuche, Fehler, EMA (α 0,2), Gewicht +2/−1, 1..20. Spuren
  `hear`/`echo`. `weakCharsLifetime(...)` für Schwachzeichen.
- `android/lib/content/adaptive_copy_engine.dart`:
  `AdaptiveCopyEngine.recordBlock(results, spacingAtCharSpeed:)` liefert
  `TempoDecision`, `shouldUnlockNextChar(activeChars)` das Freischalten.
  Schwellen: globale Adaptiv-Einstellungen.
- `android/lib/ui/adaptive_copy_body.dart`: Vorbild für Vorschlagszeilen
  (`_SuggestionRow` samt Stern und "Anhören") und den Ablauf "annehmen und
  Nächster Block". Bekannt offen aus Phase 3: `late final` beim
  Abstands-Limit.
- Gebe-Tempo: Pref `echoAnswerWpmMax` (0 = wie Hören). Profil Geben:
  `TrainingProfile` (`wpm`, `kochLevel`, `interCharSpace`,
  `interWordSpace`, `boostLevel`, `practiceChars`).

## Schritte

Jeder Schritt ist einzeln baubar und installierbar.

**6a: Statistik nach Firmware.** Neue Methode am Store, die ein Wort nach
dem ersten Versuch verbucht (Entscheidungen 5–7): Gewichte +4/+2/−1,
Versuche/Fehler/EMA nach Regel 7. Aufruf im Blockablauf nach dem ersten
Versuch, in allen Echo-Varianten außer Learn/Preview. Der alte
Einzelzeichen-Pfad (`_applyAdaptiveFeedback`) läuft nur noch im
klassischen Ablauf unverändert weiter, kein Ausbau. Unit-Tests für
Gewichte, Nachbarn, zu kurze Antwort, richtiges Wort.
Prüfung: Block üben, 📊 zeigt Werte, falsche Zeichen wandern nach oben,
Tests laufen.

**6b: Vorschläge berechnen (ohne Anzeige).** Zustand pro Profil (Block-EMA,
Blockzähler) aus der Engine. Nach jedem Block eine Entscheidung: neues
Zeichen, Abstand, Hör-Tempo, Gebe-Tempo, Schwachzeichen, mit Tempo-Sperre
und "nicht im selben Block wie neues Zeichen". Unit-Tests für die
Regeln. Prüfung: Tests, Analyzer sauber.

**6c: Ergebnis-Seite mit Vorschlägen.** Vorschlagszeilen mit Häkchen und ±,
Stern und "Anhören" beim neuen Zeichen, Chips für Schwachzeichen,
Abstand ±. Noch ohne Wirkung. Strings de/en.
Prüfung: Zeilen erscheinen nur, wenn ein Auslöser zutrifft.

**6d: Annehmen wirkt.** "Nächster Block" schreibt angehakte Werte ins
Profil Geben (Lektion, Hör-WPM, Abstände) bzw. `echoAnswerWpmMax`, setzt
Boost für angetippte Zeichen und wendet alles auf die Engine an
(CLAUDE.md Regel 2: Tempo, Abstände, Vorrat neu pushen).
Prüfung: nach Annahme klingt der nächste Block anders, ⚙ zeigt die neuen
Werte, Neustart behält sie.

**6e: Doku.** STATUS, DECISIONS, README-Tabelle, Ergebnis hier.

## Testplan (User, auf dem Gerät)

- [ ] Blockweise, Koch-Echo: nach einem Block erscheinen Vorschläge nur, wenn
      ein Auslöser zutrifft.
- [ ] Viele Wörter fehlerfrei: "Neues Zeichen" erscheint mit Stern und
      "Anhören". Annehmen: Lektion im ⚙ ist +1.
- [ ] Solange noch Koch-Zeichen offen sind, kommt kein "Hör-Tempo hoch".
- [ ] Nach neuem Zeichen im selben Block kein Tempo-Anstieg.
- [ ] Zwei gute Blöcke ohne offene Zeichen: erst Abstand enger, dann WPM +1.
- [ ] Viele Fehler: Abstand wird weiter vorgeschlagen.
- [ ] Gebe-Tempo unter Hör-Tempo und gute Quote: Vorschlag, Häkchen aus.
- [ ] Ein Zeichen absichtlich oft falsch geben: es erscheint als Chip, kommt
      im Block danach öfter.
- [ ] 📊 Geben: Werte auch in Echo mit Wörtern/Zufall, nicht nur "Adapt.
      Rand.". Hören bleibt unverändert.
- [ ] Nicht angehakte Vorschläge ändern nichts.
- [ ] Learn New Chr / Preview Char unverändert, ohne Statistik.
- [ ] Neustart: übernommene Werte bleiben.

## Ergebnis

Umgesetzt wie spezifiziert, 6a–6d einzeln installiert und vom User geprüft
(6d ohne Meldung, "passt"). Abweichungen: keine. Ergänzt:
- Labels im ⚙-Sheet klarer ("Gruppen-Länge (Zufall)", "Max. Wortlänge (nur
  Wörter)", "Max. Abkürzungslänge (nur Abkürzungen)"), weil "Max.
  Wortlänge" bei Zufall keine Wirkung hat.
- "Beenden" übernimmt angehakte Werte wie Adaptive Copy, ohne Boost.
- Boost gilt einen Block: Koch-Modi mit Übungsvorrat + Boost, "Adapt. Rand."
  mit doppeltem Gewicht.
Code: `content/echo_suggestions.dart` (Regeln, Tests in
`test/content/echo_suggestions_test.dart`), `CharStatsStore.recordWord`,
`echo_trainer_screen.dart` (`_computeSuggestions`, `_buildSuggestionRows`,
`_applyAccepted`), `SuggestionRow` jetzt öffentlich in
`adaptive_copy_body.dart`. Block-EMA unter `echoBlockEma` (global, nicht pro
Profil). Nacharbeit: Gesamttest des Testplans durch den User später; Klassisch
entfernen in Phase 7.
