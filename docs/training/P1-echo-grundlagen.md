# Phase 1: Echo-Grundlagen

Status: **Spec zur Freigabe** · Stand: 2026-09-23

## Ziel

Im Echo Trainer kann man schneller hören als geben: Das Wort wird mit dem
Hör-Tempo vorgespielt, die Antwort gibt man mit einem eigenen, langsameren
Gebe-Tempo. Außerdem klingt das Vorspiel immer gleich, egal welcher Screen
vorher offen war. Adaptive Speed arbeitet wie am Morserino.

## Nicht in dieser Phase

- Keine getrennten Profile. Hör-Tempo, Lektion und Gruppenlänge bleiben
  vorerst gemeinsam mit dem Generator (kommt in Phase 2).
- Keine neue Oberfläche im Echo-Screen außer der Tempo-Anzeige (Phase 3).
- Keine Änderung an Zeichenstatistik, Blöcken oder Adaptiv-Ablauf (Phase 4–6).
- Denkzeit-Berechnung bleibt, wie sie ist (siehe "Später prüfen").

## Entscheidungen

Noch offen, die Empfehlung steht jeweils zuerst:

- **E1 Gebe-Tempo-Semantik** (Konzept §9 Frage 2): Obergrenze wie in der
  Firmware: Antwort-Tempo = min(Hör-Tempo, Gebe-Tempo). *Alternative:*
  ein fester Wert, der auch über dem Hör-Tempo liegen darf.
- **E2 Wertebereich:** "Aus" oder 5–50 WPM in 1er-Schritten. Die Firmware
  hat nur 5er-Schritte. 1er-Schritte sind feiner und ändern nichts am
  Ablauf. Standard ist "Aus", wie in der Firmware.
- **E3 Neuer Speicher-Schlüssel** `echoAnswerWpmMax` (0 = Aus). Der alte
  Schlüssel `echoSpeedMax` war bisher die Obergrenze für Adaptive Speed und
  steht bei den meisten auf 35. Würde man ihn weiterverwenden, bekäme er
  stillschweigend eine neue Bedeutung. Der alte Schlüssel wird nicht mehr
  gelesen.
- **E4 Adaptive Speed** wie Firmware: nach *jeder* Auswertung (auch bei
  Wiederholungen) ±1 WPM auf das Hör-Tempo, Grenzen 5–60. Die bisherige
  Obergrenze entfällt.
- **E5 Adaptiv verändertes Tempo speichern?** Empfehlung: **nein, nur für
  die laufende Sitzung** (wie heute). Die Firmware speichert es global. In
  der App würde das den CW Generator mitverstellen, solange Phase 2 fehlt.
  Ab Phase 2 wird es im Echo-Profil gespeichert.

Nach Freigabe: E1–E5 als ein Eintrag in `docs/DECISIONS.md`.

## Firmware-Referenz

`reference/Software/src/Version 6 and newer/`:

- `MorsePreferences.cpp:366-372`: "Echo Speed Max", Werte 0 = No limit,
  sonst Index × 5 WPM, Standard 0.
- `m32_v6.ino:2553-2561` (SEND_WORD/REPEAT_WORD → GET_ANSWER): nach dem
  Vorspiel gilt: Wenn Max > 0 und WPM > Max, dann `echoPromptSpeed = wpm;
  wpm = Max`. Keyer und Generator teilen sich in der Firmware *ein* WPM,
  also gilt die Absenkung für die Antwort.
- `m32_v6.ino:3166-3171` (COMPLETE_ANSWER): WPM zurück auf
  `echoPromptSpeed`, *bevor* ausgewertet wird.
- `m32_v6.ino:3208-3211` (EVAL_SETTLE): `if (speedAdapt)
  changeSpeed(echoEvalCorrect ? 1 : -1)`, also nach jeder Auswertung.
  Weil vorher schon zurückgesetzt wurde, wirkt ±1 aufs Hör-Tempo.
