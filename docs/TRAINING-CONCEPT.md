# Trainingskonzept: Hören, Echo und Einstellungen (Entwurf)

Status: **Zielbild.** Erstellt 2026-09-23. Die Umsetzung läuft in Phasen,
jede wird vor dem Bauen einzeln genauer spezifiziert. Fahrplan, Status und
Phasen-Specs: `docs/training/README.md`. Offene Fragen (Abschnitt 9) werden
in der Phase geklärt, der sie zugeordnet sind.

Ziel: Der Echo Trainer bekommt denselben adaptiven Block-Ablauf wie der
adaptive Koch-Generator (Adaptive Copy, siehe `docs/ADAPTIVE-COPY.md`).
Dabei gilt die Firmware-Logik als Grundlage. Gleichzeitig werden die
Einstellungen neu geordnet, damit Hören und Geben unabhängig voneinander
geübt werden können, ohne ständig die Einstellungen umzustellen.

---

## 1. Ausgangslage

### 1.1 So macht es die Firmware (V9.0, geprüft im Quellcode)

- **Alle Einstellungen sind global.** Es gibt einen einzigen Wertespeicher.
  Koch-Lektion (`kochFilter`), Gruppenlänge (`posRandomLength`), Max # of
  Words (`posMaxSequence`), Wortlänge, Abstände und WPM gelten für
  Generator *und* Echo Trainer gleichermaßen.
- **Nur die Menüs sind kontextabhängig.** `MorsePreferences.cpp` hat pro
  Modus eine eigene Optionsliste (`kochGenOptions[]`, `kochEchoOptions[]`,
  `echoTrainerOptions[]` …). Drückt man im Modus lang, sieht man nur die
  Einstellungen, die dort wirken. Die Werte dahinter sind trotzdem geteilt.
- **Die Firmware-Lösung für "verschiedene Setups" sind Snapshots.** Es gibt
  8 Speicherplätze, die man manuell speichert und abruft.
- **Echo Speed Max** (`posEchoSpeedMax`, `m32_v6.ino` ca. Z. 2554): Das Wort
  wird mit dem normalen WPM vorgespielt. Für die Antwort senkt die Firmware
  das WPM auf den Maximalwert und stellt es in `echoTrainerEval()` wieder her.
- **Adaptive Speed** (`posSpeedAdapt`): **+1 WPM nach jedem richtigen, −1
  nach jedem falschen Wort** (`changeSpeed(echoEvalCorrect ? 1 : -1)`).
- **Adaptive Zeichengewichtung** (`Koch::increaseWordProbability`): Bei
  einem Fehler wird das *erste falsche Zeichen* stark (+4) und seine
  Nachbarn schwach (+2) gewichtet. Ein richtiges Wort senkt die Gewichte
  aller seiner Zeichen um 1. Das steckt hinter "Adapt. Rand.".
- **Practice Stats** (`MorsePracticeStats.h`) trennen bereits
  "listen"-Segmente (Generator) von "send"-Segmenten (Echo). Die Firmware
  sieht Hören und Geben also selbst als getrennte Messgrößen.

### 1.2 So ist es heute in der App

- Vier Trainings-Einstiege: CW Generator, Koch Trainer (derselbe Screen mit
  `kochMode`), Echo Trainer und Koch-Echo (derselbe Screen mit `kochMode`).
- WPM, Koch-Lektion, Gruppenlänge und Max # of Words stehen global in
  SharedPreferences (`wpm`, `kochLevel`, `groupLength`, `maxWords`). Stellt
  Adaptive Copy die Lektion hoch, springt auch der Echo Trainer mit.
- Die Einstellungsseite hat 14 Abschnitte, darunter viele modusspezifische.
- Der Echo Trainer weicht in zwei Punkten von der Firmware ab:
  - "Max. Geschwindigkeit" (`echoSpeedMax`) begrenzt nur die adaptive
    Steigerung und senkt **nicht** das Tempo für die Antwort.
  - Adaptive Speed erhöht um +1 nach je 10 richtigen und senkt nie wieder.
    Die Firmware macht ±1 pro Wort.
