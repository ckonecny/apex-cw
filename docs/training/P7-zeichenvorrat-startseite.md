# Phase 7: Zeichenvorrat, neue Startseite, Klassisch entfällt

Status: **umgesetzt 7a–7g, Testplan durch User offen** · Stand: 2026-09-25

## Ziel

Ich sehe auf der Startseite nur noch **Hören** und **Geben** (neben CW Keyer
und WiFi Trx). In beiden Screens wähle ich oben zuerst den **Zeichenvorrat**
(Koch-Lektion, Alle Zeichen, Übungsset) und dann den **Inhalt** (Zufall,
Wörter, …). "Koch Trainer" ist kein eigener Einstieg mehr, sondern ein
Zeichenvorrat. Geübt wird immer **blockweise mit Ergebnis-Seite und
Vorschlägen**. Den klassischen Endlos-Ablauf gibt es nicht mehr.

## Nicht in dieser Phase

- Reaktionszeit, Presets, Trend, Verwechslungspaare: Phase 8.
- Eigener Text als Zeichenvorrat: Phase 9.
- **Paddle-Wahl Wiederholen/Weiter im neuen Hören-Ablauf** (User-Wunsch):
  Sie entfällt mit Klassisch, soll aber später in der Block-Darstellung
  (Adaptive Copy) wieder angeboten werden, z. B. beim Aufdecken/Markieren
  eines Wortes. Umsetzung als eigener Punkt in Phase 8 (Extras), hier nur
  vorgemerkt.
- Neue Vorschlags-Regeln. Die Regeln aus Phase 6 (Echo) und Adaptive Copy
  (Hören) bleiben, sie werden nur für weitere Zeichenvorräte freigeschaltet.
- Die alte Einzelzeichen-Wertung (+2/−1) in Adaptive Copy. Sie wird nicht
  angefasst.
- Keine Änderung an CW Keyer und WiFi Trx.

## Entscheidungen

Offen, Empfehlung zuerst:

1. **Koch-Karte (Konzept §9 Frage 1):** "Koch Trainer" fällt als Karte weg,
   Koch wird Zeichenvorrat in Hören und Geben. *Empfehlung, wie in deiner
   Vorgabe.* Die Firmware-Namen bleiben als Untertitel: Hören
   "CW Generator · Koch Trainer", Geben "Echo Trainer".
2. **Zeichenvorrat und Inhalt:** je Screen und getrennt für Hören und Geben
   im Profil gespeichert (`charset`, `content`).

   | Zeichenvorrat | Inhalte |
   |---|---|
   | Koch-Lektion | Zufall, Wörter, Abkürzungen, Gemischt |
   | Alle Zeichen | Zufall, Wörter, Abkürzungen, Rufzeichen, Gemischt |
   | Übungsset | Zufall |

   Rufzeichen nur bei "Alle Zeichen" (wie die Firmware im Koch-Menü).
   *Empfehlung, entspricht Konzept 3.1.*
3. **"Adapt. Rand." (Echo) entfällt als Inhalt.** Bei Koch-Lektion + Zufall
   wird im Blockablauf immer nach Schwächen gewichtet (bisher die Wahl
   "Adapt. Rand."). Bei Alle Zeichen und Übungsset gibt es keine
   Gewichtung, sondern zufällige Auswahl. *Empfehlung.* Die Statistik-Spur
   `echo` bleibt dieselbe.
4. **Klassisch entfällt vollständig (Hören und Geben).** Folge für Hören:
   die Einstellungen **Anzeige (Zeichen/Wort/Aus)**, **Jedes Wort
   zweimal** und **Stop nach Wort** entfallen mit; die Paddle-Wahl
   Wiederholen/Weiter entfällt zunächst und wird später neu im
   Block-Ablauf angeboten (siehe "Nicht in dieser Phase"), weil Adaptive Copy einen eigenen Ablauf hat
   (senden → aufdecken → markieren). Für Geben entfällt der Endlosablauf,
   der globale Schalter **Adaptive Speed** (wird durch die Vorschläge
   ersetzt), und Ablauf-Auswahl "Klassisch | Blockweise". Der **Ablauf pro
   Wort** beim Echo (Vorspiel, Antwort, Wiederholungen, Aufdecken, Denkzeit)
   bleibt. *Empfehlung, bitte bestätigen:* Das ist die Konsequenz aus
   deiner Vorgabe. Die Anzeige-Modi sind danach weg.
