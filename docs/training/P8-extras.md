# Phase 8: Extras

Status: **teilweise umgesetzt (Paddle, Trend, Verwechslungspaare fertig; Reaktionszeit gestrichen; Presets zurückgestellt)** · Stand: 2026-09-25

## Ziel

Vier kleine Ergänzungen (Reaktionszeit wurde vom User gestrichen), die das Üben angenehmer und aussagekräftiger
machen. Jede ist einzeln nutzbar und einzeln installierbar:

1. **Paddle-Wahl im Hören-Block:** Nach dem Aufdecken eines Blocks wähle ich
   mit dem Paddle: Dit = "Wiederholen", Dah = "Weiter" (wie am Morserino).
2. **Trend:** Auf der Ergebnis-Seite sehe ich, ob ich über die letzten
   Blöcke besser oder schlechter werde (z. B. "Trend 88 % ▲").
3. **Verwechslungspaare (Geben):** Die App zeigt, welche Zeichen ich
   miteinander verwechsle (z. B. "Soll K, gegeben R: 5×").
4. **Benannte Presets:** Ich speichere die Einstellungen eines Trainings
   (Hören oder Geben) unter einem Namen und lade sie später wieder.

## Nicht in dieser Phase

- Kein neuer Übungsablauf, keine neuen Vorschlags-Regeln.
- Verwechslungspaare fließen nicht in die Vorschläge ein, sie werden nur
  angezeigt.
- Verwechslungspaare gibt es nur beim **Geben**. Beim
  Hören tippe ich keine Antwort ein, die App kann dort nichts vergleichen.
- Eigener Text (File Player): Phase 9.

## Entscheidungen

Offen, Empfehlung zuerst. Bitte kurz bestätigen oder ändern:

1. **Umfang:** Alle fünf Punkte, in der Reihenfolge unten (einfach zuerst).
   Einzelne dürfen auch wegfallen.
2. **Trend:** Mittelwert der Erstversuchs-Quote der letzten 5 Blöcke gegen
   die 5 Blöcke davor. Pfeil ▲ bei mindestens +3 Prozentpunkten, ▼ bei
   mindestens −3, sonst ►. Erst ab 6 Blöcken sichtbar. Getrennt für
   Hören und Geben.
4. **Verwechslungspaare:** Aus dem ersten falschen Zeichen eines Wortes
   (Firmware-Logik `getFailedCharIndex`): Paar (Soll → Gegeben). Anzeige
   in der Statistik "Geben" als Liste der 10 häufigsten Paare mit Anzahl
   und auf der Ergebnis-Seite die Paare des letzten Blocks. Zurücksetzen
   zusammen mit der Statistik "Geben".
5. **Presets:** Pro Training (Hören, Geben) eine Liste. Ein Preset enthält
   das gesamte Profil (Zeichenvorrat, Lektion, Tempo, Abstände,
   Wörter pro Block, Practice Set, Einstellungen des Trainings). Speichern
   und Laden im ⚙-Sheet des jeweiligen Trainings. Löschen und
   Umbenennen ebenfalls dort. Maximal 10 pro Training. Statistik und
   Verlauf gehören nicht dazu.
6. **Paddle-Wahl:** Nur im Hören-Block, nach dem Aufdecken. Auf dem Bildschirm
   stehen weiterhin die Knöpfe "Wiederholen" und "Weiter", das Paddle ist
   eine zusätzliche Bedienung. Die native Funktion `choosePaddle` ist
   schon da.

## Firmware-Referenz

- Paddle-Wahl: `m32_v6.ino` Zustand nach dem Aufdecken im Generator
  (Dit = Wort wiederholen, Dah = nächstes Wort). Im nativen Code:
  `CwGenerator.kt:74` und `:290` (`choosePaddle`).
- Verwechslungspaare: `Koch::getFailedCharIndex`, bereits in der
  Statistik-Logik ab Phase 6 genutzt (`char_stats.dart:115`).
- Trend und Presets sind in der Firmware nicht
  vorgesehen (Presets ähneln den Snapshots). Neu und ohne Firmware-Vorlage.

## Ist-Zustand App

- Paddle: `choosePaddle` im nativen Generator und im MethodChannel
  (`MainActivity.kt:183`, `:311`) ist noch vorhanden. Die klassische
  Oberfläche, die es genutzt hat, ist seit Phase 7 weg. Im Hören-Block
  (`adaptive_copy_body.dart`) gibt es Wiederholen/Weiter nur als Knöpfe.
  Strings `repeat_upper` / `next_upper` sind noch da.