- **Gefundener Fehler (Regel 2, gemeinsamer Singleton):**
  `echo_trainer_screen.dart` setzt weder `setInterCharSpace` noch
  `setInterWordSpace` noch Practice Set oder Boost für den Generator. Das
  Vorspiel läuft also mit den Abständen des zuletzt benutzten Screens. Nach
  WiFi Trx sind das fix 3 Dits, nach Adaptive Copy dessen Farnsworth-Werte.
- Zeichenstatistik (`CharStatsStore`) ist *eine* Statistik für Hören
  (Adaptive Copy) und Echo ("Adapt. Rand."). Laut `ADAPTIVE-COPY.md` war
  schon notiert, dass Echo eine eigene Statistik braucht.

---

## 2. Leitprinzipien

1. **Die Firmware-Logik bleibt die Basis.** Ablauf, Wiederholungen,
   Auswertung, Tempo-Absenkung für die Antwort und die Gewichtung werden aus
   `reference/` übernommen. Neu ist nur, *wo* die Werte gespeichert sind und
   wie sie angezeigt werden.
2. **Pro Trainingsart ein eigenes Profil statt globaler Werte.** Das ist
   die automatische Version der Firmware-Snapshots: Jeder Trainingsmodus
   merkt sich seine eigenen Werte.
3. **Einstellungen dort, wo sie wirken.** Das ist die Weiterführung der
   kontextabhängigen Firmware-Menüs: Was nur einen Modus betrifft, steht in
   diesem Modus. Die globale Einstellungsseite behält nur, was wirklich
   überall gilt.
4. **Hören und Geben werden getrennt gemessen.** Es gibt zwei
   Statistik-Spuren und zwei Fortschritte, und jede Spur hat ihre eigene
   Koch-Lektion.
5. **Ein Bedienkonzept für alle Trainings.** Setup → Block → Ergebnis mit
   Vorschlägen, die man annehmen oder ablehnen kann. Das hat sich bei
   Adaptive Copy bewährt.
6. **Kein Big Bang.** Jede Phase ist für sich installierbar und testbar, und
   nach jeder Phase funktioniert die App vollständig.

---

## 3. Neue Struktur der Trainings

### 3.1 Koch ist ein Zeichenvorrat, kein eigener Modus

Heute gibt es "CW Generator" und "Koch Trainer" als zwei Einstiege in
denselben Screen, und dasselbe noch einmal beim Echo Trainer. Technisch
unterscheidet die Firmware nur durch `kochActive`, also durch einen Filter
auf den Zeichenvorrat plus Gewichtung.

**Vorschlag:** Jeder Trainings-Screen bekommt oben eine Wahl
**Zeichenvorrat**:

| Zeichenvorrat | Bedeutung | Verfügbare Inhalte |
|---|---|---|
| **Koch-Lektion** | die ersten N Zeichen der Koch-Folge | Zufall, Wörter, Abkürzungen, Gemischt |
| **Alle Zeichen** | "Random Groups"-Option (Buchstaben, Ziffern, …) | Zufall, Wörter, Abkürzungen, Rufzeichen, Gemischt |
| **Practice Set** | eigene Zeichenliste | Zufall |

Später (Phase 9, niedrige Priorität) kommt als vierter Zeichenvorrat
**Eigener Text** dazu. Das entspricht dem File Player der Firmware.

Rufzeichen gibt es nur bei "Alle Zeichen", weil die Firmware sie im
Koch-Menü auch nicht anbietet. "Adapt. Rand." ist kein eigener Inhalt mehr.
Die Gewichtung schwacher Zeichen wird eine Eigenschaft des adaptiven
Ablaufs (siehe 5.4).

### 3.2 Startseite

| Karte | Inhalt |
|---|---|
| **CW Keyer** | unverändert |
| **Hören** (CW Generator) | Zeichenvorrat-Wahl, Ablauf Klassisch/Adaptiv |
| **Geben** (Echo Trainer) | Zeichenvorrat-Wahl, Ablauf Klassisch/Adaptiv |
| **WiFi Trx** | unverändert |

Damit gibt es statt vier Trainings-Varianten zwei Screens, die denselben
Aufbau haben. Die Firmware-Namen bleiben als Untertitel erhalten, damit
Morserino-Nutzer sich zurechtfinden.

"Neues Zeichen lernen" und "Zeichen anhören" (Firmware: Learn New Chr /
Preview Char) sind keine eigenen Menüpunkte mehr. Man tippt in der Zeile der
Koch-Zeichen auf ein Zeichen und bekommt zwei Aktionen: "Anhören" und "Mit
Echo üben".

