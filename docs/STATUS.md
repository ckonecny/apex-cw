# Status

Baseline: Morserino-32 firmware v9.0.0. Repo: ckonecny/next_cw_trainer (public since 2026-09-28, GPL-3.0).
Latest tagged build: v1.5.0 (2026-10-03, tag `v1.5.0` = commit 299f683, daily goal and achievements, four new games, share into Own texts #24). Previous: v1.4.0 (2026-10-03); older versions in `docs/STATUS-ARCHIVE.md`.

Open features and bugs: GitHub issues in ckonecny/next_cw_trainer (CLAUDE.md
rule 12). Finished work: `docs/STATUS-ARCHIVE.md` (rule 13). This file holds
only the current state, organisational steps and hints for the next session.

## Next steps — Play Store (user, 2026-09-28)
Done: upload key and signing, privacy policy, store texts and graphics
(`docs/PLAY-LISTING.md`, `docs/DECISIONS.md` "Play Store preparation"); store
raw shots home / Hören and Geben statistics retaken for v1.3.0 (2026-10-01,
dark, DE+EN), graphics rebuilt; AAB `releases/next-cw-trainer-v1.5.0.aab` (store raw shots still from v1.3.0).
1. User: developer account (identity check passed).
2. Upload the AAB; closed test: 12 testers × 14 days.
3. Production.
The store raw shots `home` and `games` still show the v1.3.0 screens: retake them
(dark, DE+EN) before uploading the v1.5.0 AAB. Check `qso`, `adventure`, `hear`
for the old home layout/labels too.

## Manual: screenshots not retaken (since v1.3.0, still so at v1.5.0)
Screens that show Straight-key-only states (issue #17: `keyer.png` WPM slider
disabled, `echo_result*.png` Geben row disabled, `qso.png`, `adv_settings*.png`/
tempo sheet measured row) still show the other keyer modes and stay valid; add
Straight-mode shots only if wanted. Adventure map shots show the default zoom
(pinch can't be injected over adb). The manual's progress and character-detail
shots were taken with seeded example data (12 weeks) on the test phone; the
phone's own data was restored afterwards.

## Manual: pending for next release
- `settings*.png` showing the General card: new row "Pausenhinweis" (#5; check which file shows it).
- Head copy (#7): new `games.png` (nine cards) plus a screenshot per phase (setup, listening, question, result).
- Issue #37 (branch `fix/keyer-unknown-and-umlauts`, not yet installed): keyer
  text now shows `*`/`ERR`/umlauts; retake `keyer.png` only if it shows a `?`.

## Head copy (issue #7, branch `feature/head-copy`, not committed)
Engine, screen, manual text (DE+EN) done; debug build installed on the test
phone but **not yet checked on the device** (phone was locked): open Spiele →
Verstehen, play a round DE and EN, check "KUECHE" plays right, replay, results.
Later stages: mini-QSO on the same slot engine, Q-groups as a separate mode.

## Hints for the next session
- Release steps: `manual/README.md` "At release time"; `MANUAL_COMMIT=<hash>
  ./build.sh` states the release commit on the title page when only manual
  sources changed after the tag.
- Seeding statistics for screenshots needs a debug build (`run-as`); the
  release build isn't debuggable. Back up and restore the prefs
  (`shared_prefs/FlutterSharedPreferences.xml`) and `files/owntexts/`.