5. **Standard:** Beide Screens starten im Blockablauf (Standard aus dem
   Profil-Feld `blockFlow` entfällt komplett, es gibt nur noch Blöcke).
   Blockgröße bleibt "Wörter pro Block" (Standard 10, wenn 0).
6. **Neues Zeichen lernen / Zeichen anhören:** keine eigenen Knöpfe mehr.
   In der Koch-Zeichenzeile tippt man ein Zeichen an und wählt
   **Anhören** oder **Mit Echo üben**. Der Echo-Einzelzeichen-Modus
   (`fixedTarget`) bleibt intern als Übung dahinter. Er hat weiterhin
   keinen Block. *Empfehlung.* Beim ersten Start einer neuen Lektion (Zeichen
   frisch freigeschaltet) bleibt die Vorschau wie in Adaptive Copy.
7. **Koch-Folge (Konzept §9 Frage 3):** global, für Hören und Geben gleich.
   Die Lektion bleibt getrennt (Profil). Die Auswahl der Folge steht im ⚙
   beider Screens, wenn "Koch-Lektion" gewählt ist. *Empfehlung, ist der
   Ist-Zustand.*
8. **Regler nach Inhalt ausblenden:** im ⚙-Sheet zeigt "Wortauswahl" nur, was
   zum gewählten Inhalt passt:
   - Gruppen-Länge: nur Zufall
   - Zeichenauswahl "Random Groups": nur Zufall + Alle Zeichen
   - Max. Wortlänge: nur Wörter und Gemischt
   - Max. Abkürzungslänge: nur Abkürzungen und Gemischt
   - Rufzeichen-Optionen: nur Rufzeichen
   - Übungsset-Feld: nur bei Übungsset
   Dazu steht oben im Sheet, für welchen Zeichenvorrat/Inhalt sie gelten.
   *Empfehlung,* löst die Verwirrung von "Max. Wortlänge 2 bei Zufall".
9. **Adaptiv (Hören) für Alle Zeichen und Übungsset:** Adaptive Copy kann
   bisher nur Koch. Dort gibt es kein "neues Zeichen freischalten", also
   entfallen Freischaltung, Boost-Auswahl neuer Zeichen und Tempo-Sperre.
   Tempo, Abstand, Ergebnis und Schwachzeichen funktionieren wie sonst.
   Beim Echo ist das seit Phase 6 bereits so. *Empfehlung.*
10. **Bestehende Einstellungen des Users:** Die Migration übernimmt
    automatisch: hat der User den Koch Trainer benutzt (Pref
    `kochModeIndex` / `kochEchoModeIndex` vorhanden), startet Hören/Geben
    mit Zeichenvorrat Koch-Lektion, sonst mit Alle Zeichen. Inhalt aus den
    alten Werten (Zufall/Wörter/…), "Adapt. Rand." wird Zufall. Alte
    Schlüssel bleiben liegen (Rückweg), werden nicht mehr gelesen.

## Firmware-Referenz

- `reference/Software/src/Version 6 and newer/MorseMenu.cpp` Z. 100–110,
  188–198, 786–800: Koch Trainer als Untermenü mit Select Lesson, Learn New
  Chr, Preview Char, CW Generator (Zufall/Abkürzungen/Wörter/Gemischt), Echo
  Trainer (dieselben plus "Adapt."). Kein Rufzeichen, kein File Player im
  Koch-Menü.
