# Phase 2: Trainingsprofile (Datenebene)

Status: **abgeschlossen** · Stand: 2026-09-25

## Ziel

Hören (CW Generator inkl. Adaptive Copy) und Geben (Echo Trainer) merken
sich ihre Werte **jeweils für sich**. Wer im Generator auf Lektion 20 ist,
findet den Echo Trainer weiterhin auf Lektion 8. Änderungen im einen
Training verstellen das andere nicht mehr. Die Oberfläche bleibt fast
gleich (siehe Schritt 2d).

## Nicht in dieser Phase

- Keine Chips/Bottom-Sheets in den Screens (Phase 3).
- Keine getrennte Zeichenstatistik (Phase 4). Boost und Practice Set sind
  ab jetzt pro Profil, die *automatisch ermittelten* Schwachzeichen
  bleiben bis Phase 4 gemeinsam.
- Kein Adaptiv-Ablauf beim Echo (Phase 5/6), keine Adaptiv-Schwellen im
  Echo-Profil.
- Keine benannten Presets, kein Zurücksetzen-Knopf.

## Was ins Profil wandert

Profil-Arten: `hear` (CW Generator, Koch-Generator, Adaptive Copy) und
`echo` (Echo Trainer, Koch-Echo, Learn New/Preview).
Jedes Profil hat **dieselben** Felder, damit Phase 3/7 nur einen Aufbau
kennen:

