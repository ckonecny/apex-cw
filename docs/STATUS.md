# Status

Baseline: Morserino-32 firmware v9.0.0. Repo: ckonecny/next_cw_trainer (public since 2026-09-28, GPL-3.0).
Latest tagged build: v1.6.0 (2026-10-05, tag `v1.6.0` = commit 45fe7e4, Head copy / Verstehen with Sentences, Q-groups and Mini QSO, break hint, beginner chapter in the manual). Previous: v1.5.0 (2026-10-03); older versions in `docs/STATUS-ARCHIVE.md`.

Open features and bugs: GitHub issues in ckonecny/next_cw_trainer (CLAUDE.md
rule 12). Finished work: `docs/STATUS-ARCHIVE.md` (rule 13). This file holds
only the current state, organisational steps and hints for the next session.

## Next steps — Play Store (user, 2026-09-28)
Done: upload key and signing, privacy policy, store texts and graphics
(`docs/PLAY-LISTING.md`, `docs/DECISIONS.md` "Play Store preparation"); store
raw shots home / Hören and Geben statistics retaken for v1.3.0 (2026-10-01,
dark, DE+EN), graphics rebuilt; AAB `releases/next-cw-trainer-v1.6.0.aab` (store raw shots still from v1.3.0).
1. User: developer account (identity check passed).
2. Upload the AAB; closed test: 12 testers × 14 days.
3. Production.
The store raw shots `home` and `games` still show the v1.3.0 screens: retake them
(dark, DE+EN) before uploading the v1.6.0 AAB. Check `qso`, `adventure`, `hear`
for the old home layout/labels too.

## Manual: screenshots not retaken (since v1.3.0, still so at v1.6.0)
Screens that show Straight-key-only states (issue #17: `keyer.png` WPM slider
disabled, `echo_result*.png` Geben row disabled, `qso.png`, `adv_settings*.png`/
tempo sheet measured row) still show the other keyer modes and stay valid; add
Straight-mode shots only if wanted. Adventure map shots show the default zoom
(pinch can't be injected over adb). The manual's progress and character-detail
shots were taken with seeded example data (12 weeks) on the test phone; the
phone's own data was restored afterwards.

## Landing page (branch `feature/landing-page`, not committed yet)
`site/` + `.github/workflows/pages.yml` ready. To go live: merge to main, then
repo Settings -> Pages -> Source "GitHub Actions". Then replace the disabled
"Google Play: coming soon" button with the store link once the app is live,
and set the Play listing's website to the Pages URL (decision in DECISIONS.md).

## New logo (2026-10-06, branch `feature/new-logo`): still to do
Done in the app (launcher icons), README, landing page. Pending:
- **Play Store**: rebuild `store/out` with `python3 store/make_graphics.py`
  after changing its palette (`TOP`/`BOTTOM` gradient is still the old blue
  panel; use the new navy `#122241`/teal/orange accents) and re-check
  `feature_{de,en}.png`; upload new `icon_512.png` + feature graphic in the
  Play Console (store listing, app icon). `docs/PLAY-LISTING.md` unchanged.
- **GitHub**: upload `android/tool/icon/social_preview.png` (repo Settings →
  Social preview; no API).
- **Manual** (at release): the built HTML/PDF carry no icon, but check the
  cover/info for the old look; screenshots with the launcher icon, if any.
- On-device install of the new icon still to verify (rule 4).

## Manual: pending for next release
- Retaken 2026-10-05 (DE+EN): `hear_start`, `hear_result`, `hear_weak`,
  `hear_sheet2`, `echo_start`, `echo_result`, `echo_result2` (the last one
  needs a 100 % block played by hand; the suggestion is not pre-ticked, tick
  it before the shot). Other ⚙ sheet shots may still show the old wraps. Taken
  on a debug build with the phone's prefs backed up and restored afterwards;
  `tools/echo_loop.py` knows "Gruppe n /" and "Geben …", needs Echo Prompt =
  Both (`echoDisplayMode` 3).
- Branch `feature/swap-touch-paddles`: new Keyer setting "Swap on-screen
  paddles"; retake the Keyer settings shot (`settings1.png`, DE+EN) and
  `keyer.png` if wanted (the touch paddles themselves look the same by default).
- Issue #37 (branch `fix/keyer-unknown-and-umlauts`, not yet installed): keyer
  text now shows `*`/`ERR`/umlauts; retake `keyer.png` only if it shows a `?`.

## Hints for the next session
- Release steps: `manual/README.md` "At release time"; `MANUAL_COMMIT=<hash>
  ./build.sh` states the release commit on the title page when only manual
  sources changed after the tag.
- Seeding statistics for screenshots needs a debug build (`run-as`); the
  release build isn't debuggable. Back up and restore the prefs
  (`shared_prefs/FlutterSharedPreferences.xml`) and `files/owntexts/`.