- Block-Ergebnisse: `echo_trainer_screen.dart:306–327` hält die
  Block-EMA (`echoBlockEma`, global) und `_blockResults` mit Ausgang je
  Wort. Ein Verlauf über mehrere Blöcke wird nirgends gespeichert.
- Statistik: `char_stats.dart` (Spuren `hear` / `echo`, Felder Versuche,
  Fehler, EMA, Gewicht). Anzeige in `char_stats_screen.dart`.
- Profile: `training_profile.dart`, Präfix `profile.<hear|echo>.<Feld>`.

## Schritte

Jeder Schritt: bauen, installieren, kurz prüfen, dann "passt".

- **8a Paddle-Wahl im Hören-Block (umgesetzt anders):** Wie die Firmware
  `Stop<Next>Rep` je Gruppe (Profilfeld `stopEach`, Standard aus, nur Hören). Dateien:
  `adaptive_copy_body.dart`, ggf. `MainActivity.kt`. Prüfung: Block
  aufdecken, Dit wiederholt das Wort, Dah geht weiter, die Knöpfe gehen
  weiterhin.
- **8b Trend.** Blockquote je Training nach jedem Block speichern (letzte
  20). Ergebnis-Seiten von Hören und Geben zeigen die Trendzeile. Dateien:
  neue Datei `content/block_history.dart`, beide Ergebnis-Seiten.
  Prüfung: 6 Blöcke üben, Trend erscheint, Pfeil passt zur Entwicklung.
- **8c Verwechslungspaare (umgesetzt).** Paare beim Geben mitzählen, in der Statistik
  "Geben" und auf der Ergebnis-Seite anzeigen. Dateien: `char_stats.dart`,
  `echo_trainer_screen.dart`, `char_stats_screen.dart`. Prüfung: bewusst
  ein falsches Zeichen geben, Paar erscheint mit Anzahl.
- **8d Benannte Presets.** Speichern, Laden, Umbenennen, Löschen im
  ⚙-Sheet. Dateien: `training_profile.dart`,
  `widgets/training_settings_sheet.dart`. Prüfung: Preset speichern,
  Einstellungen ändern, Preset laden, alles ist wieder wie vorher.
- **8e Docs.** STATUS, README, DECISIONS, diese Spec ("Ergebnis").

## Testplan

- [ ] Hören: Block aufdecken, Dit wiederholt, Dah geht weiter.
- [ ] Nach 6 Blöcken zeigt die Ergebnis-Seite einen Trend, getrennt für
      Hören und Geben.
- [ ] Geben: ein Zeichen absichtlich falsch geben, das Paar steht danach
      in der Statistik und auf der Ergebnis-Seite.
- [ ] Preset speichern, Einstellungen ändern, Preset laden: alles wie
      gespeichert. Ein Preset des Hörens erscheint nicht beim Geben.
- [ ] Statistik "Geben" zurücksetzen löscht auch die Paare.

## Ergebnis

Zwischenstand (2026-09-25), noch nicht abgeschlossen:

- **Paddle-Wahl:** als Firmware-`Stop<Next>Rep` je Gruppe umgesetzt
  (Dit = Wiederholen, Dah = Weiter), Standard aus, nur im Hören.
- **Trend:** `content/block_history.dart`, Trendzeile auf beiden
  Ergebnis-Seiten ab 6 Blöcken.
- **Think Time:** gilt nur noch für den Antwortbeginn (Firmware-Fix
  f98a409), danach zählt die Wortlücke.
- **Echo-Extras (vom User bestätigt):** Bestätigungstöne (Standard an,
  Schalter im Echo-⚙), Hören/Geben-Tempo auf Start- und Ergebnis-Seite,
  2 s "Bereit machen …" statt VVVKA/"+".
- **Echo-Anzeige:** "Versuch n von max" über dem Wort ab dem 2. Versuch,
  die drei Punkte entfallen; Reste des vorigen Blocks werden beim Start
  gelöscht.
- **Reaktionszeit:** vom User gestrichen (geringer Nutzen, viele
  Störfaktoren, keine Firmware-Vorlage).
- **Verwechslungspaare:** `CharStatsStore.pairs` (`T>G`, "–" = ausgelassen),
  gezählt beim ersten Versuch aus dem ersten falschen Zeichen, nur Geben.
  Anzeige: Zeile auf der Ergebnis-Seite, Top 10 in der Statistik "Geben",
  Zurücksetzen mit der Statistik.
- **Zurückgestellt (User, 2026-09-25):** 8d Benannte Presets.