| Feld (bisheriger globaler Schlüssel) | Bedeutung |
|---|---|
| `wpm` | Hör-Tempo |
| `kochLevel` | Koch-Lektion |
| `groupLength` | Gruppenlänge (Random) |
| `randomOption` | Random-Zeichenvorrat (Buchstaben, Ziffern …) |
| `maxWords` | Wörter pro Durchgang (Max # of Words) |
| `wordLengthMax` | max. Wortlänge |
| `abbrevLengthMax` | max. Abkürzungslänge |
| `interCharSpace`, `interWordSpace` | Abstände (Farnsworth) |
| `practiceChars`, `boostLevel` | Practice Set + Boost |

**Bleibt, wie es ist (nicht im Profil):**
- Global (Ebene A): Koch-Folge (`kochSeq`, `customKochChars`,
  `licwCarouselStart`), Tonhöhe/Weichheit, Keyer-Einstellungen, Rufzeichen-
  Optionen, `outputCase`, WiFi Trx.
- Schon nur für ein Training: Echo-Optionen (`echoThinkTime`,
  `echoRepeats`, `echoDisplayMode`, `confirmTone`, `toneShift`,
  `echoAnswerWpmMax`, `adaptiveSpeed`, `echoSpeedMax`), Generator-Optionen
  (`genDisplayMode`, `eachWordTwice`, `stopAfterItem`), Modus-Indizes
  (`kochModeIndex`, `echoModeIndex`, `kochEchoModeIndex`, `kochFlow`),
  Adaptive-Copy-Schwellen (`adaptive*`, bleiben Hören).
- Das Tempo des **CW Keyers** (`keyer_screen.dart`) und von **WiFi Trx**
  (`wifi_trx_screen.dart` liest ebenfalls `wpm`): Sie behalten den alten
  globalen Schlüssel `wpm`. Das heißt, der Keyer hat nach Phase 2 sein
  eigenes Tempo, unabhängig vom Hören und Geben.

## Entscheidungen

Offen, Empfehlung zuerst:

- **D1 Speicherform:** Ein Schlüssel pro Feld mit Präfix, z. B.
  `profile.hear.kochLevel`, `profile.echo.kochLevel`. Kein JSON-Block,
  weil SharedPreferences-Einzelwerte einfacher zu prüfen und zu
  migrieren sind.
- **D2 Migration:** Einmalig beim ersten Start (Marke `profileVersion=1`):
  beide Profile werden aus den globalen Werten befüllt, leere/fehlende
  Werte bekommen den Standard. Die alten globalen Schlüssel werden **nicht
  gelöscht** (Rückweg, falls etwas schiefgeht), aber danach nicht mehr
  gelesen. Bekannte Falle: `?? default` greift nicht bei gespeichertem
  `''` (siehe DECISIONS.md), also explizit prüfen.
- **D3 Koch-Folge global** (Konzept §9 Frage 3): eine Folge für beide,
  nur die Lektion getrennt. Empfehlung: ja.
- **D4 Abstände pro Profil** (Konzept §9 Frage 4): ja, wie in der Tabelle.
- **D5 Einstellungsseite in der Zwischenzeit:** Oben in den
  Trainings-Abschnitten ein Umschalter **Hören | Geben**. Die
  Profil-Felder darunter bearbeiten das gewählte Profil. Die Zeile
  "Default WPM / Default Koch-Lektion" entfällt dort, denn beides ist in
  den Screens selbst einstellbar. Der Umschalter ist nur eine
  Zwischenlösung und verschwindet in Phase 3. Er ist klein (ein Widget)
  und der einzige Weg, bis dahin Abstände/Practice Set/Boost getrennt zu
  ändern.

## Ist-Zustand App

Alle Felder oben liegen heute unter dem globalen Schlüssel. Gelesen
werden sie in `generator_screen.dart` (`_loadPrefs`, ca. Z. 130-170),
`echo_trainer_screen.dart` (`_loadPrefs`), `adaptive_copy_body.dart`
(Practice Set/Boost, Z. ~223) und `settings_screen.dart`. Geschrieben
wird u. a. `wpm`/`kochLevel` in beiden Trainings-Screens
(`_savePrefs`) und die Abstände durch Adaptive Copy über den
Generator-Screen.

## Schritte

Jeder Schritt einzeln baubar, App danach voll funktionsfähig.

**2a: Profil-Schicht und Migration** (neu: `lib/content/training_profile.dart`)
- Klasse `TrainingProfile` (die Felder oben, Grenzen wie bisher) mit
  `load(kind)`/`save()` über den Präfix-Schlüssel.
- `migrateProfilesIfNeeded(prefs)`, aufgerufen vor dem ersten Screen.
- Unit-Test: Migration aus globalen Werten, leere Strings, fehlende
  Werte, zweiter Aufruf ändert nichts.
- Noch keine Nutzung, die App verhält sich unverändert.

**2b: Hören nutzt das Profil `hear`**
- `generator_screen.dart` und `adaptive_copy_body.dart` lesen/schreiben
  die Felder aus `hear`. Restore-Logik für Practice Set/Boost
  (`_restorePracticeCharsAndBoost`) liest `hear`.
- Prüfen: Generator verhält sich wie vorher (Werte wurden migriert).

**2c: Geben nutzt das Profil `echo`**
- `echo_trainer_screen.dart` liest/schreibt aus `echo` (inkl. der
  Werte aus Phase 1: Abstände, Practice Set, Boost).
- Prüfen: Lektion, WPM, Gruppenlänge im Echo ändern, Generator zeigt
  die alten Werte, und umgekehrt.

**2d: Einstellungsseite**
- Umschalter Hören | Geben (D5), Profil-Felder bearbeiten das gewählte
  Profil, "Default WPM/Koch" entfällt.
- Prüfen: Abstände im Profil "Geben" ändern → nur Echo-Vorspiel ändert
  sich.

**Abschluss:** DECISIONS.md (D1–D5), STATUS.md, README-Status.

## Testplan (User, auf dem Gerät)

- [ ] Nach dem Update stehen Hören und Geben auf denselben Werten wie
      vorher (Tempo, Lektion, Gruppenlänge, Wörter, Abstände).
- [ ] Lektion im Generator erhöhen: Echo bleibt auf seiner Lektion.
- [ ] Tempo im Echo ändern: Generator-Tempo bleibt.
- [ ] Practice Set/Boost im Profil "Geben" ändern: Generator unverändert.
- [ ] Adaptive Copy ändert Abstände/Lektion: Echo unberührt.
- [ ] CW Keyer und WiFi Trx behalten ihr Tempo.
- [ ] App neu starten: alle Werte bleiben getrennt erhalten.

## Ergebnis

2026-09-24: 2a–2d umgesetzt, Debug-APK gebaut, **noch nicht auf dem Gerät getestet**. D3/D4/D5 vom User bestätigt.
- `lib/content/training_profile.dart` (+ `test/training_profile_test.dart`, grün): Präfix-Schlüssel `profile.<hear|echo>.<Feld>`, einmalige Migration (`profileVersion=1`), alte Globals bleiben stehen.
- Feldliste inkl. `wpm`. Keyer und WiFi Trx behalten den globalen `wpm`.
- Hören: `generator_screen`, `adaptive_copy_body` (Practice Set/Boost), `char_stats_screen` (Lektion). Geben: `echo_trainer_screen`.
- Einstellungen: Umschalter "Einstellungen für Hören | Geben" in Allgemein, Practice Set, Abstände und CW Generator. Abweichung von der Spec: Der Koch-Lektions-Regler bleibt in "Allgemein" (jetzt profilabhängig), nur "Default WPM" entfiel.
- Bekannt: `test/widget_test.dart` ist schon länger defekt (Template-Test, `MyApp`), unabhängig von dieser Phase.

2026-09-25: Auf dem Gerät installiert, alle Tests bestanden (zusammen mit Phase 1). Der Hören/Geben-Umschalter in den Einstellungen ist nur die Zwischenlösung bis Phase 3.
