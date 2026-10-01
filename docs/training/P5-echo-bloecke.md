# Phase 5: Adaptiver Echo-Ablauf, nur Anzeige (Blöcke, Ergebnis-Seite)

Status: **abgeschlossen** (kein Gesamttest, User-Entscheidung 2026-10-01) · Stand: 2026-09-25

## Ziel

Beim Echo Trainer kann ich zwischen **Klassisch** (endlos, wie auf dem
Morserino, unverändert) und **Blockweise** wählen. Blockweise übe ich
einen Block mit z. B. 10 Wörtern, sehe dabei, wie weit ich bin, und
bekomme am Ende eine **Ergebnis-Seite**: wie viele Wörter ich beim ersten
Versuch richtig hatte, welche erst nach Wiederholung und welche falsch,
mit meiner Antwort und dem ersten falschen Zeichen in Rot. Von dort
starte ich den nächsten Block oder höre auf.

Es ändert sich dabei **nichts** an Tempo, Abständen oder Zeichenvorrat.
Die Seite zeigt nur an.

## Nicht in dieser Phase

- Keine Vorschläge (neues Zeichen, Tempo, Abstand, Gebe-Tempo) und keine
  Schwachzeichen-Chips: Phase 6.
- Kein Trend, keine Reaktionszeit: Phase 8.
- Keine Änderung der Zeichenstatistik (weiter +2/−1, nur Koch-Echo
  "Adapt. Rand."). Die Firmware-Gewichtung +4/+2/−1 und die Erfassung in
  allen Echo-Modi gehören zu Phase 6, weil erst dort etwas daraus folgt.
- Der klassische Ablauf bleibt wie er ist.
- Kein neuer Start-Bildschirm (Phase 7).

## Entscheidungen

Offen, Empfehlung zuerst:

1. **Wo wählt man Klassisch/Blockweise?** Im ⚙-Sheet des Echo, Abschnitt
   "Ablauf", als Auswahl **Klassisch | Blockweise**, gespeichert im Profil
   Geben (`profile.echo.blockFlow`). *Empfehlung.* Standard: Klassisch,
   damit sich für niemanden etwas ändert. Alternative: ein Umschalter
   direkt im Screen. Der wäre aber ein weiteres Bedienelement, das Phase 7
   ohnehin neu ordnet.
2. **Blockgröße:** Es gilt "Wörter pro Block" (heute "Max # of Words",
   `profile.echo.maxWords`). Steht dort 0 (unbegrenzt), nimmt der
   Blockmodus **10**. *Empfehlung.* Im Blockmodus zeigt das Sheet den
   Wert als "Wörter pro Block" mit Minimum 1.
3. **Nach Wiederholung richtig (Konzept §9 Frage 7):** Wird **getrennt
   angezeigt** (◐) und nicht in den großen Prozentwert eingerechnet. Der
   Prozentwert ist der **Erstversuch** (nur ● zählt). Ob ◐ später als
   halber Treffer in Vorschläge eingeht, entscheidet Phase 6 mit
   Daten. *Empfehlung, entspricht Konzept 5.3.* Dadurch ist in dieser
   Phase keine Wertungsregel festgelegt, die später zurückgenommen werden
   müsste. Alternative: ◐ als halb im Prozentwert. Dann ist der Wert
   schwerer zu deuten.
4. **Aufgegeben (aufgedeckt)** zählt als falsch (○). Steht so im Konzept.
5. **Gilt für welche Echo-Varianten:** Echo Trainer und Koch-Echo (alle
   Inhaltsmodi). **Nicht** für Learn New Chr / Preview Char
   (`fixedTarget`), die haben keinen Block.
6. **Ende-Signal:** Am Blockende wird wie heute bei "Max # of Words" das
   `+` gespielt, danach erscheint die Ergebnis-Seite. Kein Signal bei
   manuellem Stopp. Bei Stopp mitten im Block: keine Ergebnis-Seite, der
   angefangene Block wird verworfen. *Empfehlung*, einfach und
   vorhersehbar.

## Firmware-Referenz