### 3.3 Klassisch und Adaptiv in beiden Screens

- **Klassisch:** Das ist der firmwaretreue Endlosablauf wie auf dem
  Morserino. Er bleibt erhalten, damit man das Original-Verhalten jederzeit
  hat.
- **Adaptiv:** Blockweise mit Ergebnis-Seite und Vorschlägen. Beim Hören
  existiert das schon (Adaptive Copy), beim Geben ist es neu (Abschnitt 5).

---

## 4. Einstellungen neu geordnet

### 4.1 Drei Ebenen

**Ebene A: Global** (Einstellungs-Seite über das Zahnrad auf der Startseite).
Das sind Dinge, die an der Person oder am Gerät hängen und nicht am Training.

- Darstellung: Theme, Sprache, Groß-/Kleinschreibung
- Ton: Tonhöhe, Weichheit, Audio-Ausgabe
- Taste/Keyer: Keyer-Modus, CurtisB, AutoChar Spacing, vband-Paddle, Tastenanalyse
- Koch-Folge (Native/LCWO/CWops/LICW/Custom, Custom-Zeichen, LICW-Carousel).
  Die Folge ist *der eine* Lernweg. Wie weit man darauf ist, ist pro
  Training verschieden (siehe Ebene B).
- Rufzeichen-Daten: Länge, Region, nur gängige Präfixe
- WiFi Trx: Rufzeichen, Name
- Zeichenstatistik ansehen/zurücksetzen (mit Reitern Hören/Geben)

**Ebene B: Trainingsprofil** (pro Screen gespeichert, im Screen selbst
bedienbar). Jedes Training hat sein eigenes Profil mit eigenen Werten:

| Wert | Profil "Hören" | Profil "Geben" |
|---|---|---|
| Zeichenvorrat + Inhalt | ✓ | ✓ |
| **Koch-Lektion** | ✓ eigene | ✓ eigene |
| Hör-Tempo (WPM) | ✓ | ✓ (Vorspiel) |
| **Gebe-Tempo** | – | ✓ (Abschnitt 5.2) |
| Zeichen-/Wortabstand (Farnsworth) | ✓ | ✓ (Vorspiel) |
| Gruppenlänge | ✓ z. B. 5 | ✓ z. B. 2–3 |
| Max. Wortlänge / Abkürzungslänge | ✓ | ✓ |
| Wörter pro Block (Max # of Words) | ✓ | ✓ |
| Practice Set + Boost | ✓ | ✓ |
| Anzeige beim Generator, Stop<Next>Rep, Wort doppelt | ✓ | – |
| Denkzeit, Wiederholungen, Echo-Anzeige, Bestätigungston, Tonversatz | – | ✓ |
| Adaptiv-Schwellen (hoch/niedrig, Glättung, Freischalt-Anzahl) | ✓ | ✓ |

Ein Profil wird automatisch gespeichert, sobald man etwas ändert. Beim
ersten Start nach dem Update werden beide Profile mit den heutigen globalen
Werten befüllt. Danach sieht zunächst alles aus wie vorher, aber die Werte
laufen auseinander, sobald man sie in einem Modus ändert.

**Ebene C: Im Block** (nur während des adaptiven Ablaufs): Vorschläge
annehmen oder anpassen und Abstände per ± nachstellen. Das gibt es heute bei
Adaptive Copy schon.

### 4.2 Wie das im Screen aussieht

Der Setup-Zustand jedes Trainings-Screens (bevor man Start drückt) zeigt:

1. **Kopfzeile:** Zeichenvorrat (Koch/Alle/Practice) und Ablauf
   (Klassisch/Adaptiv)
2. **Koch-Zeile:** aktive Zeichen, farbig nach Zeichentyp; Tippen auf ein
   Zeichen öffnet Anhören/Üben; ± für die Lektion
3. **Schnellwerte**, als große, tippbare Chips, die man mit ± verstellt:
   - Hören: `22 WPM · eff. 15 · Gruppe 5 · 20 Gruppen`
   - Geben: `Hören 22 · Geben 15 WPM · Gruppe 3 · 10 Wörter`
4. **Schwache Zeichen** aus der Statistik dieses Trainings (antippen zum
   Ein-/Ausschließen, wie heute)
5. **"⚙ Weitere Einstellungen"** öffnet ein Bottom-Sheet nur mit den Werten
   dieses Profils (Ebene B), gegliedert in Inhalt / Tempo & Abstand /
   Ablauf / Adaptiv
6. **Start**

Während ein Block läuft, verschwinden 1–5, so wie heute bereits beim
Generator ("Setup-Screen declutter").

Die globale Einstellungsseite schrumpft dadurch von 14 auf etwa 8
Abschnitte. Die Abschnitte "CW Generator", "Echo Trainer", "Adaptive Mode",
"Practice Set" und "Abstände" fallen dort weg.

---

## 5. Der adaptive Echo Trainer im Detail

### 5.1 Ablauf eines Blocks

```
Setup ──Start──▶ [ Vorspiel ▶ Antwort ▶ Auswertung ] × N Wörter ──▶ Ergebnis ──▶ nächster Block / Ende
```

Pro Wort (firmwaretreu, `m32_v6.ino` Zustände SEND_WORD → GET_ANSWER →
EVAL_ANSWER → EVAL_FEEDBACK → EVAL_SETTLE):

1. **Vorspiel** mit Hör-Tempo und den Abständen des Profils "Geben".
   Anzeige je nach "Echo-Anzeige": nur Ton / nur Text / beides.
2. **Antwort** mit Gebe-Tempo (5.2) und verschobenem Mithörton. Timeout ist
   die Denkzeit, gemessen ab Ende des Vorspiels, und verlängert sich mit
   jedem gegebenen Zeichen.
3. **Auswertung**: OK/ERR plus optional Bestätigungston. Bei ERR wird das
   Wort wiederholt, bis "Wiederholungen" erschöpft ist. Danach wird es
   aufgedeckt (invers angezeigt) und das nächste Wort kommt.

Am Blockende (nach "Wörter pro Block") kommt das Ende-Signal `+` und dann
die **Ergebnis-Seite**. Im klassischen Ablauf gibt es keine Ergebnis-Seite,
und es geht endlos weiter wie auf dem Morserino.

### 5.2 Hör-Tempo und Gebe-Tempo

Das ist die Antwort auf die ursprüngliche Frage. Firmwaretreue Semantik:

> **Antwort-Tempo = min(Hör-Tempo, Gebe-Tempo)**

- Im Profil "Geben" gibt es zwei sichtbare Werte: **Hören** und **Geben**.
- Das Gebe-Tempo ist in der Firmware "Echo Speed Max". Es ist eine
  Obergrenze: Hört man langsamer, als man gibt, gilt das Hör-Tempo auch für
  die Antwort.
- Einstellbar in 1er-Schritten, nicht nur in 5er-Schritten wie in der
  Firmware. Der Wert "Aus" entspricht der Firmware-Einstellung "No limit".
- Die Umschaltung passiert genau wie in der Firmware: Nach dem Vorspiel wird
  der Keyer auf das Gebe-Tempo gesetzt, vor dem nächsten Vorspiel geht es
  zurück aufs Hör-Tempo. Weil der Keyer ein Singleton ist, wird das Tempo
  bei *jedem* Wechsel explizit gesetzt (Regel 2).
- Das Antwort-Tempo muss am **Keyer** gesetzt werden. Der Dekoder arbeitet
  auf den Keyer-Symbolen und braucht selbst kein WPM. Heute setzt der Echo
  Trainer das Keyer-Tempo gar nicht (Fehler C in der P1-Spec).

### 5.3 Was gemessen wird

Pro Wort wird festgehalten:

| Messwert | Herkunft | Verwendung |
|---|---|---|
| Richtig beim **ersten** Versuch | neu | Hauptmaß für Tempo-Vorschläge |
| Richtig nach Wiederholung | Firmware-Ablauf | Anzeige, zählt als halber Treffer |
| Erstes falsches Zeichen + Nachbarn | `Koch::getFailedCharIndex` | Zeichenstatistik "Geben" |
| Aufgegeben (aufgedeckt) | Firmware-Ablauf | zählt als Fehler |
| Reaktionszeit (Ende Vorspiel → erstes Element) | neu, optional | später: Maß für "sicher erkannt" |

Zeichenstatistik: Pro Zeichen werden in der Spur "Geben" dieselben Felder
wie heute gepflegt (Versuche, Fehler, EMA-Fehlerrate, Gewicht). Das
Gewicht folgt exakt der Firmware: erstes falsches Zeichen +4, Nachbarn +2,
bei richtigem Wort alle Zeichen −1.

### 5.4 Was angepasst wird (Vorschläge auf der Ergebnis-Seite)

Wie bei Adaptive Copy laufen die Hebel unabhängig voneinander. Jeder
erscheint als Vorschlagszeile mit Häkchen und ± zum Nachstellen.

| Hebel | Auslöser | Richtung |
|---|---|---|
| **Neues Koch-Zeichen** | alle aktiven Zeichen der Spur "Geben" über Schwelle hoch + Mindestanzahl | Lektion +1 (nur Profil "Geben") |
| **Hör-Tempo / Abstand** | Block-EMA der Erstversuchs-Quote ≥ hoch (2 Blöcke in Folge) | erst Abstand enger, dann Hör-WPM +1 |
| | Block-EMA < niedrig | Abstand weiter |
| **Gebe-Tempo** | Erstversuchs-Quote ≥ hoch *und* Gebe-Tempo < Hör-Tempo | Vorschlag +1, nie automatisch |
| **Schwache Zeichen** | EMA-Fehlerrate der Spur "Geben" | Boost im nächsten Block, antippbar |

Übernommene Regeln aus Adaptive Copy:

- Kein Tempo-Anstieg im selben Block, in dem ein neues Zeichen dazukommt.
- Kein Tempo-Anstieg, solange noch Koch-Zeichen offen sind. Offen ist, ob
  das beim Echo auch gelten soll (Abschnitt 9).
- Obergrenze der Schwelle ist 99 %, nicht 100 %.

Firmware-Adaptive Speed (±1 pro Wort) bleibt als Option im **klassischen**
Ablauf erhalten und wird dort firmwaretreu korrigiert.

### 5.5 Optik

Aufbau wie der adaptive Koch-Generator, damit beide Trainings gleich aussehen.

**Während des Blocks:**
- Oben ein Fortschritt: `Wort 4 / 10` und eine Punktereihe (● richtig,
  ◐ nach Wiederholung, ○ falsch)
- Mitte: ein großes Feld mit Zustand ("Hör zu …" / "Du bist dran" mit
  Countdown der Denkzeit) und darunter die eigene Eingabe, die Zeichen für
  Zeichen erscheint
- Protokoll wie heute (Ziel / Antwort / OK / ERR), kleiner darunter
- Paddles unten

**Ergebnis-Seite:**
- Großer Prozentwert (Erstversuch), daneben richtig / nach Wiederholung /
  falsch
- Statuszeile: `Hören 22 WPM · eff. 15 · Geben 15 WPM · Lektion 12 · Trend 88 % ▲`
- Liste der Wörter: Ziel und Antwort untereinander, das erste falsche
  Zeichen rot markiert
- Vorschlagszeilen (neues Zeichen zuerst, mit Stern und "Anhören"-Knopf)
- Schwache Zeichen als Chips (antippen = im nächsten Block verstärken)
- Abstand ± (wie heute bei Adaptive Copy)
- Buttons: "Nächster Block" / "Beenden"

### 5.6 Zeichenstatistik: zwei Spuren

- `CharStatsStore` bekommt eine Spur-Kennung: `copy` (Hören) und `echo`
  (Geben).
- Übernahme der heutigen Daten: Die bestehende Statistik stammt fast nur
  aus Adaptive Copy und wird zur Spur `copy`. Die Spur `echo` startet leer
  (Alternative siehe Abschnitt 9).
- Der Statistik-Screen bekommt zwei Reiter, **Hören** und **Geben**. Dann
  sieht man direkt: "K höre ich sicher, gebe es aber oft falsch."
- Zurücksetzen geht pro Spur.

---

## 6. Was aus welchem Konzept übernommen wird

| Idee | Quelle |
|---|---|
| Ablauf Vorspiel/Antwort/Auswertung, Wiederholen, Aufdecken, Start-/Endsignal | Firmware |
| Antwort-Tempo als Obergrenze (Echo Speed Max) | Firmware |
| Gewichtung erstes falsches Zeichen +4 / Nachbarn +2 | Firmware (`Koch::increaseWordProbability`) |
| Kontextabhängige Einstellungen | Firmware-Menüs, weitergeführt |
| Gespeicherte Setups | Firmware-Snapshots, automatisiert als Profile |
| Hören und Geben getrennt messen | Firmware Practice Stats (listen/send) |
| Blöcke, Ergebnis-Seite, Vorschläge zum Annehmen, EMA, Freischalt-Regeln | Adaptive Copy |
| Schwache Zeichen antippen / verstärken | Adaptive Copy |
| Aufgeräumter Screen während des Übens, 1 s Vorlauf | Generator-Cleanup |
| Effektive WPM-Anzeige, Zeichenfarben | UI-Polish-Runde |

---

## 7. Umsetzung in Phasen

Die Phasenliste mit Status und die Detail-Specs stehen in
`docs/training/README.md`. Kurzfassung:

1. Echo-Grundlagen: Singleton-Fehler, Gebe-Tempo, Adaptive Speed ±1
2. Trainingsprofile (Datenebene)
3. Einstellungen in die Screens
4. Getrennte Zeichenstatistik Hören/Geben
5. Adaptiver Echo-Ablauf, zuerst nur Anzeige
6. Adaptive Vorschläge beim Echo
7. Koch als Zeichenvorrat, neue Startseite
8. Extras: Reaktionszeit, benannte Presets, Trend, Verwechslungspaare
9. Eigener Text (File Player) als weiterer Zeichenvorrat, niedrige Priorität

**Warum diese Reihenfolge:** Phase 1 löst das akute Problem (schneller
hören als geben) mit einer kleinen Änderung. Phase 2 ist die Voraussetzung
für alles Weitere und ändert noch nichts an der Oberfläche. Der Umbau der
Startseite (7) kommt erst, wenn beide Screens gleich aufgebaut sind. Dann
ist er fast nur noch Navigation. Der File Player kommt ganz am Ende, weil
er derzeit nicht wichtig ist.

---

## 8. Risiken

- **Migration der Einstellungen (Phase 2):** Ein falscher Standardwert
  überschreibt Nutzerwerte. Bekanntes Muster: `?? default` greift nicht bei
  bereits gespeichertem `''` (siehe DECISIONS.md). Migration nur einmal,
  mit Versionsmarke.
- **Singleton-Engine:** Mehr Tempo-Wechsel pro Wort bedeuten mehr Stellen,
  an denen ein Wert veraltet sein kann. Alle Werte werden an einer Stelle
  gesetzt (`_applyPromptConfig()` / `_applyAnswerConfig()`), nicht verstreut.
- **Zwei Echo-Varianten parallel** (Klassisch + Adaptiv) erhöhen den
  Testaufwand. Gemeinsame Teile (Vorspiel, Antwort, Auswertung) werden
  deshalb in eine Klasse ohne UI ausgelagert, die beide Abläufe benutzen.

---

## 9. Offene Fragen an dich

1. **Startseite:** Einverstanden, dass "Koch Trainer" als eigene Karte
   wegfällt und Koch ein Zeichenvorrat in "Hören" und "Geben" wird? Oder
   soll Koch als eigene Karte bleiben?
2. **Gebe-Tempo:** Firmware-Semantik als Obergrenze (min aus Hören und
   Geben), wie vorgeschlagen? Oder ein fester, eigener Wert, auch wenn er
   höher als das Hör-Tempo ist?
3. **Koch-Folge global:** Eine Folge (z. B. LCWO) für beide Trainings, nur
   die Lektion getrennt? Oder soll auch die Folge pro Training wählbar sein?
4. **Abstände (Farnsworth):** Pro Profil getrennt, wie vorgeschlagen?
5. **Echo-Statistik:** Leer starten, oder mit den bisherigen Daten
   vorbefüllen?
6. **Tempo-Sperre bei offenen Koch-Zeichen:** Adaptive Copy steigert das
   Tempo nicht, solange noch Zeichen freigeschaltet werden. Soll das beim
   Echo genauso sein?
7. **Nach Wiederholung richtig:** Als halber Treffer werten (Vorschlag),
   als voller Treffer oder als Fehler?
8. **Adaptiv-Schwellen:** Pro Profil (Vorschlag), oder eine gemeinsame
   Einstellung für beide?