- `m32_v6.ino:3242-3248` `changeSpeedValue`: begrenzt auf wpmMin..wpmMax.
- `MorsePreferences.cpp:359-364`: Adaptive Speed, Standard OFF.

## Ist-Zustand App

`android/lib/ui/echo_trainer_screen.dart`:

- `_startSession()` (ca. Z. 287) setzt am Keyer Modus, CurtisB, ACS und
  Wortpause 7, am Ton Pitch und Weichheit, am Generator nur `setWpm`.
- **Fehler A:** Es gibt nie `setInterCharSpace`/`setInterWordSpace` am
  Generator. Das Vorspiel übernimmt die Abstände des letzten Screens
  (Adaptive Copy mit Farnsworth-Werten, WiFi Trx mit fix 3 Dits).
- **Fehler B:** Es gibt nie `setPracticeChars`/`setBoostLevel`. "Practice
  Set" im Echo hängt davon ab, was zuletzt gesetzt wurde. Der Generator
  stellt es beim Verlassen zwar wieder her (`generator_screen.dart`
  `_restorePracticeCharsAndBoost`), Adaptive Copy und andere Wege aber
  nicht zuverlässig.
- **Fehler C (neu gefunden):** Es gibt nie `setWpm` **am Keyer**. Die
  Antwort läuft mit dem Tempo, das zuletzt Keyer-Screen oder WiFi Trx
  gesetzt haben. Deshalb hat das heutige Gebe-Tempo nie wirklich
  funktioniert.
- `_evaluate()` Z. ~499: Adaptive Speed +1 pro 10 richtige,
  `.clamp(_wpm, _echoSpeedMax)`, nie −1.
- `_beginReceive()` (Z. ~429): Startpunkt der Antwort. Hier den Keyer auf
  das Antwort-Tempo setzen.
- `_StatsBar` (Z. ~801) zeigt `currentWpm`, nur wenn Adaptive Speed an ist.
- Werte, die geladen werden: `wpm`, `echoSpeedMax`, `adaptiveSpeed` (Z. 184-191).
  `interCharSpace` (Std. 28), `interWordSpace` (Std. 40), `practiceChars`,
  `boostLevel` werden nicht geladen. Der Generator lädt sie in
  `generator_screen.dart` Z. 156-170, dort sind auch die Standardwerte.
- Der Dekoder arbeitet auf den Symbolen des Keyers (Dit/Dah/Pausen) und
  braucht kein WPM. Die Zeichengrenze ergibt sich aus dem Keyer-Tempo. Es
  reicht also, das Keyer-Tempo richtig zu setzen.

`android/lib/ui/settings_screen.dart` Z. 876-883: Schalter "Adaptive
Speed", darunter nur bei "an" der Regler "Max. Speed" (10–50,
Schlüssel `echoSpeedMax`).

## Schritte

Jeder Schritt wird einzeln gebaut und installiert.

**1a: Singleton-Fehler A, B, C beheben** (nur `echo_trainer_screen.dart`)
- In `_loadPrefs` zusätzlich laden: `interCharSpace`, `interWordSpace`,
  `practiceChars`, `boostLevel` (gleiche Standardwerte und Grenzen wie der
  Generator).
- Eine Methode `_applyPromptConfig()`: setzt am Generator WPM
  (`_currentWpm`), Abstände, Practice Set und Boost, am Ton den
  Basis-Pitch. Aufruf in `_startSession()` vor dem Startsignal und in
  `_playWord()` statt der einzelnen `setWpm`/`setFreq`-Aufrufe.
- Eine Methode `_applyAnswerConfig()`: setzt am Keyer das WPM (vorerst =
  `_currentWpm`) und den verschobenen Pitch. Aufruf in `_beginReceive()`.
- Adapt. Rand. wählt die Zeichen selbst, Practice Set/Boost stören dort
  nicht. Das bei der Umsetzung prüfen.
- *Prüfen:* WiFi Trx mit 30 WPM öffnen, dann Echo mit 18 WPM: Das
  Vorspiel hat die Abstände aus den Einstellungen, die Antwort wird mit
  18 WPM erkannt.

