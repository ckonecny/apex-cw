# Phase 1: Echo-Grundlagen

Status: **abgeschlossen** · Stand: 2026-09-25

## Ziel

Im Echo Trainer kann man schneller hören als geben: Das Wort wird mit dem
Hör-Tempo vorgespielt, die Antwort gibt man mit einem eigenen, langsameren
Gebe-Tempo. Außerdem klingt das Vorspiel immer gleich, egal welcher Screen
vorher offen war.

## Nicht in dieser Phase

- Keine getrennten Profile (Phase 2). Hör-Tempo, Lektion, Gruppenlänge
  bleiben vorerst gemeinsam mit dem Generator.
- **Keine Änderung an Adaptive Speed.** Es soll später wie beim CW
  Generator arbeiten (Blöcke, gleiche Einstellungen, getrennt vom Hören,
  eigene Speicherung): Phase 5/6. Die bestehende Adaptive-Speed-Logik und
  ihr Regler "Max. Speed" bleiben unangetastet, es gibt keinen Zwischenumbau.
- Keine neue Oberfläche außer dem Gebe-Tempo-Regler und der Tempo-Anzeige.
- Denkzeit-Berechnung bleibt (siehe "Später prüfen").

## Entscheidungen (getroffen 2026-09-24)

- **E1** Gebe-Tempo ist eine Obergrenze wie in der Firmware:
  Antwort-Tempo = min(Hör-Tempo, Gebe-Tempo).
- **E2** Schrittweite 1 WPM, Bereich 5–50. Der Ausgangswert bedeutet
  "wie Hören": Die Antwort wird im selben Tempo erwartet wie das
  Vorspiel. Im Regler als "wie Hören" beschriftet, nicht "Aus". Intern 0.
- **E3** Eigener Speicherschlüssel `echoAnswerWpmMax` (Rein technisch,
  keine Auswirkung für den User: der alte Wert von Adaptive Speed wird
  nicht umgedeutet).
- **E4/E5** entfallen in Phase 1 (siehe oben). Adaptive Speed und dessen
  Speicherung kommen in Phase 5/6 mit eigenem Echo-Profil.

Nach Abschluss: E1–E3 als ein Eintrag in `docs/DECISIONS.md`.

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
- Neuer Wert `_answerWpmMax` aus `echoAnswerWpmMax` (Std. 0 = wie Hören).
- `_answerWpm = (_answerWpmMax > 0) ? min(_currentWpm, _answerWpmMax) :
  _currentWpm`, genutzt in `_applyAnswerConfig()`. Vor dem nächsten
  Vorspiel setzt `_applyPromptConfig()` wieder das Hör-Tempo, also ist
  kein eigenes Zurücksetzen nötig.
- Einstellungen, Abschnitt Echo Trainer: Regler **"Gebe-Tempo (max.)"**,
  0–50, 0 wird als "wie Hören" angezeigt, immer sichtbar, unabhängig von Adaptive Speed. Hilfetext: "Deine Antwort wird mit höchstens diesem
  Tempo erwartet. Vorgespielt wird weiter mit dem normalen Tempo."
  Texte DE/EN in `strings.dart`.
- Echo-Screen: Die Statuszeile zeigt `Hören 22 · Geben 15 WPM`, sobald
  das Gebe-Tempo gilt. Sonst bleibt alles wie bisher.
- *Prüfen:* 22 WPM und Gebe-Tempo 15: Das Vorspiel läuft schnell, und
  langsam gegebene Antworten werden sauber erkannt.

**Abschluss:** DECISIONS.md-Eintrag, STATUS.md, `PORTING-MAP.md`-Zeile
"echoTrainerEval()" um "Echo Speed Max" ergänzen.

## Testplan (User, auf dem Gerät)

- [ ] Nacheinander Adaptive Copy, WiFi Trx und Keyer öffnen, dann Echo
      Trainer: Das Vorspiel klingt jedes Mal gleich (Abstände wie
      eingestellt).
- [ ] Echo Trainer mit Practice Set (nicht Koch): Es kommen nur Zeichen
      aus der eigenen Liste, auch direkt nach Adaptive Copy.
- [ ] Hör-Tempo 22, Gebe-Tempo "wie Hören": Die Antwort mit 22 WPM wird erkannt.
- [ ] Hör-Tempo 22, Gebe-Tempo 15: Das Vorspiel läuft mit 22, die Antwort
      mit 15 wird sauber erkannt, und die Anzeige zeigt beide Werte.
- [ ] Hör-Tempo 12, Gebe-Tempo 15: Die Antwort wird mit 12 erwartet
      (Obergrenze, nicht schneller).
- [ ] Learn New Chr / Preview Char funktionieren unverändert.
- [ ] Der CW Generator klingt danach unverändert.

## Später prüfen (nicht Phase 1)

- Denkzeit: Die Firmware rechnet `1400 ms + Zeichenpause + Wortpause/3 +
  Denkzeit` ab Ende des Vorspiels (`m32_v6.ino:2551`). Die App nutzt die
  Denkzeit als Pausen-Timeout ab dem letzten Symbol. Das in Phase 5
  angleichen.

## Ergebnis

2026-09-24: 1a und 1b umgesetzt, Debug-APK gebaut, **noch nicht auf dem Gerät installiert/getestet** (Handy nicht angeschlossen). Abweichung: Kein `_beginReceive`-Pitch-Umbau nötig, Shift-Pitch blieb dort. Regler-Werte 1–4 werden als "wie Hören" (0) gespeichert. Nächster Schritt: Installieren und Testplan durchgehen.

2026-09-25: Auf dem Gerät installiert, alle Tests (A–G, zusammen mit Phase 2) vom User bestanden. Hinweis vom User: Einstellungsmenü mit Hören/Geben-Umschalter ist unübersichtlich → wird in Phase 3 aufgeräumt.