- `m32_v6.ino`, `kochActive`: Koch ist nur ein Filter auf den Zeichenvorrat
  plus Gewichtung, kein eigener Ablauf. Deshalb ist die Umstellung auf
  Zeichenvorrat fachlich gedeckt. Die neue Auswahlstruktur und die Karten
  haben keine Firmware-Entsprechung.

## Ist-Zustand App

- `lib/ui/home_screen.dart` Z. 43–75: Karten CW Keyer, CW Generator, Koch
  Trainer (`GeneratorScreen(kochMode: true)`), Echo Trainer, WiFi Trx.
- `lib/ui/generator_screen.dart`: ein Screen für CW Generator und Koch,
  gesteuert über `widget.kochMode`. Koch-Inhalte `_kochModeOrdinals`
  `[0,5,1,3]`, sonst `_modeIndex`. `_flow` (Pref `kochFlow`, 0 klassisch, 1
  adaptiv) und `_FlowToggle` nur im Koch-Modus. Adaptiv =
  `AdaptiveCopyBody` (Z. 545). Knöpfe Learn New / Preview / Practice Echo
  (Z. 625–650), `_openLearnNewChar`, `_openPreviewChar`, `_openKochEcho`,
  `_KochCharsRow`. Klassisch: `_running`, Log, Paddle-Wahl,
  `_genDisplay`, `_stopAfterItem`, `_eachWordTwice`.
- `lib/ui/adaptive_copy_body.dart`: nimmt `kochLevel`, `activeKochChars`,
  `contentModeIndex/Ordinals/Labels`; Content-Aufruf hart mit
  `kochActive: true` (Z. 285); Freischaltung, Boost, Tempo-Sperre hängen an
  `kochLevel < activeKochChars.length`.
- `lib/ui/echo_trainer_screen.dart`: `widget.kochMode` wählt zwischen
  `_kochModeIndex` (Zufall/Abk./Wörter/Gemischt/Adapt. Rand., Pref
  `kochEchoModeIndex`) und `_modeIndex` (Zufall/Wörter/Rufzeichen/Gemischt/
  Übungsset/Abk.). Inhalt in `_fetchTarget` (Z. 883–935). `_blockFlow`,
  `_blockActive` (Block-Ablauf, Phasen 5/6). `_adaptiveSpeed` (Klassisch).
- `lib/ui/widgets/training_settings_sheet.dart`: Sections `content, spacing,
  wordSelection, generatorFlow, echoFlow, adaptive, kochSequence`; die
  Wortauswahl-Karte zeigt immer alle Regler.
- `lib/content/training_profile.dart`: Int-Felder u. a. `kochLevel`,
  `blockFlow`; hier kommen `charset` und `content` dazu.
- `lib/ui/settings_screen.dart`: globale Seite, enthält noch die
  Adaptive-Speed-Reste (prüfen).

## Schritte

Jeder Schritt ist einzeln baubar und installierbar; die App bleibt danach
benutzbar. Klassisch wird bewusst erst zum Schluss (7f) entfernt, damit bis
dahin nichts halb fertig ist.

**7a: Modell Zeichenvorrat/Inhalt und gemeinsame Kopfzeile.**
Profil-Felder `charset` (0 Koch, 1 Alle Zeichen, 2 Übungsset) und `content`
(Zufall, Wörter, Abkürzungen, Rufzeichen, Gemischt) samt Migration
(Entscheidung 10). Neue reine Funktion in `lib/content/` (z. B.
`charset_content.dart`), die aus `(charset, content)` die Engine-Parameter
liefert (Modus-Ordinal, `kochActive`, `randomOption`) und die erlaubten Inhalte
je Zeichenvorrat. Gemeinsames Widget `lib/ui/widgets/charset_header.dart`:
Zeichenvorrat-Auswahl, Inhalt-Auswahl, Koch-Lektion-Regler und
Koch-Zeichenzeile. Unit-Tests für Mapping und Migration. Noch nicht
eingebunden.
Prüfung: Tests grün, Analyzer sauber, App unverändert.

