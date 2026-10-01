# Status

Baseline: Morserino-32 firmware v9.0.0. Repo: ckonecny/next_cw_trainer (public since 2026-09-28, GPL-3.0).
Latest tagged build: v1.2.2 (2026-09-28: nav bar no longer covers the bottom row on Android 15+ with 3-button navigation; first build signed with the upload key). Previous: v1.2.1 (2026-09-28: author credits, GPL-3.0 licence page, licence guard); v1.2.0 (2026-09-28, text adventure Zork I–III in CW, new app icon, games order); v1.1.0 (2026-09-27, Hören typing mode, Koch character row, terminology pass); v1.0.0 (2026-09-26, first build handed out to other users).

Open features and bugs: GitHub issues in ckonecny/next_cw_trainer (CLAUDE.md
rule 12). Finished work: `docs/STATUS-ARCHIVE.md` (rule 13). This file holds
only the current state, organisational steps and hints for the next session.

## Next steps — Play Store (user, 2026-09-28)
Done so far: upload key and signing, privacy policy, store texts and graphics
(details in `docs/STATUS-ARCHIVE.md`, `docs/DECISIONS.md` "Play Store
preparation", `docs/PLAY-LISTING.md`).
1. User: developer account (identity check passed).
2. Retake the home raw shot for the store (see the pending list below), then
   rebuild the graphics with `python3 store/make_graphics.py`.
3. Tag v1.3.0, build with `tools/build_release.sh`, upload the AAB.
4. Closed test: 12 testers × 14 days.
5. Production.

## In progress: own texts (issue #8)
Implemented and checked on the test phone (library, playback, tap to jump,
live tempo, Continue/Start over); manual DE+EN written; not committed yet.
Not tried on the phone: pasting from the real clipboard (the test text was
copied into the app folder), a text near the 20,000-character limit. Next:
ask for the commit (`Closes #8`). Follow-ups: #21, #22, #23, #24.

## Manual: pending for next release

Per CLAUDE.md rule 10, only the Markdown sources are updated per change;
HTML/PDF and screenshots are refreshed when the next version is cut. List
every screenshot (both `img/de/` and `img/en/`) whose screen changed since
the last release, with the reason. Clear this list after the release build
(steps: `manual/README.md` → "At release time").

- `hear_stats.png`, `echo_stats.png`: rows now read "N Versuche · noch k nötig · unter X %", percent carries an "aktuell" caption, rule sentence under the intro; icon hidden on the sending track.
- New: progress tab ("Verlauf") in `hear_stats`/`echo_stats` style, one shot per training (12 weeks, with data), and the character detail sheet now has the weekly curve — both in the "Zeichenstatistik" chapter, DE+EN.
- New: character detail sheet (Hören, e.g. a not-ready char; Geben with mix-ups) in the "Zeichenstatistik" chapter, DE+EN, via `manual/tools/insert.py`.
- Morse tree shots: portrait and landscape (letters, and deep tree).
- `home.png` (manual, DE+EN) (new "Lernen" tile; "Frei" is now one tile "Freie Modi", home no longer scrolls), plus a new hub shot "Freie Modi" (four tiles).
- **Play Store:** the start-screen shot changed too (five cards, "Freie Modi", "Lernressourcen"). Retake the home raw shot in `store/raw/{de,en}/` (dark theme, test phone) and rebuild the graphics with `python3 store/make_graphics.py` before the next store upload; check the caption and the other raw shots for the old home layout.
- New screens to shoot: learning-resources hub, character chart (one tile lit), Morse tree (letters; with
  digits and signs; one character lit), links page. Add them to the manual's
  "Learning resources" chapter with `manual/tools/insert.py`.
- Adventure map shots: pinch zoom can't be injected over adb, so
  `adv_map*.png` show the default zoom.
- Issue #17 (straight key): the settings screenshot with the Keyer card (`settings*.png`: new row "Starttempo Handtaste" in Straight mode), `keyer.png` (WPM slider disabled in Straight), `echo_result*.png` (Geben row disabled in Straight), `qso.png`, `adv_settings*.png`/tempo sheet (measured row). Text already updated (DE+EN).
- Issue #8 (own texts): `home.png` is unchanged, but the "Freie Modi" hub shot now has five tiles; new shots: library ("Eigene Texte", with one text), player (text playing, "after playing" mode) and its ⚙ sheet. Add them to the new "Own texts"/"Eigene Texte" chapter with `manual/tools/insert.py`.
