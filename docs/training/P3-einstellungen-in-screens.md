# Phase 3: Einstellungen in die Screens

Status: **abgeschlossen** (Geräte-Test 3a–3e bestanden 2026-09-25) · Stand: 2026-09-25

## Ziel

Alles, was zu einem Training gehört, stellt man im Training selbst ein:
Ein Zahnrad ⚙ im Screen öffnet ein Fenster (Bottom-Sheet) mit genau den
Werten dieses Trainings. Die globale Einstellungsseite enthält danach nur
noch, was an der Person oder am Gerät hängt. Der Umschalter "Einstellungen
für: Hören | Geben" entfällt, weil der Screen schon sagt, welches Profil gilt.

## Nicht in dieser Phase

- Keine neuen Werte, keine neue Logik, keine Datenänderung. Die Profile
  aus Phase 2 bleiben wie sie sind, nur der Ort der Bedienung wechselt.
- Keine Schnellwert-Chips (Konzept 4.2, Punkt 3). Die vorhandenen Regler im
  Setup-Bereich bleiben. Chips kommen erst, wenn Phase 5/7 den Setup-Bereich
  ohnehin neu bauen.
- Adaptive Speed beim Echo wird 1:1 mitverschoben (Schalter + "Max. Speed"),
  nicht umgebaut (Phase 5/6 ersetzt es).
- Adaptiv-Schwellen (Bereich, Glättung, Freischalt-Anzahl) bleiben global
  gespeichert. Sie wirken nur in Adaptive Copy, und Echo nutzt sie erst ab
  Phase 5/6. Getrennte Ablage dort, nicht jetzt.
- Zeichenstatistik ansehen/zurücksetzen bleibt global (Phase 4).

## Entscheidungen (zur Freigabe)

- **F1** Ein gemeinsames Sheet-Bauteil `TrainingSettingsSheet`, das je Screen
  nur die passenden Abschnitte zeigt. Kein separates Sheet je Screen, damit
  sich nichts doppelt.
- **F2** Das Sheet ist an das jeweilige Profil gebunden (Generator und
  Adaptive Copy = Hören, Echo = Geben). Änderungen werden sofort gespeichert
  und, falls ein Block läuft, erst beim nächsten Block/Wort wirksam, wie
  heute.
- **F3** Das ⚙ ist nur im Setup-Zustand sichtbar (wie die übrigen Regler,
  "Setup-Screen declutter").
- **F4** Nach der Umsetzung fällt die Hören/Geben-Umschaltung in den
  Einstellungen weg.

## Aufteilung: was kommt wohin

**Sheet im CW Generator (Profil Hören):**
- Inhalt: Practice Set (Zeichen, Boost), Random Groups, Gruppenlänge, Max.
  Wortlänge, Max. Abkürzungslänge, Max # of Words
- Tempo & Abstand: Interchar Spc, InterWord Spc
- Ablauf: CW Gen Displ, Stop<Next>Rep, Jedes Wort doppelt

**Sheet im Echo Trainer (Profil Geben):**
- Inhalt und Tempo & Abstand: wie oben (eigene Werte)
- Ablauf: Denkzeit, Wiederholungen, Echo Prompt, **Gebe-Tempo**, Adaptive
  Speed (+ Max. Speed), Tonversatz

**Sheet in Adaptive Copy (Profil Hören):**
- Tempo & Abstand (wie heute schon per ± im Block, hier die Grundwerte)
- Adaptiv: Schwellen, Glättung, Freischalt-Anzahl
- Practice Set und Boost, soweit Adaptive Copy sie nutzt (bei der
  Umsetzung prüfen, keine Anzeige, wenn ohne Wirkung)

**Bleibt in den globalen Einstellungen:** Darstellung, Allgemein (Rest nach
Wegfall von Tempo/Lektion), Koch-Folge, Keyer, Audio-Ausgabe, Rufzeichen-
Daten, WiFi Trx, vband Paddle, Tastenanalyse, Statistik ansehen/zurücksetzen.
**Entfällt dort:** Practice Set, Abstände, CW Generator, Echo Trainer,
Adaptive Mode.

Die Koch-Lektion bleibt wie heute im Screen (Regler bzw. Koch-Zeile), sie
wandert nicht ins Sheet.

## Ist-Zustand App

- `lib/ui/settings_screen.dart` (1407 Zeilen): Abschnitte Practice Set
  (Z. ~586), Abstände (~660), CW Generator (~715), Adaptive Mode (~774),
  Echo Trainer (~877) und der Profil-Umschalter `_profileSwitch()`. Laden/
  Speichern über `TrainingProfile.open(_profile)`.
- `_LabeledSlider`, `_ToggleRow` und Auswahlzeilen sind dort private
  Bauteile. Sie müssen für das Sheet nach `lib/ui/widgets/` verschoben
  (kein Umbau, nur Umzug).