**7b: Geben auf Zeichenvorrat umstellen.**
`EchoTrainerScreen` verwendet die Kopfzeile und `charset/content`, der
`kochMode`-Parameter und die zwei Inhaltslisten entfallen. Koch-Zufall
gewichtet immer (ehem. Adapt. Rand.), Übungsset und Alle Zeichen ohne
Gewichtung. `_fetchTarget` und Phase-6-Vorschläge (`charContent`) auf die
neue Kopplung umstellen. Klassisch bleibt hier vorerst noch drin.
Prüfung: alle Kombinationen liefern die richtigen Zeichen (Koch-Lektion
enthält nur freigeschaltete Zeichen, Übungsset nur eigene), Block und
Vorschläge wie in Phase 6.

**7c: Hören auf Zeichenvorrat umstellen.**
`GeneratorScreen` zu einem Screen "Hören" ohne `kochMode`-Parameter, gleiche
Kopfzeile. Klassisch weiterhin da (für alle Zeichenvorräte), Adaptiv vorerst
nur bei Koch-Lektion. Die Karten "CW Generator" und "Koch Trainer" der
Startseite zeigen beide auf den neuen Screen (Zwischenzustand, wird in 7e
zur einen Karte).
Prüfung: Koch-Lektion wie bisher, Alle Zeichen und Übungsset im
klassischen Ablauf, Einstellungen bleiben erhalten.

**7d: Adaptiv (Hören) für Alle Zeichen und Übungsset.**
`AdaptiveCopyBody` bekommt Zeichenvorrat statt hart Koch: Content-Aufruf aus
dem Mapping, Freischaltung/Boost/Tempo-Sperre nur bei Koch-Lektion, sonst
ausgeblendet. Der Abschnitt "Wortauswahl" im Sheet blendet Regler nach Inhalt
aus (Entscheidung 8, für beide Screens).
Prüfung: Block mit Alle Zeichen (Zufall, Wörter, Rufzeichen), Übungsset;
Ergebnis-Seite und Tempo-/Abstands-Vorschläge erscheinen, keine
Freischaltung; Koch wie zuvor.

**7e: Neue Startseite und Zeichen-Tippen.**
Startseite: CW Keyer, Hören, Geben, WiFi Trx (Untertitel siehe Entscheidung
1). Tippen auf ein Koch-Zeichen in der Zeichenzeile: Sheet mit **Anhören**
und **Mit Echo üben** (nutzt Echo `fixedTarget`). Knöpfe Learn New Chr /
Preview Char / Practice Echo und `_PreviewCharSheet` entfallen. Koch-Folge
im ⚙ beider Screens.
Prüfung: alle Wege zu Anhören/Mit Echo üben, keine toten Knöpfe,
Startseite auf Handy-Breite und Dunkelmodus.

**7f: Klassisch entfernen, Adaptiv wird Standard, einheitliche Übungsdarstellung.**
(User, 2026-09-25: In allen Übungsmodi wird die Ausgabe grundsätzlich analog
zu "Koch Hören Adaptiv" umgestellt, zusammen mit dem Entfernen der
klassischen Anzeige. Das betrifft vor allem den Echo-Übungsscreen. Wenn der
Schritt zu groß wird, teile ich ihn in 7f-1 Entfernen und 7f-2 Darstellung.)
Hören: Klassisch-Zweig, `_FlowToggle`, Pref `kochFlow`, Paddle-Wahl,
`_genDisplay`, `_stopAfterItem`, `_eachWordTwice`, Log; Sheet-Section
`generatorFlow`. Geben: Endlosablauf, `_adaptiveSpeed` samt globaler Pref und
Sheet-Zeile (`adaptiveSpeed`), Ablauf-Auswahl, `profile.echo.blockFlow`
(alle Läufe sind Blöcke). Der Einzelzeichen-Übungsweg (`fixedTarget`)
bleibt. Toter Code und nicht mehr benutzte Strings aufräumen, Analyzer auf
den Vor-Phasen-Stand (nur die zwei alten Warnungen). Sheet-Sections
entsprechend kürzen.
Prüfung: keine Spur von "Klassisch" in der Oberfläche, beide Screens
starten direkt in den Block, Tests und Analyzer sauber.

