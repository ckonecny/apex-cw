# Phase 4: Getrennte Zeichenstatistik Hören/Geben

Status: **abgeschlossen** · Stand: 2026-09-25

## Ziel

Die App führt für **Hören** (CW Generator, Koch-Generator, Adaptive Copy)
und **Geben** (Echo Trainer) je eine eigene Zeichenstatistik. Was ich
beim Echo falsch gebe, macht das Hören nicht schwerer und umgekehrt. Jede
Statistik ist **im jeweiligen Training** erreichbar (📊 in der Titelleiste
des Koch-Generators/Adaptive Copy bzw. des Koch-Echo), mit eigenem
Zurücksetzen. In den globalen Einstellungen gibt es keine Statistik mehr.

## Nicht in dieser Phase

- Keine neue Erfassung beim Echo. Wie heute wird nur im Koch-Echo mit
  "Adapt. Rand." mitgezählt (Phase 5/6 erweitert das).
- Keine Schwachzeichen-Vorschläge oder Boost-Automatik beim Echo (Phase 6).
- Keine Änderung an Gewichtung, EMA, Schwellen oder Freischalt-Regeln.
- Keine Änderung der Statistik-Felder (Versuche, Fehler, EMA, Gewicht).

## Entscheidungen

Offen, Empfehlung zuerst:

1. **Bestehende Daten (Konzept §9 Frage 5):** Die vorhandene Statistik
   wird zur Spur **Hören**. Die Spur **Geben** startet **leer**.
   *Empfehlung.* Grund: Die Daten stammen fast nur aus Adaptive Copy,
   und "Geben" mit fremden Hör-Werten vorzubefüllen wäre falsch.
   Alternative: beide Spuren bekommen eine Kopie. Dann sieht anfangs alles
   aus wie vorher, aber Echo würde Schwächen gewichten, die nur das Hören
   betreffen.
2. **Zurücksetzen:** in der Statistik der jeweiligen Spur (🗑 oben rechts).
   Die Knöpfe in den globalen Einstellungen entfallen. *Freigegeben.*
3. **Statt Reitern (User, 2026-09-25):** Es gibt keinen gemeinsamen
   Statistik-Screen mit Reitern, sondern jedes Training öffnet seine eigene
   Statistik (Prinzip "Einstellungen dort, wo sie wirken").

## Firmware-Referenz

Die Firmware führt getrennte Practice-Stats für listen und send
(`reference/`, Practice Stats). Das Gewicht pro Zeichen folgt weiter der
Firmware-Formel wie heute. Es ändert sich nur, *wo* gespeichert wird.
(Genaue Datei:Zeile wird beim Umsetzen in Schritt 4a nachgetragen.)

## Ist-Zustand App

- `android/lib/content/char_stats.dart`: `CharStatsStore` speichert alles
  unter einem Schlüssel `charStats` (JSON, pro Zeichen a/e/ema/lb/w).
  Enthält auch die Migration vom alten Echo-Format `adaptiveWeights`.
  `weakCharsLifetime(store, activeChars, …)` liest daraus.
- Nutzer:
  - `adaptive_copy_body.dart` (lädt Zeile ~182/455, schreibt ~465,
    Schwachzeichen ~186/546) → **Hören**
  - `generator_screen.dart` Zeile ~207 (Schwachzeichen am Koch-Start) →
    **Hören**
  - `echo_trainer_screen.dart` Zeile ~252 (lädt), ~269 (Gewichte), ~287
    (schreibt, nur Koch-Echo Modus 4 "Adapt. Rand.") → **Geben**
  - `char_stats_screen.dart` liest Statistik + Hör-Koch-Lektion
    (`TrainingProfile.hear`) + globale Adaptiv-Schwellen
  - `settings_screen.dart` ~231–251: Ansehen/Zurücksetzen (gemeinsam)

## Schritte

Jeder Schritt ist einzeln baubar und installierbar.

**4a – Datenebene.** `CharStatsStore` bekommt eine Spur (`hear`/`echo`,
analog `TrainingProfile`). Schlüssel: `charStats.hear`, `charStats.echo`.
Beim ersten Laden: vorhandenes `charStats` (bzw. altes `adaptiveWeights`)
→ `charStats.hear`, alter Schlüssel wird entfernt; `charStats.echo` leer
(Entscheidung 1). `reset` gilt pro Spur. Alle Aufrufer geben ihre Spur an:
Adaptive Copy und Generator = `hear`, Echo = `echo`.
Dateien: `char_stats.dart`, `adaptive_copy_body.dart`,
`generator_screen.dart`, `echo_trainer_screen.dart`.
Prüfung: Unit-Test für Migration und Spurtrennung; App verhält sich beim
Hören wie vorher, Echo startet mit Gewicht 1 für alle Zeichen.

**4b – Statistik im jeweiligen Training.** `CharStatsScreen(track)`.
📊 in der Titelleiste (nur Koch-Modus, nicht während des Übens) vor dem ⚙:
Koch-Generator/Adaptive Copy → Spur Hören, Koch-Echo → Spur Geben. Der
Screen zeigt die aktiven Koch-Zeichen mit der Lektion des jeweiligen
Profils. Hören: wie bisher (bereit/Freischalt-Schwelle). Geben: ohne
Freischalt-Anzeige, schwächste Zeichen oben. 🗑 setzt nur diese Spur zurück
(mit Bestätigung). Der Abschnitt "Zeichenstatistik" in den globalen
Einstellungen entfällt. Dateien: `char_stats_screen.dart`,
`generator_screen.dart`, `echo_trainer_screen.dart`, `settings_screen.dart`,
`strings.dart`.
Prüfung: beide Screens zeigen unterschiedliche Daten; Reset betrifft nur die
eigene Spur.

**4c – Doku.** README (Zeile 4), STATUS, DECISIONS (Entscheidungen 1/2,
Spur-Schlüssel), Grundsatz in README "bis dahin teilen sich beide" auf
"jetzt getrennt" ändern, `ADAPTIVE-COPY.md`-Hinweis auf gemeinsame
Statistik korrigieren.

## Testplan

1. Koch-Generator → 📊: zeigt die alten Werte. Koch-Echo → 📊: leer.
2. Adaptive Copy einen Block üben → nur die Statistik im Koch-Generator ändert sich.
3. Koch-Echo mit "Adapt. Rand." ein paar Wörter, auch falsch antworten →
   nur die Statistik im Koch-Echo ändert sich, Zeichen mit Fehlern kommen öfter.
4. 🗑 in der Echo-Statistik → Hören bleibt unverändert, und umgekehrt.
5. In den globalen Einstellungen gibt es keine Statistik mehr.
6. Koch-Generator: Schwachzeichen am Start kommen weiter aus **Hören**.
7. App neu starten: Werte bleiben in beiden Spuren erhalten.

## Ergebnis

4a und 4b umgesetzt und vom User auf dem Gerät getestet. Abweichung von der
ersten Spec: keine Reiter, sondern 📊 im jeweiligen Training (Entscheidung
3). Firmware-Referenz wurde nicht gebraucht (nur Speicherort geändert,
Formeln unverändert). Nacharbeit: keine. Bekannt: Echo zählt weiterhin nur
im Koch-Echo "Adapt. Rand." mit; Ausweitung in Phase 5/6.
