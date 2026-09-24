# Trainings-Umbau: Fahrplan

**Einstieg für jede Session zu diesem Thema.** Nur diese Datei und die
Spec der aktuellen Phase lesen. `docs/TRAINING-CONCEPT.md` ist das
Zielbild und wird nur gelesen, wenn eine Phase neu spezifiziert wird, und
auch dann nur die Abschnitte, die in der Tabelle unten stehen.

## Arbeitsweise

Jede Phase durchläuft dieselben Schritte. Eine Phase ist erst fertig, wenn
sie auf dem Gerät getestet ist. Erst dann beginnt die nächste.

1. **Spezifizieren:** `P<n>-<name>.md` nach der Vorlage unten schreiben.
   Offene Fragen der Phase klären. Entscheidungen in `docs/DECISIONS.md`
   eintragen. Status → *Spec freigegeben*, sobald der User zustimmt.
2. **Umsetzen:** Schritt für Schritt nach der Spec. Jeder Schritt ist für
   sich baubar. Nach jedem Schritt: bauen, installieren, kurz prüfen.
3. **Testen:** Der User arbeitet den Testplan der Spec auf dem Gerät durch.
4. **Abschließen:** In der Spec den Abschnitt "Ergebnis" füllen
   (Abweichungen, Nacharbeit). Status hier aktualisieren. `docs/STATUS.md`
   aktualisieren. Commit nur auf Anweisung.

Kleine Phasen dürfen Spec und Umsetzung in einer Session haben. Große
Phasen: eine Session für die Spec und eine oder mehrere für die Umsetzung.

**Session-Start (zum Kopieren):**
> Trainings-Umbau: lies `docs/training/README.md` und die Spec der
> aktuellen Phase. Dann weiter mit dem nächsten offenen Schritt.

## Phasen

| # | Phase | Status | Spec | Konzept-Abschnitte | Offene Fragen (Konzept §9) |
|---|---|---|---|---|---|
| 1 | Echo-Grundlagen: Singleton-Fehler, Gebe-Tempo (Adaptive Speed bewusst nicht) | **Spec freigegeben** | [P1](P1-echo-grundlagen.md) | 1, 5.2 | 2 |
| 2 | Trainingsprofile (nur Datenebene, Oberfläche bleibt) | offen | – | 4.1 | 3, 4, 8 |
| 3 | Einstellungen in die Screens (Chips, Sheet), globale Seite schrumpft | offen | – | 4.2 | – |
| 4 | Getrennte Zeichenstatistik Hören/Geben | offen | – | 5.3, 5.6 | 5 |
| 5 | Adaptiver Echo-Ablauf, nur Anzeige (Blöcke, Ergebnis-Seite) | offen | – | 5.1, 5.5 | 7 |
| 6 | Adaptive Vorschläge beim Echo | offen | – | 5.4 | 6 |
| 7 | Koch als Zeichenvorrat, neue Startseite | offen | – | 3 | 1 |
| 8 | Extras: Reaktionszeit, benannte Presets, Trend, Verwechslungspaare | offen | – | 7 (Phase 8) | – |
| 9 | Eigener Text (File Player) als weiterer Zeichenvorrat | offen, niedrige Priorität | – | – | – |

Status-Werte: offen → Spec in Arbeit → Spec zur Freigabe → Spec
freigegeben → in Umsetzung → Install ausstehend → Test durch User →
abgeschlossen.

Jede Phase lässt die App vollständig benutzbar zurück. Phasen werden
nicht vermischt (CLAUDE.md Regel 7).

## Vorlage für eine Phasen-Spec

```
# Phase <n>: <Name>
Status: … · Stand: <Datum>

## Ziel                  – was der User danach kann (1–3 Sätze, Endnutzer-Sicht)
## Nicht in dieser Phase – was bewusst später kommt
## Entscheidungen        – getroffen (→ DECISIONS.md) und noch offen
## Firmware-Referenz     – Datei:Zeile + was genau übernommen wird
## Ist-Zustand App       – Datei:Zeile, relevante Fakten (damit keiner neu suchen muss)
## Schritte              – je Schritt: Änderung, Dateien, Prüfung; einzeln installierbar
## Testplan              – Checkliste für den User auf dem Gerät
## Ergebnis              – nach Abschluss: was umgesetzt, Abweichungen, Nacharbeit
```