**7g: Doku.** README-Tabelle, STATUS, DECISIONS, CLAUDE.md (falls
Screen-Namen dort stehen), `docs/ADAPTIVE-COPY.md` (Hinweis Zeichenvorrat),
diese Spec (Ergebnis).

## Testplan (User, auf dem Gerät)

- [ ] Startseite: CW Keyer, Hören, Geben, WiFi Trx. Kein "Koch Trainer".
- [ ] Hören und Geben: Zeichenvorrat und Inhalt wählbar, Auswahl bleibt
      nach Neustart, getrennt für Hören und Geben.
- [ ] Koch-Lektion: nur die freigeschalteten Zeichen kommen vor
      (Zufall, Wörter, Abkürzungen, Gemischt), in beiden Screens.
- [ ] Alle Zeichen: Zufall (mit Zeichenauswahl), Wörter, Abkürzungen,
      Rufzeichen, Gemischt.
- [ ] Übungsset: nur eigene Zeichen, nur Zufall wählbar.
- [ ] ⚙ zeigt nur Regler, die zum Inhalt passen (Zufall → Gruppen-Länge,
      Wörter → Max. Wortlänge, …).
- [ ] Beide Screens laufen nur blockweise mit Ergebnis-Seite. Nirgends
      "Klassisch", kein Endlosablauf, kein Adaptive Speed.
- [ ] Hören mit Alle Zeichen/Übungsset: Ergebnis und Tempo-/Abstands-
      Vorschläge, keine Zeichen-Freischaltung.
- [ ] Koch-Zeichen antippen → Anhören mit Code-Kachel; lange drücken → Mit Echo üben (geändert 2026-09-27).
- [ ] Koch-Freischaltung, Boost und Schwachzeichen funktionieren in Hören
      und Geben wie zuvor.
- [ ] Alte Einstellungen (Lektion, Tempo, Abstände, Statistik) sind nach
      dem Update noch da.
- [ ] Sprache, Dunkelmodus, schmales Display.

## Ergebnis

Umgesetzt 7a–7g, jeder Schritt einzeln auf dem Gerät bestätigt. Abweichungen und Zusätze:

- Klassisch wurde in einem Stück mit der einheitlichen Darstellung entfernt (7f). Geben zeigt beim Üben das aktuelle Wort groß in der Mitte (Ziel, Getastetes, OK/ERR) statt eines Logs; im Leerlauf Hinweis und Statuszeile.
- Hören: START-Button unten wie im Geben (`AdaptiveCopyController.start`). Kopfbereich (Vorrat, Inhalt, Koch-Regler, Zeichenkästchen) steht in beiden Screens oben, gemeinsames Widget `CharsetHeader`.
- Übungsset: Zeichenfeld direkt im Kopfbereich, zusätzlich zu den Einstellungen.
- Zeichen antippen: Anhören spielt das Zeichen 3× mit eingestelltem WPM und Wortabstand (`playCharThrice`), oder Mit Echo üben (Einzelzeichen-Übung, endlos, ohne Block, ohne Statistik).
- Aufräumen: Adaptive Speed, "Ablauf"-Auswahl, Anzeige-Modi, Stop<Next>Rep, Jedes Wort 2× und zugehörige Texte entfernt. Pref `blockFlow`, `kochFlow` u. a. bleiben ungenutzt liegen.
- Nacharbeit: Rufzeichen-Optionen werden in adaptiven Hören-Blöcken noch nicht übergeben (Standardwerte); `echoBlockEma` ist global; Paddle-Wahl Wiederholen/Weiter im Hören-Block kommt in Phase 8.
