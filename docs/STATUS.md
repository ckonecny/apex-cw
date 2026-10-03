# Status

Baseline: Morserino-32 firmware v9.0.0. Repo: ckonecny/next_cw_trainer (public since 2026-09-28, GPL-3.0).
Latest tagged build: v1.4.0 (2026-10-03, tag `v1.4.0` = commit 3f687f4, interference simulation, "Morse key" wording, GUI fixes #26/#28/#29). Previous: v1.3.0 (2026-10-01); older versions in `docs/STATUS-ARCHIVE.md`.

Open features and bugs: GitHub issues in ckonecny/next_cw_trainer (CLAUDE.md
rule 12). Finished work: `docs/STATUS-ARCHIVE.md` (rule 13). This file holds
only the current state, organisational steps and hints for the next session.

## Next steps — Play Store (user, 2026-09-28)
Done: upload key and signing, privacy policy, store texts and graphics
(`docs/PLAY-LISTING.md`, `docs/DECISIONS.md` "Play Store preparation"); store
raw shots home / Hören and Geben statistics retaken for v1.3.0 (2026-10-01,
dark, DE+EN), graphics rebuilt; AAB `releases/next-cw-trainer-v1.4.0.aab` (store raw shots still from v1.3.0).
1. User: developer account (identity check passed).
2. Upload the AAB; closed test: 12 testers × 14 days.
3. Production.
Check the remaining raw shots (`qso`, `games`, `adventure`, `hear`) for the old
home layout/labels before the upload.

## Manual: screenshots not retaken at v1.3.0
Screens that show Straight-key-only states (issue #17: `keyer.png` WPM slider
disabled, `echo_result*.png` Geben row disabled, `qso.png`, `adv_settings*.png`/
tempo sheet measured row) still show the other keyer modes and stay valid; add
Straight-mode shots only if wanted. Adventure map shots show the default zoom
(pinch can't be injected over adb). The manual's progress and character-detail
shots were taken with seeded example data (12 weeks) on the test phone; the
phone's own data was restored afterwards.

## Manual: pending for next release
- `home.png` (DE+EN): daily goal card at the top (#31).
- New (#13): `tb_lobby.png` (DE+EN), the Trailblazer lobby; the games hub list (`games.png`) shows two more cards.
- New: Fight the Pileup (#15): `pu_lobby.png` DE+EN (manual section has no image yet), `games.png` (fifth game card).
- New: achievements page and its settings incl. sessions, reminder and awards (#31–#34); `settings1.png`: new switch in General.

## In progress: daily goal series (#3)
Branch `feature/practice-log` (neither pushed nor merged). #30 practice log
(c88039e) and #31 goal card, achievements page and settings are committed;
a real streak across days is unit-tested only. #32 reminder (d6818bd,
native, see DECISIONS) is committed. #33 spaced sessions (3b915e1) is
committed. #34 achievements (05ed4c4) is committed (follow-up #36). #35 weekly
review implemented, not committed; it closes the series #3.

## Next game port
Radio Cave (#14). Branches `feature/maze-games` and `feature/pileup` are merged into `main` (not pushed).

## Hints for the next session
- Release steps: `manual/README.md` "At release time"; `MANUAL_COMMIT=<hash>
  ./build.sh` states the release commit on the title page when only manual
  sources changed after the tag.
- Seeding statistics for screenshots needs a debug build (`run-as`); the
  release build isn't debuggable. Back up and restore the prefs
  (`shared_prefs/FlutterSharedPreferences.xml`) and `files/owntexts/`.
