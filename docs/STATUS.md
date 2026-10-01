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
1. User: developer account (identity check pending).
2. Retake the home raw shot for the store (see the pending list below), then
   rebuild the graphics with `python3 store/make_graphics.py`.
3. Tag v1.3.0, build with `tools/build_release.sh`, upload the AAB.
4. Closed test: 12 testers × 14 days.
5. Production.

## Manual: pending for next release

Per CLAUDE.md rule 10, only the Markdown sources are updated per change;
HTML/PDF and screenshots are refreshed when the next version is cut. List
every screenshot (both `img/de/` and `img/en/`) whose screen changed since
the last release, with the reason. Clear this list after the release build
(steps: `manual/README.md` → "At release time").

- `hear_stats.png`, `echo_stats.png`: rows now read "N Versuche · noch k nötig · unter X %", percent carries an "aktuell" caption, rule sentence under the intro; icon hidden on the sending track.
- New: character detail sheet (Hören, e.g. a not-ready char; Geben with mix-ups) in the "Zeichenstatistik" chapter, DE+EN, via `manual/tools/insert.py`.
- Morse tree shots: portrait and landscape (letters, and deep tree).
- `home.png` (manual, DE+EN) (new "Lernen" tile; "Frei" is now one tile "Freie Modi", home no longer scrolls), plus a new hub shot "Freie Modi" (four tiles).
- **Play Store:** the start-screen shot changed too (five cards, "Freie Modi", "Lernressourcen"). Retake the home raw shot in `store/raw/{de,en}/` (dark theme, test phone) and rebuild the graphics with `python3 store/make_graphics.py` before the next store upload; check the caption and the other raw shots for the old home layout.
- New screens to shoot: learning-resources hub, character chart (one tile lit), Morse tree (letters; with
  digits and signs; one character lit), links page. Add them to the manual's
  "Learning resources" chapter with `manual/tools/insert.py`.
- Adventure map shots: pinch zoom can't be injected over adb, so
  `adv_map*.png` show the default zoom.