- `reference/.../m32_v6.ino`, Zustände SEND_WORD → GET_ANSWER →
  EVAL_ANSWER → EVAL_FEEDBACK → EVAL_SETTLE: pro Wort Vorspiel, Antwort,
  Auswertung, Wiederholung bis `posEchoRepeats`, danach Aufdecken. Der
  Ablauf pro Wort bleibt **unverändert**, die Blockebene ist neu und
  hat keine Firmware-Entsprechung außer dem Ende-Signal nach
  `posMaxSequence` Wörtern (`+`).

## Ist-Zustand App

- `android/lib/ui/echo_trainer_screen.dart`: Zustände `_State`
  (idle, playing, receiving, correct, wrong), Wortablauf in
  `_playWord` → `_beginReceive` → `_evaluate` → `_advance`.
- `_evaluate` kennt schon alles Nötige: `_repeats` (wievielter Versuch),
  `ok`, `exhausted` (aufgedeckt), `_target`, `_attempt`. Es wird nur
  noch pro Wort ein Ergebnis festgehalten.
- `_advance` zählt `_wordCounter` und beendet bei `_maxWords` mit `+`. Das
  ist genau die Stelle für das Blockende.
- Protokoll (`_log`, Ziel/Antwort/OK/ERR) und `_StatsBar` (✓/✗/%) sind
  vorhanden, Blockmodus ergänzt sie um Fortschritt und Punktereihe.
- ⚙-Sheet: `lib/ui/widgets/training_settings_sheet.dart`, Abschnitt
  `TrainingSection.echoFlow`. Profil-Felder:
  `lib/content/training_profile.dart`.
- Vorbild für Ergebnis-Seite und Buttons: `adaptive_copy_body.dart`
  (`_buildResult`, `_PrimaryButton`, `_SecondaryButton`).

## Schritte

Jeder Schritt ist einzeln baubar und installierbar.

**5a: Einstellung und Wort-Ergebnisse.**
Profil-Feld `blockFlow` (Standard aus), Auswahl im ⚙-Sheet (Abschnitt
Ablauf), "Wörter pro Block" beschriftet. Im Echo pro Wort ein Ergebnis
festhalten (Ziel, Antwort, Versuche, Ausgang ●/◐/○, Index des ersten
falschen Zeichens). Noch keine sichtbare Änderung im klassischen Ablauf.
Prüfung: klassisch verhält sich exakt wie vorher, Analyzer sauber, Tests
laufen.

**5b: Blockablauf und Fortschritt.**
Im Blockmodus zählt `_advance` gegen die Blockgröße (Standard 10), oben
erscheint `Wort 4 / 10` mit Punktereihe (● ◐ ○, offene Wörter leer). Am
Blockende `+` und Wechsel in einen Zustand "Ergebnis". Noch schlichte
Ergebnis-Seite (Zahlen und Buttons).
Prüfung: Block mit 3 Wörtern läuft durch, Stopp verwirft, klassisch
unverändert.

**5c: Ergebnis-Seite fertig.**
Großer Erstversuchs-Prozentwert mit richtig / nach Wiederholung / falsch,
Statuszeile `Hören 22 WPM · Geben 15 WPM · Lektion 12` (Teile, die es
im Modus nicht gibt, entfallen), Wortliste mit Ziel und Antwort und rot
markiertem ersten falschen Zeichen, Schrift wie bei Adaptive Copy
zoombar. Buttons **Nächster Block** und **Beenden**.
Prüfung: alle drei Ausgänge erscheinen richtig, Sprache/Dunkelmodus ok.

**5d: Doku.** STATUS, DECISIONS, README-Tabelle, dieses Dokument.

## Ergebnis

Umgesetzt wie spezifiziert, 5a–5c einzeln installiert und vom User
geprüft. Abweichungen: keine. Kleinigkeit: "Nächster Block" startet über
`_startSession`, deshalb wird am Anfang jedes Blocks wieder `vvv<ka>`
gespielt. Code: `echo_trainer_screen.dart` (`WordResult`, `_recordWord`,
`_buildBlockProgress`, `_buildBlockResult`), Sheet-Auswahl in
`training_settings_sheet.dart`. Kein Gesamttest (User-Entscheidung 2026-10-01).