- Generator: Setup-Regler in `generator_screen.dart` Z. ~550-630. Echo:
  `echo_trainer_screen.dart` Z. ~679-730. Adaptive Copy: eigene Setup-Zeile
  in `adaptive_copy_body.dart`.
- Die Screens laden ihr Profil beim Öffnen. Nach dem Schließen des Sheets
  müssen sie neu laden (Rückgabewert oder Callback).

## Schritte

Jeder Schritt einzeln baubar und installierbar. Die alten Abschnitte in den
Einstellungen bleiben bis 3d stehen, damit nie etwas fehlt.

**3a: Bauteile und Sheet-Grundgerüst**
- Regler/Schalter/Auswahlzeile aus `settings_screen.dart` in
  `lib/ui/widgets/setting_rows.dart` verschieben. Einstellungen nutzen sie
  weiter.
- `lib/ui/widgets/training_settings_sheet.dart`: nimmt Profil und eine Liste
  der gewünschten Abschnitte, liest/schreibt via `TrainingProfile`.
- *Prüfen:* Einstellungen sehen aus und funktionieren wie vorher.

**3b: CW Generator**
- ⚙ im Setup-Zustand, öffnet das Sheet mit Inhalt / Tempo & Abstand /
  Ablauf. Nach Schließen Werte neu laden und ans Native pushen (Regel 2).
- *Prüfen:* Werte im Sheet ändern → Generator klingt/verhält sich danach
  entsprechend, Werte bleiben nach App-Neustart.

**3c: Echo Trainer**
- ⚙ mit Profil Geben, inkl. Echo-Abschnitten und Gebe-Tempo.
- *Prüfen:* wie 3b, plus Gebe-Tempo im Sheet wirkt wie zuvor in den
  Einstellungen.

**3d: Adaptive Copy, dann Einstellungen aufräumen**
- ⚙ in Adaptive Copy.
- Aus den globalen Einstellungen entfernen: Practice Set, Abstände, CW
  Generator, Echo Trainer, Adaptive Mode, Profil-Umschalter. Nicht mehr
  benötigte Strings/Felder aufräumen.
- *Prüfen:* Testplan unten.

## Testplan (User, auf dem Gerät)

- [ ] Generator: ⚙ öffnet Sheet mit den Werten, alle Änderungen wirken
      nach Schließen. Nach App-Neustart erhalten.
- [ ] Echo: ⚙ zeigt eigene (Geben-)Werte, getrennt vom Generator. Gebe-Tempo,
      Denkzeit, Wiederholungen, Adaptive Speed funktionieren wie zuvor.
- [ ] Adaptive Copy: ⚙ funktioniert, Änderungen betreffen Echo nicht.
- [ ] Globale Einstellungen: Nur noch die oben genannten Abschnitte,
      übersichtlich, nichts Verstreutes für Hören/Geben.
- [ ] Alle vorher eingestellten Werte sind unverändert (nichts ging beim
      Umzug verloren).
- [ ] Während ein Block läuft ist kein ⚙ sichtbar.
- [ ] Keyer und WiFi Trx unverändert.

## Ergebnis

(offen)

Stand 3a–3d: gemeinsames `TrainingSettingsSheet` (Abschnitte content, spacing, wordSelection, generatorFlow, echoFlow, adaptive). ⚙ im Generator/Koch (Hören), Echo (Geben) und Adaptive Copy (läuft im Koch-Screen, Flow „Adaptiv“: zeigt statt generatorFlow den Abschnitt „Adaptiver Modus“ mit Schwellen, Glättung, Freischalt-Anzahl). Globale Einstellungen ohne Hören/Geben-Schalter, ohne Practice Set, Abstände, CW Generator, Echo Trainer, Adaptive-Mode-Regler und Standard-Koch-Level; Zeichenstatistik (ansehen/zurücksetzen) bleibt dort. Abweichung: Wortauswahl ist ein eigener Abschnitt, weil das Echo die Hör-Optionen (Anzeige, Stop<Next>Rep, doppelt) nicht braucht. Zusatzfix: Echo gibt jetzt Wortlänge/Gruppenlänge an die Engine weiter; Practice Set nutzt min(Gruppenlänge, Wortlänge).

3e (auf Wunsch nachgezogen): Abschnitt „Koch Sequence“ (Reihenfolge, LICW-Einstieg, Custom-Zeichen) aus den globalen Einstellungen ins ⚙-Sheet des Koch Trainers verschoben (`TrainingSection.kochSequence`, nur bei `kochMode`, nicht in Generator ohne Koch und nicht im Echo). Die Prefs bleiben global und gelten weiter für Echo und Adaptiv; die Screens klemmen ihr Level beim Laden auf die neue Zeichenzahl.
