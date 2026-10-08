# Status

Baseline: Morserino-32 firmware v9.0.0. Repo: ckonecny/apex-cw (public since 2026-09-28, GPL-3.0).
Latest tagged build: v1.6.0 (2026-10-05, tag `v1.6.0` = commit 45fe7e4, Head copy / Verstehen with Sentences, Q-groups and Mini QSO, break hint, beginner chapter in the manual). Latest pre-release: `v1.6.1-beta1` (2026-10-06, commit 6d08a30). Previous: v1.5.0 (2026-10-03); older versions in `docs/STATUS-ARCHIVE.md`.

Open features and bugs: GitHub issues in ckonecny/apex-cw (CLAUDE.md
rule 12). Finished work: `docs/STATUS-ARCHIVE.md` (rule 13). This file holds
only the current state, organisational steps and hints for the next session.

## Next steps — Play Store (user, 2026-09-28)
Done: upload key and signing, privacy policy, store texts and graphics
(`docs/PLAY-LISTING.md`, `docs/DECISIONS.md` "Play Store preparation"); store
raw shots home / Hören and Geben statistics retaken for v1.3.0 (2026-10-01,
dark, DE+EN), graphics rebuilt; AAB `releases/apex-cw-v1.6.0.aab` (store raw shots still from v1.3.0).
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

## Landing page (live, Pages source "GitHub Actions" set)
Open: replace the disabled "Google Play: coming soon" button with the store
link once the app is live, and set the Play listing's website to the Pages URL.

## New logo (2026-10-06, on main): still to do
Done and checked on the test phone: launcher icons, README, landing page. Pending:
- **Play Store** (deliberately postponed until the store launch; no work per beta): rebuild `store/out` with `python3 store/make_graphics.py`
  after changing its palette (`TOP`/`BOTTOM` gradient is still the old blue
  panel; use the new navy `#122241`/teal/orange accents) and re-check
  `feature_{de,en}.png`; upload new `icon_512.png` + feature graphic in the
  Play Console (store listing, app icon). `docs/PLAY-LISTING.md` unchanged.
- **GitHub**: upload `android/tool/icon/social_preview.png` (repo Settings →
  Social preview; no API).
- **Manual** (at release): the built HTML/PDF carry no icon, but check the
  cover/info for the old look; screenshots with the launcher icon, if any.

## Manual: pending for next release
- Rename to "APEX CW" (feature/rename-apex-cw): app bar title on Home and the About dialog show the new name; retake `home*` and any shot with the title bar (DE+EN) at release. Also: store raw shots + graphics (`store/make_graphics.py`) and the Play Console app name/listing. (Site images were retaken 2026-10-08, see archive.)
- Listen start page: slim "On the way to X" card (Koch lesson) below the weak characters; retake `hear_start` (DE+EN).
- Break hint sensitivity (#48, on main): new row in Settings → General; retake `settings1.png` (DE+EN) if the row shows there. Defaults still to be tuned on real sessions (being tried by testers).
- Light theme "navy mist" + blue light filter: every light screenshot changes; Settings → Appearance has three new rows (retake `settings1.png` DE+EN). Start/Stop buttons now carry play/stop icons (Geben, games, Decoder, QSO bot): retake those shots too.
- Practice a character (#44): new Hear/Send sliders above the keyer; retake `char_practice.png` (DE+EN).
- UI font DM Sans (on main): every screenshot
  changes its look (titles/labels no longer monospace); retake all at release.
- Retaken 2026-10-05 (DE+EN): `hear_start`, `hear_result`, `hear_weak`,
  `hear_sheet2`, `echo_start`, `echo_result`, `echo_result2` (the last one
  needs a 100 % block played by hand; the suggestion is not pre-ticked, tick
  it before the shot). Other ⚙ sheet shots may still show the old wraps. Taken
  on a debug build with the phone's prefs backed up and restored afterwards;
  `tools/echo_loop.py` knows "Gruppe n /" and "Geben …", needs Echo Prompt =
  Both (`echoDisplayMode` 3).
- Swap touch paddles (on main): new Keyer setting "Swap on-screen
  paddles"; retake the Keyer settings shot (`settings1.png`, DE+EN) and
  `keyer.png` if wanted (the touch paddles themselves look the same by default).
- Issue #37 (on main): keyer
  text now shows `*`/`ERR`/umlauts; retake `keyer.png` only if it shows a `?`.

- Char detail curves (on main): weekly curve note + current-week line in
  the character detail; tap detail on the curves/bars (also the Verlauf rate
  curve); no Mix-ups item in Listen; heatmap columns fill the width. Retake
  `hear_char_detail.png`, `hear_progress2.png`, `echo_progress.png` (DE+EN).

- Exam simulation (issue #42, merged): new Learn-hub card and exam screens; retake `home.png` (the Learn card subtitle changed), `res_hub.png` (DE+EN) and add shots of the exam setup,
  receive result, send ready/keying/result pages (not taken yet).

## Exam simulation (issue #42, on main incl. English texts)
Receive and send part, six country families and the custom profile done, unit and overflow tests green; checked on the test phone. Next: KA/SK, feed weak characters into the statistics, check the ARRL steps (13 WPM?) and the Indian/UK/NZ details against the official sources. Decisions:
`docs/DECISIONS.md` "Exam simulation".

- Practice time (on main): practice time (this training + total) at the top of Progress, tap
  detail on the days-practised bars; retake `hear_progress.png`,
  `echo_progress.png` (DE+EN).

## Hints for the next session
- README describes the features since v1.6.0 (exam simulation, single-character practice, practice time, swapped paddles; PR #45, 2026-10-07). Its manual links still point to the v1.6.0 PDFs: update them at the next release.
- Release steps: `manual/README.md` "At release time"; `MANUAL_COMMIT=<hash>
  ./build.sh` states the release commit on the title page when only manual
  sources changed after the tag.
- Seeding statistics for screenshots needs a debug build (`run-as`); the
  release build isn't debuggable. Back up and restore the prefs
  (`shared_prefs/FlutterSharedPreferences.xml`) and `files/owntexts/`.