**1b: Gebe-Tempo**
- Neuer Wert `_answerWpmMax` aus `echoAnswerWpmMax` (Std. 0 = Aus).
- `_answerWpm = (_answerWpmMax > 0) ? min(_currentWpm, _answerWpmMax) :
  _currentWpm`, genutzt in `_applyAnswerConfig()`. Vor dem nächsten
  Vorspiel setzt `_applyPromptConfig()` wieder das Hör-Tempo, also ist
  kein eigenes Zurücksetzen nötig.
- Einstellungen, Abschnitt Echo Trainer: Regler **"Gebe-Tempo (max.)"**,
  0–50, 0 wird als "Aus" angezeigt, immer sichtbar (nicht mehr unter
  Adaptive Speed). Hilfetext: "Deine Antwort wird mit höchstens diesem
  Tempo erwartet. Vorgespielt wird weiter mit dem normalen Tempo."
  Texte DE/EN in `strings.dart`.
- Echo-Screen: Die Statuszeile zeigt `Hören 22 · Geben 15 WPM`, sobald
  das Gebe-Tempo gilt. Sonst bleibt alles wie bisher.
- *Prüfen:* 22 WPM und Gebe-Tempo 15: Das Vorspiel läuft schnell, und
  langsam gegebene Antworten werden sauber erkannt.

**1c: Adaptive Speed wie Firmware**
- In `_evaluate()`: nach jeder Auswertung (richtig +1, falsch −1, auch bei
  Wiederholungen) `_currentWpm = (_currentWpm ± 1).clamp(5, 60)`. Nicht
  bei Learn New/Preview ohne Antwort, denn das wird schon vorher
  übersprungen.
- Die Obergrenze `_echoSpeedMax` entfällt, der alte Regler verschwindet
  aus den Einstellungen.
- Nicht speichern (E5).
- *Prüfen:* Adaptive Speed an, 3× richtig ergibt +3, 1× falsch ergibt −1.
  Die Anzeige folgt.

**Abschluss:** DECISIONS.md-Eintrag, STATUS.md, `PORTING-MAP.md`-Zeile
"echoTrainerEval()" um "Echo Speed Max, Adaptive Speed ±1" ergänzen.

## Testplan (User, auf dem Gerät)

- [ ] Nacheinander Adaptive Copy, WiFi Trx und Keyer öffnen, dann Echo
      Trainer: Das Vorspiel klingt jedes Mal gleich (Abstände wie
      eingestellt).
- [ ] Echo Trainer mit Practice Set (nicht Koch): Es kommen nur Zeichen
      aus der eigenen Liste, auch direkt nach Adaptive Copy.
- [ ] Hör-Tempo 22, Gebe-Tempo Aus: Die Antwort mit 22 WPM wird erkannt.
- [ ] Hör-Tempo 22, Gebe-Tempo 15: Das Vorspiel läuft mit 22, die Antwort
      mit 15 wird sauber erkannt, und die Anzeige zeigt beide Werte.
- [ ] Hör-Tempo 12, Gebe-Tempo 15: Die Antwort wird mit 12 erwartet
      (Obergrenze, nicht schneller).
- [ ] Adaptive Speed an: Das Tempo geht pro richtigem Wort hoch und pro
      falschem runter. Nach dem Verlassen und erneuten Öffnen steht
      wieder das eingestellte Tempo.
- [ ] Learn New Chr / Preview Char funktionieren unverändert.
- [ ] Der CW Generator klingt danach unverändert.

## Später prüfen (nicht Phase 1)

- Denkzeit: Die Firmware rechnet `1400 ms + Zeichenpause + Wortpause/3 +
  Denkzeit` ab Ende des Vorspiels (`m32_v6.ino:2551`). Die App nutzt die
  Denkzeit als Pausen-Timeout ab dem letzten Symbol. Das in Phase 5
  angleichen.

## Ergebnis

(nach Abschluss ausfüllen)
